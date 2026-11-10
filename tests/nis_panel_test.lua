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

local function component(parent, kind, categoryID, dynamicID)
    local result = {
        parent = parent, kind = kind, children = {}, subscriptions = {}, namedSubscriptions = {},
        x = 0, y = 0, width = 0, height = 0, hidden = false,
        opConfig = { ClearOpCursors = function() end, SetOpCursor = function() end },
        cursorConfig = {},
        dragConfig = {},
        resizeOrder = {},
    }
    local position, size = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
    function result:SetPos(x, y, xAnchor, yAnchor)
        assert(not self.destroyed, "positioning destroyed component")
        position = { x, y, xAnchor or 0, yAnchor or 0 }
        self.x = x + ((parent and parent.width or 0) * position[3])
        self.y = y + ((parent and parent.height or 0) * position[4])
    end
    function result:EmitResize()
        for _, key in ipairs(self.resizeOrder) do
            local callback = (self.namedSubscriptions[ui.Hook.ONRESIZE] or {})[key]
            if callback then callback(self) end
        end
    end
    function result:Relayout()
        self:SetPos(table.unpack(position))
        self.width = size[1] + ((parent and parent.width or 0) * size[3])
        self.height = size[2] + ((parent and parent.height or 0) * size[4])
        for _, child in ipairs(self.children) do child:Relayout() end
        self:EmitResize()
    end
    function result:SetSize(width, height, widthAnchor, heightAnchor)
        size = { width, height, widthAnchor or 0, heightAnchor or 0 }
        self:Relayout()
    end
    function result:SetWidth(width, anchor)
        self:SetSize(width, size[2], anchor or 0, size[4])
    end
    function result:SetHeight(height, anchor)
        self:SetSize(size[1], height, size[3], anchor or 0)
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
            if hook == ui.Hook.ONRESIZE and self.namedSubscriptions[hook][name] == nil then
                self.resizeOrder[#self.resizeOrder + 1] = name
            end
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
        end
    end
    function result:MoveToFront()
        if not parent then return end
        removeChild(parent, self)
        parent.children[#parent.children + 1] = self
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
    if parent then parent.children[#parent.children + 1] = result end
    return Interfaces.component(result, parent, categoryID, dynamicID)
end

local function factory(kind)
    return { new = function(parent, categoryID, dynamicID)
        return component(parent, kind, categoryID, dynamicID)
    end }
end

ui = {
    Layer = factory("layer"), Sprite = factory("sprite"), Rectangle = factory("rectangle"),
    Text = factory("text"),
    Hook = {
        ONCLICK = 1, ONHOLD = 2, ONDRAG = 3, ONRELEASE = 4,
        ONDRAGCOMPLETE = 5, ONSCROLLWHEEL = 6, ONMOUSEOVER = 7,
        ONMOUSELEAVE = 8, ONMOUSEREPEAT = 9, ONRESIZE = 10,
    },
    AlignMode = { TOPLEFT = 1, CENTRE = 2 },
    DragRenderBehaviour = { INVISIBLE = 0 },
}
local nextSpriteID = 10000
id = {
    Sprite = setmetatable({}, { __index = function(sprites, key)
        nextSpriteID = nextSpriteID + 1
        rawset(sprites, key, nextSpriteID)
        return nextSpriteID
    end }),
    Font = { MUSEO_SANS_15PT_REGULAR = 1, CINZEL_13PT_BOLD = 2 },
    VarPlayer = { TOPLEVEL_V2_SKINS_VARP = 12, TOPLEVEL_V2_TRANSPARENCY = -13 },
    Component = {
        TOPLEVEL_V2__GAME_AREA = (1477 << 16) | 61,
        TOPLEVEL_V2__PLUGIN_BUILD_LAYER_BOTTOM = (1477 << 16) | 62,
    },
}
local font = {
    baseline = 18,
    GetStringLineCount = function() return 1 end,
    GetStringWidth = function(_, text) return #text * 7 end,
    GetStringHeightAndLineCount = function() return 18 end,
}
config = {
    Cursor = {
        TOPLEVEL_V2_MOVE = 194,
        TOPLEVEL_V2_SCALE_VERT = 195, TOPLEVEL_V2_SCALE_HORZ = 196,
        TOPLEVEL_V2_SCALE_DIAG_1 = 197, TOPLEVEL_V2_SCALE_DIAG_2 = 198,
    },
    Font = { MUSEO_SANS_15PT_REGULAR = font, CINZEL_13PT_BOLD = font },
}
Mouse = { GetPosition = function() return nil end }
Keyboard = {
    IsAvailable = function() return true end,
    IsBlocked = function() return false end,
    IsAltDown = function() return false end,
}
game = { options = { InterfaceScale = { setting = 100 } } }
GameKey = { ESCAPE = 27 }
local events = {}
local function event(name)
    events[name] = {}
    return {
        Subscribe = function(key, callback) events[name][key] = callback end,
        Unsubscribe = function(key) events[name][key] = nil end,
    }
end
Event = {
    Logic = event("Logic"), VarTransmit = event("VarTransmit"),
    KeyDown = event("KeyDown"), WindowFocusChanged = event("WindowFocusChanged"),
}
local locked, transparency = true, 0
var = { VarPlayer = {
    TOPLEVEL_V2_CUSTOMIZATION_LOCK = setmetatable({}, {
        __index = function() return locked and 1 or 0 end,
    }),
    TOPLEVEL_V2_TRANSPARENCY = setmetatable({
        isVarBit = true, baseVar = { id = 12 }, varBitMask = 0xFF00,
    }, {
        __index = function(_, key)
            if key == "value" then return transparency end
        end,
    }),
} }
local function transmit(varID)
    for _, callback in pairs(events.VarTransmit) do callback({ var = { id = varID } }) end
end
local function fire(target, hook, ...)
    return assert(target.subscriptions[hook], "missing hook " .. tostring(hook))(target, ...)
end

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

local NisPanel = require("src/nis_panel")
local parent = component(nil, "parent")
parent:SetSize(1000, 700)
local closed = 0
local panel = NisPanel.new(parent, {
    categoryID = "auto", x = 100, y = 70, width = 300, height = 200,
    rowBackgroundColours = { 0x24211EFF, 0x2E2825FF },
    rowBackgroundEdgeToEdge = true,
    onClose = function() closed = closed + 1 end,
})
expect(panel.surface.background.alpha, 1, "native full opacity has no caller-imposed cap")
expect(panel.locked, true, "known locked state starts without editing chrome")
expect(panel.headerLeft.hidden, true, "locked header hidden")
expect(panel.closeButton.enabled, false, "locked close disabled")
expect(panel.dragLayer.enabled, false, "locked drag hit region disabled")
expect(panel.surface.container.y, 4, "locked content begins below ordinary border")
expect(panel.surface.container.height, 192, "locked content has four-unit bottom inset")
expect(panel.surface.background.y, 4, "locked body starts below ordinary top border")
expect(panel.resize.handles.e.enabled, false, "locked panel has no resize input")

locked = false
transmit(12)
expect(panel.locked, false, "native unlock updates panel")
expect(panel.root.x, 100, "unlock keeps outer x")
expect(panel.root.height, 200, "unlock keeps outer dimensions")
expect(panel.surface.container.y, 16, "unlocked content clears header and top border")
expect(panel.surface.container.height, 180, "unlocked viewport reserves the body frame")
expect(panel.closeButton.hidden, false, "unlocked close is visible")
expect(panel.dragLayer.enabled, true, "unlocked drag hit region enabled")
expect(panel.dragLayer.width, 288, "drag hit region excludes close")
expect(panel.surface.background.y, 16, "background does not overlap unlocked header or top border")
expect(panel.surface.background.height, 180, "background ends inside unchanged bottom border")
expect(panel.surface.top.y, 12, "body top border is visible below the header")
expect(panel.surface.topLeft.y, 12, "body corner connects below the header")
expect(panel.surface.left.y, 16, "side frame begins below the body corner")
expect(hitAt(parent, 250, 76), panel.dragLayer, "unlocked header wins native sibling hit testing")
local pressed = hitAt(parent, 250, 76)
fire(pressed, ui.Hook.ONCLICK, 150, 6)
fire(pressed, ui.Hook.ONHOLD, 180, 26)
fire(pressed, ui.Hook.ONRELEASE)
expect(panel.root.x, 130, "hit-tested header drag commits horizontal motion without Alt")
expect(panel.root.y, 90, "hit-tested header drag preserves first movement")
panel:_ApplyRect(100, 70, 300, 200)
expect(hitAt(parent, 394, 76), panel.closeButton, "raising header capture keeps close clickable")

fire(panel.closeButton, ui.Hook.ONMOUSEOVER)
expect(panel.closeSprite.spriteID, id.Sprite.RS3_CHILD_COMPACT_CLOSE_BUTTON_OVER,
    "close hover uses alternate sprite")
fire(panel.closeButton, ui.Hook.ONMOUSELEAVE)
expect(panel.closeSprite.spriteID, id.Sprite.RS3_CHILD_COMPACT_CLOSE_BUTTON,
    "close leave restores sprite")
panel:AddTitle("NisPanel QA")
for index = 1, 16 do panel:AddText("Row " .. index) end
expect(panel.contentHeight > panel.surface.container.height, true, "content overflows")
expect(panel.scrollbarVisible, true, "scrollbar appears when content overflows")
panel:RefreshRowBackgrounds()
expect(panel.rowBackgrounds[1].y, 0, "edge-to-edge rows cover viewport top")
local firstBackground = panel.rowBackgrounds[1]
panel:RefreshRowBackgrounds()
expect(firstBackground.destroyed, true, "refresh destroys replaced backdrops")

panel:SetSize(32, 8)
expect(panel.root.width, 64, "body obeys chrome floor")
expect(panel.root.height, 21, "height floor reserves header, both borders, and content")
expect(panel.headerFill.hidden, true, "zero-width centre fill hidden")
expect(panel.headerTop.hidden, true, "zero-width centre top hidden")
expect(panel.surface.container.height, 1, "minimum height keeps one unit for content")
expect(panel._scroll.root.width, 56, "scroll root follows fitted container")
panel:_ApplyRect(400, 200, 80, 40)
expect(panel.root.x, 400, "fitted origin applies")
expect(panel._scroll.root.height, 20, "fitted height refreshes content viewport")
expect(panel.dragLayer.x, 400, "idle drag hit region follows fitted origin")
expect(panel.dragLayer.width, 68, "idle hit region follows fitted width")
expect(panel.scrollbarVisible, true, "narrow surface retains scrolling")
local thumb = panel._scroll.thumbDrag
expect(thumb.hidden, false, "overflow capture is visible")
panel:Hide()
expect(panel.root.hidden, true, "hide suppresses body")
expect(panel.dragLayer.hidden, true, "hide removes sibling input hit")
expect(thumb.hidden, true, "hide removes overlay capture")
panel:Show()
expect(panel.dragLayer.hidden, false, "show restores unlocked drag region")
expect(thumb.hidden, false, "show restores scrollbar capture")
fire(panel.closeButton, ui.Hook.ONCLICK)
expect(closed, 1, "close runs onClose callback")
expect(panel.root.hidden, true, "close hides by default")
expect(panel.root.destroyed == true, false, "default close retains panel")
panel:Show()
locked = true
transmit(12)
expect(panel.surface.container.y, 4, "relocking restores ordinary inset")
expect(panel.dragLayer.enabled, false, "relocking disables hit")
expect(panel.root.x, 400, "relocking preserves outer geometry")
expect(panel.surface.background.y, 4, "relocking expands background below normal border")
expect(panel.surface.top.y, 0, "locking returns the body top border to the outer top")
transparency = 128
transmit(12)
expect(panel.surface.background.alpha, 1 - 128 / 255,
    "transparency base-variable event updates the actual NisPanel background")
expect(panel.headerFill.alpha, 1 - 128 / 255, "native transparency fades header artwork")
expect(panel.surface.top.alpha, 1 - 128 / 255, "native transparency fades the body frame")
expect(panel.root.alpha or 1, 1, "native transparency does not fade the content host")
expect(panel.closeSprite.alpha or 1, 1, "native transparency leaves close control usable")
transparency = 0
transmit(12)
expect(panel.surface.background.alpha, 1, "native opacity changes remain live without opt-in")
expect(panel.headerFill.alpha, 1, "native full opacity restores header artwork")
expect(panel.surface.bottom.alpha, 1, "native full opacity restores border artwork")

panel:Destroy()
expect(panel.root, nil, "destroy clears root")
expect(panel.dragLayer, nil, "destroy clears sibling capture")
expect(panel._scroll, nil, "destroy clears scroll controller")
expect(next(panel.overlays), nil, "destroy releases overlay registry")
expect(next(events.VarTransmit), nil, "destroy unwatches native settings")

local capped = NisPanel.new(parent, {
    width = 400.9, height = 200.5, minWidth = 100.9, minHeight = 32.9,
    maxWidth = 20.9, maxHeight = 4.9, destroyOnClose = true,
})
expect(capped.minWidth, 100, "minimum width floors to units")
expect(capped.maxWidth, 100, "maximum width normalizes to minimum")
expect(capped.maxHeight, 32, "maximum height normalizes to minimum")
expect(capped.root.width, 100, "constructor dimensions honor normalized maximum")
capped:Close()
expect(capped.root, nil, "destroy-on-close releases host")

local function expectRect(root, x, y, width, height, message)
    expect(root.x, x, message .. " x")
    expect(root.y, y, message .. " y")
    expect(root.width, width, message .. " width")
    expect(root.height, height, message .. " height")
end

locked = false
local obstacles = {
    { x = 0, y = 300, width = 400, height = 400 },
    { x = 520, y = 300, width = 480, height = 400 },
}
local enumerationFails = false
local nativeLayer = {}
function nativeLayer:IterateStaticComponents(callback)
    if enumerationFails then error("native enumeration failed") end
    local origin = parent.xyGlobal
    for index, rect in ipairs(obstacles) do
        callback({
            interfaceID = rect.interfaceID or 1477, staticID = rect.staticID or (100 + index),
            xyGlobal = { x = rect.x + origin.x, y = rect.y + origin.y },
            width = rect.width, height = rect.height, visibleGlobal = true,
        })
    end
end
local getComponent = ui.Interfaces.GetComponent
function ui.Interfaces:GetComponent(packed, ...)
    if packed == id.Component.TOPLEVEL_V2__GAME_AREA then return nativeLayer end
    return getComponent(self, packed, ...)
end
local function emit(name, payload)
    for _, callback in pairs(events[name]) do callback(payload or {}) end
end
local function makePanel()
    return NisPanel.new(parent, {
        categoryID = "auto", x = 100, y = 100, width = 300, height = 200,
    })
end
local function begin(owner)
    fire(owner.dragLayer, ui.Hook.ONCLICK, owner.root.width / 2, 6)
end
local function move(owner, x, y)
    fire(owner.dragLayer, ui.Hook.ONDRAG, x - owner.dragLayer.x, y - owner.dragLayer.y)
end
local function release(owner)
    fire(owner.dragLayer, ui.Hook.ONRELEASE)
end
local function expectNoDrag(owner, message)
    expect(owner.dragState, nil, message .. " ends capture")
    expect(owner.dragFeedback, nil, message .. " removes outlines")
    expect(events.Logic.prettyui_nis_panel_drag, nil, message .. " unsubscribes sampling")
end
local moving = makePanel()
-- Alt remains up throughout: only the unlocked header starts placement.
expect(Keyboard.IsAltDown(), false, "header dragging requires no modifier key")
begin(moving)
fire(moving.dragLayer, ui.Hook.ONHOLD, 150, 6)
release(moving)
expectRect(moving.root, 100, 100, 300, 200, "stationary header click never fits")
begin(moving)
move(moving, 460, 450)
expectRect(moving.dragFeedback.origin, 100, 100, 300, 200, "white source stays fixed")
expectRect(moving.dragFeedback.active, 400, 300, 120, 400, "orange fills native corridor and matches neighbor height")
expectRect(moving.root, 310, 444, 300, 200, "body follows its pointer grip without adopting orange's snapped position or size")
local white, orange = moving.dragFeedback.origin, moving.dragFeedback.active
release(moving)
expectRect(moving.root, 400, 300, 120, 400, "release commits exact filled orange")
expect(white.destroyed, true, "release destroys white")
expect(orange.destroyed, true, "release destroys orange")
fire(moving.dragLayer, ui.Hook.ONDRAGCOMPLETE)
expectRect(moving.root, 400, 300, 120, 400, "duplicate completion cannot recommit")
begin(moving)
move(moving, 460, 100)
release(moving)
expectRect(moving.root, 400, 94, 120, 400, "leaving a gap retains committed dimensions")

-- A blocked pointer moves orange to free space, not the freely dragged body.
begin(moving)
move(moving, 200, 450)
expectRect(moving.dragFeedback.active, 400, 300, 120, 400, "blocked pointer finds and fills nearest gap")
obstacles[2].x, obstacles[2].width = 500, 500
emit("Logic")
expectRect(moving.dragFeedback.active, 400, 300, 100, 400, "logic refreshes the narrowed native gap")
expectRect(moving.root, 140, 444, 120, 400, "changing the fitted destination cannot move or resize the held body")
obstacles[2].x, obstacles[2].width = 480, 520
release(moving)
expectRect(moving.root, 400, 300, 80, 400, "release revalidates changed native geometry")
obstacles = { { x = 0, y = 0, width = 1000, height = 700 } }
begin(moving)
move(moving, 700, 200)
expect(moving.dragFeedback.active.hidden, true, "no destination hides orange")
expectRect(moving.root, 660, 194, 80, 400, "without a valid destination the body still follows the cursor until release")
release(moving)
expectRect(moving.root, 400, 300, 80, 400, "impossible release preserves source")

obstacles = {}
begin(moving)
move(moving, 700, 100)
enumerationFails = true
release(moving)
expectRect(moving.root, 400, 300, 80, 400, "enumeration failure cannot approve stale target")
enumerationFails = false

for _, cancellation in ipairs({ "lock", "escape", "focus", "hide", "size" }) do
    begin(moving)
    move(moving, 200, 100)
    if cancellation == "lock" then locked = true; transmit(12)
    elseif cancellation == "escape" then emit("KeyDown", { gameKey = GameKey.ESCAPE })
    elseif cancellation == "focus" then emit("WindowFocusChanged", { hasFocus = false })
    elseif cancellation == "hide" then moving:Hide()
    else moving:SetSize(300, 200) end
    expectNoDrag(moving, cancellation)
    if cancellation ~= "size" then
        expectRect(moving.root, 400, 300, 80, 400, cancellation .. " restores source")
    end
    locked = false; transmit(12); moving:Show()
end
moving:Destroy()

-- Raw screen pixels and hook-local interface units agree with a nonzero parent
-- origin and non-100% scaling; release also consumes the newest pointer.
obstacles = {
    { x = 0, y = 300, width = 400, height = 400 },
    { x = 520, y = 300, width = 480, height = 400 },
}
parent:SetPos(40, 30)
game.options.InterfaceScale.setting = 125
for _, rawMouse in ipairs({ false, true }) do
    local owner = makePanel()
    local raw
    Mouse.GetPosition = function() return raw end
    if rawMouse then raw = { x = (40 + 250) * 1.25, y = (30 + 106) * 1.25 } end
    begin(owner)
    if rawMouse then raw = { x = (40 + 460) * 1.25, y = (30 + 450) * 1.25 } end
    move(owner, 460, 450)
    expectRect(owner.dragFeedback.active, 400, 300, 120, 400, "scaled pointer fills native gap in parent units")
    expectRect(owner.root, 310, 444, 300, 200, "scaled body tracks the pointer independently of the fitted preview")
    if rawMouse then raw = { x = (40 + 200) * 1.25, y = (30 + 100) * 1.25 } end
    fire(owner.dragLayer, ui.Hook.ONRELEASE, 200, 100)
    expectRect(owner.root, 50, 94, 300, 200, "latest release pointer wins")
    owner:Destroy()
end
Mouse.GetPosition = function() return nil end
game.options.InterfaceScale.setting = 100
parent:SetPos(0, 0)
obstacles = {}
local resized = makePanel()
begin(resized); move(resized, 900, 600)
parent:SetSize(500, 350)
expectNoDrag(resized, "viewport resize")
expectRect(resized.root, 100, 100, 300, 200, "resize cancels before bounds mutate source")
expect(resized.root.x + resized.root.width <= parent.width, true, "resized viewport contains source")
resized:Destroy()
parent:SetSize(1000, 700)
for _, change in ipairs({ "origin", "scale" }) do
    local owner = makePanel()
    begin(owner); move(owner, 700, 500)
    if change == "origin" then parent:SetPos(20, 10)
    else game.options.InterfaceScale.setting = 150 end
    emit("Logic")
    expectNoDrag(owner, change)
    expectRect(owner.root, 100, 100, 300, 200, change .. " restores source")
    owner:Destroy()
    parent:SetPos(0, 0); game.options.InterfaceScale.setting = 100
end

-- A fitted parent retains its scroll contract, including nested sibling captures.
obstacles = {
    { x = 0, y = 300, width = 400, height = 400 },
    { x = 520, y = 300, width = 480, height = 400 },
}
local scrolling = makePanel()
for index = 1, 16 do scrolling:AddText("Row " .. index) end
local nested = scrolling:AddPanel({ height = 80 })
for index = 1, 8 do nested:AddText("Nested " .. index) end
begin(scrolling); move(scrolling, 460, 450); release(scrolling)
expect(scrolling.contentWidth, 94, "narrowed viewport reserves scrollbar and gutter")
expect(scrolling.viewport.width, 94, "content and viewport widths agree")
expect(scrolling._scroll.thumbDrag.x, 500, "scrollbar hit region follows fitted x")
scrolling:SetScrollPosition(64)
expect(scrolling.scrollY, 64, "narrowed content remains scrollable")
local overlayRoots = {}
for root in pairs(scrolling.overlays) do overlayRoots[#overlayRoots + 1] = root end
scrolling:Hide()
for _, root in ipairs(overlayRoots) do expect(root.hidden, true, "hide removes nested input overlays") end
scrolling:Destroy()
for _, root in ipairs(overlayRoots) do expect(root.destroyed, true, "destroy releases nested overlays") end

-- Other NisPanels obstruct with their full body; Windows keep their visible inset.
obstacles = {}
local Snap = require("src/core/snap")
local Window = require("src/window")
local a, b = makePanel(), NisPanel.new(parent, { x = 500, y = 300, width = 200, height = 200 })
local window = Window.new(parent, { x = 10, y = 400, width = 300, height = 200 })
local rects = Snap.collect(a, {}, true)
expect(#rects, 2, "moving panel excludes itself")
table.sort(rects, function(left, right) return left.x < right.x end)
expectRect(rects[1], 12, 402, 296, 196, "Window collision keeps visible inset")
expectRect(rects[2], 500, 300, 200, 200, "NisPanel collision uses full outer bounds")
b:Hide(); window:Hide()
expect(#Snap.collect(a, {}, true), 0, "hidden surfaces do not obstruct placement")
b:Show()
b.root.visibleGlobal = false
expect(#Snap.collect(a, {}, true), 0, "globally invisible surfaces do not obstruct")
b:Destroy(); window:Destroy()
begin(a); move(a, 460, 450)
local replacing = makePanel()
begin(replacing)
expect(a.dragState, nil, "second panel capture ends previous capture")
expect(a.dragFeedback, nil, "second panel capture removes previous outlines")
replacing:_CancelDrag()
a:Destroy(); replacing:Destroy()
local remount = makePanel()
expect(#Snap.collect(remount, {}, true), 0, "destroy/remount leaves no collision registrations")
remount:Destroy()

-- Edge/corner input uses the ordinary resize controller without a modifier.
-- Manual resizing commits the dimensions used by later free-space fitting.
local manual = makePanel()
local east = hitAt(parent, 400, 200)
expect(east, manual.resize.handles.e, "right edge is reachable above body/header siblings")
expect(east.cursorConfig.mouseOverCursor, config.Cursor.TOPLEVEL_V2_SCALE_HORZ,
    "reachable edge advertises the normal horizontal resize cursor")
fire(east, ui.Hook.ONCLICK, 5, 30)
fire(east, ui.Hook.ONHOLD, 65, 30)
expectRect(manual.root, 100, 100, 360, 200, "edge drag changes live outer dimensions")
fire(east, ui.Hook.ONRELEASE)
expect(manual.resize.dragState, nil, "edge release ends resize capture")
expect(manual.resize.feedback, nil, "edge release removes resize outline")
local corner = hitAt(parent, 460, 300)
fire(corner, ui.Hook.ONCLICK, 5, 20)
fire(corner, ui.Hook.ONHOLD, -15, 50)
fire(corner, ui.Hook.ONRELEASE)
expectRect(manual.root, 100, 100, 340, 230, "corner drag adjusts both dimensions")
begin(manual)
expect(manual.resize.handles.e.enabled, false, "placement disables competing resize regions")
move(manual, 200, 100); release(manual)
expectRect(manual.root, 30, 94, 340, 230, "placement retains manually resized dimensions")
expect(manual.resize.handles.e.enabled, true, "placement release restores resize regions")
locked = true; transmit(12)
expect(manual.resize.handles.e.enabled, false, "native relock disables resize handles")
locked = false; transmit(12)
manual:Hide()
expect(manual.resize.handles.e.hidden, true, "hide removes resize hit regions")
manual:Show()
local handles = manual.resize.handles
manual:Destroy()
for _, handle in pairs(handles) do expect(handle.destroyed, true, "destroy releases resize siblings") end

-- Persist only committed rectangles, never transient drag ghosts or live resize frames.
local changes = {}
local notified = NisPanel.new(parent, {
    x = 100, y = 100, width = 300, height = 200,
    onBoundsChange = function(owner, x, y, width, height)
        expect(owner.dragFeedback, nil, "bounds callback runs after placement feedback cleanup")
        changes[#changes + 1] = { x = x, y = y, width = width, height = height }
    end,
})
expect(#changes, 0, "construction does not notify unchanged initial bounds")
begin(notified); release(notified)
expect(#changes, 0, "stationary click does not notify")
begin(notified); move(notified, 500, 200)
expect(#changes, 0, "drag ghost does not notify")
notified:_CancelDrag()
expect(#changes, 0, "cancelled placement does not notify")
begin(notified); move(notified, 500, 200); release(notified)
expect(#changes, 1, "committed placement notifies once")
expectRect(changes[1], 350, 194, 300, 200, "placement callback carries committed position and size")
fire(notified.dragLayer, ui.Hook.ONDRAGCOMPLETE)
expect(#changes, 1, "duplicate completion does not notify again")
notified:SetSize(320, 220)
expect(#changes, 2, "explicit sizing notifies")
expectRect(changes[2], 350, 194, 320, 220, "size callback carries final contained bounds")
notified:SetSize(320, 220)
expect(#changes, 2, "unchanged explicit size does not notify")
local resizeHandle = notified.resize.handles.e
fire(resizeHandle, ui.Hook.ONCLICK, 2, 2)
fire(resizeHandle, ui.Hook.ONHOLD, 32, 2)
expect(#changes, 2, "live edge resize does not notify until release")
fire(resizeHandle, ui.Hook.ONRELEASE)
expect(#changes, 3, "resize release notifies once")
expectRect(changes[3], 350, 194, 350, 220, "resize callback carries committed dimensions")
fire(resizeHandle, ui.Hook.ONDRAGCOMPLETE)
expect(#changes, 3, "duplicate resize completion does not notify")
notified:SetSize(300, 200)
parent:SetSize(800, 600)
expect(#changes, 5, "parent containment/repositioning notifies after explicit size")
expectRect(changes[5], 250, 155, 300, 200, "parent resize callback uses actual proportional position")
notified:Hide(); notified:Show()
expect(#changes, 5, "visibility changes do not notify unchanged geometry")
resizeHandle = notified.resize.handles.e
fire(resizeHandle, ui.Hook.ONCLICK, 2, 2)
fire(resizeHandle, ui.Hook.ONHOLD, 22, 2)
expect(#changes, 5, "interrupted resize has not yet notified")
notified:Hide()
expect(#changes, 6, "hiding commits the live resized bounds once")
expectRect(changes[6], 250, 155, 320, 200, "interrupted resize persists its retained dimensions")
fire(resizeHandle, ui.Hook.ONRELEASE)
expect(#changes, 6, "release after hiding cannot duplicate persistence")
notified:Destroy()
parent:SetSize(1000, 700)
local destroyOnBounds = NisPanel.new(parent, {
    onBoundsChange = function(owner) owner:Destroy() end,
})
destroyOnBounds:SetSize(340, 220)
expect(destroyOnBounds.root, nil, "bounds callback may destroy its owner during SetSize")
local destroyOnCommit = NisPanel.new(parent, {
    x = 100, y = 100, width = 300, height = 200,
    onBoundsChange = function(owner) owner:Destroy() end,
})
begin(destroyOnCommit); move(destroyOnCommit, 500, 200); release(destroyOnCommit)
expect(destroyOnCommit.root, nil, "bounds callback may destroy its owner after placement cleanup")

-- Interactive sizing stops at native/registered visible edges, not just the viewport.
local function resizeBy(owner, key, dx, dy)
    local handle = owner.resize.handles[key]
    fire(handle, ui.Hook.ONCLICK, 2, 2)
    fire(handle, ui.Hook.ONHOLD, 2 + dx, 2 + dy)
    fire(handle, ui.Hook.ONRELEASE)
end
for _, scenario in ipairs({
    { edge = "e", dx = 600, dy = 0, blocker = { x = 450, y = 0, width = 100, height = 700 },
        result = { 100, 100, 350, 200 } },
    { edge = "w", dx = -300, dy = 0, blocker = { x = 30, y = 0, width = 30, height = 700 },
        result = { 60, 100, 340, 200 } },
    { edge = "n", dx = 0, dy = -300, blocker = { x = 0, y = 30, width = 1000, height = 30 },
        result = { 100, 60, 300, 240 } },
    { edge = "s", dx = 0, dy = 300, blocker = { x = 0, y = 350, width = 1000, height = 100 },
        result = { 100, 100, 300, 250 } },
}) do
    obstacles = { scenario.blocker }
    local constrained = makePanel()
    resizeBy(constrained, scenario.edge, scenario.dx, scenario.dy)
    local x, y, width, height = table.unpack(scenario.result)
    expectRect(constrained.root, x, y, width, height, scenario.edge .. " edge stops at native panel")
    constrained:Destroy()
end
obstacles = { { x = 450, y = 350, width = 100, height = 100 } }
local diagonal = makePanel()
resizeBy(diagonal, "se_v", 250, 250)
expect(diagonal.root.x + diagonal.root.width <= 450 or diagonal.root.y + diagonal.root.height <= 350,
    true, "corner resize cannot grow through a diagonal native panel")
diagonal:Destroy()
obstacles = {}
local registered = Window.new(parent, { x = 450, y = 100, width = 300, height = 200 })
local constrained = makePanel()
resizeBy(constrained, "e", 400, 0)
expectRect(constrained.root, 100, 100, 352, 200, "resize respects ordinary Window's visible inset")
registered:Hide()
resizeBy(constrained, "e", 100, 0)
expectRect(constrained.root, 100, 100, 452, 200, "hidden Window no longer constrains resizing")
enumerationFails = true
resizeBy(constrained, "e", 100, 0)
expectRect(constrained.root, 100, 100, 452, 200, "failed native collection rejects unverified resizing")
enumerationFails = false
constrained:Destroy(); registered:Destroy()

-- Client evidence: 1477:62 is PLUGIN_BUILD_LAYER_BOTTOM, a visible
-- full-viewport plugin host, not a native panel. Only NisPanel fitting excludes it.
parent:SetSize(3440, 1439)
obstacles = {
    { interfaceID = 1477, staticID = 62, x = 0, y = 0, width = 3440, height = 1439 },
    { interfaceID = 1477, staticID = 94, x = 3061, y = 0, width = 379, height = 214 },
    { interfaceID = 1477, staticID = 69, x = 1296, y = 1124, width = 530, height = 76 },
    { interfaceID = 1477, staticID = 103, x = 1084, y = 1127, width = 211, height = 312 },
}
local nativePlacement = makePanel()
begin(nativePlacement); move(nativePlacement, 500, 400)
expectRect(nativePlacement.dragFeedback.active, 350, 394, 300, 200,
    "plugin host wrapper does not prevent placement in open native space")
release(nativePlacement)
expectRect(nativePlacement.root, 350, 394, 300, 200, "placement leaves default origin with native wrapper present")
begin(nativePlacement); move(nativePlacement, 3200, 100)
local destination = nativePlacement.dragFeedback.active
expect(destination.x + destination.width <= 3061 or destination.y >= 214, true,
    "actual minimap still obstructs placement")
release(nativePlacement)
local defaultCollection = Snap.collect(nativePlacement, {}, true)
expectRect(defaultCollection[1], 0, 0, 3440, 1439, "default snap collection still includes the plugin host")
expect(#Snap.start(nativePlacement).across, 18, "ordinary snapping retains every native target")
local nativeSource = {
    x = nativePlacement.root.x, y = nativePlacement.root.y,
    width = nativePlacement.root.width, height = nativePlacement.root.height,
}
obstacles = {
    { interfaceID = 1477, staticID = 103, x = 0, y = 0, width = 3440, height = 1439 },
}
begin(nativePlacement); move(nativePlacement, 500, 400)
expect(nativePlacement.dragFeedback.active.hidden, true, "a full-viewport actual panel is not size-filtered")
release(nativePlacement)
expectRect(nativePlacement.root, nativeSource.x, nativeSource.y, nativeSource.width, nativeSource.height,
    "occupied viewport retains source rather than overlapping native UI")
nativePlacement:Destroy()
obstacles = {}
parent:SetSize(1000, 700)

-- Native-style nesting is a cursor target, not a body-overlap heuristic.
do
    local function pair(sourceOptions, targetOptions)
        local function options(extra, x, y, width, height)
            local result = {
                categoryID = "auto", x = x, y = y, width = width, height = height,
                tabText = "QA",
            }
            for key, value in pairs(extra or {}) do result[key] = value end
            return result
        end
        return NisPanel.new(parent, options(sourceOptions, 50, 350, 200, 180)),
            NisPanel.new(parent, options(targetOptions, 500, 100, 300, 260))
    end
    local function sameBounds(a, b, message)
        expectRect(a.root, b.root.x, b.root.y, b.root.width, b.root.height, message)
    end
    local function endPair(source, target)
        source:Destroy()
        target:Destroy()
        expect(next(events.Logic), nil, "pair cleanup releases drag sampling")
        expect(#parent.children, 0, "pair cleanup releases sibling tab art and input layers")
    end

    for _, point in ipairs({
        { 503, 130 }, { 796, 130 }, -- frame side boundaries
        { 650, 115 }, { 650, 144 }, -- header/top border and first body row
        { 650, 106 }, { 650, 250 }, -- header and deep body
    }) do
        local source, target = pair()
        begin(source); move(source, point[1], point[2])
        expect(target._nisTabs.root.hidden, true, "outside tab band does not show nesting feedback")
        release(source)
        expect(source.root.hidden, false, "outside-band release leaves source independent")
        expect(target.root.hidden, false, "outside-band release leaves target independent")
        expect(target.surface.container.y, 16, "outside-band release does not reserve a tab row")
        endPair(source, target)
    end

    for _, point in ipairs({ { 504, 116 }, { 795, 143 }, { 650, 130 } }) do
        local source, target = pair()
        begin(source); move(source, point[1], point[2])
        expect(target._nisTabs.root.hidden, false, "strict strip interior shows the incoming tab")
        expectRect(source.dragFeedback.active, 500, 100, 300, 260, "nesting previews target outer bounds")
        expectRect(source.root, point[1] - 100, point[2] - 6, 200, 180,
            "nesting preview does not relocate or resize the body to the target")
        release(source)
        sameBounds(source, target, "docked panels share target bounds")
        expect(source.root.hidden, false, "incoming panel is selected")
        expect(target.root.hidden, true, "inactive panel content is hidden")
        expect(source.surface.container.y, 44, "group content begins below header and tabs")
        target:SelectTab()
        expect(target.root.hidden, false, "selecting retained target reveals its content")
        expect(source.root.hidden, true, "selecting target hides incoming content")
        source:Show()
        expect(source.root.hidden, false, "Show selects an existing grouped member")
        sameBounds(source, target, "tab selection never relocates or resizes members")
        source:Undock()
        expect(source.root.hidden, false, "explicit detach reveals standalone source")
        expect(target.root.hidden, false, "last survivor becomes standalone")
        expect(source.surface.container.y, 16, "detached panel releases its tab inset")
        expect(target.surface.container.y, 16, "singleton survivor releases its tab inset")
        expectRect(source.root, 500, 100, 300, 260, "detaching preserves the committed current size")
        endPair(source, target)
    end

    local source, target = pair()
    begin(source); move(source, 650, 130)
    move(source, 650, 250)
    expect(target._nisTabs.root.hidden, true, "leaving strip immediately clears incoming-tab feedback")
    release(source)
    expect(target.root.hidden, false, "leaving strip cannot commit a remembered docking target")
    endPair(source, target)

    source, target = pair()
    begin(source); move(source, 650, 130)
    -- Release is independently targeted, even without another drag hook.
    fire(source.dragLayer, ui.Hook.ONRELEASE, 650, 250)
    expect(target.root.hidden, false, "release outside strip cannot commit stale nesting")
    endPair(source, target)

    for _, cancellation in ipairs({ "escape", "focus", "lock", "hide", "destroy" }) do
        source, target = pair()
        begin(source); move(source, 650, 130)
        if cancellation == "escape" then emit("KeyDown", { gameKey = GameKey.ESCAPE })
        elseif cancellation == "focus" then emit("WindowFocusChanged", { hasFocus = false })
        elseif cancellation == "lock" then locked = true; transmit(12)
        elseif cancellation == "hide" then target:Hide(); release(source)
        else target:Destroy(); release(source) end
        if target.root then
            expect(target._nisTabs.root.hidden, true, cancellation .. " clears target tab feedback")
        end
        if source.dragState then source:_CancelDrag() end
        expect(source.surface.container.y, locked and 4 or 16, cancellation .. " cannot create a group")
        locked = false; transmit(12)
        endPair(source, target)
    end

    local saved = {}
    source, target = pair({
        onBoundsChange = function(_, x, y, width, height)
            saved[#saved + 1] = { x = x, y = y, width = width, height = height }
        end,
    })
    for index = 1, 16 do source:AddText("Source row " .. index) end
    local nested = source:AddPanel({ height = 100 })
    for index = 1, 8 do nested:AddText("Nested row " .. index) end
    begin(source); move(source, 650, 130)
    expect(#saved, 0, "nesting preview does not persist bounds")
    release(source)
    expect(#saved, 1, "nest commit persists new shared bounds once")
    fire(source.dragLayer, ui.Hook.ONDRAGCOMPLETE)
    expect(#saved, 1, "duplicate nesting completion cannot persist twice")
    target:SelectTab()
    for overlay in pairs(source.overlays) do
        expect(overlay.hidden, true, "inactive tab hides nested content input overlays")
    end
    source:SelectTab()
    source:SetSize(340, 280)
    sameBounds(source, target, "explicit group sizing synchronizes inactive member geometry")
    expectRect(target.root, 500, 100, 340, 280, "group sizing updates dimensions without restoring old sizes")
    expect(#saved, 2, "explicit group sizing notifies selected member once")
    resizeBy(source, "e", 20, 0)
    sameBounds(source, target, "interactive group resize synchronizes inactive member")
    expect(source.root.width, 360, "group uses the normal edge resizing path")
    expect(#saved, 3, "interactive group resize saves only its final bounds")
    obstacles = { { x = 890, y = 0, width = 110, height = 700 } }
    resizeBy(source, "e", 200, 0)
    expect(source.root.x + source.root.width, 890, "group resizing cannot overlap a native panel")
    sameBounds(source, target, "collision-clamped group sizing is shared")
    obstacles = {}
    begin(source); move(source, 250, 100); release(source)
    sameBounds(source, target, "header placement moves every group member")
    expect(source.root.width, 390, "group movement retains its current resized width")
    parent:SetSize(900, 650)
    sameBounds(source, target, "parent resize keeps grouped member positions identical")
    parent:SetSize(1000, 700)
    sameBounds(source, target, "parent resize does not apply proportional movement twice")
    transparency = 128; transmit(12)
    expect(source._nisTabs.tabs[1].background.alpha, 1 - 128 / 255, "native opacity fades tab artwork")
    expect(source._nisTabs.tabs[1].iconSprite.alpha, 1, "native opacity leaves tab icons opaque")
    locked = true; transmit(12)
    expect(source.surface.container.y, 32, "locked group retains tab row without editing header")
    target:SelectTab()
    expect(target.root.hidden, false, "locked group still allows tab selection")
    expect(target.dragLayer.enabled, false, "locked selection never enables editing input")
    locked = false; transparency = 0; transmit(12)
    source:Hide()
    expect(target.root.hidden, false, "hiding inactive member leaves survivor visible")
    expect(target.surface.container.y, 16, "hiding member dissolves a two-member group")
    endPair(source, target)

    source, target = pair()
    expect(source:DockTo(target), true, "explicit docking shares a compatible target")
    -- Tab input must switch retained pages without replacing their content.
    local originalContent = target.content
    local firstTab = source._nisTabs.tabs[1].hit
    expect(hitAt(parent, 514, 126), firstTab, "the visible tab receives the initial press")
    fire(firstTab, ui.Hook.ONCLICK, 10, 10)
    expect(target.root.hidden, false, "native-style tab click selects the target")
    expect(target.content, originalContent, "selection preserves content and scroll ownership")
    expect(hitAt(parent, 514, 126), firstTab,
        "tab switching preserves the native pressed component until release")
    expect(firstTab.destroyed == true, false, "switching content must not destroy the pressed tab")
    expect(target.dragLayer.height, 12, "a pending tab click keeps the header hitbox bounded")
    expect(target.dragState, nil, "tab selection does not begin panel placement")
    fire(firstTab, ui.Hook.ONRELEASE, 10, 10)
    for _, selected in ipairs({ source, target, source, target }) do
        local slot = selected == target and 0 or 40
        local clicked = hitAt(parent, 514 + slot, 126)
        fire(clicked, ui.Hook.ONCLICK, 10, 10)
        fire(clicked, ui.Hook.ONHOLD, 12, 11)
        expect(selected.root.hidden, false, "edit-mode tab clicks switch content despite small pointer jitter")
        expect(selected.dragState, nil, "small held movement never detaches a tab")
        expect(hitAt(parent, 514 + slot, 126), clicked, "selection preserves native gesture ownership")
        expect(selected.dragLayer.height, 12, "tab presses cannot expand the header into the body")
        fire(clicked, ui.Hook.ONRELEASE, 12, 11)
        expectNoDrag(selected, "repeated tab click release")
        sameBounds(source, target, "tab clicks cannot change shared bounds")
    end
    locked = true; transmit(12)
    for _, selected in ipairs({ source, target, source, target }) do
        local slot = selected == target and 0 or 40
        local clicked = hitAt(parent, 514 + slot, 114)
        fire(clicked, ui.Hook.ONCLICK, 10, 10)
        expect(selected.root.hidden, false, "locked tab clicks switch retained content")
        expect(clicked.destroyed == true, false, "locked selection preserves the pressed native target")
        expect(hitAt(parent, 514 + slot, 114), clicked, "locked selection retains gesture ownership")
        fire(clicked, ui.Hook.ONHOLD, 30, 20)
        fire(clicked, ui.Hook.ONRELEASE, 30, 20)
        expect(selected.root.hidden, false, "holding a locked tab cannot undo selection")
        expectNoDrag(selected, "locked tab release")
        sameBounds(source, target, "locked tab interaction cannot move the group")
    end
    locked = false; transmit(12)
    local body = target:AddText("Interactive body")
    local bodyClicks = 0
    body.clickthrough = false
    body:Subscribe(ui.Hook.ONCLICK, function() bodyClicks = bodyClicks + 1; return false end)
    local bodyPoint = body.xyGlobal
    local bodyHit = hitAt(parent, bodyPoint.x + 2, bodyPoint.y + 2)
    expect(bodyHit, body, "tab clicking leaves body controls reachable below the header")
    fire(bodyHit, ui.Hook.ONCLICK, 2, 2)
    expect(bodyClicks, 1, "body control interaction is not redirected into panel dragging")
    expectNoDrag(target, "tab click without movement")
    target:Destroy()
    expect(source.root.hidden, false, "destroying selected member selects surviving content")
    expect(source.surface.container.y, 16, "destroying selected member dissolves group chrome")
    source:Destroy()
    source, target = pair()
    expect(source:DockTo(target), true, "release-only movement starts grouped")
    local releaseTab = source._nisTabs.tabs[1].hit
    local releaseRaw = { x = 514, y = 126 }
    Mouse.GetPosition = function() return releaseRaw end
    fire(releaseTab, ui.Hook.ONCLICK, 10, 10)
    releaseRaw = { x = 200, y = 500 }
    emit("Logic")
    expect(target.dragState, nil, "raw pointer sampling cannot promote tab clicks into a drag")
    fire(releaseTab, ui.Hook.ONRELEASE, 200, 500)
    expectNoDrag(target, "release-only movement")
    expect(target.surface.container.y, 44, "release movement alone cannot detach a tab")
    expectRect(target.root, 500, 100, 300, 260, "release movement preserves nested bounds")
    Mouse.GetPosition = function() return nil end
    endPair(source, target)
    source, target = pair()
    expect(source:DockTo(target), true, "pending resize scenario starts grouped")
    local resizingTab = source._nisTabs.tabs[1].hit
    fire(resizingTab, ui.Hook.ONCLICK, 10, 10)
    parent:SetSize(800, 600)
    expectNoDrag(target, "parent resizing cancels pending tab press")
    sameBounds(source, target, "pending-press cancellation preserves shared parent containment")
    expect(source.root.x + source.root.width <= parent.width, true, "resized parent contains restored group")
    parent:SetSize(1000, 700)
    endPair(source, target)

    local unloadingParent = component(nil, "pending-tab unload host")
    unloadingParent.interfaceID = 1499
    Interfaces.component(unloadingParent)
    unloadingParent:SetSize(1000, 700)
    local unloadingA = NisPanel.new(unloadingParent, { width = 300, height = 200 })
    local unloadingB = NisPanel.new(unloadingParent, { x = 400, width = 300, height = 260 })
    expect(unloadingA:DockTo(unloadingB), true, "pending unload scenario starts grouped")
    fire(unloadingA._nisTabs.tabs[1].hit, ui.Hook.ONCLICK, 10, 10)
    Interfaces.unload(1499)
    emit("Logic")
    unloadingA:Destroy(); unloadingB:Destroy()
    expectNoDrag(unloadingB, "pending tab interface unload")



    local committed = 0
    source, target = pair({ onBoundsChange = function() committed = committed + 1 end })
    expect(source:DockTo(target), true, "selection-interruption scenario starts grouped")
    begin(source); move(source, 250, 100)
    target:SelectTab()
    expectNoDrag(source, "switching tabs cancels active group placement")
    sameBounds(source, target, "switching during placement restores all shared bounds")
    expectRect(target.root, 500, 100, 300, 260, "switching during placement retains source rectangle")
    expect(committed, 1, "tab switching cannot persist a cancelled group ghost")
    source:SelectTab()
    local liveEdge = source.resize.handles.e
    fire(liveEdge, ui.Hook.ONCLICK, 2, 2)
    fire(liveEdge, ui.Hook.ONHOLD, 22, 2)
    expect(committed, 1, "live group resize does not persist before selection")
    target:SelectTab()
    expect(source.resize.dragState, nil, "switching tabs ends active edge capture")
    sameBounds(source, target, "switching during resize retains final shared bounds")
    expect(target.root.width, 320, "switching during resize keeps the retained live size")
    expect(committed, 2, "switching during resize persists retained bounds once")
    endPair(source, target)

    -- A tab drag detaches one page, not the whole shared rectangle.
    for _, cancellation in ipairs({ "release", "complete", "escape", "lock", "focus" }) do
        local commits = 0
        source, target = pair({ onBoundsChange = function() commits = commits + 1 end })
        expect(source:DockTo(target), true, "tab drag starts from a real group")
        expect(commits, 1, "initial grouping records adopted target bounds")
        local tab = source._nisTabs.tabs[2].hit
        local raw = { x = tab.xyGlobal.x + 12, y = tab.xyGlobal.y + 12 }
        Mouse.GetPosition = function() return raw end
        fire(tab, ui.Hook.ONCLICK, 12, 12)
        raw = { x = 200, y = 500 }
        fire(tab, ui.Hook.ONDRAG, 12, 100)
        expect(target.root.hidden, false, "dragging one tab leaves the other content visible")
        expect(hitAt(parent, 200, 500), tab, "intentional tab drag keeps capture on the original native hit")
        expect(source.dragLayer.height, 12, "actual tab detachment does not expand the header hitbox")
        expect(commits, 1, "tab-detach preview does not persist intermediate geometry")
        if cancellation == "release" or cancellation == "complete" then
            if cancellation == "complete" then
                Mouse.GetPosition = function() return nil end
                fire(tab, ui.Hook.ONDRAGCOMPLETE, nil, 200, 500)
            else
                fire(tab, ui.Hook.ONRELEASE)
            end
            expect(source.surface.container.y, 16, "committed tab drag becomes standalone")
            expect(target.surface.container.y, 16, "committed tab drag dissolves singleton group")
            expect(source.root.width, 300, "tab detach retains shared current width")
            expect(source.root.height, 260, "tab detach retains shared current height")
            expect(source.root.x + source.root.width <= target.root.x
                or source.root.y >= target.root.y + target.root.height,
                true, "detached tab uses collision-safe free placement")
            expect(commits, 2, "tab-detach release persists once")
        else
            if cancellation == "escape" then emit("KeyDown", { gameKey = GameKey.ESCAPE })
            elseif cancellation == "lock" then locked = true; transmit(12)
            else emit("WindowFocusChanged", { hasFocus = false }) end
            expectRect(source.root, 500, 100, 300, 260, cancellation .. " restores shared rectangle")
            expect(target.root.hidden, true, cancellation .. " restores original selected tab")
            expect(source.surface.container.y, locked and 32 or 44,
                cancellation .. " restores group content inset")
            expect(commits, 1, cancellation .. " does not persist cancelled detachment")
        end
        expectNoDrag(source, cancellation .. " ends tab capture")
        Mouse.GetPosition = function() return nil end
        locked = false; transmit(12)
        endPair(source, target)
    end

    -- Native tab dragging reorders within the strip before becoming a window.
    do
        local function order(owner, expected, message)
            for index, member in ipairs(expected) do
                expect(owner._nisTabs.tabs[index].member, member, message .. " slot " .. index)
            end
        end
        for _, finish in ipairs({ "release", "escape", "lock", "focus", "tearout", "reenter" }) do
            local saved = 0
            local function save() saved = saved + 1 end
            source, target = pair({ onBoundsChange = save }, { onBoundsChange = save })
            expect(source:DockTo(target), true, "reorder source joins target")
            local third = NisPanel.new(parent, {
                categoryID = "auto", x = 50, y = 100, width = 200, height = 180,
                tabText = "Third", onBoundsChange = save,
            })
            expect(third:DockTo(source), true, "third member joins existing group")
            source:SelectTab()
            saved = 0
            local held = source._nisTabs.tabs[3].hit
            local raw = { x = held.x + 12, y = held.y + 12 }
            Mouse.GetPosition = function() return raw end
            fire(held, ui.Hook.ONCLICK, 12, 12)
            raw = { x = 556, y = 128 }
            fire(held, ui.Hook.ONHOLD, 12, 12)
            order(third, { target, third, source }, "dragging across one tab previews the middle position")
            expect(third.dragState, nil, "in-strip tab dragging does not detach a window")
            expectRect(third.root, 500, 100, 300, 260, "in-strip tab dragging leaves shared body fixed")
            expectRect(third.dragFeedback.origin, 500, 100, 300, 260, "reordering keeps white group origin")
            expectRect(third.dragFeedback.active, 406, 122, 300, 260, "reordering previews a centered tear-out frame")
            local white, orange = third.dragFeedback.origin, third.dragFeedback.active
            raw = { x = 514, y = 128 }
            fire(held, ui.Hook.ONHOLD, 514, 128)
            order(third, { third, target, source }, "continued in-strip dragging previews the first position")
            expect(saved, 0, "tab reordering never persists unchanged geometry")
            if finish == "tearout" or finish == "reenter" then
                raw = { x = 200, y = 500 }
                fire(held, ui.Hook.ONHOLD, 200, 500)
                expect(third.dragState ~= nil, true, "leaving the strip begins window tear-out")
                expect(third.dragFeedback.origin, white, "tear-out preserves the original white frame")
                expect(target.root.hidden, false, "tear-out reveals a surviving member")
                if finish == "reenter" then
                    raw = { x = 514, y = 128 }
                    fire(held, ui.Hook.ONHOLD, 514, 128)
                end
            end
            if finish == "escape" then emit("KeyDown", { gameKey = GameKey.ESCAPE })
            elseif finish == "lock" then locked = true; transmit(12)
            elseif finish == "focus" then emit("WindowFocusChanged", { hasFocus = false })
            else fire(held, ui.Hook.ONRELEASE) end
            expectNoDrag(third, "completed " .. finish .. " tab gesture")
            expect(held.destroyed, true, "completed tab dragging releases its original native capture")
            expect(white.destroyed, true, "completed tab gesture releases white frame")
            expect(orange.destroyed, true, "completed tab gesture releases orange frame")
            if finish == "tearout" then
                expect(third.surface.container.y, 16, "outside release commits standalone layout")
                order(target, { target, source }, "tear-out retains the remaining members' order")
                expect(saved, 1, "only committed tear-out persists geometry")
                expect(third.root.x + third.root.width <= target.root.x
                    or third.root.y >= target.root.y + target.root.height,
                    true, "committed tear-out cannot overlap the remaining group")
            elseif finish == "release" or finish == "reenter" then
                order(third, { third, target, source }, "inside release commits requested tab order")
                expect(saved, 0, "committed tab order does not pretend geometry changed")
                local first = hitAt(parent, 514, 126)
                fire(first, ui.Hook.ONCLICK, 10, 10)
                fire(first, ui.Hook.ONRELEASE, 10, 10)
                expect(third.root.hidden, false, "reordered tab remains clickable after release")
            else
                order(source, { target, source, third }, "cancellation restores original tab order")
                expect(source.root.hidden, false, "cancellation restores original selected member")
                expect(saved, 0, "cancelled reorder does not persist transient geometry")
            end
            locked = false; transmit(12)
            Mouse.GetPosition = function() return nil end
            third:Destroy()
            endPair(source, target)
        end
        source, target = pair()
        expect(source:DockTo(target), true, "same-slot tab drag starts grouped")
        local held = source._nisTabs.tabs[2].hit
        local raw = { x = held.x + 12, y = held.y + 12 }
        Mouse.GetPosition = function() return raw end
        fire(held, ui.Hook.ONCLICK, 12, 12)
        raw.x = raw.x + 5
        fire(held, ui.Hook.ONHOLD, 17, 12)
        fire(held, ui.Hook.ONRELEASE, 17, 12)
        local clickable = hitAt(parent, 554, 126)
        fire(clickable, ui.Hook.ONCLICK, 10, 10)
        fire(clickable, ui.Hook.ONRELEASE, 10, 10)
        expect(source.root.hidden, false, "a same-slot drag cannot remove its tab's input hit")
        Mouse.GetPosition = function() return nil end
        endPair(source, target)
    end

    source, target = pair({ tabText = "From" }, { tabText = "To" })
    begin(source); move(source, 520, 130)
    release(source)
    source:SetSize(64, 260)
    expect(source.root.width, 64, "an existing group can shrink below the width needed for all tabs")
    local previousTab = hitAt(parent, 548, 130)
    fire(previousTab, ui.Hook.ONCLICK, 4, 10)
    expect(target.root.hidden, false, "previous-tab navigation reaches hidden content in a narrow group")
    local nextTab = hitAt(parent, 556, 130)
    fire(nextTab, ui.Hook.ONCLICK, 4, 10)
    expect(source.root.hidden, false, "next-tab navigation returns to the incoming member")
    source:SetSize(460, 260)
    local stripY = source.root.y + 26
    expect(hitAt(parent, source.root.x + source.root.width - 10, stripY) ~= nil, true,
        "expanding the strip blocks game clicks through its newly exposed unused space")
    local targetTab = hitAt(parent, source.root.x + 14, stripY)
    fire(targetTab, ui.Hook.ONCLICK, 10, 10)
    fire(targetTab, ui.Hook.ONRELEASE, 10, 10)
    expect(target.root.hidden, false, "expanding the strip restores direct access to the first tab")
    local sourceTab = hitAt(parent, target.root.x + 54, stripY)
    fire(sourceTab, ui.Hook.ONCLICK, 10, 10)
    fire(sourceTab, ui.Hook.ONRELEASE, 10, 10)
    expect(source.root.hidden, false, "expanding the strip restores direct access to the second tab")
    endPair(source, target)

    for _, conflict in ipairs({
        { minWidth = 301 }, { minHeight = 261 },
        { maxWidth = 299 }, { maxHeight = 259 },
    }) do
        source, target = pair(conflict)
        expect(source:DockTo(target), false, "incompatible member bounds reject docking without stretching target")
        expectRect(target.root, 500, 100, 300, 260, "rejected docking does not mutate target bounds")
        expect(source.root.hidden, false, "rejected docking does not hide source")
        endPair(source, target)
    end
    source, target = pair()
    local otherParent = component(nil, "different nesting host")
    otherParent:SetSize(1000, 700)
    local foreign = NisPanel.new(otherParent, { width = 300, height = 260 })
    expect(source:DockTo(foreign), false, "different native parents never group")
    expect(source:DockTo(source), false, "self docking is rejected")
    target:Hide()
    expect(source:DockTo(target), false, "hidden targets cannot receive docking")
    foreign:Destroy()
    endPair(source, target)

    source, target = pair({ maxWidth = 340 }, { minWidth = 280 })
    expect(source:DockTo(target), true, "compatible member limits allow grouping")
    target:SetSize(700, 280)
    sameBounds(source, target, "sizing from either member applies common maxima")
    expect(source.root.width, 340, "hidden member maximum constrains shared size")
    resizeBy(source, "w", 200, 0)
    expect(target.root.width, 280, "hidden member minimum constrains interactive resize")
    sameBounds(source, target, "shared constraints preserve identical group bounds")
    source:Undock()
    source:SetSize(200, 200)
    target:SetSize(400, 200)
    expect(source.root.width, 200, "detaching restores source's individual minimum")
    expect(target.root.width, 400, "last survivor restores its individual maximum")
    endPair(source, target)

    source, target = pair({
        onBoundsChange = function(owner) owner:Destroy() end,
    })
    expect(source:DockTo(target), true, "nesting tolerates callback-driven source destruction")
    expect(source.root, nil, "bounds callback can destroy incoming member")
    expect(target.root.hidden, false, "callback destruction leaves target content visible")
    expect(target.surface.container.y, 16, "callback destruction cleans up shared chrome")
    endPair(source, target)
end

-- Active unload must take the full destruction path without touching native handles.
local activeUnloaded = makePanel()
begin(activeUnloaded); move(activeUnloaded, 460, 450)
Interfaces.unload(activeUnloaded.interfaceID)
emit("Logic")
expect(activeUnloaded.root, nil, "active unload destroys Lua ownership")
expectNoDrag(activeUnloaded, "active unload")
-- Use a fresh interface for the idle unload path below.
parent = component(nil, "remounted parent")
parent.interfaceID = 1478
Interfaces.component(parent)
parent:SetSize(1000, 700)

local unloaded = NisPanel.new(parent, { categoryID = "auto" })
local interfaceID = unloaded.interfaceID
Interfaces.unload(interfaceID)
unloaded:Destroy()
expect(unloaded.root, nil, "unload permits Lua-only cleanup")
print("nis_panel_test: ok")
