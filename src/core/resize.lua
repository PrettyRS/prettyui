local Cursor = require("src/core/cursor")
local Components = require("src/core/components")
local DragFeedback = require("src/core/drag_feedback")
local InterfaceMouse = require("src/core/mouse")
local clamp = require("src/core/math").clamp
local WorldMap = require("src/core/world_map")

local Resize = {}
Resize.__index = Resize

local EVENT_ID = "prettyui_resize"
local controllers = {}

-- Each corner extends along the adjacent edges up to a maximum distance.
-- This makes it easier to grab corners, and matches native behaviour.
local VERTICAL_CURSOR = "TOPLEVEL_V2_SCALE_VERT"
local HORIZONTAL_CURSOR = "TOPLEVEL_V2_SCALE_HORZ"
local DIAGONAL_CURSOR_1 = "TOPLEVEL_V2_SCALE_DIAG_1"
local DIAGONAL_CURSOR_2 = "TOPLEVEL_V2_SCALE_DIAG_2"
local order = { "n", "s", "e", "w", "nw_v", "nw_h", "ne_v", "ne_h", "sw_v", "sw_h", "se_v", "se_h" }
local edges = {
    n = { north = true, horizontal = true, cursor = VERTICAL_CURSOR },
    s = { south = true, horizontal = true, cursor = VERTICAL_CURSOR },
    e = { east = true, cursor = HORIZONTAL_CURSOR },
    w = { west = true, cursor = HORIZONTAL_CURSOR },
    nw_v = { north = true, west = true, cursor = DIAGONAL_CURSOR_1 },
    nw_h = { north = true, west = true, horizontal = true, cursor = DIAGONAL_CURSOR_1 },
    ne_v = { north = true, east = true, cursor = DIAGONAL_CURSOR_2 },
    ne_h = { north = true, east = true, horizontal = true, cursor = DIAGONAL_CURSOR_2 },
    sw_v = { south = true, west = true, cursor = DIAGONAL_CURSOR_2 },
    sw_h = { south = true, west = true, horizontal = true, cursor = DIAGONAL_CURSOR_2 },
    se_v = { south = true, east = true, cursor = DIAGONAL_CURSOR_1 },
    se_h = { south = true, east = true, horizontal = true, cursor = DIAGONAL_CURSOR_1 },
}
local BORDER = 5
local CORNER = 35

local function loaded(self)
    return self.root ~= nil and ui.Interfaces:GetInterface(self.interfaceID) ~= nil
end

local function available(self)
    return not WorldMap.isSuspended() and loaded(self) and self.enabled and not self.root.hidden and
        self.root.visibleGlobal ~= false and self.isVisible()
end

local function resizeAxis(position, size, delta, leading, trailing, extent, minimum, maximum)
    local limit = math.max(minimum, math.min(maximum, extent))
    if leading then
        -- The opposite edge stays fixed unless the viewport cannot contain it.
        local far = clamp(position + size, minimum, math.max(minimum, extent))
        size = clamp(size - delta, minimum, math.min(limit, far))
        position = far - size
    elseif trailing then
        position = clamp(position, 0, extent - minimum)
        size = clamp(size + delta, minimum, math.max(minimum, math.min(limit, extent - position)))
    else
        size = clamp(size, minimum, limit)
        position = clamp(position, 0, extent - size)
    end
    return position, size
end

-- The rectangle of one handle around a root at x, y of the given size. Corner arms
-- reach this far along each edge from the outer corner; the straight edges fill the rest.
local function borderRectangle(edge, x, y, width, height, reachX, reachY)
    local thickness = BORDER * 2
    local left, top = x - BORDER, y - BORDER
    local right, bottom = x + width + BORDER, y + height + BORDER
    local corner = (edge.north or edge.south) and (edge.west or edge.east)
    if edge.horizontal then
        local start = corner and (edge.west and left + thickness or right - reachX) or left + reachX
        local length = corner and reachX - thickness or width + thickness - reachX * 2
        return start, edge.north and top or bottom - thickness, length, thickness
    end
    local start = corner and (edge.north and top or bottom - reachY) or top + reachY
    local length = corner and reachY or height + thickness - reachY * 2
    return edge.west and left or right - thickness, start, thickness, length
end

local function place(self, key, x, y, width, height, visible, raise)
    local handle = self.handles[key]
    local enabled = visible and width > 0 and height > 0
    if handle.hidden ~= not enabled then Components.setHidden(handle, not enabled) end
    if handle.enabled ~= enabled then
        handle.enabled = enabled
        handle.clickthrough = not enabled
        Cursor.apply(handle, config.Cursor[edges[key].cursor], enabled)
    end
    if self.restoreHandle == handle or handle.x ~= x or handle.y ~= y then
        handle:SetPos(x, y)
    end
    if self.restoreHandle == handle or handle.width ~= width or handle.height ~= height then
        handle:SetSize(width, height)
    end
    if enabled and raise then handle:MoveToFront() end
end

function Resize:_Clear()
    local drag = self.dragState
    if drag then
        InterfaceMouse.EndCapture(drag.component)
        if drag.captureExpanded then self.restoreHandle = drag.component end
    end
    self.dragState = nil
    if self.feedback then
        self.feedback:Destroy()
        self.feedback = nil
    end
end

