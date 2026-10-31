local Components = require("src/core/components")
local Sprites = require("src/core/sprites")
local Tooltip = require("src/tooltip")
local Cursor = require("src/core/cursor")
local Wheel = require("src/core/wheel")

local SpriteButton = {}
SpriteButton.__index = SpriteButton

local DEFAULT_SIZE = 24

local function resolveSprites(name)
    if type(name) ~= "string" then error("SpriteButton sprite name must be a string") end
    local normalizedName = string.upper(name)
    local spriteSet = Sprites.SPRITE_BUTTONS[normalizedName]
    if spriteSet == nil then error("Unknown SpriteButton sprite: " .. name) end
    return normalizedName, spriteSet
end

local function defaultCursor(name)
    if name == "INFO" then return config.Cursor.CURSOR_INFO end
    return config.Cursor.CURSOR_BLANK
end

function SpriteButton.new(parent, spriteName, action, options)
    options = options or {}

    local normalizedName, spriteSet = resolveSprites(spriteName)
    local self = setmetatable({}, SpriteButton)
    self.spriteName = normalizedName
    self.sprites = spriteSet
    self.action = action
    self.toggleable = options.toggleable == true
    self.disabled = options.disabled == true
    self.hovered = false
    self.pressed = false
    self.hasCustomHoverCursor = options.hoverCursor ~= nil
    self.hoverCursor = options.hoverCursor or defaultCursor(normalizedName)

    self.interfaceID = parent.interfaceID
    self.root = Components.new(ui.Sprite, parent)
    self.root:SetPos(
        options.x or 0,
        options.y or 0,
        options.xAnchor or 0,
        options.yAnchor or 0
    )
    self.root:SetSize(options.width or options.size or DEFAULT_SIZE, options.height or options.size or DEFAULT_SIZE)
    self.root.clickthrough = self.disabled and not self.toggleable
    Wheel.bind(self.root, options)

    self.root:Subscribe(ui.Hook.ONMOUSEOVER, function()
        if self.disabled and not self.toggleable then return false end
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
        if self.disabled and not self.toggleable then return false end
        self.pressed = true
        if self.toggleable then self.disabled = not self.disabled end
        self:_UpdateState()
        if self.action then self.action(self, not self.disabled) end
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

function SpriteButton:_UpdateState()
    self.root.enabled = self.toggleable or not self.disabled
    self.root.clickthrough = self.disabled and not self.toggleable
    Cursor.apply(self.root, self.hoverCursor, self.toggleable or not self.disabled)
    if self.disabled then
        if self.toggleable and (self.hovered or self.pressed) and self.sprites.disabledHovered then
            self.root.spriteID = self.sprites.disabledHovered
        else
            self.root.spriteID = self.sprites.disabled or self.sprites.neutral
        end
    elseif self.hovered or self.pressed then
        self.root.spriteID = self.sprites.active
    else
        self.root.spriteID = self.sprites.neutral
    end
end

function SpriteButton:SetDisabled(disabled)
    self.disabled = disabled == true
    self.hovered = false
    self.pressed = false
    self:_UpdateState()
end

function SpriteButton:SetSprite(spriteName)
    self.spriteName, self.sprites = resolveSprites(spriteName)
    if not self.hasCustomHoverCursor then self.hoverCursor = defaultCursor(self.spriteName) end
    self:_UpdateState()
end

function SpriteButton:SetHoverCursor(cursor)
    self.hasCustomHoverCursor = true
    self.hoverCursor = cursor
    Cursor.apply(self.root, self.hoverCursor, self.toggleable or not self.disabled)
end

function SpriteButton:SetTooltip(value)
    return Tooltip.set(self, value)
end

function SpriteButton:Destroy()
    Tooltip.unbind(self)
    if self.root then
        if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.root:Destroy() end
        self.root = nil
    end
end

return SpriteButton
