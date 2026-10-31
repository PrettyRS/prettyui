local Components = require("src/core/components")
local Sprites = require("src/core/sprites")

local DragFeedback = {}
DragFeedback.__index = DragFeedback

local function sprite(parent, spriteID, tiled, flipped)
    local component = Components.new(ui.Sprite, parent)
    component.spriteID = spriteID
    component.clickthrough = true
    component.isTiling = tiled == true
    component.isFlippedHorizontally = flipped == true
    return component
end

local function layout(frame, parts, width, height, size)
    local border = math.min(size, math.floor(width / 2), math.floor(height / 2))
    frame:SetSize(width, height)
    parts.topLeft:SetPos(0, 0)
    parts.topLeft:SetSize(border, border)
    parts.topRight:SetPos(width - border, 0)
    parts.topRight:SetSize(border, border)
    parts.bottomLeft:SetPos(0, height - border)
    parts.bottomLeft:SetSize(border, border)
    parts.bottomRight:SetPos(width - border, height - border)
    parts.bottomRight:SetSize(border, border)
    parts.top:SetPos(border, 0)
    parts.top:SetSize(width - border * 2, border)
    parts.bottom:SetPos(border, height - border)
    parts.bottom:SetSize(width - border * 2, border)
    parts.left:SetPos(0, border)
    parts.left:SetSize(border, height - border * 2)
    parts.right:SetPos(width - border, border)
    parts.right:SetSize(border, height - border * 2)
end

local function createFrame(parent, root, sprites, size)
    local frame = Components.new(ui.Layer, parent)
    frame.clickthrough = true
    frame:SetPos(root.x, root.y)
    local parts = {
        topLeft = sprite(frame, sprites.topLeft),
        topRight = sprite(frame, sprites.topLeft, false, true),
        bottomLeft = sprite(frame, sprites.bottomLeft),
        bottomRight = sprite(frame, sprites.bottomLeft, false, true),
        top = sprite(frame, sprites.top, true),
        bottom = sprite(frame, sprites.bottom, true),
        left = sprite(frame, sprites.left, true),
        right = sprite(frame, sprites.left, true, true),
    }
    layout(frame, parts, root.width, root.height, size)
    frame:MoveToFront()
    return frame, parts
end

function DragFeedback.new(parent, root)
    local self = setmetatable({ root = root, interfaceID = parent.interfaceID }, DragFeedback)
    -- Siblings share the dragged surface's coordinates but not its movement.
    self.origin = createFrame(parent, root, Sprites.FEEDBACK_POSITION_FRAME, 10)
    self.active, self.activeParts = createFrame(parent, root, Sprites.FEEDBACK_FINAL_FRAME, 8)
    return self
end

function DragFeedback.newFinal(parent, root)
    local self = setmetatable({ root = root, interfaceID = parent.interfaceID }, DragFeedback)
    self.active, self.activeParts = createFrame(parent, root, Sprites.FEEDBACK_FINAL_FRAME, 8)
    return self
end

function DragFeedback:Update()
    local root, active = self.root, self.active
    if active.x ~= root.x or active.y ~= root.y then
        active:SetPos(root.x, root.y)
    end
    if active.width ~= root.width or active.height ~= root.height then
        layout(active, self.activeParts, root.width, root.height, 8)
    end
end

function DragFeedback:Destroy()
    if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then
        if self.origin then self.origin:Destroy() end
        if self.active then self.active:Destroy() end
    end
    self.origin = nil
    self.active = nil
    self.activeParts = nil
    self.root = nil
end

return DragFeedback
