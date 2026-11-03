---
title: "Item grid"
weight: 23
---

{{% doc-section %}}

## Item grid {#item-grid-api}

ItemGrid arranges item slots into configurable rows and columns, with optional tooltips and drag-and-drop. With an inventory-like visual style.

```lua
local weapon = config.Obj.EGWD_JAS_BOSS_MAGIC_WEAPON_NEW

local grid = view:AddItemGrid({
    [1] = weapon,
    [2] = config.Obj.STEEL_BAR,
    [4] = { object = config.Obj.BRONZE_ARROW, quantity = 250 },
    [6] = config.Obj.LOGS,
    [10] = config.Obj.PLATINUM_BRACELET,
    [16] = weapon,
}, {
    columns = 4,
    rows = 4,
    tooltip = true,
    dragDrop = true,
})

grid:SetObjectAt(2, 2, weapon)
grid:SetObject(1, nil)
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### Construction and data

{{< signature compact="true" >}}
ItemGrid.new(parent, objects, options)
{{< /signature >}}

`objects`
: A sparse row-major array of Obj configs or
  **{ object, quantity, tooltip }** entries.

`columns`, `rows`
: Grid dimensions; each defaults to 1.

`slotGap`
: Distance between cells; defaults to 2.

`quantityMode`
: Quantity display mode for grid cells.

`dragDrop`
: Enables dragging between cells.

`onDrop`
: Receives the grid, source and destination indices, moved object, and displaced object.

`tooltip`
: Use true for object names, a shared value, or a function receiving the object, index, row, and column.

{{% /api-card %}}

{{% api-card %}}

### Methods and behavior

`GetSlot(index)`
: Returns the ItemSlot at a row-major index.

`SetObject(index, object, tooltip, quantity)`
: Updates one cell; pass nil to empty it.

`SetObjectAt(column, row, object, tooltip, quantity)`
: Updates one cell by coordinates.

`SetObjects(objects)`
: Replaces all cell contents.

`SetTooltip(value)`
: Changes the default tooltip value or resolver and refreshes every cell. Explicit per-entry tooltips still take precedence.

`MoveObject(source, destination, notify)`
: Moves or swaps entries while preserving quantities and tooltips.

`SetDragDropEnabled(enabled)`
: Changes drag-and-drop availability.

Empty cells
: Remain valid drop targets but do not show tooltips.

`Destroy()`
: Destroys the grid and its slots.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
