local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function removeChild(parent, child)
    if not parent then return end
    for index, candidate in ipairs(parent.children) do
        if candidate == child then table.remove(parent.children, index); return end
    end
end

-- Native geometry retains anchors when the parent changes size. Subscribing does
-- not invoke callbacks: constructors must finish before input is dispatched.
local function component(parent, kind, categoryID, dynamicID)
    local result = {
        parent = parent, kind = kind, children = {}, subscriptions = {}, namedSubscriptions = {},
        x = 0, y = 0, width = 0, height = 0, hidden = false,
        cursorConfig = {}, operationCursors = {},
    }
    local px, py, ax, ay, w, h, aw, ah = 0, 0, 0, 0, 0, 0, 0, 0
    function result:EmitResize()
        local callbacks = {}
        if self.subscriptions[ui.Hook.ONRESIZE] then
            table.insert(callbacks, self.subscriptions[ui.Hook.ONRESIZE])
        end
        for _, callback in pairs(self.namedSubscriptions[ui.Hook.ONRESIZE] or {}) do
            table.insert(callbacks, callback)
        end
        for _, callback in ipairs(callbacks) do callback(self) end
    end
    function result:ResolveGeometry()
        assert(not self.destroyed, "resolving a destroyed component")
        local oldWidth, oldHeight = self.width, self.height
        self.x, self.y = px + (parent and parent.width or 0) * ax, py + (parent and parent.height or 0) * ay
        self.width, self.height = w + (parent and parent.width or 0) * aw, h + (parent and parent.height or 0) * ah
        if oldWidth ~= self.width or oldHeight ~= self.height then
            local children = {}
            for _, child in ipairs(self.children) do table.insert(children, child) end
            for _, child in ipairs(children) do
                if not child.destroyed then child:ResolveGeometry() end
            end
            self:EmitResize()
        end
    end
    function result:SetPos(x, y, xAnchor, yAnchor)
        assert(not self.destroyed, "positioning a destroyed component")
        px, py, ax, ay = x, y, xAnchor or 0, yAnchor or 0
        self:ResolveGeometry()
    end
    function result:SetSize(width, height, widthAnchor, heightAnchor)
        assert(not self.destroyed, "sizing a destroyed component")
        w, h, aw, ah = width, height, widthAnchor or 0, heightAnchor or 0
        self:ResolveGeometry()
    end
    function result:SetWidth(width, anchor)
        w, aw = width, anchor or 0
        self:ResolveGeometry()
    end
    function result:SetHeight(height, anchor)
        h, ah = height, anchor or 0
        self:ResolveGeometry()
    end
    function result:SetScrollSize(width, height) self.scrollWidth, self.scrollHeight = width, height end
    function result:SetScrollPos(x, y) self.scrollX, self.scrollY = x, y end
    function result:Subscribe(hook, name, callback)
        assert(not self.destroyed, "subscribing a destroyed component")
        if callback then
            self.namedSubscriptions[hook] = self.namedSubscriptions[hook] or {}
            self.namedSubscriptions[hook][name] = callback
        else
            self.subscriptions[hook] = name
        end
    end
    function result:Unsubscribe(hook, name)
        assert(not self.destroyed, "unsubscribing a destroyed component")
        if name then
            if self.namedSubscriptions[hook] then self.namedSubscriptions[hook][name] = nil end
        else
            self.subscriptions[hook], self.namedSubscriptions[hook] = nil, nil
        end
    end
    function result:MoveToFront()
        assert(not self.destroyed, "raising a destroyed component")
        if parent then removeChild(parent, self); table.insert(parent.children, self) end
    end
    function result:MoveToBack()
        assert(not self.destroyed, "lowering a destroyed component")
        if parent then removeChild(parent, self); table.insert(parent.children, 1, self) end
    end
    function result:Destroy()
        assert(not self.destroyed, "destroying a component twice")
        while #self.children > 0 do self.children[#self.children]:Destroy() end
        removeChild(parent, self)
        self.destroyed = true
    end
    result.opConfig = {
        ClearOpCursors = function() result.operationCursors = {} end,
        SetOpCursor = function(_, operation, cursor) result.operationCursors[operation] = cursor end,
    }
    if parent then table.insert(parent.children, result) end
    return Interfaces.component(result, parent, categoryID, dynamicID)
end

local function factory(kind)
    return { new = function(parent, categoryID, dynamicID)
        return component(parent, kind, categoryID, dynamicID)
    end }
