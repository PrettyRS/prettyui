local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function updateLayout(component)
    local parent = component.parent
    local parentWidth, parentHeight = parent and parent.width or 0, parent and parent.height or 0
    local position, size = component.position, component.size
    component.width = size.width + size.widthParentPc * parentWidth
    component.height = size.height + size.heightParentPc * parentHeight
    component.x = position.x + position.xParentPc * parentWidth + position.xSelfPc * component.width
    component.y = position.y + position.yParentPc * parentHeight + position.ySelfPc * component.height
    local origin = parent and parent.xyGlobal or { x = 0, y = 0 }
    component.xyGlobal = { x = origin.x + component.x, y = origin.y + component.y }
    for _, child in ipairs(component.children) do updateLayout(child) end
end

local liveComponents = 0
local function component(parent, kind, interfaceID)
    local result = {
        position = { x = 0, y = 0, xParentPc = 0, yParentPc = 0, xSelfPc = 0, ySelfPc = 0 },
        size = { width = 0, height = 0, widthParentPc = 0, heightParentPc = 0 },
        children = {}, subscriptions = {}, parent = parent, kind = kind,
        hidden = false, destroyed = false,
    }
    function result:SetPos(x, y, xParentPc, yParentPc, xSelfPc, ySelfPc)
        self.position = {
            x = x, y = y, xParentPc = xParentPc or 0, yParentPc = yParentPc or 0,
            xSelfPc = xSelfPc or 0, ySelfPc = ySelfPc or 0,
        }
        updateLayout(self)
    end
    function result:SetSize(width, height, widthParentPc, heightParentPc)
        self.size = {
            width = width, height = height,
            widthParentPc = widthParentPc or 0, heightParentPc = heightParentPc or 0,
        }
        updateLayout(self)
    end
    function result:Subscribe(hook, id, callback)
        if callback == nil then callback, id = id, "default" end
        self.subscriptions[tostring(hook) .. ":" .. tostring(id)] = callback
    end
    function result:Unsubscribe(hook, id)
        self.subscriptions[tostring(hook) .. ":" .. tostring(id or "default")] = nil
    end
    function result:MoveToFront() end
    function result:Destroy()
        if self.destroyed then return end
        while #self.children > 0 do self.children[#self.children]:Destroy() end
        self.subscriptions = {}
        self.destroyed = true
        liveComponents = liveComponents - 1
        if self.parent then
            for index, child in ipairs(self.parent.children) do
                if child == self then table.remove(self.parent.children, index) break end
            end
        end
    end
    updateLayout(result)
    liveComponents = liveComponents + 1
    if parent then table.insert(parent.children, result) end
    return Interfaces.component(result, interfaceID and { interfaceID = interfaceID } or parent)
end

local root = component(nil, "Layer")
root:SetSize(640, 480)
local nativeHitbox
local function mountNativeHitbox()
    nativeHitbox = component(root, "Layer", 2)
    nativeHitbox:SetPos(240, 90, 0.25, 0.125, -0.5, -0.25)
    nativeHitbox:SetSize(160, 90, 0.1, 0.2)
    nativeHitbox.clickthrough = false
end
mountNativeHitbox()
local nativeLayer = "blocking"

id = {
    Component = {
        TOPLEVEL_V2__ROOT = 1, TOPLEVEL_V2__GAME_AREA = 2,
        MINIMENU__PC_MOUSE_LEAVE_LAYER = 3, MINIMENU__MENU_BLOCKING_LAYER = 4,
    },
    Font = { NOTOSANS_BOLD_12 = 1 },
}
ui = {
    AlignMode = { TOPLEFT = 1, CENTRE = 2 },
    Hook = { ONMOUSEOVER = 1, ONMOUSEREPEAT = 2, ONMOUSELEAVE = 3, ONCLICK = 4, ONSCROLLWHEEL = 5 },
    Layer = { new = function(parent) return component(parent, "Layer") end },
    Rectangle = { new = function(parent) return component(parent, "Rectangle") end },
    Sprite = { new = function(parent) return component(parent, "Sprite") end },
    Text = { new = function(parent) return component(parent, "Text") end },
    Interfaces = {
        GetComponent = function(_, componentID)
            if componentID == id.Component.TOPLEVEL_V2__ROOT
                    or componentID == id.Component.TOPLEVEL_V2__GAME_AREA then return root end
            if nativeLayer == "mouseLeave" and componentID == id.Component.MINIMENU__PC_MOUSE_LEAVE_LAYER
                    or nativeLayer == "blocking" and componentID == id.Component.MINIMENU__MENU_BLOCKING_LAYER then
                return nativeHitbox
            end
        end,
    },
}
-- Install the shared fixture's loaded-interface lookup after defining ui.
local probe = component(root, "Layer")
probe:Destroy()

