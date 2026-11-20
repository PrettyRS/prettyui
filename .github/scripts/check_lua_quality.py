#!/usr/bin/env python3
"""Check formatting and lint for Lua files changed since the PR merge base."""

import argparse
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def git(*args: str) -> bytes:
    return subprocess.check_output(["git", *args], cwd=ROOT)


def changed_lua_files(base: str) -> list[str]:
    base_commit = git("rev-parse", "--verify", "--end-of-options", f"{base}^{{commit}}").decode().strip()
    merge_base = git("merge-base", base_commit, "HEAD").decode().strip()
    scope = ("--", "main.lua", "src/", "tests/")
    # With rename detection off, the destination is an addition and the removed path is excluded.
    changed = git("diff", "--name-only", "-z", "--no-renames", "--diff-filter=AMT", merge_base, *scope)
    untracked = git("ls-files", "-z", "--others", "--exclude-standard", *scope)
    paths = {os.fsdecode(name) for name in (changed + untracked).split(b"\0")}
    return sorted(
        path
        for path in paths
        if (path == "main.lua" or path.startswith(("src/", "tests/")))
        and path.endswith(".lua")
        and (ROOT / path).is_file()
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True, help="target branch ref or commit SHA")
    args = parser.parse_args()
    try:
        files = changed_lua_files(args.base)
    except (OSError, subprocess.CalledProcessError) as error:
        parser.error(f"cannot determine changed Lua files against {args.base!r}: {error}")
    if not files:
        print("No changed Lua files in main.lua, src/, or tests/.")
        return 0

    failed = False
    for command in (
        ["stylua", "--config-path", "stylua.toml", "--check", "--verify"],
        ["luacheck", "--config", ".luacheckrc", "--codes"],
    ):
        try:
            result = subprocess.run([*command, "--", *files], cwd=ROOT, check=False)
        except OSError as error:
            print(f"Cannot run {command[0]} ({error}). See CONTRIBUTING.md for setup.", file=sys.stderr)
            failed = True
        else:
            failed |= result.returncode != 0
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
