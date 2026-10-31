local Sprites = require("src/core/sprites")
local Tooltip = require("src/tooltip")
local Wheel = require("src/core/wheel")
local clamp = require("src/core/math").clamp
local Components = require("src/core/components")

local ItemSlot = {}
ItemSlot.__index = ItemSlot

local SLOT_SIZE = 40
local DEFAULT_ITEM_INSET = 4
local DISABLED_OVERLAY_RGBA = 0x000000FF
local DISABLED_OVERLAY_ALPHA = 0.55
local DISABLED_ITEM_ALPHA = 0.75

local function objectID(object)
    if object == nil then return nil end
    if type(object.id) ~= "number" then error("ItemSlot object must be an Obj config") end
    local id = math.tointeger(object.id)
    if id == nil then error("ItemSlot object ID must be an integer") end
    return id
end

local function stackQuantity(quantity)
    if quantity == nil then return nil end
    local value = math.tointeger(quantity)
    if value == nil or value < 0 then error("ItemSlot quantity must be a non-negative integer") end
    return value
end

function ItemSlot:_UpdateQuantity()
    if self.item == nil then return end
    if self.object ~= nil and self.quantity ~= nil then
        self.item.associatedObjectQuantity = self.quantity
        self.item.associatedObjectQuantityMode = self.quantityMode
    else
        self.item.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
    end
end
function ItemSlot:_UpdateDisabled()
    if self.disabledOverlay == nil then return end
    local visible = self.disabled and self.item ~= nil
    if self.item ~= nil then
        self.item.alpha = self.disabled and DISABLED_ITEM_ALPHA or 1
    end
    self.disabledOverlay.hidden = not visible
    if visible then self.disabledOverlay:MoveToFront() end
end


function ItemSlot:_CreateItemSprite()
    if self.item then self.item:Destroy() end
    self.item = nil
    local id = objectID(self.object)
    if id == nil then
        self:_UpdateDisabled()
        return
    end

    self.item = Components.new(ui.Sprite, self.root)
    self.item:SetPos(self.itemInset, self.itemInset)
    self.item:SetSize(SLOT_SIZE - self.itemInset * 2, SLOT_SIZE - self.itemInset * 2)
    self.item.clickthrough = true
    if self.outlineWidth ~= nil then self.item.outlineWidth = self.outlineWidth end
    if self.shadowRGBA ~= nil then self.item.shadowRGBA = self.shadowRGBA end
    self.item:SetAssociatedObject(id)
    self:_UpdateQuantity()
    self.item.alpha = 1
    self:_UpdateDisabled()
end

function ItemSlot:_CreateDragItemSprite()
    self.dragItem = Components.new(ui.Sprite, self.root)
    self.dragItem:SetPos(self.itemInset, self.itemInset)
    self.dragItem:SetSize(SLOT_SIZE - self.itemInset * 2, SLOT_SIZE - self.itemInset * 2)
    self.dragItem.clickthrough = true
    self.dragItem.hidden = true
    self.dragItem.alpha = 0.5
    if self.outlineWidth ~= nil then self.dragItem.outlineWidth = self.outlineWidth end
    if self.shadowRGBA ~= nil then self.dragItem.shadowRGBA = self.shadowRGBA end
end

function ItemSlot:_ShowDragItem()
    local id = objectID(self.object)
    if id == nil or self.dragItem == nil then return false end
    self.dragItem.alpha = 0.5
    self.dragItem:SetAssociatedObject(id)
    if self.quantity ~= nil then
        self.dragItem.associatedObjectQuantity = self.quantity
        self.dragItem.associatedObjectQuantityMode = self.quantityMode
    else
        self.dragItem.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
    end
    self.dragItem.hidden = false
    self.dragItem:MoveToFront()
    return true
end

function ItemSlot:_HideDragItem()
    if self.dragItem and ui.Interfaces:GetInterface(self.interfaceID) ~= nil then
        self.dragItem.hidden = true
    end
end

function ItemSlot:_UpdateTooltip()
    if self.tooltip then
        self.tooltip:Destroy()
        self.tooltip = nil
    end
    if self.object ~= nil and self.tooltipValue ~= nil then
        self.tooltip = Tooltip.attach(self.root, self.parent, self.tooltipValue)
    end
end

function ItemSlot.new(parent, object, options)
    options = options or {}

    local self = setmetatable({}, ItemSlot)
    self.parent = parent
    self.object = object
    self.disabled = options.disabled == true
    self.tooltipValue = options.tooltip
    self.quantity = stackQuantity(options.quantity)
    self.quantityMode = options.quantityMode or ui.ObjectQuantityDisplayMode.MULTIPLE
    self.itemInset = clamp(math.floor(options.itemInset or DEFAULT_ITEM_INSET), 0, 19)
    self.outlineWidth = options.outlineWidth
    self.shadowRGBA = options.shadowRGBA
    self.backgroundSpriteID = options.backgroundSpriteID or Sprites.ITEM_SLOT_BACKGROUND
    self.onObjectChange = options.onObjectChange

    self.interfaceID = parent.interfaceID
    self.root = Components.new(ui.Layer, parent)
    self.root:SetPos(
        options.x or 0,
        options.y or 0,
        options.xAnchor or 0,
        options.yAnchor or 0
    )
    self.root:SetSize(SLOT_SIZE, SLOT_SIZE)
    self.root.clickthrough = options.clickthrough ~= false
    Wheel.bind(self.root, options)

    self.background = Components.new(ui.Sprite, self.root)
    self.background:SetSize(SLOT_SIZE, SLOT_SIZE)
    self.background.spriteID = self.backgroundSpriteID
    self.background.clickthrough = true

    self:_CreateItemSprite()
    self:_CreateDragItemSprite()

    self.disabledOverlay = Components.new(ui.Rectangle, self.root)
    self.disabledOverlay:SetPos(self.itemInset, self.itemInset)
    self.disabledOverlay:SetSize(SLOT_SIZE - self.itemInset * 2, SLOT_SIZE - self.itemInset * 2)
    self.disabledOverlay.fill = true
    self.disabledOverlay.rgba = DISABLED_OVERLAY_RGBA
    self.disabledOverlay.alpha = DISABLED_OVERLAY_ALPHA
    self.disabledOverlay.clickthrough = true
    self:_UpdateDisabled()

    self:_UpdateTooltip()
    return self
end

function ItemSlot:SetObject(object, quantity)
    self.object = object
    self.quantity = stackQuantity(quantity)
    self:_CreateItemSprite()
    self:_UpdateTooltip()
    if self.onObjectChange then self.onObjectChange(self, object) end
end

function ItemSlot:SetQuantity(quantity)
    self.quantity = stackQuantity(quantity)
    self:_UpdateQuantity()
end

function ItemSlot:SetDisabled(disabled)
    self.disabled = disabled == true
    self:_UpdateDisabled()
end

function ItemSlot:SetTooltip(value)
    if self.root == nil then return false end
    self.tooltipValue = value
    self:_UpdateTooltip()
    return true
end

function ItemSlot:Destroy()
    if self.tooltip then
        self.tooltip:Destroy()
        self.tooltip = nil
    end
    if self.root then
        if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.root:Destroy() end
        self.root = nil
        self.background = nil
        self.item = nil
        self.dragItem = nil
        self.disabledOverlay = nil
        self.parent = nil
        self.onObjectChange = nil
    end
end

return ItemSlot