end
ui = {
    Layer = factory("layer"), Sprite = factory("sprite"), Rectangle = factory("rectangle"), Text = factory("text"),
    Hook = {
        ONCLICK = 1, ONHOLD = 2, ONDRAG = 3, ONRELEASE = 4, ONDRAGCOMPLETE = 5,
        ONSCROLLWHEEL = 6, ONMOUSEOVER = 7, ONMOUSELEAVE = 8, ONMOUSEREPEAT = 9, ONRESIZE = 10,
    },
    AlignMode = { TOPLEFT = 1, CENTRE = 2 },
}
id = {
    Sprite = setmetatable({}, { __index = function(_, name) return name end }),
    Font = { MUSEO_SANS_15PT_REGULAR = 1, CINZEL_13PT_BOLD = 2 },
}
local font = {
    baseline = 18,
    GetStringLineCount = function() return 1 end,
    GetStringWidth = function(_, text) return #text * 7 end,
}
config = {
    Cursor = {
        CURSOR_GOTO = 1, CURSOR_USE = 2, CURSOR_OPEN = 3, TOPLEVEL_V2_MOVE = 4,
        TOPLEVEL_V2_SCALE_VERT = 5, TOPLEVEL_V2_SCALE_HORZ = 6,
        TOPLEVEL_V2_SCALE_DIAG_1 = 7, TOPLEVEL_V2_SCALE_DIAG_2 = 8,
    },
    Font = { MUSEO_SANS_15PT_REGULAR = font, CINZEL_13PT_BOLD = font },
}
Mouse = { GetPosition = function() return nil end }
local altDown, logicCallbacks = false, {}
Keyboard = {
    IsAvailable = function() return true end,
    IsBlocked = function() return false end,
    IsAltDown = function() return altDown end,
}
Event = { Logic = {
    Subscribe = function(name, callback) logicCallbacks[name] = callback end,
    Unsubscribe = function(name) logicCallbacks[name] = nil end,
} }
local function tick()
    local pending = {}
    for _, callback in pairs(logicCallbacks) do table.insert(pending, callback) end
    for _, callback in ipairs(pending) do callback() end
