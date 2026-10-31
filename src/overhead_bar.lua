local Sprites = require("src/core/sprites")

local OverheadBar = {}
OverheadBar.__index = OverheadBar

local variants = Sprites.OVERHEAD_BARS
OverheadBar.Variants = variants

local byName = {}
for _, variant in ipairs(variants) do byName[variant.name] = variant end
local active = {}
local nextID = 0

local function sprite(parent, spriteID, width, height)
    local component = ui.Sprite.new(parent)
    component.spriteID = spriteID
    component:SetSize(width, height)
    component.clickthrough = true
    return component
end

local function create(entity, targetType, options)
    options = options or {}
    if entity == nil or entity.isValid ~= true then return nil end
    local variant = byName[options.variant or "health.default"]
    assert(variant, "Unknown overhead bar variant: " .. tostring(options.variant))
    local value = options.value == nil and 1 or options.value
    assert(type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge,
        "Overhead bar value must be a finite fraction")
    local parent = options.parent or ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__ROOT)
        or ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
    if parent == nil then return nil end
    local heightAboveGround = options.heightAboveGround
    if heightAboveGround == nil then
        if targetType == "loc" then heightAboveGround = 512 end
        if targetType == "player" then heightAboveGround = 1024 end
    end

    nextID = nextID + 1
    local self = setmetatable({
        entity = entity,
        targetType = targetType,
        parent = parent,
        interfaceID = parent.interfaceID,
        eventID = "prettyui_overhead_bar_" .. nextID,
        variant = variant,
        value = 0,
        heightAboveGround = heightAboveGround,
        offsetX = options.offsetX or 0,
        offsetY = options.offsetY == nil and 8 or options.offsetY,
        visible = options.hidden ~= true,
    }, OverheadBar)
    self.root = ui.Layer.new(parent)
    self.root:SetSize(variant.width, variant.height)
    self.root.clickthrough = true
    self.root.hidden = true
    self.background = sprite(self.root, variant.background, variant.width, variant.height)
    self.fillClip = ui.Layer.new(self.root)
    self.fillClip:SetSize(0, variant.height)
    self.fillClip.clickthrough = true
    self.fill = sprite(self.fillClip, variant.fill, variant.width, variant.height)
    active[self] = true
    self:SetValue(value)
    self:Update()
    if self.root == nil then return nil end
    Event.Logic.Subscribe(self.eventID, function() self:Update() end)
    return self
end

function OverheadBar.forNPC(npc, options)
    return create(npc, "npc", options)
end

function OverheadBar.forPlayer(player, options)
    return create(player, "player", options)
end

function OverheadBar.forLoc(loc, options)
    return create(loc, "loc", options)
end

function OverheadBar:SetValue(value)
    if self.root == nil then return false end
    assert(type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge,
        "Overhead bar value must be a finite fraction")
    self.value = math.max(0, math.min(1, value))
    self.fillClip:SetSize(math.floor(self.variant.width * self.value + 0.5), self.variant.height)
    return true
end

function OverheadBar:SetVariant(name)
    if self.root == nil then return false end
    local variant = byName[name]
    if variant == nil then return false end
    self.variant = variant
    self.root:SetSize(variant.width, variant.height)
    self.background.spriteID = variant.background
    self.background:SetSize(variant.width, variant.height)
    self.fill.spriteID = variant.fill
    self.fill:SetSize(variant.width, variant.height)
    self:SetValue(self.value)
    self:Update()
    return true
end

function OverheadBar:Update()
    if self.root == nil then return false end
    if ui.Interfaces:GetInterface(self.interfaceID) == nil or not self.entity.isValid then
        self:Destroy()
        return false
    end
    if not self.visible then
        self.root.hidden = true
        return false
    end
    if self.targetType == "loc" and (self.entity.isHidden or self.entity.isRoofRemoved) then
        self.root.hidden = true
        return false
    end

    local succeeded, screen = pcall(function()
        local position = self.entity.position
        local heightAboveGround = self.heightAboveGround
        if heightAboveGround == nil then
            local overlayHeight = self.entity.config.overlayHeight
            heightAboveGround = overlayHeight >= 0 and overlayHeight or self.entity.aabb.maxY - position.y
        end
        return ScreenConvert.Vector3ToScreen(position + Vector3.new(0, heightAboveGround, 0))
    end)
    if not self.entity.isValid then
        self:Destroy()
        return false
    end
    if not succeeded or screen == nil or screen.x < 0 or screen.y < 0
        or screen.x > self.parent.width or screen.y > self.parent.height then
        self.root.hidden = true
        return false
    end
    local width, height = self.variant.width, self.variant.height
    local x = math.floor(screen.x - width / 2 + self.offsetX + 0.5)
    local y = math.floor(screen.y - height - self.offsetY + 0.5)
    x = math.max(0, math.min(self.parent.width - width, x))
    y = math.max(0, math.min(self.parent.height - height, y))
    if x ~= self.root.x or y ~= self.root.y then self.root:SetPos(x, y) end
    self.root.hidden = false
    return true
end

function OverheadBar:Show()
    self.visible = true
    return self:Update()
end

function OverheadBar:Hide()
    self.visible = false
    if self.root then self.root.hidden = true end
end

function OverheadBar:Destroy()
    Event.Logic.Unsubscribe(self.eventID)
    active[self] = nil
    if self.root then
        if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.root:Destroy() end
        self.root = nil
    end
    self.fill = nil
    self.fillClip = nil
    self.background = nil
    self.entity = nil
    self.parent = nil
end

function OverheadBar.Shutdown()
    for bar in pairs(active) do bar:Destroy() end
end

return OverheadBar
