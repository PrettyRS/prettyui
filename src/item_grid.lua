local ItemSlot = require("src/item_slot")
local InterfaceMouse = require("src/core/mouse")
local Sprites = require("src/core/sprites")
local Tooltip = require("src/tooltip")
local Wheel = require("src/core/wheel")
local Components = require("src/core/components")

local ItemGrid = {}
ItemGrid.__index = ItemGrid

local SLOT_SIZE = 40
local DEFAULT_SLOT_GAP = 2
local PARKED_ITEM_POSITION = -100000
local DRAG_HOOK_ID = "prettyui_item_grid_drag"
local nextInstanceID = 0

local function dimensions(options)
    options = options or {}
    local columns = math.max(1, math.floor(options.columns or 1))
    local rows = math.max(1, math.floor(options.rows or 1))
    return columns, rows
end

local function slotGap(options)
    options = options or {}
    return math.max(0, math.floor(options.slotGap or DEFAULT_SLOT_GAP))
end

local function normalizeEntry(entry)
    if type(entry) == "table" and
        (rawget(entry, "object") ~= nil or rawget(entry, "tooltip") ~= nil or
            rawget(entry, "quantity") ~= nil) then
        return entry.object, entry.tooltip, entry.quantity
    end
    return entry, nil, nil
end

function ItemGrid.getSize(options)
    local columns, rows = dimensions(options)
    local gap = slotGap(options)
    return columns * SLOT_SIZE + (columns - 1) * gap,
        rows * SLOT_SIZE + (rows - 1) * gap
end

function ItemGrid:_ResolveTooltip(object, explicit, index)
    if object == nil then return nil end
    if explicit ~= nil then return explicit end
    if type(self.tooltipOption) == "function" then
        local row = math.floor((index - 1) / self.columns) + 1
        local column = (index - 1) % self.columns + 1
        return self.tooltipOption(object, index, row, column)
    end
    if self.tooltipOption == true then return object.name end
    return self.tooltipOption
end

function ItemGrid:_RefreshSlotInteraction(index)
    local slot = self.slots[index]
    if slot == nil or slot.root == nil then return end
    slot.root.clickthrough = not self.dragDrop and slot.tooltip == nil
end

function ItemGrid:_ClearDropHover()
    if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then
        for _, slot in ipairs(self.slots) do
            if slot.background then
                slot.background.spriteID = Sprites.ITEM_GRID_BACKGROUND
            end
        end
    end
    self.dropHoverIndex = nil
end

function ItemGrid:_SetDropHover(index)
    if index == self.dragSourceIndex then index = nil end
    if self.dropHoverIndex == index then return end
    if self.dropHoverIndex then
        local previous = self.slots[self.dropHoverIndex]
        if previous and previous.background then
            previous.background.spriteID = Sprites.ITEM_GRID_BACKGROUND
        end
    end
    self.dropHoverIndex = index
    if index then
        local slot = self.slots[index]
        slot.background.spriteID = Sprites.ITEM_GRID_DROP_TARGET
        if slot.tooltip then slot.tooltip:Hide() end
    end
end

function ItemGrid:_GridPosition()
    if self.parentTooltipContext and self.parentTooltipContext.active then
        return self.parentTooltipContext.position(self.root)
    end
    return self.root.x or 0, self.root.y or 0
end

function ItemGrid:_SlotAtMouse(mouse)
    if mouse == nil then return nil end
    local gridX, gridY = self:_GridPosition()
    local x = mouse.x - gridX
    local y = mouse.y - gridY
    if x < 0 or y < 0 then return nil end
    local pitch = SLOT_SIZE + self.slotGap
    local column = math.floor(x / pitch)
    local row = math.floor(y / pitch)
    if column >= self.columns or row >= self.rows then return nil end
    if x - column * pitch >= SLOT_SIZE or y - row * pitch >= SLOT_SIZE then return nil end
    return row * self.columns + column + 1
end

