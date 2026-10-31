local Components = require("src/core/components")
local Tooltip = require("src/tooltip")
local Wheel = require("src/core/wheel")

local Sprite = {}
Sprite.__index = Sprite

local DEFAULT_SIZE = 24

function Sprite.getSize(options)
    options = options or {}
    return options.width or options.size or DEFAULT_SIZE,
        options.height or options.size or DEFAULT_SIZE
end

function Sprite.new(parent, sprite, options)
    options = options or {}
    local self = setmetatable({}, Sprite)
    local width, height = Sprite.getSize(options)

    self.interfaceID = parent.interfaceID
    self.root = Components.new(ui.Sprite, parent)
    self.root:SetPos(
        options.x or 0,
        options.y or 0,
        options.xAnchor or 0,
        options.yAnchor or 0
    )
    self.root:SetSize(width, height, options.widthAnchor or 0, options.heightAnchor or 0)
    self.root.sprite = sprite
    self.root.rgba = options.colour or options.color or 0xFFFFFFFF
    if options.alpha ~= nil then self.root.alpha = options.alpha end
    self.root.clickthrough = true
    Wheel.bind(self.root, options)
    Tooltip.bind(self, self.root, parent, options.tooltip)
    return self
end

function Sprite:SetSprite(sprite)
    if self.root then self.root.sprite = sprite end
end

function Sprite:SetTooltip(value)
    return Tooltip.set(self, value)
end

function Sprite:Destroy()
    Tooltip.unbind(self)
    if self.root then
        if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.root:Destroy() end
        self.root = nil
    end
end

return Sprite
