local Components = require("src/core/components")
local DragFeedback = require("src/core/drag_feedback")
local InterfaceMouse = require("src/core/mouse")
local clamp = require("src/core/math").clamp

local Resize = {}
Resize.__index = Resize

local EVENT_ID = "prettyui_resize"
local controllers = {}
local order = { "n", "s", "e", "w", "nw", "ne", "sw", "se" }
local edges = {
    n = { north = true },
    s = { south = true },
    e = { east = true },
    w = { west = true },
    nw = { north = true, west = true },
    ne = { north = true, east = true },
    sw = { south = true, west = true },
    se = { south = true, east = true },
}
local BORDER = 5

local function loaded(self)
    return self.root ~= nil and ui.Interfaces:GetInterface(self.interfaceID) ~= nil
end

local function available(self)
    return loaded(self) and self.enabled and not self.root.hidden and
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

local function place(self, key, x, y, width, height, visible, raise)
    local handle = self.handles[key]
    local enabled = visible and width > 0 and height > 0
    if handle.hidden ~= not enabled then handle.hidden = not enabled end
    if handle.enabled ~= enabled then
        handle.enabled = enabled
        handle.clickthrough = not enabled
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
    local b = BORDER
    local horizontal = math.max(0, width - b * 2)
    local vertical = math.max(0, height - b * 2)

    -- Ten-unit hit areas straddle the edge, leaving the header and controls
    -- available outside the five-unit inner strip.
    for _, key in ipairs(order) do
        if not expanded or key ~= drag.edge then
            local edge = edges[key]
            local hx = edge.west and x - b or edge.east and x + width - b or x + b
            local hy = edge.north and y - b or edge.south and y + height - b or y + b
            local hw = (edge.west or edge.east) and b * 2 or horizontal
            local hh = (edge.north or edge.south) and b * 2 or vertical
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

function Resize:SetEnabled(enabled)
    enabled = enabled == true
    if self.enabled == enabled then return end
    self.enabled = enabled
    if not enabled then self:_Clear() end
    self:Refresh()
end

function Resize:Destroy()
    if self.root == nil then return end
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
        isVisible = options.isVisible,
        onBegin = options.onBegin,
        handles = {},
    }, Resize)
    for _, key in ipairs(order) do
        local handle = Components.new(ui.Layer, parent)
        self.handles[key] = handle
        handle.enabled = false
        handle.clickthrough = true
        handle:Subscribe(ui.Hook.ONCLICK, function(component, x, y)
            return self:_Begin(key, component, x, y)
        end)
        handle:Subscribe(ui.Hook.ONHOLD, function(component, x, y)
            return self:_Move(component, x, y)
        end)
        handle:Subscribe(ui.Hook.ONRELEASE, function() return self:Cancel() end)
        handle:Subscribe(ui.Hook.ONDRAGCOMPLETE, function() return self:Cancel() end)
    end
    local wasEmpty = next(controllers) == nil
    controllers[self] = true
    if wasEmpty then
        Event.Logic.Subscribe(EVENT_ID, function()
            for controller in pairs(controllers) do controller:_Refresh(false) end
        end)
    end
    self:Refresh()
    return self
end

return Resize
