local TextField = require("src/text_field")
local Palette = require("src/core/control_palette")
local Wheel = require("src/core/wheel")
local Components = require("src/core/components")

local KeybindField = {}
KeybindField.__index = KeybindField

local EVENT_ID = "prettyui_keybind_field"
local CLEAR_SIZE = 16
local CLEAR_INSET = 8
local instances = {}
local active, hovered
local started = false

local function copy(value)
    local result = {}
    for i, key in ipairs(value or {}) do result[i] = key end
    return result
end

local function binding(value)
    local result = copy(value)
    assert(#result <= 2, "A keybind supports at most two keys")
    for i, key in ipairs(result) do
        assert(type(key) == "number" and GameKey.FromID(key) ~= nil,
            "A keybind must contain GameKey values")
        assert(i == 1 or key ~= result[1], "A keybind cannot repeat a key")
    end
    return result
end

local function available(field)
    return field and field.root and not field.disabled
        and ui.Interfaces:GetInterface(field.interfaceID) ~= nil
        and field.root.visibleGlobal
end

function KeybindField.FormatValue(value)
    local labels = {}
    for i, key in ipairs(value or {}) do
        local name = GameKey.FromID(key)
        if name == "CONTROL" then name = "Ctrl"
        elseif name == "SHIFT" then name = "Shift"
        elseif name == "ALT" then name = "Alt"
        else name = name:gsub("^_", ""):gsub("_", " ") end
        labels[i] = name
    end
    return table.concat(labels, " + ")
end

function KeybindField.IsCapturing()
    if active and (not available(active) or Keyboard.IsBlocked()) then
        active:CancelListening()
    end
    return active ~= nil
end

function KeybindField.IsDown(value)
    if KeybindField.IsCapturing() or not value or #value == 0
            or not Keyboard.IsAvailable() or Keyboard.IsBlocked() then return false end
    for _, key in ipairs(value) do
        if not Keyboard.IsGameKeyDown(key) then return false end
    end
    return true
end

local function stopEvents()
    if not started then return end
    Event.KeyDown.Unsubscribe(EVENT_ID)
    Event.KeyUp.Unsubscribe(EVENT_ID)
    Event.Logic.Unsubscribe(EVENT_ID)
    Event.WindowFocusChanged.Unsubscribe(EVENT_ID)
    Event.MiniMenuReady.Unsubscribe(EVENT_ID)
    started = false
end

local function startEvents()
    if started then return end
    started = true
    Event.KeyDown.Subscribe(EVENT_ID, function(event)
        if not KeybindField.IsCapturing() or event.isRepeat then return end
        local field, key = active, event.gameKey
        if field.releasing or field.ignored[key] or GameKey.FromID(key) == nil then return end
        for _, captured in ipairs(field.pending) do
            if captured == key then return end
        end
        if #field.pending == 2 then return end
        table.insert(field.pending, key)
        field.held[key] = true
        field:_UpdateState()
    end)
    Event.KeyUp.Subscribe(EVENT_ID, function(event)
        if not KeybindField.IsCapturing() then return end
        local field, key = active, event.gameKey
        field.ignored[key] = nil
        if not field.held[key] then return end
        field.held[key] = nil
        field.releasing = true
        if next(field.held) == nil then field:SetValue(field.pending, true) end
    end)
    Event.Logic.Subscribe(EVENT_ID, function()
        KeybindField.IsCapturing()
        if hovered and not available(hovered) then
            hovered.hovered = false
            hovered.clearHovered = false
            hovered:_UpdateState()
            hovered = nil
        end
    end)
    Event.WindowFocusChanged.Subscribe(EVENT_ID, function(event)
        if not event.hasFocus and active then active:CancelListening() end
    end)
    Event.MiniMenuReady.Subscribe(EVENT_ID, function(event)
        local field = hovered
        if not available(field) or field.defaultValue == nil then return end
        local menu = event.miniMenu
        menu:Add("Reset to default", function()
            if available(field) then field:SetValue(field.defaultValue, true) end
        end)
        -- Keep reset below an explicit left-click action.
        local clear = field.clearHovered
        menu:Add(field.clearHovered and "Clear keybind" or "Change keybind", function()
            if available(field) then field:_Click(clear) end
        end)
    end)
end

function KeybindField.getSize(options)
    return TextField.getSize(options)
end

function KeybindField.new(parent, options)
    options = options or {}
    local self = setmetatable({}, KeybindField)
    self.value = binding(options.value)
    self.defaultValue = options.defaultValue ~= nil and binding(options.defaultValue) or nil
    self.onChange = options.onChange
    self.disabled = options.disabled == true
    self.textColour = options.colour or options.color or Palette.TEXT
    self.interfaceID = parent.interfaceID
    self.root = Components.new(ui.Layer, parent)
    self.root:SetPos(options.x or 0, options.y or 0, options.xAnchor or 0, options.yAnchor or 0)
    local width, height = KeybindField.getSize(options)
    self.root:SetSize(width, height, options.widthAnchor or 0, options.heightAnchor or 0)
    self.root.clickthrough = true

    self.input = TextField.new(self.root, {
        width = 0, height = 0, widthAnchor = 1, heightAnchor = 1,
        stylesheetID = options.stylesheetID, inputSprite = options.inputSprite,
        disabled = self.disabled, maxLength = 1, colour = 0, caretColour = 0,
        selectionColour = 0,
        onChange = function(_, reason)
            self.input:SetText("")
            if reason == ui.InputFieldActionResult.SUBMIT_ON_FOCUS_LOSS then
                self:CancelListening()
            end
        end,
    })
    self.input.root.errorCaretRGBA = 0
    Wheel.bind(self.input.root, options)

    self.focusOutline = Components.new(ui.Rectangle, self.root)
    self.focusOutline:SetSize(0, 0, 1, 1)
    self.focusOutline.fill = false
    self.focusOutline.outlineThickness = 1
    self.focusOutline.clickthrough = true

    self.label = Components.new(ui.Text, self.root)
    self.label:SetPos(CLEAR_SIZE + CLEAR_INSET, 0)
    self.label:SetSize(-2 * (CLEAR_SIZE + CLEAR_INSET), 0, 1, 1)
    self.label.font = options.font or id.Font.MUSEO_SANS_15PT_REGULAR
    self.label.alignHorizontal = ui.AlignMode.CENTRE
    self.label.alignVertical = ui.AlignMode.CENTRE
    self.label.maxLines = 1
    self.label.isShadowed = options.shadowed ~= false
    self.label.clickthrough = true

    self.clearSprite = Components.new(ui.Sprite, self.root)
    self.clearSprite:SetSize(CLEAR_SIZE, CLEAR_SIZE)
    self.clearSprite:SetPos(-CLEAR_INSET, 0, 1, 0.5, -1, -0.5)
    self.clearSprite.spriteID = id.Sprite.RS3_CONTEXTUAL_INPUT_ERROR
    self.clearSprite.clickthrough = true

    local function hover(_, x)
        if self.disabled then return false end
        hovered = self
        self.hovered = true
        self.clearHovered = x >= self.input.root.width - CLEAR_SIZE - CLEAR_INSET
        self:_UpdateState()
        return true
    end
    self.input.root:Subscribe(ui.Hook.ONMOUSEOVER, hover)
    self.input.root:Subscribe(ui.Hook.ONMOUSEREPEAT, hover)
    self.input.root:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        if hovered == self then hovered = nil end
        self.hovered, self.clearHovered = false, false
        self:_UpdateState()
        return true
    end)
    self.input.root:Subscribe(ui.Hook.ONCLICK, function(_, x)
        self:_Click(self.hovered and x >= self.input.root.width - CLEAR_SIZE - CLEAR_INSET)
        return true
    end)
    instances[self] = true
    startEvents()
    self:_UpdateState()
    return self
