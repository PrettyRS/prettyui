local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function removeChild(parent, child)
    if not parent then return end
    for index, candidate in ipairs(parent.children) do
        if candidate == child then
            table.remove(parent.children, index)
            return
        end
    end
end

local function component(parent, kind)
    local result = {
        parent = parent, kind = kind, children = {}, subscriptions = {}, namedSubscriptions = {},
        x = 0, y = 0, width = 0, height = 0, hidden = false,
        opConfig = { ClearOpCursors = function() end, SetOpCursor = function() end },
        cursorConfig = {},
    }
    function result:SetPos(x, y, xAnchor, yAnchor)
        assert(not self.destroyed, "positioning a destroyed component")
        self.x = x + ((parent and parent.width or 0) * (xAnchor or 0))
        self.y = y + ((parent and parent.height or 0) * (yAnchor or 0))
    end
    function result:EmitResize()
        for _, callback in pairs(self.namedSubscriptions[ui.Hook.ONRESIZE] or {}) do callback(self) end
    end
    function result:SetSize(width, height, widthAnchor, heightAnchor)
        self.width = width + ((parent and parent.width or 0) * (widthAnchor or 0))
        self.height = height + ((parent and parent.height or 0) * (heightAnchor or 0))
        self:EmitResize()
    end
    function result:SetWidth(width, anchor)
        self.width = width + ((parent and parent.width or 0) * (anchor or 0))
        self:EmitResize()
    end
    function result:SetHeight(height, anchor)
        self.height = height + ((parent and parent.height or 0) * (anchor or 0))
        self:EmitResize()
    end
    function result:SetScrollSize(width, height)
        self.scrollWidth, self.scrollHeight = width, height
    end
    function result:SetScrollPos(x, y)
        self.scrollX, self.scrollY = x, y
    end
    function result:Subscribe(hook, name, callback)
        if callback then
            self.namedSubscriptions[hook] = self.namedSubscriptions[hook] or {}
            self.namedSubscriptions[hook][name] = callback
        else
            self.subscriptions[hook] = name
        end
    end
    function result:Unsubscribe(hook, name)
        if name then
            if self.namedSubscriptions[hook] then self.namedSubscriptions[hook][name] = nil end
        else
            self.subscriptions[hook] = nil
            self.namedSubscriptions[hook] = nil
        end
    end
    function result:MoveToFront()
        if not parent then return end
        removeChild(parent, self)
        table.insert(parent.children, self)
    end
    function result:MoveToBack()
        if not parent then return end
        removeChild(parent, self)
        table.insert(parent.children, 1, self)
    end
    function result:Destroy()
        while #self.children > 0 do self.children[#self.children]:Destroy() end
        removeChild(parent, self)
        self.destroyed = true
    end
    if parent then table.insert(parent.children, result) end
    return Interfaces.component(result, parent)
end

local function factory(kind)
    return { new = function(parent) return component(parent, kind) end }
end

ui = {
    Layer = factory("layer"), Sprite = factory("sprite"),
    Rectangle = factory("rectangle"), Text = factory("text"),
    Hook = {
        ONCLICK = 1, ONHOLD = 2, ONDRAG = 3, ONRELEASE = 4,
        ONDRAGCOMPLETE = 5, ONSCROLLWHEEL = 6, ONMOUSEOVER = 7,
        ONMOUSELEAVE = 8, ONMOUSEREPEAT = 9, ONRESIZE = 10,
    },
    AlignMode = { TOPLEFT = 1, CENTRE = 2 },
}

-- Retain each native sprite's identity rather than making every lookup equal.
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
    Cursor = { CURSOR_GOTO = 1, CURSOR_USE = 2, CURSOR_OPEN = 3 },
    Font = { MUSEO_SANS_15PT_REGULAR = font, CINZEL_13PT_BOLD = font },
}
Mouse = { GetPosition = function() return nil end }
local altDown = false
Keyboard = {
    IsAvailable = function() return true end,
    IsBlocked = function() return false end,
    IsAltDown = function() return altDown end,
}
local logicCallbacks = {}
Event = { Logic = {
    Subscribe = function(name, callback) logicCallbacks[name] = callback end,
    Unsubscribe = function(name) logicCallbacks[name] = nil end,
} }

