local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function component(parent, categoryID, dynamicID)
    local value = { parent = parent, x = 0, y = 0, hidden = false, subscriptions = {},
        text = {}, containerSprite = {},
        opConfig = { ClearOpCursors = function() end, SetOpCursor = function() end }, cursorConfig = {} }
    setmetatable(value, { __index = function(self, key)
        if key == "width" then return (self.w or 0) + (parent and parent.width or 0) * (self.wa or 0) end
        if key == "height" then return (self.h or 0) + (parent and parent.height or 0) * (self.ha or 0) end
        if key == "visibleGlobal" then return not self.hidden and (not parent or parent.visibleGlobal) end
    end })
    function value:SetPos(x, y) self.x, self.y = x, y end
    function value:SetY(y) self.y = y end
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
field.input.root:Fire(ui.Hook.ONCLICK, field.root.width - 10, 10)
expect(#field:GetValue(), 0, "clear removes committed binding")
expect(field:IsListening(), true, "clear immediately listens")
press(GameKey.K)
release(GameKey.K)
expect(KeybindField.FormatValue(field:GetValue()), "K", "single-key capture commits")
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
field:SetDisabled(false)
field:StartListening()
parent.hidden = true
emit("Logic")
expect(field:IsListening(), false, "hidden ancestor cancels capture")
parent.hidden = false

local second = KeybindField.new(parent)
second.input.root:Fire(ui.Hook.ONMOUSEOVER, 20, 10)
expect(#menu(), 0, "no reset menu without default")
field:StartListening()
second:StartListening()
expect(field:IsListening(), false, "capture transfers exclusively")
second:Destroy()
expect(KeybindField.IsCapturing(), false, "destroy releases capture")
field:Destroy()
expect(next(handlers.KeyDown), nil, "last destroy releases keyboard subscription")

local Panel = require("src/panel")
local panel = Panel.new(parent, { width = 320, height = 240, popout = true })
local notifications = 0
local paired
paired = panel:AddKeybindField({
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

local unloaded = KeybindField.new(parent)
unloaded:StartListening()
Interfaces.unload(parent.interfaceID)
emit("Logic")
expect(KeybindField.IsCapturing(), false, "interface unload safely releases capture")
unloaded:Destroy()

print("keybind_field_test: ok")
