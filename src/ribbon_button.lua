local Components = require("src/core/components")
local Sprites = require("src/core/sprites")
local Tooltip = require("src/tooltip")
local Wheel = require("src/core/wheel")

local RibbonButton = {}
RibbonButton.__index = RibbonButton

local BUTTON_SIZE = 32
local ICON_SIZE = 20
local ICON_OFFSET = math.floor((BUTTON_SIZE - ICON_SIZE) / 2)

function RibbonButton.new(parent, spriteID, action, options)
    options = options or {}

    local self = setmetatable({}, RibbonButton)
    self.action = action
    self.disabled = action == nil or options.disabled == true
    self.hovered = false
    self.active = false

    self.interfaceID = parent.interfaceID
    self.root = Components.new(ui.Layer, parent)
    self.root:SetPos(
        options.x or 0,
        options.y or 0,
        options.xAnchor or 0,
        options.yAnchor or 0
    )
    self.root:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    self.root.enabled = not self.disabled
    self.root.clickthrough = self.disabled
    Wheel.bind(self.root, options)

    self.background = Components.new(ui.Sprite, self.root)
    self.background:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    self.background.clickthrough = true

    self.icon = Components.new(ui.Sprite, self.root)
    self.icon:SetPos(ICON_OFFSET, ICON_OFFSET)
    self.icon:SetSize(ICON_SIZE, ICON_SIZE)
    self.icon.spriteID = spriteID
    self.icon.clickthrough = true

    if not self.disabled then
        local openCursor = config.Cursor.CURSOR_OPEN
        self.root.cursorConfig.mouseOverCursor = openCursor.id
        self.root.opConfig:SetOpCursor(0, openCursor.id)

        self.root:Subscribe(ui.Hook.ONMOUSEOVER, function()
            self.hovered = true
            self:_UpdateState()
            return true
        end)
        self.root:Subscribe(ui.Hook.ONMOUSELEAVE, function()
            self.hovered = false
            self:_UpdateState()
            return true
        end)
        self.root:Subscribe(ui.Hook.ONCLICK, function()
            self.active = not self.active
            self:_UpdateState()
            self.action(self)
            return false
        end)
    end

    self:_UpdateState()
    Tooltip.bind(self, self.root, parent, options.tooltip)
    return self
end

function RibbonButton:_UpdateState()
    if self.background == nil or ui.Interfaces:GetInterface(self.interfaceID) == nil then return end
    if self.disabled then
        self.background.spriteID = Sprites.RIBBON_BUTTON_DISABLED
    elseif self.active then
        self.background.spriteID = Sprites.RIBBON_BUTTON_ACTIVE
    elseif self.hovered then
        self.background.spriteID = Sprites.RIBBON_BUTTON_HOVERED
    else
        self.background.spriteID = Sprites.RIBBON_BUTTON_NEUTRAL
    end
end

function RibbonButton:SetIcon(spriteID)
    if self.icon and ui.Interfaces:GetInterface(self.interfaceID) ~= nil then
        self.icon.spriteID = spriteID
    end
end

function RibbonButton:SetActive(active)
    self.active = active == true
    self:_UpdateState()
end

function RibbonButton:SetTooltip(value)
    return Tooltip.set(self, value)
end

function RibbonButton:Destroy()
    Tooltip.unbind(self)
    if self.root then
        if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.root:Destroy() end
        self.root = nil
        self.background = nil
        self.icon = nil
    end
end

return RibbonButton
