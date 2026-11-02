local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- Resolve native size anchors on access, including after an ancestor changes size.
local function component(parent)
    local value = { parent = parent, x = 0, y = 0, hidden = false, subscriptions = {},
        opConfig = { ClearOpCursors = function() end, SetOpCursor = function() end }, cursorConfig = {} }
    setmetatable(value, { __index = function(self, key)
        if key == "width" then return (self.w or 0) + (parent and parent.width or 0) * (self.wa or 0) end
        if key == "height" then return (self.h or 0) + (parent and parent.height or 0) * (self.ha or 0) end
    end })
    function value:SetPos(x, y) self.x, self.y = x, y end
    function value:SetY(y) self.y = y end
    function value:SetSize(w, h, wa, ha) self.w, self.h, self.wa, self.ha = w, h, wa, ha end
    function value:SetWidth(w, wa) self.w, self.wa = w, wa end
    function value:SetHeight(h, ha) self.h, self.ha = h, ha end
    function value:SetScrollSize(w, h) self.scrollWidth, self.scrollHeight = w, h end
    function value:SetScrollPos(x, y) self.scrollX, self.scrollY = x, y end
    function value:Subscribe(hook, name, callback) self.subscriptions[hook] = callback or name end
    function value:Unsubscribe(hook) self.subscriptions[hook] = nil end
    function value:MoveToFront() self.raised = (self.raised or 0) + 1 end
    function value:MoveToBack() end
    function value:Destroy() self.destroyed = true end
    return Interfaces.component(value, parent)
end

local enum = setmetatable({}, { __index = function(_, key) return key end })
ui = {
    Layer = { new = component }, Sprite = { new = component },
    Text = { new = component }, Rectangle = { new = component },
    Hook = enum, AlignMode = enum,
}
id = {
    Sprite = enum, Font = enum,
    VarPlayer = { TOPLEVEL_V2_CUSTOMIZATION_LOCK = 11, TOPLEVEL_V2_SKINS_VARP = 12, TOPLEVEL_V2_TRANSPARENCY = 13 },
}
local font = {
    baseline = 18,
    GetStringLineCount = function() return 1 end,
    GetStringWidth = function(_, text) return #text * 7 end,
}
config = { Cursor = { TOPLEVEL_V2_MOVE = 194 }, Font = { MUSEO_SANS_15PT_REGULAR = font, CINZEL_13PT_BOLD = font } }
local altDown = false
Keyboard = {
    IsAvailable = function() return true end,
    IsBlocked = function() return false end,
    IsAltDown = function() return altDown end,
}
local varCallbacks = {}
Event = {
    Logic = { Subscribe = function() end, Unsubscribe = function() end },
    VarTransmit = {
        Subscribe = function(name, callback) varCallbacks[name] = callback end,
        Unsubscribe = function(name) varCallbacks[name] = nil end,
    },
}
local lockValue, transparencyValue = 0, 0
var = { VarPlayer = {
    TOPLEVEL_V2_CUSTOMIZATION_LOCK = setmetatable({}, { __index = function() return lockValue end }),
    TOPLEVEL_V2_TRANSPARENCY = setmetatable({}, { __index = function() return transparencyValue end }),
} }
local function listening()
    local count = 0
    for _ in pairs(varCallbacks) do count = count + 1 end
    return count
end
local function transmit(varID)
    for _, callback in pairs(varCallbacks) do callback({ var = { id = varID } }) end
end

local NativeInterfaceSettings = require("src/core/native_interface_settings")
local Window = require("src/window")
local Panel = require("src/panel")
local parent = component()
parent:SetSize(1000, 800)

-- The module reports the current values at once, re-reads only the variables it
-- watches, and listens only while someone watches.
local seenLock, seenTransparency, lockCalls, transparencyCalls = nil, nil, 0, 0
expect(listening(), 0, "nothing listens before the first watcher")
lockValue, transparencyValue = 1, 51
NativeInterfaceSettings.watchLock("a", function(locked) seenLock, lockCalls = locked, lockCalls + 1 end)
expect(listening(), 1, "the first watcher subscribes to variable updates")
expect(seenLock, true, "watching reports the current lock at once")
NativeInterfaceSettings.watchTransparency("b", function(transparency)
    seenTransparency, transparencyCalls = transparency, transparencyCalls + 1
end)
expect(listening(), 1, "both settings share one subscription")
expect(seenTransparency, 0.2, "watching reports the current transparency at once")
lockValue = 0
transmit(99)
expect(seenLock, true, "an unrelated variable is not re-read")
transmit(11)
expect(seenLock, true, "the lock varbit's own id is not watched")
transmit(12)
expect(seenLock, false, "the lock varbit's base variable counts as a lock change")
expect(transparencyCalls, 1, "a lock transmit does not call transparency watchers")
transparencyValue = 255
transmit(13)
expect(seenTransparency, 1, "a transparency transmit is re-read")
expect(lockCalls, 2, "a transparency transmit does not call lock watchers")
NativeInterfaceSettings.unwatchLock("a")
expect(listening(), 1, "a transparency watcher keeps listening")
NativeInterfaceSettings.unwatchTransparency("b")
expect(listening(), 0, "the last watcher stops listening")
lockValue, transparencyValue = 0, 0

