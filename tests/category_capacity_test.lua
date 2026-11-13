local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local constructed = 0
local loaded = {}
local namespaces = {}
local nextStaticID = 0
local function pair(category, dynamic)
    return category .. ":" .. dynamic
end

local function host(interfaceID)
    nextStaticID = nextStaticID + 1
    local static = {
        interfaceID = interfaceID, staticID = nextStaticID, categoryID = -1, dynamicID = -1,
        width = 1000, height = 800, children = {}, registry = {}, virtual = {},
        subscriptions = {},
    }
    loaded[interfaceID] = static
    namespaces[interfaceID] = namespaces[interfaceID] or {}
    namespaces[interfaceID][static.staticID] = static
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
    local static = parent.categoryID == -1 and parent or parent.parentStatic or parent
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
        staticID = static.staticID,
        children = {}, subscriptions = {}, x = 0, y = 0, width = 0, height = 0,
        hidden = false, cursorConfig = {}, text = {},
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
    function result:SetAssociatedObject(objectID) self.associatedObject = objectID end
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
    ObjectQuantityDisplayMode = enum,
    SelectionChangeEvent = { SELECTED = 1, DESELECTED = 2, ERROR_MAX_SELECTED = 3 },
    Interfaces = {
        GetInterface = function(_, interfaceID) return loaded[interfaceID] end,
        GetComponent = function(_, interfaceID, staticID, categoryID, dynamicID)
            local static = namespaces[interfaceID] and namespaces[interfaceID][staticID]
            if not loaded[interfaceID] or not static then return nil end
            if categoryID == nil then return static end
            return static.registry[pair(categoryID, dynamicID)] or
                static.virtual[pair(categoryID, dynamicID)]
        end,
    },
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
Event = {
    Logic = { Subscribe = function() end, Unsubscribe = function() end },
    VarTransmit = { Subscribe = function() end, Unsubscribe = function() end },
}
var = { VarPlayer = { TOPLEVEL_V2_LEGACY_INTERFACE = { value = 0 } } }
id.VarPlayer = { TOPLEVEL_V2_GENERAL_VARP = 14 }
PersistentDB = {
    GetString = function() return "left" end,
    GetBool = function() return false end,
}
package.loaded["src/minimenu"] = { Start = function() end, Shutdown = function() end }

local prettyui = require("main")
local occupied = host(1)
for dynamic = 0, 4049 do occupied.virtual[pair(0, dynamic)] = true end
occupied.virtual[pair(1, 6)] = true
local neighbor = ui.Layer.new(occupied, 2, 0)
local window = prettyui.Window.new(occupied, { categoryID = "auto", title = "Capacity", width = 400, height = 230 })
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

local view = prettyui.SimpleView.new(occupied, { categoryID = "auto", height = 200, width = 300 })
local viewChoice = view:AddCheckboxButton({ { label = "Visible", value = 1 } })
viewChoice.items[1].row.subscriptions[ui.Hook.ONCLICK]()
expect(viewChoice.items[1].selected, true, "simple view row can be selected")
expect(viewChoice.items[1].row.categoryID > 0, true, "simple view rows receive allocated IDs")
local panel = prettyui.Panel.new(occupied, { categoryID = "auto", width = 300, height = 200 })
local pairChoice = panel:AddCheckboxButton({ { label = "Dock", value = 1 } })
expect(pairChoice.dock.items[1].row.categoryID > 0, true, "panel dock child is allocated")
expect(pairChoice.overlay.items[1].row.categoryID > 0, true, "panel overlay child is allocated")

local second = host(1)
local independent = prettyui.NewComponent(ui.Layer, second)
assert(independent.categoryID == 0 and independent.dynamicID == 0,
    "static parents sharing an interface allocate independently")

for _, row in ipairs(rawRows) do row:Destroy() end
panel:Destroy()
view:Destroy()
window:Destroy()
expect(neighbor.destroyed, nil, "destroy and rebuild preserve other owners")
local remounted = prettyui.Window.new(occupied, { categoryID = "auto", width = 320, height = 200 })
remounted:AddText({ text = "Remounted", height = 24 })
expect(remounted.root.destroyed, nil, "window remount succeeds")
remounted:Destroy()

local nestedHost = host(3)
local container = ui.Layer.new(nestedHost, 0, 0)
local nestedForeign = ui.Text.new(container, 1, 0)
local skipped = prettyui.NewComponent(ui.Text, container, { categoryID = "auto" })
expect(skipped.dynamicID, 1, "recursive scan skips an invisible-to-GetChild nested occupant")
expect(nestedForeign.destroyed, nil, "nested foreign component is preserved")

