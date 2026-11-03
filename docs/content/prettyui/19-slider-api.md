---
title: "Slider"
weight: 19
---

{{% doc-section %}}

## Slider {#slider-api}

A ranged control supporting thumb dragging, track clicks, and decrease/increase buttons.

```lua
local opacity = window:AddSlider({
    min = 0,
    max = 100,
    value = 100,
    step = 1,
    onChange = function(_, value)
        window.background.alpha = value / 100
    end,
})
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### Configuration

{{< signature compact="true" >}}
Slider.new(parent, options)
{{< /signature >}}

`min`, `max`
: Numeric range, defaulting to 0 through 100.

`value`
: Initial value; defaults to the minimum.

`step`
: Positive increment and snapping interval; defaults to 1.

`buttonGap`
: Space between the track and each button; defaults to 4.

`onChange(slider, value)`
: Runs after an interactive or notified programmatic change.

`disabled`
: Blocks interaction when true.

{{% /api-card %}}

{{% api-card %}}

### Methods and interaction

`GetValue()`
: Returns the current snapped value.

`SetValue(value, notify?)`
: Clamps and snaps a value. Pass false to suppress the callback.

`SetDisabled(value)`
: Changes availability.

`AddSlider(options)`
: Adds a width-filling slider to supported containers.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
