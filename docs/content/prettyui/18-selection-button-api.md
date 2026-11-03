---
title: "Radio and checkbox buttons"
weight: 18
---

{{% doc-section %}}

## Radio and checkbox buttons {#selection-button-api}

Radio groups select one value; checkbox groups retain an ordered set of values.

{{< signature >}}
RadioButton.new(parent, choices, options)
CheckboxButton.new(parent, choices, options)
{{< /signature >}}

```lua
local density = window:AddRadioButton({
    { text = "Compact", value = "compact" },
    { text = "Comfortable", value = "comfortable" },
}, {
    selectedValue = "comfortable",
    onChange = function(group, value)
        applyDensity(value)
    end,
})

local features = window:AddCheckboxButton({
    { text = "Audio", value = "audio", selected = true },
    { text = "Animations", value = "animations" },
}, {
    onChange = function(group, values, changedValue, selected)
        saveFeatures(values)
    end,
})

local selectedDensity = density:GetSelectedValue()
local selectedFeatures = features:GetSelectedValues()
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### Choices and state

`choices`
: A non-empty array. Each entry may be a direct value or a table with
  **text**/**label**, **value**, **selected**, **disabled**, and **tooltip**.

`selectedValue`
: Initial value for a radio group.

`selectedValues`
: Initial array or value-to-true map for a checkbox group.

`inline`
: Lays radio or checkbox choices out side by side on one row. It also retains
  the shared flow behavior and joins the current content row when one exists.

`disabled`
: Disables the entire group.

`onChange`
: Receives the updated selection after user changes.

{{% /api-card %}}

{{% api-card %}}

### Methods

`GetSelectedValue()`
: Reads the radio value.

`SetSelectedValue(value)`
: Selects one radio value, or clears it with nil.

`GetSelectedValues()`
: Returns checkbox values in option order.

`IsSelected(value)`
: Tests a radio or checkbox value.

`SetSelected(value, selected)`
: Updates one checkbox value.

`SetDisabled(disabled)`
: Changes group availability.

`SetOptionTooltip(value, tooltip)`
: Adds, replaces, or removes one choice's tooltip.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
