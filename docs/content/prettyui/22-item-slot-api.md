---
title: "Item slot"
weight: 22
---

{{% doc-section %}}

## Item slot {#item-slot-api}

ItemSlot displays an Obj config and optional quantity in a slot similar to that in the beasts tab.

```lua
local emptySlot = view:AddItemSlot(nil)

local slot = view:AddItemSlot(config.Obj.EGWD_JAS_BOSS_MAGIC_WEAPON_NEW, {
    inline = true,
    tooltip = "Magic weapon",
})

slot:SetObject(config.Obj.STEEL_BAR)
slot:SetDisabled(true)
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### Construction

{{< signature compact="true" >}}
ItemSlot.new(parent, object, options)
{{< /signature >}}

`object`
: Obj config to display, or nil for an empty slot.

`AddItemSlot(object, options)`
: Adds a flow-managed slot to a window, simple view, or panel.

`quantity`
: Optional stack size; values above one are displayed by default.

`tooltip`
: Tooltip shown while the slot contains an object.

`disabled`
: Starts the slot disabled. Populated slots dim the item and show a dark overlay; empty slots show no overlay.


{{% /api-card %}}

{{% api-card %}}

### Appearance and methods

`itemInset`
: Inset around the object; defaults to 4.

`outlineWidth`
: Optional object outline thickness.

`shadowRGBA`
: Optional object shadow colour.

`quantityMode`
: Overrides the quantity display mode.

`SetObject(object, quantity)`
: Replaces the Obj and optional stack size; pass nil to clear it.

`SetQuantity(quantity)`
: Changes or clears the stack size.

`SetDisabled(disabled)`
: Toggles the disabled appearance. This is visual only; the object, quantity, and tooltip remain unchanged.


`SetTooltip(value)`
: Changes the tooltip.

`Destroy()`
: Destroys the slot.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
