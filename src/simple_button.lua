local Components = require("src/core/components")
local Sprites = require("src/core/sprites")
local Tooltip = require("src/tooltip")
local Cursor = require("src/core/cursor")
local Wheel = require("src/core/wheel")

local SimpleButton = {}
SimpleButton.__index = SimpleButton

local TILE_SIZE = 8
local TEXT_HEIGHT = TILE_SIZE * 3
local ICON_BUTTON_SIZE = TILE_SIZE * 3
local ICON_SIZE = 12
local ICON_INSET = 4
local MIN_TEXT_WIDTH = TILE_SIZE * 3
local TEXT_COLOUR = 0xFFFFFFFF
local DISABLED_TEXT_COLOUR = 0x777777FF

local PIECES = {
    "topRight", "topLeft", "top", "left", "centre", "right",
    "bottomLeft", "bottom", "bottomRight",
}

local function validateContent(content)
    local contentType = type(content)
    if contentType ~= "string" and contentType ~= "number" then
        error("SimpleButton content must be text or a sprite ID")
    end
    return contentType
end

local function measureText(text)
    local succeeded, width = pcall(function()
        return config.Font.MUSEO_SANS_15PT_REGULAR:GetStringWidth(text, false)
    end)
    return succeeded and width or #text * 7
end

local function roundToTile(value)
    return math.ceil(value / TILE_SIZE) * TILE_SIZE
end

function SimpleButton.getSize(content, options)
    options = options or {}
    local contentType = validateContent(content)
    if contentType == "number" then
        local size = options.size or ICON_BUTTON_SIZE
        return options.width or size, options.height or size
    end
    local width = math.max(MIN_TEXT_WIDTH, roundToTile(measureText(content) + TILE_SIZE * 2))
    return options.width or width, options.height or TEXT_HEIGHT
end

local function backgroundSprite(parent, tiled)
    local component = Components.new(ui.Sprite, parent)
    component.clickthrough = true
    component.isTiling = tiled == true
    return component
end

