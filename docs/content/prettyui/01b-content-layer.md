---
title: "ContentLayer"
weight: 1
---

{{% doc-section %}}

## ContentLayer {#content-layer}

Use [SimpleView](#scrolling-api) to add PrettyUI flow layout and scrolling to `event.component`, without a separate window frame.

Requires the [PrettyUI dependency](#installation) and `"hasRibbonIcon": true` in your manifest.

```lua
local contentView
local clicks = 0

Event.ContentLayerReady.Subscribe("my-plugin-content", function(event)
    if contentView then contentView:Destroy() end

    local parent = event.component
    contentView = prettyui.SimpleView.new(parent, {
        width = parent.width,
        height = parent.height,
    })

    contentView:AddTitle("My Plugin")
    contentView:AddText("This content is mounted inside the client's Plugins window.")
    local countLabel = contentView:AddText("Clicks: " .. tostring(clicks))
    contentView:AddSimpleButton("Count a click", function()
        clicks = clicks + 1
        countLabel.content = "Clicks: " .. tostring(clicks)
    end)
end)

function PluginShutdown()
    Event.ContentLayerReady.Unsubscribe("my-plugin-content")
    if contentView then
        contentView:Destroy()
        contentView = nil
    end
end
```

`AddText` returns a `ui.Text`; update its `content` property to change the label.

Destroy the previous view when remounting, and merge its teardown into your existing `PluginShutdown`. Destroy the view, not its parent.

Scrolling is automatic when content overflows. Call `contentView:SetSize(width, height)` if the available space changes.

{{% /doc-section %}}
