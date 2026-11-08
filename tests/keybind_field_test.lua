local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function component(parent, categoryID, dynamicID)
    local value = { parent = parent, hidden = false, subscriptions = {},
        text = {}, containerSprite = {},
        opConfig = { ClearOpCursors = function() end, SetOpCursor = function() end }, cursorConfig = {} }
    setmetatable(value, { __index = function(self, key)
        if key == "width" then return (self.w or 0) + (parent and parent.width or 0) * (self.wa or 0) end
        if key == "height" then return (self.h or 0) + (parent and parent.height or 0) * (self.ha or 0) end
        if key == "x" then return (self._x or 0) + (parent and parent.width or 0) * (self.xa or 0) - self.width * (self.sxa or 0) end
        if key == "y" then return (self._y or 0) + (parent and parent.height or 0) * (self.ya or 0) - self.height * (self.sya or 0) end
        if key == "visibleGlobal" then return not self.hidden and (not parent or parent.visibleGlobal) end
    end })
    function value:SetPos(x, y, xa, ya, sxa, sya)
        self._x, self._y, self.xa, self.ya, self.sxa, self.sya = x, y, xa, ya, sxa, sya
    end
    function value:SetY(y) self._y = y end
    function value:SetSize(w, h, wa, ha) self.w, self.h, self.wa, self.ha = w, h, wa, ha end
    function value:SetWidth(w, wa) self.w, self.wa = w, wa end
    function value:SetHeight(h, ha) self.h, self.ha = h, ha end
    function value:SetScrollSize(w, h) self.scrollWidth, self.scrollHeight = w, h end
    function value:SetScrollPos(x, y) self.scrollX, self.scrollY = x, y end
    function value:Subscribe(hook, name, callback)
        self.subscriptions[hook] = self.subscriptions[hook] or {}
        self.subscriptions[hook][callback and name or "default"] = callback or name
    end
    function value:Unsubscribe(hook, name)
        if self.subscriptions[hook] then self.subscriptions[hook][name or "default"] = nil end
    end
    function value:Fire(hook, ...)
        for _, callback in pairs(self.subscriptions[hook] or {}) do callback(self, ...) end
    end
    function value:Setup() end
    function value:MoveToFront() end
    function value:MoveToBack() end
    function value:Destroy() self.destroyed = true end
    return Interfaces.component(value, parent, categoryID, dynamicID)
end

local enum = setmetatable({}, { __index = function(_, key) return key end })
ui = {
    Layer = { new = component }, Sprite = { new = component }, InputField = { new = component },
    Text = { new = component }, Rectangle = { new = component },
    Hook = enum, AlignMode = enum, TextContentVisibilityMode = enum, InputFieldFilterMode = enum,
    InputFieldKeyHandlingMode = enum, InputFieldActionResult = enum,
    Margin = { new = function(...) return { ... } end },
}
id = { Sprite = enum, Font = enum, StyleSheet = enum }
local font = {
    baseline = 18, GetStringLineCount = function() return 1 end,
    GetStringWidth = function(_, text) return #text * 7 end,
}
config = { Cursor = enum, Font = { MUSEO_SANS_15PT_REGULAR = font, CINZEL_13PT_BOLD = font } }
GameKey = { CONTROL = 82, SHIFT = 81, ALT = 86, K = 55, L = 56, ESCAPE = 13 }
function GameKey.FromID(key)
    for name, value in pairs(GameKey) do if value == key then return name end end
end
local down, blocked = {}, false
Keyboard = {
    IsAvailable = function() return true end,
    IsBlocked = function() return blocked end,
    IsGameKeyDown = function(key) return down[key] == true and not blocked end,
    IsAltDown = function() return down[GameKey.ALT] == true end,
    GetGameKeysDown = function()
        local result = {}
        for key in pairs(down) do table.insert(result, key) end
        return result
    end,
}
Event = {}
local handlers = {}
for _, name in ipairs({ "Logic", "KeyDown", "KeyUp", "WindowFocusChanged", "MiniMenuReady" }) do
    handlers[name] = {}
    Event[name] = {
        Subscribe = function(id, fn) handlers[name][id] = fn end,
        Unsubscribe = function(id) handlers[name][id] = nil end,
    }
end
local function emit(name, event)
    for _, callback in pairs(handlers[name]) do callback(event or {}) end
end
local function press(key, isRepeat)
    down[key] = true
    emit("KeyDown", { gameKey = key, isRepeat = isRepeat == true })
end
local function release(key)
    down[key] = nil
    emit("KeyUp", { gameKey = key })