local function setAlt(value)
    altDown = value
    for _, callback in pairs(logicCallbacks) do callback() end
end

local function fire(target, hook, ...)
    local callback = assert(target.subscriptions[hook], "missing drag hook " .. tostring(hook))
    return callback(target, ...)
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
    expect(root.clickthrough, true, "feedback must not intercept pointer input")
    for _, child in ipairs(root.children) do expectClickthrough(child) end
end

local function expectNativeFrame(root, family, message)
    local seenFamily
    local function visit(component)
        if component.kind == "sprite" then
            local actual = component.spriteID:match("^(RS3_FEEDBACK_%u+_FRAME)_%d+$")
            expect(actual, family, message)
            seenFamily = actual
        end
        for _, child in ipairs(component.children) do visit(child) end
    end
    visit(root)
    expect(seenFamily, family, message .. " has visible native frame artwork")
end

local function siblingIndex(root)
    for index, child in ipairs(root.parent.children) do
        if child == root then return index end
    end
    error("feedback is missing from its parent")
end

local function startDrag(owner, root, target)
    local initial = rect(root)
    fire(target, ui.Hook.ONCLICK, 12, 9)
    expect(owner.dragFeedback, nil, "press alone does not display drag borders")
    fire(target, ui.Hook.ONHOLD, 12, 9)
    local feedback = assert(owner.dragFeedback, "holding displays drag borders")
    local origin, active = feedback.origin, feedback.active
    expect(origin.parent, root.parent, "origin uses the moving surface's parent")
    expect(active.parent, root.parent, "active border uses the moving surface's parent")
    expectRect(origin, initial, "origin outlines the pre-drag rectangle")
    expectRect(active, initial, "active border initially outlines the surface")
    expect(origin.hidden, false, "origin border is visible")
    expect(active.hidden, false, "active border is visible")
    expectClickthrough(origin)
    expectClickthrough(active)
    expectNativeFrame(origin, "RS3_FEEDBACK_POSITION_FRAME", "origin uses native white artwork")
    expectNativeFrame(active, "RS3_FEEDBACK_FINAL_FRAME", "active uses native gold artwork")

    -- Hook coordinates retain the capture origin when the drag target expands.
    fire(target, ui.Hook.ONHOLD, 49, 32)
    expectRect(root, {
        x = initial.x + 37, y = initial.y + 23,
        width = initial.width, height = initial.height,
    }, "drag moves the surface")
    expectRect(origin, initial, "origin remains at the pre-drag rectangle")
    expectRect(active, rect(root), "active border follows the moved surface")
    expect(siblingIndex(active) > siblingIndex(root), true, "active border draws above the surface")

    fire(target, ui.Hook.ONHOLD, 12, 9)
    expectRect(root, {
        x = initial.x, y = initial.y,
        width = initial.width, height = initial.height,
    }, "drag can reverse direction")
    expectRect(origin, initial, "origin remains stationary after reversing")
    expectRect(active, rect(root), "active border follows reversed movement")
    return { origin = origin, active = active }
end

local function expectRemoved(owner, feedback, message)
    expect(owner.dragFeedback, nil, message .. " releases feedback")
    expect(feedback.origin.destroyed, true, message .. " removes the white origin")
    expect(feedback.active.destroyed, true, message .. " removes the gold active border")
end

