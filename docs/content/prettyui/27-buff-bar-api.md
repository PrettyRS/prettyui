---
title: "Buff and debuff bars"
weight: 27
---

{{% doc-section %}}

## Buff and debuff bars {#buff-bar-api}

Add custom buffs and debuffs to the native buffbars.

```lua
local buff = prettyui.BuffBar.addBuff({
    objId = config.Obj.COINS_10000,
    label = "187k",
    borderRgba = 0xFFD700FF,
    backgroundRgba = 0x2B2100CC,
    tooltip = "Stored coins",
})

local debuff = prettyui.BuffBar.addDebuff({
    objId = config.Obj.BRONZE_ARROW,
    duration = 45,
    tooltip = "Temporary debuff",
})

buff:SetLabel("188k")
buff:SetTooltip("Stored coins: 188k")
buff:SetObject(config.Obj.PLATINUM_BAR)
buff:SetSprite(id.Sprite.RS3_ICON_INFO_21PX_2)
prettyui.BuffBar.removeBuff(buff)
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### API

{{< signature compact="true" >}}
BuffBar.addBuff(options)
BuffBar.addDebuff(options)
BuffBar.removeBuff(handle)
BuffBar.removeDebuff(handle)
{{< /signature >}}

`addBuff(options)`, `addDebuff(options)`
: Return a handle, or nil for an invalid duration or unavailable native bar.

`removeBuff(handle)`, `removeDebuff(handle)`
: Destroy an entry. Return false for expired, removed, or wrong-bar handles.

{{% /api-card %}}

{{% api-card %}}

### Options

`objId`, `spriteID`
: Object inventory artwork or a static sprite. **objId** takes precedence.

`label`, `labelRgba`, `font`
: Untimed label and styling. Defaults are empty, white, and
  **id.Font.NOTOSANS_BOLD_12**.

`backgroundRgba`
: Inset background colour. Defaults to transparent.

`borderRgba`
: Buff border colour. Only buffs can have custom border colours, debuffs use the default red.

`tooltip`, `visible`
: Standard tooltip value and initial visibility. Visibility defaults to true.
  Buff and debuff tooltips appear after after a brief delay to match the native buff behavior.

`duration`
: Positive lifetime in seconds.

{{% /api-card %}}

{{% api-card %}}

### Handle

`SetLabel(text, rgba?)`
: Updates an untimed label. Returns false for timed or removed entries.

`SetObject(objId)`
: Switches to object inventory item sprite. Accepts an object ID, an Obj config, or nil to clear the icon.

`SetSprite(spriteID)`
: Switches to a raw sprite ID. Pass nil to clear the icon.

`SetTooltip(value)`
: Adds, replaces, or removes the entry tooltip. Pass nil to remove it. Returns false after removal.

`SetVisible(visible)`
: Shows or hides the entry and updates layout. Returns false after removal; timers continue while hidden.

Lifecycle
: Remove untimed entries with the matching method. PrettyUI clears remaining entries on shutdown.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