end
local function setAlt(value) altDown = value; tick() end
local function fire(target, hook, ...)
    assert(not target.destroyed, "dispatching input to a destroyed component")
    local callbacks = {}
    if target.subscriptions[hook] then table.insert(callbacks, target.subscriptions[hook]) end
    for _, callback in pairs(target.namedSubscriptions[hook] or {}) do table.insert(callbacks, callback) end
    assert(#callbacks > 0, "missing native hook " .. tostring(hook))
    for _, callback in ipairs(callbacks) do callback(target, ...) end
end

-- Resolve native sibling order before dispatch, rather than invoking a covered
-- drag layer directly. Coordinates are relative to the supplied parent.
local function hitAt(area, x, y)
    for index = #area.children, 1, -1 do
        local child = area.children[index]
        if not child.hidden and child.enabled ~= false and
            x >= child.x and x < child.x + child.width and
            y >= child.y and y < child.y + child.height then
            local target = hitAt(child, x - child.x, y - child.y)
            if target then return target end
            if child.clickthrough ~= true then return child end
        end
    end
end

local function hoverAt(area, x, y)
    local target = hitAt(area, x, y)
    if target then
        target.isMouseOver = true
        if target.subscriptions[ui.Hook.ONMOUSEOVER] then
            fire(target, ui.Hook.ONMOUSEOVER, 0, 0)
        end
    end
    return target
end
local function rect(root)
    return { x = root.x, y = root.y, width = root.width, height = root.height }
end
local function expectRect(root, expected, message)
    for _, key in ipairs({ "x", "y", "width", "height" }) do
        expect(root[key], expected[key], message .. " " .. key)
    end
end
local function expectClickthrough(root)
    expect(root.clickthrough, true, "resize feedback does not intercept input")
    for _, child in ipairs(root.children) do expectClickthrough(child) end
end
local function expectGold(controller, root)
    local feedback = assert(controller.feedback, "enabled edge displays feedback")
    expect(feedback.origin, nil, "resizing never displays a white origin frame")
    expect(feedback.active.hidden, false, "gold feedback is visible")
    expect(feedback.active.parent, root.parent, "gold feedback shares the resized surface's coordinate space")
    expectRect(feedback.active, rect(root), "gold feedback outlines the live rectangle")
    expectClickthrough(feedback.active)
    local seen = false
    local function visit(native)
        if native.kind == "sprite" then
            expect(native.spriteID:match("^(RS3_FEEDBACK_%u+_FRAME)_%d+$"),
                "RS3_FEEDBACK_FINAL_FRAME", "feedback uses native gold FINAL artwork")
            seen = true
        end
        for _, child in ipairs(native.children) do visit(child) end
    end
    visit(feedback.active)
    expect(seen, true, "feedback includes native frame artwork")
    return feedback.active
end
local function expectCleared(controller, active, message)
    expect(controller.feedback, nil, message .. " releases gold feedback")
    expect(active.destroyed, true, message .. " destroys gold native layers")
    expect(controller.dragState, nil, message .. " cancels resize state")
end
local edgeCursors = {
    n = config.Cursor.TOPLEVEL_V2_SCALE_VERT, s = config.Cursor.TOPLEVEL_V2_SCALE_VERT,
    e = config.Cursor.TOPLEVEL_V2_SCALE_HORZ, w = config.Cursor.TOPLEVEL_V2_SCALE_HORZ,
    nw = config.Cursor.TOPLEVEL_V2_SCALE_DIAG_1, se = config.Cursor.TOPLEVEL_V2_SCALE_DIAG_1,
    ne = config.Cursor.TOPLEVEL_V2_SCALE_DIAG_2, sw = config.Cursor.TOPLEVEL_V2_SCALE_DIAG_2,
}
local function begin(controller, direction, root)
    local handle = assert(controller.handles[direction], "missing " .. direction .. " resize edge")
    expect(handle.hidden, false, direction .. " edge is reachable without Alt")
    expect(handle.clickthrough, false, direction .. " edge receives pointer input")
    expect(handle.cursorConfig.mouseOverCursor, edgeCursors[direction:sub(1, 2)],
        direction .. " edge shows its scale cursor")
    expect(controller.feedback, nil, "hover does not display resize feedback")
    fire(handle, ui.Hook.ONCLICK, 2, 2)
    expectGold(controller, root)
    fire(handle, ui.Hook.ONHOLD, 2, 2)
    expectGold(controller, root)
    return handle
end
local function finish(controller, handle, hook)
    fire(handle, hook or ui.Hook.ONRELEASE, 2, 2)
    expect(controller.dragState, nil, "release/completion stops resizing")
    expect(controller.feedback, nil, "release clears feedback even while still over the edge")
end

local Window = require("src/window")
local Panel = require("src/panel")
local parent = component(nil, "parent")
parent:SetSize(1000, 700)
local overlayParent = component(nil, "overlayParent")
overlayParent:SetSize(1200, 800)
local directions = { "n", "s", "e", "w", "nw_v", "ne_v", "sw_v", "se_v" }

-- Resize is opt-in; both existing panel surfaces remain unchanged by default.
local plainWindow = Window.new(parent, { title = "Default" })
local plainPanel = Panel.new(parent, { popout = true, overlayParent = overlayParent })
expect(plainWindow.resize, nil, "default window has no resize controller")
expect(plainPanel.dockResize, nil, "default dock has no resize controller")
expect(plainPanel.overlayResize, nil, "default popout has no resize controller")
plainWindow:Destroy()
plainPanel:Destroy()

local function createSurface(kind, area, options)
    options = options or {}
    options.resizable = true
    options.width, options.height = options.width or 320, options.height or 220
    options.x, options.y = options.x or 100, options.y or 80
    if kind == "titled" or kind == "untitled" then
        options.title = kind == "titled" and "Resizable" or nil
        local owner = Window.new(area, options)
        return owner, owner.root, owner.resize
    elseif kind == "flow" then
        local host = Window.new(area, { title = "Host", width = 700, height = 540, scrollable = false })
        -- Omit y: this must be real flow, not an absolute-positioned AddPanel.
        options.x, options.y = nil, nil
        local owner = host:AddPanel(options)
        return owner, owner.dock.root, owner.dockResize, host
    elseif kind == "popout" then
        options.popout, options.poppedOut, options.overlayParent = true, true, area
        options.popoutX, options.popoutY = options.x, options.y
        options.popoutWidth, options.popoutHeight = options.width, options.height
        local owner = Panel.new(parent, options)
        return owner, owner.overlay.root, owner.overlayResize
    end
    local owner = Panel.new(area, options)
    return owner, owner.dock.root, owner.dockResize
end

for _, kind in ipairs({ "titled", "untitled", "standalone", "flow", "popout" }) do
    for index, direction in ipairs(directions) do
        local owner, root, controller, host = createSurface(kind, parent)
        assert(controller, kind .. " supports opt-in resizing")
        local initial = rect(root)
        local handle = begin(controller, direction, root)
        fire(handle, ui.Hook.ONHOLD, 19, 15)
        local west, east = direction:find("w", 1, true), direction:find("e", 1, true)
        local north, south = direction:find("n", 1, true), direction:find("s", 1, true)
        local expected = {
            x = initial.x + (west and 17 or 0), y = initial.y + (north and 13 or 0),
            width = initial.width + (east and 17 or west and -17 or 0),
            height = initial.height + (south and 13 or north and -13 or 0),
        }
        expectRect(root, expected, kind .. " " .. direction .. " preserves opposite anchor")
        expectGold(controller, root)
        tick()
        -- The shared logic refresh must not replace the expanded input capture.
        fire(handle, ui.Hook.ONHOLD, 20, 16)
        fire(handle, ui.Hook.ONHOLD, 19, 15)
        expectRect(root, expected, kind .. " " .. direction .. " remains stable across capture refresh")
        finish(controller, handle, index % 2 == 0 and ui.Hook.ONDRAGCOMPLETE or ui.Hook.ONRELEASE)
        fire(handle, ui.Hook.ONHOLD, 100, 100)
        expectRect(root, expected, "released hold cannot restart resizing")
        if host then
            local following = host:AddText("Following flow row")
            expect(following.y >= root.y + root.height, true, "following flow row clears resized panel")
            following:Destroy()
            tick()
            expectRect(root, expected, "flow reflow retains all resized edges")
            host:SetSize(740, 580)
            tick()
            expectRect(root, expected, "host resize retains explicit resized panel rectangle")
            host:Destroy()
        else
            owner:Destroy()
        end
    end
end

-- A flow resize must not leave a stale width after resizing the other surface.
local flowHost = Window.new(parent, { title = "Inline resize", width = 800, height = 600 })
local flowPanel = flowHost:AddPanel({ resizable = true, popout = true, width = 300, height = 200 })
local inlineSibling = flowHost:AddPanel({ inline = true, width = 100, height = 160 })
local flowHandle = begin(flowPanel.dockResize, "e", flowPanel.root)
fire(flowHandle, ui.Hook.ONHOLD, 42, 2)
finish(flowPanel.dockResize, flowHandle)
flowPanel:SetPoppedOut(true)
flowHandle = begin(flowPanel.overlayResize, "e", flowPanel.overlay.root)
fire(flowHandle, ui.Hook.ONHOLD, 62, 2)
finish(flowPanel.overlayResize, flowHandle)
flowPanel:SetPoppedOut(false)
expect(flowPanel.root.width, 400, "redocking retains both surface resize increments")
expect(inlineSibling.root.x >= flowPanel.root.x + flowPanel.root.width, true,
    "redocking reflows inline siblings using the new width")
flowHost:Destroy()

-- Click-through popouts expose resize edges only while Alt is held. Changing
-- either input state cancels a resize that is no longer allowed.
local clickthroughPanel = Panel.new(parent, {
    resizable = true, popout = true, poppedOut = true, popoutClickthrough = true,
    overlayParent = overlayParent, width = 300, height = 200,
})
local clickthroughResize = clickthroughPanel.overlayResize
expect(clickthroughResize.enabled, false, "click-through popout resize requires Alt")
for _, edge in pairs(clickthroughResize.handles) do
    expect(edge.hidden, true, "click-through popout resize edges stay hidden without Alt")
    expect(edge.clickthrough, true, "hidden click-through popout edges do not intercept input")
end
setAlt(true)
expect(clickthroughResize.enabled, true, "Alt enables click-through popout resize")
handle = begin(clickthroughResize, "se_v", clickthroughPanel.overlay.root)
active = clickthroughResize.feedback.active
setAlt(false)
expectCleared(clickthroughResize, active, "releasing Alt on a click-through popout")
for _, edge in pairs(clickthroughResize.handles) do
    expect(edge.hidden, true, "releasing Alt hides click-through popout resize edges")
    expect(edge.cursorConfig.mouseOverCursor, -1, "hidden resize edges drop their scale cursor")
end
clickthroughPanel:SetPopoutClickthrough(false)
expect(clickthroughResize.enabled, true, "disabling click-through enables ordinary resize")
handle = begin(clickthroughResize, "e", clickthroughPanel.overlay.root)
active = clickthroughResize.feedback.active
clickthroughPanel:SetPopoutClickthrough(true)
expectCleared(clickthroughResize, active, "enabling click-through without Alt")
clickthroughPanel:Destroy()

-- Inline requests can become the first item in a row, initially or after removal.
for _, placement in ipairs({ "first", "inline", "removed" }) do
    flowHost = Window.new(parent, { title = "First inline", width = 800, height = 600 })
    local previous = placement ~= "first" and flowHost:AddPanel({ width = 100, height = 160 }) or nil
    flowPanel = flowHost:AddPanel({ resizable = true, inline = true, width = 300, height = 200 })
    if placement == "removed" then previous:Destroy() end
    local before = rect(flowPanel.root)
    flowHandle = begin(flowPanel.dockResize, "nw_v", flowPanel.root)
    fire(flowHandle, ui.Hook.ONHOLD, 22, 17)
    expectRect(flowPanel.root, {
        x = before.x + 20, y = before.y + 15, width = before.width - 20, height = before.height - 15,
    }, "northwest resize preserves opposite corner across inline row placements")
    finish(flowPanel.dockResize, flowHandle)
    flowHost:Destroy()
end

-- Edge hitboxes remain reachable without displaying feedback on hover.
local hoverPoints = {
    n = { 0.5, 0 },
    s = { 0.5, 1 },
    e = { 1, 0.5 },
    w = { 0, 0.5 },
    nw_v = { 0, 0 },
    ne_v = { 1, 0 },
    sw_v = { 0, 1 },
    se_v = { 1, 1 },
}
for _, kind in ipairs({ "titled", "untitled", "standalone", "flow", "popout" }) do
    local owner, root, controller, host = createSurface(kind, parent)
    local before = rect(root)
    for direction, point in pairs(hoverPoints) do
        local x, y = root.x + root.width * point[1], root.y + root.height * point[2]
        local target = hoverAt(root.parent, x, y)
        expect(target, controller.handles[direction], kind .. " edge receives hover input")
        tick()
        expect(controller.feedback, nil, "hover never displays the gold border")
        expectRect(root, before, "hover leaves the rectangle unchanged")
        -- The five-unit band is reachable on either side; farther points stay clear.
        for _, distance in ipairs({ -6, -4.5, 4.5, 6 }) do
            local nearX = x + (point[1] == 0 and distance or point[1] == 1 and -distance or 0)
            local nearY = y + (point[2] == 0 and distance or point[2] == 1 and -distance or 0)
            target = hoverAt(root.parent, nearX, nearY)
            if math.abs(distance) < 5 then
                expect(target, controller.handles[direction], "expanded edge band receives hover")
                expect(controller.feedback, nil, "expanded hover band does not display feedback")
            else
                for _, edge in pairs(controller.handles) do
                    expect(target ~= edge, true, "pointer away from edge cannot activate resize")
                end
            end
        end
    end
    if host then host:Destroy() else owner:Destroy() end
end

-- Corner arms extend the diagonal grab along both edges without covering the
-- content, and the straight edges begin where the arms end.
do
    local owner, root, controller = createSurface("titled", parent)
    local before = rect(root)
    local area = root.parent
    expect(hoverAt(area, root.x + 25, root.y), controller.handles.nw_h, "top edge near the corner is the corner arm")
    expect(hoverAt(area, root.x, root.y + 25), controller.handles.nw_v, "left edge near the corner is the corner arm")
    expect(hoverAt(area, root.x + 35, root.y), controller.handles.n, "top edge past the arm is the north edge")
    expect(hoverAt(area, root.x, root.y + 35), controller.handles.w, "left edge past the arm is the west edge")
    local inside = hoverAt(area, root.x + 15, root.y + 8)
    for _, edge in pairs(controller.handles) do
        expect(inside ~= edge, true, "content beside the corner arms stays clear of resize handles")
    end
    local handle = begin(controller, "nw_h", root)
    fire(handle, ui.Hook.ONHOLD, 2 - 10, 2 - 10)
    expectRect(root, {
        x = before.x - 10, y = before.y - 10, width = before.width + 10, height = before.height + 10,
    }, "the horizontal corner arm resizes both axes")
    finish(controller, handle)
    owner:Destroy()
end

-- Clicking or dragging a resize edge must not bury the separate header layer.
local headerWindow, headerRoot, headerResize = createSurface("titled", parent)
local handle, active
for _, drag in ipairs({ false, true }) do
    local edge = hoverAt(parent, headerRoot.x + headerRoot.width, headerRoot.y + headerRoot.height / 2)
    fire(edge, ui.Hook.ONCLICK, 2, 2)
    active = expectGold(headerResize, headerRoot)
    if drag then
        fire(edge, ui.Hook.ONHOLD, 2, 2)
        fire(edge, ui.Hook.ONHOLD, 22, 2)
    end
    fire(edge, ui.Hook.ONRELEASE)
    expectCleared(headerResize, active, "resize mouse-up")
    local title = hoverAt(parent, headerRoot.x + 100, headerRoot.y + 12)
    expect(title, headerWindow.titleDrag, "header stays reachable after resize")
    expect(title.cursorConfig.mouseOverCursor, config.Cursor.TOPLEVEL_V2_MOVE, "header retains move cursor")
    local before = rect(headerRoot)
    fire(title, ui.Hook.ONCLICK, 100, 12)
    fire(title, ui.Hook.ONHOLD, 100, 12)
    fire(title, ui.Hook.ONHOLD, 125, 27)
    fire(title, ui.Hook.ONRELEASE)
    expectRect(headerRoot, {
        x = before.x + 25, y = before.y + 15, width = before.width, height = before.height,
    }, "header drag moves the resized window without changing dimensions")
end
handle = begin(headerResize, "se_v", headerRoot)
active = headerResize.feedback.active
headerResize:Cancel()
expectCleared(headerResize, active, "explicit cancellation")
headerWindow:Destroy()

-- Limits must apply to the resized edge, keeping the other edge fixed unless
-- the containing area is too small even for the configured minimum.
local bounds = component(nil, "bounds")
bounds:SetSize(600, 400)
for _, kind in ipairs({ "titled", "standalone", "popout" }) do
    for _, sample in ipairs({
        { direction = "se_v", delta = 1000, expected = { x = 100, y = 80, width = 360, height = 250 } },
        { direction = "se_v", delta = -1000, expected = { x = 100, y = 80, width = 100, height = 80 } },
        { direction = "nw_v", delta = -1000, expected = { x = 40, y = 30, width = 360, height = 250 } },
        { direction = "nw_v", delta = 1000, expected = { x = 300, y = 200, width = 100, height = 80 } },
    }) do
        local owner, root, controller = createSurface(kind, bounds, {
            width = 300, height = 200, minWidth = 100, minHeight = 80, maxWidth = 360, maxHeight = 250,
        })
        handle = begin(controller, sample.direction, root)
        fire(handle, ui.Hook.ONHOLD, 2 + sample.delta, 2 + sample.delta)
        expectRect(root, sample.expected, kind .. " respects min/max and opposite anchor")
        expectGold(controller, root)
        finish(controller, handle)
        owner:SetSize(1, 1)
        expect(root.width, 100, "SetSize applies configured minimum width")
        expect(root.height, 80, "SetSize applies configured minimum height")
        owner:SetSize(1000, 1000)
        expect(root.width, 360, "SetSize applies configured maximum width")
        expect(root.height, 250, "SetSize applies configured maximum height")
        if owner.dock then
            if owner.poppedOut then owner:SetPoppedOut(false, false) end
            expect(owner.dock.root.width, owner.overlay and owner.overlay.root.width or root.width,
                "panel SetSize mirrors width to dock and popout")
            expect(owner.dock.root.height, owner.overlay.root.height,
                "resized popout height is retained when docking")
        end
        owner:Destroy()
    end
    for _, direction in ipairs({ "se_v", "nw_v" }) do
        local owner, root, controller = createSurface(kind, bounds, { width = 300, height = 200 })
        handle = begin(controller, direction, root)
        local delta = direction == "se_v" and 10000 or -10000
        fire(handle, ui.Hook.ONHOLD, 2 + delta, 2 + delta)
        expectRect(root, direction == "se_v" and { x = 100, y = 80, width = 500, height = 320 }
            or { x = 0, y = 0, width = 400, height = 280 }, kind .. " stops at viewport boundary")
        expectGold(controller, root)
        finish(controller, handle)
        owner:Destroy()
    end
    bounds:SetSize(100, 90)
    local owner, root, controller = createSurface(kind, bounds, {
        width = 220, height = 140, minWidth = 220, minHeight = 140,
    })
    handle = begin(controller, "nw_v", root)
    fire(handle, ui.Hook.ONHOLD, 1000, 1000)
    expectRect(root, { x = 0, y = 0, width = 220, height = 140 }, "undersized viewport retains minimum and pins origin")
    expectGold(controller, root)
    finish(controller, handle)
    owner:Destroy()
    bounds:SetSize(600, 400)
end


-- Owner motion and reflow update edge hit areas even with no resize events.
local moving, movingRoot, movingResize = createSurface("titled", parent)
local oldHandle = rect(movingResize.handles.e)
fire(moving.titleDrag, ui.Hook.ONCLICK, 12, 9)
fire(moving.titleDrag, ui.Hook.ONHOLD, 12, 9)
fire(moving.titleDrag, ui.Hook.ONHOLD, 49, 32)
fire(moving.titleDrag, ui.Hook.ONRELEASE)
tick()
expect(movingResize.handles.e.x, oldHandle.x + 37, "edge follows window movement horizontally")
expect(movingResize.handles.e.y, oldHandle.y + 23, "edge follows window movement vertically")
handle = begin(movingResize, "e", movingRoot)
active = movingResize.feedback.active
fire(moving.titleDrag, ui.Hook.ONCLICK, 12, 9)
fire(moving.titleDrag, ui.Hook.ONHOLD, 12, 9)
expectCleared(movingResize, active, "title movement supersedes resizing")
local titleFeedback = assert(moving.dragFeedback, "title drag still starts movement")
local titleOrigin, titleFinal = titleFeedback.origin, titleFeedback.active
expect(movingResize.handles.e.hidden, true, "movement capture hides resize handles")
fire(moving.titleDrag, ui.Hook.ONRELEASE)
expect(titleOrigin.destroyed, true, "movement release removes white feedback")
expect(titleFinal.destroyed, true, "movement release removes gold feedback")
handle = begin(movingResize, "e", movingRoot)
active = movingResize.feedback.active
moving:Close()
expectCleared(movingResize, active, "Close")
for _, edge in pairs(movingResize.handles) do expect(edge.hidden, true, "closed window hides resize edges") end
moving:Show()
tick()
handle = begin(movingResize, "w", movingRoot)
active = movingResize.feedback.active
local savedHandles = {}
for _, edge in pairs(movingResize.handles) do table.insert(savedHandles, edge) end
moving:Destroy()
expectCleared(movingResize, active, "Destroy")
for _, edge in ipairs(savedHandles) do expect(edge.destroyed, true, "Destroy removes sibling hit areas") end

local closing, closingRoot, closingResize = createSurface("titled", parent, { destroyOnClose = true })
begin(closingResize, "se_v", closingRoot)
active = closingResize.feedback.active
closing:Close()
expectCleared(closingResize, active, "destroy-on-close")
expect(closingRoot.destroyed, true, "destroy-on-close removes the resized surface")

-- A late viewport change during capture must not be undone by the next hold.
local livePanel, liveRoot, liveResize = createSurface("popout", bounds, { width = 300, height = 200 })
handle = begin(liveResize, "se_v", liveRoot)
fire(handle, ui.Hook.ONHOLD, 42, 22)
bounds.width, bounds.height = 450, 300
tick()
local adjusted = rect(liveRoot)
expect(adjusted.x >= 0 and adjusted.x + adjusted.width <= bounds.width, true,
    "active popout remains horizontally contained after late viewport shrink")
expect(adjusted.y >= 0 and adjusted.y + adjusted.height <= bounds.height, true,
    "active popout remains vertically contained after late viewport shrink")
fire(handle, ui.Hook.ONHOLD, 42, 22)
expectRect(liveRoot, adjusted, "stationary hold preserves viewport-adjusted resize rectangle")
fire(handle, ui.Hook.ONHOLD, 52, 32)
expectRect(liveRoot, {
    x = adjusted.x, y = adjusted.y, width = adjusted.width + 10, height = adjusted.height + 10,
}, "resizing continues from the adjusted rectangle")
expectGold(liveResize, liveRoot)
finish(liveResize, handle)
livePanel:Destroy()

local switching = Panel.new(parent, {
    resizable = true, popout = true, overlayParent = overlayParent,
    x = 100, y = 80, width = 300, height = 200,
})
local dockResize, overlayResize = switching.dockResize, switching.overlayResize
handle = begin(dockResize, "se_v", switching.dock.root)
active = dockResize.feedback.active
switching:SetPoppedOut(true)
expectCleared(dockResize, active, "popping out")
for _, edge in pairs(dockResize.handles) do expect(edge.hidden, true, "popped-out dock edges stay hidden") end
handle = begin(overlayResize, "nw_v", switching.overlay.root)
active = overlayResize.feedback.active
switching:SetPoppedOut(false)
expectCleared(overlayResize, active, "docking")
for _, edge in pairs(overlayResize.handles) do expect(edge.hidden, true, "docked overlay edges stay hidden") end

-- Alt move and ordinary edge resize are mutually exclusive; neither leaves a
-- stranded capture or either colour of movement feedback behind.
for _, poppedOut in ipairs({ false, true }) do
    switching:SetPoppedOut(poppedOut)
    local root = poppedOut and switching.overlay.root or switching.dock.root
    local controller = poppedOut and overlayResize or dockResize
    local drag = poppedOut and switching.overlayDragLayer or switching.dockDragLayer
    setAlt(false)
    handle = begin(controller, "e", root)
    active = controller.feedback.active
    setAlt(true)
    fire(drag, ui.Hook.ONCLICK, 12, 9)
    fire(drag, ui.Hook.ONHOLD, 12, 9)
    expectCleared(controller, active, "Alt movement supersedes resizing")
    local movement = assert(switching.dragFeedback, "Alt still starts panel movement")
    local origin, final = movement.origin, movement.active
    expect(controller.handles.s.hidden, true, "Alt movement capture hides resize handles")
    fire(drag, ui.Hook.ONRELEASE)
    expect(origin.destroyed, true, "Alt movement release removes white feedback")
    expect(final.destroyed, true, "Alt movement release removes gold feedback")
    handle = begin(controller, "s", root)
    finish(controller, handle)
    setAlt(false)
end
switching:Destroy()
expect(next(logicCallbacks), nil, "destroyed owners leave no logic listeners")

local Components = require("src/core/components")
local Resize = require("src/core/resize")
local resizeHost = component(parent, "shared-resize-host")
resizeHost:SetSize(360, 220)
local autoOwner = Components.new(ui.Layer, resizeHost, { categoryID = "auto" })
autoOwner:SetSize(90, 65)
local autoResize = Resize.new(resizeHost, autoOwner, {
    setRect = function(x, y, width, height)
        autoOwner:SetPos(x, y)
        autoOwner:SetSize(width, height)
    end,
    isVisible = function() return true end,
})
expect(autoResize.handles.se_v.categoryID > 0, true,
    "auto owner's sibling resize handles use managed native IDs")
local autoHandle = begin(autoResize, "se_v", autoOwner)
expect(autoResize.feedback.active.categoryID > 0, true,
    "deferred resize feedback follows the auto owner's policy")
finish(autoResize, autoHandle)
autoResize:Destroy()
-- Optional geometry constraints can reject a motion without releasing the
-- capture or its outline, and can return a different safe edge on the next hold.
local limitedOwner = component(resizeHost, "limited-owner")
limitedOwner:SetPos(100, 100)
limitedOwner:SetSize(100, 80)
local allowResize = false
local limitedResize = Resize.new(resizeHost, limitedOwner, {
    isVisible = function() return true end,
    setRect = function(x, y, width, height)
        limitedOwner:SetPos(x, y)
        limitedOwner:SetSize(width, height)
    end,
    constrainRect = function(x, y, width, height, edge)
        expect(edge.east, true, "constraint receives the grabbed edge")
        if not allowResize then return nil end
        return x, y, math.min(width, 120), height
    end,
})
local limitedHandle = begin(limitedResize, "e", limitedOwner)
local limitedFeedback = limitedResize.feedback
fire(limitedHandle, ui.Hook.ONHOLD, 42, 2)
expectRect(limitedOwner, { x = 100, y = 100, width = 100, height = 80 },
    "rejected motion keeps the source rectangle")
expect(limitedResize.feedback, limitedFeedback, "rejected motion retains resize feedback")
expect(limitedResize.dragState ~= nil, true, "rejected motion retains capture")
allowResize = true
fire(limitedHandle, ui.Hook.ONHOLD, 62, 2)
expectRect(limitedOwner, { x = 100, y = 100, width = 120, height = 80 },
    "accepted motion applies the constrained rectangle")
expectGold(limitedResize, limitedOwner)
finish(limitedResize, limitedHandle)
limitedResize:Destroy()
expect(limitedResize.constrainRect, nil, "destroy clears the constraint callback")
limitedOwner:Destroy()


local autoPhysicalHost = Components.new(ui.Layer, overlayParent, { categoryID = "auto" })
autoPhysicalHost:SetSize(360, 220)
local legacyOwner = Components.new(ui.Layer, autoPhysicalHost, {
    _categoryPolicy = "legacy",
})
legacyOwner:SetSize(90, 65)
local legacyResize = Resize.new(autoPhysicalHost, legacyOwner, {
    setRect = function(x, y, width, height)
        legacyOwner:SetPos(x, y)
        legacyOwner:SetSize(width, height)
    end,
    isVisible = function() return true end,
})
expect(legacyResize.handles.se_v.categoryID, autoPhysicalHost.categoryID,
    "legacy resize handles override their auto physical host")
local legacyHandle = begin(legacyResize, "se_v", legacyOwner)
expect(legacyResize.feedback.active.categoryID, autoPhysicalHost.categoryID,
    "deferred resize feedback also follows the legacy owner")
finish(legacyResize, legacyHandle)
legacyResize:Destroy()
autoOwner:Destroy()
legacyOwner:Destroy()
autoPhysicalHost:Destroy()

-- A vanished native interface must be detected before touching any stale handle.
local unloadedWindow, unloadedRoot, unloadedResize = createSurface("titled", parent)
local unloadedPanel = Panel.new(parent, { resizable = true, popout = true, overlayParent = overlayParent })
begin(unloadedResize, "se_v", unloadedRoot)
Interfaces.unload()
tick()
expect(unloadedResize.feedback, nil, "interface unload releases resize feedback state")
expect(unloadedResize.dragState, nil, "interface unload cancels capture state")
unloadedWindow:Destroy()
unloadedPanel:Destroy()
expect(next(logicCallbacks), nil, "unloaded owners leave no logic listeners")

print("resize tests passed")
