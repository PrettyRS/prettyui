local Components = require("src/core/components")
local clamp = require("src/core/math").clamp
local Cursor = require("src/core/cursor")
local Sprites = require("src/core/sprites")
local Tooltip = require("src/tooltip")
local Wheel = require("src/core/wheel")
local InterfaceMouse = require("src/core/mouse")

local Slider = {}
Slider.__index = Slider

local BUTTON_SIZE = 23
local DEFAULT_BUTTON_GAP = 4
local BACKING_END_WIDTH = 6
local BACKING_HEIGHT = 12
local BAR_END_WIDTH = 5
local BAR_HEIGHT = 5
local THUMB_WIDTH = 11
local THUMB_HEIGHT = 19
local DEFAULT_WIDTH = 220
local HEIGHT = 23

local function sprite(parent, spriteID)
    local component = Components.new(ui.Sprite, parent)
    component.spriteID = spriteID
    component.clickthrough = true
    return component
end

local function interactiveSprite(parent)
    local component = Components.new(ui.Sprite, parent)
    component.clickthrough = false
    return component
end

local function configureRange(options)
    local minimum = tonumber(options.min) or 0
    local maximum = tonumber(options.max) or 100
    if maximum <= minimum then error("Slider max must be greater than min") end
    local step = tonumber(options.step) or 1
    if step <= 0 then error("Slider step must be greater than zero") end
    return minimum, maximum, step
end

function Slider.getSize(options)
    options = options or {}
    local buttonGap = math.max(0, tonumber(options.buttonGap) or DEFAULT_BUTTON_GAP)
    local minimumWidth = BUTTON_SIZE * 2 + buttonGap * 2 + BACKING_END_WIDTH * 2
    return math.max(minimumWidth, options.width or DEFAULT_WIDTH), HEIGHT
end

