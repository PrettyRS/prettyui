#!/usr/bin/env python3
"""Check formatting, lint, and nesting for Lua files changed since the PR merge base."""

import argparse
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
MAX_NESTING = 3
NESTING_STATEMENTS = {"if_statement", "for_statement", "while_statement", "repeat_statement"}
FUNCTION_NODES = {"function_declaration", "function_definition"}


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


def check_nesting(files: list[str]) -> bool:
    """Report whether any Lua chunk or function exceeds the control-flow limit."""
    try:
        from tree_sitter import Language, Parser
        import tree_sitter_lua
    except ImportError:
        print(
            "Install the Lua parser: python3 -m pip install -r .github/scripts/lua-quality-requirements.txt",
            file=sys.stderr,
        )
        return True

    parser = Parser(Language(tree_sitter_lua.language()))
    failed = False
    for path in files:
        root = parser.parse((ROOT / path).read_bytes()).root_node
        if root.has_error:
            print(f"{path}: could not parse Lua for the nesting check", file=sys.stderr)
            failed = True
            continue

        pending = [(root, 0)]
        while pending:
            node, depth = pending.pop()
            if node.type in FUNCTION_NODES:
                depth = 0
            elif node.type in NESTING_STATEMENTS:
                depth += 1
                if depth == MAX_NESTING + 1:
                    line, column = node.start_point
                    print(
                        f"{path}:{line + 1}:{column + 1}: Lua control-flow nesting exceeds {MAX_NESTING} levels",
                        file=sys.stderr,
                    )
                    failed = True
            pending.extend((child, depth) for child in reversed(node.named_children))
    return failed


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
            print(
                f"Cannot run {command[0]} ({error}). Check that it is executable on PATH; "
                "see .github/workflows/tests.yml for the pinned version.",
                file=sys.stderr,
            )
            failed = True
        else:
            failed |= result.returncode != 0
    failed |= check_nesting(files)
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
