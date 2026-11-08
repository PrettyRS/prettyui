---
title: "Keybind field"
weight: 33
---

{{% doc-section %}}

## Keybind field {#keybind-field-api}

An input-styled field for one key or a two-key chord, displayed as centered text.

{{< signature >}}
KeybindField.new(parent, options)
host:AddKeybindField(options)
{{< /signature >}}

```lua
local binding = { GameKey.CONTROL, GameKey.SHIFT }
local field = window:AddKeybindField({
    value = binding,
    defaultValue = binding,
    onChange = function(field, value)
        binding = value
    end,
})

-- In your input handler or update loop:
local held = prettyui.KeybindField.IsDown(binding)
```

Click to listen. The first one or two distinct keys are committed when all captured keys are released. Repeats, extra keys, and keys held before clicking are ignored. Focus loss cancels unfinished capture.

{{% api-grid compact="true" %}}

{{% api-card %}}

### Options

`value`
: Array of up to two distinct numeric **GameKey** values. Defaults to **{}** (unbound).

`defaultValue`
: Optional reset value. Does not set the initial value; pass `value` to display a binding on creation.

`onChange(field, value)`
: Receives the committed array after capture, clearing, or reset. Construction does not notify.

`disabled`
: Disables interaction. Defaults to **false**.

`width`, `height`
: Default size is **240 × 24**. Container helpers fill the content width unless a width is supplied.

{{% /api-card %}}

{{% api-card %}}

### Methods

`GetValue()`, `SetValue(value, notify?)`
: Read a copied array or replace the binding. Setting cancels capture; pass **true** to notify `onChange`.

`StartListening()`, `CancelListening()`, `IsListening()`
: Start, cancel, or query capture. Cancel restores the committed value's display.

`SetDisabled(disabled)`, `Destroy()`
: Disable interaction or release the control. Disabling or destroying stops capture.

### KeybindField helpers

`IsDown(value)`
: True while all keys in a nonempty binding are held, not just on the initial press. False during any keybind field's capture or when keyboard input is unavailable or blocked. Extra held keys are allowed.

`IsCapturing()`
: Whether any keybind field is listening. Only one can listen at a time.

`FormatValue(value)`
: Returns the display label, such as **Ctrl + Shift**.

{{% /api-card %}}

{{% /api-grid %}}

{{% note %}}

**Container helpers.** `AddKeybindField` is available on windows, simple views, panels, tab pages, and collapse sections. Panels synchronize docked and pop-out values and notify once with the paired field handle.

{{% /note %}}

{{% /doc-section %}}
