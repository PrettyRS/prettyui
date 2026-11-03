local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function moveInRenderOrder(value, front)
    local siblings = value.parent and value.parent.renderOrder
    if not siblings then return end
    for index, sibling in ipairs(siblings) do
        if sibling == value then table.remove(siblings, index); break end
    end
    table.insert(siblings, front and #siblings + 1 or 1, value)
end

local function component(parent, kind, categoryID, dynamicID)
    local result = {
        kind = kind,
        x = 0,
        y = 0,
        width = 0,
        height = 0,
        hidden = false,
        subscriptions = {},
        children = {},
    }
    if parent then
        local static = parent.parentStatic or parent
        local category = categoryID or (parent.categoryID == -1 and 0 or parent.categoryID)
        local dynamic = dynamicID or parent.dynamicID + 1
        local ids = static.registry[category] or {}
        static.registry[category] = ids
        if dynamicID == nil then
            while ids[dynamic] do dynamic = dynamic + 1 end
        end
        assert(category >= 0 and category <= 234 and dynamic >= 0 and
            dynamic <= (category == 0 and 4095 or 234), "native ID capacity exceeded")
        assert(ids[dynamic] == nil, "native ID collision")
        result.parentStatic = static
        result.categoryID, result.dynamicID = category, dynamic
        ids[dynamic] = result
        parent.children[#parent.children + 1] = result
    else
        result.categoryID, result.dynamicID = -1, -1
        result.registry = {}
        function result:GetChild(category, dynamic)
            for _, child in ipairs(self.children) do
                if not child.destroyed and child.categoryID == category and
                    child.dynamicID == dynamic then return child end
            end
        end
    end
    function result:IterateDynamicComponents(callback)
        for _, child in ipairs(self.children) do
            if not child.destroyed and callback(child, not child.hidden) then return end
        end
    end
    function result:SetPos(x, y)
        self.x, self.y = x, y
    end
    function result:SetSize(width, height, widthAnchor, heightAnchor)
        self.width = width + ((parent and parent.width or 0) * (widthAnchor or 0))
        self.height = height + ((parent and parent.height or 0) * (heightAnchor or 0))
    end
    function result:SetScrollSize(width, height)
        self.scrollWidth, self.scrollHeight = width, height
    end
    function result:SetScrollPos(x, y)
        self.scrollX, self.scrollY = x, y
    end
    function result:Subscribe(hook, idOrCallback, callback)
        self.subscriptions[hook] = callback or idOrCallback
    end
    function result:MoveToFront() moveInRenderOrder(self, true) end
    function result:MoveToBack() moveInRenderOrder(self, false) end
    function result:Destroy()
        if self.destroyed then return end
        for _, child in ipairs(self.children) do child:Destroy() end
        self.destroyed = true
        if parent then
            self.parentStatic.registry[self.categoryID][self.dynamicID] = nil
        end
    end
    Interfaces.component(result, parent, categoryID, dynamicID)
    if parent then
        -- Model native category-first painting rather than insertion order.
        -- Category-zero content precedes managed artwork; among managed
        -- categories the drawing order need not follow allocation order.
        local siblings = parent.renderOrder or {}
        parent.renderOrder = siblings
        local position = #siblings + 1
        local rank = result.categoryID == 0 and 0 or 235 - result.categoryID
        for index, sibling in ipairs(siblings) do
            local siblingRank = sibling.categoryID == 0 and 0 or 235 - sibling.categoryID
            if siblingRank > rank or
                (siblingRank == rank and sibling.dynamicID > result.dynamicID) then
                position = index
                break
            end
        end
        table.insert(siblings, position, result)
    end
    return result
end

local function factory(kind)
    return { new = function(parent, category, dynamic)
        return component(parent, kind, category, dynamic)
    end }
end

ui = {
    Layer = factory("layer"),
    Rectangle = factory("rectangle"),
    Sprite = factory("sprite"),
    Text = factory("text"),
    Hook = {
        ONCLICK = 1,
        ONHOLD = 2,
        ONRELEASE = 3,
        ONSCROLLWHEEL = 4,
        ONMOUSEOVER = 5,
        ONMOUSELEAVE = 6,
    },
    AlignMode = { CENTRE = 1 },
    SelectionChangeEvent = {
        SELECTED = 1,
        DESELECTED = 2,
        ERROR_MAX_SELECTED = 3,
    },
}

id = { Font = { MUSEO_SANS_15PT_REGULAR = 1 } }
config = { Cursor = { CURSOR_TICK = 1 } }

package.loaded["src/core/control_palette"] = {
    TEXT = 1,
    DISABLED_TEXT = 2,
    HOVER = 3,
    SELECTED = 4,
}
package.loaded["src/core/cursor"] = { apply = function() end }
package.loaded["src/core/mouse"] = { GetPosition = function() return nil end }
package.loaded["src/core/sprites"] = {
    SCROLL_ARROW_UP = 1,
    SCROLL_ARROW_DOWN = 2,
    SCROLL_TRACK_TOP = 3,
    SCROLL_TRACK_CENTRE = 4,
    SCROLL_TRACK_BOTTOM = 5,
    SCROLL_THUMB_TOP = 6,
    SCROLL_THUMB_CENTRE = 7,
    SCROLL_THUMB_BOTTOM = 8,
}
package.loaded["src/tooltip"] = {
    bind = function() return nil end,
    set = function() return true end,
    unbind = function() return true end,
}

-- Sample an occupied label point after painting native siblings in category
-- order. Rectangles erase a prior glyph, so this exercises visible text rather
-- than checking which constructors or ordering methods were called.
local function labelAt(root, x, y)
    local painted
    local function paint(node, parentX, parentY)
        if node.hidden or node.destroyed then return end
        local left, top = parentX + node.x, parentY + node.y
        if x >= left and x < left + node.width and
            y >= top and y < top + node.height then
            if node.kind == "rectangle" and node.rgba ~= 0 then
                painted = nil
            elseif node.kind == "text" then
                painted = node.content
            end
        end
        for _, child in ipairs(node.renderOrder or {}) do
            paint(child, left - (node.scrollX or 0), top - (node.scrollY or 0))
        end
    end
    paint(root, 0, 0)
    return painted
end

local List = require("src/list")
local parent = component(nil, "parent")
parent.width = 400
parent.height = 300

local list = List.new(parent, {
    width = 240,
    height = 96,
    entries = {
        { label = "Selected", id = 1, selected = true },
        {
            label = "Enabled",
            id = 2,
            backgroundColour = 10,
            hoverColour = 11,
            selectedColour = 12,
            textColour = 13,
        },
        { label = "Unavailable", id = 3, disabled = true },
        { label = "Fourth", id = 4 },
        { label = "Fifth", id = 5 },
        { label = "Sixth", id = 6 },
    },
})
expect(labelAt(list.root, 12, 13), "Selected",
    "legacy list paints its selected label over list and row backgrounds")
expect(labelAt(list.root, 12, 37), "Enabled",
    "legacy list paints its custom-colour label over its row background")

expect(list.rows[2].background.rgba, 10, "entry background colour renders")
expect(list.rows[2].label.rgba, 13, "entry text colour renders")
list.rows[2].root.subscriptions[ui.Hook.ONMOUSEOVER]()
expect(list.rows[2].background.rgba, 11, "entry hover colour renders")
list.rows[2].root.subscriptions[ui.Hook.ONMOUSELEAVE]()
expect(list.rows[2].background.rgba, 10, "entry background restores after hover")
list.rows[2].root.subscriptions[ui.Hook.ONCLICK]()
expect(list.rows[2].background.rgba, 12, "entry selected colour renders")

local wheel = ui.Hook.ONSCROLLWHEEL
list.rows[1].background.subscriptions[wheel](list.rows[1].background, 1)
expect(list.scrollY, 24, "selected row backgrounds forward wheel scrolling")

list.rows[3].label.subscriptions[wheel](list.rows[3].label, 1)
expect(list.scrollY, 48, "disabled row labels forward wheel scrolling")

list.viewport.subscriptions[wheel](list.viewport, 1)
expect(list.scrollY, 50, "the exposed viewport forwards wheel scrolling to the limit")
list:SetScrollPosition(0)
list:SetEntryIcon(1, 42)
expect(labelAt(list.root, 35, 13), "Selected",
    "legacy list keeps rebuilt labels above backgrounds")

local neighbor = ui.Layer.new(parent)
local large = List.new(parent, { categoryID = "auto", width = 240, height = 96 })
-- The host's direct-child lookup cannot see a raw descendant of the viewport.
local foreign = ui.Text.new(large.viewport, 1, 230)
require("src/core/components").refresh(large.viewport)
local entries = {}
for index = 1, 1400 do
    entries[index] = { id = index, label = "Entry " .. index,
        backgroundColour = 0x24211EFF }
    if index % 10 == 0 then entries[index].icon = 42 end
end
large:SetEntries(entries)
expect(#large.rows, 1400, "large lists mount every requested row")
expect(foreign.destroyed, nil, "nested foreign category ID remains occupied")
expect(large.root.categoryID, 0, "auto list root remains raw-compatible")
expect(large.viewport.categoryID, 0, "auto list viewport remains raw-compatible")
expect(large.rows[1].root.categoryID, 0, "list rows remain raw-compatible")
expect(large.rows[1].label.categoryID > 0, true,
    "row decorations use IDs outside the raw content category")
expect(labelAt(large.root, 12, 13), "Entry 1",
    "auto list paints its label over category-zero viewport and list background")
local categoryBoundaryRow
for _, row in ipairs(large.rows) do
    if row.background.categoryID ~= row.label.categoryID then
        categoryBoundaryRow = row
        break
    end
end
expect(categoryBoundaryRow ~= nil, true, "large list crosses a managed category boundary")
large:SetScrollPosition(categoryBoundaryRow.baseY)
expect(labelAt(large.root, 35, 13), categoryBoundaryRow.entry.text,
    "auto list paints labels over coloured row backgrounds across categories")
large:SetScrollPosition(0)
local rawExtension = ui.Layer.new(large.rows[1].root)
expect(rawExtension.categoryID, 0, "raw row extensions inherit category zero")
large.rows[1400].root.subscriptions[ui.Hook.ONCLICK]()
expect(large.entriesByID[1400].selected, true, "last row can be selected")

local oldRow = large.rows[2].root
large:SetEntryIcon(2, 43)
expect(oldRow.destroyed, true, "rebuild destroys the replaced row")
expect(large.rows[2].label.x > large.rows[1].label.x, true,
    "new icon leaves room before the row label")
expect(labelAt(large.root, 35, 37), "Entry 2",
    "auto list keeps rebuilt icon-row labels above backgrounds")
large:SetEntryVisible(3, false)
expect(#large.rows, 1399, "visibility rebuild excludes the hidden row")
expect(large.rows[3].entry.id, 4, "remaining rows retain their entry order")
expect(labelAt(large.root, 12, 61), "Entry 4",
    "auto list keeps labels visible after a visibility rebuild")
large:Clear()
expect(#large.rows, 0, "clearing releases every row")
expect(foreign.destroyed, nil, "clearing leaves foreign viewport components intact")
expect(neighbor.destroyed, nil, "clearing preserves neighboring widgets")

local retained = {}
for category = 0, 234 do
    for dynamic, component_ in pairs(parent.registry[category] or {}) do
        retained[category .. ":" .. dynamic] = component_
    end
end

local originalTextNew = ui.Text.new
local attempts = 0
ui.Text.new = function(...)
    if select(2, ...) ~= nil then
        attempts = attempts + 1
        if attempts == 4 then error("injected row text failure") end
    end
    return originalTextNew(...)
end
local ok, err = pcall(large.SetEntries, large, entries)
ui.Text.new = originalTextNew
expect(ok, false, "failed row creation propagates")
assert(tostring(err):find("injected row text failure", 1, true), "original constructor error survives")
expect(#large.rows, 0, "failed rebuild rolls back completed rows")
for category = 0, 234 do
    for dynamic, component_ in pairs(parent.registry[category] or {}) do
        local key = category .. ":" .. dynamic
        expect(component_, retained[key], "failed rebuild preserves only preexisting components")
        retained[key] = nil
    end
end
expect(next(retained), nil, "failed rebuild retains all preexisting components")
large:SetEntries(entries)
expect(#large.rows, 1400, "list remounts after a failed rebuild")
expect(labelAt(large.root, 12, 13), "Entry 1",
    "auto list paints labels above backgrounds after a failed rebuild")
large:Destroy()
expect(neighbor.destroyed, nil, "destroying the list preserves neighboring widgets")

local failedEntries = { { id = 1, label = "Row" } }
local failedHost = component(nil, "failed host")
local textNew = ui.Text.new
ui.Text.new = function(...)
    if select(2, ...) ~= nil then error("constructor failed") end
    return textNew(...)
end
local mounted, mountErr = pcall(List.new, failedHost, {
    categoryID = "auto",
    entries = failedEntries,
})
ui.Text.new = textNew
expect(mounted, false, "list constructor propagates a row failure")
assert(tostring(mountErr):find("constructor failed", 1, true), "mount failure survives")
expect(failedHost.children[1].destroyed, true, "failed mount releases the list shell")
for _, ids in pairs(failedHost.registry) do
    expect(next(ids), nil, "failed mount leaves no native components")
end

print("list_test: ok")
