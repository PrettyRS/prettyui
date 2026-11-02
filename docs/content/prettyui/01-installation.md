---
title: "Installation"
weight: 1
---

{{% doc-section %}}

## Installation {#installation}

Declare PrettyUI as a required external plugin dependency in `plugin.json`, using its mod.io ID **6398181**. RuneScape loads PrettyUI first and exposes its returned table under the dependency alias `prettyui`.

```json
{
  "name": "My Plugin",
  "version": "1.0.0",
  "requiredDependencies": {
    "prettyui": 6398181
  },
  "optionalDependencies": {}
}
```

{{% /doc-section %}}

{{% doc-section %}}

## Editor integration {#editor-integration}

The LuaLS addon provides autocomplete and type checking in VS Code's Lua extension,
Neovim, and other LuaLS clients.

1. Download `PrettyUI-luals-addon-<tag>.zip` from the
   [GitHub Release](https://github.com/PrettyRS/prettyui/releases) matching your PrettyUI version.
2. Extract it into an addon collection **outside your plugin folder**. The config
   should be at `/path/to/LuaAddons/prettyui-luals-addon/config.json`.
3. Add the collection directory (not the addon itself) to your workspace's
   `.luarc.json`, preserving existing settings:

   ```json
   {
     "workspace.userThirdParty": ["/path/to/LuaAddons"],
     "workspace.checkThirdParty": "Ask"
   }
   ```

4. Replace the example path with your actual directory, reload LuaLS, open code
   using `prettyui.`, and accept the addon prompt.

Alternatively, add the addon's `library/` directory to `workspace.library`.
When upgrading, replace the addon directory and reload LuaLS; load only one version.

{{% /doc-section %}}