function ItemGrid:_UpdateDrag()
    if self.dragSourceIndex == nil then return false end
    local mouse = InterfaceMouse.GetPosition()
    if mouse and self.dragSprite then
        self.dragSprite:SetPos(
            math.floor(mouse.x - (self.dragSprite.width or 0) / 2),
            math.floor(mouse.y - (self.dragSprite.height or 0) / 2)
        )
        self.dragSprite:MoveToFront()
    end
    self:_SetDropHover(self:_SlotAtMouse(mouse))
    return false
end

function ItemGrid:_FinishDrag(commit)
    local sourceIndex = self.dragSourceIndex
    local destinationIndex = commit and self.dropHoverIndex or nil
    local sourceSlot = sourceIndex and self.slots[sourceIndex] or nil
    if sourceSlot then
        if sourceSlot.item and ui.Interfaces:GetInterface(sourceSlot.interfaceID) ~= nil then
            sourceSlot.item:SetPos(sourceSlot.itemInset, sourceSlot.itemInset)
            sourceSlot.item.alpha = 1
        end
        sourceSlot:_HideDragItem()
    end

    self.dragSourceIndex = nil
    self.dragCaptureWasPressed = false
    self:_ClearDropHover()

    if sourceIndex and destinationIndex and sourceIndex ~= destinationIndex then
        self:MoveObject(sourceIndex, destinationIndex)
        local movedSource = self.slots[sourceIndex]
        local movedDestination = self.slots[destinationIndex]
        if movedSource and movedSource.item then movedSource.item.alpha = 1 end
        if movedDestination and movedDestination.item then movedDestination.item.alpha = 1 end
    end
    local overlayLoaded = ui.Interfaces:GetInterface(self.overlayInterfaceID) ~= nil
    if self.dragSprite and overlayLoaded then
        self.dragSprite.hidden = true
        self.dragSprite.alpha = 1
    end
    if self.dragCapture then
        if overlayLoaded then self.dragCapture:Destroy() end
        self.dragCapture = nil
    end
    return false
end

function ItemGrid:_PollDrag()
    if self.dragSourceIndex == nil then return end
    self:_UpdateDrag()
    if self.dragCapture and self.dragCapture.isClicked then
        self.dragCaptureWasPressed = true
    elseif self.dragCaptureWasPressed then
        self:_FinishDrag(true)
    end
end

function ItemGrid:_CreateDragCapture()
    if self.dragSourceIndex == nil or self.dragCapture then return false end

    self.dragCapture = Components.new(ui.Button, self.overlayParent)
    self.dragCapture:SetSize(0, 0, 1.0, 1.0)
    self.dragCapture.clickthrough = false
    self.dragCapture.alpha = 0
    self.dragCapture.text.content = ""
    self.dragCapture:MoveToFront()
    self.dragCapture:Subscribe(ui.Hook.ONHOLD, function() return self:_UpdateDrag() end)
    self.dragCapture:Subscribe(ui.Hook.ONDRAG, function() return self:_UpdateDrag() end)
    self.dragCapture:Subscribe(ui.Hook.ONRELEASE, function() return self:_FinishDrag(true) end)
    self.dragCapture:Subscribe(ui.Hook.ONDRAGCOMPLETE, function() return self:_FinishDrag(true) end)
    if self.dragSprite then self.dragSprite:MoveToFront() end
    return false
end