local function simpleClick(owner, root, target)
    local initial = rect(root)
    local children = #root.parent.children
    fire(target, ui.Hook.ONCLICK, 12, 9)
    expect(owner.dragFeedback, nil, "click does not create feedback")
    fire(target, ui.Hook.ONRELEASE, 12, 9)
    expect(owner.dragFeedback, nil, "click release leaves no feedback")
    expect(#root.parent.children, children, "click leaves no extra native layers")
    expectRect(root, initial, "click does not move the surface")
end

local Window = require("src/window")
local Panel = require("src/panel")
local parent = component(nil, "parent")
parent:SetSize(1000, 700)
local overlayParent = component(nil, "overlayParent")
overlayParent:SetSize(1200, 800)

local window = Window.new(parent, {
    title = "Drag feedback", x = 74, y = 53, width = 340, height = 230,
})
simpleClick(window, window.root, window.titleDrag)
for _, hook in ipairs({ ui.Hook.ONRELEASE, ui.Hook.ONDRAGCOMPLETE }) do
    local feedback = startDrag(window, window.root, window.titleDrag)
    fire(window.titleDrag, hook)
    expectRemoved(window, feedback, "window release/completion")
    local stopped = rect(window.root)
    fire(window.titleDrag, ui.Hook.ONHOLD, 100, 100)
    expectRect(window.root, stopped, "released window ignores further hold events")
    expect(window.dragFeedback, nil, "released window cannot restart without a press")
end
local feedback = startDrag(window, window.root, window.titleDrag)
window:Close()
expectRemoved(window, feedback, "window Close")
expect(window.root.hidden, true, "Close hides the moved window")
window:Show()
feedback = startDrag(window, window.root, window.titleDrag)
window:Destroy()
expectRemoved(window, feedback, "window Destroy")

local closingWindow = Window.new(parent, { title = "Destroy on close", destroyOnClose = true })
feedback = startDrag(closingWindow, closingWindow.root, closingWindow.titleDrag)
closingWindow:Close()
expectRemoved(closingWindow, feedback, "destroy-on-close window")
expect(closingWindow.root, nil, "destroy-on-close releases the moving surface")

local panel = Panel.new(parent, { x = 45, y = 68, width = 270, height = 150 })
setAlt(true)
simpleClick(panel, panel.dock.root, panel.dockDragLayer)
for _, hook in ipairs({ ui.Hook.ONRELEASE, ui.Hook.ONDRAGCOMPLETE }) do
    feedback = startDrag(panel, panel.dock.root, panel.dockDragLayer)
    fire(panel.dockDragLayer, hook)
    expectRemoved(panel, feedback, "standalone panel release/completion")
end
feedback = startDrag(panel, panel.dock.root, panel.dockDragLayer)
setAlt(false)
expectRemoved(panel, feedback, "Alt loss without further pointer events")
expect(panel.dockDragLayer.hidden, true, "Alt loss hides the drag input layer")
setAlt(true)
feedback = startDrag(panel, panel.dock.root, panel.dockDragLayer)
altDown = false
fire(panel.dockDragLayer, ui.Hook.ONHOLD, 80, 40)
expectRemoved(panel, feedback, "Alt loss during a hold")
setAlt(false)
setAlt(true)
feedback = startDrag(panel, panel.dock.root, panel.dockDragLayer)
panel:Destroy()
expectRemoved(panel, feedback, "standalone panel Destroy")

local popout = Panel.new(parent, {
    x = 31, y = 48, width = 260, height = 145, popout = true,
    overlayParent = overlayParent, popoutX = 130, popoutY = 95,
    popoutWidth = 310, popoutHeight = 180, popoutClickthrough = true,
})
feedback = startDrag(popout, popout.dock.root, popout.dockDragLayer)
popout:SetPoppedOut(true)
expectRemoved(popout, feedback, "switching from dock to popout")
simpleClick(popout, popout.overlay.root, popout.overlayDragLayer)
for _, hook in ipairs({ ui.Hook.ONRELEASE, ui.Hook.ONDRAGCOMPLETE }) do
    feedback = startDrag(popout, popout.overlay.root, popout.overlayDragLayer)
    fire(popout.overlayDragLayer, hook)
    expectRemoved(popout, feedback, "popout release/completion")
end
feedback = startDrag(popout, popout.overlay.root, popout.overlayDragLayer)
setAlt(false)
expectRemoved(popout, feedback, "popout Alt loss")
setAlt(true)
feedback = startDrag(popout, popout.overlay.root, popout.overlayDragLayer)
popout:SetPoppedOut(false)
expectRemoved(popout, feedback, "switching from popout to dock")
popout:SetPoppedOut(true)
feedback = startDrag(popout, popout.overlay.root, popout.overlayDragLayer)
popout:Destroy()
expectRemoved(popout, feedback, "popout Destroy")
expect(next(logicCallbacks), nil, "destroyed panels leave no Alt polling subscription")

local function exerciseBounds(owner, root, target, bounds)
    local initial = rect(root)
    local parentWidth, parentHeight = bounds.width, bounds.height
    fire(target, ui.Hook.ONCLICK, 12, 9)
    fire(target, ui.Hook.ONHOLD, 12, 9)
    local feedback = owner.dragFeedback
    local function move(x, y, expectedX, expectedY)
        fire(target, ui.Hook.ONHOLD, x, y)
        expect(root.x, expectedX, "horizontal movement stays inside the containing area")
        expect(root.y, expectedY, "vertical movement stays inside the containing area")
        expectRect(feedback.active, rect(root), "gold frame follows the clamped surface")
        expectRect(feedback.origin, initial, "clamping preserves the original reference")
    end
    local maxX, maxY = parentWidth - root.width, parentHeight - root.height
    move(-10000, -10000, 0, 0)
    move(10000, -10000, maxX, 0)
    move(-10000, 10000, 0, maxY)
    move(10000, 10000, maxX, maxY)
    move(12, 9, initial.x, initial.y)

    -- Bounds are re-read during the drag, with oversized axes pinned to zero.
    bounds:SetSize(root.width - 20, root.height + 40)
    move(10000, 10000, 0, 40)
    bounds:SetSize(root.width + 50, root.height - 20)
    move(10000, 10000, 50, 0)
    bounds:SetSize(root.width, root.height)
    move(-10000, 10000, 0, 0)
    bounds:SetSize(parentWidth, parentHeight)
    fire(target, ui.Hook.ONRELEASE)
    owner:Destroy()
end

local boundedWindow = Window.new(parent, {
    title = "Bounded window", x = -170, y = -115,
    xAnchor = 0.5, yAnchor = 0.5, width = 340, height = 230,
})
exerciseBounds(boundedWindow, boundedWindow.root, boundedWindow.titleDrag, parent)

local boundedPanel = Panel.new(parent, { x = 40, y = 60, width = 270, height = 150 })
setAlt(true)
exerciseBounds(boundedPanel, boundedPanel.root, boundedPanel.dockDragLayer, parent)

local boundedPopout = Panel.new(parent, {
    popout = true, poppedOut = true, overlayParent = overlayParent,
    popoutX = 100, popoutY = 80, popoutWidth = 310, popoutHeight = 180,
}, true)
exerciseBounds(boundedPopout, boundedPopout.overlay.root, boundedPopout.overlayDragLayer, overlayParent)

-- Relative placement is measured across the available travel, not screen pixels.
local area = component(nil, "resizing-parent")
area:SetSize(1000, 700)
local centered = Window.new(area, {
    title = "Centered", x = -150, y = -100, xAnchor = 0.5, yAnchor = 0.5,
    width = 300, height = 200,
})
local edged = Window.new(area, { title = "Edge", x = 700, y = 500, width = 300, height = 200 })
edged:Close()
local corner = Panel.new(area, { x = 0, y = 0, width = 250, height = 150 })
local fractional = Panel.new(parent, {
    popout = true, overlayParent = area, popoutX = 170, popoutY = 390,
    popoutWidth = 320, popoutHeight = 180,
}, true)
local dockPosition = rect(fractional.dock.root)
setAlt(false)
local otherResizeCalls = 0
area:Subscribe(ui.Hook.ONRESIZE, "consumer", function() otherResizeCalls = otherResizeCalls + 1 end)
local function expectRelativePlacement()
    expect(centered.root.x, math.floor((area.width - 300) / 2 + 0.5), "window stays horizontally centered")
    expect(centered.root.y, math.floor((area.height - 200) / 2 + 0.5), "window stays vertically centered")
    expect(centered.titleDrag.x, centered.root.x, "title handle follows relative placement")
    expect(centered.titleDrag.y, centered.root.y, "title handle stays aligned vertically")
    expect(edged.root.x, area.width - 300, "right edge remains attached")
    expect(edged.root.y, area.height - 200, "bottom edge remains attached")
    expect(corner.root.x, 0, "left edge remains attached")
    expect(corner.root.y, 0, "top edge remains attached")
    expect(fractional.overlay.root.x, math.floor((area.width - 320) / 4 + 0.5), "popout retains quarter-width placement")
    expect(fractional.overlay.root.y, math.floor((area.height - 180) * 0.75 + 0.5), "popout retains three-quarter-height placement")
    expectRect(fractional.dock.root, dockPosition, "flow-managed dock is not repositioned")
end
area:SetSize(1400, 900)
expectRelativePlacement()
area:SetSize(500, 350)
expectRelativePlacement()
expect(edged.root.hidden, true, "relative resize does not reveal closed windows")
expect(fractional.overlay.root.hidden, true, "relative resize does not reveal docked popouts")
expect(corner.dockDragLayer.hidden, true, "resize does not enable Alt input")
expect(centered.dragFeedback, nil, "idle resize does not start drag feedback")

-- Rounding, exact-fit and temporarily undersized viewports must not lose intent.
for _ = 1, 10 do
    area:SetSize(503, 353)
    expectRelativePlacement()
    area:SetSize(1000, 700)
    expectRelativePlacement()
end
for _, size in ipairs({ {300, 200}, {100, 80}, {0, 0} }) do
    area:SetSize(size[1], size[2])
    expect(centered.root.x, 0, "centered window clamps when no horizontal travel remains")
    expect(centered.root.y, 0, "centered window clamps when no vertical travel remains")
    expect(edged.root.x, 0, "edge window clamps in undersized viewport")
    expect(edged.root.width, 300, "containment does not resize the surface")
end
area:SetSize(1000, 700)
expectRelativePlacement()
edged:Show()
fractional:SetPoppedOut(true)
expect(edged.titleDrag.x, 700, "reopened window's handle follows its retained edge")
expect(fractional.overlayDragLayer.x, 170, "popout handle follows retained fractional position")

centered:Destroy()
local callsBeforeDestroy = otherResizeCalls
area:SetSize(500, 350)
expect(edged.root.x, 200, "surviving window retains edge after sibling destruction")
expect(otherResizeCalls, callsBeforeDestroy + 1, "sibling destruction preserves consumer listeners")
edged:Destroy()
corner:Destroy()
fractional:Destroy()
area:SetSize(1000, 700)

local function exerciseRelativeDrag(owner, root, target)
    setAlt(true)
    fire(target, ui.Hook.ONCLICK, 12, 9)
    fire(target, ui.Hook.ONHOLD, 12, 9)
    -- Move from center to a quarter of the available travel on both axes.
    fire(target, ui.Hook.ONHOLD, -163, -116)
    expect(root.x, 175, "drag establishes a new horizontal relative position")
    expect(root.y, 125, "drag establishes a new vertical relative position")
    local origin = rect(owner.dragFeedback.origin)
    area:SetSize(700, 500)
    expect(root.x, 100, "resize retains dragged quarter-width placement")
    expect(root.y, 75, "resize retains dragged quarter-height placement")
    expectRect(owner.dragFeedback.active, rect(root), "gold frame follows relative resize")
    expectRect(owner.dragFeedback.origin, origin, "white frame retains the drag origin")
    expect(target.x, 0, "relative resize preserves expanded capture")
    fire(target, ui.Hook.ONHOLD, -163, -116)
    expect(root.x, 100, "stationary pointer does not undo horizontal resize adjustment")
    expect(root.y, 75, "stationary pointer does not undo vertical resize adjustment")
    fire(target, ui.Hook.ONRELEASE)
    expect(target.x, 100, "release restores the corrected hit area")
    area:SetSize(1000, 700)
    expect(root.x, 175, "idle resize retains the most recent drag position")
    expect(root.y, 125, "idle resize retains the most recent vertical drag position")
    owner:Destroy()
end
local relativeWindow = Window.new(area, { title = "Drag", x = 350, y = 250, width = 300, height = 200 })
exerciseRelativeDrag(relativeWindow, relativeWindow.root, relativeWindow.titleDrag)
local relativePanel = Panel.new(area, { x = 350, y = 250, width = 300, height = 200 })
exerciseRelativeDrag(relativePanel, relativePanel.root, relativePanel.dockDragLayer)
local relativePopout = Panel.new(parent, {
    popout = true, poppedOut = true, overlayParent = area,
    popoutX = 350, popoutY = 250, popoutWidth = 300, popoutHeight = 200,
}, true)
exerciseRelativeDrag(relativePopout, relativePopout.overlay.root, relativePopout.overlayDragLayer)
local callsBeforeTeardown = otherResizeCalls
area:SetSize(400, 250)
expect(otherResizeCalls, callsBeforeTeardown + 1, "teardown leaves consumer resize listeners intact")

-- A popout can start outside the viewport before any drag or resize occurs.
local galleryArea = component(nil, "gallery-area")
galleryArea:SetSize(1000, 700)
local galleryWindow = Window.new(galleryArea, {
    title = "Gallery", x = -270, y = -200, xAnchor = 0.5, yAnchor = 0.5,
    width = 540, height = 400,
})
local galleryTabs = galleryWindow:AddTabs({ "UI" }, { height = 330 })
local galleryPanel = galleryTabs:GetPage(1):AddPanel({
    popout = true, width = 458, height = 154,
    popoutX = -764, popoutY = -90, popoutXAnchor = 0.5, popoutYAnchor = 0.5,
})
local dockX, dockY = galleryPanel.dock.root.x, galleryPanel.dock.root.y
galleryPanel:SetPoppedOut(true)
expect(galleryPanel.overlay.root.x, 0, "anchored gallery popout is contained on first reveal")
expect(galleryPanel.overlay.root.y, 260, "initial containment preserves the in-bounds axis")
expect(galleryPanel.overlayDragLayer.x, 0, "initial popout drag target follows the corrected frame")
expect(galleryPanel.dock.root.x, dockX, "popout containment does not move its flow-managed dock")
expect(galleryPanel.dock.root.y, dockY, "popout containment does not move its dock vertically")
galleryPanel:SetPoppedOut(false)
galleryPanel.overlay.root:SetPos(-30, 900)
galleryPanel:SetPoppedOut(true)
expect(galleryPanel.overlay.root.x, 0, "reopening clamps a repositioned hidden popout")
expect(galleryPanel.overlay.root.y, 546, "reopening clamps to the bottom edge")
galleryPanel:SetSize(600, 300)
expect(galleryPanel.overlay.root.y, 400, "growing a popout cannot extend its bottom outside the viewport")
expect(galleryPanel.overlayDragLayer.y, 400, "growing popout keeps the drag target aligned")
galleryWindow:Destroy()

local initiallyOutside = Panel.new(galleryArea, { x = 950, y = 680, width = 200, height = 100 })
expect(initiallyOutside.root.x, 800, "standalone panel starts within the right edge")
expect(initiallyOutside.root.y, 600, "standalone panel starts within the bottom edge")
initiallyOutside:SetSize(450, 300)
expect(initiallyOutside.root.x, 550, "growing standalone panel remains within the right edge")
expect(initiallyOutside.root.y, 400, "growing standalone panel remains within the bottom edge")
expect(initiallyOutside.dockDragLayer.x, 550, "standalone size correction keeps the drag target aligned")
initiallyOutside:Destroy()

-- Native geometry can settle after ONRESIZE, or without another notification.
-- Drive the gallery's real Window -> Tabs -> AddPanel path, then only logic ticks.
local liveArea = component(nil, "live-resize-area")
liveArea:SetSize(1000, 700)
local liveWindow = Window.new(liveArea, { title = "Live gallery", width = 540, height = 400 })
local liveTabs = liveWindow:AddTabs({ "UI" }, { height = 330 })
local livePanel = liveTabs:GetPage(1):AddPanel({
    popout = true, poppedOut = true, width = 300, height = 200,
    popoutX = -150, popoutY = -100, popoutXAnchor = 0.5, popoutYAnchor = 0.5,
})
expect(livePanel.overlayParent, liveArea, "nested gallery popout uses the game-area viewport")
setAlt(false)
local function tickPanels()
    for _, callback in pairs(logicCallbacks) do callback() end
end
liveArea:EmitResize()
liveArea.width, liveArea.height = 600, 400
tickPanels()
expect(livePanel.overlay.root.x, 150, "logic update contains popout after a late viewport width change")
expect(livePanel.overlay.root.y, 100, "logic update contains popout after a late viewport height change")
expect(livePanel.overlayDragLayer.x, 150, "late resize keeps the popout hit area aligned")
expect(livePanel.overlayDragLayer.hidden, true, "late resize does not require Alt")
expect(livePanel.dragFeedback, nil, "late resize does not require a drag")

-- A later child-layout pass must not undo a previously observed viewport resize.
livePanel.overlay.root:SetPos(650, 450)
tickPanels()
expect(livePanel.overlay.root.x, 150, "later child layout cannot leave the popout outside the viewport")
expect(livePanel.overlay.root.y, 100, "later child layout retains the vertical relative position")
livePanel:SetPoppedOut(false)
liveArea.width, liveArea.height = 1000, 700
tickPanels()
livePanel:SetPoppedOut(true)
expect(livePanel.overlay.root.x, 350, "hidden popout retains relative placement through unnotified growth")
expect(livePanel.overlay.root.y, 250, "hidden popout retains vertical placement through unnotified growth")

setAlt(true)
fire(livePanel.overlayDragLayer, ui.Hook.ONCLICK, 12, 9)
fire(livePanel.overlayDragLayer, ui.Hook.ONHOLD, 12, 9)
local liveOrigin = rect(livePanel.dragFeedback.origin)
liveArea.width, liveArea.height = 500, 350
tickPanels()
expect(livePanel.overlay.root.x, 100, "active drag responds to viewport shrink without a pointer event")
expect(livePanel.overlay.root.y, 75, "active drag responds to late vertical shrink")
expectRect(livePanel.dragFeedback.active, rect(livePanel.overlay.root), "late resize updates the gold frame")
expectRect(livePanel.dragFeedback.origin, liveOrigin, "late resize preserves the white reference")
fire(livePanel.overlayDragLayer, ui.Hook.ONHOLD, 12, 9)
expect(livePanel.overlay.root.x, 100, "stationary hold does not undo a polled resize")
expect(livePanel.overlay.root.y, 75, "stationary hold preserves the corrected vertical position")
fire(livePanel.overlayDragLayer, ui.Hook.ONRELEASE)
liveWindow:Destroy()
liveArea.width, liveArea.height = 400, 250
tickPanels()

-- Position callbacks report actual drag changes, not pointer noise or layout.
local function exercisePositionCallback(create, poppedOut)
    local events = {}
    local owner, root, target
    local destroyOnChange = false
    local function onPositionChange(component, x, y, overlay)
        expect(component, owner, "position callback receives the PrettyUI owner")
        expect(root.x, x, "callback observes the updated horizontal position")
        expect(root.y, y, "callback observes the updated vertical position")
        expect(owner.dragFeedback.active.x, x, "feedback updates before the callback")
        expect(owner.dragFeedback.active.y, y, "vertical feedback updates before the callback")
        expect(overlay, poppedOut, "callback identifies the moved panel surface")
        table.insert(events, { x = x, y = y })
        if destroyOnChange then owner:Destroy() end
    end
    local callbackArea = component(nil, "callback-area")
    callbackArea:SetSize(1000, 700)
    local cleanup
    owner, root, target, cleanup = create(callbackArea, onPositionChange)
    expect(#events, 0, "construction does not emit position changes")
    simpleClick(owner, root, target)
    expect(#events, 0, "click does not emit position changes")
    fire(target, ui.Hook.ONCLICK, 12, 9)
    fire(target, ui.Hook.ONHOLD, 12, 9)
    expect(#events, 0, "stationary hold does not emit position changes")
    fire(target, ui.Hook.ONHOLD, 49, 32)
    expect(#events, 1, "movement emits one position change")
    expect(events[1].x, 387, "callback reports resolved parent-relative x, not anchor offset")
    expect(events[1].y, 273, "callback reports resolved parent-relative y, not anchor offset")
    fire(target, ui.Hook.ONHOLD, 49, 32)
    expect(#events, 1, "repeated pointer position does not emit again")
    local moveHook = poppedOut == nil and ui.Hook.ONHOLD or ui.Hook.ONDRAG
    fire(target, moveHook, -10000, -10000)
    expect(#events, 2, "dragging to the boundary emits a position change")
    expect(events[2].x, 0, "callback reports clamped x")
    expect(events[2].y, 0, "callback reports clamped y")
    fire(target, moveHook, -9999, -9999)
    expect(#events, 2, "movement beyond the same boundary does not emit again")
    fire(target, ui.Hook.ONRELEASE)
    fire(target, ui.Hook.ONDRAGCOMPLETE)
    expect(#events, 2, "release and drag completion do not duplicate changes")
    callbackArea:SetSize(1200, 800)
    owner:SetSize(320, 220)
    expect(#events, 2, "automatic layout and size changes do not emit drag callbacks")
    destroyOnChange = true
    fire(target, ui.Hook.ONCLICK, 12, 9)
    fire(target, ui.Hook.ONHOLD, 12, 9)
    fire(target, ui.Hook.ONHOLD, 49, 32)
    expect(#events, 3, "a callback may destroy the moving component")
    expect(root.destroyed, true, "callback destruction releases the moving surface")
    expect(owner.dragFeedback, nil, "callback destruction releases drag feedback")
    if cleanup then cleanup() end
end

setAlt(true)
exercisePositionCallback(function(area, onPositionChange)
    local owner = Window.new(area, {
        title = "Position callback", x = -150, y = -100,
        xAnchor = 0.5, yAnchor = 0.5, width = 300, height = 200,
        onPositionChange = onPositionChange,
    })
    return owner, owner.root, owner.titleDrag
end, nil)
exercisePositionCallback(function(area, onPositionChange)
    local owner = Panel.new(area, {
        x = -150, y = -100, xAnchor = 0.5, yAnchor = 0.5,
        width = 300, height = 200, onPositionChange = onPositionChange,
    })
    return owner, owner.root, owner.dockDragLayer
end, false)
exercisePositionCallback(function(area, onPositionChange)
    local host = Window.new(area, { title = "Panel host" })
    local owner = host:AddPanel({
        popout = true, poppedOut = true, popoutClickthrough = true,
        popoutX = -150, popoutY = -100, popoutXAnchor = 0.5, popoutYAnchor = 0.5,
        width = 300, height = 200, onPositionChange = onPositionChange,
    })
    return owner, owner.overlay.root, owner.overlayDragLayer, function() host:Destroy() end
end, true)

local unloadWindow = Window.new(area, { title = "Unload" })
local unloadPanel = Panel.new(area, { popout = true })
Interfaces.unload()
unloadWindow:Destroy()
unloadPanel:Destroy()

print("drag_feedback_test: ok")