-- A window following both settings fades its background and freezes its frame.
local window = Window.new(parent, {
    title = "Settings", width = 400, height = 300, resizable = true,
    useNativeTransparency = true, respectInterfaceLock = true,
})
expect(window.background.alpha, 1, "opaque while the slider is at zero")
expect(window.resize.enabled, true, "resizable while unlocked")
expect(window.titleDrag.cursorConfig.mouseOverCursor, 194, "move cursor while unlocked")
transparencyValue = 102
transmit(13)
expect(window.background.alpha, 0.6, "background follows the transparency slider")
lockValue = 1
transmit(12)
expect(window.resize.enabled, false, "locking disables resizing")
expect(window.titleDrag.cursorConfig.mouseOverCursor, -1, "locking drops the move cursor")
local raised = window.root.raised
window.titleDrag.subscriptions[ui.Hook.ONCLICK](window.titleDrag, 5, 5)
expect(window.root.raised, raised + 1, "a title click still raises a locked window")
expect(window.dragFeedback, nil, "a title click does not start moving a locked window")
lockValue = 0
transmit(12)
expect(window.resize.enabled, true, "unlocking restores resizing")
expect(window.titleDrag.cursorConfig.mouseOverCursor, 194, "unlocking restores the move cursor")
window:SetUseNativeTransparency(false)
expect(window.background.alpha, 1, "turning the option off restores opacity")
window:SetRespectInterfaceLock(false)
expect(listening(), 0, "a window following nothing stops listening")
window:SetRespectInterfaceLock(true)
expect(listening(), 1, "turning an option on listens again")
window:Destroy()
expect(listening(), 0, "destroying the window stops listening")

-- A window without the options ignores both settings entirely.
lockValue, transparencyValue = 1, 255
local plain = Window.new(parent, { title = "Plain", width = 300, height = 200, resizable = true })
expect(listening(), 0, "a plain window does not listen")
expect(plain.background.alpha, nil, "a plain window never touches its background alpha")
expect(plain.resize.enabled, true, "a plain window stays resizable")
plain:Destroy()
lockValue, transparencyValue = 0, 0

-- A panel scales both surfaces' own alpha by the slider and refuses Alt dragging
-- and resizing while locked.
local panel = Panel.new(parent, {
    width = 300, height = 200, resizable = true, backgroundAlpha = 0.5,
    popout = true, popoutBackgroundAlpha = 0.8, overlayParent = parent,
    useNativeTransparency = true, respectInterfaceLock = true,
})
expect(panel.dock.background.alpha, 0.5, "dock keeps its own alpha at zero transparency")
expect(panel.overlay.background.alpha, 0.8, "popout keeps its own alpha at zero transparency")
transparencyValue = 127.5
transmit(13)
expect(panel.dock.background.alpha, 0.25, "dock alpha scales with the slider")
expect(panel.overlay.background.alpha, 0.4, "popout alpha scales with the slider")
panel:SetPopoutBackgroundAlpha(0.6)
expect(panel.overlay.background.alpha, 0.3, "a new popout alpha is scaled too")
altDown = true
panel:_SetAltDragActive(true)
expect(panel.altDragSurface, panel.dock, "Alt enables dragging while unlocked")
expect(panel.dockResize.enabled, true, "resizable while unlocked")
lockValue = 1
transmit(12)
expect(panel.altDragSurface, nil, "locking ends Alt dragging")
expect(panel.dockDragLayer.enabled, false, "locking disables the drag layer")
expect(panel.dockResize.enabled, false, "locking disables resizing")
panel:_SetAltDragActive(true)
expect(panel.altDragSurface, nil, "Alt cannot drag a locked panel")
lockValue = 0
transmit(12)
expect(panel.altDragSurface, panel.dock, "unlocking restores Alt dragging")
expect(panel.dockResize.enabled, true, "unlocking restores resizing")
altDown = false
panel:Destroy()
expect(listening(), 0, "destroying the panel stops listening")

-- A variable the client does not know leaves its setting unwatched: no listening, no
-- callback, and the component keeps its own behaviour. The other setting still works.
id.VarPlayer.TOPLEVEL_V2_TRANSPARENCY = nil
for _, name in ipairs({ "src/core/native_interface_settings", "src/window" }) do package.loaded[name] = nil end
local MissingSettings = require("src/core/native_interface_settings")
local MissingWindow = require("src/window")
local called = false
MissingSettings.watchTransparency("c", function() called = true end)
expect(listening(), 0, "an unknown variable is not listened for")
expect(called, false, "an unknown variable never calls back")
transparencyValue, lockValue = 255, 1
local unaffected = MissingWindow.new(parent, {
    title = "Missing", width = 300, height = 200, resizable = true,
    useNativeTransparency = true, respectInterfaceLock = true,
})
expect(unaffected.background.alpha, nil, "without the transparency variable the background alpha is untouched")
expect(unaffected.resize.enabled, false, "the lock still applies")
unaffected:Destroy()
expect(listening(), 0, "destroying it stops listening")

print("native_interface_settings_test: module, window and panel passed")
