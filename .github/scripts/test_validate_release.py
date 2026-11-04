import json
import tempfile
import unittest
from pathlib import Path

from validate_release import validate_release


class ValidateReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def source(self, manifest_version, lua_versions):
        (self.root / "plugin.json").write_text(json.dumps({"version": manifest_version}), encoding="utf-8")
        (self.root / "main.lua").write_text(
            "\n".join(f'PrettyUI.version = "{version}"' for version in lua_versions) + "\n",
            encoding="utf-8",
        )

    def test_version_normalization_and_source_preservation(self):
        for suffix in ("1.2.3", "v1.2.3", "1.2.3-rc.1", "v1.2.3+build.4"):
            with self.subTest(suffix=suffix):
                version = suffix.removeprefix("v")
                self.source(version, [version])
                before = {path: path.read_bytes() for path in self.root.iterdir()}
                self.assertEqual(validate_release(f"release/{suffix}", self.root), version)
                self.assertEqual({path: path.read_bytes() for path in self.root.iterdir()}, before)

    def test_ordinary_pr_does_not_require_release_files(self):
        self.assertIsNone(validate_release("feature/new-control", self.root))

    def test_invalid_release_branch(self):
        for suffix in ("", "next", "1.2", "1.2.3/extra", "1.2.3\n", "1.2.3;echo unsafe"):
            with self.subTest(suffix=suffix), self.assertRaisesRegex(ValueError, "Release branch must"):
                validate_release(f"release/{suffix}", self.root)

    def test_both_source_versions_must_match(self):
        for manifest, lua in (("1.2.2", ["1.2.3"]), ("1.2.3", ["1.2.2"]), ("v1.2.3", ["1.2.3"])):
            with self.subTest(manifest=manifest, lua=lua):
                self.source(manifest, lua)
                with self.assertRaises(ValueError):
                    validate_release("release/1.2.3", self.root)

    def test_missing_or_duplicate_lua_assignments_fail(self):
        for lua in ([], ["1.2.3", "1.2.3"], ["1.2.3", "1.2.2"]):
            with self.subTest(lua=lua):
                self.source("1.2.3", lua)
                with self.assertRaisesRegex(ValueError, "exactly one"):
                    validate_release("release/1.2.3", self.root)


if __name__ == "__main__":
    unittest.main()