local saturated = host(4)
local saturatedParent = ui.Layer.new(saturated, 0, 0)
for dynamic = 1, 4095 do saturated.virtual[pair(0, dynamic)] = true end
for category = 1, 234 do
    for dynamic = 0, 234 do saturated.virtual[pair(category, dynamic)] = true end
end
local before = constructed
local full = pcall(prettyui.NewComponent, ui.Text, saturatedParent, { categoryID = "auto" })
expect(full, false, "exhaustion rejects before native construction")
expect(constructed, before, "exhaustion does not call a native constructor")
saturated.virtual[pair(234, 234)] = nil
local failure = "native constructor failed"
local broken = { new = function() error(failure, 0) end }
local ok, err = pcall(prettyui.NewComponent, broken, saturatedParent, { categoryID = "auto" })
expect(ok, false, "other native errors propagate")
expect(err, failure, "original constructor error is unchanged")
local rescued = prettyui.NewComponent(ui.Text, saturatedParent, { categoryID = "auto" })
expect(rescued.categoryID, 234, "freed final category can be used")
expect(rescued.dynamicID, 234, "freed final ID can be used")
rescued:Destroy()
local reused = prettyui.NewComponent(ui.Text, saturatedParent, { categoryID = "auto" })
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
do
    local static = host(9)
    local calls = 0
    ui.Sprite.new = function(...)
        calls = calls + 1
        if calls == 3 then error("auto frame constructor failed", 0) end
        return originalSpriteNew(...)
    end
    local success, message = pcall(prettyui.Window.new, static, { categoryID = "auto" })
    ui.Sprite.new = originalSpriteNew
    expect(success, false, "automatic window propagates native failure")
    expect(message, "auto frame constructor failed", "automatic rollback retains original error")
    expect(next(static.registry), nil, "automatic batch releases its structural and managed components")
end

local strictHost = host(6)
strictHost.rejectExplicitStatic = true
local strictWindow = prettyui.Window.new(strictHost, { categoryID = "auto", title = "Static-parent window" })
expect(strictWindow.root.categoryID, 0, "static window root uses native category")
local strictPage = strictWindow:AddTabs({ "First", "Second" }, { height = 100 }):GetPage(1)
local rawLayer = ui.Layer.new(strictPage.content)
prettyui.RefreshComponentIDs(strictPage.content)
expect(rawLayer.destroyed, nil, "native row remains usable under managed tab content")
local strictView = prettyui.SimpleView.new(strictHost, { categoryID = "auto", width = 300, height = 200 })
local strictPanel = prettyui.Panel.new(strictHost, { categoryID = "auto", width = 300, height = 200 })
expect(strictPanel.dock.root.categoryID, 0, "static panel dock root uses native IDs")
strictPanel:Destroy()
strictView:Destroy()
strictWindow:Destroy()

local mixedHost = host(7)
local mixedParent = ui.Layer.new(mixedHost)
require("src/core/components").withBatch(mixedParent, function()
    local first = prettyui.NewComponent(ui.Text, mixedParent, { categoryID = "auto" })
    local foreign = ui.Text.new(mixedParent, 1, first.dynamicID + 1)
    prettyui.RefreshComponentIDs(mixedParent)
    local following = prettyui.NewComponent(ui.Text, mixedParent, { categoryID = "auto" })
    expect(following.dynamicID, foreign.dynamicID + 1,
        "refresh during a batch includes newly inserted unmanaged descendants")
end)

-- Legacy positional APIs preserve native identity; an opted-in sibling cannot
-- change a supplied host's allocation policy.
do
    for _, category in ipairs({ 0, 7 }) do
        local static = host(20 + category)
        local parent = ui.Layer.new(static, category, 0)
        local legacy = prettyui.Window.new(parent, { title = "Unchanged" })
        expect(legacy.root.categoryID, category, "legacy window inherits its physical parent")
        expect(legacy:AddText("String form").categoryID, category, "AddText string remains valid")
        local view_ = prettyui.SimpleView.new(parent)
        expect(view_.content.categoryID, category, "legacy view content inherits")
        view_:Destroy()
        local panel_ = prettyui.Panel.new(parent, { width = 300, height = 200 })
        expect(panel_.dock.root.categoryID, category, "legacy panel dock inherits")
        expect(panel_.overlay.root.categoryID, category, "legacy panel overlay inherits")
        panel_:Destroy()
        legacy:Destroy()
        parent:Destroy()
    end
