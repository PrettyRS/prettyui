---
title: "Achievement popup"
weight: 26
---

{{% doc-section %}}

## Achievement popup {#achievement-popup-api}

A convincing recreation of the collection log and achievement popup.

```lua
local popup = prettyui.AchievementPopup.show({
    title = "FREE PARTYHAT!",
    text = "You found yourself a free yellow partyhat. Congratulations!",
    item = config.Obj.YELLOW_PARTYHAT,
})

local textOnly = prettyui.AchievementPopup.show({
    title = "NO PARTYHAT",
    text = "No item slot is rendered",
})
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### Construction

`AchievementPopup.show(options)`
: Shows a top-centred popup and returns it, or nil while the game area is unavailable.

`AchievementPopup.new(parent, options)`
: Uses an explicit parent.

`title`, `text`
: Set the heading and body.

`item`, `quantity`
: Optionally display an Obj config and stack quantity.

{{% /api-card %}}

{{% api-card %}}

### Presentation and lifecycle

Timing
: The popup reveals, remains visible, then fades over four seconds.

`sound`, `soundID`
: Disable or replace the completion sound.

Position
: Defaults to a 300x92 top-centred overlay. Override **parent**, **x**, **y**,
  **xAnchor**, or **yAnchor**.

`Destroy()`
: Dismisses the popup early.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
