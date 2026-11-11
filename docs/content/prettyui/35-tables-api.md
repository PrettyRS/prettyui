---
title: "Tables"
weight: 35
---

{{% doc-section %}}

## Tables {#tables-api}

A table is a scrollable, column-based grid for displaying lists of data, with a fixed header and support for custom cell content. 

{{< signature >}}
Table.new(parent, options)
{{< /signature >}}

```lua
local data = {
    {
        bossName = "King Black Dragon",
        bossLevel = 276,
        bossHealth = 45000,
        bossLoc = "Wildy"
    },
    {
        bossName = "Ivar, King of Bones",
        bossLevel = 206,
        bossHealth = 45000,
        bossLoc = "Wildy"
    },
    {
        bossName = "Solak, Guardian of the Grove",
        bossLevel = 7000,
        bossHealth = 2000000,
        bossLoc = " Lost Grove"
    },
}


local bossTable = window:AddTable({
    width = window.root.width - 40,
    height = 300,
    rowHeight = 30,
    emptyText = "No Boss Data to Display",
    stretch = true,
    rows = rows,
    columns = {
        { key = "bossName", label = "Boss Name", width = 150 },
        { key = "bossLevel", label = "Boss Level", width = 60 },
        { key = "bossHealth", label = "Boss Health Total", width = 150, stretch = false },
        { key = "bossLoc", label = "Boss Location", width = 200 },
        { label = "Teleport", width = 150, stretch = false,  
            render = function(cell, rowData, cellWidth, cellHeight)
                return prettyui.SimpleButton.new(cell, "Teleport", function() 
                    print("Teleport")
                end,  {
                    x = 6, y = 2, width = cellWidth - 12, height = cellHeight - 10
                })
            end
        },
        
    }
})
```

Some Text here

{{% api-grid compact="true" %}}

{{% api-card %}}

### Options

`columns`
:  An array of column tables one per column. Each column's `key` picks which field of a row it shows and `label` sets its header text. A table must have at least one column. See the [Columns](#columns) section for every column option.

`rows`
: An array of row tables, one per row displayed in order. Each rows fields are matched to columns by the columns `key` so `{ bossName = "King Black Dragon", bossLevel = 276 }` fills the `Boss Name` and `Boss Level` columns. Render columns get the whole rows table, so a row can also hold fields that no column shows (IDs, callbacks and so on). 

`width`, `height`
: Default size is **600 × 400**.

`stretch`
: When **true** columns stretch to fill any remaining width. The spare space is shared between stretchable columns in proportion to their starting `width`, so wider columns get more. Defaults to **false**.

`rowHeight`
: Sets the height of each row. Default height is **36**

`headerHeight`
: Sets the height of the header. Default height is **28**

`scrollbarGap`
: The gap(padding) between the scroll bar and the last column. Default is **18**

`overscan`
: The amount of additional rows built above and below the viewable rows. Default is **2**

`emptyText`
: Displayed when there is no current data in the table. 

`colours`
: Overrides the tables default colours. Only pass the colours you want to change. Default Colours

    - header = 0x2A231BFF
    - headerText = 0xF2C66DFF
    - rowOdd = 0x13110EFF
    - rowEven = 0x181510FF
    - text = 0xE7D7B0FF
    - empty = 0xC9BEA4FF

`X`, `Y`
: Optional layout overrides.

{{% /api-card %}}

{{% api-card %}}

### Columns

`key`
: Column refrece key for data to be applied to the right columns, Render columns do not need keys.

`label`
: The text displayed at the top of each column in the header. 

`width`
: Width of each column. Default is **100**

`stretch`
: When set to false it stops the column from being stretched is `stretch` in table.options is set to true. Default is **true**

`format`
: Optional callback function(value, rowData, rowIndex) Allows you to format the text passed in by the orginal data table without changing the underlying data. `format` is ignored on `render` columns. `rowData` contains all the data for that row including all other keys information. 

    ```lua
        { key = "salary", label = "Salary", width = 100, format = function(value, rowData, rowIndex)
            return "$" .. tostring(value)
        end }
    ```

`render`
: Optional callback function(cell, rowData, width, height, rowIndex) Allows you to insert custom content (Buttons, Sprites, ItemSlots) into the cell layer. `rowData` contains all the data for that row including all other keys information. 


{{% /api-card %}}

{{% api-card %}}

### Methods

`GetRows()`, `SetRows(rows, keepScroll)`
: Get or Set the row data. `GetRows` returns the table itself, not a copy. 
`SetRows` replaces all row data with `rows`, passing nil or an empty table displays `emptyText`. The scrollbar will reset to the top unless
`keepScroll` is set to true, at which point it will stay it was.

`SetColumns(columns)`
: Replaces the column and rebuilds the whole table. Requires at least one column. Scrollbar is reset back to top.

`SetPos(x, y)`
: Moves the table. Passing nil for either value keeps its current position on that axis.

`SetSize(width, height)`
: Resizes the table without a rebuild. Passing nil for either value keeps its current size. Rows are onyl rebuild if a
`render` column changes width. 

`SetStretch(stretch)`
: Turns column stretching on or off and resizes the table.

`SetRowHeight(rowheight, headerHeight)`
: Changes the row and/or header height and rebuilds the entire table. Passing nil for either keeps its current value. Scrollbar is reset abck to top.

`Refresh()`
: Rebuilds the rows currently in view from the current row data. Use it after editing rows that are in view

`Rebuild(keepScroll)`
: Destroys and rebuilds the whole table (header, body and rows). Scrollbar resets to the top unless `keepScroll` is true.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