end
local nativeFailure = "legacy native constructor failed"
local legacySuccess, legacyError = pcall(prettyui.NewComponent,
    { new = function() error(nativeFailure, 0) end }, host(29))
expect(legacySuccess, false, "legacy native construction failure propagates")
expect(legacyError, nativeFailure, "legacy constructor preserves native error")

do
    local static = host(30)
    local auto = prettyui.Window.new(static, { categoryID = "auto" })
    local legacy = prettyui.Window.new(static)
    for _, content in ipairs({ auto.root, auto.content, auto._scroll.root, auto._scroll.viewport }) do
        expect(content.categoryID, 0, "automatic Window structural spine remains category zero")
    end
    expect(ui.Text.new(auto.content, auto.root.categoryID).categoryID, 0,
        "native extensions keep the category-zero content namespace")
    local foreignLayer = ui.Layer.new(auto.content)
    expect(prettyui.Text.new(foreignLayer, { text = "Late" }).categoryID > 0, true,
        "ancestor policy passes through foreign native layers")
    expect(legacy:AddText("Still legacy").categoryID, 0, "auto sibling does not relabel shared host")
    local collapse = auto:AddCollapseButton("Section", { expanded = true })
    expect(collapse.root.categoryID, 0, "auto CollapseButton root is raw-compatible")
    expect(collapse.content.categoryID, 0, "auto CollapseButton content is raw-compatible")
    expect(collapse:AddText("Nested").categoryID > 0, true, "nested controls retain auto policy")
    local tabs = auto:AddTabs({ "One" }, { height = 100 })
    expect(tabs:GetPage(1).root.categoryID, 0, "auto Tabs pages are raw-compatible")
    expect(tabs:GetPage(1):AddText("Page").categoryID > 0, true, "page children remain managed")
    auto:Destroy()
    legacy:Destroy()
end

-- Every fresh explicit candidate sees raw mutations without an explicit refresh.
do
    local C = require("src/core/components")
    local fullLookup = ui.Interfaces.GetComponent
    for _, mode in ipairs({ "full", "unresolved" }) do
        local static = host(31)
        local parent = ui.Layer.new(static)
        if mode == "unresolved" then
            ui.Interfaces.GetComponent = function() return nil end
        end
        local first = C.new(ui.Text, parent, { categoryID = "auto" })
        ui.Text.new(ui.Layer.new(parent), first.categoryID, first.dynamicID + 1)
        local next_ = C.new(ui.Text, parent, { categoryID = "auto" })
        expect(next_.dynamicID, first.dynamicID + 2, "fresh lookup skips nested raw occupancy: " .. mode)
        ui.Text.new(ui.Layer.new(static), next_.categoryID, next_.dynamicID + 1)
        C.withBatch(parent, function()
            local allocated = C.new(ui.Text, parent, { categoryID = "auto" })
            expect(allocated.dynamicID, next_.dynamicID + 2, "foreign siblings share the full namespace")
            local raw = ui.Text.new(parent, allocated.categoryID, allocated.dynamicID + 1)
            local afterRaw = C.new(ui.Text, parent, { categoryID = "auto" })
            expect(afterRaw.dynamicID, raw.dynamicID + 1, "active batches still check fresh native occupancy")
        end)
        ui.Interfaces.GetComponent = fullLookup
    end
end

-- Different Lua handles can identify the same native parent. Lookups and
-- iteration must still protect components created through the original handle.
do
    local C = require("src/core/components")
    local fullLookup = ui.Interfaces.GetComponent
    for _, mode in ipairs({ "full", "unresolved" }) do
        local static = host(46)
        local parent = ui.Layer.new(static)
        local foreign = ui.Text.new(parent, 1, 0)
        foreign.content = "Other plugin"
        local staticAlias = setmetatable({}, { __index = static })
        local parentAlias = setmetatable({ parentStatic = staticAlias }, { __index = parent })
        if mode == "unresolved" then ui.Interfaces.GetComponent = function() return nil end end
        local control = C.new(ui.Text, parentAlias, { categoryID = "auto" })
        control.content = "This plugin"
        expect(static.registry[pair(foreign.categoryID, foreign.dynamicID)].content, "Other plugin",
            "aliased parent preserves the other plugin's control: " .. mode)
        expect(static.registry[pair(control.categoryID, control.dynamicID)].content, "This plugin",
            "aliased parent creates a separately addressable control: " .. mode)
        control:Destroy()
        expect(foreign.destroyed, nil, "aliased allocation cleanup cannot destroy a foreign control")
        ui.Interfaces.GetComponent = fullLookup
    end
