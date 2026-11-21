# PrettyUI

PrettyUI is a UI library that helps craft native-looking interfaces for your plugins. The aim is to offer something that delivers a uniform look and makes UI as simple as constructing a web page.

## Useful resources
- [Mod.io page](https://mod.io/g/runescape/m/prettyui)
- [Documentation](https://prettyui.j3.gg/)
- [Visual Editor](https://prettyui.j3.gg/editor.html)


## Contributing to PrettyUI

We welcome community contributions to PrettyUI! A good way to get started is by picking an [open issue on our GitHub repository](https://github.com/PrettyRS/prettyui/issues).

When contributing, please follow our contribution guidelines as outlined below.

### How to Contribute

1. Fork the repository.
2. Create a new branch for your feature or bugfix.
3. Make your changes and commit them with clear messages.
4. Push your changes to your forked repository.
5. Submit a pull request describing your changes and why they should be merged.

When submitting a contribution we also expect you to document the changes in the relevant markdown file under `docs/content`. And for the changelog under `docs/changelog.md` to be updated accordingly.

### LLM usage policy

When contributing to PrettyUI we permit the use of AI tools to assist in writing code. However, all contributions must be reviewed and approved by a human maintainer to ensure quality and adherence to project standards.

**DO NOT**
- Let LLMs generate your documentation for you
- Submit Pull Requests generated solely by LLMs without human review
- Have an LLM generate your Pull Request body.

### Lua style and checks

- Use four spaces, LF, and double quotes unless single quotes avoid escaping. Let StyLua wrap at 120 columns.
- Keep helpers and state `local`. Use `lowerCamelCase` for helpers and `UPPER_SNAKE_CASE` for constants. Preserve public signatures and `require` order.
- Comments explain why. Document non-obvious defaults, units, callback arguments, and cleanup responsibilities.
- We permit up to three levels of lua control-flow nesting. If an operation requires deeper nesting, consider refactoring into helper functions.
- Fix lint warnings rather than suppressing them. Release owned components and subscriptions on teardown. Run the relevant Lua 5.4 regression test for behavior changes.

Install Python 3, [StyLua 2.6.0](https://github.com/JohnnyMorganz/StyLua/releases/tag/v2.6.0) with Lua 5.4 support, and [Luacheck 1.2.0](https://github.com/lunarmodules/luacheck/releases/tag/v1.2.0). From the repo root, run CI’s check against your PR’s target branch:

```sh
git fetch origin
python3 .github/scripts/check_lua_quality.py --base origin/main
```

The check covers new and changed Lua files in full. To fix formatting, run `stylua --config-path stylua.toml --verify -- path/to/changed.lua`.
