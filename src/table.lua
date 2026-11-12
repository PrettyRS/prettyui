local Components = require("src/core/components")
local Layout = require("src/core/layout")
local SimpleView = require("src/simple_view")
local Wheel = require("src/core/wheel")

local Table = {}
Table.__index = Table

--[[ 
    I've left some comments in the code mainly explaining some things for anyone that will edit this file,
    I plan to add more comments soon when I get around to it. 

    Theres also other features that could be added in like maybe row selecting (Highlight selected row?)
    But this is a solid foundation for tables for the time being. 
]]

--[[
    Table is a scrollable column based grid with sizeable columns 

    Features Lazy loading (Maybe we need a better name for this?)
        Lazy Loading: Your scroll content is sized for every row (Ensures the Scrollbar is right) 
        but only rows inside the viewable area + overscan are acutally built.
        As you scroll rows that leave the viewable area are destroyed and rows that enter it
        are built. This allows ComponentIDs to get reused after rows are Destroyed, so the tables
        component count stays roughtly the same no matter how many rows it has. 

    Columns Explained:
        key      - Refrence Key for data to be applied to the right columns (Renders Do not need keys)
        label    - Column headers text.
        width    - Column width (default 100)
        stretch  - False keeps this column at its width when the table stretches (default true)
        format   - optional function(value, rowData, rowIndex) -> Allows
                    you to modify the Text without changing the underlying data (Text Columns only)
        render   - optional function(cell, rowData, width, height, rowIndex) -> 
                   Builds custom content (buttons, sprites etc.) inside the cell layer.
]]

local DEFAULT_COLOURS = {
    header = 0x2A231BFF,
    headerHighlight = 0x3A3024FF,
    headerBorder = 0x6B5530FF,
    headerText = 0xF2C66DFF,
    rowOdd = 0x13110EFF,
    rowEven = 0x181510FF,
    text = 0xE7D7B0FF,
    empty = 0xC9BEA4FF,
}

local DEFAULT_FONT = id.Font.MUSEO_SANS_13PT_REGULAR
local HEADER_FONT = id.Font.MUSEO_SANS_15PT_BOLD


local function mergeColours(overrides)
    local colours = {}

    for key, value in pairs(DEFAULT_COLOURS) do colours[key] = value end

    for key, value in pairs(overrides or {}) do colours[key] = value end

    return colours
end

local function rectangle(parent, x, y, width, height, colour)
    local rect = Components.new(ui.Rectangle, parent)

    rect:SetPos(x, y)
    rect:SetSize(width, height)
    rect.fill = true
    rect.rgba = colour

    return rect
end

local function label(parent, value, x, y, width, height, font, colour)
    local text = Components.new(ui.Text, parent)

    text:SetPos(x, y)
    text:SetSize(width, height)
    text.content = tostring(value == nil and "" or value)
    text.font = font or DEFAULT_FONT
    text.rgba = colour or DEFAULT_COLOURS.text
    text.maxLines = 1
    text.alignVertical = ui.AlignMode.CENTRE
    text.clickthrough = true

    return text
end

local function columnWidth(col)
    return col.width or 100
end


local function layoutColumns(columns, available, stretch)
    local widths, total, stretchTotal = {}, 0, 0

    for i, col in ipairs(columns) do
        widths[i] = columnWidth(col)
        total = total + widths[i]

        if col.stretch ~= false then 
            stretchTotal = stretchTotal + widths[i] 
        end
    end

    local spare = available - total

    if not stretch or spare <= 0 or stretchTotal <= 0 then return widths, total end

    --We spread out the spare space among the columns based on there original width. 

    local given, lastStretchable = 0, nil

    for i, col in ipairs(columns) do
        if col.stretch ~= false then
            local extra = math.floor(spare * widths[i] / stretchTotal)

            widths[i] = widths[i] + extra
            given = given + extra
            lastStretchable = i
        end
    end

    widths[lastStretchable] = widths[lastStretchable] + (spare - given)

    return widths, available
end

