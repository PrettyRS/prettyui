---
title: "Simple button"
weight: 13
---

{{% doc-section %}}

## Simple button {#simple-button-api}

A compact action or toggle button containing text or an icon.

{{< signature >}}
SimpleButton.new(parent, content, action, options)
{{< /signature >}}

```lua
local iconButton = window:AddSimpleButton(id.Sprite.CHAT_V2_FILTERS_ON_8, function()
    openIconAction()
end)

local textButton = window:AddSimpleButton("Test", function(self, active)
    setTestEnabled(active)
end, { inline = true, toggleable = true })
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### Content and options

Text
: Pass a string; the button sizes itself to fit.

Icon
: Pass a numeric sprite ID.

Options
: **width**, **height**, **size**, **iconSize**, **iconWidth**, **iconHeight**,
  **colour**, **disabledColour**, **hoverCursor**, and **tooltip** customize the
  button.

{{% /api-card %}}

{{% api-card %}}

### States and methods

`toggleable`
: Persists the active state after a click.

`disabled`
: Sets the initial disabled state and blocks input.

`SetActive(active)`
: Changes the persistent active state.

`SetDisabled(disabled)`
: Changes availability.

`SetHoverCursor(cursor)`
: Overrides the hover cursor.

`Destroy()`
: Destroys the button.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
