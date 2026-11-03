---
title: "Sprite button"
weight: 15
---

{{% doc-section %}}

## Sprite button {#sprite-button-api}

Named sprite buttons support momentary actions and enabled/disabled toggles.

{{< signature >}}
SpriteButton.new(parent, spriteName, action, options)
{{< /signature >}}

```lua
local actionButton = window:AddSpriteButton("MENU", function()
    openMenu()
end)

local toggleButton = window:AddSpriteButton("SETTINGS", function(self, enabled)
    setSettingsEnabled(enabled)
end, { inline = true, toggleable = true })

local lockButton = window:AddSpriteButton("LOCK", function(self, unlocked)
    setLocked(not unlocked)
end, { inline = true, toggleable = true, disabled = true })

local trashButton = window:AddSpriteButton("TRASH", function()
    deleteSelectedItem()
end, { inline = true, tooltip = "Delete" })
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### Modes

Action
: Runs the callback when clicked.

Toggle
: Set **toggleable = true**; each click changes the enabled state and passes it
  to the callback.

`disabled`
: Sets the initial disabled state. Non-toggle buttons ignore input while disabled.

`hoverCursor`
: Overrides the sprite set's default cursor.

{{% /api-card %}}

{{% api-card %}}

### Methods

`SetDisabled(disabled)`
: Updates the enabled state.

`SetSprite(name)`
: Switches to another predefined sprite set.

`SetHoverCursor(cursor)`
: Applies a Cursor config or numeric ID.

`Destroy()`
: Destroys the button.

{{% /api-card %}}

{{% /api-grid %}}

The name palette below shows each button's neutral client sprite. Filter by name, then select a tile to copy its `SpriteButton` name.

{{% sprite-names %}}

{{% /doc-section %}}
