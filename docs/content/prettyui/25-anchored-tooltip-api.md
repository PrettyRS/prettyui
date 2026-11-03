---
title: "Anchored tooltips"
weight: 25
---

{{% doc-section %}}

## Anchored tooltips {#anchored-tooltip-api}

An examine-style tooltip that follows an NPC, world location, projected position, or custom screen-space anchor.

```lua
local npcTooltip = prettyui.AnchoredTooltip.forNPC(npc, {
    text = "An NPC tooltip",
})

npcTooltip:SetText("Updated NPC tooltip")

local locTooltip = prettyui.AnchoredTooltip.forLoc(coordGrid, {
    text = "A location tooltip",
    heightAboveGround = 512,
})

local richTooltip = prettyui.AnchoredTooltip.forNPC(npc, {
    width = 240,
    height = 64,
    buildContent = function(tooltip, content)
        local icon = ui.Sprite.new(content)
        icon:SetSize(21, 21)
        icon.spriteID = id.Sprite.RS3_ICON_INFO_21PX_2

        local timer = ui.Text.new(content)
        timer:SetPos(29, 0)
        timer:SetSize(-29, 28, 1.0)
        timer.content = "00:30"
        timer.rgba = 0xF1C384FF
        return { icon = icon, timer = timer }
    end,
})

richTooltip.contentResult.timer.content = "00:29"
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### Anchors

`forNPC(npc, options)`
: Tracks a live **NPCEntity** and destroys itself when that entity becomes
  invalid.

`forLoc(loc, options)`
: Tracks a **CoordGrid** or **CoordFine**.

`show(options)`
: Accepts **npc**, **loc**, a world **position** (**Vector3**), or an **anchor**
  callback returning a screen **Vector2**.

`new(parent, options)`
: Uses an explicit overlay parent.

{{% /api-card %}}

{{% api-card %}}

### Content and lifecycle

`text`
: Simple text content.

`buildContent(tooltip, content)`
: Builds custom content; its return value is available as **contentResult**.

`content`
: Exposed layer for adding or updating components.

`width`, `height`, `contentWidth`, `contentHeight`
: Configure total or inner dimensions.

`padding`, `paddingX`, `paddingY`
: Configure the content inset.

`heightAboveGround`, `offsetX`, `offsetY`
: Control world and screen-space offsets.

`backgroundColour`, `backgroundAlpha`
: Configure the background.

`SetText(text)`
: Updates the tooltip text and resizes it if necessary.

`Update()`, `Show()`, `Hide()`, `Destroy()`
: Refresh, control, or remove the tooltip.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
