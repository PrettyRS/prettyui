local Sprites = require("src/core/sprites")
local Tooltip = require("src/tooltip")
local Cursor = require("src/core/cursor")
local Wheel = require("src/core/wheel")
local Components = require("src/core/components")

local FancyButton = {}
FancyButton.__index = FancyButton

local PART_WIDTH = 25
local HEIGHT = 27
local MIN_WIDTH = PART_WIDTH * 3
local TEXT_PADDING = 12
local FONT = id.Font.CINZEL_13PT_BOLD
local TEXT_COLOURS = {
    neutral = 0xC8F1FFFF,
    positive = 0x372D1EFF,
    negative = 0xDCB58DFF,
}

local function withAlpha(colour, alpha)
    return colour - (colour % 0x100) + alpha
end

local function resolveVariant(variant)
    if variant ~= nil and type(variant) ~= "string" then
        error("FancyButton variant must be a string")
    end
    local name = string.lower(variant or "neutral")
    local sprites = Sprites.FANCY_BUTTON[name]
    if sprites == nil then error("Unknown FancyButton variant: " .. tostring(variant)) end
    return name, sprites
end

local function measureText(text)
    local succeeded, width = pcall(function()
        return config.Font.CINZEL_13PT_BOLD:GetStringWidth(text, false)
    end)
    return succeeded and width or #text * 9
end

function FancyButton.getSize(text, options)
    options = options or {}
    text = tostring(text or "")
    local middleWidth = math.ceil((measureText(text) + TEXT_PADDING * 2) / PART_WIDTH) * PART_WIDTH
    local contentWidth = PART_WIDTH * 2 + middleWidth
    return math.max(MIN_WIDTH, options.width or 0, contentWidth), HEIGHT
end

local function part(parent)
    local sprite = Components.new(ui.Sprite, parent)
    sprite.clickthrough = true
    return sprite
end

function FancyButton.new(parent, text, action, options)
    options = options or {}
    text = tostring(text or "")
    local width = FancyButton.getSize(text, options)

    local self = setmetatable({}, FancyButton)
    self.action = action
    self.minimumWidth = options.width or 0
    self.disabled = options.disabled == true
    self.hovered = false
    self.pressed = false
    self.variant, self.sprites = resolveVariant(options.variant)
    self.hasCustomTextColour = options.colour ~= nil
    self.hasCustomDisabledTextColour = options.disabledColour ~= nil
    self.textColour = options.colour or TEXT_COLOURS[self.variant]
    self.disabledTextColour = options.disabledColour or withAlpha(self.textColour, 0x80)
    self.hoverCursor = options.hoverCursor or config.Cursor.CURSOR_BLANK

    self.interfaceID = parent.interfaceID
    self.root = Components.new(ui.Layer, parent)
    self.root:SetPos(options.x or 0, options.y or 0, options.xAnchor or 0, options.yAnchor or 0)
    self.root:SetSize(width, HEIGHT)
    Wheel.bind(self.root, options)

    self.left = part(self.root)
    self.left:SetSize(PART_WIDTH, HEIGHT)

    self.middle = part(self.root)
    self.middle:SetPos(PART_WIDTH, 0)
    self.middle:SetSize(-PART_WIDTH * 2, HEIGHT, 1.0)
    self.middle.isTiling = true

    self.right = part(self.root)
    self.right:SetPos(-PART_WIDTH, 0, 1.0)
    self.right:SetSize(PART_WIDTH, HEIGHT)

    self.label = Components.new(ui.Text, self.root)
    self.label:SetPos(PART_WIDTH, 0)
    self.label:SetSize(-PART_WIDTH * 2, HEIGHT, 1.0)
    self.label.content = text
    self.label.font = FONT
    self.label.isShadowed = false
    self.label.alignHorizontal = ui.AlignMode.CENTRE
    self.label.alignVertical = ui.AlignMode.CENTRE
    self.label.maxLines = 1
    self.label.clickthrough = true

    self.root:Subscribe(ui.Hook.ONMOUSEOVER, function()
        if self.disabled then return false end
        self.hovered = true
        self:_UpdateState()
        return true
    end)
    self.root:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        self.hovered = false
        self.pressed = false
        self:_UpdateState()
        return true
    end)
    self.root:Subscribe(ui.Hook.ONCLICK, function()
        if self.disabled then return false end
        self.pressed = true
        self:_UpdateState()
        if self.action then self.action(self) end
        return false
    end)
    self.root:Subscribe(ui.Hook.ONRELEASE, function()
        self.pressed = false
        self:_UpdateState()
        return false
    end)

    self:_UpdateState()
    Tooltip.bind(self, self.root, parent, options.tooltip)
    return self
end

function FancyButton:_UpdateState()
    self.root.enabled = not self.disabled
    self.root.clickthrough = self.disabled
    local state = "normal"
    if self.disabled then
        state = "disabled"
    elseif self.pressed then
        state = "pressed"
    elseif self.hovered then
        state = "hovered"
    end
    local sprites = self.sprites[state]
    self.left.spriteID = sprites.left
    self.middle.spriteID = sprites.middle
    self.right.spriteID = sprites.right
    self.label.rgba = self.disabled and self.disabledTextColour or self.textColour
    Cursor.apply(self.root, self.hoverCursor, not self.disabled)
end

function FancyButton:SetDisabled(disabled)
    self.disabled = disabled == true
    self.hovered = false
    self.pressed = false
    self:_UpdateState()
end

function FancyButton:SetTooltip(value)
    return Tooltip.set(self, value)
end

function FancyButton:SetVariant(variant)
    self.variant, self.sprites = resolveVariant(variant)
    if not self.hasCustomTextColour then self.textColour = TEXT_COLOURS[self.variant] end
    if not self.hasCustomDisabledTextColour then
        self.disabledTextColour = withAlpha(self.textColour, 0x80)
    end
    self:_UpdateState()
end

function FancyButton:SetText(text)
    text = tostring(text or "")
    self.label.content = text
    local width = FancyButton.getSize(text, { width = self.minimumWidth })
    self.root:SetSize(width, HEIGHT)
    if self._onPreferredWidthChanged then self._onPreferredWidthChanged(self, width) end
end

function FancyButton:SetHoverCursor(cursor)
    self.hoverCursor = cursor
    Cursor.apply(self.root, self.hoverCursor, not self.disabled)
end

function FancyButton:Destroy()
    Tooltip.unbind(self)
    if self.root then
        if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.root:Destroy() end
        self.root = nil
        self.left = nil
        self.middle = nil
        self.right = nil
        self.label = nil
    end
end

return FancyButton