local function font(characterWidth)
    return { GetStringWidth = function(_, text)
        local visible = text:gsub("<([^>]*)>", function(tag)
            if tag == "gt" then return ">" end
            if tag == "lt" then return "<" end
            return ""
        end)
        return #visible * characterWidth
    end }
end
config = { Font = { NOTOSANS_BOLD_12 = font(7), MUSEO_SANS_15PT_REGULAR = font(8) } }
game = { options = { InterfaceScale = { setting = 100 } } }
local monitorScale = 1
local mouse = { x = 320, y = 100 }
Mouse = { GetPosition = function() return { x = mouse.x, y = mouse.y } end }

local handlers = {}
local function event(name)
    local listeners = {}
    handlers[name] = listeners
    return {
        Subscribe = function(id, callback)
            for _, listener in ipairs(listeners) do
                if listener.id == id then listener.callback = callback return end
            end
            listeners[#listeners + 1] = { id = id, callback = callback }
        end,
        Unsubscribe = function(id)
            for index, listener in ipairs(listeners) do
                if listener.id == id then table.remove(listeners, index) return end
            end
        end,
    }
end
Event = {
    MiniMenuReady = event("MiniMenuReady"), MiniMenuOpened = event("MiniMenuOpened"),
    MiniMenuClosed = event("MiniMenuClosed"), MiniMenuEntrySelected = event("MiniMenuEntrySelected"),
    Logic = event("Logic"),
}
local function emit(name, payload)
    for _, listener in ipairs(handlers[name]) do listener.callback(payload) end
end
local nativeMenuOpen = false
MiniMenu = { IsOpen = function() return nativeMenuOpen end }
package.loaded["src/core/sprites"] = {
    MINIMENU = { title = 1, titleCorner = 2, side = 3, bottom = 4, bottomCorner = 5 },
}
local PrettyMiniMenu = require("src/minimenu")
PrettyMiniMenu.Start()

local function readyMenu(build, labels)
    local menu = { entries = {}, writable = true }
    for _, label in ipairs(labels or { "Cancel", "Walk here" }) do
        menu.entries[#menu.entries + 1] = { fullText = label }
    end
    function menu:Add(label, action)
        assert(self.writable)
        table.insert(self.entries, 1, { overrideText = label, callback = action })
    end
    function menu:Swap(a, b)
        assert(self.writable)
        self.entries[a], self.entries[b] = self.entries[b], self.entries[a]
    end
    nativeMenuOpen = false
    Event.MiniMenuReady.Subscribe("consumer", function(event) build(event.miniMenu) end)
    emit("MiniMenuReady", { miniMenu = menu })
    Event.MiniMenuReady.Unsubscribe("consumer")
    menu.writable = false
    return menu
end

local function hook(componentValue, eventType, id)
    return componentValue.subscriptions[tostring(eventType) .. ":" .. tostring(id or "default")]
end
local function findOverlay(parent)
    for _, child in ipairs(parent.children) do
        if hook(child, ui.Hook.ONSCROLLWHEEL) then return child end
        local found = findOverlay(child)
        if found then return found end
    end
end
local function rowText(row)
    for _, child in ipairs(row.children) do
        if child.kind == "Text" then return child.content end
    end
end
local function rows(menuOverlay)
    local result = {}
    for _, child in ipairs(menuOverlay.children) do
        if hook(child, ui.Hook.ONCLICK) and not child.hidden then result[#result + 1] = child end
    end
    table.sort(result, function(a, b) return a.y < b.y end)
    return result
end
local function click(row)
    if not row.destroyed then return hook(row, ui.Hook.ONCLICK)(row) end
end
local function point(x, y)
    mouse.x = (root.xyGlobal.x + x) * monitorScale
    mouse.y = (root.xyGlobal.y + y) * monitorScale
end
local function openMenu(menu, freshWrappers, x, y)
    point(x or 320, y or 100)
    local opened = menu
    if freshWrappers then
        opened = { entries = {} }
        for index, entry in ipairs(menu.entries) do
            opened.entries[index] = { fullText = entry.fullText, overrideText = entry.overrideText }
        end
    end
    nativeMenuOpen = true
    emit("MiniMenuOpened", { miniMenu = opened })
end
local function hoverParent(menu, parent, x, y)
    for index, entry in ipairs(menu.entries) do
        if entry == parent then
            point(x or 320, (y or 100) + 22 + (#menu.entries - index) * 15 + 7)
            if nativeLayer ~= "missing" then
                local mouseOver = hook(nativeHitbox, ui.Hook.ONMOUSEOVER, "prettyui_minimenu")
                if mouseOver then
                    mouseOver(nativeHitbox,
                        root.xyGlobal.x + (x or 320) - nativeHitbox.xyGlobal.x,
                        root.xyGlobal.y + (y or 100) + 22 + (#menu.entries - index) * 15 + 7
                            - nativeHitbox.xyGlobal.y)
                end
            end
            emit("Logic")
            return findOverlay(root)
        end
    end
    error("parent entry missing")
end
local function closeMenu()
    nativeMenuOpen = false
    emit("MiniMenuClosed")
end
local function nativeSnapshot()
    return { position = nativeHitbox.position, size = nativeHitbox.size }
end
local function expectNativeRestored(snapshot)
    for key, value in pairs(snapshot.position) do
        expect(nativeHitbox.position[key], value, "native position restores " .. key)
    end
    for key, value in pairs(snapshot.size) do
        expect(nativeHitbox.size[key], value, "native size restores " .. key)
    end
end
local function children(action)
    return { { label = "Child", action = action or function() end } }
end

-- Visible placement protects the native default action and Cancel, on a menu
-- large enough to distinguish top, bottom, and an intermediate position.
for _, case in ipairs({ { "top", 4 }, { "bottom", 2 }, { 3, 3 }, { 99, 2 } }) do
    local parent
    local menu = readyMenu(function(menu)
        parent = PrettyMiniMenu.AddSubmenu(menu, "Positioned", children(), { position = case[1] })
    end, { "Cancel", "Examine", "Trade", "Walk here" })
    expect(menu.entries[case[2]], parent, "requested placement uses the displayed row")
    expect(menu.entries[1].fullText, "Cancel", "placement preserves Cancel")
    expect(menu.entries[#menu.entries].fullText, "Walk here", "placement preserves the default action")
end

-- mocks the client mini menu and adds new entries at the start and end
local function clientMenu(labels, addAtEnd)
    local stored = {}
    for index, label in ipairs(labels) do stored[index] = { fullText = label } end
    local menu = { reads = 0 }
    function menu:Add(label, action)
        table.insert(stored, addAtEnd and #stored + 1 or 1, { overrideText = label, callback = action })
    end
    function menu:Swap(a, b)
        stored[a], stored[b] = stored[b], stored[a]
    end
    return setmetatable(menu, { __index = function(self, key)
        if key ~= "entries" then return nil end
        self.reads = self.reads + 1
        local entries = {}
        for index, entry in ipairs(stored) do
            entries[index] = { fullText = entry.fullText, overrideText = entry.overrideText, callback = entry.callback }
        end
        return entries
    end })
end
local function entryLabels(menu)
    local labels = {}
    for index, entry in ipairs(menu.entries) do labels[index] = entry.overrideText or entry.fullText end
    return table.concat(labels, ", ")
end
local function clientSubmenu(menu, label, position)
    local reads = menu.reads
    local result = PrettyMiniMenu.AddSubmenu(menu, label, children(), { position = position, arrow = false })
    expect(menu.reads - reads, 2, "AddSubmenu reads client entries once on each side of Add")
    return result
end
for _, addAtEnd in ipairs({ false, true }) do
    for _, case in ipairs({
        { "top", "Cancel, Examine, Trade, Client, Walk here" },
        { "bottom", "Cancel, Client, Examine, Trade, Walk here" },
        { 3, "Cancel, Examine, Client, Trade, Walk here" },
        { 99, "Cancel, Client, Examine, Trade, Walk here" },
    }) do
        local menu = clientMenu({ "Cancel", "Examine", "Trade", "Walk here" }, addAtEnd)
        emit("MiniMenuReady", { miniMenu = menu })
        local parent = clientSubmenu(menu, "Client", case[1])
        expect(parent.overrideText, "Client", "client placement returns the new parent entry")
        expect(entryLabels(menu), case[2], "client placement moves only the new parent")
    end
    local menu = clientMenu({ "Cancel", "Examine", "Trade", "Walk here" }, addAtEnd)
    emit("MiniMenuReady", { miniMenu = menu })
    clientSubmenu(menu, "First", "top")
    clientSubmenu(menu, "Second", "bottom")
    expect(entryLabels(menu), "Cancel, Second, Examine, Trade, First, Walk here",
        "repeated client submenus keep native entries in order")
end

readyMenu(function(menu)
    local count = #menu.entries
    local accepted = pcall(PrettyMiniMenu.AddSubmenu, menu, "Invalid", children(), { position = 1 })
    expect(accepted, false, "reserved default row is rejected")
    expect(#menu.entries, count, "invalid placement does not add a native entry")
end)

local selected, parent
local menu = readyMenu(function(menu)
    parent = PrettyMiniMenu.AddSubmenu(menu, "PrettyUI actions", {
        { label = "First child", action = function(value) selected = value end, args = { "first" } },
        { label = "Second child", action = function() selected = "second" end },
    }, { parentAction = function() selected = "parent" end })
end)
expect(menu.entries[2], parent, "default placement is above Cancel")
parent.callback()
expect(selected, "parent", "native parent retains its independent action")
selected = nil
local originalBounds = nativeSnapshot()
root:SetPos(40, 30)
openMenu(menu, true)
local rightOverlay = assert(hoverParent(menu, parent))
expect(rightOverlay.parent, nativeHitbox, "blocking host places custom rows above native input blocking")
expect(rightOverlay.xyGlobal.x > mouse.x, true, "submenu opens on the right with room available")
expect(nativeHitbox.xyGlobal.x + nativeHitbox.width >= rightOverlay.xyGlobal.x + rightOverlay.width,
    true, "native hover bounds include submenu width")
expect(nativeHitbox.xyGlobal.y + nativeHitbox.height >= rightOverlay.xyGlobal.y + rightOverlay.height,
    true, "native hover bounds include submenu height")
mouse.x, mouse.y = rightOverlay.xyGlobal.x + 5, rightOverlay.xyGlobal.y + 30
emit("Logic")
expect(findOverlay(root), rightOverlay, "pointer transition into the submenu keeps it open")
mouse.x = rightOverlay.xyGlobal.x + rightOverlay.width + 20
emit("Logic")
expect(rightOverlay.destroyed, true, "leaving both menus dismisses the submenu")
expectNativeRestored(originalBounds)
rightOverlay = assert(hoverParent(menu, parent))
click(rows(rightOverlay)[1])
expect(selected, "first", "reopened submenu invokes its child with arguments")
expect(rightOverlay.destroyed, true, "child selection destroys the overlay")
expectNativeRestored(originalBounds)
closeMenu()
root:SetPos(0, 0)
-- Raw window pixels may include both OS and in-game interface scaling.
local baselineX, baselineY
for _, case in ipairs({
    { rawScale = 1, interfaceScale = 100 },
    { rawScale = 1.2, interfaceScale = 100 },
    { rawScale = 1.8, interfaceScale = 150 },
}) do
    monitorScale = case.rawScale
    game.options.InterfaceScale.setting = case.interfaceScale
    menu = readyMenu(function(menu)
        parent = PrettyMiniMenu.AddSubmenu(menu, "PrettyUI actions", children())
    end)
    openMenu(menu, true)
    if case.rawScale > 1 then emit("Logic") end -- hook can arrive after a logic tick
    local menuOverlay = assert(hoverParent(menu, parent))
    if baselineX == nil then
        baselineX, baselineY = menuOverlay.xyGlobal.x, menuOverlay.xyGlobal.y
    else
        expect(menuOverlay.xyGlobal.x, baselineX,
            "monitor scaling keeps the submenu adjacent to the same native row")
        expect(menuOverlay.xyGlobal.y, baselineY,
            "monitor scaling preserves the submenu's vertical alignment")
        mouse.x = (menuOverlay.xyGlobal.x + 5) * monitorScale
        mouse.y = (menuOverlay.xyGlobal.y + 30) * monitorScale
        emit("Logic")
        expect(findOverlay(root), menuOverlay,
            "scaled pointer entering the child submenu keeps it open")
        mouse.x = (menuOverlay.xyGlobal.x + menuOverlay.width + 20) * monitorScale
        emit("Logic")
        expect(menuOverlay.destroyed, true,
            "scaled pointer leaving both menus dismisses the submenu")
    end
    closeMenu()
end
monitorScale = 1
game.options.InterfaceScale.setting = 100

-- A duplicate is rejected before mutating the native menu, including text
-- rendered equivalently after colour markup and whitespace normalization.
menu = readyMenu(function(menu)
    parent = PrettyMiniMenu.AddSubmenu(menu, "<col=ff0000>Shared   actions</col>", children(function()
        selected = "original"
    end))
    local count = #menu.entries
    local accepted = pcall(PrettyMiniMenu.AddSubmenu, menu, "Shared actions", children(function()
        selected = "wrong"
    end))
    expect(accepted, false, "ambiguous submenu labels are rejected")
    expect(#menu.entries, count, "duplicate rejection preserves native entries")
end)
openMenu(menu, true)
click(rows(assert(hoverParent(menu, parent)))[1])
expect(selected, "original", "duplicate rejection preserves the first registration's action")
closeMenu()
readyMenu(function(menu)
    local accepted = pcall(PrettyMiniMenu.AddSubmenu, menu, "Walk here", children(), { arrow = false })
    expect(accepted, false, "a submenu cannot impersonate an existing native entry")
    expect(#menu.entries, 2, "native-label rejection does not add a parent")
end)

local otherParent
menu = readyMenu(function(menu)
    parent = PrettyMiniMenu.AddSubmenu(menu, "Compare <lt>one<gt>", children(function() selected = "one" end))
    otherParent = PrettyMiniMenu.AddSubmenu(menu, "Compare <lt>two<gt>", children(function() selected = "two" end))
end)
openMenu(menu, true)
local firstOverlay = assert(hoverParent(menu, parent))
local secondOverlay = assert(hoverParent(menu, otherParent))
expect(firstOverlay.destroyed, true, "changing parents retires the previous overlay")
click(rows(secondOverlay)[1])
expect(selected, "two", "escaped literal brackets remain distinct during fallback matching")
closeMenu()

-- Another subscriber can add a conflicting ordinary entry after AddSubmenu.
-- Fresh wrappers must not guess, but unchanged entry identity remains safe.
for _, freshWrappers in ipairs({ true, false }) do
    menu = readyMenu(function(menu)
        parent = PrettyMiniMenu.AddSubmenu(menu, "Late collision", children(function() selected = "registered" end))
        menu:Add(parent.overrideText, function() selected = "native" end)
        otherParent = menu.entries[1]
    end)
    openMenu(menu, freshWrappers)
    expect(hoverParent(menu, otherParent), nil, "an unrelated duplicate never inherits a submenu")
    local menuOverlay = hoverParent(menu, parent)
    if freshWrappers then
        expect(menuOverlay, nil, "ambiguous open-time text cannot select a registration")
    else
        click(rows(assert(menuOverlay))[1])
        expect(selected, "registered", "known identity survives an unrelated text collision")
    end
    closeMenu()
end

local retained = setmetatable({}, { __mode = "v" })
for index = 1, 20 do
    readyMenu(function(menu)
        local payload = { value = index }
        retained[index] = payload
        PrettyMiniMenu.AddSubmenu(menu, "Dynamic " .. index,
            children(function() return payload.value end), { arrow = false })
    end)
end
menu = readyMenu(function(menu)
    menu:Add("Dynamic 20", function() selected = "ordinary" end)
    parent = menu.entries[1]
end)
collectgarbage("collect")
expect(next(retained), nil, "the next menu build releases discarded callbacks without shutdown")
openMenu(menu, true)
expect(hoverParent(menu, parent), nil, "a later native entry cannot revive a stale registration")
parent.callback()
expect(selected, "ordinary", "the later native action remains independent")
closeMenu()

root:SetSize(300, 180)
menu = readyMenu(function(menu)
    parent = PrettyMiniMenu.AddSubmenu(menu, "Edge actions", children())
end)
openMenu(menu, false, 285, 100)
local leftOverlay = assert(hoverParent(menu, parent, 285, 100))
expect(leftOverlay.xyGlobal.x + leftOverlay.width <= mouse.x, true, "submenu flips left near the viewport edge")
expect(leftOverlay.xyGlobal.x >= 0 and leftOverlay.xyGlobal.y >= 0
    and leftOverlay.xyGlobal.y + leftOverlay.height <= root.height, true, "flipped submenu remains in the viewport")
closeMenu()

root:SetSize(320, 80)
menu = readyMenu(function(menu)
    local options = {}
    for index, label in ipairs({ "One", "Two", "Three", "Four", "Five" }) do
        options[index] = { label = label, action = function() selected = index end }
    end
    parent = PrettyMiniMenu.AddSubmenu(menu, "Scrollable", options)
    menu:Swap(2, 3)
end)
openMenu(menu, false, 160, 0)
local scrollOverlay = assert(hoverParent(menu, parent, 160, 0))
expect(scrollOverlay.height <= root.height, true, "overflow submenu fits the viewport")
local scrollRow = rows(scrollOverlay)[1]
for _ = 1, 10 do hook(scrollOverlay, ui.Hook.ONSCROLLWHEEL)(scrollOverlay, -1) end
expect(rowText(scrollRow), "One", "scrolling clamps at the first child")
for _ = 1, 10 do hook(scrollRow, ui.Hook.ONSCROLLWHEEL)(scrollRow, 1) end
expect(rowText(scrollRow), "Three", "scrolling clamps with the last children visible")
click(scrollRow)
expect(selected, 3, "a reused visible row selects its current child after scrolling")
closeMenu()
root:SetSize(640, 480)

for _, host in ipairs({ "blocking", "mouseLeave", "missing" }) do
    nativeLayer = host
    menu = readyMenu(function(menu)
        parent = PrettyMiniMenu.AddSubmenu(menu, "Close lifecycle", children(function() selected = "closed child" end))
    end)
    originalBounds = nativeSnapshot()
    openMenu(menu)
    local menuOverlay = assert(hoverParent(menu, parent))
    local row = rows(menuOverlay)[1]
    selected = nil
    nativeHitbox.clickthrough = true
    closeMenu()
    click(row)
    expect(menuOverlay.destroyed, true, "native close destroys the overlay for " .. host)
    expect(selected, nil, "closed submenu cannot dispatch a child for " .. host)
    expectNativeRestored(originalBounds)
    expect(nativeHitbox.clickthrough, true, "cleanup does not overwrite native input changes")
    nativeHitbox.clickthrough = false
end
nativeLayer = "blocking"
menu = readyMenu(function(menu)
    parent = PrettyMiniMenu.AddSubmenu(menu, "Polled close", children())
end)
openMenu(menu)
local polledOverlay = assert(hoverParent(menu, parent))
nativeMenuOpen = false
emit("Logic")
expect(polledOverlay.destroyed, true, "logic also retires an overlay when the native menu is closed")

-- Fail at three different ownership boundaries: after a native position change,
-- immediately after allocating the root, and after constructing frame children.
for _, stage in ipairs({ "nativeSize", "rootPosition", "title" }) do
    menu = readyMenu(function(menu)
        parent = PrettyMiniMenu.AddSubmenu(menu, "Failed construction", {
            { label = string.rep("Wide child ", 8), action = function() selected = "recovered" end },
        })
    end)
    originalBounds = nativeSnapshot()
    local baselineComponents = liveComponents
    local failure = { stage = stage }
    local restoreConstructor
    if stage == "nativeSize" then
        local original = nativeHitbox.SetSize
        local failOnce = true
        nativeHitbox.SetSize = function(self, ...)
            if failOnce then failOnce = false error(failure, 0) end
            return original(self, ...)
        end
        restoreConstructor = function() nativeHitbox.SetSize = original end
    elseif stage == "rootPosition" then
        local original = ui.Layer.new
        ui.Layer.new = function(host)
            local layer = original(host)
            layer.SetPos = function() error(failure, 0) end
            return layer
        end
        restoreConstructor = function() ui.Layer.new = original end
    else
        local original = ui.Text.new
        ui.Text.new = function() error(failure, 0) end
        restoreConstructor = function() ui.Text.new = original end
    end
    openMenu(menu)
    local succeeded, observed = pcall(hoverParent, menu, parent)
    restoreConstructor()
    expect(succeeded, false, "construction failure propagates at " .. stage)
    expect(observed, failure, "construction preserves the original error at " .. stage)
    expect(liveComponents, baselineComponents, "construction failure releases partial UI at " .. stage)
    expectNativeRestored(originalBounds)
    emit("Logic")
    expect(findOverlay(root), nil, "failed construction is not retried on the next tick")
    closeMenu()
end

local actionFailure = {}
menu = readyMenu(function(menu)
    parent = PrettyMiniMenu.AddSubmenu(menu, "Action failure", children(function() error(actionFailure, 0) end))
end)
originalBounds = nativeSnapshot()
openMenu(menu)
local throwingOverlay = assert(hoverParent(menu, parent))
local succeeded, observed = pcall(click, rows(throwingOverlay)[1])
expect(succeeded, false, "child action errors propagate")
expect(observed, actionFailure, "child action errors retain their original value")
expect(throwingOverlay.destroyed, true, "cleanup precedes a throwing child action")
expectNativeRestored(originalBounds)
closeMenu()

menu = readyMenu(function(menu)
    parent = PrettyMiniMenu.AddSubmenu(menu, "Native selection", children())
end)
openMenu(menu)
local selectedOverlay = assert(hoverParent(menu, parent))
emit("MiniMenuEntrySelected", { entry = menu.entries[#menu.entries] })
emit("Logic")
expect(selectedOverlay.destroyed, true, "native selection retires the custom overlay")
expect(findOverlay(root), nil, "native selection cannot reopen the old submenu")
closeMenu()

menu = readyMenu(function(menu)
    parent = PrettyMiniMenu.AddSubmenu(menu, "Shutdown", children())
end)
openMenu(menu)
local shutdownOverlay = assert(hoverParent(menu, parent))
PrettyMiniMenu.Shutdown()
expect(shutdownOverlay.destroyed, true, "shutdown releases an active submenu")
emit("MiniMenuOpened", { miniMenu = menu })
emit("Logic")
expect(findOverlay(root), nil, "shutdown prevents native events from remounting the submenu")
PrettyMiniMenu.Start()
PrettyMiniMenu.Start()

menu = readyMenu(function(menu)
    parent = PrettyMiniMenu.AddSubmenu(menu, "Interface unload", children())
end)
openMenu(menu)
assert(hoverParent(menu, parent))
-- Native menus live in a different interface from the viewport. Unloading that
-- interface removes its tree before the native close notification is delivered.
for index, child in ipairs(root.children) do
    if child == nativeHitbox then table.remove(root.children, index) break end
end
nativeHitbox = nil
Interfaces.unload(2)
closeMenu()
mountNativeHitbox()
menu = readyMenu(function(menu)
    parent = PrettyMiniMenu.AddSubmenu(menu, "Remounted", children(function() selected = "remounted" end))
end)
openMenu(menu, true)
click(rows(assert(hoverParent(menu, parent)))[1])
expect(selected, "remounted", "restart and native interface reload allow a fresh submenu action")
closeMenu()
PrettyMiniMenu.Shutdown()

print("minimenu_test: ok")