end

-- A static component can have a static ancestor without sharing its namespace.
do
    local ancestor = host(47)
    local area = host(47)
    area.parent, area.parentStatic = ancestor, ancestor
    local foreignRoot = ui.Layer.new(area)
    local foreign = ui.Sprite.new(foreignRoot, 1, 0)
    foreign.content = "Existing plugin"
    local window = prettyui.Window.new(area, { categoryID = "auto", title = "Static descendant" })
    local text = window:AddText("Independent window")
    expect(text.parentStatic, area, "managed content uses the supplied static area's namespace")
    expect(area.registry[pair(1, 0)], foreign, "managed construction preserves another plugin's sprite")
    expect(next(ancestor.registry), nil, "managed construction does not allocate in the static ancestor")
    window:Destroy()
    expect(foreign.content, "Existing plugin", "destroying the new window preserves existing content")
    local grouped = prettyui.BuildCategoryGroup(area, 1, function(new)
        return new(ui.Text, foreignRoot)
    end)
    grouped.content = "Reserved group"
    expect(grouped.parentStatic, area, "reserved groups use the supplied static area's namespace")
    expect(area.registry[pair(1, 0)], foreign, "reserved groups preserve the existing plugin's slot")
    grouped:Destroy()
    foreignRoot:Destroy()
end

do
    local C = require("src/core/components")
    for _, ids in ipairs({ { 7, 234 }, { 0, 4095 } }) do
        local static = host(33)
        local parent = ui.Layer.new(static, ids[1], ids[2])
        local count = constructed
        local success = pcall(C.new, ui.Text, parent)
        expect(success, false, "inherited boundary rejects before native entry")
        expect(constructed, count, "known-impossible inherited construction never enters native")
    end
    for _, ids in ipairs({ { 235, 0 }, { 7, -1 }, { 7, 235 }, { 0, 4096 }, { 7.5, 0 }, { 7, 0.5 } }) do
        local static = host(43)
        local invalid = ui.Layer.new(static)
        invalid.categoryID, invalid.dynamicID = ids[1], ids[2]
        local count = constructed
        local success = pcall(C.new, ui.Text, invalid)
        expect(success, false, "invalid inherited numeric identity is rejected")
        expect(constructed, count, "invalid parent identity never enters native")
    end
    local static = host(34)
    local parent = ui.Layer.new(static, 7, 230)
    for dynamic = 231, 234 do static.virtual[pair(7, dynamic)] = true end
    local count = constructed
    local success = pcall(C.new, ui.Text, parent)
    expect(success, false, "occupied inherited suffix cannot silently escape category")
    expect(constructed, count, "full inherited suffix avoids native entry")
    local empty = host(35)
    for dynamic = 0, 4095 do empty.virtual[pair(0, dynamic)] = true end
    count = constructed
    success = pcall(prettyui.Window.new, empty, { categoryID = "auto" })
    expect(success, false, "full category zero does not relocate automatic content")
    expect(constructed, count, "full zero pool rejects before root native construction")
    local nonzero = ui.Layer.new(host(36), 7, 0)
    for _, constructor in ipairs({
        function() return prettyui.Window.new(nonzero, { categoryID = "auto" }) end,
        function() return prettyui.SimpleView.new(nonzero, { categoryID = "auto" }) end,
        function() return prettyui.Tabs.new(nonzero, { "Page" }, { categoryID = "auto" }) end,
        function() return prettyui.CollapseButton.new(nonzero, "Section", { categoryID = "auto" }) end,
        function() return prettyui.List.new(nonzero, { categoryID = "auto" }) end,
        function() return prettyui.Panel.new(nonzero, { categoryID = "auto" }) end,
    }) do
        count = constructed
        success = pcall(constructor)
        expect(success, false, "auto content rejects a dynamic nonzero mount")
        expect(constructed, count, "invalid mount rejects before creating the subtree")
    end
    local clean = host(37)
    count = constructed
    success = pcall(prettyui.Panel.new, clean, { categoryID = "auto", overlayParent = nonzero })
    expect(success, false, "invalid Panel overlay is rejected")
    expect(constructed, count, "invalid overlay leaves no dock surface")
    success = pcall(require("src/ordered_combo_box").new, clean, { categoryID = "auto", overlayParent = nonzero })
    expect(success, false, "invalid combo dropdown mount is rejected")
    expect(constructed, count, "invalid combo dropdown leaves no shell")
    -- Permit the first structural root, then fail its viewport preflight.
    local tiny = host(38)
    for dynamic = 1, 4095 do tiny.virtual[pair(0, dynamic)] = true end
    success = pcall(prettyui.SimpleView.new, tiny, { categoryID = "auto" })
    expect(success, false, "later content capacity rejection propagates")
    expect(next(tiny.registry), nil, "direct constructor rolls back its earlier structural layers")
    local blind = host(39)
    local dynamic = ui.Layer.new(blind)
    blind.IterateDynamicComponents = nil
    local lookup = ui.Interfaces.GetComponent
    ui.Interfaces.GetComponent = nil
    count = constructed
    success = pcall(C.new, ui.Text, dynamic, { categoryID = "auto" })
    ui.Interfaces.GetComponent = lookup
    expect(success, false, "allocation fails closed without authoritative namespace lookup")
    expect(constructed, count, "missing complete lookup never attempts explicit native allocation")
