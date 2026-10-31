local Components = require("src/core/components")
local Sprites = require("src/core/sprites")
local Tooltip = require("src/tooltip")
local Wheel = require("src/core/wheel")

local Spinner = {}
Spinner.__index = Spinner

local DEFAULT_SIZE = 72
local DEFAULT_DEGREES_PER_LOGIC_UPDATE = 6
local nextInstanceID = 0

local function rotation(value)
    return (tonumber(value) or 0) % 360
end

function Spinner.new(parent, options)
    options = options or {}
    nextInstanceID = nextInstanceID + 1

    local self = setmetatable({}, Spinner)
    self.eventID = "prettyui_big_spinner_" .. tostring(nextInstanceID)
    self.degreesPerLogicUpdate = tonumber(options.degreesPerLogicUpdate) or DEFAULT_DEGREES_PER_LOGIC_UPDATE
    self.rotation = rotation(options.rotation)
    self.running = false

    self.interfaceID = parent.interfaceID
    self.root = Components.new(ui.Layer, parent)
    self.root:SetPos(
        options.x or 0,
        options.y or 0,
        options.xAnchor or 0,
        options.yAnchor or 0
    )
    self.root:SetSize(options.width or options.size or DEFAULT_SIZE, options.height or options.size or DEFAULT_SIZE)
    self.root.clickthrough = true
    Wheel.bind(self.root, options)

    self.backdrop = Components.new(ui.Sprite, self.root)
    self.backdrop:SetSize(0, 0, 1.0, 1.0)
    self.backdrop.spriteID = Sprites.BIG_SPINNER_BACKDROP
    self.backdrop.clickthrough = true

    self.rotating = Components.new(ui.Sprite, self.root)
    self.rotating:SetSize(0, 0, 1.0, 1.0)
    self.rotating.spriteID = Sprites.BIG_SPINNER_ROTATING
    self.rotating.rotationDegrees = self.rotation
    self.rotating.clickthrough = true

    Tooltip.bind(self, self.root, parent, options.tooltip)
    if options.autoPlay ~= false then self:Start() end
    return self
end

function Spinner:SetRotation(degrees)
    self.rotation = rotation(degrees)
    if self.rotating then self.rotating.rotationDegrees = self.rotation end
end

function Spinner:SetDegreesPerLogicUpdate(degrees)
    self.degreesPerLogicUpdate = tonumber(degrees) or DEFAULT_DEGREES_PER_LOGIC_UPDATE
end

function Spinner:SetTooltip(value)
    return Tooltip.set(self, value)
end

function Spinner:Start()
    if self.running or self.root == nil then return end
    self.running = true
    Event.Logic.Subscribe(self.eventID, function()
        self:SetRotation(self.rotation + self.degreesPerLogicUpdate)
    end)
end

function Spinner:Stop()
    if not self.running then return end
    Event.Logic.Unsubscribe(self.eventID)
    self.running = false
end

function Spinner:Reset()
    self:SetRotation(0)
end

function Spinner:Destroy()
    self:Stop()
    Tooltip.unbind(self)
    if self.root then
        if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.root:Destroy() end
        self.root = nil
        self.backdrop = nil
        self.rotating = nil
    end
end

return Spinner
