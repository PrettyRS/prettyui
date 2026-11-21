"""Post Lua quality results from a trusted workflow_run, never from a PR checkout."""

import io
import json
import os
from pathlib import Path
import re
import subprocess
from urllib.parse import quote, urlencode
from zipfile import BadZipFile, ZipFile

MARKER = re.compile(r"\A<!-- prettyui-lua-quality (\d+)\.(\d+) -->\n")
MAX_REPORT_BYTES = 1024 * 1024
LUA_PATH = r"(?:main\.lua|(?:src|tests)/.+\.lua)"
FORMAT_FILE = re.compile(rf"Diff in ({LUA_PATH}):")
FORMAT_ROW = re.compile(r"^(?:(?P<old>[0-9]{1,9})[ \t]+|[ \t]+)(?:[0-9]+[ \t]+)?\|(?P<change>[-+]?)")
FILE_FINDING = re.compile(rf"({LUA_PATH}):([0-9]{{1,9}})(?::[0-9]{{1,9}})?:[ \t]*(.+)")


def gh_api(endpoint, *, method="GET", body=None, paginate=False):
    command = ["gh", "api", "--method", method, endpoint]
    if paginate:
        command.extend(["--paginate", "--slurp"])
    if body is not None:
        command.extend(["--input", "-"])
    return subprocess.run(
        command,
        input=json.dumps(body).encode() if body is not None else None,
        stdout=subprocess.PIPE,
        check=True,
    ).stdout


def pages(endpoint, key=None):
    for page in json.loads(gh_api(endpoint, paginate=True)):
        yield from page if key is None else page[key]


def pull_number(run, repo_id, pulls):
    associated = {pull["number"]: pull["base"]["ref"] for pull in run["pull_requests"]}
    head_repo = run["head_repository"]["id"]
    candidates = [
        pull["number"]
        for pull in pulls
        if pull["state"] == "open"
        and pull["created_at"] <= run["created_at"]
        and pull["base"]["repo"]["id"] == repo_id
        and (pull["head"]["repo"] or {}).get("id") == head_repo
        and pull["head"]["ref"] == run["head_branch"]
        and pull["head"]["sha"] == run["head_sha"]
        and (not associated or associated.get(pull["number"]) == pull["base"]["ref"])
    ]
    # Fork workflow_run payloads may omit the pull request. Don't guess if a head matches several PRs.
    return candidates[0] if len(candidates) == 1 else None


def failure_log(repo, run):
    artifacts = list(pages(f"{repo}/actions/runs/{run['id']}/artifacts?per_page=100", "artifacts"))
    expected_name = f"lua-quality-failure-{run['run_attempt']}"
    for artifact in artifacts:
        if artifact["name"] != expected_name or artifact["expired"] or artifact["size_in_bytes"] > MAX_REPORT_BYTES:
            continue
        # This ZIP came from the read-only PR job. Read one bounded member; never extract it.
        try:
            archive = gh_api(f"{repo}/actions/artifacts/{artifact['id']}/zip")
            with ZipFile(io.BytesIO(archive)) as report:
                member = report.getinfo("lua-quality.log")
                if member.file_size <= MAX_REPORT_BYTES:
                    return report.read(member).decode("utf-8", errors="replace")
        except (BadZipFile, KeyError, OSError, RuntimeError, subprocess.CalledProcessError):
            break
    return ""


def inline_code(text):
    text = "".join(c if c.isprintable() else "?" for c in text)
    fence = "`" * (1 + max((len(run) for run in re.findall(r"`+", text)), default=0))
    return f"{fence} {text} {fence}"


def source_location(source, path, number):
    label = inline_code(f"{path[:250]}:{number}")
    if len(path.encode("utf-8")) > 400 or any(part in {"", ".", ".."} for part in path.split("/")):
        return label
    return f"[{label}]({source}/{quote(path)}#L{number})"


