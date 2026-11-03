---
title: "Row backgrounds"
weight: 28
---

{{% doc-section %}}

## Row backgrounds {#row-backgrounds}

Row backgrounds mimic the alternating colours used by native settings panels.
They are available on windows, panels, and tab pages.

```lua
local window = prettyui.Window.new(parent, {
    width = 420,
    height = 300,
    rowBackgroundColours = {
        0x24211EFF,
        0x2E2825FF,
    },
})

local group = "display"
window:AddTitle({
    text = "Display",
    rowBackgroundGroup = group,
})
window:AddText({
    text = "Configure the interface below.",
    rowBackgroundGroup = group,
})
window:AddCheckboxButton({
    { text = "Show labels", value = "labels" },
}, {
    rowBackgroundGroup = group,
})

window:AddTitle("Notifications")
window:RefreshRowBackgrounds()
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### Configuration

`rowBackgroundColours`, `rowBackgroundColors`
: Colours applied in order and repeated as needed. Each flow row receives one
  background by default. Inline components on the same row share it.

`rowBackgroundGroup`
: Consecutive rows with the same value share one background. The colour sequence
  advances once for the group. Reusing the value after another group starts a
  new background.

`rowBackground`
: Set to false on a managed component to leave its flow row unpainted. An
  excluded row also separates matching **rowBackgroundGroup** regions, so a
  group never paints across excluded content. If included and excluded
  components share one inline row, the row remains painted.

`rowBackgroundEdgeToEdge`
: Extends backgrounds through layout padding and gaps to the content edges.
  Defaults to false.

Absolute children
: Components using **absolute = true** or an explicit **y** are ignored.

{{% /api-card %}}

{{% api-card %}}

### Hosts and refresh

`Window.new(parent, options)`
: Accepts the row-background configuration options.

`Panel.new(parent, options)`
: Accepts the options and applies backgrounds to docked and pop-out content.

`Tabs.new(parent, tabs, options)`
: Applies the options to every page. A tab entry may override them for its page.

`RefreshRowBackgrounds()`
: Rebuilds backgrounds after adding, removing, moving, or resizing rows. Adding
  a slider refreshes configured backgrounds automatically; call this after
  other layout changes. Call it on the window, panel, or tab page that owns the
  rows.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