function ItemGrid:_BeginDrag(index)
    local slot = self.slots[index]
    local entry = self.entries[index]
    if not self.dragDrop or self.dragSourceIndex ~= nil or slot == nil or entry.object == nil then
        return false
    end

    self.dragSourceIndex = index
    self.dragCaptureWasPressed = false
    if not slot:_ShowDragItem() then
        self.dragSourceIndex = nil
        return false
    end
    slot.item:SetPos(PARKED_ITEM_POSITION, PARKED_ITEM_POSITION)
    if slot.tooltip then slot.tooltip:Hide() end

    if self.dragSprite == nil then
        self.dragSprite = Components.new(ui.Sprite, self.overlayParent)
        self.dragSprite.clickthrough = true
    end
    local width = slot.item.width or (SLOT_SIZE - slot.itemInset * 2)
    local height = slot.item.height or (SLOT_SIZE - slot.itemInset * 2)
    self.dragSprite:SetSize(width, height)
    self.dragSprite.hidden = false
    self.dragSprite.alpha = 1
    self.dragSprite:SetAssociatedObject(math.tointeger(entry.object.id))
    self.dragSprite.associatedObjectQuantityMode = slot.item.associatedObjectQuantityMode
    if entry.quantity ~= nil then self.dragSprite.associatedObjectQuantity = entry.quantity end
    if slot.outlineWidth ~= nil then self.dragSprite.outlineWidth = slot.outlineWidth end
    if slot.shadowRGBA ~= nil then self.dragSprite.shadowRGBA = slot.shadowRGBA end
    self.dragSprite:MoveToFront()

    self:_CreateDragCapture()
    return self:_UpdateDrag()
end

function ItemGrid:_BindSlotDrag(index)
    local root = self.slots[index].root
    root:Subscribe(ui.Hook.ONCLICK, DRAG_HOOK_ID, function()
        return self:_BeginDrag(index)
    end)
    root:Subscribe(ui.Hook.ONHOLD, DRAG_HOOK_ID, function()
        if self.dragSourceIndex ~= index then return true end
        return self:_UpdateDrag()
    end)
    root:Subscribe(ui.Hook.ONDRAG, DRAG_HOOK_ID, function()
        if self.dragSourceIndex ~= index then return true end
        return self:_UpdateDrag()
    end)
    root:Subscribe(ui.Hook.ONMOUSELEAVE, DRAG_HOOK_ID, function()
        if self.dragSourceIndex ~= index then return true end
        return self:_UpdateDrag()
    end)
end

function ItemGrid:_ApplyEntry(index)
    local entry = self.entries[index]
    local slot = self.slots[index]
    slot.tooltipValue = self:_ResolveTooltip(entry.object, entry.tooltip, index)
    slot:SetObject(entry.object, entry.quantity)
    if slot.item then slot.item.alpha = 1 end
    slot.background.spriteID = Sprites.ITEM_GRID_BACKGROUND
end

function ItemGrid.new(parent, objects, options)
    options = options or {}
    local columns, rows = dimensions(options)
    local gap = slotGap(options)

    local self = setmetatable({}, ItemGrid)
    nextInstanceID = nextInstanceID + 1
    self.dragEventID = "prettyui_item_grid_drag_" .. tostring(nextInstanceID)
    self.columns = columns
    self.rows = rows
    self.capacity = columns * rows
    self.slotGap = gap
    self.tooltipOption = options.tooltip
    self.dragDrop = options.dragDrop == true
    self.onDrop = options.onDrop
    self.slots = {}
    self.entries = {}

    self.interfaceID = parent.interfaceID
    self.root = Components.new(ui.Layer, parent)
    self.root:SetPos(
        options.x or 0,
        options.y or 0,
        options.xAnchor or 0,
        options.yAnchor or 0
    )
    self.root:SetSize(
        columns * SLOT_SIZE + (columns - 1) * gap,
        rows * SLOT_SIZE + (rows - 1) * gap
    )
    self.root.clickthrough = true
    Wheel.bind(self.root, options)

    local parentContext = Tooltip.getContext(parent)
    local tooltipParent = parentContext and parentContext.parent or parent
    self.parentTooltipContext = parentContext
    self.overlayParent = tooltipParent
    self.overlayInterfaceID = tooltipParent.interfaceID
    self.tooltipContext = Tooltip.registerContext(self.root, tooltipParent, function(target)
        local rootX = self.root.x or 0
        local rootY = self.root.y or 0
        if parentContext then rootX, rootY = parentContext.position(self.root) end
        return rootX + (target.x or 0), rootY + (target.y or 0)
    end, parentContext)

    objects = objects or {}
    for index = 1, self.capacity do
        local object, tooltip, quantity = normalizeEntry(objects[index])
        self.entries[index] = { object = object, tooltip = tooltip, quantity = quantity }
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        local slotIndex = index
        self.slots[index] = ItemSlot.new(self.root, object, {
            x = column * (SLOT_SIZE + gap),
            y = row * (SLOT_SIZE + gap),
            backgroundSpriteID = Sprites.ITEM_GRID_BACKGROUND,
            itemInset = options.itemInset,
            outlineWidth = options.outlineWidth,
            shadowRGBA = options.shadowRGBA,
            quantity = quantity,
            quantityMode = options.quantityMode,
            tooltip = self:_ResolveTooltip(object, tooltip, index),
            clickthrough = not self.dragDrop,
            onObjectChange = function(changedSlot)
                local entry = self.entries[slotIndex]
                if entry then
                    entry.object = changedSlot.object
                    entry.quantity = changedSlot.quantity
                end
                self:_RefreshSlotInteraction(slotIndex)
            end,
            _onScrollWheel = options._onScrollWheel,
        })
        self:_BindSlotDrag(index)
    end
    self:SetDragDropEnabled(self.dragDrop)
    Event.Logic.Subscribe(self.dragEventID, function() self:_PollDrag() end)
    return self
