---
title: "SettingsLayer"
weight: 1
---

{{% doc-section %}}

## SettingsLayer {#settings-layer}

Mount a [SimpleView](#scrolling-api) on `event.component` and add PrettyUI settings controls with its `Add...` methods.

Requires the [PrettyUI dependency](#installation) and `"hasSettingsIcon": true` in your manifest.

```lua
local settingsView
local showHints = PersistentDB:GetBool("showHints") ~= false

Event.SettingsLayerReady.Subscribe("my-plugin-settings", function(event)
    if settingsView then settingsView:Destroy() end

    local parent = event.component
    settingsView = prettyui.SimpleView.new(parent, {
        width = parent.width,
        height = parent.height,
    })

    settingsView:AddTitle("My Plugin settings")
    settingsView:AddText("Changes are saved immediately.")
    settingsView:AddCheckboxButton({
        { text = "Show hints", value = "showHints", selected = showHints },
    }, {
        onChange = function(_, _, _, selected)
            showHints = selected
            PersistentDB:SetBool("showHints", selected)
        end,
    })
end)

function PluginShutdown()
    Event.SettingsLayerReady.Unsubscribe("my-plugin-settings")
    if settingsView then
        settingsView:Destroy()
        settingsView = nil
    end
end
```

Destroy the previous view when remounting, and include its teardown in your existing `PluginShutdown`. When using both examples, combine their cleanup in that one function.

`SimpleView` uses the supplied width and height; call `settingsView:SetSize(width, height)` if the available space changes.

{{% /doc-section %}}