end

do
    local savedMouse = Mouse
    Mouse = { GetPosition = function() return { x = 5, y = 5 } end }
    local C = require("src/core/components")
    local static = host(45)
    local parent = ui.Layer.new(static)
    local overlay = C.newContent(static, { categoryID = "auto" })
    prettyui.Tooltip.registerContext(parent, overlay, function(target)
        return target.x, target.y
    end)
    for _, automatic in ipairs({ true, false }) do
        local grid = prettyui.ItemGrid.new(parent, { { id = 42, name = "Item" } }, {
            categoryID = automatic and "auto" or nil,
            columns = 2, rows = 1, dragDrop = true,
        })
        expect(grid.dragCapture, nil, "ItemGrid capture remains lazy before drag")
        grid.slots[1].root.subscriptions[ui.Hook.ONCLICK]()
        expect(grid.dragCapture.parent, overlay, "drag capture mounts under resolved overlay")
        expect(grid.dragCapture.categoryID > 0, automatic,
            "detached capture follows owner, not an already-auto overlay")
        expect(grid.dragSprite.categoryID > 0, automatic,
            "floating item follows its logical owner")
        local capture = grid.dragCapture
        grid.dragCapture.subscriptions[ui.Hook.ONRELEASE]()
        expect(capture.destroyed, true, "release tears down native drag capture")
        grid:Destroy()
    end
    prettyui.Tooltip.unregisterContext(parent)
    overlay:Destroy()
    Mouse = savedMouse
end

-- Exercise real Dialog, Window, chrome, content callbacks and native buttons.
do
    local savedVector = Vector4
    Vector4 = { new = function(r, g, b, a) return { r, g, b, a } end }
    local function chromes(parent)
        local result = {}
        for _, layer in ipairs(parent.children) do
            if not layer.destroyed and layer.kind == "layer" then
                for _, child in ipairs(layer.children) do
                    if child.kind == "rectangle" and child.colour ~= nil then
                        result[#result + 1] = layer
                        break
                    end
                end
            end
        end
        return result
    end
    for _, firstAuto in ipairs({ true, false }) do
        local static = host(44)
        local parent = ui.Layer.new(static)
        local action1 = { label = "First" }
        local first = prettyui.Dialog.new(parent, {
            categoryID = firstAuto and "auto" or nil,
            actions = { action1 },
            content = function(window_)
                expect(window_.content.categoryID, 0, "modal callback receives completed raw-compatible content")
                expect(ui.Layer.new(window_.content).categoryID, 0, "modal callback can safely extend zero content")
            end,
        })
        expect(first.window:AddText("First owner").categoryID > 0, firstAuto,
            "real first modal Window preserves its allocation choice")
        local chrome = chromes(parent)
        expect(#chrome, 2, "modal mounts a dim and blocker")
        expect(chrome[1].categoryID > 0, firstAuto, "real shared chrome follows its first modal owner")
        local second = prettyui.Dialog.new(parent, {
            categoryID = not firstAuto and "auto" or nil,
        })
        expect(second.window:AddText("Second owner").categoryID > 0, not firstAuto,
            "real second modal Window preserves an independent allocation choice")
        local stillChrome = chromes(parent)
        expect(#stillChrome, 2, "stacking a modal does not create replacement chrome")
        expect(stillChrome[1], chrome[1], "shared dim retains native identity across policies")
        second.window:Close()
        expect(chrome[1].destroyed, nil, "shared chrome survives while another modal remains")
        first.actionSlots[action1].button.root.subscriptions[ui.Hook.ONCLICK]()
        expect(chrome[1].destroyed, true, "last modal destroys shared chrome")
    end
    Vector4 = savedVector
end

print("category_capacity_test: ok")