function Slider.new(parent, options)
    options = options or {}
    local requestedWidth = Slider.getSize(options)

    local self = setmetatable({}, Slider)
    self.parent = parent
    self.min, self.max, self.step = configureRange(options)
    self.value = self.min
    self._valueLaidOut = false
    self.onChange = options.onChange
    self.disabled = options.disabled == true
    self.buttonGap = math.max(0, tonumber(options.buttonGap) or DEFAULT_BUTTON_GAP)
    self.hoverCursor = options.hoverCursor or config.Cursor.CURSOR_BLANK
    self.dragStart = nil

    self.interfaceID = parent.interfaceID
    self.root = Components.new(ui.Layer, parent)
    self.root:SetPos(options.x or 0, options.y or 0, options.xAnchor or 0, options.yAnchor or 0)
    self.root:SetSize(options.width or requestedWidth, HEIGHT, options.widthAnchor or 0)
    self.root.clickthrough = false
    Wheel.bind(self.root, options)

    self.decrease = interactiveSprite(self.root)
    self.decrease:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    self.increase = interactiveSprite(self.root)
    self.increase:SetPos(-BUTTON_SIZE, 0, 1.0)
    self.increase:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    Wheel.bind(self.decrease, options)
    Wheel.bind(self.increase, options)

    self.track = Components.new(ui.Layer, self.root)
    self.track:SetPos(BUTTON_SIZE + self.buttonGap, 0)
    self.track:SetSize(-(BUTTON_SIZE + self.buttonGap) * 2, HEIGHT, 1.0)
    self.track.clickthrough = false
    Wheel.bind(self.track, options)

    local backingY = math.floor((HEIGHT - BACKING_HEIGHT) / 2)
    self.backingLeft = sprite(self.track, Sprites.SLIDER.backingEnd)
    self.backingLeft:SetPos(0, backingY)
    self.backingLeft:SetSize(BACKING_END_WIDTH, BACKING_HEIGHT)
    self.backingMiddle = sprite(self.track, Sprites.SLIDER.backingTile)
    self.backingMiddle:SetPos(BACKING_END_WIDTH, backingY)
    self.backingMiddle:SetSize(-BACKING_END_WIDTH * 2, BACKING_HEIGHT, 1.0)
    self.backingMiddle.isTiling = true
    self.backingRight = sprite(self.track, Sprites.SLIDER.backingEnd)
    self.backingRight:SetPos(-BACKING_END_WIDTH, backingY, 1.0)
    self.backingRight:SetSize(BACKING_END_WIDTH, BACKING_HEIGHT)
    self.backingRight.isFlippedHorizontally = true

    local barY = math.floor((HEIGHT - BAR_HEIGHT) / 2)
    self.barLeft = sprite(self.track, Sprites.SLIDER.barEnd)
    self.barLeft:SetPos(0, barY)
    self.barLeft:SetSize(BAR_END_WIDTH, BAR_HEIGHT)
    self.barMiddle = sprite(self.track, Sprites.SLIDER.barTile)
    self.barMiddle:SetPos(BAR_END_WIDTH, barY)
    self.barMiddle:SetSize(0, BAR_HEIGHT)
    self.barMiddle.isTiling = true
    self.barRight = sprite(self.track, Sprites.SLIDER.barEnd)
    self.barRight:SetPos(0, barY)
    self.barRight:SetSize(BAR_END_WIDTH, BAR_HEIGHT)
    self.barRight.isFlippedHorizontally = true

    self.thumb = sprite(self.track, Sprites.SLIDER.thumb.normal)
    self.thumb:SetPos(0, math.floor((HEIGHT - THUMB_HEIGHT) / 2))
    self.thumb:SetSize(THUMB_WIDTH, THUMB_HEIGHT)

    self.thumbDrag = Components.new(ui.Layer, self.parent)
    self.thumbDrag.clickthrough = false
    self.thumbDrag:MoveToFront()
    Wheel.bind(self.thumbDrag, options)

    self:_BindButton(self.decrease, -1)
    self:_BindButton(self.increase, 1)

    self.track:Subscribe(ui.Hook.ONCLICK, function(_, clickX)
        if self.disabled then return false end
        local travel = math.max(1, self.track.width - THUMB_WIDTH)
        local ratio = clamp((clickX - THUMB_WIDTH / 2) / travel, 0, 1)
        self:SetValue(self.min + ratio * (self.max - self.min))
        return false
    end)

    self.thumbDrag:Subscribe(ui.Hook.ONMOUSEOVER, function()
        self.thumbHovered = true
        self:_UpdateState()
        return true
    end)
    self.thumbDrag:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        self.thumbHovered = false
        self:_UpdateState()
        return true
    end)
    self.thumbDrag:Subscribe(ui.Hook.ONCLICK, function(component, x, y)
        if self.disabled then return false end
        InterfaceMouse.BeginCapture(component)
        local mouse = InterfaceMouse.GetPosition(component, x, y)
        self.thumbPressed = true
        if mouse then self.dragStart = { mouseX = mouse.x, value = self.value } end
        self.thumbDrag:SetPos(0, 0)
        self.thumbDrag:SetSize(0, 0, 1.0, 1.0)
        self.thumbDrag:MoveToFront()
        self:_UpdateState()
        return false
    end)
    self.thumbDrag:Subscribe(ui.Hook.ONHOLD, function(component, x, y)
        return self:_UpdateDrag(component, x, y)
    end)
    self.thumbDrag:Subscribe(ui.Hook.ONDRAG, function(component, x, y)
        return self:_UpdateDrag(component, x, y)
    end)
    self.thumbDrag:Subscribe(ui.Hook.ONRELEASE, function()
        return self:_StopDrag()
    end)
    self.thumbDrag:Subscribe(ui.Hook.ONDRAGCOMPLETE, function()
        return self:_StopDrag()
    end)

    self:SetValue(options.value == nil and self.min or options.value, false)
    self:SetDisabled(self.disabled)
    Tooltip.bind(self, self.root, parent, options.tooltip)
    return self
end

function Slider:_BindButton(component, direction)
    local state = { hovered = false, pressed = false }
    if direction < 0 then
        self.decreaseState = state
    else
        self.increaseState = state
    end
    component:Subscribe(ui.Hook.ONMOUSEOVER, function()
        state.hovered = true
        self:_UpdateState()
        return true
    end)
    component:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        state.hovered = false
        state.pressed = false
        self:_UpdateState()
        return true
    end)
    component:Subscribe(ui.Hook.ONCLICK, function()
        if self.disabled or (direction < 0 and self.value <= self.min) or
            (direction > 0 and self.value >= self.max) then return false end
        state.pressed = true
        self:SetValue(self.value + direction * self.step)
        return false
    end)
    component:Subscribe(ui.Hook.ONRELEASE, function()
        state.pressed = false
        self:_UpdateState()
        return false
    end)
end

function Slider:_ButtonState(state, atLimit)
    if self.disabled then return "disabled" end
    if state.pressed then return "pressed" end
    if atLimit then return "disabled" end
    if state.hovered then return "hovered" end
    return "normal"
end

