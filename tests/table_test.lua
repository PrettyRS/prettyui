local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function expectError(fn, message)
    local ok = pcall(fn)
    if ok then error(message .. ": expected an error but none happened", 2) end
end

local function count(tbl)
    local n = 0

    for _ in pairs(tbl) do
        n = n + 1
    end

    return n
end

local function childrenOfKind(component, kind)
    local result = {}

    for _, child in ipairs(component.children) do
        if child.kind == kind and not child.destroyed then
            result[#result + 1] = child
        end
    end

    return result
end

local function liveRows(tbl)
    return childrenOfKind(tbl.scrollView.content, "Layer")
end

local function rowShowing(tbl, text)
    for _, row in ipairs(liveRows(tbl)) do
        local first = childrenOfKind(row, "Text")[1]

        if first and first.content == text then
            return row
        end
    end
    return nil
end

local function component(parent, categoryID, dynamicID)
    local result = { children = {}, x = 0, y = 0, width = 0, height = 0 }

    function result:SetPos(x, y) self.x, self.y = x, y end
    function result:SetSize(width, height) self.width, self.height = width, height end
    function result:MoveToBack() self.movedToBack = true end

    function result:Destroy()
        if self.destroyed then return end
        self.destroyed = true
        for _, child in ipairs(self.children) do child:Destroy() end
    end

    if parent then 
        parent.children[#parent.children + 1] = result
    end

    return Interfaces.component(result, parent, categoryID, dynamicID)
end

local function factory(kind)
    return function(parent, categoryID, dynamicID)
        local c = component(parent, categoryID, dynamicID)

        c.kind = kind

        return c
    end
end

ui = {
    Layer = { new = factory("Layer") },
    Text = { new = factory("Text") },
    Rectangle = { new = factory("Rectangle") },
    AlignMode = { CENTRE = "CENTRE" },
    Interfaces = {},
}

id = {
    Font = setmetatable({}, { __index = function(_, name) return name end }),
}

local layoutResizes = {}

package.loaded["src/core/layout"] = {
    resize = function(owner, component, height)
        layoutResizes[#layoutResizes + 1] = { owner = owner, component = component, height = height }
    end,
}

package.loaded["src/simple_view"] = {
    new = function(parent, options)
        local view = {
            options = options,
            root = ui.Layer.new(parent),
            width = options.width,
            height = options.height,
            contentHeight = options.contentHeight,
            scrollY = 0,
            _onScrollWheel = options._onScrollWheel,
        }
        view.content = ui.Layer.new(view.root)
        view.interfaceID = view.root.interfaceID 

        local function clamp(self)
            local maxScroll = math.max(0, self.contentHeight - self.height)
            self.scrollY = math.max(0, math.min(self.scrollY, maxScroll))
        end

        function view:SetSize(w, h)
            self.width, self.height = w, h
            clamp(self)
            if self.onLayout then self.onLayout(self) end
        end

        function view:SetContentHeight(h)
            self.contentHeight = h
            clamp(self)
            if self.onLayout then self.onLayout(self) end
        end

        function view:SetScrollPosition(y)
            self.scrollY = y
            clamp(self)
            if self.onLayout then self.onLayout(self) end
        end

        function view:Destroy()
            self.destroyed = true
            if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.root:Destroy() end
        end

        return view
    end,
}

package.loaded["src/core/wheel"] = { bind = function() end }
package.loaded["src/table"] = nil

local Table = require("src/table")

local function newParent()
    return ui.Layer.new(nil)
end

local COLUMNS = {
    { key = "name", label = "Name", width = 100 },
    { key = "qty", label = "Qty", width = 50, stretch = false },
    { key = "price", label = "Price", width = 100 },
}

local function makeRows(n)
    local rows = {}

    for i = 1, n do
        rows[i] = { name = "Item " .. i, qty = i, price = i * 10 }
    end

    return rows
end

expectError(function() Table.new(newParent(), {}) end, "new with no columns errors")

local t = Table.new(newParent(), { columns = COLUMNS })

expect(t.root.width, 268, "frame shrinks to columns + scrollbar gap")

local headers = childrenOfKind(t.headerArea, "Text")

expect(#headers, 3, "one header label per column")
expect(headers[1].content, "Name", "headers are in column order")
expect(headers[3].content, "Price", "headers are in column order")
expect(t.headerBackground.movedToBack, true, "header background sits behind the labels")

expect(childrenOfKind(t.scrollView.content, "Text")[1].content, "Nothing to show.",
    "empty table shows the empty text")
expect(#liveRows(t), 0, "empty table builds no rows")

local s = Table.new(newParent(), { columns = COLUMNS, width = 418, stretch = true })

expect(s.columnWidths[1], 175, "stretch: Name gets half the spare")
expect(s.columnWidths[2], 50, "stretch: stretch=false column stays put")
expect(s.columnWidths[3], 175, "stretch: Price gets half the spare")
s:Destroy()

s = Table.new(newParent(), { columns = COLUMNS, width = 419, stretch = true })
expect(s.columnWidths[3], 176, "stretch: leftover pixel goes to the last stretchable column")
s:Destroy()

s = Table.new(newParent(), { columns = COLUMNS, width = 200, stretch = true })
expect(s.columnWidths[1], 100, "columns are not shrunk")
expect(s.root.width, 200, "frame stays within the given width")
s:Destroy()

t:SetRows(makeRows(100))

expect(t.scrollView.contentHeight, 4400, "scroll area is sized for ALL rows")
expect(#liveRows(t), 11, "only 11 of 100 rows are built")
expect(rowShowing(t, "Item 11") ~= nil, true, "row 11 (overscan) is built")
expect(rowShowing(t, "Item 12"), nil, "row 12 is not built")
expect(rowShowing(t, "Nothing to show."), nil, "empty text is gone once there are rows")

local row1 = rowShowing(t, "Item 1")
t.scrollView:SetScrollPosition(49 * 44) 

expect(row1.destroyed, true, "rows scrolled out of view are destroyed")
expect(#liveRows(t), 13, "still only a handful of rows built")
expect(rowShowing(t, "Item 47"), nil, "row above the overscan is not built")
expect(rowShowing(t, "Item 48") ~= nil, true, "first overscan row is built")
expect(rowShowing(t, "Item 60") ~= nil, true, "last overscan row is built")
expect(rowShowing(t, "Item 61"), nil, "row below the overscan is not built")
expect(rowShowing(t, "Item 50").y, 49 * 44, "rows are positioned by index")

local row50 = rowShowing(t, "Item 50")
t.scrollView:SetScrollPosition(49 * 44 + 1)
expect(rowShowing(t, "Item 50"), row50, "tiny scroll does not rebuild rows")


local renderCalls = {}
local cleaned = 0
local wheelHandler = function() end

local cells = Table.new(newParent(), {
    columns = {
        { key = "name", label = "Name", width = 120 },
        { key = "price", label = "Price", width = 80,
          format = function(value) 
            return value .. "gp" 
        end },
        { label = "Action", width = 60,
          render = function(cell, rowData, width, height, rowIndex)
            renderCalls[#renderCalls + 1] = {
                cell = cell, rowData = rowData, width = width, rowIndex = rowIndex
            }

            return function()
                cleaned = cleaned + 1
             end
          end },
    },
    rows = { { name = "sheep", price = 500 }, { name = "dragon", price = 900 } },
    _onScrollWheel = wheelHandler,
})

local sheep = rowShowing(cells, "sheep")
local texts = childrenOfKind(sheep, "Text")
expect(#texts, 2, "render columns don't create text labels")
expect(texts[2].content, "500gp", "format changes the displayed text")
expect(cells:GetRows()[1].price, 500, "format doesn't change the data")

expect(childrenOfKind(sheep, "Rectangle")[1].rgba, cells.colours.rowOdd, "row 1 uses the odd colour")
expect(childrenOfKind(rowShowing(cells, "dragon"), "Rectangle")[1].rgba, cells.colours.rowEven,
    "row 2 uses the even colour")

expect(#renderCalls, 2, "render is called once per row")
expect(renderCalls[2].rowData.name, "dragon", "render gets the row data")
expect(renderCalls[2].rowIndex, 2, "render gets the row index")
expect(renderCalls[1].width, 60, "render gets the column width")
expect(renderCalls[1].cell.x, 200, "render cell starts after the earlier columns")

cells:GetRows()[1].name = "Big Sheep"
cells:Refresh()
expect(sheep.destroyed, true, "Refresh destroys the old rows")
expect(cleaned, 2, "Refresh cleans up render handles")
expect(rowShowing(cells, "Big Sheep") ~= nil, true, "Refresh shows the new data")

local newRows = makeRows(5)
cells:SetRows(newRows)
expect(cells:GetRows(), newRows, "GetRows returns what SetRows was given")
expect(#liveRows(cells), 5, "SetRows builds the new rows")
cells:Destroy()

t.scrollView:SetScrollPosition(1000)
t:SetRows(makeRows(100))
expect(t.scrollView.scrollY, 0, "SetRows scrolls back to the top")
t.scrollView:SetScrollPosition(1000)
t:SetRows(makeRows(100), true)
expect(t.scrollView.scrollY, 1000, "SetRows(rows, true) keeps the scroll position")


t:SetPos(25, 40)
local root, view = t.root, t.scrollView
local row30 = rowShowing(t, "Item 30")

t:SetSize(700, 500)

expect(t.root, root, "SetSize keeps the same root")
expect(t.scrollView, view, "SetSize keeps the same scroll view")
expect(rowShowing(t, "Item 30"), row30, "SetSize keeps existing rows")
expect(t.root.height, 500, "root gets the new height")
expect(t.root.x, 25, "SetSize keeps the position")
expect(t.scrollView.scrollY, 1000, "SetSize keeps the scroll position")
expect(rowShowing(t, "Item 36") ~= nil, true, "growing taller builds the newly visible rows")


t.root.height = 1
t:SetSize(700, 500)
expect(t.root.height, 1, "same size: SetSize returns early")
t.root.height = 500

local renders, lastWidth = 0, nil
cleaned = 0
local r = Table.new(newParent(), {
    columns = {
        { key = "name", label = "Name", width = 100 },
        { label = "Btn", width = 60, render = function(cell, rowData, width)
            renders = renders + 1
            lastWidth = width
            return function() cleaned = cleaned + 1 end
        end },
    },
    rows = makeRows(2), width = 218, stretch = true,
})

r:SetSize(318, 400)
expect(renders, 4, "render column width changed -> rows re-rendered")
expect(cleaned, 2, "old render handles are cleaned up first")
expect(lastWidth, 113, "render gets the new width")
r:Destroy()

renders = 0

local fixed = Table.new(newParent(), {
    columns = {
        { key = "name", label = "Name", width = 100 },
        { label = "Btn", width = 60, stretch = false, render = function() renders = renders + 1 end },
    },
    rows = makeRows(2), width = 218, stretch = true,
})
local fixedRow = rowShowing(fixed, "Item 1")

fixed:SetSize(318, 400)
expect(renders, 2, "render width unchanged -> render not called again")
expect(rowShowing(fixed, "Item 1"), fixedRow, "row is reused")
expect(childrenOfKind(fixedRow, "Text")[1].width, 240 - 16, "text cell resized in place")
expect(fixedRow.width, 300, "row resized to the new width")
fixed:Destroy()


local someRow = liveRows(t)[1]

t:SetStretch(true)
expect(t.root, root, "SetStretch doesn't rebuild")
expect(childrenOfKind(t.headerArea, "Text")[3].x, 316 + 50 + 8, "headers move to the new columns")
expect(someRow.width, 682, "existing rows widen")
t:SetStretch(false)
expect(someRow.width, 250, "SetStretch(false) restores natural widths")


t:SetRowHeight(20, 40)
expect(root.destroyed, true, "SetRowHeight rebuilds")
expect(t.scrollView.contentHeight, 100 * 20, "content height uses the new row height")
expect(rowShowing(t, "Item 2").y, 20, "rows are positioned with the new height")

expectError(function() t:SetColumns({}) end, "SetColumns({}) errors")
t:SetColumns({ { key = "name", label = "Only", width = 90 } })
expect(childrenOfKind(t.headerArea, "Text")[1].content, "Only", "SetColumns rebuilds the header")
expect(#childrenOfKind(liveRows(t)[1], "Text"), 1, "rows use the new columns")

t.scrollView:SetScrollPosition(300)
t:Rebuild(true)
expect(t.scrollView.scrollY, 300, "Rebuild(true) keeps the scroll position")

t.root:SetPos(77, 88)
t:Rebuild()
expect(t.root.x, 77, "Rebuild keeps a position set by someone else")
expect(t.scrollView.scrollY, 0, "Rebuild without keepScroll goes to the top")


local shouldFail = false
cleaned = 0

local e = Table.new(newParent(), {
    columns = { 
        { label = "X", width = 50, render = function(cell, rowData, width, height, rowIndex)
            if shouldFail and rowIndex == 3 then
                error("render bboke")
            end

            return function() cleaned = cleaned + 1 end
        end } },
    rows = makeRows(5),
})

shouldFail = true
expectError(function() e:Refresh() end, "the render error reaches the caller")
expect(count(e.renderedRows), 0, "rows from the failed pass are forgotten")
expect(cleaned, 5 + 2, "their render handles are cleaned up")

shouldFail = false
e:Refresh()
expect(count(e.renderedRows), 5, "the table renders again once fixed")
e:Destroy()

local lastRoot, lastView = t.root, t.scrollView
local aRow = liveRows(t)[1]
t:Destroy()
expect(lastRoot.destroyed, true, "Destroy destroys the root")
expect(aRow.destroyed, true, "Destroy destroys the rows")
expect(lastView.onLayout, nil, "Destroy unhooks scrolling so no rows get rebuilt")
t:Destroy()
t:SetSize(100, 100)

cleaned = 0
local late = Table.new(newParent(), {
    columns = { 
        { label = "X", width = 50, render = function() 
            return function() 
                    cleaned = cleaned + 1
                end
            end
        } 
        },
    rows = makeRows(3),
})

Interfaces.unload(late.root.interfaceID)
late:SetSize(999, 999)
late:Destroy()
expect(cleaned, 3, "closed: render handles still cleaned up")

print("table_test: ok")