function Resize:_Refresh(raise)
    if self.applying or self.root == nil then return end
    if not loaded(self) then
        self:Destroy()
        return
    end
    local visible = available(self)
    if not visible then self:_Clear() end
    local root = self.root
    local x, y, width, height = root.x, root.y, root.width, root.height
    local drag = self.dragState
    local expanded = drag and drag.captureExpanded
    local localVisible = visible and not expanded
    -- Ten-unit hit areas straddle the edge, leaving the header and controls
    -- available outside the five-unit inner strip.
    -- limit the size of the corner handles to half the size of the root, so they don't overlap each other
    local reachX = math.min(CORNER, (width + BORDER * 2) // 2)
    local reachY = math.min(CORNER, (height + BORDER * 2) // 2)
    for _, key in ipairs(order) do
        if not expanded or key ~= drag.edge then
            local hx, hy, hw, hh = borderRectangle(edges[key], x, y, width, height, reachX, reachY)
            place(self, key, hx, hy, hw, hh, localVisible, raise)
        end
    end
    self.restoreHandle = nil
    if expanded and raise then drag.component:MoveToFront() end
    if self.feedback then
        self.feedback:Update()
        if raise then self.feedback.active:MoveToFront() end
    end
end

function Resize:Refresh()
    self:_Refresh(true)
end


function Resize:_Begin(key, component, x, y)
    if not available(self) then return true end
    self:Cancel()
    if self.onBegin then self.onBegin() end
    if not available(self) then return false end
    InterfaceMouse.BeginCapture(component)
    local mouse = InterfaceMouse.GetPosition(component, x, y)
    if not mouse then
        InterfaceMouse.EndCapture(component)
        return false
    end
    self.dragState = {
        edge = key,
        component = component,
        mouseX = mouse.x,
        mouseY = mouse.y,
        captureExpanded = false,
    }
    self.feedback = DragFeedback.newFinal(self.parent, self.root)
    self:Refresh()
    return false
end

function Resize:_Move(component, x, y)
    local drag = self.dragState
    if not drag or drag.component ~= component then return false end
    if not available(self) then return self:Cancel() end
    local mouse = InterfaceMouse.GetPosition(component, x, y)
    if not mouse then return false end
    if not drag.captureExpanded then
        drag.captureExpanded = true
        component:SetPos(0, 0)
        component:SetSize(0, 0, 1.0, 1.0)
        component:MoveToFront()
    end
    local dx, dy = mouse.x - drag.mouseX, mouse.y - drag.mouseY
    drag.mouseX, drag.mouseY = mouse.x, mouse.y
    local root, parent, edge = self.root, self.parent, edges[drag.edge]
    local nextX, width = resizeAxis(root.x, root.width, dx, edge.west, edge.east,
        parent.width, self.minWidth, self.maxWidth)
    local nextY, height = resizeAxis(root.y, root.height, dy, edge.north, edge.south,
        parent.height, self.minHeight, self.maxHeight)
    if self.constrainRect then
        local constrainedX, constrainedY, constrainedWidth, constrainedHeight =
            self.constrainRect(nextX, nextY, width, height, edge)
        if constrainedX == nil then
            self:Refresh()
            return false
        end
        nextX, nextY, width, height =
            constrainedX, constrainedY, constrainedWidth, constrainedHeight
    end
    if nextX ~= root.x or nextY ~= root.y or width ~= root.width or height ~= root.height then
        -- Owners may synchronously reflow their content and call Refresh again.
        self.applying = true
        self.setRect(nextX, nextY, width, height)
        self.applying = false
    end
    self:Refresh()
    return false
end

function Resize:Cancel()
    self:_Clear()
    self:Refresh()
    return false
end

function Resize:_Finish()
    local dragging = self.dragState ~= nil
    self:Cancel()
    if dragging and self.onFinish then self.onFinish() end
    return false
end

function Resize:SetEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then return end
    self.enabled = enabled
    if not enabled then self:_Clear() end
    self:Refresh()
end

function Resize:Destroy()
    if self.root == nil then return end
    WorldMap.unwatch(self)
    self:_Clear()
    if loaded(self) then
        for _, key in ipairs(order) do self.handles[key]:Destroy() end
    end
    controllers[self] = nil
    if next(controllers) == nil then Event.Logic.Unsubscribe(EVENT_ID) end
    self.root = nil
    self.parent = nil
    self.handles = nil
    self.restoreHandle = nil
    self.setRect = nil
    self.isVisible = nil
    self.onBegin = nil
    self.constrainRect = nil
    self.onFinish = nil
end

function Resize.new(parent, root, options)
    local self = setmetatable({
        parent = parent,
        root = root,
        interfaceID = parent.interfaceID,
        enabled = true,
        minWidth = options.minWidth or 1,
        minHeight = options.minHeight or 1,
        maxWidth = options.maxWidth or math.huge,
        maxHeight = options.maxHeight or math.huge,
        setRect = options.setRect,
        constrainRect = options.constrainRect,
        isVisible = options.isVisible,
        onBegin = options.onBegin,
        onFinish = options.onFinish,
        handles = {},
    }, Resize)
    local policyOptions = { _categoryPolicy = Components.policyOf(root) }
    for _, key in ipairs(order) do
        local handle = Components.new(ui.Layer, parent, policyOptions)
        self.handles[key] = handle
        handle.enabled = false
        handle.clickthrough = true
        handle:Subscribe(ui.Hook.ONCLICK, function(component, x, y)
            return self:_Begin(key, component, x, y)
        end)
        handle:Subscribe(ui.Hook.ONHOLD, function(component, x, y)
            return self:_Move(component, x, y)
        end)
        handle:Subscribe(ui.Hook.ONRELEASE, function() return self:_Finish() end)
        handle:Subscribe(ui.Hook.ONDRAGCOMPLETE, function() return self:_Finish() end)
    end
    local wasEmpty = next(controllers) == nil
    controllers[self] = true
    if wasEmpty then
        Event.Logic.Subscribe(EVENT_ID, function()
            for controller in pairs(controllers) do controller:_Refresh(false) end
        end)
    end
    self:Refresh()
    WorldMap.watch(self, function(suspended)
        if suspended then self:_Clear() else self:Refresh() end
    end)
    return self
end

return Resize