function Slider:_UpdateState()
    if self.root == nil then return end
    local states = Sprites.SLIDER
    self.decrease.spriteID = states.decrease[self:_ButtonState(self.decreaseState, self.value <= self.min)]
    self.increase.spriteID = states.increase[self:_ButtonState(self.increaseState, self.value >= self.max)]
    local thumbState = "normal"
    if self.disabled then
        thumbState = "disabled"
    elseif self.thumbPressed then
        thumbState = "pressed"
    elseif self.thumbHovered then
        thumbState = "hovered"
    end
    self.thumb.spriteID = states.thumb[thumbState]
    self.track.enabled = not self.disabled
    self.track.clickthrough = self.disabled
    self.decrease.enabled = not self.disabled and (self.decreaseState.pressed or self.value > self.min)
    self.decrease.clickthrough = not self.decrease.enabled
    self.increase.enabled = not self.disabled and (self.increaseState.pressed or self.value < self.max)
    self.increase.clickthrough = not self.increase.enabled
    Cursor.apply(self.decrease, self.hoverCursor, self.decrease.enabled)
    Cursor.apply(self.increase, self.hoverCursor, self.increase.enabled)
    self.thumbDrag.enabled = not self.disabled
    self.thumbDrag.clickthrough = self.disabled
    Cursor.apply(self.thumbDrag, self.hoverCursor, not self.disabled)
end

function Slider:_LayoutValue()
    local ratio = (self.value - self.min) / (self.max - self.min)
    local travel = math.max(0, self.track.width - THUMB_WIDTH)
    local thumbX = math.floor(travel * ratio + 0.5)
    self.thumb:SetX(thumbX)

    local filledWidth = thumbX + math.ceil(THUMB_WIDTH / 2)
    local middleWidth = math.max(0, filledWidth - BAR_END_WIDTH * 2)
    local barHidden = self.value <= self.min
    self.barLeft.hidden = barHidden
    self.barMiddle:SetWidth(middleWidth)
    self.barMiddle.hidden = barHidden or middleWidth == 0
    self.barRight:SetX(math.max(BAR_END_WIDTH, filledWidth - BAR_END_WIDTH))
    self.barRight.hidden = barHidden
    if self.dragStart == nil then self:_LayoutThumbDrag() end
end

function Slider:_LayoutThumbDrag()
    if self.thumbDrag == nil or self.root == nil then return end
    self.thumbDrag:SetPos(
        (self.root.x or 0) + (self.track.x or 0) + (self.thumb.x or 0),
        (self.root.y or 0) + (self.track.y or 0) + (self.thumb.y or 0)
    )
    self.thumbDrag:SetSize(THUMB_WIDTH, THUMB_HEIGHT)
end

function Slider:_UpdateDrag(component, x, y)
    local mouse = InterfaceMouse.GetPosition(component, x, y)
    if self.disabled or self.dragStart == nil or mouse == nil then return false end
    local travel = math.max(1, self.track.width - THUMB_WIDTH)
    local range = self.max - self.min
    self:SetValue(self.dragStart.value + (mouse.x - self.dragStart.mouseX) * range / travel)
    return false
end

function Slider:_StopDrag()
    InterfaceMouse.EndCapture(self.thumbDrag)
    self.dragStart = nil
    self.thumbPressed = false
    self.thumbHovered = false
    if self.root and self.thumbDrag and ui.Interfaces:GetInterface(self.interfaceID) ~= nil then
        self:_LayoutThumbDrag()
        self:_UpdateState()
    end
    return false
end

function Slider:SetValue(value, notify)
    value = clamp(tonumber(value) or self.min, self.min, self.max)
    value = self.min + math.floor((value - self.min) / self.step + 0.5) * self.step
    value = clamp(value, self.min, self.max)
    local changed = value ~= self.value
    if not changed and self._valueLaidOut then return false end
    self.value = value
    self._valueLaidOut = true
    self:_LayoutValue()
    self:_UpdateState()
    if changed and notify ~= false and self.onChange then self.onChange(self, self.value) end
    return changed
end

function Slider:GetValue()
    return self.value
end

function Slider:SetDisabled(disabled)
    self.disabled = disabled == true
    self.decreaseState.hovered = false
    self.decreaseState.pressed = false
    self.increaseState.hovered = false
    self.increaseState.pressed = false
    if self.disabled then self:_StopDrag() end
    self:_UpdateState()
end

function Slider:SetTooltip(value)
    return Tooltip.set(self, value)
end

function Slider:Destroy()
    self:_StopDrag()
    Tooltip.unbind(self)
    local loaded = ui.Interfaces:GetInterface(self.interfaceID) ~= nil
    if self.thumbDrag then
        if loaded then self.thumbDrag:Destroy() end
        self.thumbDrag = nil
    end
    if self.root then
        if loaded then self.root:Destroy() end
        self.root = nil
    end
    self.parent = nil
    self.onChange = nil
end

return Slider