local function interfaceLoaded(interfaceID)
    return interfaceID == nil or ui.Interfaces:GetInterface(interfaceID) ~= nil
end

local function cleanupHandle(handle)
    if type(handle) == "function" then
        pcall(handle)
    elseif type(handle) == "table" and handle.Destroy ~= nil then
        pcall(handle.Destroy, handle)
    end
end


function Table.getSize(options)
    options = options or {}

    return options.width or 600, options.height or 400
end

--[[ 
    Constructor
    parent  - Parent we attach to same for all UI.

    options
        columns        - See Column options above.
        rows           - initial row data. 
        x, y           - position (default 0, 0)
        width, height  - size (default 600 x 400). Without stretch table shrinks scroll bar & table to
                            max column width.
        stretch        - True allows columns to stretch to fill in remaing width. (default false)
        rowHeight      - default 36
        headerHeight   - default 28
        scrollbarGap   - space between the last column and the scrollbar
        padding        - horizontal text padding inside cells (default 8)
        overscan       - extra rows built above/below the visable rows. (default 2)
        emptyText      - shown when there is now row data (default "Nothing to show.")
        colours        - partial override of DEFAULT_COLOURS
]]
function Table.new(parent, options)
    options = options or {}
    assert(options.columns and #options.columns > 0, "Table needs at least one column")

    return Components.withBatch(parent, function()
        local self = setmetatable({}, Table)

        self.parent = parent
        self.options = options
        self.columns = options.columns
        self.rows = options.rows or {}

        self.x = options.x or 0
        self.y = options.y or 0
        self.width = options.width or 600
        self.height = options.height or 400
        self.rowHeight = options.rowHeight or 44
        self.headerHeight = options.headerHeight or 28
        self.scrollbarGap = options.scrollbarGap or 18
        self.stretch = options.stretch == true
        self.padding = options.padding or 8
        self.overscan = options.overscan or 2
        self.emptyText = options.emptyText or "Nothing to show."
        self.colours = mergeColours(options.colours)

        self.parentWheel = options._onScrollWheel

        self.renderedRows = {}
        self.firstRendered = nil
        self.lastRendered = nil
        self.rendering = false
        self.suspendRender = false

        self:_BuildFrame()
        self:_BuildBody()

        return self
    end)
end

function Table:SetRows(rows, keepScroll)
    self.rows = rows or {}
    self:_BuildBody(keepScroll)
end

function Table:GetRows()
    return self.rows
end

function Table:SetColumns(columns)
    assert(columns and #columns > 0, "Table needs at least one column")

    self.columns = columns
    self:Rebuild()
end

function Table:SetPos(x, y)
    self.x = x or self.x
    self.y = y or self.y

    if self.root ~= nil then self.root:SetPos(self.x, self.y) end
end

-- Resizes in place no rebuild, so it's cheap enough to call on every step of a window drag.
function Table:SetSize(width, height)
    width = width or self.width
    height = height or self.height

    if width == self.width and height == self.height then return end

    self.width = width
    self.height = height

    self:_Relayout()
end

function Table:SetStretch(stretch)
    stretch = stretch == true

    if stretch == self.stretch then return end

    self.stretch = stretch

    self:_Relayout()
end

function Table:SetRowHeight(rowHeight, headerHeight)
    self.rowHeight = rowHeight or self.rowHeight
    self.headerHeight = headerHeight or self.headerHeight

    self:Rebuild()
end

-- Rebuilds the rows currently in view
function Table:Refresh()
    self:_ClearRenderedRows()
    self:_RenderVisibleRows()
end

function Table:Rebuild(keepScroll)
    local scrollY = keepScroll and self.scrollView and self.scrollView.scrollY or 0

    if self.flowOwner ~= nil and self.root ~= nil and interfaceLoaded(self.interfaceID) then
        Layout.resize(self.flowOwner, self, self.height)
    end

    if self.root ~= nil and interfaceLoaded(self.interfaceID) then
        self.x = self.root.x or self.x
        self.y = self.root.y or self.y
    end

    self:_Teardown()

    Components.withBatch(self.parent, function()
        self:_BuildFrame()
        self:_BuildBody(true)
    end)

    if scrollY > 0 then self.scrollView:SetScrollPosition(scrollY) end
end

function Table:BindFlow(owner)
    self.flowOwner = owner
    return self
end

function Table:Destroy()
    self:_Teardown()
end

--[[
    Applies the current width/height/stretch to the existing components.
    Text cells are moved and resized where they are. Rows are only rebuilt when a
    render column changed width, because whatever render() built was laid out for
    the old width. 
    Growing taller just builds the extra rows that come into view.
]]
function Table:_Relayout()
    if self.root == nil or not interfaceLoaded(self.interfaceID) then return end

    if self.flowOwner ~= nil then Layout.resize(self.flowOwner, self, self.height) end

    local oldWidths = self.columnWidths

    self:_ComputeLayout()

    local rerender = false

    for i, col in ipairs(self.columns) do
        if col.render ~= nil and self.columnWidths[i] ~= oldWidths[i] then
            rerender = true
            break
        end
    end

    self.root:SetSize(self.frameWidth, self.height)
    self.headerArea:SetSize(self.frameWidth, self.headerHeight)
    self.bodyArea:SetSize(self.frameWidth, self.height - self.headerHeight)
    self.headerBackground:SetSize(self.rowWidth, self.headerHeight)
    self.headerHighlight:SetSize(self.rowWidth, 1)
    self.headerBorder:SetSize(self.rowWidth, 2)

    local currentX = 0

    for i, headerLabel in ipairs(self.headerLabels) do
        local colWidth = self.columnWidths[i]

        headerLabel:SetPos(currentX + self.padding, 0)
        headerLabel:SetSize(colWidth - (self.padding * 2), self.headerHeight)

        currentX = currentX + colWidth
    end

    if self.emptyLabel ~= nil then self.emptyLabel:SetSize(self.rowWidth - 24, self.rowHeight) end

    -- Rows
    if rerender then
        self:_ClearRenderedRows()
    else
        for _, rendered in pairs(self.renderedRows) do self:_LayoutRow(rendered) end
    end

    -- Scroll view. Hold rendering until it's fully sized, then build only what's new.
    local view = self.scrollView
    local viewHeight = self.height - self.headerHeight

    self.suspendRender = true
    view:SetSize(self.frameWidth, viewHeight)
    view:SetContentHeight(math.max(viewHeight, #self.rows * self.rowHeight))
    self.suspendRender = false

    self:_RenderVisibleRows()
end

-- Moves/resizes an already built row's cells to the current column widths.
function Table:_LayoutRow(rendered)
    rendered.layer:SetSize(self.rowWidth, self.rowHeight)
    rendered.background:SetSize(self.rowWidth, self.rowHeight)

    local currentX = 0

    for i, colWidth in ipairs(self.columnWidths) do
        local cell = rendered.cells[i]

        if cell.isText then
            cell.component:SetPos(currentX + self.padding, 0)
            cell.component:SetSize(colWidth - (self.padding * 2), self.rowHeight)
        else
            cell.component:SetPos(currentX, 0)
            cell.component:SetSize(colWidth, self.rowHeight)
        end

        currentX = currentX + colWidth
    end
end

function Table:_ComputeLayout()
    local available = math.max(0, self.width - self.scrollbarGap)

    self.columnWidths, self.rowWidth = layoutColumns(self.columns, available, self.stretch)
    self.frameWidth = math.min(self.width, self.rowWidth + self.scrollbarGap)
end

function Table:_BuildFrame()
    self:_ComputeLayout()

    -- Root layer, everything lives inside this so destroying it destroys everything
    self.root = Components.newContent(self.parent, self.options)
    self.interfaceID = self.root.interfaceID

    self.root:SetPos(self.x, self.y)
    self.root:SetSize(self.frameWidth, self.height)
    self.root.clickthrough = true

    -- Header bar that stays at the top
    self.headerArea = Components.newContent(self.root)

    self.headerArea:SetPos(0, 0)
    self.headerArea:SetSize(self.frameWidth, self.headerHeight)
    self.headerArea.clickthrough = true

    self.headerHighlight = rectangle(self.headerArea, 0, 0, self.rowWidth, 1, self.colours.headerHighlight)
    self.headerHighlight.clickthrough = true

    self.headerBorder = rectangle(self.headerArea, 0, self.headerHeight - 2, self.rowWidth, 2, self.colours.headerBorder)
    self.headerBorder.clickthrough = true

    self.bodyArea = Components.newContent(self.root)

    self.bodyArea:SetPos(0, self.headerHeight)
    self.bodyArea:SetSize(self.frameWidth, self.height - self.headerHeight)
    self.bodyArea.clickthrough = true

    local headerBackground = rectangle(self.headerArea, 0, 0, self.rowWidth, self.headerHeight, self.colours.header)
    headerBackground.clickthrough = true

    -- Kept so SetSize/SetStretch can move them without a rebuild
    self.headerBackground = headerBackground
    self.headerLabels = {}

    local currentX = 0

    for i, col in ipairs(self.columns) do
        local colWidth = self.columnWidths[i]

        self.headerLabels[i] = label(
            self.headerArea,
            col.label or "",
            currentX + self.padding,
            0,
            colWidth - (self.padding * 2),
            self.headerHeight,
            HEADER_FONT,
            self.colours.headerText
        )

        currentX = currentX + colWidth
    end

    -- Ensure this stays at the back and doesnt end up at the front. 
    headerBackground:MoveToBack()
end

function Table:_EnsureScrollView()
    if self.scrollView ~= nil then return self.scrollView end

    local viewHeight = self.height - self.headerHeight

    self.scrollView = SimpleView.new(self.bodyArea, {
        width = self.frameWidth,
        height = viewHeight,
        contentHeight = viewHeight,
        scrollable = true,
        scrollStep = self.rowHeight,
        _onScrollWheel = self.parentWheel,
    })

    local previousOnLayout = self.scrollView.onLayout

    self.scrollView.onLayout = function(view)
        if previousOnLayout ~= nil then previousOnLayout(view) end

        self:_RenderVisibleRows()
    end

    return self.scrollView
end

function Table:_BuildBody(keepScroll)
    self:_ClearRenderedRows()

    if self.emptyLabel ~= nil and interfaceLoaded(self.interfaceID) then self.emptyLabel:Destroy() end
    self.emptyLabel = nil

    local view = self:_EnsureScrollView()
    local viewHeight = self.height - self.headerHeight

    -- Size the content for ALL rows (scrollbar stays correct) without building any yet
    self.suspendRender = true
    view:SetContentHeight(math.max(viewHeight, #self.rows * self.rowHeight))

    if not keepScroll then view:SetScrollPosition(0) end
    
    self.suspendRender = false

    if #self.rows == 0 then
        self.emptyLabel = label(
            view.content,
            self.emptyText,
            12,
            0,
            self.rowWidth - 24,
            self.rowHeight,
            HEADER_FONT,
            self.colours.empty
        )
        return
    end

    self:_RenderVisibleRows()
end

-- Works out which rows should exist right now, builds the new ones, destroys the old ones.
function Table:_RenderVisibleRows()
    local view = self.scrollView

    if view == nil or self.rendering or self.suspendRender then return end

    local total = #self.rows

    if total == 0 then return end

    local scrollY = view.scrollY or 0
    local viewHeight = view.height or (self.height - self.headerHeight)

    local first = math.max(1, math.floor(scrollY / self.rowHeight) + 1 - self.overscan)
    local last = math.min(total, math.ceil((scrollY + viewHeight) / self.rowHeight) + self.overscan)

    -- Scrolled less than a row - nothing to do
    if first == self.firstRendered and last == self.lastRendered then return end

    self.rendering = true

    local built = {}

    local ok, err = pcall(function()
        for rowIndex in pairs(self.renderedRows) do
            if rowIndex < first or rowIndex > last then
                self:_DestroyRenderedRow(rowIndex)
            end
        end

        Components.withBatch(view.content, function()
            for rowIndex = first, last do
                if self.renderedRows[rowIndex] == nil then
                    self:_BuildRowAt(rowIndex)
                    built[#built + 1] = rowIndex
                end
            end
        end)
    end)

    self.rendering = false

    if not ok then
        for _, rowIndex in ipairs(built) do
            for _, handle in ipairs(self.renderedRows[rowIndex].handles) do cleanupHandle(handle) end
            self.renderedRows[rowIndex] = nil
        end

        self.firstRendered = nil
        self.lastRendered = nil

        error(err, 0)
    end

    self.firstRendered = first
    self.lastRendered = last
end

function Table:_BuildRowAt(rowIndex)
    local view = self.scrollView
    local rowData = self.rows[rowIndex]
    local rowWidth = self.rowWidth
    local bgColour = (rowIndex % 2 == 1) and self.colours.rowOdd or self.colours.rowEven
    local wheel = { _onScrollWheel = view._onScrollWheel }
    local handles = {}
    local cells = {}

    local rowLayer = Components.newContent(view.content)

    rowLayer:SetPos(0, (rowIndex - 1) * self.rowHeight)
    rowLayer:SetSize(rowWidth, self.rowHeight)
    Wheel.bind(rowLayer, wheel)

    local background = rectangle(rowLayer, 0, 0, rowWidth, self.rowHeight, bgColour)
    Wheel.bind(background, wheel)

    local currentX = 0

    for i, col in ipairs(self.columns) do
        local colWidth = self.columnWidths[i]

        if col.render ~= nil then
            local cell = Components.newContent(rowLayer)

            cell:SetPos(currentX, 0)
            cell:SetSize(colWidth, self.rowHeight)
            Wheel.bind(cell, wheel)

            local handle = col.render(cell, rowData, colWidth, self.rowHeight, rowIndex)

            if handle ~= nil then table.insert(handles, handle) end

            cells[i] = { component = cell, isText = false }
        else
            local value = rowData[col.key]

            if col.format ~= nil then value = col.format(value, rowData, rowIndex) end

            local text = label(
                rowLayer,
                value,
                currentX + self.padding,
                0,
                colWidth - (self.padding * 2),
                self.rowHeight,
                col.font,
                col.colour or self.colours.text
            )

            Wheel.bind(text, wheel)

            cells[i] = { component = text, isText = true }
        end

        currentX = currentX + colWidth
    end

    background:MoveToBack()

    self.renderedRows[rowIndex] = { layer = rowLayer, background = background, cells = cells, handles = handles }
end

function Table:_DestroyRenderedRow(rowIndex)
    local rendered = self.renderedRows[rowIndex]

    if rendered == nil then return end

    for _, handle in ipairs(rendered.handles) do cleanupHandle(handle) end

    if interfaceLoaded(self.interfaceID) then pcall(rendered.layer.Destroy, rendered.layer) end

    self.renderedRows[rowIndex] = nil
end

function Table:_ClearRenderedRows()
    for rowIndex in pairs(self.renderedRows) do
        self:_DestroyRenderedRow(rowIndex)
    end

    self.renderedRows = {}
    self.firstRendered = nil
    self.lastRendered = nil
end

function Table:_Teardown()
    self:_ClearRenderedRows()

    local loaded = interfaceLoaded(self.interfaceID)

    if self.emptyLabel ~= nil and loaded then pcall(self.emptyLabel.Destroy, self.emptyLabel) end
    self.emptyLabel = nil

    if self.scrollView ~= nil then
        self.scrollView.onLayout = nil
        pcall(self.scrollView.Destroy, self.scrollView)
        self.scrollView = nil
    end

    if self.root ~= nil and loaded then pcall(self.root.Destroy, self.root) end
    self.root = nil

    self.headerArea = nil
    self.bodyArea = nil
    self.headerBackground = nil
    self.headerLabels = nil
end

return Table