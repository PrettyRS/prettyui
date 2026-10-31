local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local constructed = 0
local loaded = {}
local function pair(category, dynamic)
    return category .. ":" .. dynamic
end

local function host(interfaceID)
    local static = {
        interfaceID = interfaceID, categoryID = -1, dynamicID = -1,
        width = 1000, height = 800, children = {}, registry = {}, virtual = {},
        subscriptions = {},
    }
    loaded[interfaceID] = static
    -- This client double deliberately only resolves direct children.
    function static:GetChild(category, dynamic)
        if self.virtual[pair(category, dynamic)] then return self.virtual[pair(category, dynamic)] end
        for _, child in ipairs(self.children) do
            if not child.destroyed and child.categoryID == category and child.dynamicID == dynamic then
                return child
            end
        end
    end
    function static:IterateDynamicComponents(callback)
        self.scans = (self.scans or 0) + 1
        for _, child in ipairs(self.children) do
            if not child.destroyed and callback(child, not child.hidden) then return end
        end
    end
    function static:Subscribe(hook, name, callback)
        self.subscriptions[hook] = callback or name
    end
    function static:Unsubscribe(hook) self.subscriptions[hook] = nil end
    return static
end

local function component(parent, categoryID, dynamicID, kind)
    constructed = constructed + 1
    local static = parent.parentStatic or parent
    if static.rejectExplicitStatic and parent == static and categoryID ~= nil then
        error("categorized constructor on static parent", 0)
    end
    local category = categoryID or (parent.categoryID == -1 and 0 or parent.categoryID)
    local dynamic = dynamicID or parent.dynamicID + 1
    if dynamicID == nil then
        while static.registry[pair(category, dynamic)] or static.virtual[pair(category, dynamic)] do
            dynamic = dynamic + 1
        end
    end
    assert(category >= 0 and category <= 234 and dynamic >= 0 and
        dynamic <= (category == 0 and 4095 or 234), "native ID capacity exceeded")
    local key = pair(category, dynamic)
    assert(not static.registry[key] and not static.virtual[key], "native ID collision: " .. key)
    local result = {
        parent = parent, parentStatic = static, interfaceID = static.interfaceID,
        categoryID = category, dynamicID = dynamic, kind = kind,
        children = {}, subscriptions = {}, x = 0, y = 0, width = 0, height = 0,
        hidden = false, cursorConfig = {},
        opConfig = { ClearOpCursors = function() end, SetOpCursor = function() end },
    }
    static.registry[key] = result
    parent.children[#parent.children + 1] = result
    function result:IterateDynamicComponents(callback)
        for _, child in ipairs(self.children) do
            if not child.destroyed and callback(child, not child.hidden) then return end
        end
    end
    function result:SetPos(x, y, xAnchor, yAnchor)
        self.x = x + parent.width * (xAnchor or 0)
        self.y = y + parent.height * (yAnchor or 0)
    end
    function result:SetSize(width, height, widthAnchor, heightAnchor)
        self.width = width + parent.width * (widthAnchor or 0)
        self.height = height + parent.height * (heightAnchor or 0)
    end
    function result:SetWidth(width, anchor) self.width = width + parent.width * (anchor or 0) end
    function result:SetHeight(height, anchor) self.height = height + parent.height * (anchor or 0) end
    function result:SetScrollSize(width, height)
        self.scrollWidth, self.scrollHeight = width, height
    end
    function result:SetScrollPos(x, y) self.scrollX, self.scrollY = x, y end
    function result:Subscribe(hook, name, callback) self.subscriptions[hook] = callback or name end
    function result:Unsubscribe(hook) self.subscriptions[hook] = nil end
    function result:MoveToFront() end
    function result:MoveToBack() end
    function result:Destroy()
        if self.destroyed then return end
        for _, child in ipairs(self.children) do child:Destroy() end
        self.destroyed = true
        if static.registry[key] == self then static.registry[key] = nil end
    end
    return result
end

local function factory(kind)
    return { new = function(parent, category, dynamic)
        return component(parent, category, dynamic, kind)
    end }
end
local function namespace()
    return setmetatable({}, { __index = function(table_, field)
        local value = 1
        rawset(table_, field, value)
        return value
    end })
end
local enum = setmetatable({}, { __index = function(_, field) return field end })
ui = {
    Layer = factory("layer"), Text = factory("text"), Sprite = factory("sprite"),
    Rectangle = factory("rectangle"), Button = factory("button"),
    Hook = enum, AlignMode = enum, ComponentType = enum,
    SelectionChangeEvent = { SELECTED = 1, DESELECTED = 2, ERROR_MAX_SELECTED = 3 },
    Interfaces = { GetInterface = function(_, interfaceID) return loaded[interfaceID] end },
}
id = setmetatable({}, { __index = function(table_, field)
    local value = namespace()
    rawset(table_, field, value)
    return value
end })
config = {
    Cursor = enum,
    Font = { MUSEO_SANS_15PT_REGULAR = {
        baseline = 18, GetStringLineCount = function() return 1 end,
        GetStringWidth = function(_, text) return #text * 7 end,
    } },
}
config.Font.CINZEL_13PT_BOLD = config.Font.MUSEO_SANS_15PT_REGULAR
Plugin = { resources = {} }
Keyboard = { IsAvailable = function() return false end }
Event = { Logic = { Subscribe = function() end, Unsubscribe = function() end } }
package.loaded["src/ribbon_bar"] = { Start = function() end, Shutdown = function() end }
package.loaded["src/minimenu"] = { Start = function() end, Shutdown = function() end }

local prettyui = require("main")
local occupied = host(1)
for dynamic = 0, 4049 do occupied.virtual[pair(0, dynamic)] = true end
occupied.virtual[pair(1, 6)] = true
local oldRows = {}
local oldFailure
for index = 1, 250 do
    local root
    local ok, err = pcall(function()
        root = ui.Layer.new(occupied)
        for _ = 1, 5 do ui.Text.new(root) end
    end)
    if root then oldRows[#oldRows + 1] = root end
    if not ok then oldFailure = err; break end
end
assert(oldFailure and oldFailure:find("native ID capacity exceeded", 1, true),
    "native-default six-component rows must hit category zero")
for _, root in ipairs(oldRows) do root:Destroy() end

local neighbor = ui.Layer.new(occupied, 2, 0)
local window = prettyui.Window.new(occupied, { title = "Capacity", width = 400, height = 230 })
local rawRows = {}
local firstClick, lastClick
for index = 1, 250 do
    local row = prettyui.NewComponent(ui.Layer, window.content)
    rawRows[index] = row
    for _ = 1, 4 do prettyui.NewComponent(ui.Text, row) end
    local button = prettyui.NewComponent(ui.Button, row)
    button:Subscribe(ui.Hook.ONCLICK, function()
        if index == 1 then firstClick = true end
        if index == 250 then lastClick = true end
    end)
end
rawRows[1].children[5].subscriptions[ui.Hook.ONCLICK]()
rawRows[250].children[5].subscriptions[ui.Hook.ONCLICK]()
expect(firstClick, true, "first raw row remains clickable")
expect(lastClick, true, "last raw row remains clickable")
expect(rawRows[250].categoryID > 0, true, "raw rows cross category zero")
expect(neighbor.destroyed, nil, "mixed-owner neighbor survives raw rows")

local choices = {}
for index = 1, 250 do choices[index] = { label = "Choice " .. index, value = index } end
local checkbox = window:AddCheckboxButton(choices)
checkbox.items[1].row.subscriptions[ui.Hook.ONCLICK]()
checkbox.items[250].row.subscriptions[ui.Hook.ONCLICK]()
expect(checkbox.items[1].selected, true, "first PrettyUI checkbox can be selected")
expect(checkbox.items[250].selected, true, "last PrettyUI checkbox can be selected")
expect(checkbox.items[250].row.categoryID > 0, true, "nested PrettyUI rows cross category zero")
window:AddText({ text = "After choices", height = 24 })
window:SetScrollPosition(100000)
expect(window.scrollY > 0, true, "window scroll reaches populated content")

local view = prettyui.SimpleView.new(occupied, { height = 200, width = 300 })
local viewChoice = view:AddCheckboxButton({ { label = "Visible", value = 1 } })
viewChoice.items[1].row.subscriptions[ui.Hook.ONCLICK]()
expect(viewChoice.items[1].selected, true, "simple view row can be selected")
expect(viewChoice.items[1].row.categoryID > 0, true, "simple view rows receive allocated IDs")
local panel = prettyui.Panel.new(occupied, { width = 300, height = 200 })
local pairChoice = panel:AddCheckboxButton({ { label = "Dock", value = 1 } })
expect(pairChoice.dock.items[1].row.categoryID > 0, true, "panel dock child is allocated")
expect(pairChoice.overlay.items[1].row.categoryID > 0, true, "panel overlay child is allocated")

local pairsSeen = {}
for key in pairs(occupied.registry) do
    expect(pairsSeen[key], nil, "all window, panel, view and raw pairs are unique")
    pairsSeen[key] = true
    local category, dynamic = key:match("^(%d+):(%d+)$")
    category, dynamic = tonumber(category), tonumber(dynamic)
    assert(category <= 234 and dynamic <= (category == 0 and 4095 or 234),
        "no allocation crosses the native ID boundary")
end
local second = host(1)
local independent = prettyui.NewComponent(ui.Layer, second)
expect(independent.categoryID, 0, "two static parents sharing an interface start independently")
expect(independent.dynamicID, 0, "second static parent has its own cursor")

for _, row in ipairs(rawRows) do row:Destroy() end
panel:Destroy()
view:Destroy()
window:Destroy()
expect(neighbor.destroyed, nil, "destroy and rebuild preserve other owners")
local remounted = prettyui.Window.new(occupied, { width = 320, height = 200 })
remounted:AddText({ text = "Remounted", height = 24 })
expect(remounted.root.destroyed, nil, "window remount succeeds")
remounted:Destroy()

local nestedHost = host(3)
local container = ui.Layer.new(nestedHost, 0, 0)
local nestedForeign = ui.Text.new(container, 1, 0)
local skipped = prettyui.NewComponent(ui.Text, container)
expect(skipped.dynamicID, 1, "recursive scan skips an invisible-to-GetChild nested occupant")
expect(nestedForeign.destroyed, nil, "nested foreign component is preserved")

local saturated = host(4)
local saturatedParent = ui.Layer.new(saturated, 0, 0)
for dynamic = 1, 4095 do saturated.virtual[pair(0, dynamic)] = true end
for category = 1, 234 do
    for dynamic = 0, 234 do saturated.virtual[pair(category, dynamic)] = true end
end
local before = constructed
local full, diagnostic = pcall(prettyui.NewComponent, ui.Text, saturatedParent)
expect(full, false, "exhaustion rejects before native construction")
expect(diagnostic:sub(-#"PrettyUI: no dynamic component IDs available on this static parent; page or reuse components"),
    "PrettyUI: no dynamic component IDs available on this static parent; page or reuse components",
    "exhaustion has the exact capacity diagnostic")
expect(constructed, before, "exhaustion does not call a native constructor")
saturated.virtual[pair(234, 234)] = nil
local failure = "native constructor failed"
local broken = { new = function() error(failure, 0) end }
local ok, err = pcall(prettyui.NewComponent, broken, saturatedParent)
expect(ok, false, "other native errors propagate")
expect(err, failure, "original constructor error is unchanged")
local rescued = prettyui.NewComponent(ui.Text, saturatedParent)
expect(rescued.categoryID, 234, "freed final category can be used")
expect(rescued.dynamicID, 234, "freed final ID can be used")
rescued:Destroy()
local reused = prettyui.NewComponent(ui.Text, saturatedParent)
expect(reused.dynamicID, 234, "destroyed final ID is reused on wrapped search")

local rollbackHost = host(5)
local originalSpriteNew = ui.Sprite.new
local spriteCalls = 0
ui.Sprite.new = function(...)
    spriteCalls = spriteCalls + 1
    if spriteCalls == 3 then error("frame constructor failed", 0) end
    return originalSpriteNew(...)
end
local rolledBack, rollbackError = pcall(prettyui.Window.new, rollbackHost, { title = "Rollback" })
ui.Sprite.new = originalSpriteNew
expect(rolledBack, false, "failed window constructor reports an error")
expect(rollbackError, "frame constructor failed", "failed constructor preserves native error")
expect(next(rollbackHost.registry), nil, "batch destroys partially built window components")
local recoveredWindow = prettyui.Window.new(rollbackHost, { title = "Recovered" })
expect(recoveredWindow.root.destroyed, nil, "the same parent can mount after a failed build")
recoveredWindow:Destroy()

local strictHost = host(6)
strictHost.rejectExplicitStatic = true
local strictWindow = prettyui.Window.new(strictHost, { title = "Static-parent window" })
expect(strictWindow.root.categoryID, 0, "static window root uses native category")
local strictTabs = strictWindow:AddTabs({ "First", "Second" }, { height = 100 })
local strictPage = strictTabs:GetPage(1)
local rawLayer = ui.Layer.new(strictPage.content)
prettyui.RefreshComponentIDs(strictPage.content)
expect(rawLayer.destroyed, nil, "native row remains usable under managed tab content")
local strictView = prettyui.SimpleView.new(strictHost, { width = 300, height = 200 })
local strictPanel = prettyui.Panel.new(strictHost, { width = 300, height = 200 })
expect(strictPanel.dock.root.categoryID, 0, "static panel dock root uses native IDs")
local scansAfterMount = strictHost.scans
for index = 1, 60 do
    strictWindow:AddText({ text = "Gallery item " .. index })
end
expect(strictHost.scans, scansAfterMount, "adding gallery widgets reuses occupancy snapshot")
strictPanel:Destroy()
strictView:Destroy()
strictWindow:Destroy()
local reopened = prettyui.Window.new(strictHost, { title = "Reopened static-parent window" })
for index = 1, 60 do
    reopened:AddText({ text = "Reopened item " .. index })
end
expect(strictHost.scans, scansAfterMount, "reopening does not rescan the whole host per widget")
reopened:Destroy()

local mixedHost = host(7)
local mixedParent = ui.Layer.new(mixedHost)
require("src/core/components").withBatch(mixedParent, function()
    local first = prettyui.NewComponent(ui.Text, mixedParent)
    local foreign = ui.Text.new(mixedParent, 1, first.dynamicID + 1)
    prettyui.RefreshComponentIDs(mixedParent)
    local following = prettyui.NewComponent(ui.Text, mixedParent)
    expect(following.dynamicID, foreign.dynamicID + 1,
        "refresh during a batch includes newly inserted unmanaged descendants")
end)

local zeroCategoryStatic = host(8)
zeroCategoryStatic.categoryID = 0
zeroCategoryStatic.rejectExplicitStatic = true
local zeroCategoryWindow = prettyui.Window.new(zeroCategoryStatic, {
    title = "Static parent reporting category zero",
})
expect(zeroCategoryWindow.root.categoryID, 0,
    "category-zero static parent also uses native root allocation")
zeroCategoryWindow:Destroy()

print("category_capacity_test: ok")