function SimpleButton.new(parent, content, action, options)
    options = options or {}
    local contentType = validateContent(content)
    local width, height = SimpleButton.getSize(content, options)

    local self = setmetatable({}, SimpleButton)
    self.action = action
    self.toggleable = options.toggleable == true
    self.disabled = options.disabled == true
    self.active = options.active == true
    self.hovered = false
    self.pressed = false
    self.contentType = contentType
    self.textColour = options.colour or TEXT_COLOUR
    self.disabledTextColour = options.disabledColour or DISABLED_TEXT_COLOUR
    self.hoverCursor = options.hoverCursor or config.Cursor.CURSOR_BLANK

    self.interfaceID = parent.interfaceID
    self.root = Components.new(ui.Layer, parent)
    self.root:SetPos(options.x or 0, options.y or 0, options.xAnchor or 0, options.yAnchor or 0)
    self.root:SetSize(width, height)
    Wheel.bind(self.root, options)

    self.parts = {}
    for _, name in ipairs(PIECES) do
        self.parts[name] = backgroundSprite(self.root,
            name == "top" or name == "left" or name == "centre" or
            name == "right" or name == "bottom")
    end

    self.parts.topLeft:SetSize(TILE_SIZE, TILE_SIZE)
    self.parts.top:SetPos(TILE_SIZE, 0)
    self.parts.top:SetSize(-TILE_SIZE * 2, TILE_SIZE, 1.0)
    self.parts.topRight:SetPos(-TILE_SIZE, 0, 1.0)
    self.parts.topRight:SetSize(TILE_SIZE, TILE_SIZE)
    self.parts.left:SetPos(0, TILE_SIZE)
    self.parts.left:SetSize(TILE_SIZE, -TILE_SIZE * 2, 0, 1.0)
    self.parts.centre:SetPos(TILE_SIZE, TILE_SIZE)
    self.parts.centre:SetSize(-TILE_SIZE * 2, -TILE_SIZE * 2, 1.0, 1.0)
    self.parts.right:SetPos(-TILE_SIZE, TILE_SIZE, 1.0)
    self.parts.right:SetSize(TILE_SIZE, -TILE_SIZE * 2, 0, 1.0)
    self.parts.bottomLeft:SetPos(0, -TILE_SIZE, 0, 1.0)
    self.parts.bottomLeft:SetSize(TILE_SIZE, TILE_SIZE)
    self.parts.bottom:SetPos(TILE_SIZE, -TILE_SIZE, 0, 1.0)
    self.parts.bottom:SetSize(-TILE_SIZE * 2, TILE_SIZE, 1.0)
    self.parts.bottomRight:SetPos(-TILE_SIZE, -TILE_SIZE, 1.0, 1.0)
    self.parts.bottomRight:SetSize(TILE_SIZE, TILE_SIZE)

    if contentType == "number" then
        local requestedWidth = math.max(1, options.iconWidth or options.iconSize or ICON_SIZE)
        local requestedHeight = math.max(1, options.iconHeight or options.iconSize or ICON_SIZE)
        local availableWidth = math.max(1, width - ICON_INSET * 2)
        local availableHeight = math.max(1, height - ICON_INSET * 2)
        local scale = math.min(1, availableWidth / requestedWidth, availableHeight / requestedHeight)
        local iconWidth = math.max(1, math.floor(requestedWidth * scale))
        local iconHeight = math.max(1, math.floor(requestedHeight * scale))
        self.content = Components.new(ui.Sprite, self.root)
        self.content:SetSize(iconWidth, iconHeight)
        self.content:SetPos(
            math.floor((width - iconWidth) / 2),
            math.floor((height - iconHeight) / 2)
        )
        self.content.spriteID = content
    else
        self.content = Components.new(ui.Text, self.root)
        self.content:SetPos(TILE_SIZE, 0)
        self.content:SetSize(-TILE_SIZE * 2, 0, 1.0, 1.0)
        self.content.content = content
        self.content.font = id.Font.MUSEO_SANS_15PT_REGULAR
        self.content.rgba = self.textColour
        self.content.isShadowed = options.shadowed ~= false
        self.content.alignHorizontal = ui.AlignMode.CENTRE
        self.content.alignVertical = ui.AlignMode.CENTRE
        self.content.maxLines = 1
    end
    self.content.clickthrough = true

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
        if self.toggleable then self.active = not self.active end
        self:_UpdateState()
        if self.action then self.action(self, self.active) end
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

function SimpleButton:_UpdateState()
    self.root.enabled = not self.disabled
    self.root.clickthrough = self.disabled
    local state = "neutral"
    if self.disabled then
        state = "disabled"
    elseif self.active or self.pressed then
        state = "active"
    elseif self.hovered then
        state = "hovered"
    end
    local sprites = Sprites.SIMPLE_BUTTON[state]
    Cursor.apply(self.root, self.hoverCursor, not self.disabled)
    if self.contentType == "string" then
        self.content.rgba = self.disabled and self.disabledTextColour or self.textColour
    end
    for _, name in ipairs(PIECES) do self.parts[name].spriteID = sprites[name] end
end

function SimpleButton:SetDisabled(disabled)
    self.disabled = disabled == true
    self.hovered = false
    self.pressed = false
    self:_UpdateState()
end

function SimpleButton:SetActive(active)
    self.active = active == true
    self:_UpdateState()
end

function SimpleButton:SetHoverCursor(cursor)
    self.hoverCursor = cursor
    Cursor.apply(self.root, self.hoverCursor, not self.disabled)
end

function SimpleButton:SetTooltip(value)
    return Tooltip.set(self, value)
end

function SimpleButton:Destroy()
    Tooltip.unbind(self)
    if self.root then
        if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.root:Destroy() end
        self.root = nil
        self.content = nil
        self.parts = nil
    end
end

return SimpleButton