end

function KeybindField:_UpdateState()
    if not self.root or ui.Interfaces:GetInterface(self.interfaceID) == nil then return end
    self.label.content = KeybindField.FormatValue(self.pending or self.value)
    self.label.rgba = self.disabled and Palette.DISABLED_TEXT or self.textColour
    self.clearSprite.hidden = self.disabled or not self.hovered
    self.focusOutline.hidden = self.disabled or not (self.hovered or active == self)
    self.focusOutline.rgba = active == self and Palette.CARET or Palette.SELECTED
end

function KeybindField:_Click(clear)
    if not available(self) then return end
    if clear then self:SetValue({}, #self.value > 0) end
    self:StartListening()
end

function KeybindField:StartListening()
    if not available(self) or not Keyboard.IsAvailable() or Keyboard.IsBlocked() then return end
    if active == self then return end
    if active then active:CancelListening() end
    self.pending, self.held, self.ignored = {}, {}, {}
    for _, key in ipairs(Keyboard.GetGameKeysDown()) do self.ignored[key] = true end
    self.releasing = false
    active = self
    self:_UpdateState()
end

function KeybindField:CancelListening()
    if active ~= self then return end
    active = nil
    self.pending, self.held, self.ignored = nil, nil, nil
    self.releasing = false
    self:_UpdateState()
end

function KeybindField:IsListening()
    return KeybindField.IsCapturing() and active == self
end

function KeybindField:GetValue()
    return copy(self.value)
end

function KeybindField:SetValue(value, notify)
    local nextValue = binding(value)
    self:CancelListening()
    self.value = nextValue
    self:_UpdateState()
    if notify == true and self.onChange then self.onChange(self, self:GetValue()) end
end

function KeybindField:SetDisabled(disabled)
    self.disabled = disabled == true
    if self.disabled then
        self:CancelListening()
        if hovered == self then hovered = nil end
        self.hovered, self.clearHovered = false, false
    end
    self.input:SetDisabled(self.disabled)
    self:_UpdateState()
end

function KeybindField:Destroy()
    self:CancelListening()
    if hovered == self then hovered = nil end
    instances[self] = nil
    self.input:Destroy()
    if self.root then
        if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.root:Destroy() end
        self.root = nil
    end
    if next(instances) == nil then stopEvents() end
end

function KeybindField.Shutdown()
    if active then active:CancelListening() end
    hovered = nil
    stopEvents()
end

return KeybindField
