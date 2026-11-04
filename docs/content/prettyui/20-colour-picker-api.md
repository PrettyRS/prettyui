---
title: "Colour picker"
weight: 20
---

{{% doc-section %}}

## Colour picker {#colour-picker-api}

A button with a colour swatch that opens a picker window beside the swatch. Changes remain provisional until the user accepts them; closing the window cancels the selection.

```lua
local picker = window:AddColourPicker({
    value = 0xC86B17FF,
    buttonSize = 48,
    windowTitle = "Highlight colour",
    tooltip = "Choose a highlight colour",
    onChange = function(_, colour)
        settings.highlightColour = colour
    end,
})

picker:SetValue(0x8A2BE2FF, false)
local colour = picker:GetValue()
```

Enable `alphaSlider` when callers need to choose opacity as well as colour:

```lua
local overlayPicker = window:AddColourPicker({
    value = 0x4D8BD566,
    alphaSlider = true,
    windowTitle = "Overlay colour",
    onChange = function(_, colour)
        settings.overlayColour = colour
    end,
})
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### Construction and appearance

{{< signature compact="true" >}}
ColourPicker.new(parent, options)
{{< /signature >}}

`value`
: Initial colour value.

`alphaSlider`
: Adds an opacity slider when true. The accepted value includes the selected
  alpha in its final **AA** byte.

`buttonSize` or `size`
: Sets the square button size; defaults to 24. The colour swatch occupies 65% of the shorter button edge.

`width`, `height`
: Override the button dimensions independently.

`tooltip`, `disabled`
: Configure the button tooltip and initial availability.

`AddColourPicker(options)`
: Adds a flow-managed picker to a window, simple view, panel, or tab page.

{{% /api-card %}}

{{% api-card %}}

### Picker window

`windowTitle` or `title`
: Changes the picker window title.

`windowWidth`, `windowHeight`
: Override picker dimensions. The minimum and default size is 220 × 340.
  `alphaSlider` raises the minimum and default height to 376.

`windowParent`, `overlayParent`
: Select the parent that contains the picker window. `overlayParent` is an
  alias. Without either option, the window is mounted in the outermost parent.

`windowX`, `windowY`, `pickerX`, `pickerY`
: Override either position axis. `pickerX` and `pickerY` are aliases. Without
  an override, the picker aligns horizontally with its swatch, opens below it,
  flips above it when necessary, and keeps automatic coordinates within its
  window parent. Explicit coordinates are not clamped.

`acceptText`, `acceptWidth`, `acceptVariant`
: Configure the accept button.

Accept and cancel
: Dragging updates the preview. Accept commits the colour and runs
  **onChange**; the window close button discards the provisional colour.

{{% /api-card %}}

{{% api-card %}}

### State

`GetValue()`
: Returns the committed colour. **GetColour()** is an alias.

`SetValue(colour, notify?)`
: Sets the committed colour and updates the swatch. Pass false to suppress
  **onChange**. **SetColour()** is an alias.

`Open()`
: Opens or raises the picker and returns true, or false while the control is disabled.

`Close()`
: Closes the picker without committing its provisional colour.

`SetDisabled(disabled)`
: Changes button availability.

`Destroy()`
: Closes the picker and destroys its component tree.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
