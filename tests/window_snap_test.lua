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

local function component(parent, kind, categoryID, dynamicID)
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
    setmetatable(result, { __index = function(self, key)
        if key ~= "xyGlobal" then return nil end
        local origin = parent and parent.xyGlobal or { x = 0, y = 0 }
        return { x = origin.x + self.x, y = origin.y + self.y }
    end })
    if parent then table.insert(parent.children, result) end
    return Interfaces.component(result, parent, categoryID, dynamicID)
end

local function factory(kind)
    return { new = function(parent, categoryID, dynamicID)
        return component(parent, kind, categoryID, dynamicID)
    end }
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

id = {
    Sprite = setmetatable({}, { __index = function(_, name) return name end }),
    Font = { MUSEO_SANS_15PT_REGULAR = 1, CINZEL_13PT_BOLD = 2 },
    Component = { TOPLEVEL_V2__GAME_AREA = (1477 << 16) | 61 },
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
Keyboard = {
    IsAvailable = function() return true end,
    IsBlocked = function() return false end,
    IsAltDown = function() return false end,
}
Event = { Logic = { Subscribe = function() end, Unsubscribe = function() end } }

local minimap = { xyGlobal = { x = 700, y = 40 }, width = 200, height = 150, visibleGlobal = true }
local closedWindow = { xyGlobal = { x = 300, y = 300 }, width = 200, height = 150, visibleGlobal = false }
local layoutLayer = { children = { minimap, closedWindow } }
function layoutLayer:IterateStaticComponents(callback)
    for _, child in ipairs(self.children) do callback(child) end
end
local layoutLayerFails = false
ui.Interfaces = {
    GetComponent = function(_, packed)
        if packed ~= id.Component.TOPLEVEL_V2__GAME_AREA then return nil end
        if layoutLayerFails then error("layout layer unavailable") end
        return layoutLayer
    end,
}

local function fire(target, hook, ...)
    local callback = assert(target.subscriptions[hook], "missing drag hook " .. tostring(hook))
    return callback(target, ...)
end

local function dragBy(window, dx, dy)
    fire(window.titleDrag, ui.Hook.ONCLICK, 12, 9)
    fire(window.titleDrag, ui.Hook.ONHOLD, 12, 9)
    fire(window.titleDrag, ui.Hook.ONHOLD, 12 + dx, 9 + dy)
    fire(window.titleDrag, ui.Hook.ONRELEASE, 12 + dx, 9 + dy)
end

local function expectAt(window, x, y, message)
    expect(window.root.x, x, message .. " x")
    expect(window.root.y, y, message .. " y")
end

local Window = require("src/window")
local parent = component(nil, "parent")
parent:SetSize(1000, 700)

local snapping = Window.new(parent, { title = "Snapping", x = 100, y = 300, width = 300, height = 200 })
local still = Window.new(parent, {
    title = "Not snapping", x = 600, y = 300, width = 300, height = 200, snapToEdges = false,
})
expect(snapping.snapToEdges, true, "snapToEdges is on by default")
expect(still.snapToEdges, false, "snapToEdges = false turns snapping off")

dragBy(snapping, 199, 0)
expectAt(snapping, 304, 300, "a window dropped 5 units short of an opted-out window still snaps beside it")

snapping.root:SetPos(100, 300)
dragBy(still, -199, 0)
expectAt(still, 401, 300, "a window with snapToEdges = false doesn't snap")

still.root:SetPos(600, 300)
snapping.root:SetPos(100, 40)
dragBy(snapping, 297, 0)
expectAt(snapping, 402, 40, "a window snaps beside a shown game window, its title bar flush with its top")

snapping.root:SetPos(100, 300)
layoutLayerFails = true
dragBy(snapping, 199, 0)
expectAt(snapping, 299, 300, "if gathering targets fails, the window drags without snapping")
layoutLayerFails = false

still:Destroy()
snapping.root:SetPos(100, 300)
dragBy(snapping, 199, 0)
expectAt(snapping, 299, 300, "a destroyed window is no longer a target")

local replacement = Window.new(parent, { title = "Replacement", x = 600, y = 300, width = 300, height = 200 })
snapping.root:SetPos(100, 300)
dragBy(snapping, 199, 0)
expectAt(snapping, 304, 300, "snapping to the remaining windows still works after one is destroyed")

-- Stacked windows meet border to border: a title bar's top has no strip, so a titled window below
-- another sits 2 units lower, and one above a titled window 2 units higher, than with a strip there.
snapping.root:SetPos(600, 100)
dragBy(snapping, 0, 393)
expectAt(snapping, 600, 498, "a window dropped below another meets its bottom border with its title bar")
snapping.root:SetPos(600, 50)
dragBy(snapping, 0, 55)
expectAt(snapping, 600, 102, "a window dropped above a titled window meets its title bar with its bottom border")
replacement:Destroy()
local untitledTarget = Window.new(parent, { x = 600, y = 300, width = 300, height = 200 })
snapping.root:SetPos(600, 50)
dragBy(snapping, 0, 55)
expectAt(snapping, 600, 104, "a window dropped above an untitled window meets its top border")
snapping.root:SetPos(600, 100)
dragBy(snapping, 0, 393)
expectAt(snapping, 600, 498, "a window dropped below an untitled window meets its bottom border")
untitledTarget:Destroy()

-- The window's box hangs 2 units past the parent's edges but its title bar's top, so its visible
-- border sits flush.
snapping.root:SetPos(100, 300)
dragBy(snapping, -94, 0)
expectAt(snapping, -2, 300, "a window dropped near the parent's left edge snaps flush with it")
dragBy(snapping, -10000, -10000)
expectAt(snapping, -2, 0, "a window dragged past the parent's corner stops with its border flush")
dragBy(snapping, 10000, 10000)
expectAt(snapping, 702, 502, "a window dragged past the far corner stops with its border flush")
snapping:Destroy()
print("window_snap_test: ok")
