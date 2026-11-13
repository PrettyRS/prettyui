local clamp = require("src/core/math").clamp
local WorldMap = require("src/core/world_map")

local DragBounds = {}
DragBounds.__index = DragBounds
local nextID = 0
local NO_EDGE_OFFSETS = { left = 0, top = 0, right = 0, bottom = 0 }

function DragBounds.new(parent, root, onResize, edgeOffsets)
    nextID = nextID + 1
    local self = setmetatable({
        parent = parent,
        root = root,
        edgeOffsets = edgeOffsets or NO_EDGE_OFFSETS,
        interfaceID = parent.interfaceID,
        onResize = onResize,
        hookID = "prettyui_drag_bounds_" .. nextID,
        parentWidth = parent.width,
        parentHeight = parent.height,
        rootWidth = root.width,
        rootHeight = root.height,
    }, DragBounds)
    self:RememberPosition()
    parent:Subscribe(ui.Hook.ONRESIZE, self.hookID, function()
        self:Refresh()
        return true
    end)
    return self
end

function DragBounds:Refresh()
    if WorldMap.isSuspended() or ui.Interfaces:GetInterface(self.interfaceID) == nil then return end
    local root, parent = self.root, self.parent
    local parentWidth, parentHeight = parent.width, parent.height
    local rootWidth, rootHeight = root.width, root.height
    if parentWidth == self.parentWidth and parentHeight == self.parentHeight and
        rootWidth == self.rootWidth and rootHeight == self.rootHeight and
        root.x == self.lastX and root.y == self.lastY then return end

    self.parentWidth, self.parentHeight = parentWidth, parentHeight
    self.rootWidth, self.rootHeight = rootWidth, rootHeight
    local offsets = self.edgeOffsets
    local travelX = math.max(0, parentWidth - rootWidth + offsets.left + offsets.right)
    local travelY = math.max(0, parentHeight - rootHeight + offsets.top + offsets.bottom)
    local x = math.floor(self.relativeX * travelX + 0.5) - offsets.left
    local y = math.floor(self.relativeY * travelY + 0.5) - offsets.top
    local dx, dy = x - self.lastX, y - self.lastY
    self.lastX, self.lastY = x, y
    if x ~= root.x or y ~= root.y then root:SetPos(x, y) end
    -- Retain unrounded placement through resize notifications and layout updates.
    self.onResize(dx, dy)
end

function DragBounds:RememberPosition()
    local root, parent = self.root, self.parent
    local offsets = self.edgeOffsets
    local travelX = parent.width - root.width + offsets.left + offsets.right
    local travelY = parent.height - root.height + offsets.top + offsets.bottom
    self.lastX, self.lastY = root.x, root.y
    -- An undersized viewport cannot represent a relative position; retain it.
    self.relativeX = travelX > 0 and clamp((root.x + offsets.left) / travelX, 0, 1) or self.relativeX or 0
    self.relativeY = travelY > 0 and clamp((root.y + offsets.top) / travelY, 0, 1) or self.relativeY or 0
end

function DragBounds:Clamp()
    if WorldMap.isSuspended() or ui.Interfaces:GetInterface(self.interfaceID) == nil then return end
    local root, parent = self.root, self.parent
    local offsets = self.edgeOffsets
    local x = clamp(root.x, -offsets.left, parent.width - root.width + offsets.right)
    local y = clamp(root.y, -offsets.top, parent.height - root.height + offsets.bottom)
    local dx, dy = x - self.lastX, y - self.lastY
    if x ~= root.x or y ~= root.y then root:SetPos(x, y) end
    -- Keep unrounded relative placement when an already-contained surface opens.
    if dx ~= 0 or dy ~= 0 then self:RememberPosition() end
    self.onResize(dx, dy)
end

function DragBounds:Destroy()
    if self.parent and ui.Interfaces:GetInterface(self.interfaceID) ~= nil then
        self.parent:Unsubscribe(ui.Hook.ONRESIZE, self.hookID)
    end
    self.parent = nil
    self.root = nil
    self.onResize = nil
end

return DragBounds
