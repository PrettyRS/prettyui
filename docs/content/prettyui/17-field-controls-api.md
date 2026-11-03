---
title: "Text fields, combo boxes and lists"
weight: 17
---

{{% doc-section %}}

## Text fields, combo boxes and lists {#field-controls-api}

These controls provide text entry and single- or multi-selection with consistent flow placement, tooltips, disabled states, and callbacks.

For keyboard bindings, use [KeybindField](#keybind-field-api).

{{< signature >}}
TextField.new(parent, options)
ComboBox.new(parent, options)
List.new(parent, options)
{{< /signature >}}

```lua
local name = window:AddTextField({
    placeholder = "Character name",
    maxLength = 24,
    onSubmit = function(field, text)
        saveName(text)
    end,
})

local skill = window:AddComboBox({
    entries = {
        { label = "Attack", id = 1 },
        { label = "Magic", id = 2 },
    },
    selectedID = 1,
    onChange = function(combo, id, label)
        selectSkill(id)
    end,
})

local filters = window:AddList({
    maxSelected = 2,
    entries = {
        { label = "Timers", id = 1, selected = true },
        {
            label = "Icons",
            id = 2,
            backgroundColour = 0x211E1BFF,
            hoverColour = 0x332C27FF,
            selectedColour = 0x4A3D32FF,
            textColour = 0xF4E7D0FF,
        },
    },
    onChange = function(list, id, selected)
        setFilter(id, selected)
    end,
})
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### TextField

`text`, `placeholder`
: Initial and empty-state text.

`visibility`, `filterMode`, `maxLength`, `inputMode`
: Configure native input and validation behavior. **maxLength** defaults to
  9999.

`onChange(field, reason, text)`
: Runs when content changes.

`onSubmit(field, text)`
: Runs when Enter submits the field.

`GetText()`, `SetText(text, notify?)`
: Read or replace the content.

{{% /api-card %}}

{{% api-card %}}

### ComboBox and List

`entries`
: An array of labels or **{ label, id }** records. IDs must be unique.

Ordered combo boxes
: Give an entry an integer **order** to use the searchable ordered combo box.
  Entries with **order** appear first, sorted by order and then label; entries
  without **order** follow alphabetically. Supply ordered entries at construction.
  An open dropdown closes when its field is partially or fully clipped by a
  scrolling container. Scrolling the field back into view does not reopen it.

`selectedID`
: Selects the initial combo-box entry.

`maxSelected`
: Limits active list entries.

Entry options
: **selected**, **disabled**, **visible**, and **icon** configure individual
  entries. List entries also accept **backgroundColour**, **hoverColour**,
  **selectedColour**, **textColour**, and **disabledTextColour** overrides.
  Selected backgrounds take precedence over hover and base backgrounds.

Callbacks
: Combo boxes report **(control, id, label, eventType)**; lists report
  **(control, id, selected, eventType)**.

Methods
: Use **Select**, **SetSelected**, **SetScrollPosition**, **SetEntries**,
  **Clear**, and **SetDisabled** to update controls.

{{% /api-card %}}

{{% /api-grid %}}

{{% note %}}

**Container helpers.** `AddTextField`, `AddComboBox`, and `AddList` are available on windows, simple views, panels, tab pages, and collapse sections. They fill the content width by default. Pop-out panels synchronize field values and selections between views.

{{% /note %}}

{{% /doc-section %}}