def failure_details(log, source):
    formatting, diagnostics, errors = [], [], []
    path, old_line, changing = None, 1, False
    for raw in log.splitlines():
        if header := FORMAT_FILE.fullmatch(raw):
            path, old_line, changing = header[1], 1, False
            continue
        if path and (row := FORMAT_ROW.match(raw)):
            if row["old"]:
                old_line = int(row["old"])
            if row["change"] and not changing:
                location = source_location(source, path, old_line)
                formatting.append(f"- {location} — Run StyLua to fix formatting.")
            changing = bool(row["change"])
            continue
        # Separate StyLua hunks and subsequent tool output.
        changing = False
        if not raw.startswith("-"):
            path = None

        line = raw.strip()
        if finding := FILE_FINDING.fullmatch(line):
            location = source_location(source, finding[1], int(finding[2]))
            diagnostics.append(f"- {location} — {inline_code(finding[3][:300])}")
        elif line.startswith(("error:", "fatal:", "Cannot run ", "Install the Lua parser:")):
            errors.append(f"- {inline_code(line[:300])}")

    sections = []
    for title, lines, limit in (
        ("Formatting (StyLua)", formatting, 12),
        ("Lint, nesting, and complexity", diagnostics, 20),
        ("Other errors", errors, 6),
    ):
        if lines:
            if len(lines) > limit:
                lines = [*lines[:limit], f"- … {len(lines) - limit} more; see the full report."]
            sections.append(f"**{title}**\n\n" + "\n".join(lines))
    return "\n\n".join(sections)


def report(repo, repo_id, server, run):
    if run["event"] != "pull_request" or run["path"].split("@", 1)[0] != ".github/workflows/tests.yml":
        return
    if not run["head_repository"]:
        return
    jobs = pages(f"{repo}/actions/runs/{run['id']}/attempts/{run['run_attempt']}/jobs?per_page=100", "jobs")
    quality = [job for job in jobs if job["name"] == "Lua quality"]
    if len(quality) != 1 or quality[0]["conclusion"] not in {"failure", "success", "timed_out"}:
        return
    job = quality[0]

    owner = run["head_repository"]["owner"]["login"]
    query = urlencode({"state": "open", "head": f"{owner}:{run['head_branch']}", "per_page": 100})
    number = pull_number(run, repo_id, pages(f"{repo}/pulls?{query}"))
    if number is None:
        print("No unique open pull request matches the quality check's head.")
        return

    comments = f"{repo}/issues/{number}/comments"
    revision = (run["run_number"], run["run_attempt"])
    previous = []
    for comment in pages(f"{comments}?per_page=100"):
        match = MARKER.match(comment.get("body") or "")
        if match and comment["user"]["login"] == "github-actions[bot]" and comment["user"]["type"] == "Bot":
            previous.append((tuple(map(int, match.groups())), comment["id"]))
    latest, comment_id = max(previous, default=((0, 0), None))
    passed = job["conclusion"] == "success"
    if latest >= revision or (passed and comment_id is None):
        return

    status = "passed" if passed else "failed"
    link = f"{server}/{repo.removeprefix('repos/')}/actions/runs/{run['id']}/job/{job['id']}"
    body = f"<!-- prettyui-lua-quality {revision[0]}.{revision[1]} -->\n"
    body += f"### Lua quality {status}\n\nCommit `{run['head_sha'][:12]}` · [Full report (job log)]({link})"
    if not passed:
        head_repo = quote(run["head_repository"]["full_name"])
        source = f"{server}/{head_repo}/blob/{run['head_sha']}"
        details = failure_details(failure_log(repo, run), source)
        body += "\n\n" + (details or "No file diagnostics were recorded. See the job log for the failure.")

    # The head can change while this job is gathering logs. Recheck before writing.
    current = json.loads(gh_api(f"{repo}/pulls/{number}"))
    if pull_number(run, repo_id, [current]) != number:
        return
    if comment_id is None:
        gh_api(comments, method="POST", body={"body": body})
    else:
        gh_api(f"{repo}/issues/comments/{comment_id}", method="PATCH", body={"body": body})


if __name__ == "__main__":
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text(encoding="utf-8"))
    report(f"repos/{os.environ['GITHUB_REPOSITORY']}", event["repository"]["id"], os.environ["GITHUB_SERVER_URL"], event["workflow_run"])
