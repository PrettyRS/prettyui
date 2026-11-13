---
title: "Mouseover tooltips"
weight: 21
---

{{% doc-section %}}

## Mouseover tooltips {#tooltip-api}

Tooltip-enabled PrettyUI controllers accept a string or options table through their `tooltip` option and expose `SetTooltip(value)` for later changes. Tooltips are built on demand and cleaned up when hidden.

```lua
local button = prettyui.SpriteButton.new(
    window.content,
    "SETTINGS",
    openSettings,
    { tooltip = "Open settings" }
)

button:SetTooltip("Settings are unavailable")
button:SetTooltip({ text = "Try again later", maxWidth = 180 })
button:SetTooltip(nil)

local attachment = prettyui.Tooltip.attach(
    anotherComponent,
    itsParent,
    { text = "More information", maxWidth = 180 }
)

attachment:SetText("Updated information")
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### Automatic

`tooltip = "text"`
: Measures the content, chooses a side with enough room, and stays within its overlay parent.

`tooltip = options`
: Customizes text, maximum width, dimensions, position, or overlay parent.

Overlay
: Inherits the owning window's top-level coordinate space, so tooltips render above windows without scroll viewport clipping.

`SetTooltip(value)`
: Adds, updates, or removes a controller's tooltip.
{{% /api-card %}}

{{% api-card %}}

### Attachment

`Show()`
: Builds (when needed), positions, raises, and displays the tooltip.

`Hide()`
: Hides the tooltip and frees its components.

`SetText(text)`
: Updates, remeasures, and repositions the attachment in place. Returns false after destruction.

`Destroy()`
: Removes hooks and destroys its component tree.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