end
local function menu()
    local result = { entries = {}, entryCount = 0 }
    function result:Add(label, callback)
        table.insert(self.entries, { label = label, callback = callback })
        self.entryCount = #self.entries
    end
    function result:Swap(a, b) self.entries[a], self.entries[b] = self.entries[b], self.entries[a] end
    emit("MiniMenuReady", { miniMenu = result })
    return result.entries
end

local KeybindField = require("src/keybind_field")
local parent = component()
parent:SetSize(1000, 800)
local changes = {}
local field = KeybindField.new(parent, {
    defaultValue = { GameKey.CONTROL, GameKey.SHIFT },
    onChange = function(_, value) changes[#changes + 1] = value end,
})
expect(field.root.height, 24, "keybind field matches native field height")
for _, size in ipairs({ {240, 24}, {576, 46}, {360, 64} }) do
    field.root:SetSize(size[1], size[2])
    expect(field.root.width - field.clearSprite.x - field.clearSprite.width, 4,
        "clear sprite remains inside the right edge after resize")
    expect(field.clearSprite.y, (field.root.height - field.clearSprite.height) / 2,
        "clear sprite remains vertically centered after resize")
end
field.root:SetSize(240, 24)
field.input.root:Fire(ui.Hook.ONCLICK, 30, 10)
press(GameKey.CONTROL)
press(GameKey.CONTROL, true)
press(GameKey.K)
press(GameKey.L)
expect(field.label.content, "Ctrl + K", "live display ignores repeats and third key")
expect(#changes, 0, "capture does not publish before release")
expect(KeybindField.IsDown({ GameKey.CONTROL, GameKey.K }), false, "capture suppresses activation")
release(GameKey.K)
expect(field:IsListening(), true, "partial release keeps capture active")
release(GameKey.CONTROL)
expect(#changes, 1, "all captured keys released publishes once")
expect(KeybindField.FormatValue(field:GetValue()), "Ctrl + K", "two-key result is committed")
release(GameKey.L)
press(GameKey.CONTROL)
press(GameKey.K)
expect(KeybindField.IsDown(field:GetValue()), true, "consumer can activate committed chord")
release(GameKey.K)
release(GameKey.CONTROL)

field.input.root:Fire(ui.Hook.ONMOUSEOVER, field.root.width - 10, 10)
expect(field.clearSprite.hidden, false, "hover exposes clear")
expect(field.tooltip._parts.label.content, "Reset Keybind", "sprite hover describes reset action")
field.input.root:Fire(ui.Hook.ONCLICK, field.root.width - 10, 10)
expect(KeybindField.FormatValue(field:GetValue()), "Ctrl + Shift", "clear sprite restores default binding")
expect(#changes, 2, "sprite reset notifies once")
expect(field:IsListening(), false, "sprite reset does not start capture")
field.input.root:Fire(ui.Hook.ONCLICK, 30, 10)
press(GameKey.K)
release(GameKey.K)
expect(KeybindField.FormatValue(field:GetValue()), "K", "single-key capture commits")
field.input.root:Fire(ui.Hook.ONMOUSEREPEAT, 30, 10)
expect(field.tooltip._parts.label.content, "change keybind", "moving off sprite updates tooltip without leaving field")
local entries = menu()
local reset
for _, entry in ipairs(entries) do if entry.label == "Reset to default" then reset = entry.callback end end
assert(reset, "right-click exposes provided default")
reset()
expect(KeybindField.FormatValue(field:GetValue()), "Ctrl + Shift", "reset restores default")
local detached = field:GetValue()
detached[1] = GameKey.L
expect(field:GetValue()[1], GameKey.CONTROL, "consumer cannot mutate internal binding")

press(GameKey.SHIFT)
field:StartListening()
press(GameKey.SHIFT, true)
press(GameKey.K)
release(GameKey.K)
expect(KeybindField.FormatValue(field:GetValue()), "K", "keys already held on entry are ignored")
release(GameKey.SHIFT)
field:StartListening()
press(GameKey.CONTROL)
press(GameKey.K)
release(GameKey.CONTROL)
press(GameKey.L)
release(GameKey.K)
release(GameKey.L)
expect(KeybindField.FormatValue(field:GetValue()), "Ctrl + K", "release phase does not admit later keys")

field:StartListening()
press(GameKey.L)
field.input.root:Fire(ui.Hook.ONCONTENTCHANGED, ui.InputFieldActionResult.SUBMIT_ON_FOCUS_LOSS)
release(GameKey.L)
expect(KeybindField.FormatValue(field:GetValue()), "Ctrl + K", "focus loss cancels unfinished capture")
field:StartListening()
emit("WindowFocusChanged", { hasFocus = false })
expect(field:IsListening(), false, "window focus loss cancels")
field:StartListening()
blocked = true
emit("Logic")
expect(field:IsListening(), false, "restricted input cancels capture")
blocked = false
field:StartListening()
field:SetDisabled(true)
press(GameKey.L)
release(GameKey.L)
expect(KeybindField.FormatValue(field:GetValue()), "Ctrl + K", "disabled field preserves value")
expect(field.clearSprite.hidden, true, "disabled field hides clear")
expect(field.tooltip._parts, nil, "disabling removes the visible tooltip")
field.input.root:Fire(ui.Hook.ONMOUSEOVER, 30, 10)
expect(field.tooltip._parts, nil, "disabled hover cannot show a tooltip")
field:SetDisabled(false)
field:StartListening()
field.input.root:Fire(ui.Hook.ONMOUSEOVER, 30, 10)
parent.hidden = true
emit("Logic")
expect(field:IsListening(), false, "hidden ancestor cancels capture")
expect(field.tooltip._parts, nil, "hiding an ancestor removes its tooltip")
parent.hidden = false

for _, point in ipairs({
    { field.root.width - 21, 10 }, -- left of sprite
    { field.root.width - 4, 10 }, -- right inset
    { field.root.width - 10, field.clearSprite.y - 1 }, -- above sprite
    { field.root.width - 10, field.clearSprite.y + field.clearSprite.height }, -- below sprite
}) do
    field.input.root:Fire(ui.Hook.ONMOUSEOVER, point[1], point[2])
    expect(field.tooltip._parts.label.content, "change keybind", "sprite edge exclusions retain the change action tooltip")
    field.input.root:Fire(ui.Hook.ONCLICK, point[1], point[2])
    expect(field:IsListening(), true, "outside sprite starts capture instead of resetting")
    expect(KeybindField.FormatValue(field:GetValue()), "Ctrl + K", "outside sprite preserves binding")
    field:CancelListening()
end
field:StartListening()
press(GameKey.L)
field.input.root:Fire(ui.Hook.ONMOUSEREPEAT, field.clearSprite.x, field.clearSprite.y)
expect(field.tooltip._parts.label.content, "Reset Keybind", "entering sprite bounds updates tooltip to reset")
field.input.root:Fire(ui.Hook.ONCLICK, field.clearSprite.x, field.clearSprite.y)
release(GameKey.L)
expect(field:IsListening(), false, "sprite reset cancels pending capture")
expect(KeybindField.FormatValue(field:GetValue()), "Ctrl + Shift", "pending key cannot replace reset value")
field.input.root:Fire(ui.Hook.ONMOUSELEAVE)
expect(field.clearSprite.hidden, true, "leaving hides clear sprite")
expect(field.tooltip._parts, nil, "leaving field removes its tooltip")

local second = KeybindField.new(parent)
second.input.root:Fire(ui.Hook.ONMOUSEOVER, 20, 10)
expect(#menu(), 0, "no reset menu without default")
field:StartListening()
second:StartListening()
expect(field:IsListening(), false, "capture transfers exclusively")
second:SetValue({ GameKey.K })
second.input.root:Fire(ui.Hook.ONMOUSEREPEAT, second.root.width - 5, 19)
second.input.root:Fire(ui.Hook.ONCLICK, second.root.width - 5, 19)
expect(#second:GetValue(), 0, "sprite resets to unbound without a default")
expect(second:IsListening(), false, "unbound reset does not start capture")
second:StartListening()
local secondTooltipRoot = second.tooltip._parts.root
second:Destroy()
expect(KeybindField.IsCapturing(), false, "destroy releases capture")
expect(secondTooltipRoot.destroyed, true, "destroying a hovered field removes its tooltip")
field:Destroy()
expect(next(handlers.KeyDown), nil, "last destroy releases keyboard subscription")

local SimpleView = require("src/simple_view")
local view = SimpleView.new(parent, { x = 80, y = 70, width = 500, height = 220, contentHeight = 600 })
local positioned = KeybindField.new(view.content, { x = 30, y = 260, width = 240 })
view:SetScrollPosition(100)
positioned.input.root:Fire(ui.Hook.ONMOUSEOVER, 30, 10)
expect(positioned.tooltip._parts.root.x, 152, "tooltip includes field and view horizontal offsets")
expect(positioned.tooltip._parts.root.y, 240, "tooltip includes field offset and view scroll position")
expect(positioned.tooltip._parts.root.parent, parent, "tooltip renders outside the scroll viewport")
positioned.input.root:Fire(ui.Hook.ONMOUSEREPEAT, 228, 12)
expect(positioned.tooltip._parts.label.content, "Reset Keybind", "positioned sprite hover selects reset tooltip")
expect(positioned.tooltip._parts.root.x, 350, "reset tooltip follows the cursor near the sprite")
expect(positioned.tooltip._parts.root.y, 242, "reset tooltip stays beside the field vertically")
view:SetScrollPosition(140)
positioned.input.root:Fire(ui.Hook.ONMOUSEREPEAT, 30, 10)
expect(positioned.tooltip._parts.root.y, 200, "tooltip follows a changed scroll position")
view.root:SetPos(120, 90)
positioned.input.root:Fire(ui.Hook.ONMOUSEREPEAT, 30, 10)
expect(positioned.tooltip._parts.root.x, 192, "tooltip follows a moved view horizontally")
expect(positioned.tooltip._parts.root.y, 220, "tooltip follows a moved view vertically")
positioned:Destroy()
view.root:SetPos(80, 70)
view:SetScrollPosition(100)
local nestedView = SimpleView.new(view.content, { x = 40, y = 150, width = 400, height = 180, contentHeight = 400 })
local nestedField = KeybindField.new(nestedView.content, { x = 20, y = 90 })
nestedView:SetScrollPosition(40)
nestedField.input.root:Fire(ui.Hook.ONMOUSEOVER, 30, 10)
expect(nestedField.tooltip._parts.root.x, 182, "nested tooltip includes both view horizontal offsets")
expect(nestedField.tooltip._parts.root.y, 180, "nested tooltip includes both view scroll offsets")
local nestedTooltipRoot = nestedField.tooltip._parts.root
require("src/tooltip").unregisterContext(view.content)
expect(nestedTooltipRoot.destroyed, true, "destroying the outer context releases nested keybind tooltips")
nestedField:Destroy()
nestedView:Destroy()
view:Destroy()

local Panel = require("src/panel")
local panel = Panel.new(parent, { width = 320, height = 240, popout = true })
local notifications = 0
local paired
paired = panel:AddKeybindField({
    defaultValue = { GameKey.SHIFT },
    onChange = function(control)
        expect(control, paired, "panel callback receives paired handle")
        notifications = notifications + 1
    end,
})
paired:StartListening()
press(GameKey.K)
release(GameKey.K)
expect(notifications, 1, "paired capture notifies once")
expect(paired.overlay:GetValue()[1], GameKey.K, "docked capture mirrors popout")
paired:SetValue({ GameKey.L }, true)
expect(notifications, 2, "paired programmatic change notifies once")
expect(paired.dock:GetValue()[1], GameKey.L, "programmatic change mirrors dock")
local pairedValue = paired:GetValue()
pairedValue[1] = GameKey.K
expect(paired:GetValue()[1], GameKey.L, "paired getter returns detached array")
paired:StartListening()
panel:SetPoppedOut(true)
expect(paired.overlay:IsListening(), true, "capture follows visible popout")
expect(paired.dock:IsListening(), false, "hidden dock is not listening")
press(GameKey.K)
release(GameKey.K)
expect(paired.dock:GetValue()[1], GameKey.K, "popout capture mirrors dock")
paired.overlay.input.root:Fire(ui.Hook.ONMOUSEOVER, paired.overlay.root.width - 10, 10)
paired.overlay.input.root:Fire(ui.Hook.ONCLICK, paired.overlay.root.width - 10, 10)
expect(notifications, 4, "popout sprite reset notifies once")
expect(paired.dock:GetValue()[1], GameKey.SHIFT, "popout sprite reset mirrors default to dock")
expect(paired:IsListening(), false, "paired sprite reset does not start capture")
local section = panel:AddCollapseButton("Keys", { expanded = true })
local nested = section:AddKeybindField()
nested:StartListening()
press(GameKey.L)
release(GameKey.L)
expect(nested.dock:GetValue()[1], GameKey.L, "nested paired section synchronizes")
local tabs = panel:AddTabs({ "Keys" }, { height = 140 })
local tabField = tabs:GetPage(1):AddKeybindField()
tabField:SetValue({ GameKey.CONTROL, GameKey.K }, true)
expect(tabField.overlay:GetValue()[2], GameKey.K, "paired tab page synchronizes")
panel:Destroy()

local shutdown = KeybindField.new(parent)
shutdown.input.root:Fire(ui.Hook.ONMOUSEOVER, 30, 10)
local shutdownTooltipRoot = shutdown.tooltip._parts.root
KeybindField.Shutdown()
expect(shutdownTooltipRoot.destroyed, true, "shutdown removes the active tooltip")
shutdown:Destroy()

local unloaded = KeybindField.new(parent)
unloaded.input.root:Fire(ui.Hook.ONMOUSEOVER, 30, 10)
unloaded:StartListening()
Interfaces.unload(parent.interfaceID)
emit("Logic")
expect(KeybindField.IsCapturing(), false, "interface unload safely releases capture")
expect(unloaded.tooltip._parts, nil, "interface unload safely releases the tooltip")
unloaded:Destroy()

print("keybind_field_test: ok")
