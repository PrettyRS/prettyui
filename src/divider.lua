local Sprites = require("src/core/sprites")
local Tooltip = require("src/tooltip")
local Wheel = require("src/core/wheel")
local Components = require("src/core/components")

local Divider = {}
Divider.__index = Divider

local HEIGHT = 60

function Divider.flowOptions(options)
    local copied = {}
    if type(options) == "table" then
        for key, value in pairs(options) do copied[key] = value end
    end
    if copied.rowBackground == nil then copied.rowBackground = false end
    if copied.x == nil and copied.width == nil and copied.widthAnchor == nil then
        copied.x = 0
        copied.width = 0
        copied.widthAnchor = 1.0
    end
    return copied
end

function Divider.new(parent, options)
    options = options or {}

    local self = setmetatable({}, Divider)
    local width = options.width or 0
    local widthAnchor = options.widthAnchor
    if widthAnchor == nil then widthAnchor = width <= 0 and 1.0 or 0 end

    self.interfaceID = parent.interfaceID
    self.root = Components.new(ui.Sprite, parent)
    self.root:SetPos(
        options.x or 0,
        options.y or 0,
        options.xAnchor or 0,
        options.yAnchor or 0
    )
    self.root:SetSize(width, HEIGHT, widthAnchor, 0)
    self.root.spriteID = Sprites.DIVIDER
    self.root.isTiling = true
    self.root.clickthrough = true
    Wheel.bind(self.root, options)

    Tooltip.bind(self, self.root, parent, options.tooltip)
    return self
end

function Divider:SetTooltip(value)
    return Tooltip.set(self, value)
end

function Divider:Destroy()
    Tooltip.unbind(self)
    if self.root then
        if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.root:Destroy() end
        self.root = nil
    end
end

return Divider
