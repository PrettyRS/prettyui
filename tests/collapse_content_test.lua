local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function moveInRenderOrder(component, front)
    local siblings = component.parent and component.parent.renderOrder
    if not siblings then return end
    for index, sibling in ipairs(siblings) do
        if sibling == component then
            table.remove(siblings, index)
            break
        end
    end
    table.insert(siblings, front and #siblings + 1 or 1, component)
end

-- Resolve native size anchors on access, including after an ancestor changes size.
local function component(parent, categoryID, dynamicID)
    local value = {
        parent = parent,
        x = 0,
        y = 0,
        hidden = false,
        subscriptions = {},
        opConfig = { ClearOpCursors = function() end, SetOpCursor = function() end },
        cursorConfig = {},
    }
    setmetatable(value, {
        __index = function(self, key)
            if key == "width" then return (self.w or 0) + (parent and parent.width or 0) * (self.wa or 0) end
            if key == "height" then return (self.h or 0) + (parent and parent.height or 0) * (self.ha or 0) end
        end,
    })
    function value:SetPos(x, y)
        self.x, self.y = x, y
    end
    function value:SetY(y) self.y = y end
    function value:SetSize(w, h, wa, ha)
        self.w, self.h, self.wa, self.ha = w, h, wa, ha
    end
    function value:SetWidth(w, wa)
        self.w, self.wa = w, wa
    end
    function value:SetHeight(h, ha)
        self.h, self.ha = h, ha
    end
    function value:SetScrollSize(w, h)
        self.scrollWidth, self.scrollHeight = w, h
    end
    function value:SetScrollPos(x, y)
        self.scrollX, self.scrollY = x, y
    end
    function value:Subscribe(hook, name, callback) self.subscriptions[hook] = callback or name end
    function value:Unsubscribe(hook) self.subscriptions[hook] = nil end
    function value:MoveToFront() moveInRenderOrder(self, true) end
    function value:MoveToBack() moveInRenderOrder(self, false) end
    function value:Destroy() self.destroyed = true end
    Interfaces.component(value, parent, categoryID, dynamicID)
    if parent then
        -- Exercise a native default order where category-zero content precedes
        -- nonzero artwork, rather than assuming construction order wins.
        local siblings = parent.renderOrder or {}
        parent.renderOrder = siblings
        local position = #siblings + 1
        for index, sibling in ipairs(siblings) do
            if
                sibling.categoryID > value.categoryID
                or (sibling.categoryID == value.categoryID and sibling.dynamicID > value.dynamicID)
            then
                position = index
                break
            end
        end
        table.insert(siblings, position, value)
    end
    return value
end

local enum = setmetatable({}, { __index = function(_, key) return key end })
ui = {
    Layer = { new = component },
    Sprite = { new = component },
    Text = { new = component },
    Rectangle = { new = component },
    Hook = enum,
    AlignMode = enum,
}
id = { Sprite = enum, Font = enum }
ui.ObjectQuantityDisplayMode = enum
local font = {
    baseline = 18,
    GetStringLineCount = function() return 1 end,
    GetStringWidth = function(_, text) return #text * 7 end,
}
config = { Cursor = enum, Font = { MUSEO_SANS_15PT_REGULAR = font, CINZEL_13PT_BOLD = font } }
Keyboard = { IsAvailable = function() return false end }
Event = { Logic = { Subscribe = function() end, Unsubscribe = function() end } }

local SimpleView = require("src/simple_view")
local CollapseButton = require("src/collapse_button")

-- Sections lay their content out like pages, so they offer every Add method a page has except the hosts.
local HOSTS = { AddTabs = true, AddPanel = true, AddCollapseButton = true }
for method, value in pairs(SimpleView) do
    if type(value) == "function" and method:match("^Add") then
        local expected = HOSTS[method] and "nil" or "function"
        expect(type(CollapseButton[method]), expected, method .. " availability in collapse sections")
    end
end

local CONTROL_GAP = 8
local parent = component()
parent:SetSize(1000, 800)
local view = SimpleView.new(parent, { width = 400, height = 600 })
local noop = function() end

local section = view:AddCollapseButton("Everything", { expanded = true })
local controls = {
    section:AddTitle("A title"),
    section:AddSprite(1, {}),
    section:AddSpinner({}),
    section:AddColourPicker({}),
    section:AddItemSlot(nil, {}),
    section:AddDivider({}),
    section:AddTimeGraph({ metric = { id = "gold" } }),
    section:AddBarChart({}),
    section:AddSpriteButton("menu", noop, {}),
}
local dataTable = section:AddTable({ columns = { { key = "a", title = "A" } }, rows = {} })
local last = section:AddSimpleButton("Last", noop)
controls[#controls + 1] = dataTable
controls[#controls + 1] = last

local function rootOf(control) return control.root or control end
for index = 2, #controls do
    local previous, current = rootOf(controls[index - 1]), rootOf(controls[index])
    expect(
        current.y >= previous.y + previous.height,
        true,
        "section control " .. index .. " stacks below the one before"
    )
end
expect(section.contentHeight, last.root.y + last.root.height, "the section fits its last control")

local lastY = last.root.y
dataTable:SetSize(nil, dataTable.height + 50)
expect(last.root.y, lastY + 50, "a table that grows moves the controls below it")
expect(section.contentHeight, last.root.y + last.root.height, "the section grows with its table")

-- Controls placed with an explicit y still push later controls down, as sections always have.
local positioned = view:AddCollapseButton("Positioned", { expanded = true })
positioned:AddSimpleButton("Top", noop)
local placed = positioned:AddSimpleButton("Placed", noop, { y = 60 })
local afterPlaced = positioned:AddSimpleButton("After", noop)
expect(
    afterPlaced.root.y,
    placed.root.y + placed.root.height + CONTROL_GAP,
    "a control placed with y pushes the next down"
)

-- Destroying a control re-flows the section.
local removable = view:AddCollapseButton("Removable", { expanded = true })
local first = removable:AddSimpleButton("First", noop)
local second = removable:AddSimpleButton("Second", noop)
first:Destroy()
expect(second.root.y, 0, "destroying a control moves the next one up")

-- Text anchored to its parent's height keeps the same content height however often the layout re-flows,
-- in a section and on a page taller than its view.
local anchoredSection = view:AddCollapseButton("Anchored", { expanded = true })
anchoredSection:AddText({ text = "Anchored", heightAnchor = 0.5 })
anchoredSection:AddSimpleButton("Below", noop)
local tallView = SimpleView.new(parent, { width = 400, height = 200 })
tallView:AddText({ text = "Filler", height = 400 })
tallView:AddText({ text = "Anchored", heightAnchor = 0.5 })
local sectionHeight, pageHeight = anchoredSection.contentHeight, tallView.contentHeight
for _ = 1, 3 do
    view:RefreshLayout()
    tallView:RefreshLayout()
end
expect(anchoredSection.contentHeight, sectionHeight, "anchored text doesn't grow a section on re-flow")
expect(tallView.contentHeight, pageHeight, "anchored text doesn't grow a page on re-flow")

print("collapse_content_test: ok")
