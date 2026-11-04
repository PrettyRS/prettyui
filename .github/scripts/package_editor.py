#!/usr/bin/env python3
"""Build the PrettyUI LuaLS addon for a release tag."""

import argparse
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory
from zipfile import ZIP_DEFLATED, ZipFile

from package_release import ROOT, TAG_VERSION


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag", help="Release tag (1.2.3 or v1.2.3)")
    parser.add_argument("--output", type=Path, required=True, help="Directory for developer release assets")
    args = parser.parse_args()
    match = TAG_VERSION.fullmatch(args.tag)
    if not match:
        parser.error("release tag must be a version such as 1.2.3 or v1.2.3")

    with TemporaryDirectory(prefix="prettyui-editor-") as directory:
        generated = Path(directory)
        subprocess.run(
            [sys.executable, str(ROOT / ".github/scripts/generate_definitions.py"),
             "--output", str(generated), "--version", match.group(1)],
            check=True,
        )
        args.output.mkdir(parents=True, exist_ok=True)
        definitions = generated / "prettyui-definitions.lua"
        addon_prefix = "prettyui-luals-addon"
        with ZipFile(args.output / f"PrettyUI-luals-addon-{args.tag}.zip", "w", ZIP_DEFLATED) as archive:
            archive.write(definitions, f"{addon_prefix}/library/prettyui-definitions.lua")
            archive.write(ROOT / "editor/addon/config.json", f"{addon_prefix}/config.json")
            archive.write(ROOT / "README.md", f"{addon_prefix}/README.md")
            archive.write(ROOT / "LICENSE", f"{addon_prefix}/LICENSE")


if __name__ == "__main__":
    main()
