#!/usr/bin/env python3
"""Mirror canonical PrettyUI Markdown into the site without touching site-owned files."""

import argparse
from pathlib import Path


def require_regular(path: Path) -> None:
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"Expected a regular file: {path}")


def sync_docs(source_root: Path, site_root: Path) -> bool:
    source = source_root / "docs/content/prettyui"
    changelog = source_root / "docs/content/prettyui-changelog.md"
    destination = site_root / "content/prettyui"
    # Refuse symlinked parents too: mapped writes must stay inside the site.
    for directory in (source_root / "docs", source.parent, source,
                      site_root / "content", destination):
        if directory.is_symlink() or not directory.is_dir():
            raise ValueError(f"Expected a regular directory: {directory}")
    require_regular(changelog)
    require_regular(destination / "index.md")

    components = sorted(source.iterdir())
    if not components:
        raise ValueError(f"No component Markdown in {source}")
    for path in components:
        require_regular(path)
        if path.suffix != ".md" or path.name == "index.md":
            raise ValueError(f"Invalid canonical component: {path}")

    # Read and validate the complete mapping before any copy or deletion.
    mapped = {destination / path.name: path.read_bytes() for path in components}
    mapped[site_root / "content/prettyui-changelog.md"] = changelog.read_bytes()
    existing = []
    for path in destination.iterdir():
        if path.name != "index.md" and path.suffix == ".md":
            if path.is_dir() and not path.is_symlink():
                if path in mapped:
                    raise ValueError(f"Destination conflicts with component: {path}")
                continue
            require_regular(path)
            existing.append(path)
    updates = []
    for path, content in mapped.items():
        if path.exists() or path.is_symlink():
            require_regular(path)
            if path.read_bytes() == content:
                continue
        updates.append((path, content))
    deletions = [path for path in existing if path not in mapped]

    for path, content in updates:
        path.write_bytes(content)
    for path in deletions:
        path.unlink()
    return bool(updates or deletions)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_root", type=Path)
    parser.add_argument("site_root", type=Path)
    args = parser.parse_args()
    changed = sync_docs(args.source_root, args.site_root)
    print("Updated documentation mirror" if changed else "Documentation mirror already matches")


if __name__ == "__main__":
    main()
