#!/usr/bin/env python3
"""Check release/<version> branches against both source versions without editing files."""

import argparse
import json
from pathlib import Path

from package_release import ROOT, TAG_VERSION, VERSION_LINE


def validate_release(branch: str, root: Path) -> str | None:
    if not branch.startswith("release/"):
        return None
    match = TAG_VERSION.fullmatch(branch.removeprefix("release/"))
    if not match:
        raise ValueError("Release branch must be release/1.2.3 or release/v1.2.3 (optional prerelease/build suffix)")
    version = match.group(1)
    manifest_version = json.loads((root / "plugin.json").read_text(encoding="utf-8"))["version"]
    lua_versions = VERSION_LINE.findall((root / "main.lua").read_text(encoding="utf-8"))
    if manifest_version != version:
        raise ValueError(f"plugin.json version must be {version!r}, found {manifest_version!r}")
    if lua_versions != [version]:
        raise ValueError(f"main.lua must contain exactly one PrettyUI.version = \"{version}\" assignment; found {lua_versions!r}")
    return version


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("branch", help="Pull request head branch")
    args = parser.parse_args()
    try:
        tag = validate_release(args.branch, ROOT)
    except (ValueError, KeyError, OSError) as error:
        parser.error(str(error))
    if tag:
        print(tag)


if __name__ == "__main__":
    main()
