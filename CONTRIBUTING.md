# Contributing to PrettyUI

## Lua style

- Use four spaces, LF line endings, and double quotes unless single quotes avoid escaping. Let StyLua wrap code around the 120-column target.
- Use `local` by default. Follow existing module and public method names, preserve the client API's `.` versus `:` call syntax, and keep `require` calls in evaluation order.
- Comment on why an invariant, client constraint, callback contract, or cleanup order matters. Don't narrate the next line. Document non-obvious arguments, returns, and side effects on public APIs. Use LuaLS annotations where they clarify the contract, and update them when it changes.
- In review, check that comments still describe the code and that behavioral changes have focused regression coverage. If a real client global needs a lint allowance, use the narrowest scope that works; don't disable global checking.

## Before opening a PR

Install Python 3, [StyLua 2.6.0](https://github.com/JohnnyMorganz/StyLua/releases/tag/v2.6.0) with Lua 5.4 support, and [Luacheck 1.2.0](https://github.com/lunarmodules/luacheck/releases/tag/v1.2.0), all on `PATH`. If there's no Luacheck release binary for your platform, use `luarocks --local install luacheck 1.2.0-1` and add the LuaRocks bin directory to `PATH`.

From the repository root, update your target branch ref and pass it to the same checker used by CI. This example targets `main`; substitute the actual PR target for a release or another branch:

```sh
git fetch origin
python3 .github/scripts/check_lua_quality.py --base origin/main
```

`Lua quality` checks new and modified `main.lua`, `src/**/*.lua`, and `tests/**/*.lua` files in full. It includes local staged, unstaged, and non-ignored untracked changes. Untouched files, generated editor files, and Lua examples in Markdown are outside this rollout. Format only the Lua files you changed (replace the example path with yours):

```sh
stylua --config-path stylua.toml --verify -- src/spinner.lua
```

For a behavior change, run the relevant regression script with Lua 5.4, for example `lua5.4 tests/resize_test.lua` for changes to resize behavior. CI's separate `Tests` job still runs the full Lua regression suite and the Python tooling tests.
