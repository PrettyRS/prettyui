---
title: "Fancy button"
weight: 14
---

{{% doc-section %}}

## Fancy button {#fancy-button-api}

A prominent text button available in positive, neutral, and negative variants.

{{< signature >}}
FancyButton.new(parent, text, action, options)
{{< /signature >}}

```lua
local confirm = window:AddFancyButton("Confirm", function()
    confirmAction()
end, { variant = "positive" })

local cancel = window:AddFancyButton("Cancel", function()
    cancelAction()
end, { inline = true, variant = "negative" })
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### Options

`variant`
: Accepts **positive**, **neutral** (default), or **negative**.

`width`
: Requests a minimum width; otherwise the button fits its label.

`colour`, `disabledColour`
: Override the variant's text colours.

`disabled`, `hoverCursor`, `tooltip`
: Configure initial availability and interaction.

{{% /api-card %}}

{{% api-card %}}

### Methods

`SetVariant(variant)`
: Changes the variant and default text colour.

`SetDisabled(disabled)`
: Changes availability.

`SetText(text)`
: Changes the label and recalculates the fitted width.

`SetHoverCursor(cursor)`
: Overrides the hover cursor.

`Destroy()`
: Destroys the button.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
