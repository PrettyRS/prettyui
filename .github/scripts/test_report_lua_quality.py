import unittest

from report_lua_quality import failure_details

SOURCE = "https://github.com/contributor/prettyui/blob/" + "a" * 40


class LuaQualityFeedbackTests(unittest.TestCase):
    def test_formatting_links_use_original_lines(self):
        log = """Diff in src/with space.lua:
1   1    | local a = 1
2        |-local b=2
    2    |+local b = 2
--------------------------------------------------------------------------------
18  18   | local c = 3
    19   |+
19  20   | return a + b + c
Diff in tests/other.lua:
5        |-return 0
    5    |+return 0
"""
        details = failure_details(log, SOURCE)
        self.assertIn(f"]({SOURCE}/src/with%20space.lua#L2) — Run StyLua", details)
        self.assertIn(f"]({SOURCE}/src/with%20space.lua#L18)", details)
        self.assertIn(f"]({SOURCE}/tests/other.lua#L5)", details)
        self.assertEqual(details.count("Run StyLua"), 3)
        self.assertNotIn("local b", details)

    def test_diagnostics_keep_issue_text_and_link_to_source(self):
        log = """    src/widget.lua:14:6: (W113) accessing undefined variable 'widgte'
main.lua:22:5: Lua control-flow nesting exceeds 3 levels
    tests/broken.lua:12: (E011) expected expression
"""
        details = failure_details(log, SOURCE)
        self.assertIn(f"]({SOURCE}/src/widget.lua#L14) — ` (W113) accessing undefined variable 'widgte' `", details)
        self.assertIn(f"]({SOURCE}/main.lua#L22) — ` Lua control-flow nesting exceeds 3 levels `", details)
        self.assertIn(f"]({SOURCE}/tests/broken.lua#L12) — ` (E011) expected expression `", details)

    def test_diagnostics_treat_contributor_text_as_data(self):
        log = "src/odd [x]`#.lua:4: (W113) ``` @team <img> [fake](https://invalid.example)\n"
        details = failure_details(log, SOURCE)
        self.assertIn(f"[{chr(96) * 2} src/odd [x]`#.lua:4 {chr(96) * 2}]({SOURCE}/src/odd%20%5Bx%5D%60%23.lua#L4)", details)
        self.assertIn("— ```` (W113) ``` @team <img> [fake](https://invalid.example) ````", details)
        self.assertNotIn("](https://github.com", failure_details("src/../other.lua:1: (W113) example", SOURCE))
