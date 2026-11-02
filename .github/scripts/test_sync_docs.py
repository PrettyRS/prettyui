import tempfile
import unittest
from pathlib import Path

from sync_docs import sync_docs


class SyncDocsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "library"
        self.site = self.root / "site"
        self.components = self.source / "docs/content/prettyui"
        self.destination = self.site / "content/prettyui"
        self.components.mkdir(parents=True)
        self.destination.mkdir(parents=True)
        (self.components / "01-api.md").write_bytes(b"canonical\r\n\x00")
        (self.source / "docs/content/prettyui-changelog.md").write_bytes(b"release\r\n")
        (self.destination / "index.md").write_bytes(b"site-owned index")
        (self.destination / "01-api.md").write_bytes(b"outdated")
        (self.destination / "art.svg").write_bytes(b"art")
        (self.destination / "nested").mkdir()
        (self.destination / "nested/notes.md").write_bytes(b"unrelated")
        (self.site / "content/prettyui-editor.md").write_bytes(b"editor")

    def snapshot(self):
        return {str(p.relative_to(self.site)): p.read_bytes()
                for p in self.site.rglob("*") if p.is_file()}

    def test_replacement_addition_and_site_owned_preservation(self):
        before = self.snapshot()
        (self.components / "02-new.md").write_bytes(b"new\r\n")
        self.assertTrue(sync_docs(self.source, self.site))
        self.assertEqual((self.destination / "01-api.md").read_bytes(), b"canonical\r\n\x00")
        self.assertEqual((self.destination / "02-new.md").read_bytes(), b"new\r\n")
        self.assertEqual((self.site / "content/prettyui-changelog.md").read_bytes(), b"release\r\n")
        after = self.snapshot()
        for path in ("content/prettyui/index.md", "content/prettyui/art.svg",
                     "content/prettyui/nested/notes.md", "content/prettyui-editor.md"):
            self.assertEqual(after[path], before[path])

    def test_deletion_rename_and_noop(self):
        (self.destination / "03-removed.md").write_bytes(b"obsolete")
        (self.components / "01-api.md").rename(self.components / "04-renamed.md")
        self.assertTrue(sync_docs(self.source, self.site))
        self.assertFalse((self.destination / "01-api.md").exists())
        self.assertFalse((self.destination / "03-removed.md").exists())
        self.assertEqual((self.destination / "04-renamed.md").read_bytes(), b"canonical\r\n\x00")
        before = self.snapshot()
        self.assertFalse(sync_docs(self.source, self.site))
        self.assertEqual(self.snapshot(), before)

    def test_invalid_inputs_fail_before_mutation(self):
        cases = ("missing_directory", "missing_changelog", "empty", "index", "nested",
                 "non_markdown", "symlink", "changelog_symlink", "missing_index",
                 "destination_symlink", "destination_conflict")
        for case in cases:
            with self.subTest(case=case), tempfile.TemporaryDirectory() as tmp:
                import shutil
                source, site = Path(tmp) / "source", Path(tmp) / "site"
                shutil.copytree(self.source, source)
                shutil.copytree(self.site, site)
                components = source / "docs/content/prettyui"
                destination = site / "content/prettyui"
                if case == "missing_directory":
                    shutil.rmtree(components)
                elif case == "missing_changelog":
                    (source / "docs/content/prettyui-changelog.md").unlink()
                elif case == "empty":
                    (components / "01-api.md").unlink()
                elif case == "index":
                    (components / "index.md").write_text("conflict")
                elif case == "nested":
                    (components / "nested").mkdir()
                elif case == "non_markdown":
                    (components / "asset.png").write_bytes(b"invalid")
                elif case == "symlink":
                    (components / "02-link.md").symlink_to(components / "01-api.md")
                elif case == "changelog_symlink":
                    log = source / "docs/content/prettyui-changelog.md"
                    log.unlink()
                    log.symlink_to(components / "01-api.md")
                elif case == "missing_index":
                    (destination / "index.md").unlink()
                elif case == "destination_symlink":
                    (destination / "01-api.md").unlink()
                    (destination / "01-api.md").symlink_to(components / "01-api.md")
                elif case == "destination_conflict":
                    (destination / "01-api.md").unlink()
                    (destination / "01-api.md").mkdir()
                before = {str(p.relative_to(site)): p.read_bytes()
                          for p in site.rglob("*") if p.is_file()}
                source_before = (components / "01-api.md").read_bytes() if (components / "01-api.md").exists() else None
                with self.assertRaises((ValueError, OSError)):
                    sync_docs(source, site)
                after = {str(p.relative_to(site)): p.read_bytes()
                         for p in site.rglob("*") if p.is_file()}
                self.assertEqual(after, before)
                if source_before is not None:
                    self.assertEqual((components / "01-api.md").read_bytes(), source_before)


if __name__ == "__main__":
    unittest.main()