end

function ItemGrid:GetSlot(index)
    return self.slots[index]
end

function ItemGrid:SetObject(index, object, tooltip, quantity)
    if self.slots[index] == nil then return false end
    self.entries[index] = { object = object, tooltip = tooltip, quantity = quantity }
    self:_ApplyEntry(index)
    return true
end

function ItemGrid:SetObjectAt(column, row, object, tooltip, quantity)
    if column < 1 or column > self.columns or row < 1 or row > self.rows then return false end
    return self:SetObject((row - 1) * self.columns + column, object, tooltip, quantity)
end

function ItemGrid:SetTooltip(value)
    if self.root == nil then return false end
    self.tooltipOption = value
    for index = 1, self.capacity do self:_ApplyEntry(index) end
    return true
end

function ItemGrid:MoveObject(sourceIndex, destinationIndex, notify)
    local source = self.entries[sourceIndex]
    local destination = self.entries[destinationIndex]
    if source == nil or destination == nil or source.object == nil or sourceIndex == destinationIndex then
        return false
    end
    self.entries[sourceIndex], self.entries[destinationIndex] = destination, source
    -- Build the destination before releasing the source's native object
    -- renderer, so an empty destination cannot recycle its dimmed component.
    self:_ApplyEntry(destinationIndex)
    self:_ApplyEntry(sourceIndex)
    if notify ~= false and self.onDrop then
        self.onDrop(self, sourceIndex, destinationIndex, source.object, destination.object)
    end
    return true
end

function ItemGrid:SetDragDropEnabled(enabled)
    if not enabled and self.dragSourceIndex then self:_FinishDrag(false) end
    self.dragDrop = enabled == true
    self:_ClearDropHover()
    for index = 1, #self.slots do self:_RefreshSlotInteraction(index) end
end

function ItemGrid:SetObjects(objects)
    objects = objects or {}
    for index = 1, self.capacity do
        local object, tooltip, quantity = normalizeEntry(objects[index])
        self:SetObject(index, object, tooltip, quantity)
    end
end

function ItemGrid:Destroy()
    if self.dragSourceIndex then self:_FinishDrag(false) end
    Event.Logic.Unsubscribe(self.dragEventID)
    self:_ClearDropHover()
    if self.root then
        Tooltip.unregisterContext(self.root)
        self.tooltipContext = nil
    end
    for index = #self.slots, 1, -1 do self.slots[index]:Destroy() end
    self.slots = {}
    self.entries = {}
    self.parentTooltipContext = nil
    if self.dragSprite then
        if ui.Interfaces:GetInterface(self.overlayInterfaceID) ~= nil then self.dragSprite:Destroy() end
        self.dragSprite = nil
    end
    self.overlayParent = nil
    if self.root then
        if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.root:Destroy() end
        self.root = nil
    end
end

return ItemGrid
