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

local function removeRenderChild(parent, child)
    if not parent then return false end
    for index, candidate in ipairs(parent.renderChildren) do
        if candidate == child then table.remove(parent.renderChildren, index); return true end
    end
    return false
end

local function component(parent, kind, categoryID, dynamicID)
    local result = {
        parent = parent, kind = kind, children = {}, renderChildren = {},
        subscriptions = {}, namedSubscriptions = {},
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
        assert(removeRenderChild(parent, self), "cannot reorder an absent native render entry")
        self.frontMoves = (self.frontMoves or 0) + 1
        removeChild(parent, self)
        parent.children[#parent.children + 1] = self
        parent.renderChildren[#parent.renderChildren + 1] = self
    end
    function result:MoveToBack()
        if not parent then return end
        assert(removeRenderChild(parent, self), "cannot reorder an absent native render entry")
        removeChild(parent, self)
        table.insert(parent.children, 1, self)
        table.insert(parent.renderChildren, 1, self)
    end
    function result:Destroy()
        while #self.children > 0 do self.children[#self.children]:Destroy() end
        removeChild(parent, self)
        removeRenderChild(parent, self)
        self.destroyed = true
    end
    setmetatable(result, { __index = function(self, key)
        if key ~= "xyGlobal" then return nil end
        local origin = parent and parent.xyGlobal or { x = 0, y = 0 }
        return { x = origin.x + self.x, y = origin.y + self.y }
    end })
    if parent then
        parent.children[#parent.children + 1] = result
        parent.renderChildren[#parent.renderChildren + 1] = result
    end
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
    for index = #area.renderChildren, 1, -1 do
        local child = area.renderChildren[index]
        if not child.hidden and child.enabled ~= false and
            x >= child.x and x < child.x + child.width and
            y >= child.y and y < child.y + child.height then
            local target = hitAt(child, x - child.x, y - child.y)
            if target then return target end
            if child.clickthrough ~= true then return child end
        end
    end
end

local savedLayouts = {}
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = copy(child) end
    return result
end
PersistentDB = {
    GetStructuredData = function(_, key) return copy(savedLayouts[key]) end,
    SetStructuredData = function(_, key, value)
        savedLayouts[key] = copy(value)
        return true
    end,
}

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

-- Stable IDs retain user layouts across plugin teardown and complete Lua restarts.
do
    locked = false
    transmit(id.VarPlayer.TOPLEVEL_V2_SKINS_VARP)
    obstacles = {}
    Mouse.GetPosition = function() return nil end
    local function create(panelID, extra)
        local options = { id = panelID, x = 100, y = 100, width = 260, height = 180 }
        for key, value in pairs(extra or {}) do options[key] = value end
        return NisPanel.new(parent, options)
    end
    local function restart()
        for _, name in ipairs({ "src/nis_panel", "src/core/nis_group",
            "src/core/nis_drag", "src/core/nis_native", "src/core/nis_persistence" }) do
            package.loaded[name] = nil
        end
        NisPanel = require("src/nis_panel")
    end
    local function saved(panelID)
        return savedLayouts["prettyui.nis-layout.v1"].panels[panelID]
    end
    local a = create("plugin-a:tracker")
    local b = create("plugin-b:tracker", { x = 500, height = 240 })
    expectRect(a.root, 100, 100, 260, 180, "first declaration uses defaults")
    expect(saved("plugin-a:tracker").group, nil, "first standalone declaration is recorded")
    expect(a:DockTo(b), true, "identified panels can group across plugin namespaces")
    a:SetSize(340, 260)
    b:SelectTab()
    local held = b._nisTabs.tabs[1].hit
    local raw = { x = held.x + 12, y = held.y + 12 }
    Mouse.GetPosition = function() return raw end
    fire(held, ui.Hook.ONCLICK, 12, 12)
    raw = { x = b.root.x + 60, y = b.root.y + 28 }
    fire(held, ui.Hook.ONHOLD, 12, 12)
    fire(held, ui.Hook.ONRELEASE)
    Mouse.GetPosition = function() return nil end
    local oldGroup = saved("plugin-a:tracker").group
    expect(savedLayouts["prettyui.nis-layout.v1"].groups[oldGroup].active,
        "plugin-b:tracker", "active tab is saved without changing geometry")
    local children = #parent.children
    expect(pcall(create, "plugin-a:tracker"), false, "duplicate live IDs are rejected")
    expect(#parent.children, children, "duplicate ID fails before allocating components")
    a:Destroy()
    b:Destroy()
    expect(saved("plugin-a:tracker").group, oldGroup, "shutdown does not save an undock")

    restart()
    locked = true
    b = create("plugin-b:tracker", { x = -10, y = -10, xAnchor = 0.5,
        yAnchor = 0.5, width = 600, height = 400, dockTo = "new:default" })
    expectRect(b.root, 500, 100, 340, 260, "saved bounds override changed defaults and anchors")
    expect(b._nisGroup, nil, "missing plugin leaves a usable standalone panel")
    a = create("plugin-a:tracker", { width = 500, height = 500 })
    expect(a._nisGroup, b._nisGroup, "group restores in reverse plugin creation order")
    expect(a._nisGroup.active, b, "locked startup restores the selected tab")
    expect(a._nisGroup.members[1], a, "saved tab order restores")
    expect(a._nisGroup.members[2], b, "reordered tab remains last")
    expect(a.root.hidden, true, "restored inactive page is hidden")
    expectRect(a.root, 500, 100, 340, 260, "restored members share saved bounds")

    b:Destroy()
    a:SetSize(360, 280)
    b = create("plugin-b:tracker")
    expectRect(b.root, 500, 100, 360, 280, "absent plugin follows changes to its saved group")
    expect(a._nisGroup, b._nisGroup, "plugin remount rejoins its saved group")
    a:Undock()
    expect(saved("plugin-a:tracker").group, nil, "explicit undock persists")
    a:Destroy()
    b:Destroy()
    restart()
    a = create("plugin-a:tracker", { dockTo = "plugin-b:tracker" })
    b = create("plugin-b:tracker", { dockTo = "plugin-a:tracker" })
    expect(a._nisGroup, nil, "new defaults cannot reset a previously declared panel")
    expect(b._nisGroup, nil, "saved standalone state overrides default docking")
    a:Destroy()
    b:Destroy()

    a = create("late:a", { dockTo = "late:b" })
    b = create("late:b", { x = 500, width = 300, height = 240 })
    expect(a._nisGroup, b._nisGroup, "first-use default docking waits for the target")
    expect(a._nisGroup.active, a, "default docking selects the incoming panel")
    expectRect(a.root, 500, 100, 300, 240, "default docking adopts target bounds")
    local c = create("late:c", { dockTo = "late:b" })
    expect(#c._nisGroup.members, 3, "first-use defaults can extend a saved group")
    c:Hide()
    expect(saved("late:c").group, nil, "hiding a panel persists its explicit removal")
    c:Destroy()
    b:Destroy()
    a:Destroy()
    restart()
    a = create("late:a")
    c = create("late:c", { dockTo = "late:b" })
    b = create("late:b")
    expect(c._nisGroup, nil, "hidden panel's old default is not reapplied")
    expect(#a._nisGroup.members, 2, "remaining group survives shutdown and a missing member")
    a:Destroy()
    b:Destroy()
    c:Destroy()

    locked = false
    a = create("drag:a")
    begin(a)
    move(a, 450, 450)
    expect(saved("drag:a").x, 100, "drag preview never persists transient coordinates")
    a:_CancelDrag()
    expect(saved("drag:a").x, 100, "cancelled drag keeps saved coordinates")
    begin(a)
    move(a, 450, 450)
    release(a)
    expect(saved("drag:a").x, a.root.x, "drag release persists committed position")
    expect(saved("drag:a").y, a.root.y, "drag release persists committed vertical position")
    a:Destroy()
    restart()
    a = create("drag:a")
    expectRect(a.root, 320, 444, 260, 180, "dragged position restores after restart")
    a:Destroy()

    a = create("pending:a", { dockTo = "pending:b" })
    a:Undock()
    b = create("pending:b")
    expect(a._nisGroup, nil, "explicit undock cancels an unresolved first-use default")
    a:Destroy()
    b:Destroy()

    -- A saved target may be absent when a new default member is declared.
    a = create("absent:target", { x = 500, width = 300, height = 240 })
    a:Destroy()
    b = create("absent:source", { dockTo = "absent:target" })
    expectRect(b.root, 500, 100, 300, 240, "first-use docking adopts an absent target's saved bounds")
    b:Destroy()
    a = create("absent:target")
    b = create("absent:source")
    expect(a._nisGroup, b._nisGroup, "absent target eventually restores the default group")
    expectRect(a.root, 500, 100, 300, 240, "waiting member teardown cannot reset saved target geometry")
    a:Destroy()
    b:Destroy()

    -- Tab tear-out is transactional: only a valid drop forgets the old group.
    a = create("gesture:a")
    b = create("gesture:b", { x = 500, height = 240 })
    expect(a:DockTo(b), true, "persistent tab gesture starts grouped")
    local originalGroup = saved("gesture:a").group
    for _, commit in ipairs({ false, true }) do
        local tab = a._nisTabs.tabs[2].hit
        local pointer = { x = tab.x + 12, y = tab.y + 12 }
        Mouse.GetPosition = function() return pointer end
        fire(tab, ui.Hook.ONCLICK, 12, 12)
        pointer = { x = 200, y = 500 }
        fire(tab, ui.Hook.ONHOLD, 12, 100)
        expect(saved("gesture:a").group, originalGroup, "tab tear-out preview retains saved nesting")
        if commit then fire(tab, ui.Hook.ONRELEASE)
        else emit("KeyDown", { gameKey = GameKey.ESCAPE }) end
        expect(saved("gesture:a").group == nil, commit, "tab gesture saves only committed nesting")
    end
    Mouse.GetPosition = function() return nil end
    a:Destroy()
    b:Destroy()
    restart()
    a = create("gesture:a", { dockTo = "gesture:b" })
    b = create("gesture:b")
    expect(a._nisGroup, nil, "committed tab tear-out remains standalone after restart")
    expect(b._nisGroup, nil, "tear-out survivor remains standalone after restart")
    a:Destroy()
    b:Destroy()

    -- Constructor limits continue to apply to a restored layout.
    a = create("limits:a")
    b = create("limits:b", { x = 500, width = 300, height = 240 })
    expect(a:DockTo(b), true, "limits scenario starts grouped")
    a:Destroy()
    b:Destroy()
    restart()
    a = create("limits:a", { maxWidth = 280 })
    b = create("limits:b", { maxWidth = 270 })
    expect(a._nisGroup, b._nisGroup, "compatible changed limits retain nesting")
    expect(a.root.width, 270, "restored width obeys the tightest current limit")
    expect(b.root.width, 270, "restored members retain common constrained width")
    a:Destroy()
    b:Destroy()

    a = create("selection:absent", { x = 500, height = 240 })
    b = create("selection:remaining")
    c = create("selection:detached")
    expect(b:DockTo(a), true, "selection scenario forms its first group")
    expect(c:DockTo(b), true, "selection scenario adds a third member")
    a:Destroy()
    c:Undock()
    b:Destroy()
    c:Destroy()
    restart()
    a = create("selection:absent")
    b = create("selection:remaining")
    expect(a._nisGroup.active, b, "undocking selects the visible survivor, not an absent plugin")
    a:Destroy()
    b:Destroy()

    a = create("close:a", { onClose = function(owner) owner:Destroy() end })
    b = create("close:b", { x = 500, height = 240 })
    expect(a:DockTo(b), true, "close callback scenario starts grouped")
    begin(a)
    move(a, 200, 500)
    a:Close()
    expect(saved("close:a").group, nil, "close remains an explicit removal when its callback destroys the panel")
    expect(saved("close:a").x, 500, "close cancels the drag before saving bounds")
    b:Destroy()

    -- Plugins may receive distinct Lua handles for one native game-area parent.
    local originalParent = parent
    local alias = setmetatable({}, { __index = originalParent })
    alias.parentStatic = alias
    b = create("aliases:b", { x = 500, width = 300, height = 240 })
    parent = alias
    a = create("aliases:a")
    parent = originalParent
    expect(a:DockTo(b), true, "distinct handles for the same native parent permit docking")
    a:SetSize(320, 260)
    a:Destroy()
    b:Destroy()
    restart()
    b = create("aliases:b")
    parent = alias
    a = create("aliases:a")
    parent = originalParent
    expect(a._nisGroup, b._nisGroup, "saved grouping restores across native parent aliases")
    expect(a._nisGroup.active, a, "parent aliases retain the saved active tab")
    expectRect(a.root, 500, 100, 320, 260, "parent aliases retain shared saved bounds")
    a:Destroy()
    b:Destroy()
end

-- Native groups retain the actual panel tree through selection and drag-out.
do
    local oldParent, oldGet, oldInterface = parent, ui.Interfaces.GetComponent, ui.Interfaces.GetInterface
    local nativeNodes = {}
    local function nativeNode(interfaceID, staticID, owner, x, y, width, height)
        local node = component(nil, "native")
        node.type = 20
        node.interfaceID, node.staticID = interfaceID, staticID
        node.parentStatic = nil
        Interfaces.component(node)
        node.parent = owner
        if owner then
            owner.children[#owner.children + 1] = node
            owner.renderChildren[#owner.renderChildren + 1] = node
        end
        node.position = { x = x, y = y, xParentPc = 0, yParentPc = 0, xSelfPc = 0, ySelfPc = 0 }
        node.size = { width = width, height = height, widthParentPc = 0, heightParentPc = 0 }
        node.nativeShown = true
        setmetatable(node, { __index = function(self, key)
            if key == "xyGlobal" then
                local origin = self.parent and self.parent.xyGlobal or { x = 0, y = 0 }
                return { x = origin.x + self.x, y = origin.y + self.y }
            elseif key == "visibleGlobal" then
                return self.nativeShown and self.visible ~= false and not self.hidden
                    and (not self.parent or self.parent.visibleGlobal ~= false)
            end
        end })
        function node:SetPos(px, py, xp, yp, xs, ys)
            self.position = { x = px, y = py, xParentPc = xp or 0, yParentPc = yp or 0,
                xSelfPc = xs or 0, ySelfPc = ys or 0 }
            self.x = px + (self.parent and self.parent.width or 0) * (xp or 0) - self.width * (xs or 0)
            self.y = py + (self.parent and self.parent.height or 0) * (yp or 0) - self.height * (ys or 0)
        end
        function node:SetSize(w, h, wp, hp)
            self.size = { width = w, height = h, widthParentPc = wp or 0, heightParentPc = hp or 0 }
            self.width = w + (self.parent and self.parent.width or 0) * (wp or 0)
            self.height = h + (self.parent and self.parent.height or 0) * (hp or 0)
            local pos = self.position
            self.x = pos.x + (self.parent and self.parent.width or 0) * pos.xParentPc - self.width * pos.xSelfPc
            self.y = pos.y + (self.parent and self.parent.height or 0) * pos.yParentPc - self.height * pos.ySelfPc
            for _, child in ipairs(self.children) do child:Relayout() end
            self:EmitResize()
        end
        function node:Relayout()
            local p, s = self.position, self.size
            self:SetPos(p.x, p.y, p.xParentPc, p.yParentPc, p.xSelfPc, p.ySelfPc)
            self:SetSize(s.width, s.height, s.widthParentPc, s.heightParentPc)
        end
        function node:IterateStaticComponents(callback)
            for _, child in ipairs(self.children) do
                if child.categoryID == -1 and callback(child, child.visibleGlobal) then return end
            end
        end
        function node:MoveToFront()
            if not self.parent then return end
            removeChild(self.parent, self)
            assert(removeRenderChild(self.parent, self), "native frame remains in its parent's render list")
            self.parent.children[#self.parent.children + 1] = self
            self.parent.renderChildren[#self.parent.renderChildren + 1] = self
        end
        node.x, node.y, node.width, node.height = x, y, width, height
        local retired = nativeNodes[(interfaceID << 16) | staticID]
        if retired then
            removeChild(retired.parent, retired)
            removeRenderChild(retired.parent, retired)
            retired.destroyed = true
        end
        nativeNodes[(interfaceID << 16) | staticID] = node
        return node
    end
    local function rendered(node)
        while node do
            if node.hidden or node.visibleGlobal == false then return false end
            local owner, found = node.parent, false
            if owner then
                for _, child in ipairs(owner.renderChildren) do
                    if child == node then found = true; break end
                end
                if not found then return false end
            end
            node = owner
        end
        return true
    end
    local function drawable(label, owner)
        if not rendered(label) then return false end
        local top = label.y - owner.scrollY
        return label.width > 0 and label.height > 0 and owner.viewport.width > 0
            and top < owner.viewport.height and top + label.height > 0
    end
    local area = nativeNode(1477, 61, nil, 80, 40, 1000, 700)
    local frames = {}
    function area:IterateStaticComponents(callback)
        for _, frame in ipairs(frames) do if callback(frame, frame.visibleGlobal) then break end end
    end
    local function host(first, name, shown, icons)
        local frame = nativeNode(1477, first, area, 500, 100, 379, 357)
        frame.nativeShown = shown
        frames[#frames + 1] = frame
        local body = nativeNode(1477, first + 2, frame, 4, 44, 371, 309)
        nativeNode(1477, first + 3, frame, 4, 44, 371, 309)
        local scroll = nativeNode(1477, first + 4, frame, 4, 44, 371, 309)
        nativeNode(1477, first + 7, frame, 0, 16, 379, 28)
        local tabs = nativeNode(1477, first + 8, frame, 4, 16, 371, 28)
        tabs.visible = true
        nativeNode(1477, first + 9, frame, 4, 16, 371, 28)
        local prefix, suffix = name:match("^(.+_WINDOW)(.*)$")
        if not prefix then
            prefix, suffix = name == "NOTES" and "NOTES_WINDOW" or "ABILITY_WINDOW",
                name == "NOTES" and "" or "_" .. name
        end
        id.Component["TOPLEVEL_V2__" .. prefix .. suffix] = (1477 << 16) | first
        id.Component["TOPLEVEL_V2__" .. prefix .. "_CONTENT" .. suffix] = (1477 << 16) | (first + 2)
        id.Component["TOPLEVEL_V2__" .. prefix .. "_EDIT_BLOCK" .. suffix] = (1477 << 16) | (first + 3)
        id.Component["TOPLEVEL_V2__" .. prefix .. "_SCROLL" .. suffix] = (1477 << 16) | (first + 4)
        id.Component["TOPLEVEL_V2__" .. prefix .. "_TABS" .. suffix] = (1477 << 16) | (first + 8)
        id.Component["TOPLEVEL_V2__" .. prefix .. "_TAB_BACKGROUND" .. suffix] = (1477 << 16) | (first + 7)
        local result = { frame = frame, body = body, scroll = scroll, tabs = tabs }
        function result:rebuild(order, selected)
            for _, child in ipairs({ table.unpack(tabs.children) }) do child:Destroy() end
            self.backgrounds = {}
            for index, iconID in ipairs(order) do
                local background = component(tabs, "sprite", 0, (index - 1) * 4)
                background.type, background.visible, background.nativeShown = 3, true, true
                setmetatable(background, getmetatable(tabs))
                background:SetPos((index - 1) * 44, 0)
                background:SetSize(44, 28)
                background.spriteID = index == selected
                    and id.Sprite.RS3_CHILD_TAB_SELECTED or id.Sprite.RS3_CHILD_TAB_UNSELECTED
                self.backgrounds[index] = background
                local icon = component(tabs, "sprite", 0, (index - 1) * 4 + 1)
                icon.type, icon.visible, icon.nativeShown = 3, true, true
                setmetatable(icon, getmetatable(tabs))
                icon:SetPos((index - 1) * 44 + 10, 2)
                icon:SetSize(24, 24)
                icon.spriteID = iconID
            end
        end
        result:rebuild(icons or { 9001, 9002 }, icons and 1 or (shown and 1 or 2))
        return result
    end
    local notes = host(545, "NOTES", true)
    local ranged = host(158, "RANGED", false)
    local magic = host(2000, "MAGIC", false, { 9003 })
    magic.frame:SetPos(50, 200)
    local wrapper = nativeNode(1417, 3, notes.body, 0, 0, 371, 309)
    wrapper:SetSize(0, 0, 1, 1)
    id.Component.NOTES_CHILD__WRAPPER = (1417 << 16) | 3
    -- Actual standalone roots and anchors supplied by the user's read-only report.
    local standaloneHosts = {
        { label = "Inventory", frame = 103, name = "INVENTORY_WINDOW", icon = 18772,
            owner = 1473, static = 0, rootName = "TOPLEVEL_V2_INVENTORY__MAIN_LAYER", width = 204, height = 292 },
        { label = "Prayer", frame = 136, name = "PRAYER_WINDOW", icon = 18774,
            owner = 1458, static = 4, rootName = "TOPLEVEL_V2_PRAYER__MAIN_LAYER", width = 371, height = 207 },
        { label = "Equipment", frame = 114, name = "WORN_WINDOW", icon = 18773,
            owner = 1464, static = 0, rootName = "TOPLEVEL_V2_WORN__CONTENT_LAYER", width = 165, height = 293,
            centred = true },
        { label = "Chat", frame = 420, name = "CHAT_WINDOW", icon = 18754,
            owner = 137, static = 0, rootName = "CHATDEFAULT__CHAT_CONTAINER", width = 536, height = 292 },
        { label = "Stats", frame = 300, name = "STATS_WINDOW", icon = 24429,
            owner = 1466, static = 0, rootName = "STATS_CHILD__CANVAS", width = 371, height = 209 },
    }
    for _, captured in ipairs(standaloneHosts) do
        local item = host(captured.frame, captured.name, false, { captured.icon })
        captured.host = item
        item.frame:SetSize(captured.width + 8, captured.height + 20)
        item.tabs.visible = false
        item.tabs:SetSize(captured.width, 28)
        item.body:SetPos(4, 16); item.body:SetSize(captured.width, captured.height)
        item.scroll:SetPos(4, 16); item.scroll:SetSize(captured.width, captured.height)
        local edit = nativeNodes[(1477 << 16) | (captured.frame + 3)]
        edit:SetPos(4, 16); edit:SetSize(captured.width, captured.height)
        captured.root = nativeNode(captured.owner, captured.static, item.body,
            0, 0, captured.width, captured.height)
        captured.root:SetSize(0, 0, 1, 1)
        local anchor = captured.centred and 0.5 or 0
        captured.root:SetPos(0, 0, anchor, anchor, anchor, anchor)
        id.Component[captured.rootName] = (captured.owner << 16) | captured.static
    end
    local prayerListeners = nativeNode(1458, 1, standaloneHosts[2].host.body, 0, 0, 1, 1)
    id.Component.TOPLEVEL_V2_PRAYER__LISTENERS_AND_TIMERS = (1458 << 16) | 1
    -- Captured CHAT_WINDOW_2/3 have no *_SCROLL component at all.
    local chat = host(431, "CHAT_WINDOW_2", false, { 18755, 18756 })
    local chatPeer = host(441, "CHAT_WINDOW_3", false, { 18755, 18756 })
    for _, item in ipairs({ chat, chatPeer }) do
        local packed = (1477 << 16) | (item.frame.staticID + 4)
        nativeNodes[packed] = nil
        removeChild(item.frame, item.scroll)
        removeRenderChild(item.frame, item.scroll)
        item.scroll:Destroy()
        item.scroll = nil
    end
    id.Component.TOPLEVEL_V2__CHAT_WINDOW_SCROLL_2 = nil
    id.Component.TOPLEVEL_V2__CHAT_WINDOW_SCROLL_3 = nil
    setmetatable(id.Component, { __pairs = function(values)
        local name
        return function()
            name = next(values, name)
            if name then return values[name], name end
        end
    end })
    function ui.Interfaces:GetComponent(first, second, ...)
        if select("#", ...) == 0 then
            local packed = second and ((first << 16) | second) or first
            if nativeNodes[packed] then return nativeNodes[packed] end
        end
        return oldGet(self, first, second, ...)
    end
    function ui.Interfaces:GetInterface(number)
        local loaded = oldInterface(self, number)
        if loaded and (number == 1477 or number == 1417) then
            -- Interface wrappers need not have stable Lua object identity.
            return setmetatable({ id = number }, { __index = loaded })
        end
        return loaded
    end
    parent = area
    local nativePanel = NisPanel.new(area, {
        categoryID = "auto", x = 50, y = 450, width = 280, height = 180, id = "native:retained",
    })
    local title = nativePanel:AddTitle("Retained native page")
    local rows = {}
    for index = 1, 30 do rows[index] = nativePanel:AddText("Native retained row " .. index) end
    local root, content = nativePanel.root, nativePanel.content
    local overlay = component(area, "overlay")
    nativePanel:_RegisterOverlay(overlay, function() return true end)
    begin(nativePanel); move(nativePanel, 650, 250)
    expect(nativePanel.dragState.nativeTarget == nil, true, "native body overlap is not a tab-band drop target")
    nativePanel:_CancelDrag()
    local bounded = NisPanel.new(area, { categoryID = "auto", maxWidth = 300 })
    expect(bounded:DockTo(notes.frame), false, "native viewport exceeding member limits is rejected")
    expect(notes.body.hidden, false, "rejected native docking leaves native content visible")
    bounded:Destroy()
    begin(nativePanel)
    move(nativePanel, 650, 130)
    expectRect(nativePanel.dragFeedback.active, 500, 100, 379, 357, "native band previews its actual frame")
    release(nativePanel)
    expect(nativePanel._nisNative ~= nil, true, "header drop joins the native group")
    expect(nativePanel.root, root, "native docking retains the original root")
    expect(nativePanel.content, content, "native docking retains consumer content")
    expect(nativePanel.surface.container.y, 0, "native body has no nested panel inset")
    expect(nativePanel.dragLayer.hidden, true, "docked panel has no standalone header capture")
    expect(notes.body.hidden, true, "selected own tab conceals native content")
    emit("Logic")
    expect(drawable(title, nativePanel), true, "native docking keeps an actual title visible inside the viewport")
    expectRect(nativePanel.viewport, 0, 0, 353, 309, "native docking retains a nonzero clipped content viewport")
    local bodyIndex, overlayIndex
    for index, child in ipairs(area.children) do
        if child == root then bodyIndex = index end
        if child == overlay then overlayIndex = index end
    end
    expect(overlayIndex > bodyIndex, true, "selected native body's input overlays remain above its body")
    notes.frame:SetPos(520, 120)
    emit("Logic")
    expectRect(nativePanel.root, 524, 164, 371, 309, "retained native body follows host movement in parent units")
    notes.frame:SetPos(500, 100)
    emit("Logic")
    local function nativeClick(tabs)
        for _, callback in pairs(tabs.namedSubscriptions[ui.Hook.ONCLICK] or {}) do
            expect(callback(tabs, 10, 10), true, "native observer preserves native handling")
        end
        emit("Logic")
    end
    local function nativeLock(value, repaintBeforeNotification, repaintAfterLogic)
        local function repaint()
            -- Native lock can remove addon render attachments while public
            -- handles, IDs and the logical geometry tree remain available.
            local function retireAddonRenderEntries(node)
                local kept = {}
                for _, child in ipairs(node.children) do
                    retireAddonRenderEntries(child)
                    if child.nativeShown ~= nil then kept[#kept + 1] = child end
                end
                node.renderChildren = kept
            end
            for index, host in ipairs({ notes, ranged }) do
                local tabTop, bodyTop = value and 4 or 16, value and 32 or 44
                local height = value and 321 or 309
                host.tabs:SetPos(4, tabTop)
                nativeNodes[(1477 << 16) | (host.frame.staticID + 7)]:SetPos(0, tabTop)
                host.body:SetPos(4, bodyTop)
                host.body:SetSize(371, height)
                host.scroll:SetPos(4, bodyTop)
                host.scroll:SetSize(371, height)
                host.body.hidden, host.scroll.hidden = false, false
                for slot, background in ipairs(host.backgrounds) do
                    background.spriteID = slot == index
                        and id.Sprite.RS3_CHILD_TAB_SELECTED or id.Sprite.RS3_CHILD_TAB_UNSELECTED
                end
                retireAddonRenderEntries(host.frame)
                if host.frame.visibleGlobal then host.frame:MoveToFront() end
            end
        end
        if repaintBeforeNotification then repaint() end
        locked = value; transmit(12)
        if repaintAfterLogic then emit("Logic") end
        if not repaintBeforeNotification then repaint() end
        emit("Logic")
    end
    nativePanel:SetScrollPosition(80)
    local lockedPeer = NisPanel.new(area, { categoryID = "auto", x = 20, y = 20 })
    expect(lockedPeer:DockTo(nativePanel), true, "lock scenario starts with multiple own native tabs")
    nativePanel:SelectTab()
    local nativeBinding = nativePanel._nisNative
    nativeLock(true, true)
    expect(nativePanel._nisNative, nativeBinding, "locking retains native membership")
    expect(drawable(rows[4], nativePanel), true, "locking native chrome does not discard the selected content")
    expect(lockedPeer.root.hidden, true, "locking does not reveal an inactive nested page")
    expectRect(nativePanel.root, 504, 132, 371, 321, "locked native body follows its reflowed slot")
    local target = hitAt(area, root.x + 10, root.y + 100)
    while target and target ~= root do target = target.parent end
    expect(target, root, "locked body input reaches its visible retained content above native chrome")
    local frontMoves = root.frontMoves
    emit("Logic")
    expect(root.frontMoves, frontMoves, "idle native ticks do not continually raise the body")
    expect(nativePanel.headerLeft.hidden, true, "native locking cannot reveal nested standalone chrome")
    expect(nativePanel.dragLayer.hidden, true, "native locking keeps the standalone capture suppressed")
    local lockedTab = nativeBinding.tabs[nativeBinding.group.current].hit
    expect(hitAt(area, lockedTab.x + 10, lockedTab.y + 10), lockedTab,
        "locked synthetic tab input stays above native chrome")
    local visibleTab = nativeBinding.tabs[nativeBinding.group.current]
    expect(rendered(visibleTab.background), true, "locked tab artwork remains drawn with its input target")
    local artOrigin, frameOrigin = visibleTab.visual.xyGlobal, visibleTab.host.frame.xyGlobal
    expect(artOrigin.x, frameOrigin.x + visibleTab.visual.x, "locked artwork follows the native frame origin")
    expect(artOrigin.y, frameOrigin.y + visibleTab.host.tabs.y, "locked artwork follows native header reflow")
    fire(lockedTab, ui.Hook.ONCLICK, 10, 10)
    fire(lockedTab, ui.Hook.ONHOLD, 200 - lockedTab.x, 450 - lockedTab.y)
    fire(lockedTab, ui.Hook.ONRELEASE)
    expect(nativePanel._nisNative, nativeBinding, "locked tab input cannot undock a nested page")
    expect(nativePanel.dragState, nil, "locked nested tabs cannot start placement")
    expect(nativePanel._nisTabPress, nil, "locked nested tabs cannot retain a drag press")
    lockedPeer:SelectTab()
    expect(drawable(rows[4], nativePanel), false, "locked own-tab switching hides the previous content")
    nativePanel:SelectTab()
    expect(drawable(rows[4], nativePanel), true, "own tabs remain selectable while locked")
    nativeClick(notes.tabs)
    expect(nativePanel.root.hidden, true, "real native tabs remain selectable while locked")
    nativeLock(false, false)
    expect(nativePanel.root.hidden, true, "unlocking does not replace the selected native page")
    nativePanel:SelectTab()
    nativeLock(true, false, true)
    expect(drawable(rows[4], nativePanel), true, "a repaint after the lock notification retains own selection")
    expect(rendered(nativeBinding.tabs[nativeBinding.group.current].background), true,
        "late native repaint cannot discard the visible synthetic tab")
    expect(notes.body.hidden, true, "late native repaint cannot reveal native content over the own page")
    expect(hitAt(area, lockedTab.x + 10, lockedTab.y + 10), lockedTab,
        "late native repaint leaves matching visible tab input above native chrome")
    nativeLock(false, true)
    expect(drawable(rows[4], nativePanel), true, "unlocking retains the selected nested content")
    expect(nativePanel.scrollY, 80, "lock and unlock retain scroll position")
    expect(notes.backgrounds[1].spriteID, id.Sprite.RS3_CHILD_TAB_UNSELECTED,
        "unlock repaint restores exclusive PrettyUI tab highlighting")
    lockedPeer:Destroy()
    nativeLock(true, false)
    local failedBinding = nativePanel._nisNative
    local failedTab = failedBinding.tabs[failedBinding.group.current].hit
    local moveRoot = root.MoveToFront
    root.MoveToFront = function() error("injected body ordering failure") end
    fire(failedTab, ui.Hook.ONCLICK, 10, 10)
    expect(failedTab.destroyed, nil, "selection failure cannot destroy its currently dispatching input target")
    expect(nativePanel._nisNative, failedBinding, "selection failure waits for Logic before native teardown")
    root.MoveToFront = moveRoot
    emit("Logic")
    expect(nativePanel._nisNative, nil, "Logic tears down the failed native binding")
    expect(failedTab.destroyed, true, "deferred teardown releases input after dispatch")
    nativeLock(false, false)
    expect(nativePanel:DockTo(notes.frame), true, "failed native selection leaves retained content usable")
    nativePanel:SetScrollPosition(80)
    local scrollY = nativePanel.scrollY
    local function retainedPage(reason)
        expect(nativePanel._nisNative ~= nil, true, reason .. " keeps native membership")
        expect(nativePanel.root, root, reason .. " retains the actual panel root")
        expect(nativePanel.content, content, reason .. " retains consumer controls")
        expect(nativePanel.scrollY, scrollY, reason .. " preserves scroll position")
        expect(drawable(rows[4], nativePanel), true, reason .. " leaves real content drawable")
    end
    local sameIDBackground = notes.backgrounds[1]
    notes:rebuild({ 9001, 9002 }, 1)
    ranged:rebuild({ 9001, 9002 }, 2)
    emit("Logic")
    retainedPage("unchanged-ID native tab replacement")
    expect(next(sameIDBackground.namedSubscriptions[ui.Hook.ONCLICK] or {}), nil,
        "unchanged-ID replacement releases the retired observer")
    nativeClick(notes.backgrounds[1])
    expect(nativePanel.root.hidden, true, "rebuilt same-ID native tab clicks still select native content")
    nativePanel:SelectTab()
    local retiredBackground = notes.backgrounds[1]
    notes:rebuild({ 9002, 9001 }, 2)
    ranged:rebuild({ 9002, 9001 }, 1)
    emit("Logic")
    retainedPage("native tab rebuild/reorder")
    expect(next(retiredBackground.namedSubscriptions[ui.Hook.ONCLICK] or {}), nil,
        "native rebuild removes observers from retired tab children")
    local badge = component(notes.tabs, "sprite", 0, 12)
    badge.visible = false
    emit("Logic")
    retainedPage("native badge membership change")
    badge:Destroy()
    emit("Logic")
    notes.frame.nativeShown = false
    emit("Logic")
    expect(nativePanel._nisNative ~= nil, true, "transient native drag visibility does not discard the own page")
    expect(drawable(rows[4], nativePanel), false, "transient native drag suspends the retained page's drawing")
    expect(overlay.hidden, true, "transient native drag removes the own page's sibling input overlays")
    expect(rendered(nativePanel._nisNative.tabs[nativePanel._nisNative.group.current].background), false,
        "transient native visibility loss hides overlay artwork as well as input")
    notes.frame.nativeShown = true
    emit("Logic")
    retainedPage("native drag visibility return")
    notes:rebuild({ 9002, 9001, 9003 }, 2)
    ranged:rebuild({ 9002, 9001, 9003 }, 1)
    magic:rebuild({ 9002, 9001, 9003 }, 3)
    magic.frame:SetPos(500, 100)
    emit("Logic")
    retainedPage("native group merge")
    notes.frame.nativeShown, magic.frame.nativeShown = false, true
    nativeClick(magic.tabs)
    expect(nativePanel.root.hidden, true, "a newly merged native page keeps native selection authority")
    nativePanel:SelectTab()
    retainedPage("own page selected from newly merged native frame")
    notes:rebuild({ 9001, 9003 }, 1)
    magic:rebuild({ 9001, 9003 }, 2)
    ranged:rebuild({ 9002 }, 1)
    ranged.frame:SetPos(40, 200)
    emit("Logic")
    retainedPage("native group split")
    expect(ranged.body.hidden, false, "split-away native host has its original body visibility")
    notes:rebuild({ 9001, 9002 }, 1)
    ranged:rebuild({ 9001, 9002 }, 2)
    ranged.frame:SetPos(500, 100)
    magic:rebuild({ 9003 }, 1)
    magic.frame:SetPos(50, 200)
    notes.frame.nativeShown, magic.frame.nativeShown = true, false
    emit("Logic")
    retainedPage("native arrangement restored")
    nativeClick(notes.tabs)
    expect(nativePanel.root.hidden, true, "same-selected native click hides the own page")
    expect(overlay.hidden, true, "native return suppresses sibling popouts")
    expect(notes.body.hidden, false, "native return restores its body")
    expect(drawable(rows[4], nativePanel), false, "native return prevents the retained row drawing through its hidden page")
    nativePanel:SelectTab()
    expect(nativePanel.scrollY, scrollY, "native selection round-trip retains scroll")
    expect(drawable(rows[4], nativePanel), true, "own-tab return makes the retained scrolled row drawable again")
    ranged.body = nativeNode(1477, 160, ranged.frame, 4, 44, 371, 309)
    notes.frame.nativeShown, ranged.frame.nativeShown = false, true
    emit("Logic")
    expect(nativePanel.root.hidden, true, "native frame selection restores native page authority")
    nativePanel:SelectTab()
    expect(ranged.body.hidden, true, "own page can be selected from the other native frame")
    expect(nativePanel.content, content, "native frame changes do not rebuild content")
    local function captureTab()
        for _, child in ipairs(area.children) do
            if child ~= overlay and child ~= nativePanel.dragLayer and not child.hidden
                and child.width == 40 and child.height == 28 and child.subscriptions[ui.Hook.ONHOLD] then
                return child
            end
        end
        error("native tab exposes no drag capture")
    end
    local capture = captureTab()
    fire(capture, ui.Hook.ONCLICK, 10, 10)
    local captureX, captureY = capture.x, capture.y
    fire(capture, ui.Hook.ONHOLD, 200 - captureX, 450 - captureY)
    expect(nativePanel._nisNative, nil, "dragging out detaches native membership")
    expect(nativePanel.dragState ~= nil, true, "drag-out enters normal placement")
    emit("KeyDown", { gameKey = GameKey.ESCAPE })
    expect(nativePanel._nisNative ~= nil, true, "escape restores the native membership")
    expect(nativePanel.content, content, "cancelled drag-out retains content")
    expect(ranged.body.hidden, true, "cancelled drag restores native concealment")
    capture = captureTab()
    fire(capture, ui.Hook.ONCLICK, 10, 10)
    captureX, captureY = capture.x, capture.y
    fire(capture, ui.Hook.ONHOLD, 200 - captureX, 450 - captureY)
    fire(capture, ui.Hook.ONRELEASE, 200, 450)
    expect(nativePanel._nisNative, nil, "valid drop commits a standalone panel")
    expect(nativePanel.root, root, "committed native drag-out retains the root")
    expect(nativePanel.content, content, "committed native drag-out retains content")
    expect(ranged.body.hidden, false, "dragging the last tab out restores native content")
    expect(capture.destroyed, true, "committed drag-out releases the retained capture")
    local freeX, freeY, freeWidth, freeHeight = root.x, root.y, root.width, root.height
    begin(nativePanel); move(nativePanel, 650, 130); release(nativePanel)
    expect(nativePanel._nisNative ~= nil, true, "detached panel can be dragged back into the native group")
    local peer = NisPanel.new(area, { categoryID = "auto", x = 20, y = 20 })
    expect(peer:DockTo(nativePanel), true, "another panel can join the same native group")
    expect(nativePanel.root.hidden, true, "selecting the new own tab hides the previous body")
    expect(peer.root.hidden, false, "incoming native member is selected")
    nativePanel:SelectTab()
    peer:Destroy()
    expect(nativePanel.root.hidden, false, "destroying an inactive native member preserves selection")
    expect(ranged.body.hidden, true, "removing one own tab preserves native concealment for the survivor")
    notes.frame.visible, ranged.frame.visible = false, false
    emit("Logic")
    expect(nativePanel._nisNative, nil, "closing every native host restores a standalone panel")
    expect(drawable(rows[4], nativePanel), true, "closed native group cannot make retained consumer content disappear")
    expectRect(nativePanel.root, freeX, freeY, freeWidth, freeHeight, "closed native group restores standalone bounds")
    local restoredIndex, nativeIndex
    for index, child in ipairs(area.children) do
        if child == root then restoredIndex = index end
        if child == ranged.frame then nativeIndex = index end
    end
    expect(restoredIndex > nativeIndex, true, "automatic native detach raises the restored standalone body")
    notes.frame.visible, ranged.frame.visible = true, true
    expect(nativePanel:DockTo(ranged.frame), true, "reopened native group accepts the retained panel again")
    nativePanel:Undock()
    expect(nativePanel._nisNative, nil, "explicit undock removes native binding")
    expectRect(nativePanel.root, freeX, freeY, freeWidth, freeHeight,
        "native undock restores the last standalone placement, not the docking ghost")
    expect(ranged.body.hidden, false, "last member restores the native body")
    expect(nativePanel.surface.left.hidden, false, "undock restores standalone frame artwork")
    expect(nativePanel.dragLayer.hidden, false, "undock restores the standalone gesture")
    expect(next(notes.tabs.namedSubscriptions[ui.Hook.ONCLICK] or {}), nil, "undock removes native click observers")
    notes.frame.nativeShown, ranged.frame.nativeShown = true, false
    notes.tabs.visible = false
    notes.body:SetPos(4, 16)
    notes.body:SetSize(371, 337)
    notes.scroll:SetPos(4, 16)
    notes.scroll:SetSize(371, 337)
    begin(nativePanel); move(nativePanel, 300, 500); move(nativePanel, 650, 130); release(nativePanel)
    expect(nativePanel._nisNative ~= nil, true, "standalone Notes synthesizes a native and own tab row")
    expect(wrapper.y, 28, "standalone docking reserves one band in the embedded wrapper")
    expect(wrapper.height, 309, "standalone wrapper shrinks without moving individual native controls")
    expect(notes.body.y, 16, "standalone docking does not rewrite the script-owned outer slot")
    expect(wrapper.hidden, true, "own selection conceals the whole standalone native wrapper")
    nativePanel:Undock()
    expect(wrapper.y, 0, "standalone detach restores the native wrapper origin")
    expect(wrapper.height, 337, "standalone detach restores the native wrapper height")
    expect(wrapper.size.heightParentPc, 1, "standalone detach preserves the original height anchor")
    expect(wrapper.hidden, false, "standalone detach restores the native wrapper visibility")
    begin(nativePanel); move(nativePanel, 300, 500); move(nativePanel, 650, 130); release(nativePanel)
    expect(wrapper.hidden, true, "shutdown scenario starts with a concealed native page")
    require("src/core/nis_native").shutdown()
    expect(nativePanel._nisNative, nil, "library shutdown detaches retained native members")
    expect(wrapper.y, 0, "library shutdown restores the native wrapper inset")
    expect(wrapper.hidden, false, "library shutdown restores native visibility")
    expect(nativePanel.content, content, "library shutdown does not destroy consumer controls")
    nativePanel:_UnregisterOverlay(overlay)
    overlay:Destroy()
    nativePanel:Destroy()

    do
        notes.frame.nativeShown = false
        for _, captured in ipairs(standaloneHosts) do
            local item, embedded = captured.host, captured.root
            local panelID = "native-standalone:" .. captured.label
            local owner = NisPanel.new(area, { id = panelID, categoryID = "auto",
                x = 30, y = 450, width = 280, height = 180 })
            local content = owner.content
            local title = owner:AddTitle(captured.label .. " native host")
            item.frame.nativeShown = true
            embedded:SetSize(-10, 0, 1, 1)
            expect(owner:DockTo(item.frame), false, captured.label .. " partial root cannot establish safe reflow")
            embedded:SetSize(0, 0, 1, 1)
            begin(owner)
            move(owner, item.frame.x + item.tabs.x + 50, item.frame.y + item.tabs.y + 8)
            release(owner)
            expect(owner._nisNative ~= nil, true, captured.label .. " standalone band accepts its actual embedded root")
            expect(owner._nisNative.group.hosts[1].nativeIcon, captured.icon, captured.label .. " retains native icon")
            expect(item.tabs.visible, false, captured.label .. " client-hidden native tabs stay hidden")
            expectRect(embedded, 0, 28, captured.width, captured.height - 28,
                captured.label .. " reserves exactly one complete band")
            expect(embedded.hidden, true, captured.label .. " own page conceals embedded native content")
            expect(item.scroll.hidden, true, captured.label .. " own page conceals outer scrollbar input")
            local edit = nativeNodes[(1477 << 16) | (captured.frame + 3)]
            expect(edit.hidden, true, captured.label .. " own page conceals the edit layer")
            expect(prayerListeners.hidden, false, "Prayer timers remain live while its main page is concealed")
            expectRect(prayerListeners, 0, 0, 1, 1, "Prayer listeners are not inset or resized")
            emit("Logic")
            expect(drawable(title, owner), true, captured.label .. " retained consumer content remains drawable")
            expect(owner.content, content, captured.label .. " docking retains consumer controls")
            local binding = owner._nisNative
            fire(binding.group.hosts[1].nativeTab.hit, ui.Hook.ONCLICK)
            expect(embedded.hidden, false, captured.label .. " native tab restores embedded content")
            expect(item.scroll.hidden, false, captured.label .. " native tab restores scrollbar visibility")
            expect(edit.hidden, false, captured.label .. " native tab restores edit visibility")
            owner:SelectTab()
            if captured.label == "Prayer" then
                local retainedBinding, retainedRoot = owner._nisNative, owner.root
                local nativeWrites = 0
                local function observeRoot(root)
                    local setPos = root.SetPos
                    root.SetPos = function(self, ...)
                        nativeWrites = nativeWrites + 1
                        return setPos(self, ...)
                    end
                end
                observeRoot(embedded)
                local function repaintPrayer(value, rebuild)
                    local top, height = value and 4 or 16, captured.height + (value and 12 or 0)
                    item.body:SetPos(4, top); item.body:SetSize(captured.width, height)
                    item.scroll:SetPos(4, top); item.scroll:SetSize(captured.width, height)
                    edit:SetPos(4, top); edit:SetSize(captured.width, height)
                    if rebuild then
                        embedded = nativeNode(1458, 4, item.body, 0, 0, captured.width, height)
                        embedded:SetSize(0, 0, 1, 1)
                        captured.root = embedded
                        observeRoot(embedded)
                        item:rebuild({}, 1)
                        item.tabs:SetSize(0, 0)
                    else
                        embedded:SetPos(0, 0); embedded:SetSize(0, 0, 1, 1)
                    end
                    if not value then
                        item.tabs:SetSize(captured.width, 28)
                        item:rebuild({ captured.icon }, 1)
                    end
                    -- The hidden native strip/backdrop deliberately retain y16.
                    embedded.hidden, item.scroll.hidden, edit.hidden = false, false, false
                    item.frame:MoveToFront()
                end
                local function prayerLock(value, beforeNotification, rebuild)
                    local active = retainedBinding.group.active
                    if beforeNotification then repaintPrayer(value, rebuild) end
                    locked = value; transmit(12)
                    if not beforeNotification then
                        emit("Logic"); emit("Logic")
                        repaintPrayer(value, rebuild)
                    end
                    emit("Logic")
                    expect(owner._nisNative, retainedBinding, "Prayer lock transition retains its native binding")
                    expect(owner.root, retainedRoot, "Prayer lock transition retains the populated root")
                    expect(owner.content, content, "Prayer lock transition retains consumer controls")
                    expect(retainedBinding.group.active, active, "Prayer lock transition preserves selected page")
                    local top, height = value and 4 or 16, captured.height + (value and 12 or 0)
                    expectRect(embedded, 0, 28, captured.width, height - 28, "Prayer lock reflow reapplies one native inset")
                    expectRect(owner.root, item.frame.x + 4, item.frame.y + top + 28,
                        captured.width, height - 28, "Prayer retained page follows the live content slot")
                    expect(owner.root.hidden, active ~= owner, "Prayer lock does not change own-page visibility")
                    expect(prayerListeners.visibleGlobal, true, "Prayer lock leaves listeners and timers active")
                    expectRect(prayerListeners, 0, 0, 1, 1, "Prayer lock never insets its listener root")
                    local tab = retainedBinding.tabs[retainedBinding.group.current]
                    expect(tab.visual.y, top, "Prayer synthetic artwork follows content, not stale hidden strip")
                    expect(tab.hit.y, item.frame.y + top, "Prayer tab input follows its artwork")
                    expect(require("src/core/nis_native").contains(owner, tab.hit.x + 10, tab.hit.y + 10),
                        true, "Prayer tab containment follows the current synthetic row")
                    expect(rendered(tab.background), true, "Prayer lock retains visible synthetic tab artwork")
                    if active == owner then
                        expect(drawable(title, owner), true, "Prayer lock leaves retained content drawable")
                        expect(hitAt(area, tab.hit.x + 10, tab.hit.y + 10), tab.hit,
                            "Prayer lock keeps tab input above repainted native chrome")
                    end
                    local writes = nativeWrites
                    emit("Logic"); emit("Logic")
                    expect(nativeWrites, writes, "idle Prayer ticks do not fight native layout with repeated writes")
                end
                prayerLock(true, true, false)
                fire(retainedBinding.group.hosts[1].nativeTab.hit, ui.Hook.ONCLICK)
                expect(owner.root.hidden, true, "locked Prayer native tab remains selectable")
                prayerLock(false, false, false)
                expect(embedded.hidden, false, "Prayer unlock preserves the selected native page")
                owner:SelectTab()
                local peer = NisPanel.new(area, { categoryID = "auto", x = 20, y = 20 })
                expect(peer:DockTo(owner), true, "Prayer lock regression includes an inactive own tab")
                owner:SelectTab()
                prayerLock(true, false, true)
                expect(peer.root.hidden, true, "Prayer lock rebuild does not reveal inactive retained pages")
                peer:SelectTab()
                expect(owner.root.hidden, true, "Prayer own tabs remain selectable while locked")
                owner:SelectTab()
                peer:Destroy()
                prayerLock(false, true, false)
                embedded:SetPos(1, 28)
                emit("Logic")
                expect(owner._nisNative, nil, "unexpected Prayer layout writes still detach safely")
                expectRect(embedded, 0, 0, captured.width, captured.height, "unsupported Prayer write restores native baseline")
                expect(owner:DockTo(item.frame), true, "Prayer remains usable after unsupported layout teardown")
            end
            item.body:SetSize(captured.width, captured.height + 40)
            emit("Logic")
            expectRect(embedded, 0, 28, captured.width, captured.height + 12,
                captured.label .. " embedded page follows native content resizing")
            item.body:SetSize(captured.width, captured.height)
            owner:Undock()
            expectRect(embedded, 0, 0, captured.width, captured.height, captured.label .. " detach restores full native page")
            expect(embedded.hidden, false, captured.label .. " detach restores native visibility")
            expect(item.scroll.hidden, false, captured.label .. " detach restores outer scrollbar")
            local anchor = captured.centred and 0.5 or 0
            expect(embedded.position.xParentPc, anchor, captured.label .. " restores parent x anchor")
            expect(embedded.position.yParentPc, anchor, captured.label .. " restores parent y anchor")
            expect(embedded.position.xSelfPc, anchor, captured.label .. " restores self x anchor")
            expect(embedded.position.ySelfPc, anchor, captured.label .. " restores self y anchor")
            expect(embedded.size.widthParentPc, 1, captured.label .. " restores width anchor")
            expect(embedded.size.heightParentPc, 1, captured.label .. " restores height anchor")
            expect(owner:DockTo(item.frame), true, captured.label .. " can redock without double insetting")
            owner:Destroy()
            expectRect(embedded, 0, 0, captured.width, captured.height, captured.label .. " teardown restores native anchors")
            locked = true; transmit(12)
            owner = NisPanel.new(area, { id = panelID, categoryID = "auto" })
            expect(owner._nisNative ~= nil, true, captured.label .. " saved standalone host restores while locked")
            expectRect(embedded, 0, 28, captured.width, captured.height - 28,
                captured.label .. " reload reserves one band, not two")
            owner:Undock(); owner:Destroy()
            expectRect(embedded, 0, 0, captured.width, captured.height, captured.label .. " locked teardown restores native page")
            item.frame.nativeShown = false
            locked = false; transmit(12)
        end
        local owner = NisPanel.new(area, { categoryID = "auto", x = 30, y = 450,
            width = 280, height = 180 })
        local title = owner:AddTitle("Scroll-less native host")

        chat.frame.nativeShown = true
        begin(owner); move(owner, 650, 130); release(owner)
        expect(owner._nisNative ~= nil, true, "scroll-less secondary chat band accepts nesting")
        expect(chat.body.hidden, true, "scroll-less host conceals its content")
        local edit = nativeNodes[(1477 << 16) | (chat.frame.staticID + 3)]
        expect(edit.hidden, true, "missing scroll does not skip the edit-layer input blocker")
        emit("Logic")
        expect(drawable(title, owner), true, "scroll-less host retains drawable content after reconciliation")
        chat.frame.nativeShown, chatPeer.frame.nativeShown = false, true
        emit("Logic")
        expect(owner._nisNative ~= nil, true, "scroll-less native frame changes retain membership")
        owner:SelectTab()
        expect(chatPeer.body.hidden, true, "scroll-less peer conceals its native content")
        owner:Undock()
        expect(chat.body.hidden, false, "scroll-less detach restores native content")
        expect(edit.hidden, false, "scroll-less detach restores the edit layer")
        chatPeer.frame.nativeShown = false
        chat.frame.nativeShown = true
        chat.tabs.visible = false
        chat.body:SetPos(4, 16)
        chat:rebuild({ 18755 }, 1)
        expect(owner:DockTo(chat.frame), false, "standalone native content without a whole wrapper remains untouched")
        expect(chat.body.y, 16, "unsupported host is not inset speculatively")
        chat.tabs.visible = true
        chat.body:SetPos(4, 44)
        chat:rebuild({ 18755, 18756 }, 1)
        chat.frame.nativeShown = false
        notes.frame.nativeShown = true
        owner:Destroy()
    end

    -- Native memberships survive complete Lua restarts without retaining handles.
    do
        local function restart()
            for _, name in ipairs({ "src/nis_panel", "src/core/nis_group",
                "src/core/nis_drag", "src/core/nis_native", "src/core/nis_persistence" }) do
                package.loaded[name] = nil
            end
            NisPanel = require("src/nis_panel")
        end
        local function create(name, options)
            options = options or {}
            options.id, options.categoryID = "native-restart:" .. name, "auto"
            options.x, options.y = 30, 450
            options.width, options.height = 280, 180
            return NisPanel.new(area, options)
        end
        local function saved(name)
            return savedLayouts["prettyui.nis-layout.v1"].panels["native-restart:" .. name]
        end
        local a, b, c = create("a"), create("b"), create("c")
        expect(a:DockTo(notes.frame), true, "persistent standalone Notes docking")
        expect(b:DockTo(a), true, "persistent second native member")
        expect(c:DockTo(a), true, "persistent third native member")
        b:SelectTab()
        expect(saved("b").native.frame, "TOPLEVEL_V2__NOTES_WINDOW", "save named native identity")
        expectRect(saved("a"), 30, 450, 280, 180, "native saves retain free bounds")
        require("src/core/nis_native").shutdown()
        b:Destroy(); a:Destroy(); c:Destroy()
        restart()
        locked = true; transmit(12)
        notes.frame.visible = false
        c = create("c")
        local restoredTitle = c:AddTitle("Restored native content")
        emit("Logic")
        expect(c._nisNative, nil, "unavailable host leaves a usable standalone panel")
        expect(drawable(restoredTitle, c), true, "pending native restore retains actual content")
        notes.frame:SetPos(580, 80)
        notes.frame.visible = true
        emit("Logic")
        expect(c._nisNative ~= nil, true, "late native host restores while locked")
        expect(c._nisNative.group.active, nil, "absent saved selection does not select another own page")
        a = create("a")
        b = create("b")
        local group = b._nisNative.group
        expect(group.members[1], a, "reverse load order restores first native tab")
        expect(group.members[2], b, "reverse load order restores second native tab")
        expect(group.members[3], c, "reverse load order restores third native tab")
        expect(group.active, b, "late selected plugin restores its own page")
        expectRect(b.root, 584, 124, 371, 309, "restoration follows current host bounds")
        expect(a:DockTo(notes.frame), false, "restoration does not enable explicit locked docking")
        c:SelectTab()
        expect(drawable(restoredTitle, c), true, "restored native page renders its retained consumer content")
        b:SelectTab()
        c:Destroy(); b:Destroy(); a:Destroy()
        restart()
        a = create("a"); b = create("b")
        expect(a._nisNative.group.active, b, "destroy order does not overwrite saved selection")
        a:Undock()
        b:Hide()
        expect(saved("a").native, nil, "explicit undock forgets native membership")
        expect(saved("b").native, nil, "hide forgets native membership")
        a:Destroy(); b:Destroy()
        restart()
        a = create("a"); b = create("b")
        expect(a._nisNative, nil, "explicit undock remains standalone after restart")
        expect(b._nisNative, nil, "hidden native member does not rejoin on restart")
        a:Destroy(); b:Destroy()

        -- Native selection is saved too; merely restoring tabs must not steal it.
        locked = false; transmit(12)
        a = create("a")
        expect(a:DockTo(notes.frame), true, "native-selection persistence setup")
        local binding = a._nisNative
        fire(binding.group.hosts[binding.group.current].nativeTab.hit, ui.Hook.ONCLICK)
        expect(a.root.hidden, true, "synthetic native tab selects native content")
        a:Destroy()
        restart()
        locked = true; transmit(12)
        a = create("a")
        expect(a._nisNative ~= nil, true, "native-selected group restores membership")
        expect(a._nisNative.group.active, nil, "native selection survives restart")
        expect(wrapper.hidden, false, "restoring inactive own page leaves native content visible")
        a:Undock(); a:Destroy()

        -- An explicit change cancels a pending restore, even before a host exists.
        notes.frame.visible = false
        c = create("c")
        expect(c._nisNative, nil, "missing host queues saved membership")
        c:Undock()
        notes.frame.visible = true
        emit("Logic")
        expect(c._nisNative, nil, "explicit undock cancels deferred restoration")
        c:Destroy()

        -- Grouped hosts can change which named frame is visible between runs.
        notes.tabs.visible = true
        notes.body:SetPos(4, 44); notes.body:SetSize(371, 309)
        notes.scroll:SetPos(4, 44); notes.scroll:SetSize(371, 309)
        notes.frame:SetPos(500, 100)
        notes.frame.nativeShown, ranged.frame.nativeShown = false, true
        locked = false; transmit(12)
        c = create("c")
        expect(c:DockTo(ranged.frame), true, "persistent grouped native docking")
        c:Destroy()
        restart()
        notes.frame.nativeShown, ranged.frame.nativeShown = true, false
        locked = true; transmit(12)
        c = create("c")
        expect(c._nisNative ~= nil, true, "alternate saved native frame restores the group")
        expect(c._nisNative.group.active, c, "grouped native own selection survives restart")
        c:Undock(); c:Destroy()
        locked = false; transmit(12)
    end
    do
        -- A native-tab transfer must be saved before any later click or tick.
        local prayer = standaloneHosts[2]
        notes.frame:SetPos(20, 20)
        prayer.host.frame.nativeShown = true
        local function create(name)
            local owner = NisPanel.new(area, { id = "prayer-transfer:" .. name, categoryID = "auto",
                x = name == "a" and 100 or 50, y = 450, width = 300,
                height = name == "a" and 200 or 260, minWidth = 64, minHeight = 64 })
            owner:AddTitle("Retained Prayer page " .. name)
            return owner
        end
        local function saved(name)
            return savedLayouts["prettyui.nis-layout.v1"].panels["prayer-transfer:" .. name]
        end
        local function transfer(owner)
            local binding = owner._nisNative
            local hit = binding.tabs[binding.group.current].hit
            local x, y = hit.x, hit.y
            fire(hit, ui.Hook.ONCLICK, 10, 10)
            fire(hit, ui.Hook.ONHOLD, 200 - x, 450 - y)
            expect(owner.dragState ~= nil, true, "native tab tear-out starts a transfer")
            local px, py = prayer.host.frame.x + 74, prayer.host.frame.y + 24
            fire(hit, ui.Hook.ONHOLD, px, py)
            expect(owner.dragState.nativeTarget ~= nil, true, "transferred native tab previews Prayer")
            fire(hit, ui.Hook.ONRELEASE, px, py)
        end
        local a, b = create("a"), create("b")
        local freeX, freeY, freeWidth, freeHeight = b.root.x, b.root.y, b.root.width, b.root.height
        expect(a:DockTo(prayer.host.frame), true, "first retained page docks in Prayer")
        expect(b:DockTo(notes.frame), true, "second retained page starts in another native host")
        transfer(b)
        expect(b._nisNative.group, a._nisNative.group, "native transfer joins both Prayer pages")
        expect(saved("b").native ~= nil, true, "native transfer immediately saves the moved page")
        expect(saved("b").native.frame, "TOPLEVEL_V2__PRAYER_WINDOW", "native transfer saves the new host")
        expect(saved("b").native.selected, true, "native transfer saves the selected page before restart")
        expect(saved("a").native.selected, false, "native transfer saves the inactive peer")
        expectRect(saved("b"), freeX, freeY, freeWidth, freeHeight,
            "native transfer retains the moved page's standalone bounds")
        for _ = 1, 2 do
            -- Consumer plugin restart only; the library/native host stays live.
            a:Destroy(); b:Destroy()
            a, b = create("a"), create("b")
            expect(a._nisNative ~= nil and b._nisNative ~= nil, true, "both Prayer pages restore on plugin restart")
            expect(a._nisNative.group, b._nisNative.group, "restarted Prayer pages share one native group")
            expect(b._nisNative.group.active, b, "the transferred Prayer page restores as selected")
            expectRect(a.root, 504, 144, 371, 179, "inactive Prayer page restores the full native viewport")
            expectRect(b.root, 504, 144, 371, 179, "selected Prayer page restores the full native viewport")
            expect(a.root.hidden, true, "restarted inactive Prayer page stays hidden")
            expect(b.root.hidden, false, "restarted selected Prayer page is visible")
            expect(b.surface.background.hidden, true, "restored native page has no standalone frame fill")
            expect(b.resize.enabled, false, "restored native page cannot resize independently")
            expect(prayer.root.hidden, true, "restored own selection conceals native Prayer controls")
            expect(prayer.host.scroll.hidden, true, "restored own selection conceals Prayer scrollbar input")
            expectRect(prayer.root, 0, 28, 371, 179, "multiple restored members reserve only one native band")
            transfer(b)
            expect(saved("b").native.selected, true, "redropping into the same Prayer group commits selection")
        end
        a:Undock(); b:Undock()
        a:Destroy(); b:Destroy()
        prayer.host.frame.nativeShown = false
        notes.frame:SetPos(500, 100)
    end
    expect(next(events.Logic), nil, "native teardown removes its logic observer")
    -- Broader user capture: single-root books, compact RuneMetrics chrome,
    -- and self-contained native tab rows with no matching outer-frame copy.
    local expandedHosts = {
        { name = "ABILITY_WINDOW_MELEE", frame = 147, owner = 1460, static = 11,
            rootName = "TOPLEVEL_V2_WINDOW_ABILITY_BOOK_MELEE__MAIN_LAYER", width = 112, height = 292 },
        { name = "ABILITY_WINDOW_RANGED", frame = 158, owner = 1452, static = 6,
            rootName = "TOPLEVEL_V2_WINDOW_ABILITY_BOOK_RANGED__MAIN_LAYER", width = 144, height = 292 },
        { name = "ABILITY_WINDOW_MAGIC", frame = 169, owner = 1461, static = 6,
            rootName = "TOPLEVEL_V2_WINDOW_ABILITY_BOOK_MAGIC__MAIN_LAYER", width = 320, height = 291 },
        { name = "ABILITY_WINDOW_MAGIC_TELEPORT", frame = 202, owner = 1887, static = 6,
            rootName = "TOPLEVEL_V2_WINDOW_ABILITY_BOOK_MAGIC_TELEPORT__MAIN_LAYER", width = 371, height = 235 },
        { name = "ABILITY_WINDOW_DEFENCE", frame = 268, owner = 1449, static = 6,
            rootName = "TOPLEVEL_V2_WINDOW_ABILITY_BOOK_DEFENCE__MAIN_LAYER", width = 112, height = 292 },
        { name = "ABILITY_WINDOW_CONSTITUTION", frame = 279, owner = 1882, static = 6,
            rootName = "TOPLEVEL_V2_WINDOW_ABILITY_BOOK_CONSTITUTION__MAIN_LAYER", width = 112, height = 292 },
        { name = "ABILITY_WINDOW_NECROMANCY_ABILITIES", frame = 235, owner = 1220, static = 6,
            rootName = "TOPLEVEL_V2_WINDOW_ABILITY_BOOK_NECROMANCY_ABILITIES__MAIN_LAYER", width = 113, height = 291 },
        { name = "ABILITY_WINDOW_NECROMANCY_SPELLS", frame = 246, owner = 1221, static = 6,
            rootName = "TOPLEVEL_V2_WINDOW_ABILITY_BOOK_NECROMANCY_SPELLS__MAIN_LAYER", width = 93, height = 291 },
        { name = "ABILITY_WINDOW_NECROMANCY", frame = 224, owner = 1219, static = 6, row = true,
            rootName = "TOPLEVEL_V2_WINDOW_ABILITY_BOOK_NECROMANCY__MAIN_LAYER", width = 206, height = 271 },
        { name = "EMOTES_WINDOW", frame = 409, owner = 590, static = 13,
            rootName = "EMOTES2__MAIN_LAYER", width = 371, height = 337 },
        { name = "TELEMETRY_WINDOW", frame = 343, owner = 1588, static = 0, top = 4, frameScroll = true,
            rootName = "TELEMETRY__TELEMETRY_WINDOW_CONTENT", width = 129, height = 276 },
        { name = "DROPLOG_WINDOW", frame = 354, owner = 1678, static = 0,
            rootName = "DROPLOG__DROPLOG_WINDOW_CONTENT", width = 371, height = 337 },
        { name = "GRAPH_WINDOW", frame = 365, owner = 1732, static = 20,
            rootName = "GRAPH__GRAPH_WINDOW_CONTENT", width = 371, height = 235 },
        { name = "FRIENDS_LIST_WINDOW", frame = 501, owner = 550, static = 0,
            rootName = "FRIENDS2__MAIN", width = 238, height = 292 },
        { name = "FRIENDSCHAT_WINDOW", frame = 556, owner = 1427, static = 27,
            rootName = "FRIENDSCHAT_CHILD__WRAPPER", width = 238, height = 292 },
        { name = "CLAN_LIST_WINDOW", frame = 512, owner = 1110, static = 0, tooltip = true, icon = 18762,
            rootName = "CLAN_CHAT__MAIN_CONTENT_LAYER", width = 238, height = 304, recordedTabs = true },
        { name = "GROUP_LIST_WINDOW", frame = 523, owner = 1519, static = 11, row = true,
            rootName = "GROUP_CHILD__BASE", width = 238, height = 264 },
        { name = "MUSIC_WINDOW", frame = 311, owner = 1416, static = 0,
            rootName = "MUSIC_V3_CHILD__WRAPPER", width = 214, height = 283 },
        { name = "PLUGIN_CONTENT_WINDOW", frame = 567, owner = 1604, static = 3, listener = true,
            rootName = "TOPLEVEL_V2_PLUGIN_CONTENT__MAIN_LAYER", width = 371, height = 337 },
        { name = "CHEEVO_TRACKER_WINDOW", frame = 387, owner = 1854, static = 0, top = 4, frameScroll = true,
            rootName = "CHEEVO_TRACKER__ACTIVITY_TRACKER_ROOT", width = 242, height = 249 },
        { name = "CHEEVO_PATHS_WINDOW", frame = 398, owner = 1894, static = 0, icon = 31692,
            rootName = "CHEEVO_PATHS__CHEEVO_PATHS_ROOT", width = 350, height = 396, recordedTabs = true },
        { name = "QUESTLIST_WINDOW", frame = 376, owner = 190, static = 0, icon = 32077,
            rootName = "QUESTLIST_V4__LIST_MAIN", width = 371, height = 337,
            rootY = 30, heightOffset = -30, recordedTabs = true, quest = true },
        { name = "LORE_WINDOW", frame = 125, owner = 662, static = 0, icon = 18787, familiar = true,
            rootName = "LORE_STATS_SIDE__CONTENT_LAYER", width = 286, height = 292 },
    }
    notes.frame.nativeShown = false
    local clanHost, groupHost, familiarHost
    for index, captured in ipairs(expandedHosts) do
        captured.icon = captured.icon or 50000 + index
        local item = host(captured.frame, captured.name, false, { captured.icon })
        captured.host = item
        local tabTop = captured.top or 16
        local bodyTop = captured.row and tabTop + 28 or tabTop
        item.frame:SetSize(captured.width + 8, captured.height + bodyTop + 4)
        item.tabs:SetPos(4, tabTop); item.tabs:SetSize(captured.width, 28)
        item.tabs.visible = captured.row == true
        nativeNodes[(1477 << 16) | (captured.frame + 7)]:SetPos(0, tabTop)
        item.body:SetPos(4, bodyTop); item.body:SetSize(captured.width, captured.height)
        if captured.frameScroll then
            item.scroll:SetPos(0, 0); item.scroll:SetSize(item.frame.width, item.frame.height)
        else
            item.scroll:SetPos(4, bodyTop); item.scroll:SetSize(captured.width, captured.height)
        end
        local edit = nativeNodes[(1477 << 16) | (captured.frame + 3)]
        edit:SetPos(4, bodyTop); edit:SetSize(captured.width, captured.height)
        captured.root = nativeNode(captured.owner, captured.static, item.body,
            0, 0, captured.width, captured.height)
        captured.root:SetSize(0, captured.heightOffset or 0, 1, 1)
        captured.root:SetPos(0, captured.rootY or 0)
        if captured.familiar then
            captured.root:SetPos(0, 0, 0.5, 0.5, 0.5, 0.5)
            familiarHost = item
        end
        id.Component[captured.rootName] = (captured.owner << 16) | captured.static
        if captured.recordedTabs then
            for _, child in ipairs(item.tabs.children) do
                if child.width == 24 and child.height == 24 then
                    child.position = { x = child.x, y = 0, xParentPc = 0, yParentPc = 0.5,
                        xSelfPc = 0, ySelfPc = 0.5 }
                    child.size = { width = 24, height = 24, widthParentPc = 0, heightParentPc = 0 }
                    child.SetPos, child.SetSize, child.Relayout = item.tabs.SetPos, item.tabs.SetSize, item.tabs.Relayout
                    child:SetPos(child.x, 0, 0, 0.5, 0, 0.5)
                end
            end
            local badge = component(item.tabs, "sprite", 0, 2)
            setmetatable(badge, getmetatable(item.tabs))
            badge.nativeShown, badge.visible, badge.type, badge.spriteID = true, false, 3, 10999
            badge:SetPos(22, 14); badge:SetSize(12, 12)
            local count = component(item.tabs, "text", 0, 3)
            setmetatable(count, getmetatable(item.tabs))
            count.nativeShown, count.visible, count.type, count.content = true, false, 2, "0"
            count:SetPos(24, 16); count:SetSize(9, 9)
        end
        if captured.name == "CHEEVO_PATHS_WINDOW" then
            id.Component.QA_PATHS__WRAPPER = (captured.owner << 16) | captured.static
        end
        if captured.quest then
            captured.controls = nativeNode(190, 15, item.body, 4, 2, captured.width - 8, 30)
            captured.controls:SetSize(-8, 30, 1, 0)
            captured.filters = nativeNode(190, 14, item.body, 4, 32, captured.width - 30, 130)
            captured.filters:SetSize(-30, 130, 1, 0)
            captured.filters.visible = false
            id.Component.QUESTLIST_V4__CONTROLS_LAYER = (190 << 16) | 15
            id.Component.QUESTLIST_V4__CONTROLS_FILTERS_LAYER = (190 << 16) | 14
        end
        if captured.row then item:rebuild({ captured.icon, captured.icon + 100 }, 1) end
        if captured.tooltip then
            captured.tooltip = nativeNode(1110, 186, item.body, 0, 0, captured.width, captured.height)
            captured.tooltip:SetSize(0, 0, 1, 1)
            id.Component.CLAN_CHAT__TOOLTIP = (1110 << 16) | 186
            clanHost = item
        end
        if captured.name == "GROUP_LIST_WINDOW" then groupHost = item end
        if captured.listener then
            captured.listener = nativeNode(1604, 0, item.body, 0, 0, 1, 1)
            id.Component.TOPLEVEL_V2_PLUGIN_CONTENT__LISTENERS_AND_TIMERS = (1604 << 16) | 0
        end
    end
    for _, name in ipairs({ "src/nis_panel", "src/core/nis_group",
        "src/core/nis_drag", "src/core/nis_native", "src/core/nis_persistence" }) do
        package.loaded[name] = nil
    end
    NisPanel = require("src/nis_panel")
    for _, captured in ipairs(expandedHosts) do
        local item, embedded = captured.host, captured.root
        item.frame.nativeShown = true
        local rootY = captured.rootY or 0
        local rootHeight = captured.height + (captured.heightOffset or 0)
        local panelID = "native-expanded:" .. captured.name
        local owner = NisPanel.new(area, { id = panelID, categoryID = "auto",
            x = 30, y = 450, width = 280, height = 180 })
        local title = owner:AddTitle(captured.name)
        local content = owner.content
        if captured.quest then
            item.body:SetSize(captured.width, 50)
            expect(owner:DockTo(item.frame), false, "Quest rejects an inset that would make the native list nonpositive")
            expectRect(embedded, 0, 30, 371, 20, "small-host rejection leaves native list dimensions unchanged")
            item.body:SetSize(captured.width, captured.height)
            captured.controls:SetPos(5, 2)
            expect(owner:DockTo(item.frame), false, "unexpected Quest control geometry is rejected before native writes")
            expectRect(embedded, 0, 30, 371, 307, "rejected Quest layout leaves its list untouched")
            captured.controls:SetPos(4, 2)
            local setSize, fail = captured.controls.SetSize, true
            captured.controls.SetSize = function(self, ...)
                setSize(self, ...)
                if fail then fail = false; error("injected second-root setter failure") end
            end
            expect(owner:DockTo(item.frame), false, "partial Quest root mutation rolls back the docking transaction")
            captured.controls.SetSize = setSize
            expectRect(embedded, 0, 30, 371, 307, "failed Quest docking restores the earlier root")
            expectRect(captured.controls, 4, 2, 363, 30, "failed Quest docking restores the partially written control root")
            expectRect(captured.filters, 4, 32, 341, 130, "failed Quest docking does not mutate the remaining root")
        end
        begin(owner)
        move(owner, item.frame.x + item.tabs.x + 50,
            item.frame.y + (captured.row and item.tabs.y + 8 or 6))
        release(owner)
        expect(owner._nisNative ~= nil, true, captured.name .. " accepts native-band docking")
        expect(#owner._nisNative.group.hosts, 1, captured.name .. " needs no matching outer-frame copy")
        local inset = captured.row and 0 or 28
        expectRect(embedded, 0, rootY + inset, captured.width, rootHeight - inset,
            captured.name .. " reuses existing native band or reserves exactly one")
        expect(embedded.visibleGlobal, false, captured.name .. " conceals native content")
        expect(item.scroll.hidden, true, captured.name .. " conceals outer native scrollbar")
        if captured.tooltip then
            expect(captured.tooltip.visibleGlobal, false, "Clan tooltip root is concealed with native content")
            expectRect(captured.tooltip, 0, inset, captured.width, captured.height - inset, "Clan tooltip reserves the same native band")
        end
        if captured.listener then
            expect(captured.listener.visibleGlobal, true, "Plugin listeners remain active")
            expectRect(captured.listener, 0, 0, 1, 1, "Plugin listener layout is untouched")
        end
        if captured.quest then
            expectRect(captured.controls, 4, 30, 363, 30, "Quest controls move below the tab band without shrinking")
            expectRect(captured.filters, 4, 60, 341, 130, "Quest filters retain their relative offset and fixed height")
            expect(captured.controls.visibleGlobal, false, "own page conceals Quest controls")
            captured.filters.visible = true
            expect(captured.filters.visibleGlobal, false, "own page suppresses native filter input even after native visibility changes")
        end
        emit("Logic")
        expect(drawable(title, owner), true, captured.name .. " retains drawable consumer controls")
        expect(owner.content, content, captured.name .. " retains its populated page")
        if captured.row then
            nativeClick(item.tabs)
        else
            fire(owner._nisNative.group.hosts[1].nativeTab.hit, ui.Hook.ONCLICK)
        end
        expect(embedded.visibleGlobal, true, captured.name .. " returns to native page")
        expect(item.scroll.hidden, false, captured.name .. " restores native scrollbar")
        if captured.tooltip then expect(captured.tooltip.visibleGlobal, true, "Clan tooltip root returns with native page") end
        if captured.quest then
            expect(captured.controls.visibleGlobal, true, "native selection restores Quest controls")
            expect(captured.filters.visibleGlobal, true, "native selection restores the native-open filter panel")
        end
        owner:SelectTab()
        if captured.quest then
            item.body:SetSize(captured.width, 50)
            emit("Logic")
            expect(owner._nisNative, nil, "Quest resize below native list capacity restores standalone content")
            expectRect(embedded, 0, 30, 371, 20, "forced Quest detach restores its valid native anchors")
            item.body:SetSize(captured.width, captured.height)
            expect(owner:DockTo(item.frame), true, "Quest can redock after the native content grows again")
        end
        item.body:SetSize(captured.width, captured.height + 24)
        emit("Logic")
        expectRect(embedded, 0, rootY + inset, captured.width, rootHeight + 24 - inset,
            captured.name .. " reflows on native content resize")
        item.body:SetSize(captured.width, captured.height)
        owner:Destroy()
        expectRect(embedded, 0, rootY, captured.width, rootHeight, captured.name .. " teardown restores native layout")
        locked = true; transmit(12)
        owner = NisPanel.new(area, { id = panelID, categoryID = "auto" })
        expect(owner._nisNative ~= nil, true, captured.name .. " restores membership while locked")
        expectRect(embedded, 0, rootY + inset, captured.width, rootHeight - inset, captured.name .. " reload does not double inset")
        owner:Undock()
        expectRect(embedded, 0, rootY, captured.width, rootHeight, captured.name .. " undock restores the original page")
        expect(embedded.visibleGlobal, true, captured.name .. " undock restores native visibility")
        if captured.familiar then
            expect(embedded.position.xParentPc, 0.5, "familiar undock restores centered parent X")
            expect(embedded.position.yParentPc, 0.5, "familiar undock restores centered parent Y")
            expect(embedded.position.xSelfPc, 0.5, "familiar undock restores centered self X")
            expect(embedded.position.ySelfPc, 0.5, "familiar undock restores centered self Y")
        end
        if captured.tooltip then expect(captured.tooltip.visibleGlobal, true, "Clan tooltip restores on teardown") end
        if captured.quest then
            expectRect(captured.controls, 4, 2, 363, 30, "Quest undock restores control anchors and dimensions")
            expectRect(captured.filters, 4, 32, 341, 130, "Quest undock restores filter anchors and dimensions")
            expect(captured.filters.visible, true, "undock preserves native filter state rather than forcing it closed")
        end
        owner:Destroy()
        item.frame.nativeShown = false
        locked = false; transmit(12)
    end
    do
        -- Captured unavailable state uses native edit-block children, not 662:0.
        local item, pageID = familiarHost, (662 << 16)
        local edit = nativeNodes[(1477 << 16) | 128]
        local placeholders, nativeWrites = {}, 0
        local function removePage()
            local page = nativeNodes[pageID]
            if page then
                removeChild(page.parent, page); removeRenderChild(page.parent, page)
                page.parent = nil
                page:Relayout()
            end
            return page
        end
        local function addPage()
            local page = nativeNodes[pageID]
            if page then
                page.parent = item.body
                item.body.children[#item.body.children + 1] = page
                item.body.renderChildren[#item.body.renderChildren + 1] = page
                page:Relayout()
            else
                page = nativeNode(662, 0, item.body, 0, 0, 286, 292)
                page:SetSize(0, 0, 1, 1); page:SetPos(0, 0, 0.5, 0.5, 0.5, 0.5)
            end
            return page
        end
        local function baseline()
            placeholders[1]:SetPos(0, 0); placeholders[1]:SetSize(0, 0, 1, 1)
            placeholders[2]:SetPos(5, 5); placeholders[2]:SetSize(-10, -10, 1, 1)
            placeholders[3]:SetPos(0, 20, 0.5, 0, 0.5, 0); placeholders[3]:SetSize(64, 64)
        end
        local function addPlaceholders()
            for index, kind in ipairs({ 1, 2, 3 }) do
                local child = component(edit, "native-placeholder", 0, index - 1)
                setmetatable(child, getmetatable(edit))
                child.type, child.nativeShown, child.visible = kind, true, true
                child.position = { x = 0, y = 0, xParentPc = 0, yParentPc = 0, xSelfPc = 0, ySelfPc = 0 }
                child.size = { width = 0, height = 0, widthParentPc = 0, heightParentPc = 0 }
                child.SetSize, child.Relayout = edit.SetSize, edit.Relayout
                child.SetPos = function(self, ...)
                    nativeWrites = nativeWrites + 1
                    return edit.SetPos(self, ...)
                end
                placeholders[index] = child
            end
            placeholders[2].content = "Familiar currently unavailable."
            placeholders[3].spriteID = 18690
            baseline()
        end
        local function expectInset()
            expectRect(placeholders[1], 0, 28, 286, 264, "unavailable familiar background reserves native band")
            expectRect(placeholders[2], 5, 33, 276, 254, "unavailable familiar message stays below native band")
            expectRect(placeholders[3], 111, 48, 64, 64, "unavailable familiar icon retains horizontal centering")
            expectRect(edit, 4, 16, 286, 292, "familiar edit container layout is never rewritten")
        end
        local parked = removePage()
        item.frame.nativeShown, edit.visible = true, true
        addPlaceholders()
        local owner = NisPanel.new(area, { id = "native-familiar:availability", categoryID = "auto",
            x = 30, y = 450, width = 280, height = 180 })
        local title = owner:AddTitle("Familiar companion page")
        local root, content = owner.root, owner.content
        placeholders[2]:SetPos(6, 5)
        expect(owner:DockTo(item.frame), false, "unrecognized familiar placeholder layout rejects docking")
        expectRect(placeholders[1], 0, 0, 286, 292, "rejected familiar docking leaves other roots untouched")
        placeholders[2]:SetPos(5, 5)
        begin(owner); move(owner, item.frame.x + 54, item.frame.y + 6)
        expect(owner.dragState.nativeTarget ~= nil, true, "unavailable familiar previews docking despite a loaded unparented page")
        release(owner)
        expect(owner._nisNative ~= nil, true, "unavailable familiar accepts native header docking")
        local binding = owner._nisNative
        expectInset()
        expectRect(parked, 0, 0, 0, 0, "unavailable docking does not mutate the unmounted familiar page")
        expect(parked.hidden, false, "unavailable docking does not conceal the unmounted familiar page")
        expect(placeholders[2].visibleGlobal, false, "own page hides unavailable familiar message")
        fire(binding.group.hosts[1].nativeTab.hit, ui.Hook.ONCLICK)
        expect(rendered(placeholders[2]), true, "native page restores the actual unavailable familiar message")
        owner:SelectTab()
        locked = true; transmit(12)
        baseline(); emit("Logic")
        expect(owner._nisNative, binding, "unavailable familiar lock reflow retains membership")
        expectInset()
        edit.visible = false
        local page = addPage()
        baseline()
        emit("Logic")
        expect(owner._nisNative, binding, "summoning while docked retains membership")
        expectRect(page, 0, 28, 286, 264, "new familiar page reserves exactly one band")
        expect(page.hidden, true, "new familiar native page does not steal own selection")
        expect(owner.root, root, "summoning retains the consumer root")
        expect(owner.content, content, "summoning retains populated controls")
        expect(drawable(title, owner), true, "summoning leaves consumer content drawable")
        fire(binding.group.hosts[1].nativeTab.hit, ui.Hook.ONCLICK)
        expect(page.visibleGlobal, true, "familiar native tab shows newly summoned familiar")
        expect(placeholders[2].visibleGlobal, false, "available familiar keeps unavailable message client-hidden")
        removePage(); edit.visible = true
        for _, child in ipairs(placeholders) do child:Destroy() end
        addPlaceholders()
        emit("Logic")
        expect(owner._nisNative, binding, "dismissing while native-selected retains membership")
        expect(binding.group.active, nil, "dismissing preserves native selection")
        expect(rendered(placeholders[2]), true, "dismissing restores native unavailable message")
        expectInset()
        expectRect(page, 0, 0, 0, 0, "dismissing releases the inset of a still-loaded unparented page")
        expect(page.position.yParentPc, 0.5, "unparenting restores the familiar page's centered anchors")
        expect(page.size.height, 0, "unparenting restores the familiar page's full-size height offset")
        owner:SelectTab()
        edit.visible = false
        addPage(); emit("Logic")
        expect(owner._nisNative, binding, "remounting the same familiar root retains docking")
        expectRect(page, 0, 28, 286, 264, "remounting the same familiar root reserves only one band")
        expect(page.hidden, true, "remounting preserves own selection")
        removePage(); edit.visible = true
        emit("Logic")
        expect(owner._nisNative, binding, "unparenting an own-selected familiar retains docking")
        expect(page.hidden, false, "unparenting releases the own-page concealment flag")
        for _, child in ipairs(placeholders) do child:Destroy() end
        emit("Logic")
        expect(owner._nisNative, binding, "temporary empty familiar rebuild retains membership")
        addPlaceholders()
        emit("Logic")
        expect(owner._nisNative, binding, "rebuilt familiar placeholders retain membership")
        expect(placeholders[2].visibleGlobal, false, "rebuilt unavailable message cannot cover own controls")
        expectInset()
        locked = false; transmit(12)
        baseline(); emit("Logic")
        expect(owner._nisNative, binding, "unavailable familiar unlock reflow retains membership")
        expectInset()
        local beforeIdle = nativeWrites
        emit("Logic"); emit("Logic")
        expect(nativeWrites, beforeIdle, "idle familiar reconciliation does not rewrite native layouts")
        owner:Destroy()
        expectRect(placeholders[1], 0, 0, 286, 292, "familiar teardown restores unavailable background")
        expectRect(placeholders[2], 5, 5, 276, 282, "familiar teardown restores unavailable message")
        expectRect(placeholders[3], 111, 20, 64, 64, "familiar teardown restores unavailable icon anchors")
        locked = true; transmit(12)
        owner = NisPanel.new(area, { id = "native-familiar:availability", categoryID = "auto" })
        expect(owner._nisNative ~= nil, true, "unavailable familiar restores saved membership while locked")
        expectInset()
        owner:Undock(); owner:Destroy()
        expect(rendered(placeholders[2]), true, "explicit undock restores unavailable familiar visibility")
        item.frame.nativeShown = false
        locked = false; transmit(12)
    end
    -- Exercise Clan's pre-existing native tab-row arrangement as well.
    clanHost.tabs.visible = true
    clanHost.body:SetPos(4, 44); clanHost.body:SetSize(238, 276)
    clanHost.scroll:SetPos(4, 44); clanHost.scroll:SetSize(238, 276)
    nativeNodes[(1477 << 16) | 515]:SetPos(4, 44)
    nativeNodes[(1477 << 16) | 515]:SetSize(238, 276)
    -- Identical row artwork does not merge two independently visible windows.
    clanHost:rebuild({ 60001, 60002 }, 1)
    groupHost:rebuild({ 60001, 60002 }, 1)
    clanHost.frame.nativeShown, groupHost.frame.nativeShown = true, true
    clanHost.frame:SetPos(20, 20)
    local clanPanel = NisPanel.new(area, { categoryID = "auto" })
    local groupPanel = NisPanel.new(area, { categoryID = "auto" })
    expect(clanPanel:DockTo(clanHost.frame), true, "independent Clan native row accepts its own panel")
    expect(groupPanel:DockTo(groupHost.frame), true, "identical independent Group row accepts a separate panel")
    expect(clanPanel._nisNative.group == groupPanel._nisNative.group, false, "visible native rows remain separate groups")
    emit("Logic")
    nativeClick(clanHost.tabs)
    expect(clanPanel.root.hidden, true, "Clan native selection only hides its own page")
    expect(groupPanel.root.hidden, false, "Clan native selection does not hide the independent Group page")
    clanPanel:Destroy(); groupPanel:Destroy()
    clanHost.frame.nativeShown, groupHost.frame.nativeShown = false, false
    for _, captured in ipairs(expandedHosts) do
        id.Component[captured.rootName] = nil
        local base, suffix = captured.name:match("^(.+_WINDOW)(.*)$")
        for _, role in ipairs({ "", "_CONTENT", "_SCROLL", "_EDIT_BLOCK", "_TABS", "_TAB_BACKGROUND" }) do
            id.Component["TOPLEVEL_V2__" .. base .. role .. suffix] = nil
        end
    end
    id.Component.CLAN_CHAT__TOOLTIP = nil
    id.Component.TOPLEVEL_V2_PLUGIN_CONTENT__LISTENERS_AND_TIMERS = nil
    id.Component.QA_PATHS__WRAPPER = nil
    id.Component.QUESTLIST_V4__CONTROLS_LAYER = nil
    id.Component.QUESTLIST_V4__CONTROLS_FILTERS_LAYER = nil
    expect(next(events.Logic), nil, "expanded native host teardown releases its observers")
    parent, ui.Interfaces.GetComponent = oldParent, oldGet
    ui.Interfaces.GetInterface = oldInterface
    setmetatable(id.Component, nil)
    for name in pairs(id.Component) do
        if name:match("^TOPLEVEL_V2__NOTES_") or name:match("^TOPLEVEL_V2__ABILITY_")
            or name:match("^TOPLEVEL_V2__INVENTORY_") or name:match("^TOPLEVEL_V2__CHAT_")
            or name:match("^TOPLEVEL_V2__PRAYER_") or name:match("^TOPLEVEL_V2__WORN_")
            or name:match("^TOPLEVEL_V2__STATS_") then
            id.Component[name] = nil
        end
    end
    id.Component.NOTES_CHILD__WRAPPER = nil
    for _, captured in ipairs(standaloneHosts) do id.Component[captured.rootName] = nil end
    id.Component.TOPLEVEL_V2_PRAYER__LISTENERS_AND_TIMERS = nil
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
