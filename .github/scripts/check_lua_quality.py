#!/usr/bin/env python3
"""Check formatting, lint, nesting, and complexity for Lua files changed since the PR merge base."""

import argparse
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
MAX_NESTING = 3
MAX_COMPLEXITY = 25
NESTING_STATEMENTS = {"if_statement", "for_statement", "while_statement", "repeat_statement"}
DECISION_STATEMENTS = NESTING_STATEMENTS | {"elseif_statement"}
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


def unparenthesized(node):
    while node.type == "parenthesized_expression":
        node = next(child for child in node.named_children if not child.is_extra)
    return node


def logical_operator(node):
    if node.type == "binary_expression":
        operator = node.child_by_field_name("operator").type
        if operator in {"and", "or"}:
            return operator
    return None


def ternary_cost(values) -> int:
    """Discount only the and/or pair of each direct assignment value `a and b or c`."""
    pairs = 0
    for value in values.children_by_field_name("value"):
        value = unparenthesized(value)
        if logical_operator(value) != "or":
            continue
        condition_and_value = unparenthesized(value.child_by_field_name("left"))
        if logical_operator(condition_and_value) == "and":
            pairs += 1
    return 2 * pairs


def check_file_structure(path: str, root) -> bool:
    failed = False
    scopes = [root]
    while scopes:
        scope = scopes.pop()
        complexity = 1
        pending = [(child, 0, True) for child in reversed(scope.named_children)]
        while pending:
            node, depth, count_operators = pending.pop()
            kind = node.type
            if kind in FUNCTION_NODES:
                scopes.append(node)
                continue
            if kind in NESTING_STATEMENTS:
                depth += 1
                if depth == MAX_NESTING + 1:
                    line, column = node.start_point
                    print(
                        f"{path}:{line + 1}:{column + 1}: Lua control-flow nesting exceeds {MAX_NESTING} levels",
                        file=sys.stderr,
                    )
                    failed = True
            if kind in DECISION_STATEMENTS or (count_operators and logical_operator(node)):
                complexity += 1
            if kind == "assignment_statement":
                values = next(child for child in node.named_children if child.type == "expression_list")
                complexity -= ternary_cost(values)
            # Like Luacheck, don't count operators in assignment targets.
            count_operators = count_operators and kind != "variable_list"
            pending.extend((child, depth, count_operators) for child in reversed(node.named_children))

        if complexity > MAX_COMPLEXITY:
            if scope == root:
                line, column = 0, 0
                subject = "main chunk"
            else:
                line, column = scope.start_point
                name = scope.child_by_field_name("name")
                subject = f"function {name.text.decode('utf-8', 'replace')!r}" if name else "function"
            print(
                f"{path}:{line + 1}:{column + 1}: cyclomatic complexity of {subject} "
                f"is too high ({complexity} > {MAX_COMPLEXITY})",
                file=sys.stderr,
            )
            failed = True
    return failed


def check_structure(files: list[str]) -> bool:
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
            print(f"{path}: could not parse Lua for the nesting and complexity checks", file=sys.stderr)
            failed = True
            continue

        failed |= check_file_structure(path, root)
    return failed


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        epilog=f"The complexity limit is {MAX_COMPLEXITY} per chunk or function. "
        "Direct assignment values of the form `a and b or c` don't count toward it, but other logical operators do.",
    )
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
        ["stylua", "--config-path", "stylua.toml", "--check", "--verify", "--color", "Never"],
        ["luacheck", "--config", ".luacheckrc", "--codes", "--no-color"],
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
    failed |= check_structure(files)
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
