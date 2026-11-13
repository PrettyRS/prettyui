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
        position = { x = 0, y = 0, xParentPc = 0, yParentPc = 0, xSelfPc = 0, ySelfPc = 0 },
        cursorConfig = {},
        dragConfig = {},
        resizeOrder = {},
    }
    local position, size = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
    function result:SetPos(x, y, xAnchor, yAnchor, xSelf, ySelf)
        assert(not self.destroyed, "positioning destroyed component")
        position = { x, y, xAnchor or 0, yAnchor or 0, xSelf or 0, ySelf or 0 }
        self.position = { x = x, y = y, xParentPc = position[3], yParentPc = position[4],
            xSelfPc = position[5], ySelfPc = position[6] }
        self.x = x + ((parent and parent.width or 0) * position[3]) - self.width * position[5]
        self.y = y + ((parent and parent.height or 0) * position[4]) - self.height * position[6]
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
            if self.strictNativeHooks and not (self.namedSubscriptions[hook] and self.namedSubscriptions[hook][name]) then
                error("Component doesn't have an active hook of type " .. tostring(hook))
            end
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
    VarPlayer = { TOPLEVEL_V2_SKINS_VARP = 12, TOPLEVEL_V2_TRANSPARENCY = -13,
        TOPLEVEL_V2_GENERAL_VARP = 14 },
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
        Unsubscribe = function(key)
            -- Native event bindings need a Lua caller to resolve plugin ownership.
            assert(debug.getinfo(2, "S").what ~= "C", "native unsubscribe lost its Lua plugin caller")
            events[name][key] = nil
        end,
    }
end
Event = {
    Logic = event("Logic"), Draw = event("Draw"), VarTransmit = event("VarTransmit"),
    KeyDown = event("KeyDown"), WindowFocusChanged = event("WindowFocusChanged"),
}
local locked, transparency = true, 0
local classicMode = { value = 0 }
var = { VarPlayer = {
    TOPLEVEL_V2_LEGACY_INTERFACE = classicMode,
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
        if not child.hidden and child.visibleGlobal ~= false and child.enabled ~= false and
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
local savedPreferences = {}
PersistentDB = {
    GetString = function(_, key) return savedPreferences[key] end,
    SetString = function(_, key, value) savedPreferences[key] = value; return true end,
    GetBool = function(_, key) return savedPreferences[key] end,
    SetBool = function(_, key, value) savedPreferences[key] = value; return true end,
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
    buildContent = function(owner)
        owner:AddTitle("NisPanel QA")
        for index = 1, 16 do owner:AddText("Row " .. index) end
    end,
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
expect(thumb.destroyed, true, "hide destroys the scrollbar capture")
expect(panel.content, nil, "hidden panel unmounts its content")
expect(panel.viewport, nil, "hidden panel releases its viewport")
panel:Show()
expect(panel.dragLayer.hidden, false, "show restores unlocked drag region")
expect(panel._scroll.thumbDrag.hidden, false, "show recreates scrollbar capture")
expect(panel._scroll.thumbDrag == thumb, false, "show uses a fresh scrollbar tree")
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
-- A plugin owns durable data, not UI handles: each visible mount gets fresh
-- controls, tooltips, row backdrops, Scroll and sibling input overlays.
do
    local Components = require("src/core/components")
    local Tooltip = require("src/tooltip")
    local builds, cleanups, failBuild = 0, 0, false
    local row, nestedRow, tooltipRoot, contentContext
    local owner = NisPanel.new(parent, {
        categoryID = "auto", x = 100, y = 80, width = 300, height = 200,
        rowBackgroundColours = { 0x24211EFF, 0x2E2825FF },
        buildContent = function(current)
            builds = builds + 1
            current:AddTitle("Durable plugin state " .. builds)
            row = current:AddText("Temporary control " .. builds)
            if failBuild then error("injected buildContent failure") end
            for index = 1, 20 do current:AddText("Row " .. index) end
            local nested = current:AddPanel({ height = 80 })
            nestedRow = nested:AddText("Nested control")
            for index = 1, 8 do nested:AddText("Nested row " .. index) end
            contentContext = current.content
            local tooltip = Tooltip.attach(row, current.content, "Temporary tooltip")
            tooltipRoot = tooltip.root
            return function()
                expect(row.destroyed, nil, "cleanup can still access live controls")
                expect(Tooltip.getContext(contentContext) ~= nil, true,
                    "cleanup runs before tooltip context is unregistered")
                cleanups = cleanups + 1
            end
        end,
    })
    expect(builds, 1, "visible panel builds during construction")
    local originalRoot, firstRow, firstNested, firstTooltip = owner.root, row, nestedRow, tooltipRoot
    local firstContent, firstScroll = owner.content, owner._scroll.root
    owner:SetSize(320, 220)
    expect(builds, 1, "resizing active shell does not rebuild its content")
    expect(row, firstRow, "resizing retains active control handles")
    locked = false; transmit(12)
    locked = true; transmit(12)
    expect(builds, 1, "native lock and unlock do not rebuild active content")
    local firstThumb, firstBackground = owner._scroll.thumbDrag, owner.rowBackgrounds[1]
    local categoryID, dynamicID = firstRow.categoryID, firstRow.dynamicID
    local slot = (categoryID - 1) * 235 + dynamicID
    expect(Components.occupiedIDs(parent)[slot], true, "mounted content occupies its native full ID")
    expect(ui.Interfaces:GetComponent(parent.interfaceID, parent.staticID, categoryID, dynamicID),
        firstRow, "mounted content is addressable by native full ID")
    owner:SetScrollPosition(64)
    owner:Hide()
    expect(cleanups, 1, "Hide invokes cleanup once")
    owner:Hide()
    expect(cleanups, 1, "repeated Hide cannot clean up one mount twice")
    expect(owner.root, originalRoot, "Hide retains the reusable shell")
    expect(owner.content, nil, "Hide removes the content tree")
    expect(owner.viewport, nil, "Hide removes the viewport")
    expect(owner._scroll, nil, "Hide releases the Scroll controller")
    expect(owner.scrollY, 64, "Hide saves scroll position")
    expect(firstRow.destroyed, true, "Hide destroys top-level controls")
    expect(firstNested.destroyed, true, "Hide destroys nested controls")
    expect(firstTooltip.destroyed, true, "Hide destroys a built tooltip root")
    expect(firstScroll.destroyed, true, "Hide destroys the Scroll root")
    expect(firstThumb.destroyed, true, "Hide destroys its sibling scrollbar overlay")
    expect(firstBackground.destroyed, true, "Hide destroys row backgrounds")
    expect(Tooltip.getContext(firstContent), nil, "Hide unregisters the content tooltip context")
    expect(next(owner.overlays), nil, "Hide releases all sibling input registrations")
    expect(Components.occupiedIDs(parent)[slot], nil, "Hide frees control IDs while shell stays mounted")
    expect(ui.Interfaces:GetComponent(parent.interfaceID, parent.staticID, categoryID, dynamicID),
        nil, "native lookup no longer returns removed controls")
    local reused = component(parent, "ID reuse", categoryID, dynamicID)
    expect(ui.Interfaces:GetComponent(parent.interfaceID, parent.staticID, categoryID, dynamicID),
        reused, "another consumer can reuse the freed ID")
    reused:Destroy()
    owner:Show()
    expect(owner.root, originalRoot, "Show preserves shell identity")
    expect(builds, 2, "Show rebuilds controls after Hide")
    expect(row == firstRow, false, "Show supplies new control handles")
    expect(owner.scrollY, 64, "Show restores scroll position")
    owner:Show()
    expect(builds, 2, "repeated Show of a mounted panel does not rebuild")
    owner:Hide()
    failBuild = true
    local ok, problem = pcall(function() owner:Show() end)
    expect(ok, false, "failed builder propagates an error")
    expect(problem:find("injected buildContent failure", 1, true) ~= nil, true,
        "failed builder preserves the original error")
    expect(row.destroyed, true, "failed builder rolls back partial controls")
    expect(owner.content, nil, "failed builder leaves no mounted content")
    expect(owner.viewport, nil, "failed builder leaves no viewport")
    expect(owner._scroll, nil, "failed builder releases Scroll and sibling overlays")
    expect(next(owner.overlays), nil, "failed builder releases overlay registrations")
    failBuild = false
    owner:Show()
    expect(builds, 4, "Show retries a failed build instead of retaining partial controls")
    owner:Destroy()
    expect(cleanups, 3, "Destroy invokes cleanup for the final mount")
    expect(row.destroyed, true, "Destroy releases the last consumer controls")
    expect(owner.root, nil, "Destroy releases the shell")
    local children = #parent.children
    local partialRow, failedRoot
    ok, problem = pcall(function()
        NisPanel.new(parent, { categoryID = "auto", buildContent = function(current)
            failedRoot = current.root
            partialRow = current:AddText("Partial construction")
            error("injected constructor build failure")
        end })
    end)
    expect(ok, false, "constructor propagates builder failure")
    expect(problem:find("injected constructor build failure", 1, true) ~= nil,
        true, "constructor preserves builder error")
    expect(partialRow.destroyed, true, "constructor rollback destroys partial content")
    expect(failedRoot.destroyed, true, "constructor rollback destroys its shell")
    expect(#parent.children, children, "constructor rollback leaves no sibling controls")
end

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
local nativeEnumerations = 0
local nativeLayer = {}
local function nativeObstacle(index, rect)
    local origin = parent.xyGlobal
    return {
        interfaceID = rect.interfaceID or 1477, staticID = rect.staticID or (100 + index),
        xyGlobal = { x = rect.x + origin.x, y = rect.y + origin.y },
        width = rect.width, height = rect.height, visibleGlobal = rect.visibleGlobal ~= false,
    }
end
function nativeLayer:IterateStaticComponents(callback)
    nativeEnumerations = nativeEnumerations + 1
    if enumerationFails then error("native enumeration failed") end
    for index, rect in ipairs(obstacles) do
        callback(nativeObstacle(index, rect))
    end
end
local getComponent = ui.Interfaces.GetComponent
function ui.Interfaces:GetComponent(packed, ...)
    if packed == id.Component.TOPLEVEL_V2__GAME_AREA then return nativeLayer end
    for index, rect in ipairs(obstacles) do
        local key = ((rect.interfaceID or 1477) << 16) | (rect.staticID or (100 + index))
        if packed == key then return nativeObstacle(index, rect) end
    end
    return getComponent(self, packed, ...)
end
local function emit(name, payload)
    for _, callback in pairs(events[name]) do callback(payload or {}) end
end
local function makePanel(extra)
    local options = {
        categoryID = "auto", x = 100, y = 100, width = 300, height = 200,
    }
    for key, value in pairs(extra or {}) do options[key] = value end
    return NisPanel.new(parent, options)
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
expect(moving.root.hidden, false, "free placement keeps the dragged body visible")
expectRect(moving.root, 310, 444, 300, 200, "visible body follows the pointer at its original size")
expect(moving.dragLayer.enabled, true, "visible drag body retains its active pointer capture")
local white, orange = moving.dragFeedback.origin, moving.dragFeedback.active
release(moving)
expectRect(moving.root, 400, 300, 120, 400, "release commits exact filled orange")
expect(moving.root.hidden, false, "committed placement reveals the panel body")
expect(white.destroyed, true, "release destroys white")
expect(orange.destroyed, true, "release destroys orange")
fire(moving.dragLayer, ui.Hook.ONDRAGCOMPLETE)
expectRect(moving.root, 400, 300, 120, 400, "duplicate completion cannot recommit")
begin(moving)
move(moving, 460, 100)
release(moving)
expectRect(moving.root, 400, 94, 120, 400, "leaving a gap retains committed dimensions")

-- A blocked pointer moves orange to free space while the body follows the pointer.
begin(moving)
move(moving, 200, 450)
expectRect(moving.dragFeedback.active, 400, 300, 120, 400, "blocked pointer finds and fills nearest gap")
obstacles[2].x, obstacles[2].width = 500, 500
emit("Logic")
expectRect(moving.dragFeedback.active, 400, 300, 100, 400, "logic refreshes the narrowed native gap")
expect(moving.root.hidden, false, "fitted destination changes keep the held body visible")
obstacles[2].x, obstacles[2].width = 480, 520
release(moving)
expectRect(moving.root, 400, 300, 80, 400, "release revalidates changed native geometry")
obstacles = { { x = 0, y = 0, width = 1000, height = 700 } }
begin(moving)
move(moving, 700, 200)
expect(moving.dragFeedback.active.hidden, true, "no destination hides orange")
expect(moving.root.hidden, false, "invalid placement keeps the held body visible")
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

-- Native identities are indexed once per gesture, but their bounds and
-- visibility remain live. A final full scan catches newly mounted obstacles.
do
    obstacles = {
        { x = 0, y = 300, width = 400, height = 400 },
        { x = 520, y = 300, width = 480, height = 400, visibleGlobal = false },
    }
    local owner = makePanel()
    local before = nativeEnumerations
    local layout = require("src/core/nis_layout")
    local buildSpaces, builds = layout.spaces, 0
    layout.spaces = function(...)
        builds = builds + 1
        return buildSpaces(...)
    end
    begin(owner)
    move(owner, 460, 450)
    expect(nativeEnumerations - before, 1, "first movement indexes native identities once")
    for index = 1, 20 do move(owner, 460 + index, 450); emit("Logic") end
    expect(nativeEnumerations - before, 1, "movement and Logic reuse the gesture's native index")
    expect(builds, 1, "unchanged obstacles reuse the free-space decomposition")
    obstacles[2].visibleGlobal = true
    emit("Logic")
    expectRect(owner.dragFeedback.active, 400, 300, 120, 400,
        "previously hidden native obstacles participate without reindexing")
    obstacles[2] = { x = 500, y = 300, width = 500, height = 400 }
    emit("Logic")
    expectRect(owner.dragFeedback.active, 400, 300, 100, 400,
        "same-ID native replacements supply fresh bounds")
    expect(nativeEnumerations - before, 1, "live native changes do not enumerate topology")
    obstacles[3] = { x = 400, y = 300, width = 100, height = 400 }
    release(owner)
    expect(nativeEnumerations - before, 2, "drop revalidates the complete native topology")
    expect(owner.root.y + owner.root.height <= 300, true,
        "newly mounted obstacles cannot be overlapped by the committed drop")
    owner:Destroy()
    layout.spaces = buildSpaces
end

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
    expect(owner.root.hidden, false, "scaled free placement keeps the body and its outline visible")
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
local scrolling = makePanel({ buildContent = function(owner)
    for index = 1, 16 do owner:AddText("Row " .. index) end
    local nested = owner:AddPanel({ height = 80 })
    for index = 1, 8 do nested:AddText("Nested " .. index) end
end })
begin(scrolling); move(scrolling, 460, 450); release(scrolling)
expect(scrolling.contentWidth, 94, "narrowed viewport reserves scrollbar and gutter")
expect(scrolling.viewport.width, 94, "content and viewport widths agree")
expect(scrolling._scroll.thumbDrag.x, 500, "scrollbar hit region follows fitted x")
scrolling:SetScrollPosition(64)
expect(scrolling.scrollY, 64, "narrowed content remains scrollable")
local overlayRoots = {}
for root in pairs(scrolling.overlays) do overlayRoots[#overlayRoots + 1] = root end
scrolling:Hide()
for _, root in ipairs(overlayRoots) do expect(root.destroyed, true, "hide releases nested input overlays") end
expect(next(scrolling.overlays), nil, "hide clears all content overlay registrations")
expect(scrolling._scroll, nil, "hide releases the nested Scroll tree")
scrolling:Show()
expect(scrolling.scrollY, 64, "show restores the previous scroll position")
scrolling:Destroy()

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
        expect(source.root.hidden, false, "outside a nesting tab band the held body stays visible")
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
        expectRect(source.dragFeedback.active, point[1] - 100, point[2] - 6, 200, 180,
            "nesting keeps orange at the dragged size and grip")
        expect(source.root.hidden, true, "nesting preview cannot clip the destination tabs with a body ghost")
        expect(source.dragLayer.hidden, false, "hidden nesting ghost keeps header capture visible")
        expect(source.dragLayer.enabled, true, "hidden nesting ghost keeps header capture enabled")
        expect(hitAt(parent, point[1], point[2]), source.dragLayer, "pointer capture survives hidden source content")
        emit("Logic")
        expect(target._nisTabs.root.hidden, false, "hidden source remains eligible through repeated preview ticks")
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
    expect(source.root.hidden, false, "leaving strip immediately restores the dragged body")
    move(source, 650, 130)
    expect(source.root.hidden, true, "re-entering the nesting strip hides the dragged body again")
    move(source, 650, 250)
    emit("Logic")
    expect(source.root.hidden, false, "free dragging stays visible after leaving nesting again")
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
        expect(source.root.hidden, false, cancellation .. " restores the source body after preview")
        locked = false; transmit(12)
        endPair(source, target)
    end

    local Components = require("src/core/components")
    local saved, sourceBuilds, sourceCleanups = {}, 0, 0
    local sourceRow
    source, target = pair({
        onBoundsChange = function(_, x, y, width, height)
            saved[#saved + 1] = { x = x, y = y, width = width, height = height }
        end,
        buildContent = function(owner)
            sourceBuilds = sourceBuilds + 1
            for index = 1, 16 do sourceRow = owner:AddText("Source row " .. index) end
            local nested = owner:AddPanel({ height = 100 })
            for index = 1, 8 do nested:AddText("Nested row " .. index) end
            return function()
                expect(sourceRow.destroyed, nil, "cleanup runs while source controls remain available")
                sourceCleanups = sourceCleanups + 1
            end
        end,
    }, {
        buildContent = function(owner)
            if sourceCleanups > 0 then
                local categoryID, dynamicID = sourceRow.categoryID, sourceRow.dynamicID
                local slot = (categoryID - 1) * 235 + dynamicID
                expect(Components.occupiedIDs(parent)[slot], nil,
                    "incoming page builds after outgoing control IDs are released")
                expect(ui.Interfaces:GetComponent(parent.interfaceID, parent.staticID, categoryID, dynamicID),
                    nil, "incoming page cannot observe outgoing native controls")
            end
            owner:AddText("Incoming group page")
        end,
    })
    begin(source); move(source, 650, 130)
    expect(#saved, 0, "nesting preview does not persist bounds")
    release(source)
    expect(#saved, 1, "nest commit persists new shared bounds once")
    fire(source.dragLayer, ui.Hook.ONDRAGCOMPLETE)
    expect(#saved, 1, "duplicate nesting completion cannot persist twice")
    local oldRow = sourceRow
    local oldScroll = source._scroll.root
    local oldOverlays = {}
    for overlay in pairs(source.overlays) do oldOverlays[#oldOverlays + 1] = overlay end
    source:SetScrollPosition(64)
    target:SelectTab()
    expect(sourceCleanups, 1, "inactive grouped page invokes cleanup exactly once")
    expect(oldRow.destroyed, true, "inactive grouped page destroys old rows")
    expect(oldScroll.destroyed, true, "inactive grouped page destroys its scroll tree")
    expect(source.content, nil, "inactive grouped page releases content")
    expect(source.viewport, nil, "inactive grouped page releases viewport")
    for _, overlay in ipairs(oldOverlays) do
        expect(overlay.destroyed, true, "inactive grouped page destroys nested scrollbar overlays")
    end
    expect(next(source.overlays), nil, "inactive group has no content overlays")
    source:SelectTab()
    expect(sourceBuilds, 2, "reselection rebuilds old page controls")
    expect(sourceRow == oldRow, false, "reselection gives consumers fresh control handles")
    expect(source.scrollY, 64, "group reselection restores scroll offset")
    source:SelectTab()
    expect(sourceBuilds, 2, "repeated selection of active page never rebuilds")
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
    expect(source:IsActive(), false, "hidden tab is disabled")
    expect(target:IsActive(), true, "unselected tabs remain enabled until explicitly disabled")
    locked = true; transmit(12)
    target:SetSize(380, 280)
    source:SetActive(true)
    expect(source._nisGroup, target._nisGroup, "transient tab restores while locked")
    expect(source._nisGroup.members[2], source, "transient tab returns to its previous slot")
    expect(source._nisGroup.active, source, "restoring the tab selects its content")
    sameBounds(source, target, "restored transient tab follows the current group bounds")
    locked = false; transmit(12)
    endPair(source, target)

    local body, bodyClicks, targetBuilds = nil, 0, 0
    source, target = pair(nil, { buildContent = function(owner)
        targetBuilds = targetBuilds + 1
        body = owner:AddText("Interactive body")
        body.clickthrough = false
        body:Subscribe(ui.Hook.ONCLICK, function() bodyClicks = bodyClicks + 1; return false end)
    end })
    local originalContent, originalBody = target.content, body
    expect(source:DockTo(target), true, "explicit docking shares a compatible target")
    expect(target.content, nil, "docking deactivates target's old content")
    expect(originalBody.destroyed, true, "docking destroys old body control")
    -- Tab input switches newly built pages without destroying pressed tab input.
    local firstTab = source._nisTabs.tabs[1].hit
    expect(hitAt(parent, 514, 126), firstTab, "the visible tab receives the initial press")
    fire(firstTab, ui.Hook.ONCLICK, 10, 10)
    expect(target.root.hidden, false, "native-style tab click selects the target")
    expect(target.content == originalContent, false, "selection mounts a new content tree")
    expect(body == originalBody, false, "selection rebuilds consumer controls")
    expect(targetBuilds, 2, "target content builds when selected")
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
    expect(targetBuilds > 2, true, "switching repeatedly reconstructs the target page")
    local alreadyBuilt = targetBuilds
    target:SelectTab()
    expect(targetBuilds, alreadyBuilt, "reselecting active target does not rebuild it")
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
    expect(body.destroyed, nil, "active target retains its current interactive body")
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
        expect(source.root.hidden, false, "a torn-out PrettyUI tab shows its body during free placement")
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
            local peer = third._nisTabs.tabs[3]
            expect(peer.visual.x, 40, "displaced peer starts at its previous slot")
            expect(third._nisTabs.tabs[2].visual.x, 40, "dragged tab follows the pointer grip")
            emit("Logic")
            expect(peer.visual.x > 40 and peer.visual.x < 80, true,
                "displaced peer slides through an intermediate position")
            expect(peer.hit.x, third._nisTabs.root.x + peer.visual.x,
                "sliding peer input follows its visible artwork")
            for _ = 1, 12 do emit("Logic") end
            expect(peer.visual.x, 80, "displaced peer settles into the vacated slot")
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

        for _, point in ipairs({ { 503, 128 }, { 585, 128 }, { 554, 115 }, { 554, 144 } }) do
            source, target = pair()
            expect(source:DockTo(target), true, "directional tear-out starts grouped")
            local held = source._nisTabs.tabs[2].hit
            local raw = { x = held.x + 12, y = held.y + 12 }
            Mouse.GetPosition = function() return raw end
            fire(held, ui.Hook.ONCLICK, 12, 12)
            raw = { x = point[1], y = point[2] }
            fire(held, ui.Hook.ONHOLD, 12, 12)
            expect(source.dragState ~= nil, true, "leaving any occupied row edge begins tear-out")
            expect(source.dragState.nisTarget, nil, "empty source strip cannot immediately redock a torn-out tab")
            fire(held, ui.Hook.ONRELEASE)
            expect(source._nisGroup, nil, "directional tear-out commits standalone membership")
            expect(target._nisGroup, nil, "directional tear-out leaves a standalone survivor")
            expectNoDrag(source, "directional tear-out completion")
            Mouse.GetPosition = function() return nil end
            endPair(source, target)
        end
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

-- Disabled first-use panels defer content and keep plugin-selected defaults.
do
    local builds = 0
    local owner = NisPanel.new(parent, {
        categoryID = "auto", active = false, x = 170, y = 230, width = 250, height = 140,
        buildContent = function(panel)
            builds = builds + 1
            panel:AddText("Opened on demand")
        end,
    })
    expect(owner:IsActive(), false, "first-use panel starts disabled on request")
    expect(owner.root.hidden, true, "disabled first-use panel has no visible shell")
    expect(owner.content, nil, "disabled first-use panel has no content controls")
    expect(builds, 0, "disabled first-use panel does not invoke its builder")
    owner:SetActive(true)
    expectRect(owner.root, 170, 230, 250, 140, "first activation uses plugin placement")
    expect(builds, 1, "first activation builds the page once")
    owner:SetActive(false)
    owner:SetActive(false)
    expect(owner.content, nil, "repeated deactivation keeps content absent")
    owner:SetActive(true)
    expect(builds, 2, "reactivation rebuilds once")
    owner:Destroy()
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
            "src/core/nis_drag", "src/core/nis_native", "src/core/nis_persistence", "src/ribbon_bar" }) do
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
    local inactiveBuilds = 0
    a = create("plugin-a:tracker", { width = 500, height = 500,
        buildContent = function(owner)
            inactiveBuilds = inactiveBuilds + 1
            owner:AddTitle("Saved inactive panel")
        end })
    expect(a._nisGroup, b._nisGroup, "group restores in reverse plugin creation order")
    expect(a._nisGroup.active, b, "locked startup restores the selected tab")
    expect(a._nisGroup.members[1], a, "saved tab order restores")
    expect(a._nisGroup.members[2], b, "reordered tab remains last")
    expect(a.root.hidden, true, "restored inactive page is hidden")
    expectRect(a.root, 500, 100, 340, 260, "restored members share saved bounds")
    expect(inactiveBuilds, 0, "saved inactive startup does not allocate consumer content")
    expect(a.content, nil, "saved inactive startup leaves content unmounted")
    expect(a.viewport, nil, "saved inactive startup has no viewport")

    b:Destroy()
    expect(inactiveBuilds, 1, "selecting survivor builds saved inactive content on demand")
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
    expect(saved("late:c").group, saved("late:a").group, "deactivation retains remembered group membership")
    expect(saved("late:c").active, false, "deactivation persists disabled state")
    expect(c._nisGroup, nil, "disabled panel is removed from the runtime tab row")
    c:Destroy()
    b:Destroy()
    a:Destroy()
    restart()
    a = create("late:a")
    c = create("late:c", { dockTo = "late:b" })
    b = create("late:b")
    expect(c._nisGroup, nil, "hidden panel's old default is not reapplied")
    expect(#a._nisGroup.members, 2, "remaining group survives shutdown and a missing member")
    expect(c:IsActive(), false, "disabled panel remains disabled after restart")
    expect(c.root.hidden, true, "disabled startup has no visible body")
    a:SetSize(320, 260)
    c:SetActive(true)
    expect(c._nisGroup, a._nisGroup, "activation rejoins the remembered group after restart")
    expect(c._nisGroup.members[3], c, "activation restores its previous tab slot")
    expect(c._nisGroup.active, c, "activation selects the restored page")
    expectRect(c.root, a.root.x, a.root.y, 320, 260, "activation follows group resizing while disabled")
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
    expect(saved("close:a").active, false, "close persists disabled state even when its callback destroys the panel")
    expect(saved("close:a").group, saved("close:b").group, "close retains the remembered tab location")
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
        node.clickthrough = true -- structural layers; native inputs are their children
        node.strictNativeHooks = true
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
                background.strictNativeHooks = true
                setmetatable(background, getmetatable(tabs))
                background:SetPos((index - 1) * 44, 0)
                background:SetSize(44, 28)
                background.spriteID = index == selected
                    and id.Sprite.RS3_CHILD_TAB_SELECTED or id.Sprite.RS3_CHILD_TAB_UNSELECTED
                self.backgrounds[index] = background
                local icon = component(tabs, "sprite", 0, (index - 1) * 4 + 1)
                icon.type, icon.visible, icon.nativeShown = 3, true, true
                icon.strictNativeHooks = true
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
    do
        local previousLog, messages = log, {}
        log = function(message) messages[#messages + 1] = message end
        local candidate = NisPanel.new(area, { categoryID = "auto",
            x = 50, y = 450, width = 280, height = 180 })
        local subscribe = notes.tabs.Subscribe
        function notes.tabs:Subscribe(kind, name, callback)
            if kind == ui.Hook.ONDRAG then error("injected native registration failure") end
            return subscribe(self, kind, name, callback)
        end
        expect(candidate:DockTo(notes.frame), false, "partial native hook registration rejects docking")
        notes.tabs.Subscribe = subscribe
        expect(candidate._nisNative, nil, "failed hook registration keeps the panel standalone")
        expectRect(candidate.root, 50, 450, 280, 180, "failed registration retains the source placement")
        expect(#messages, 1, "partial registration reports its failure without secondary cleanup spam")
        expect(messages[1]:find("injected native registration failure", 1, true) ~= nil, true,
            "actual registration failures remain visible in the console")
        expect(candidate:DockTo(notes.frame), true, "failed registration releases the native stack for a later dock")
        candidate:Destroy()
        expect(#messages, 1, "successful docking and teardown add no missing-hook warnings")
        log = previousLog
    end
    do
        local serial = 0
        for _, occupied in ipairs({ false, true }) do
            for before = 0, 1 do
                for _, finish in ipairs({ "release", "escape", "leave" }) do
                    serial = serial + 1
                    local anchor
                    if occupied then
                        anchor = NisPanel.new(area, { categoryID = "auto", x = 10, y = 450 })
                        expect(anchor:DockTo(notes.frame), true, "first-drop preview can target an existing own group")
                    end
                    local panelID = "native:first-drop:" .. serial
                    local incoming = NisPanel.new(area, { categoryID = "auto", id = panelID,
                        x = 50, y = 450, width = 280, height = 180 })
                    local root, content = incoming.root, incoming.content
                    local overlay = component(area, "preview input overlay")
                    overlay:SetSize(20, 20)
                    incoming:_RegisterOverlay(overlay, function() return true end)
                    incoming:_SyncOverlays(false)
                    begin(incoming)
                    move(incoming, notes.frame.x + notes.tabs.x + before * 44 + 12,
                        notes.frame.y + notes.tabs.y + 12)
                    expect(incoming.dragState.nativeInsertion.beforeNative, before,
                        "first native hover chooses the requested mixed insertion point")
                    for _ = 1, 13 do emit("Logic") end
                    expect(incoming.root.hidden, true, "native drop preview hides the incoming body")
                    expect(incoming.dragFeedback.active.hidden, false, "native drop preview leaves the outline visible")
                    expect(incoming.dragLayer.enabled, true, "native drop preview retains drag input")
                    expect(overlay.hidden, true, "native drop preview hides sibling content/input overlays")
                    expect(notes.backgrounds[1].x, before == 0 and 40 or 0,
                        "first-drop preview makes room before the requested native tab")
                    expect(notes.backgrounds[2].x, 84, "first-drop preview displaces following native tabs")
                    expect(incoming._nisNative, nil, "insertion preview does not commit native membership")
                    expect(savedLayouts["prettyui.nis-layout.v1"].panels[panelID].native, nil,
                        "insertion preview does not save temporary membership")
                    if anchor then
                        local binding = anchor._nisNative
                        expect(binding.tabs[binding.group.current].visual.x, 132,
                            "existing own tabs make room for the incoming tab")
                    end
                    if finish == "release" then
                        release(incoming)
                        local binding = incoming._nisNative
                        expect(binding ~= nil, true, "first drop commits native membership")
                        expect(binding.tabs[binding.group.current].visual.x, before == 0 and 4 or 48,
                            "first drop commits the previewed mixed slot")
                        expect(savedLayouts["prettyui.nis-layout.v1"].panels[panelID].native.beforeNative,
                            before, "first drop persists its mixed insertion point immediately")
                        expect(incoming.root, root, "first mixed drop retains the panel root")
                        expect(incoming.content, content, "first mixed drop retains consumer content")
                        incoming:Undock()
                    else
                        if finish == "leave" then
                            move(incoming, 650, 250)
                            expect(notes.backgrounds[2].x, 44, "leaving native hover restores borrowed positions")
                            expect(incoming.root.hidden, false, "leaving native hover immediately restores the dragged body")
                            expect(overlay.hidden, false, "leaving native hover immediately restores sibling overlays")
                        end
                        incoming:_CancelDrag()
                    end
                    expect(notes.backgrounds[1].x, 0, "ended first-drop preview releases the first native offset")
                    expect(notes.backgrounds[2].x, 44, "ended first-drop preview releases the second native offset")
                    expect(incoming.root.hidden, false, "ended native drop preview restores the retained body")
                    expect(overlay.hidden, false, "ended native drop preview restores sibling overlays")
                    if anchor then
                        expect(anchor._nisNative.tabs[anchor._nisNative.group.current].visual.x, 92,
                            "ended first-drop preview restores existing own positions")
                        anchor:Undock()
                        anchor:Destroy()
                    end
                    incoming:Destroy()
                    overlay:Destroy()
                end
            end
        end
    end
    local title, rows, nativeBuilds, nativeCleanups = nil, {}, 0, 0
    local nativePanel = NisPanel.new(area, {
        categoryID = "auto", x = 50, y = 450, width = 280, height = 180, id = "native:retained",
        buildContent = function(owner)
            nativeBuilds = nativeBuilds + 1
            title = owner:AddTitle("Rebuildable native page")
            rows = {}
            for index = 1, 30 do rows[index] = owner:AddText("Native row " .. index) end
            return function()
                expect(title.destroyed, nil, "native cleanup runs before controls are destroyed")
                nativeCleanups = nativeCleanups + 1
            end
        end,
    })
    local root, content = nativePanel.root, nativePanel.content
    local overlay = component(area, "overlay")
    nativePanel:_RegisterOverlay(overlay, function() return true end)
    do
        local tabEnumerations, iterate = 0, notes.tabs.IterateDynamicComponents
        local unrelatedEnumerations, unrelatedIterate = 0, magic.tabs.IterateDynamicComponents
        magic.frame.nativeShown = true
        function magic.tabs:IterateDynamicComponents(callback)
            unrelatedEnumerations = unrelatedEnumerations + 1
            return unrelatedIterate(self, callback)
        end
        function notes.tabs:IterateDynamicComponents(callback)
            tabEnumerations = tabEnumerations + 1
            return iterate(self, callback)
        end
        begin(nativePanel); move(nativePanel, 650, 250)
        for _ = 1, 10 do emit("Logic") end
        expect(nativePanel.dragState.nativeTarget, nil, "native body overlap is not a tab-band drop target")
        expect(tabEnumerations, 0, "native body dragging never enumerates tab children")
        move(nativePanel, 650, 130)
        expect(nativePanel.dragState.nativeTarget ~= nil, true, "entering a native header still validates docking")
        expect(tabEnumerations > 0, true, "native header docking captures its current tab layout")
        expect(unrelatedEnumerations, 0, "header dragging skips unrelated visible native tab trees")
        nativePanel:_CancelDrag()
        notes.tabs.IterateDynamicComponents = iterate
        magic.tabs.IterateDynamicComponents = unrelatedIterate
        magic.frame.nativeShown = false
    end
    local bounded = NisPanel.new(area, { categoryID = "auto", maxWidth = 300 })
    expect(bounded:DockTo(notes.frame), false, "native viewport exceeding member limits is rejected")
    expect(notes.body.hidden, false, "rejected native docking leaves native content visible")
    bounded:Destroy()
    local function visibleIcons(node, resource)
        if not rendered(node) then return 0 end
        local count = node.spriteID == resource and 1 or 0
        for _, child in ipairs(node.renderChildren) do count = count + visibleIcons(child, resource) end
        return count
    end
    begin(nativePanel)
    local previewBuilds, previewTitle = nativeBuilds, title
    move(nativePanel, 650, 130)
    expectRect(nativePanel.dragFeedback.active, 510, 124, 280, 180,
        "native nesting keeps the dragged dimensions instead of wrapping its host")
    expect(visibleIcons(area, nativePanel.tabIcon), 1, "native nesting previews the incoming tab icon")
    expect(nativePanel.root.hidden, true, "a visible incoming native tab hides the dragged body")
    expect(notes.body.hidden, false, "native nesting preview does not conceal native content")
    expect(nativePanel._nisNative, nil, "native nesting preview does not commit membership")
    expect(nativeBuilds, previewBuilds, "temporary native drag preview does not rebuild content")
    expect(title, previewTitle, "temporary preview keeps the current control handles")
    move(nativePanel, 650, 250)
    expect(visibleIcons(area, nativePanel.tabIcon), 0, "leaving the native band removes its incoming tab")
    expect(nativePanel.root.hidden, false, "leaving the native tab band immediately restores the body")
    move(nativePanel, 650, 130)
    expect(nativePanel.root.hidden, true, "re-entering the native band hides the body with its tab preview")
    expect(nativeBuilds, previewBuilds, "re-entering drag preview does not rebuild content")
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
    -- Opening the map temporarily removes native top-level visibility. This is
    -- not a close/undock request, and no PrettyUI sibling may paint above it.
    do
        local WorldMap = require("src/core/world_map")
        local Components = require("src/core/components")
        local focus = { id = 999999, configName = "WORLDMAP_FOCUS", value = -1 }
        var.VarClient = { WORLDMAP_FOCUS = focus }
        WorldMap.start(true)
        local function map(value)
            focus.value = value
            emit("VarTransmit", { var = focus, newValue = value })
        end
        local changes = 0
        local free = NisPanel.new(area, { categoryID = "auto", id = "worldmap:free",
            x = 100, y = 400, width = 240, height = 180,
            onBoundsChange = function() changes = changes + 1 end })
        local peer = NisPanel.new(area, { categoryID = "auto", id = "worldmap:peer",
            x = 100, y = 400, width = 240, height = 180 })
        expect(peer:DockTo(free), true, "world-map fixture creates a retained PrettyUI group")
        local group, binding = peer._nisGroup, nativePanel._nisNative
        local savedNative = copy(savedLayouts["prettyui.nis-layout.v1"].panels["native:retained"].native)
        local mapBuilds, mapTitle = nativeBuilds, title
        local hidden = NisPanel.new(area, { categoryID = "auto" })
        hidden:Hide()
        local window = Window.new(area, { x = 20, y = 450, width = 260, height = 180 })
        local shownOnReturn = Window.new(area, { x = 20, y = 450, width = 260, height = 180 })
        shownOnReturn:Hide()
        local removed = Window.new(area, { x = 20, y = 450, width = 260, height = 180 })
        local popout = require("src/panel").new(area, { categoryID = "auto", popout = true,
            poppedOut = true, popoutX = 50, popoutY = 500, width = 240, height = 180 })
        local raw = Components.new(ui.Layer, area, { categoryID = "auto" })
        raw:SetSize(20, 20)
        changes = 0
        map(0)
        expect(nativeBuilds, mapBuilds, "world-map occlusion does not rebuild selected content")
        expect(nativePanel.content, content, "world-map occlusion does not unmount selected content")
        expect(nativePanel.root.hidden, true, "map immediately suppresses the native-docked page")
        expect(binding.tabs[binding.group.current].hit.hidden, true, "map suppresses native tab input siblings")
        expect(binding.group.hosts[binding.group.current].chrome.hidden, true, "map suppresses native chrome siblings")
        expect(peer.root.hidden, true, "map suppresses the active PrettyUI group page")
        expect(window.root.hidden, true, "map suppresses ordinary windows")
        expect(popout.overlay.root.hidden, true, "map suppresses independent panel popouts")
        expect(raw.hidden, true, "shared allocation suppresses arbitrary PrettyUI root components")
        window:Hide()
        shownOnReturn:Show()
        removed:Destroy()
        local created = Window.new(area, { x = 20, y = 450, width = 260, height = 180 })
        expect(created.root.hidden, true, "windows created over the map start suppressed")
        expect(shownOnReturn.root.hidden, true, "Show cannot lift a window over the map")
        local visibility = {}
        for _, frame in ipairs(frames) do
            visibility[#visibility + 1] = { frame = frame, visible = frame.visible }
            frame.visible = false
        end
        area.nativeShown = false
        area:SetSize(0, 0)
        for _ = 1, 3 do emit("Logic"); emit("Draw") end
        expect(nativePanel._nisNative, binding, "missing top-level frames cannot discard native membership")
        expect(peer._nisGroup, group, "map retains PrettyUI group identity")
        expect(group.active, peer, "map retains the selected PrettyUI tab")
        expectRect(peer.root, 100, 400, 240, 180, "map cannot clamp retained group bounds to zero")
        expect(changes, 0, "temporary map bounds do not notify or persist placement changes")
        expect(savedLayouts["prettyui.nis-layout.v1"].panels["worldmap:free"].y, 400,
            "temporary map bounds do not overwrite saved placement")
        map(-1)
        emit("Logic"); emit("Draw")
        expect(nativePanel.root.hidden, true, "focus close waits for top-level restoration")
        expect(nativePanel._nisNative, binding, "focus-close ordering cannot discard native membership")
        for _, saved in ipairs(visibility) do saved.frame.visible = saved.visible end
        area.nativeShown = true
        area:SetSize(1000, 700)
        emit("Logic"); emit("Logic"); emit("Draw")
        expect(nativePanel._nisNative, binding, "map close restores the original native binding")
        expect(nativePanel.root, root, "map close retains native page component identity")
        expect(nativePanel.content, content, "map close retains populated consumer content")
        expect(binding.group.active, nativePanel, "map close retains the selected native-docked tab")
        expect(drawable(title, nativePanel), true, "retained native page renders again after map close")
        expect(nativeBuilds, mapBuilds, "world-map return does not rebuild selected content")
        expect(title, mapTitle, "world-map return preserves the live title handle")
        expectRect(peer.root, 100, 400, 240, 180, "map close restores group placement exactly")
        expect(peer.root.hidden, false, "active PrettyUI page returns after map close")
        expect(free.root.hidden, true, "inactive PrettyUI page stays hidden after map close")
        expect(hidden.root.hidden, true, "explicitly hidden NisPanel stays hidden")
        expect(window.root.hidden, true, "Hide during map suspension is retained")
        expect(shownOnReturn.root.hidden, false, "Show during map suspension takes effect on return")
        expect(created.root.hidden, false, "map-time windows become visible only after map close")
        expect(raw.hidden, false, "shared root visibility restores after map close")
        expect(popout.poppedOut, true, "map retains panel popout mode")
        expect(popout.overlay.root.hidden, false, "independent popout returns after map close")
        expect(popout.dock.root.hidden, true, "map close does not reveal the inactive docked surface")
        expectRect(popout.overlay.root, 50, 500, 240, 180, "map retains independent popout placement")
        local nativeRecord = savedLayouts["prettyui.nis-layout.v1"].panels["native:retained"].native
        expect(nativeRecord.frame, savedNative.frame, "map retains the saved native host")
        expect(nativeRecord.beforeNative, savedNative.beforeNative, "map retains saved mixed-tab placement")
        expectRect(nativeRecord.free, savedNative.free.x, savedNative.free.y,
            savedNative.free.width, savedNative.free.height, "map retains the saved standalone rectangle")
        local held = NisPanel.new(area, { categoryID = "auto", x = 30, y = 500, width = 240, height = 100 })
        begin(held); move(held, 700, 500)
        map(0)
        release(held)
        emit("Logic"); emit("Draw")
        expect(held.root.hidden, true, "interrupted drag stays below the map")
        map(-1)
        emit("Logic"); emit("Logic")
        expectNoDrag(held, "world-map interruption")
        expectRect(held.root, 30, 500, 240, 100, "map cancels placement without committing its preview")
        expect(held.root.hidden, false, "cancelled held body returns after map close")
        held:Destroy(); popout:Destroy()
        -- An inactive native stack can restore only its selected row. The other
        -- rows may stay hidden/empty until clicked; that is not a group split.
        for _, unavailable in ipairs({ "hidden", "cleared" }) do
            local function clickNative(source)
                for _, callback in pairs(source.namedSubscriptions[ui.Hook.ONCLICK] or {}) do
                    callback(source, 10, 10)
                end
            end
            local function savedFrame(name)
                local saved = savedLayouts["prettyui.nis-layout.v1"].panels["native:retained"].native
                if saved then
                    for _, frame in ipairs(saved.frames) do if frame == name then return true end end
                end
                return false
            end
            clickNative(notes.backgrounds[1])
            emit("Logic"); emit("Draw")
            expect(binding.group.active, nil, unavailable .. " map case starts with a native page selected")
            map(0)
            if unavailable == "hidden" then ranged.tabs.visible = false
            else ranged:rebuild({}, nil) end
            map(-1)
            emit("Logic"); emit("Logic"); emit("Draw")
            expect(nativePanel._nisNative, binding, unavailable .. " hidden row retains native docking")
            expect(savedFrame("TOPLEVEL_V2__ABILITY_WINDOW_RANGED"), true,
                unavailable .. " row absence cannot erase saved stack membership")
            expect(nativePanel.root.hidden, true, unavailable .. " map return keeps the native page selected")
            clickNative(notes.tabs)
            notes.frame.visible, notes.frame.nativeShown, notes.tabs.visible = false, false, false
            ranged.tabs.visible = true
            ranged:rebuild({ 9001, 9002 }, 2)
            ranged.frame.visible, ranged.frame.nativeShown = true, true
            -- Native selection can land between Logic and Draw.
            emit("Draw"); emit("Logic")
            expect(nativePanel._nisNative, binding, unavailable .. " selecting a restored native peer cannot detach")
            expect(nativePanel.root, root, unavailable .. " native peer selection retains the panel tree")
            expect(nativePanel.content, nil, unavailable .. " native peer selection releases content")
            expect(nativePanel.viewport, nil, unavailable .. " native peer selection releases viewport")
            expect(binding.group.active, nil, unavailable .. " native peer selection retains native authority")
            expect(nativePanel.root.hidden, true, unavailable .. " native peer selection leaves the own page hidden")
            expect(ranged.body.hidden, false, unavailable .. " newly selected native page remains visible")
            expect(savedFrame("TOPLEVEL_V2__NOTES_WINDOW"), true,
                unavailable .. " lazily hidden previous page retains saved membership")
            nativePanel:SelectTab()
            expect(drawable(title, nativePanel), true, unavailable .. " retained own tab is selectable in the restored row")
            expect(binding.beforeNative, savedNative.beforeNative, unavailable .. " map preserves the mixed tab slot")
            notes.frame.visible, notes.frame.nativeShown, notes.tabs.visible = nil, true, true
            ranged.frame.visible, ranged.frame.nativeShown = nil, false
            notes:rebuild({ 9001, 9002 }, 1)
            ranged:rebuild({ 9001, 9002 }, 2)
            emit("Logic"); emit("Draw")
        end
        free:Destroy(); peer:Destroy(); hidden:Destroy()
        window:Destroy(); shownOnReturn:Destroy(); created:Destroy(); raw:Destroy()
    end
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
        emit("Draw")
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
    do
        local previousLog, messages = log, {}
        log = function(message) messages[#messages + 1] = message end
        local binding = nativePanel._nisNative
        for _ = 1, 3 do
            nativeLock(true, false)
            notes:rebuild({ 9001, 9002 }, 1)
            ranged:rebuild({ 9001, 9002 }, 2)
            emit("Logic"); emit("Draw")
            nativeClick(notes.backgrounds[1])
            expect(nativePanel.root.hidden, true, "locked rebuilt native tabs remain selectable")
            nativePanel:SelectTab()
            expect(drawable(title, nativePanel), true, "locked own selection retains its content after row replacement")
            nativeLock(false, false)
            notes:rebuild({ 9001, 9002 }, 1)
            ranged:rebuild({ 9001, 9002 }, 2)
            emit("Logic"); emit("Draw")
            expect(nativePanel._nisNative, binding, "lock/rebuild cycles retain the native binding")
        end
        log = previousLog
        expect(table.concat(messages, "\n"), "", "locked tab replacement and unlock cycles keep the console quiet")
    end
    nativePanel:SetScrollPosition(80)
    local lockedPeer = NisPanel.new(area, { categoryID = "auto", x = 20, y = 20 })
    expect(lockedPeer:DockTo(nativePanel), true, "lock scenario starts with multiple own native tabs")
    nativePanel:SelectTab()
    local nativeBinding = nativePanel._nisNative
    do
        local group = nativeBinding.group
        local function nativeHook(source, hook, ...)
            local delivered = false
            for _, callback in pairs(source.namedSubscriptions[hook] or {}) do
                delivered = true
                expect(callback(source, ...), true, "locked observers preserve native click handling")
            end
            if hook == ui.Hook.ONCLICK then assert(delivered, "locked native source remains selectable") end
        end
        -- The client lock can change before VarTransmit updates panel caches.
        locked = true
        nativeHook(notes.backgrounds[1], ui.Hook.ONCLICK, 10, 10)
        nativeHook(notes.backgrounds[1], ui.Hook.ONHOLD, 11, 10)
        nativeHook(notes.backgrounds[1], ui.Hook.ONDRAG, 11, 10)
        expect(group.nativeSort, nil, "live lock rejects native sorting before watcher delivery")
        local tab = nativeBinding.tabs[group.current]
        fire(tab.hit, ui.Hook.ONCLICK, 10, 10)
        expect(nativePanel._nisTabPress, nil, "live lock rejects own sorting before watcher delivery")
        expect(require("src/core/nis_native").reorder(nativePanel, notes.frame.x, 10), false,
            "live lock also protects the mixed reorder entry point")
        nativeHook(notes.backgrounds[1], ui.Hook.ONRELEASE, 11, 10)
        nativeHook(notes.backgrounds[1], ui.Hook.ONDRAGCOMPLETE, nil, 11, 10)
        nativePanel:SelectTab()
    end
    local lockContent, lockBuilds = nativePanel.content, nativeBuilds
    nativeLock(true, true)
    expect(nativePanel._nisNative, nativeBinding, "locking retains native membership")
    expect(drawable(rows[4], nativePanel), true, "locking native chrome does not discard the selected content")
    expect(nativePanel.content, lockContent, "lock reflow retains the selected content tree")
    expect(nativeBuilds, lockBuilds, "lock reflow does not invoke buildContent")
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
    expect(nativePanel.content, nil, "locked own-tab switching releases previous content")
    expect(rows[4].destroyed, true, "locked own-tab switching destroys old rows")
    nativePanel:SelectTab()
    expect(drawable(rows[4], nativePanel), true, "own tabs remain selectable while locked")
    do
        local group = nativeBinding.group
        local beforeNative = nativeBinding.beforeNative
        local function nativeInput(source, hook, ...)
            for _, callback in pairs(source.namedSubscriptions[hook] or {}) do
                expect(callback(source, ...), true, "locked native input preserves other listeners")
            end
        end
        local function dragClick(source)
            local x, y = source.x, source.y
            nativeInput(source, ui.Hook.ONCLICK, 10, 10)
            -- Native pointer capture reacts to registered drag hooks independently
            -- of whether PrettyUI's Lua sorting callbacks choose to do anything.
            for delta = 1, 3 do
                if next(source.namedSubscriptions[ui.Hook.ONDRAG] or {})
                    or next(source.namedSubscriptions[ui.Hook.ONDRAGCOMPLETE] or {}) then
                    source:SetPos(x + delta, y + delta)
                end
                nativeInput(source, ui.Hook.ONHOLD, 10 + delta, 10 + delta)
                nativeInput(source, ui.Hook.ONDRAG, 10, 10)
                expect(source.x, x, "locked native tab cannot shift before the next Logic repair")
                expect(source.y, y, "locked native tab cannot lift into a drag overlay")
                emit("Logic")
                expect(nativePanel.root.hidden, true, "locked drag-click still selects the native page")
            end
            nativeInput(source, ui.Hook.ONRELEASE, 13, 13)
            nativeInput(source, ui.Hook.ONDRAGCOMPLETE, nil, 13, 13)
        end
        local nativePositions = {}
        for _, host in ipairs({ notes, ranged }) do
            for _, child in ipairs(host.tabs.children) do
                nativePositions[#nativePositions + 1] = { child = child, x = child.x, y = child.y }
            end
        end
        for _, source in ipairs({ notes.tabs, notes.backgrounds[1], notes.backgrounds[2] }) do
            dragClick(source)
            for _, hook in ipairs({ ui.Hook.ONCLICK, ui.Hook.ONHOLD, ui.Hook.ONDRAG,
                ui.Hook.ONRELEASE, ui.Hook.ONDRAGCOMPLETE }) do
                for _, callback in pairs(source.namedSubscriptions[hook] or {}) do
                    expect(callback(source, hook == ui.Hook.ONCLICK and 10 or 11, 10), true,
                        "locked lifecycle keeps native handlers active")
                end
                expect(group.nativeSort, nil, "locked native click/hold/drag cannot enter live sorting")
                emit("Logic")
            end
            expect(group.tabDrag, nil, "locked native input cannot create a mixed tab drag")
            expect(nativeBinding.beforeNative, beforeNative, "locked native input preserves mixed insertion")
            for _, saved in ipairs(nativePositions) do
                expect(saved.child.x, saved.x, "locked native tab selection preserves horizontal slots")
                expect(saved.child.y, saved.y, "locked native tab selection preserves vertical slots")
            end
            lockedPeer:SelectTab()
            nativePanel:SelectTab()
            expectRect(nativePanel.root, 504, 132, 371, 321,
                "locked page switching cannot start moving the retained body")
            expect(drawable(rows[4], nativePanel), true, "locked page switching retains actual content")
        end
        notes:rebuild({ 9001, 9002 }, 1)
        ranged:rebuild({ 9001, 9002 }, 2)
        emit("Logic")
        dragClick(notes.backgrounds[1])
        nativePanel:SelectTab()
    end
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
        expect(nativePanel.content ~= nil, true, reason .. " mounts consumer controls when selected")
        expect(nativePanel.scrollY, scrollY, reason .. " restores scroll position")
        expect(drawable(rows[4], nativePanel), true, reason .. " leaves rebuilt content drawable")
    end
    local sameIDBackground = notes.backgrounds[1]
    notes:rebuild({ 9001, 9002 }, 1)
    ranged:rebuild({ 9001, 9002 }, 2)
    emit("Logic")
    retainedPage("unchanged-ID native tab replacement")
    expect(next(sameIDBackground.namedSubscriptions[ui.Hook.ONCLICK] or {}), nil,
        "unchanged-ID replacement releases the retired observer")
    local oldNativeRow, oldBuilds = rows[4], nativeBuilds
    nativeClick(notes.backgrounds[1])
    expect(nativePanel.root.hidden, true, "rebuilt same-ID native tab clicks still select native content")
    expect(nativePanel.content, nil, "native tab switch unmounts own content")
    expect(oldNativeRow.destroyed, true, "native tab switch destroys old row handles")
    expect(nativeCleanups > 0, true, "native page switch calls consumer cleanup")
    nativePanel:SelectTab()
    expect(nativeBuilds, oldBuilds + 1, "return from native tab rebuilds own content")
    expect(rows[4] == oldNativeRow, false, "native return replaces control handles")
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
    expect(nativePanel.content, nil, "native return unmounts the old row tree")
    expect(rows[4].destroyed, true, "native return destroys rows rather than merely hiding them")
    nativePanel:SelectTab()
    expect(nativePanel.scrollY, scrollY, "native selection round-trip retains scroll")
    expect(drawable(rows[4], nativePanel), true, "own-tab return makes the retained scrolled row drawable again")
    ranged.body = nativeNode(1477, 160, ranged.frame, 4, 44, 371, 309)
    notes.frame.nativeShown, ranged.frame.nativeShown = false, true
    emit("Logic")
    expect(nativePanel.root.hidden, true, "native frame selection restores native page authority")
    nativePanel:SelectTab()
    expect(ranged.body.hidden, true, "own page can be selected from the other native frame")
    retainedPage("own page selected from another native frame")
    local function captureTab()
        for _, child in ipairs(area.children) do
            if child ~= overlay and child ~= nativePanel.dragLayer and not child.hidden
                and child.width == 40 and child.height == 28 and child.subscriptions[ui.Hook.ONHOLD] then
                return child
            end
        end
        error("native tab exposes no drag capture")
    end
    for _, edge in ipairs({ "left", "right", "top", "bottom" }) do
        local binding = nativePanel._nisNative
        local hit = binding.tabs[binding.group.current].hit
        local band = ranged.tabs
        local left, top = band.xyGlobal.x - area.xyGlobal.x, band.xyGlobal.y - area.xyGlobal.y
        local right = hit.x + 40
        local px, py = hit.x + 12, top + 12
        if edge == "left" then px = left - 1
        elseif edge == "right" then px = right + 1
        elseif edge == "top" then py = top - 1
        else py = top + 28 end
        local raw = { x = hit.xyGlobal.x + 12, y = hit.xyGlobal.y + 12 }
        Mouse.GetPosition = function() return raw end
        fire(hit, ui.Hook.ONCLICK, 12, 12)
        raw = { x = area.xyGlobal.x + px, y = area.xyGlobal.y + py }
        fire(hit, ui.Hook.ONHOLD, 12, 12)
        expect(nativePanel._nisNative, nil, "native " .. edge .. " edge allows tear-out")
        expect(nativePanel.dragState ~= nil, true, "native edge tear-out enters placement")
        expect(nativePanel.dragState.nativeTarget, nil, "native empty source strip does not redock during tear-out")
        expect(nativePanel.root.hidden, false, "a torn-out native tab shows its body during free placement")
        emit("KeyDown", { gameKey = GameKey.ESCAPE })
        expect(nativePanel._nisNative ~= nil, true, "native edge tear-out cancellation restores membership")
        Mouse.GetPosition = function() return nil end
    end
    local capture = captureTab()
    fire(capture, ui.Hook.ONCLICK, 10, 10)
    local captureX, captureY = capture.x, capture.y
    fire(capture, ui.Hook.ONHOLD, 200 - captureX, 450 - captureY)
    expect(nativePanel._nisNative, nil, "dragging out detaches native membership")
    expect(nativePanel.dragState ~= nil, true, "drag-out enters normal placement")
    emit("KeyDown", { gameKey = GameKey.ESCAPE })
    expect(nativePanel._nisNative ~= nil, true, "escape restores the native membership")
    expect(nativePanel.content ~= nil, true, "cancelled drag-out remounts selected content")
    expect(ranged.body.hidden, true, "cancelled drag restores native concealment")
    capture = captureTab()
    fire(capture, ui.Hook.ONCLICK, 10, 10)
    captureX, captureY = capture.x, capture.y
    fire(capture, ui.Hook.ONHOLD, 200 - captureX, 450 - captureY)
    fire(capture, ui.Hook.ONRELEASE, 200, 450)
    expect(nativePanel._nisNative, nil, "valid drop commits a standalone panel")
    expect(nativePanel.root, root, "committed native drag-out retains the root")
    expect(nativePanel.content ~= nil, true, "committed drag-out has mounted standalone content")
    expect(ranged.body.hidden, false, "dragging the last tab out restores native content")
    expect(capture.destroyed, true, "committed drag-out releases the retained capture")
    local freeX, freeY, freeWidth, freeHeight = root.x, root.y, root.width, root.height
    begin(nativePanel); move(nativePanel, 650, 130); release(nativePanel)
    expect(nativePanel._nisNative ~= nil, true, "detached panel can be dragged back into the native group")
    local peer = NisPanel.new(area, { categoryID = "auto", x = 20, y = 20 })
    expect(peer:DockTo(nativePanel), true, "another panel can join the same native group")
    expect(nativePanel.root.hidden, true, "selecting the new own tab hides the previous body")
    expect(nativePanel:IsActive(), true, "native background tab is still enabled")
    do
        local oldTab = nativePanel._nisNative.tabs[nativePanel._nisNative.group.current]
        local oldVisual = oldTab.visual
        local index = nativePanel._nisNative.group.members[1] == nativePanel and 1 or 2
        local beforeNative = nativePanel._nisNative.beforeNative
        nativePanel:SetActive(false)
        expect(oldVisual.destroyed, true, "deactivation destroys background native tab artwork")
        expect(oldTab.hit, nil, "deactivation releases native tab input")
        expect(nativePanel._nisNative, nil, "deactivation removes native membership at runtime")
        expect(peer:IsActive(), true, "disabling a background tab leaves its peer enabled")
        locked = true; transmit(12)
        nativePanel:SetActive(true)
        expect(nativePanel._nisNative.group.members[index], nativePanel, "reactivation restores own-tab order")
        expect(nativePanel._nisNative.beforeNative, beforeNative, "reactivation restores mixed native insertion")
        expect(nativePanel._nisNative.group.active, nativePanel, "reactivation selects the native page while locked")
        locked = false; transmit(12)
        peer:SelectTab()
    end
    expect(peer.root.hidden, false, "incoming native member is selected")
    for _, finish in ipairs({ "escape", "release" }) do
        nativePanel:SelectTab()
        local group = peer._nisNative.group
        local dragged = peer._nisNative.tabs[group.current]
        local displaced = nativePanel._nisNative.tabs[group.current]
        local startX = displaced.visual.x
        local hit = dragged.hit
        local raw = { x = hit.xyGlobal.x + 12, y = hit.xyGlobal.y + 12 }
        Mouse.GetPosition = function() return raw end
        fire(hit, ui.Hook.ONCLICK, 12, 12)
        raw.x = raw.x - 40
        fire(hit, ui.Hook.ONHOLD, 12, 12)
        expect(group.members[1], peer, "native own tab can reorder within its row")
        expect(peer.dragState, nil, "native in-row reorder keeps membership")
        expect(dragged.visual.x, startX, "native dragged artwork follows its pointer grip")
        emit("Logic")
        expect(displaced.visual.x > startX and displaced.visual.x < startX + 40, true,
            "native own peer slides through an intermediate position")
        expect(displaced.hit.x, ranged.frame.x + displaced.visual.x,
            "native sliding peer input follows artwork")
        for _ = 1, 12 do emit("Logic") end
        expect(displaced.visual.x, startX + 40, "native own peer settles into the vacated slot")
        if finish == "escape" then
            emit("KeyDown", { gameKey = GameKey.ESCAPE })
            expect(group.members[1], nativePanel, "native reorder cancellation restores original order")
            expect(group.active, nativePanel, "native reorder cancellation restores original selection")
        else
            fire(hit, ui.Hook.ONRELEASE)
            expect(group.members[1], peer, "native reorder release commits new order")
            expect(group.active, peer, "native reorder release keeps the dragged page selected")
        end
        expectNoDrag(peer, "native reorder completion")
        expect(hit.width, 40, "native reorder release restores normal input width")
        expect(hit.height, 28, "native reorder release restores normal input height")
        Mouse.GetPosition = function() return nil end
    end

    do
        local targets, nativeClicks = {}, 0
        for _, host in ipairs({ notes, ranged }) do
            local target = component(host.tabs, "native input", 0, 20)
            target:SetPos(0, 0)
            target:SetSize(44, 28)
            target.clickthrough = false
            target:Subscribe(ui.Hook.ONCLICK, function(self)
                nativeClicks = nativeClicks + 1
                nativeClick(self)
            end)
            targets[#targets + 1] = target
        end
        emit("Logic")
        local function dragTo(owner, x)
            local binding = owner._nisNative
            local tab = binding.tabs[binding.group.current]
            local raw = { x = tab.hit.xyGlobal.x + 12, y = tab.hit.xyGlobal.y + 12 }
            Mouse.GetPosition = function() return raw end
            fire(tab.hit, ui.Hook.ONCLICK, 12, 12)
            raw.x = area.xyGlobal.x + x
            fire(tab.hit, ui.Hook.ONHOLD, 12, 12)
            return tab.hit
        end
        for _, finish in ipairs({ "escape", "release" }) do
            nativePanel:SelectTab()
            local held = dragTo(peer, ranged.frame.x + ranged.tabs.x + 12)
            expect(peer.dragState, nil, "dragging before native tabs stays in the mixed row")
            emit("Logic")
            expect(ranged.backgrounds[1].x > 0 and ranged.backgrounds[1].x < 40, true,
                "native tab slides out of the incoming PrettyUI tab's way")
            expect(targets[2].x, ranged.backgrounds[1].x, "native input slides with its background")
            for _ = 1, 12 do emit("Logic") end
            expect(ranged.backgrounds[1].x, 40, "first native tab makes room for a leading PrettyUI tab")
            expect(ranged.backgrounds[2].x, 84, "native relative order and native widths are retained")
            for _, child in ipairs(ranged.tabs.children) do
                if child.width == 24 then
                    expect(child.x == 50 or child.x == 94, true, "native icons move with their original tabs")
                end
            end
            if finish == "escape" then
                emit("KeyDown", { gameKey = GameKey.ESCAPE })
                expect(ranged.backgrounds[1].x, 0, "cancelled mixed reorder restores native positions")
                expect(targets[2].x, 0, "cancelled mixed reorder restores native input")
                expect(peer._nisNative.tabs[peer._nisNative.group.current].visual.x, 92,
                    "cancelled mixed reorder restores the own tab behind native tabs")
            else
                fire(held, ui.Hook.ONRELEASE)
                local tab = peer._nisNative.tabs[peer._nisNative.group.current]
                expect(tab.visual.x, 4, "release commits a PrettyUI tab before the native row")
                expect(tab.hit.x, ranged.frame.x + 4, "leading PrettyUI input matches artwork")
                local input = hitAt(area, ranged.frame.x + ranged.tabs.x + targets[2].x + 12,
                    ranged.frame.y + ranged.tabs.y + 12)
                expect(input, targets[2], "shifted native tab remains the actual hit target")
                fire(input, ui.Hook.ONCLICK, 12, 12)
                expect(nativeClicks, 1, "shifted native input retains its original handler")
                expect(peer.root.hidden, true, "shifted native click returns to the real native page")
                peer:SelectTab()
                expect(peer.root.hidden, false, "leading PrettyUI tab still selects retained content")
            end
            Mouse.GetPosition = function() return nil end
        end
        for _, target in ipairs(targets) do target:Destroy() end
        emit("Logic")
        expect(ranged.backgrounds[1].x, 40, "native child rebuild preserves the mixed insertion point")
        local function rapidNativeSwitch(firstX, secondX, ownX)
            local binding = peer._nisNative
            local group = binding.group
            nativeLock(true, true)
            local function click(destination, beforeScript)
                local current = notes.frame.nativeShown and notes or ranged
                local source = current.backgrounds[destination == notes and 1 or 2]
                for _, callback in pairs(source.namedSubscriptions[ui.Hook.ONCLICK] or {}) do
                    expect(callback(source, 10, 10), true, "rapid switching retains native click handling")
                end
                if beforeScript then emit("Logic") end
                notes.frame.nativeShown, ranged.frame.nativeShown = destination == notes, destination == ranged
                -- The native selection/frame-copy script runs after the plugin's
                -- Logic callback and rebuilds a row at native-only coordinates.
                destination:rebuild({ 9001, 9002 }, destination == notes and 1 or 2)
            end
            for frame = 1, 6 do
                click(frame % 2 == 1 and notes or ranged, frame == 1)
                if frame == 3 then click(ranged, false) end -- multiple inputs before a single paint
                emit("Draw") -- subsequent switches have no intervening Logic tick
                expect(peer._nisNative, binding, "rapid native switching retains mixed membership")
                for _, host in ipairs({ notes, ranged }) do
                    expect(host.backgrounds[1].x, firstX, "first native slot is correct before painting")
                    expect(host.backgrounds[2].x, secondX, "second native slot is correct before painting")
                    for _, child in ipairs(host.tabs.children) do
                        if child.width == 24 then
                            local x = child.dynamicID == 1 and firstX or secondX
                            expect(child.x, x + 10, "native icon follows its mixed slot before painting")
                        end
                    end
                end
                local tab = binding.tabs[group.current]
                expect(tab.visual.x, ownX, "rapid native selection does not displace the PrettyUI slot")
                expect(tab.hit.x, tab.host.frame.x + ownX, "mixed input matches the pre-draw artwork")
                expect(peer.root.hidden, true, "latest native page remains selected before painting")
                expect(group.nativeSort, nil, "rapid locked selection cannot begin sorting")
            end
            -- An own selection after native input supersedes the earlier click,
            -- even if the native row is repainted again before Draw.
            click(notes, false)
            peer:SelectTab()
            notes:rebuild({ 9001, 9002 }, 1)
            emit("Draw")
            expect(group.active, peer, "pre-draw repair retains a later PrettyUI selection")
            expect(peer.root.hidden, false, "latest PrettyUI page remains visible after late native repaint")
            notes.frame.nativeShown, ranged.frame.nativeShown = false, true
            nativeLock(false, true)
            peer:SelectTab()
        end
        rapidNativeSwitch(40, 84, 4)
        local held = dragTo(peer, ranged.frame.x + ranged.tabs.x + 44 + 12)
        fire(held, ui.Hook.ONRELEASE)
        Mouse.GetPosition = function() return nil end
        expect(ranged.backgrounds[1].x, 0, "insertion between natives releases the preceding native tab")
        expect(ranged.backgrounds[2].x, 84, "insertion between natives displaces only the following native tab")
        expect(peer._nisNative.tabs[peer._nisNative.group.current].visual.x, 48,
            "PrettyUI tab occupies the gap between native tabs")
        rapidNativeSwitch(0, 84, 48)
        do
            local function nativeHook(source, hook, ...)
                local delivered = false
                for _, callback in pairs(source.namedSubscriptions[hook] or {}) do
                    delivered = true
                    expect(callback(source, ...), true, "native sort observer preserves client handlers")
                end
                assert(delivered, "native tab exposes its sort lifecycle hook")
            end
            local originalRoot = peer.root
            local originalScroll = nativePanel.scrollY
            for _, finish in ipairs({ "release", "complete", "escape", "focus", "lock" }) do
                local binding = peer._nisNative
                local group = binding.group
                local ownHit = dragTo(peer, ranged.frame.x + ranged.tabs.x + 44 + 12)
                fire(ownHit, ui.Hook.ONRELEASE)
                Mouse.GetPosition = function() return nil end
                local source = ranged.backgrounds[2]
                nativeClick(source)
                nativeHook(source, ui.Hook.ONDRAG, 12, 12)
                expect(rendered(binding.tabs[group.current].background), true,
                    "native sort start keeps the real PrettyUI tab visibly present")
                source:SetPos(-12, 0) -- a transient native-only move, before its icon/frame copies follow
                emit("Logic")
                expect(peer._nisNative, binding, "native drag start cannot eject the interleaved own page")
                expect(peer._nisNative.group, group, "native drag preserves the original group")
                expect(source.x, -12, "native drag positions are not overwritten by mixed layout")
                expect(rendered(binding.tabs[group.current].background), true,
                    "transient native source positions do not hide PrettyUI tab artwork")
                expect(binding.tabs[group.current].hit.enabled, false,
                    "visible PrettyUI tab cannot steal an active native drag capture")
                expect(binding.tabs[group.current].visual.x > 48 and binding.tabs[group.current].visual.x < 92,
                    true, "PrettyUI tab slides aside while the native source crosses it")
                for _ = 1, 12 do emit("Logic") end
                expect(binding.tabs[group.current].visual.x, 92,
                    "PrettyUI tab occupies its live mixed slot before native release")
                expect(peer.root, originalRoot, "native drag retains the actual own root")
                expect(peer.content, nil, "native selection releases the inactive own page during sorting")
                if finish == "escape" or finish == "focus" or finish == "lock" then
                    source:SetPos(44, 0)
                    if finish == "escape" then emit("KeyDown", { gameKey = GameKey.ESCAPE })
                    elseif finish == "lock" then nativeLock(true, true)
                    else emit("WindowFocusChanged", { hasFocus = false }) end
                    for _ = 1, 3 do emit("Logic") end
                else
                    ranged:rebuild({ 9002, 9001 }, 2)
                    emit("Logic")
                    expect(peer._nisNative, binding, "in-flight native row replacement retains membership")
                    expect(rendered(binding.tabs[group.current].background), true,
                        "same-ID native source rebuild keeps PrettyUI tabs drawn during the drag")
                    if finish == "release" then nativeHook(source, ui.Hook.ONRELEASE, 12, 12)
                    else nativeHook(source, ui.Hook.ONDRAGCOMPLETE, nil, 12, 12) end
                    for _ = 1, 3 do emit("Logic") end
                    expect(peer._nisNative, binding, "staggered native frame rebuild waits without ejecting content")
                    expect(rendered(binding.tabs[group.current].background), true,
                        "staggered native release does not remove the visible PrettyUI tab")
                    notes:rebuild({ 9002, 9001 }, 1)
                    for _ = 1, 3 do emit("Logic") end
                end
                expect(peer._nisNative, binding, "native sort completion retains the own binding")
                local cancelled = finish == "escape" or finish == "focus" or finish == "lock"
                expect(binding.tabs[group.current].visual.x, cancelled and 48 or 92,
                    "native sort keeps its live mixed insertion on release and restores it on cancellation")
                expect(ranged.backgrounds[2].x, cancelled and 84 or 44,
                    "native sort restores non-overlapping mixed spacing without accumulating offsets")
                expect(nativePanel.scrollY, originalScroll, "native sorting preserves retained scroll state")
                peer:SelectTab()
                expect(peer.root.hidden, false, "own content remains selectable after native sorting")
                if finish == "lock" then nativeLock(false, true) end
                notes:rebuild({ 9001, 9002 }, 1)
                ranged:rebuild({ 9001, 9002 }, 2)
                emit("Logic")
                -- Independent rebuilds get a settled frame; continuous
                -- baseline overwrites remain an unsupported native write fight.
                emit("Logic")
                expect(peer._nisNative, binding, "completed native sort survives its delayed baseline repaint")
            end
            local function placeOwn(owner, localX)
                local hit = dragTo(owner, ranged.frame.x + ranged.tabs.x + localX + 12)
                fire(hit, ui.Hook.ONRELEASE)
                Mouse.GetPosition = function() return nil end
            end
            for leading = 1, 2 do
                for _, finish in ipairs({ "release", "escape" }) do
                    placeOwn(nativePanel, 128)
                    placeOwn(peer, 0)
                    if leading == 2 then placeOwn(nativePanel, 40) end
                    local binding = peer._nisNative
                    local group = binding.group
                    local source = ranged.backgrounds[1]
                    expect(source.x, leading * 40, "native source starts after the leading PrettyUI prefix")
                    nativeClick(source)
                    nativeHook(source, ui.Hook.ONDRAG, 12, 12)
                    emit("Logic")
                    expect(binding.tabs[group.current].visual.x, 4,
                        "starting a native sort does not overtake a leading tab before movement")
                    expect(binding.beforeNative, 0, "press-time mixed coordinates preserve the leading order")
                    source:SetPos(0, 0) -- native dragging clamps at the strip's left edge
                    emit("Logic")
                    expect(binding.tabs[group.current].visual.x > 4
                        and binding.tabs[group.current].visual.x < 48, true,
                        "a native source at the left clamp slides the leading PrettyUI tab aside")
                    for _ = 1, 12 do emit("Logic") end
                    expect(binding.tabs[group.current].visual.x, 48,
                        "native tab overtakes the leading PrettyUI tab before release")
                    expect(source.x, 0, "leading-edge crossing does not move the captured native source")
                    expect(rendered(binding.tabs[group.current].background), true,
                        "leading PrettyUI tab stays visible while being overtaken")
                    if finish == "escape" then emit("KeyDown", { gameKey = GameKey.ESCAPE })
                    else nativeHook(source, ui.Hook.ONRELEASE, 12, 12) end
                    for _ = 1, 3 do emit("Logic") end
                    local before = finish == "escape" and 0 or 1
                    expect(binding.beforeNative, before, "leading crossing commits or rolls back the mixed order")
                    expect(binding.tabs[group.current].visual.x, before == 0 and 4 or 48,
                        "leading crossing restores the correct settled artwork")
                    if leading == 2 then
                        local other = nativePanel._nisNative
                        expect(other.beforeNative, before, "native tab can overtake every leading PrettyUI tab")
                        expect(other.tabs[group.current].visual.x, before == 0 and 44 or 88,
                            "multiple leading PrettyUI tabs retain their relative order")
                        expect(savedLayouts["prettyui.nis-layout.v1"].panels["native:retained"].native.beforeNative,
                            before, "leading crossing saves even when native relative order is unchanged")
                    end
                end
            end
            placeOwn(nativePanel, 128)
            placeOwn(peer, 44)
            for _ = 1, 2 do emit("Logic") end
        end
        notes:rebuild({ 9001, 9002 }, 1)
        ranged:rebuild({ 9001, 9002 }, 2)
        emit("Logic")
        expect(peer._nisNative ~= nil, true, "same-ID native rebuild retains mixed membership")
        expect(ranged.backgrounds[1].x, 0, "rebuilt preceding native tab remains in place")
        expect(ranged.backgrounds[2].x, 84, "rebuilt following native tab regains the owned offset")
        peer:Undock()
        expect(ranged.backgrounds[2].x, 44, "removing the mixed member restores original native positions")
        expect(peer:DockTo(nativePanel), true, "a removed mixed member can rejoin normally")
    end
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
    begin(nativePanel); move(nativePanel, 650, 106)
    expect(visibleIcons(area, nativePanel.tabIcon), 1, "standalone header previews its incoming tab")
    expect(wrapper.y, 0, "standalone preview does not inset native content")
    expect(wrapper.height, 337, "standalone preview does not shrink native content")
    expect(wrapper.hidden, false, "standalone preview leaves native content visible")
    nativePanel:_CancelDrag()
    expect(visibleIcons(area, nativePanel.tabIcon), 0, "cancelling standalone preview removes its artwork")
    begin(nativePanel); move(nativePanel, 650, 106); release(nativePanel)
    expect(nativePanel._nisNative ~= nil, true, "standalone Notes synthesizes a native and own tab row")
    expect(wrapper.y, 28, "standalone docking reserves one band in the embedded wrapper")
    expect(wrapper.height, 309, "standalone wrapper shrinks without moving individual native controls")
    expect(notes.body.y, 16, "standalone docking does not rewrite the script-owned outer slot")
    expect(wrapper.hidden, true, "own selection conceals the whole standalone native wrapper")
    do
        local binding = nativePanel._nisNative
        local host = binding.group.hosts[binding.group.current]
        local hit = binding.tabs[binding.group.current].hit
        local nativeTab = host.nativeTab
        local raw = { x = hit.xyGlobal.x + 12, y = hit.xyGlobal.y + 12 }
        Mouse.GetPosition = function() return raw end
        fire(hit, ui.Hook.ONCLICK, 12, 12)
        raw.x = host.frame.xyGlobal.x + host.content.x + 12
        fire(hit, ui.Hook.ONHOLD, 12, 12)
        emit("Logic")
        expect(nativeTab.visual.x > 4 and nativeTab.visual.x < 44, true,
            "synthetic native tab slides aside for a leading PrettyUI tab")
        fire(hit, ui.Hook.ONRELEASE)
        Mouse.GetPosition = function() return nil end
        expect(binding.tabs[binding.group.current].visual.x, 4,
            "PrettyUI tab can precede the synthetic native page")
        expect(nativeTab.visual.x, 44, "synthetic native page settles after the leading own tab")
        expect(nativeTab.hit.x, host.frame.x + 44, "synthetic native input follows mixed artwork")
        fire(nativeTab.hit, ui.Hook.ONCLICK)
        expect(wrapper.hidden, false, "shifted synthetic native tab selects real native content")
        nativePanel:SelectTab()
        expect(wrapper.hidden, true, "leading synthetic own tab retains its selected content")
    end
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
    expect(nativePanel.content ~= nil, true, "library shutdown restores selected standalone content")
    nativePanel:_UnregisterOverlay(overlay)
    overlay:Destroy()
    nativePanel:Destroy()

    do
        notes.frame.nativeShown = false
        for _, captured in ipairs(standaloneHosts) do
            local item, embedded = captured.host, captured.root
            local panelID = "native-standalone:" .. captured.label
            local title
            local owner = NisPanel.new(area, { id = panelID, categoryID = "auto",
                x = 30, y = 450, width = 280, height = 180,
                buildContent = function(panel) title = panel:AddTitle(captured.label .. " native host") end })
            local content = owner.content
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
            expect(owner.content, nil, captured.label .. " native tab destroys its controls")
            expect(title.destroyed, true, captured.label .. " native tab retires the old title")
            expect(embedded.hidden, false, captured.label .. " native tab restores embedded content")
            expect(item.scroll.hidden, false, captured.label .. " native tab restores scrollbar visibility")
            expect(edit.hidden, false, captured.label .. " native tab restores edit visibility")
            owner:SelectTab()
            content = owner.content
            expect(drawable(title, owner), true, captured.label .. " own-tab return rebuilds the title")
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
                    expect(owner.content, active == owner and content or nil,
                        "Prayer lock preserves only the selected page's content")
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
                content = owner.content
                local peer = NisPanel.new(area, { categoryID = "auto", x = 20, y = 20 })
                expect(peer:DockTo(owner), true, "Prayer lock regression includes an inactive own tab")
                owner:SelectTab()
                content = owner.content
                prayerLock(true, false, true)
                expect(peer.root.hidden, true, "Prayer lock rebuild does not reveal inactive retained pages")
                peer:SelectTab()
                expect(owner.root.hidden, true, "Prayer own tabs remain selectable while locked")
                owner:SelectTab()
                content = owner.content
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
        local title
        local owner = NisPanel.new(area, { categoryID = "auto", x = 30, y = 450,
            width = 280, height = 180,
            buildContent = function(panel) title = panel:AddTitle("Scroll-less native host") end })

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
                "src/core/nis_drag", "src/core/nis_native", "src/core/nis_persistence", "src/ribbon_bar" }) do
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
        local restoredTitle
        c = create("c", { buildContent = function(panel)
            restoredTitle = panel:AddTitle("Restored native content")
        end })
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
        expect(saved("b").native.frame, "TOPLEVEL_V2__NOTES_WINDOW", "hide remembers native membership")
        expect(saved("b").active, false, "hide saves disabled native state")
        a:Destroy(); b:Destroy()
        restart()
        a = create("a"); b = create("b")
        expect(a._nisNative, nil, "explicit undock remains standalone after restart")
        expect(b._nisNative, nil, "hidden native member does not rejoin on restart")
        expect(b:IsActive(), false, "native panel stays disabled after restart")
        expect(b.content, nil, "disabled native startup allocates no page content")
        b:SetActive(true)
        expect(b._nisNative ~= nil, true, "activation restores the saved native host while locked")
        expect(b._nisNative.group.active, b, "activation selects the restored native page")
        b:Undock()
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
        local inactiveNativeBuilds = 0
        a = create("a", { buildContent = function(panel)
            inactiveNativeBuilds = inactiveNativeBuilds + 1
            panel:AddTitle("Saved native page")
        end })
        expect(a._nisNative ~= nil, true, "native-selected group restores membership")
        expect(a._nisNative.group.active, nil, "native selection survives restart")
        expect(wrapper.hidden, false, "restoring inactive own page leaves native content visible")
        expect(inactiveNativeBuilds, 0, "saved native-selected startup skips inactive own builder")
        expect(a.content, nil, "saved native-selected startup has no own controls")
        a:Undock()
        expect(inactiveNativeBuilds, 1, "undocking inactive native page builds standalone content")
        a:Destroy()

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
        a, b = create("mixed-a"), create("mixed-b")
        expect(a:DockTo(notes.frame), true, "mixed persistence starts with a native row")
        expect(b:DockTo(a), true, "mixed persistence adds a second own tab")
        local function place(owner, localX)
            owner:SelectTab()
            local binding = owner._nisNative
            local host = binding.group.hosts[binding.group.current]
            local hit = binding.tabs[binding.group.current].hit
            local raw = { x = hit.xyGlobal.x + 12, y = hit.xyGlobal.y + 12 }
            Mouse.GetPosition = function() return raw end
            fire(hit, ui.Hook.ONCLICK, 12, 12)
            raw.x = host.frame.xyGlobal.x + host.tabs.x + localX + 12
            fire(hit, ui.Hook.ONHOLD, 12, 12)
            fire(hit, ui.Hook.ONRELEASE)
            Mouse.GetPosition = function() return nil end
        end
        place(a, 0)
        expect(saved("mixed-a").native.beforeNative, 0,
            "leading insertion persists even without changing own index or selection")
        place(b, 84)
        expect(saved("mixed-b").native.beforeNative, 1, "between-native insertion persists")
        expect(notes.backgrounds[1].x, 40, "two mixed members shift the first native once")
        expect(notes.backgrounds[2].x, 124, "two mixed members shift the second native twice")
        require("src/core/nis_native").shutdown()
        expect(notes.backgrounds[1].x, 0, "shutdown restores the first native tab")
        expect(notes.backgrounds[2].x, 44, "shutdown restores the second native tab")
        b:Destroy(); a:Destroy()
        restart()
        locked = true; transmit(12)
        b = create("mixed-b")
        a = create("mixed-a")
        local mixed = a._nisNative.group
        expect(mixed.members[1], a, "reverse startup restores the leading mixed member")
        expect(mixed.members[2], b, "reverse startup restores the between-native member")
        expect(a._nisNative.tabs[mixed.current].visual.x, 4, "startup places the leading tab before native tabs")
        expect(b._nisNative.tabs[mixed.current].visual.x, 88, "startup restores the gap between native tabs")
        expect(notes.backgrounds[1].x, 40, "startup displaces the first native tab exactly once")
        expect(notes.backgrounds[2].x, 124, "startup displaces the second native tab exactly twice")
        expect(mixed.active, b, "mixed startup retains the saved selected page")
        a:Undock(); b:Undock()
        a:Destroy(); b:Destroy()
        expect(notes.backgrounds[1].x, 0, "last-member removal restores the first native tab")
        expect(notes.backgrounds[2].x, 44, "last-member removal restores the second native tab")
        locked = false; transmit(12)
    end
    do
        -- A native-tab transfer must be saved before any later click or tick.
        local prayer = standaloneHosts[2]
        notes.frame:SetPos(20, 20)
        prayer.host.frame.nativeShown = true
        local function create(name)
            return NisPanel.new(area, { id = "prayer-transfer:" .. name, categoryID = "auto",
                x = name == "a" and 100 or 50, y = 450, width = 300,
                height = name == "a" and 200 or 260, minWidth = 64, minHeight = 64,
                buildContent = function(panel) panel:AddTitle("Prayer page " .. name) end })
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
        "src/core/nis_drag", "src/core/nis_native", "src/core/nis_persistence", "src/ribbon_bar" }) do
        package.loaded[name] = nil
    end
    NisPanel = require("src/nis_panel")
    for _, captured in ipairs(expandedHosts) do
        local item, embedded = captured.host, captured.root
        item.frame.nativeShown = true
        local rootY = captured.rootY or 0
        local rootHeight = captured.height + (captured.heightOffset or 0)
        local panelID = "native-expanded:" .. captured.name
        local title
        local owner = NisPanel.new(area, { id = panelID, categoryID = "auto",
            x = 30, y = 450, width = 280, height = 180,
            buildContent = function(panel) title = panel:AddTitle(captured.name) end })
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
        expect(owner.content, content, captured.name .. " active page keeps its current controls")
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
        local title
        local owner = NisPanel.new(area, { id = "native-familiar:availability", categoryID = "auto",
            x = 30, y = 450, width = 280, height = 180,
            buildContent = function(panel) title = panel:AddTitle("Familiar companion page") end })
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
        expect(owner.content, nil, "native familiar page selection releases old content")
        expect(title.destroyed, true, "native familiar page selection destroys old title")
        expect(rendered(placeholders[2]), true, "native page restores the actual unavailable familiar message")
        owner:SelectTab()
        expect(owner.content == content, false, "return to familiar own tab rebuilds content")
        content = owner.content
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
    -- Suspend real PrettyUI groups and named native membership without a
    -- ribbon transition; the coordinator will perform this batch on mode exit.
    do
        local Group = require("src/core/nis_group")
        local Native = require("src/core/nis_native")
        local Persistence = require("src/core/nis_persistence")
        local function record(name)
            return savedLayouts["prettyui.nis-layout.v1"].panels["classic-suspend:" .. name]
        end
        local function sameData(actual, expected, label)
            if type(expected) ~= "table" then
                expect(actual, expected, label)
                return
            end
            expect(type(actual), "table", label)
            for key, value in pairs(expected) do
                sameData(actual[key], value, label .. "." .. tostring(key))
            end
            for key in pairs(actual) do
                expect(expected[key] ~= nil, true, label .. " has no extra " .. tostring(key))
            end
        end
        local builds, released = {}, {}
        local function create(name, extra)
            local options = { id = "classic-suspend:" .. name, categoryID = "auto",
                x = 40, y = 430, width = 280, height = 180,
                buildContent = function(panel)
                    builds[name] = (builds[name] or 0) + 1
                    panel:AddTitle(name)
                    return function() released[name] = (released[name] or 0) + 1 end
                end }
            for key, value in pairs(extra or {}) do options[key] = value end
            return NisPanel.new(area, options)
        end
        local function suspend(panels)
            -- The ribbon premarks the entire batch before any native detach or
            -- resize callback. A premarked flag is not an existing suspension.
            classicMode.value = 1
            for _, owner in ipairs(panels) do owner._nisClassic = true end
            for _, owner in ipairs(panels) do owner:_SetClassicMode(true) end
        end
        local function resume(panels)
            local states, transientSelections = {}, {}
            for _, owner in ipairs(panels) do
                states[owner] = assert(owner._nisClassicState, "missing classic suspension record")
                owner._contentReady = false
                if owner._nisPersistenceID == nil and owner._nisGroup
                    and owner._nisGroup.active == owner then
                    transientSelections[#transientSelections + 1] = {
                        panel = owner, snapshot = Group.snapshot(owner),
                    }
                end
            end
            classicMode.value = 0
            for _, owner in ipairs(panels) do owner:_SetClassicMode(false) end
            for _, selected in ipairs(transientSelections) do
                Group.resume(selected.panel, selected.snapshot)
            end
            for _, owner in ipairs(panels) do
                if owner:IsActive() then
                    local restored = Persistence.setActive(owner, true, Group)
                    if not restored and owner._nisInactiveGroup then
                        Group.resume(owner, owner._nisInactiveGroup)
                    end
                    owner._nisNativePending = states[owner].native or owner._nisNativePending
                    if owner._nisNativePending then Native.register(owner) end
                end
            end
            for _, owner in ipairs(panels) do
                owner._contentReady = states[owner].contentReady
                owner:_SyncChrome()
                owner:_SyncOverlays(owner.root.hidden == true)
            end
            for _, owner in ipairs(panels) do owner:_SyncContent(owner.root.hidden ~= true) end
        end

        locked = false; transmit(12)
        notes.frame.nativeShown, notes.frame.visible = true, true
        notes.frame:SetPos(500, 100)
        notes.tabs.visible = true
        notes.body:SetPos(4, 44); notes.body:SetSize(371, 309)
        notes.scroll:SetPos(4, 44); notes.scroll:SetSize(371, 309)
        notes:rebuild({ 9001, 9002 }, 1)
        local a = create("a", { x = 110, y = 400 })
        local b = create("b", { x = 410, y = 400, width = 310, height = 200 })
        expect(a:DockTo(b), true, "suspension setup creates a persisted PrettyUI group")
        local inactive = create("inactive", { x = 480, y = 400 })
        expect(inactive:DockTo(a), true, "suspension setup saves a third group member")
        b:SelectTab()
        inactive:Hide()
        local group = assert(a._nisGroup)
        expect(group.active, b, "suspension setup selects the second modern tab")
        local native = create("native", { x = 20, y = 440 })
        expect(native:DockTo(notes.frame), true, "suspension setup docks to a named native host")
        local nativeBinding = assert(native._nisNative)
        local nativeSnapshot = Native.remember(native)
        local free = create("free", { x = 290, y = 470 })
        local pendingCandidate = create("candidate", { x = 70, y = 500 })
        local transientA = NisPanel.new(area, { categoryID = "auto",
            x = 60, y = 260, width = 220, height = 150 })
        local transientB = NisPanel.new(area, { categoryID = "auto",
            x = 310, y = 260, width = 230, height = 160 })
        expect(transientA:DockTo(transientB), true, "transient group setup docks without stable IDs")
        transientB:SelectTab()
        local transientGroup = assert(transientA._nisGroup)
        local tabX = notes.frame.x + notes.tabs.x + 12
        local tabY = notes.frame.y + notes.tabs.y + 12
        expect(Native.candidate(pendingCandidate, tabX, tabY) ~= nil, true,
            "live-mode guard has a compatible native candidate before switching")
        local savedA, savedB, savedInactive = copy(record("a")), copy(record("b")),
            copy(record("inactive"))
        local savedNative = copy(record("native"))
        local savedGroup = copy(savedLayouts["prettyui.nis-layout.v1"].groups[savedA.group])
        local firstBContent, firstNativeContent = b.content, native.content
        local modernBuildsB, modernReleasedB = builds.b, released.b or 0
        local modernReleasedNative = released.native or 0
        local oldDragBounds = b.dragBounds
        local oldHookID = oldDragBounds.hookID
        expect(area.namedSubscriptions[ui.Hook.ONRESIZE][oldHookID] ~= nil, true,
            "modern DragBounds owns a parent-resize subscription")

        -- A native tick can race ahead of the ribbon's panel-flag batch.
        classicMode.value = 1
        expect(Native.candidate(pendingCandidate, tabX, tabY), nil,
            "live classic mode rejects native hover before panel reconciliation")
        expect(Native.dock(pendingCandidate, notes.frame), false,
            "live classic mode rejects explicit native docking before reconciliation")
        pendingCandidate._nisNativePending = copy(savedNative.native)
        Native.register(pendingCandidate)
        emit("Logic")
        expect(pendingCandidate._nisNative, nil, "native tick cannot consume pending membership in classic")
        sameData(pendingCandidate._nisNativePending, savedNative.native,
            "native guard preserves deferred named membership")
        pendingCandidate._nisNativePending = nil
        local members = { a, b, inactive, native, free, pendingCandidate, transientA, transientB }
        suspend(members)
        expect(a._nisGroup, group, "suspension keeps runtime PrettyUI grouping")
        expect(group.members[1], b, "suspension retains reordered first group member")
        expect(group.members[2], a, "suspension retains reordered second group member")
        expect(group.active, b, "suspension retains the selected modern group tab")
        expect(inactive._nisGroup, nil, "disabled saved member is absent from the runtime group")
        expect(savedGroup.members[3], "classic-suspend:inactive",
            "saved group retains its inactive member")
        expect(transientA._nisGroup, transientGroup, "transient group keeps its runtime identity")
        expect(transientGroup.members[1], transientB, "transient group retains modern member order")
        expect(transientGroup.active, transientB, "transient group retains modern selection")
        expect(native._nisNative, nil, "native suspension detaches through native restoration")
        expect(native._nisClassicState.contentReady, true, "suspension remembers original content readiness")
        expect(b._nisClassicState.contentReady, true, "group suspension remembers content readiness")
        sameData(native._nisClassicState.native, nativeSnapshot, "suspended native membership")
        expect(native._nisClassicState.native.free == nativeBinding.free, false,
            "suspended standalone rectangle is independently copied")
        nativeBinding.free.x = -999
        expect(native._nisClassicState.native.free.x, savedNative.native.free.x,
            "retired binding cannot mutate suspended free geometry")
        nativeBinding.free.x = savedNative.native.free.x
        expect(b.content, nil, "classic entry releases the modern selected group page")
        expect(native.content, nil, "classic entry releases native-docked consumer content")
        expect(firstBContent.destroyed, true, "modern group controls are released")
        expect(firstNativeContent.destroyed, true, "modern native controls are released")
        expect(released.b, modernReleasedB + 1, "modern group cleanup runs once on entry")
        expect(released.native, modernReleasedNative + 1, "modern native cleanup runs once on entry")
        expect(b.dragBounds, nil, "classic entry destroys DragBounds controller")
        expect(oldDragBounds.parent, nil, "old DragBounds releases its parent")
        expect(area.namedSubscriptions[ui.Hook.ONRESIZE][oldHookID], nil,
            "classic entry removes DragBounds parent-resize listener")
        b:_SetClassicMode(true); native:_SetClassicMode(true)
        expect(released.b, modernReleasedB + 1, "premarked suspension is idempotent")
        expect(released.native, modernReleasedNative + 1, "premarked native detach is idempotent")
        expect(b._nisClassicState.contentReady, true,
            "repeated suspension keeps the original readiness snapshot")
        sameData(native._nisClassicState.native, savedNative.native,
            "repeated suspension keeps the original native membership")
        b:_SyncContent(true)
        expect(b.content, nil, "suspended page cannot build its hidden modern content")
        expect(builds.b, modernBuildsB, "hidden shell callbacks cannot rebuild suspended content")
        for _, owner in ipairs(members) do
            expect(owner.root.hidden, true, "classic suspension hides every retained modern shell")
            expect(owner.dragLayer.hidden, true, "classic suspension conceals modern drag capture")
            expect(owner.dragLayer.enabled, false, "classic suspension disables modern drag input")
            expect(owner.resize.handles.e.enabled, false, "classic suspension disables resize input")
            owner:_BeginDrag(owner.dragLayer, 5, 5)
            expect(owner.dragState, nil, "classic guard rejects programmatic drag initiation")
        end
        local rootX, rootY, rootWidth, rootHeight = b.root.x, b.root.y, b.root.width, b.root.height
        area:SetSize(940, 650)
        expectRect(b.root, rootX, rootY, rootWidth, rootHeight,
            "parent resize cannot move a suspended modern shell")
        local focus = var.VarClient.WORLDMAP_FOCUS
        focus.value = 0; emit("VarTransmit", { var = focus, newValue = 0 })
        focus.value = -1; emit("VarTransmit", { var = focus, newValue = -1 })
        emit("Logic")
        expect(require("src/core/world_map").isSuspended(), false, "native area is ready after map return")
        expectRect(b.root, rootX, rootY, rootWidth, rootHeight,
            "map return cannot resume modern placement during classic")
        area:SetSize(1000, 700)
        b:SetSize(600, 300)
        b:Undock()
        expect(b:DockTo(free), false, "classic docking cannot replace remembered group membership")
        expectRect(b.root, rootX, rootY, rootWidth, rootHeight,
            "classic size and undock leave remembered modern geometry unchanged")
        expect(b._nisGroup, group, "classic undock does not mutate runtime membership")
        expect(native:DockTo(notes.frame), false, "classic panel cannot rejoin native tab row")
        Persistence.capture(b); Persistence.bounds(b); Persistence.native(native, nativeSnapshot)
        sameData(record("a"), savedA, "classic group A persistence")
        sameData(record("b"), savedB, "classic group B persistence")
        sameData(record("inactive"), savedInactive, "classic inactive group member persistence")
        sameData(record("native"), savedNative, "classic named native persistence")
        sameData(savedLayouts["prettyui.nis-layout.v1"].groups[savedA.group], savedGroup,
            "classic selection does not overwrite saved modern group selection")
        Persistence.setActive(inactive, true, Group)
        expect(record("inactive").active, true, "classic activation updates saved enabled state")
        expect(inactive._nisGroup, nil, "classic activation does not restore modern group tabs")
        Persistence.setActive(inactive, false, Group)
        sameData(record("inactive"), savedInactive,
            "classic enabled-state toggle preserves inactive group snapshot")
        free._nisHidden = true
        Persistence.setActive(free, false, Group)
        expect(record("free").active, false, "explicit classic disable persists only enabled state")
        expect(free.content, nil, "explicit classic disable leaves no modern page")
        resume(members)
        expect(a._nisGroup, b._nisGroup, "restoration rejoins the modern group")
        expect(b._nisGroup.active, b, "restoration selects the saved modern group page")
        expect(b.root.hidden, false, "restoration reveals only the selected group shell")
        expect(a.root.hidden, true, "restoration keeps unselected group shell hidden")
        expect(native._nisNative ~= nil, true, "restoration rejoins the named native host")
        expect(native._nisNative.group.active, native, "restoration recovers native selection")
        expect(free:IsActive(), false, "disabled classic panel remains disabled in modern")
        expect(free.root.hidden, true, "disabled panel is not rebuilt on restoration")
        expect(b.content ~= nil and b.content ~= firstBContent, true,
            "modern content rebuilds once after the restoration batch")
        expect(builds.b, modernBuildsB + 1, "only the selected group page rebuilds after mode exit")
        expect(builds.a or 0, 1, "unselected group member remains unbuilt after mode exit")
        expect(inactive:IsActive(), false, "disabled saved group member remains inactive")
        expect(inactive.content, nil, "disabled saved group member does not rebuild")
        expect(b.dragBounds ~= nil, true, "restoration recreates DragBounds")
        expect(b.dragBounds.hookID == oldHookID, false, "restoration uses a fresh resize listener")
        sameData(record("native"), savedNative, "restoration retains saved native geometry")
        sameData(savedLayouts["prettyui.nis-layout.v1"].groups[savedA.group], savedGroup,
            "restoration retains saved group order and selection")
        expect(transientA._nisGroup, transientB._nisGroup,
            "transient group survives classic restoration")
        expect(transientB._nisGroup.active, transientB,
            "transient group retains its modern selection on return")
        expect(transientB.root.hidden, false, "transient selected shell returns after classic")
        expect(transientA.root.hidden, true, "transient inactive shell stays hidden")
        expect(transientB.content ~= nil, true, "transient selected content returns after batch")
        local firstReturnB = b.content
        suspend(members)
        expect(firstReturnB.destroyed, true, "second classic entry releases restored content")
        expect(native._nisClassicState.native.frame, savedNative.native.frame,
            "second classic entry retains named native host")
        resume(members)
        expect(b._nisGroup.active, b, "second mode return keeps saved group selection")
        expect(native._nisNative ~= nil, true, "second mode return restores named native membership")
        expect(transientB._nisGroup.active, transientB,
            "second mode return retains transient selection")
        expect(builds.b, modernBuildsB + 2, "two classic exits each rebuild only selected modern content")
        sameData(record("a"), savedA, "second mode return preserves group A geometry")
        sameData(record("b"), savedB, "second mode return preserves group B geometry")
        sameData(record("native"), savedNative, "second mode return preserves native geometry")
        sameData(record("inactive"), savedInactive,
            "second mode return preserves inactive group membership")
        sameData(savedLayouts["prettyui.nis-layout.v1"].groups[savedA.group], savedGroup,
            "second mode return preserves saved group selection")

        -- Restart consumers while the classic mode is already live: neither
        -- saved group members nor named native pages may mount a modern page.
        for _, owner in ipairs(members) do owner:Destroy() end
        classicMode.value = 1
        builds, released = {}, {}
        b = create("b"); native = create("native"); a = create("a")
        inactive = create("inactive"); free = create("free")
        expect(a._nisGroup, nil, "classic-first startup defers saved group restoration")
        expect(b._nisGroup, nil, "classic-first startup does not select a modern group shell")
        expect(native._nisNative, nil, "classic-first startup defers named native docking")
        sameData(native._nisNativePending, savedNative.native, "classic-first native pending snapshot")
        expectRect(b.root, savedB.x, savedB.y, savedB.width, savedB.height,
            "classic-first group member retains saved modern placement")
        expectRect(native.root, savedNative.x, savedNative.y, savedNative.width, savedNative.height,
            "classic-first native member retains saved standalone placement")
        expect(a.root.hidden and b.root.hidden and native.root.hidden, true,
            "classic-first saved enabled panels start with hidden modern shells")
        expect(a.content == nil and b.content == nil and native.content == nil, true,
            "classic-first saved panels do not eagerly build consumer content")
        expect(next(builds), nil, "classic-first saved panels invoke no builders")
        expect(free:IsActive(), false, "classic-first startup restores saved disabled state")
        expect(free.content, nil, "classic-first disabled member remains unbuilt")
        expect(inactive:IsActive(), false, "classic-first saved group member remains inactive")
        expect(inactive.content, nil, "classic-first inactive group member does not build")
        local restarted = { a, b, inactive, native, free }
        suspend(restarted)
        sameData(native._nisClassicState.native, savedNative.native,
            "classic-first pending native membership survives suspension")
        sameData(record("a"), savedA, "classic-first group A persistence")
        sameData(record("b"), savedB, "classic-first group B persistence")
        sameData(record("native"), savedNative, "classic-first native persistence")
        sameData(record("inactive"), savedInactive, "classic-first inactive group persistence")
        resume(restarted)
        expect(a._nisGroup, b._nisGroup, "classic-first group restores after mode exit")
        expect(b._nisGroup.active, b, "classic-first group restores saved selection")
        expect(a._nisGroup.members[1], b, "classic-first group restores saved order")
        expect(native._nisNative ~= nil, true, "classic-first native host restores after mode exit")
        expect(native._nisNative.group.active, native, "classic-first native selection restores")
        expect(builds.a or 0, 0, "classic-first inactive tab never builds on restoration")
        expect(builds.b, 1, "classic-first selected group page builds once")
        expect(builds.native, 1, "classic-first selected native page builds once")
        expect(builds.inactive or 0, 0, "classic-first inactive group member never builds")
        expect(builds.free or 0, 0, "classic-first disabled page does not build on restoration")
        -- Drive the same saved native members through the real coordinator,
        -- including reversed registration order on a classic-first restart.
        local function runNativeCycles()
            local Ribbon = require("src/ribbon_bar")
            local oldLookup = ui.Interfaces.GetComponent
            local oldPos, oldSize, oldParent = area.SetPos, area.SetSize, area.parent
            local named = {}
            for _, name in ipairs({ "TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP",
                "TOPLEVEL_V2__VIEWPORT", "TOPLEVEL_V2__GAMEVIEW_WINDOW" }) do
                named[name] = id.Component[name]
            end
            local top = component(nil, "native mode-cycle top")
            local viewport = component(nil, "native mode-cycle viewport")
            top:SetSize(1000, 700); viewport:SetSize(1000, 700)
            local view = component(nil, "native mode-cycle gameview")
            for _, node in ipairs({ top, viewport, view }) do
                node.interfaceID, node.staticID = area.interfaceID, nil
                Interfaces.component(node)
            end
            local function setPosition(self, x, y, xp, yp, xs, ys)
                self.position = { x = x, y = y, xParentPc = xp or 0, yParentPc = yp or 0,
                    xSelfPc = xs or 0, ySelfPc = ys or 0 }
                self.x = x + viewport.width * (xp or 0) - self.width * (xs or 0)
                self.y = y + viewport.height * (yp or 0) - self.height * (ys or 0)
            end
            local function setSize(self, w, h, wp, hp)
                self.size = { width = w, height = h, widthParentPc = wp or 0, heightParentPc = hp or 0 }
                self.width, self.height = w + viewport.width * (wp or 0), h + viewport.height * (hp or 0)
                local p = self.position
                setPosition(self, p.x, p.y, p.xParentPc, p.yParentPc, p.xSelfPc, p.ySelfPc)
                for _, child in ipairs(self.children) do child:Relayout() end
                self:EmitResize()
            end
            area.parent, view.parent = viewport, viewport
            area.SetPos, area.SetSize = setPosition, setSize
            view.SetPos, view.SetSize = setPosition, setSize
            area:SetSize(0, 0, 1, 1); area:SetPos(0, 0, .5, .5, .5, .5)
            view:SetSize(0, 0, 1, 1)
            local mounts = {}
            for name, node in pairs({ TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP = top,
                TOPLEVEL_V2__VIEWPORT = viewport, TOPLEVEL_V2__GAMEVIEW_WINDOW = view }) do
                local packed = (node.interfaceID << 16) | node.staticID
                id.Component[name], mounts[packed] = packed, node
            end
            function ui.Interfaces:GetComponent(packed, ...)
                if select("#", ...) == 0 and mounts[packed] then return mounts[packed] end
                return oldLookup(self, packed, ...)
            end
            config.Cursor.CURSOR_OPEN = { id = 7 }
            local peer = create("native-peer")
            expect(peer:DockTo(notes.frame), true, "second native member docks before mode cycle")
            native:SelectTab()
            local nativeIndex, peerIndex = Native.remember(native).index, Native.remember(peer).index
            local nativeBuilds = builds.native
            Ribbon.Start()
            local function advance(ticks)
                for _ = 1, ticks do emit("Logic") end
            end
            for pass = 1, 2 do
                classicMode.value = 1; transmit(id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP)
                expect(area.width, 956, "real native mode entry reserves collapsed rail")
                expect(native._nisNative, nil, "real coordinator suspends named native membership")
                a:Show()
                expect(area.width, 596, "classic selection reserves expanded content beside native UI")
                classicMode.value = 0; transmit(id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP)
                expect(area.width, 1000, "mode exit releases reservation before deferred native restore")
                expect(native._nisNative, nil, "mode return does not dock inside VarTransmit")
                advance(9)
                expect(native._nisNative, nil, "native docking waits through the layout settling interval")
                expect(peer._nisNative, nil, "every native member respects the settling interval")
                emit("Logic")
                expect(native._nisNative ~= nil, true, "real coordinator restores named native member")
                expect(peer._nisNative.group, native._nisNative.group, "native members restore to one group")
                expect(native._nisNative.group.active, native, "native selection survives sequential detach")
                expect(Native.remember(native).index, nativeIndex, "native first slot survives round trip")
                expect(Native.remember(peer).index, peerIndex, "native second slot survives round trip")
                expectRect(native.root, notes.frame.x + notes.body.x, notes.frame.y + notes.body.y,
                    notes.body.width, notes.body.height, "deferred restore aligns with the current native content")
                expect(builds.native, nativeBuilds + pass, "native content builds once after complete batch")
                expect(b._nisGroup.active, b, "real native cycle retains independent PrettyUI selection")
            end
            -- Right-edge frames shrink with GAME_AREA. A delayed native pass
            -- can briefly reapply the narrow layout after Modern has redocked
            -- the panels; that must not permanently discard their targets.
            do
                local savedNativeMember, savedPeerMember = copy(record("native")), copy(record("native-peer"))
                local nodes = { notes.frame, notes.body, notes.scroll, notes.tabs,
                    ranged.frame, ranged.body, ranged.scroll, ranged.tabs }
                local layouts = {}
                for _, node in ipairs(nodes) do
                    layouts[node] = { position = copy(node.position), size = copy(node.size) }
                end
                for _, item in ipairs({ notes, ranged }) do
                    item.frame:SetPos(621, 100)
                    item.frame:SetSize(-621, 357, 1, 0)
                    item.body:SetSize(-8, 309, 1, 0)
                    item.scroll:SetSize(-8, 309, 1, 0)
                    item.tabs:SetSize(-8, 28, 1, 0)
                end
                for pass = 1, 2 do
                    classicMode.value = 1; transmit(id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP)
                    a:Show()
                    expect(notes.frame.x > area.width, true, "expanded sidebar overlaps right-edge native host")
                    classicMode.value = 0; transmit(id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP)
                    advance(10)
                    expect(native._nisNative ~= nil, true, "right-edge host initially accepts mode-return docking")
                    -- Model a later native reflow still using the reduced width.
                    notes.frame:SetSize(100, 357); ranged.frame:SetSize(100, 357)
                    emit("Logic")
                    expect(native._nisNative, nil, "undersized native host releases unsafe binding")
                    expect(peer._nisNative, nil, "undersized native host releases every unsafe member")
                    expect(native._nisNativePending ~= nil, true, "capacity loss retains selected native target")
                    expect(peer._nisNativePending ~= nil, true, "capacity loss retains peer native target")
                    emit("Logic"); emit("Logic")
                    expect(native._nisNative, nil, "narrow host cannot prematurely reclaim a member")
                    sameData(record("native"), savedNativeMember, "capacity loss preserves saved native membership")
                    sameData(record("native-peer"), savedPeerMember, "capacity loss preserves saved peer membership")
                    -- Another mode round trip must retain the deferred targets.
                    classicMode.value = 1; transmit(id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP)
                    classicMode.value = 0; transmit(id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP)
                    notes.frame:SetSize(-621, 357, 1, 0); ranged.frame:SetSize(-621, 357, 1, 0)
                    advance(10)
                    expect(native._nisNative ~= nil, true, "settled right-edge host reclaims its member")
                    expect(peer._nisNative.group, native._nisNative.group, "settled host reclaims the whole group")
                    expect(native._nisNative.group.active, native, "capacity recovery restores selected tab")
                    expect(Native.remember(native).index, nativeIndex, "capacity recovery restores first tab order")
                    expect(Native.remember(peer).index, peerIndex, "capacity recovery restores peer tab order")
                    sameData(record("native"), savedNativeMember, "capacity recovery preserves standalone geometry")
                end
                for _, node in ipairs(nodes) do
                    local p, s = layouts[node].position, layouts[node].size
                    node:SetPos(p.x, p.y, p.xParentPc, p.yParentPc, p.xSelfPc, p.ySelfPc)
                    node:SetSize(s.width, s.height, s.widthParentPc, s.heightParentPc)
                end
                emit("Logic")
            end
            -- The native host may still be rebuilding when Modern returns.
            -- Parent reflow must not turn its deferred members into permanent
            -- standalone panels, even across another mode switch.
            do
                local savedNativeMember, savedPeerMember = copy(record("native")), copy(record("native-peer"))
                classicMode.value = 1; transmit(id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP)
                notes.frame.visible = false
                classicMode.value = 0; transmit(id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP)
                expect(native._nisNative, nil, "unavailable host defers mode-return docking")
                expect(peer._nisNative, nil, "unavailable host defers every native member")
                local fallbackY = native.root.y
                viewport:SetSize(960, 650); top:SetSize(960, 650); area:SetSize(0, 0, 1, 1)
                expect(native.root.y ~= fallbackY, true, "parent reflow moves the standalone fallback")
                advance(10)
                sameData(record("native"), savedNativeMember, "parent reflow preserves saved native membership")
                sameData(record("native-peer"), savedPeerMember, "parent reflow preserves peer native membership")
                expect(native._nisNativePending ~= nil, true, "parent reflow retains pending native target")
                expect(peer._nisNativePending ~= nil, true, "parent reflow retains pending peer target")
                classicMode.value = 1; transmit(id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP)
                classicMode.value = 0; transmit(id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP)
                viewport:SetSize(1000, 700); top:SetSize(1000, 700); area:SetSize(0, 0, 1, 1)
                notes.frame.visible = true
                advance(10)
                expect(native._nisNative ~= nil, true, "late host reclaims native member after repeated mode switches")
                expect(peer._nisNative.group, native._nisNative.group, "late host restores all pending members")
                expect(native._nisNative.group.active, native, "late host restores native selection")
                expect(Native.remember(native).index, nativeIndex, "late host restores native member order")
                expect(Native.remember(peer).index, peerIndex, "late host restores peer order")
                sameData(record("native"), savedNativeMember, "late host preserves original standalone bounds")
            end
            do
                local manual = create("pending-manual")
                expect(manual:DockTo(notes.frame), true, "manual-placement scenario starts natively docked")
                classicMode.value = 1; transmit(id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP)
                notes.frame.visible = false
                classicMode.value = 0; transmit(id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP)
                expect(manual._nisNativePending ~= nil, true, "manual placement starts with deferred native target")
                manual:SetSize(manual.root.width + 10, manual.root.height)
                expect(manual._nisNativePending, nil, "explicit resizing still clears deferred native target")
                expect(record("pending-manual").native, nil, "explicit resizing still saves standalone membership")
                notes.frame.visible = true
                advance(10)
                expect(manual._nisNative, nil, "manually resized fallback does not unexpectedly redock")
                native:SelectTab()
                manual:Destroy()
            end
            do
                local disabled = create("delay-disabled")
                local destroyed = create("delay-destroyed")
                expect(disabled:DockTo(notes.frame), true, "delayed cancellation starts with a docked member")
                expect(destroyed:DockTo(notes.frame), true, "delayed teardown starts with a docked member")
                native:SelectTab()
                classicMode.value = 1; transmit(id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP)
                classicMode.value = 0; transmit(id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP)
                advance(4)
                disabled:SetActive(false)
                destroyed:Destroy()
                classicMode.value = 1; transmit(id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP)
                advance(12)
                expect(native._nisNative, nil, "rapid Classic reentry cancels deferred Modern docking")
                expect(peer._nisNative, nil, "cancelled batch cannot redock another member in Classic")
                classicMode.value = 0; transmit(id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP)
                advance(9)
                expect(native._nisNative, nil, "rapid mode reentry starts a fresh settling interval")
                emit("Logic")
                expect(native._nisNative ~= nil, true, "latest mode return restores eligible native members")
                expect(disabled._nisNative, nil, "disabled panel is not resurrected by deferred work")
                expect(destroyed._nisNative, nil, "destroyed panel is not resurrected by deferred work")
                disabled:SetActive(true)
                expect(disabled._nisNative ~= nil, true, "explicit ribbon-style reactivation still docks immediately")
                expect(disabled._nisNative.group.active, disabled, "explicit reactivation selects the requested panel")
                disabled:Destroy()
                native:SelectTab()
            end
            classicMode.value = 1; transmit(id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP)
            native:Destroy(); peer:Destroy()
            local before = builds.native
            peer, native = create("native-peer"), create("native")
            expect(builds.native, before, "classic-first saved native host does not build eagerly")
            expect(native._nisNative, nil, "classic-first named host remains deferred")
            classicMode.value = 0; transmit(id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP)
            advance(10)
            expect(peer._nisNative.group, native._nisNative.group, "reversed registration rejoins saved native group")
            expect(native._nisNative.group.active, native, "reversed registration restores saved native selection")
            expect(Native.remember(native).index, nativeIndex, "classic-first native order restores by saved slot")
            expect(Native.remember(peer).index, peerIndex, "classic-first peer order restores by saved slot")
            peer:Destroy()
            Ribbon.Shutdown()
            restarted[#restarted + 1] = native
            area.parent, area.SetPos, area.SetSize = oldParent, oldPos, oldSize
            area:SetPos(0, 0); area:SetSize(1000, 700)
            ui.Interfaces.GetComponent = oldLookup
            for _, name in ipairs({ "TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP",
                "TOPLEVEL_V2__VIEWPORT", "TOPLEVEL_V2__GAMEVIEW_WINDOW" }) do id.Component[name] = named[name] end
            view:Destroy(); viewport:Destroy(); top:Destroy()
        end
        runNativeCycles()
        for _, owner in ipairs(restarted) do owner:Destroy() end
        expect(next(events.Logic), nil, "classic suspension releases native restoration observers")
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
    -- Real ribbon hooks drive real panels, including removal/restoration of a tab.
    do
        local RibbonBar = require("src/ribbon_bar")
        local oldString, oldBool = PersistentDB.GetString, PersistentDB.GetBool
        PersistentDB.GetString = function() return "left" end
        PersistentDB.GetBool = function() return false end
        config.Cursor.CURSOR_OPEN = { id = 7 }
        RibbonBar.Start()
        local owner = NisPanel.new(area, {
            categoryID = "auto", active = false, tabIcon = 910001, tabText = "Ribbon smoke",
            x = 30, y = 450, width = 250, height = 140,
            buildContent = function(panel) panel:AddText("Ribbon-mounted content") end,
        })
        local peer = NisPanel.new(area, {
            categoryID = "auto", tabIcon = 910002, x = 400, y = 300, width = 280, height = 180,
        })
        local function iconIn(node, spriteID)
            if node.spriteID == spriteID then return node end
            for _, child in ipairs(node.children) do
                local found = iconIn(child, spriteID)
                if found then return found end
            end
        end
        local cog = assert(iconIn(area, require("src/core/sprites").SPRITE_BUTTONS.SETTINGS.neutral))
        local ribbon = cog.parent.parent
        local button = assert(iconIn(ribbon, owner.tabIcon)).parent
        fire(button, ui.Hook.ONCLICK)
        expect(owner:IsActive(), true, "ribbon hook activates a first-use panel")
        expectRect(owner.root, 30, 450, 250, 140, "ribbon first opening uses plugin placement")
        expect(owner.content ~= nil, true, "ribbon first opening mounts real controls")
        expect(owner:DockTo(peer), true, "ribbon scenario docks a real panel")
        peer:SelectTab()
        fire(button, ui.Hook.ONCLICK)
        expect(owner:IsActive(), false, "ribbon hook disables an unselected tab")
        expect(owner._nisGroup, nil, "ribbon hook removes the disabled tab from its group")
        expect(owner.root.hidden, true, "disabled ribbon page has no visible shell")
        expect(peer._nisGroup, nil, "disabled ribbon tab leaves no empty tab slot")
        locked = true; transmit(12)
        fire(button, ui.Hook.ONCLICK)
        expect(owner._nisGroup, peer._nisGroup, "ribbon hook restores membership while locked")
        expect(owner._nisGroup.active, owner, "ribbon restoration selects real content")
        expectRect(owner.root, peer.root.x, peer.root.y, 280, 180, "ribbon restores previous bounds")
        owner:Destroy(); peer:Destroy()
        expect(ribbon.destroyed, true, "last real panel teardown removes the ribbon")
        RibbonBar.Shutdown()
        PersistentDB.GetString, PersistentDB.GetBool = oldString, oldBool
        locked = false; transmit(12)
    end
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

-- The retained modern shell and the classic content host can belong to
-- different interfaces. Exercise the dormant host path without a ribbon.
do
    local Components = require("src/core/components")
    local Tooltip = require("src/tooltip")
    local WorldMap = require("src/core/world_map")
    local function classicHost(interfaceID)
        local overlay = component(nil, "classic overlay parent")
        overlay.interfaceID = interfaceID
        Interfaces.component(overlay)
        overlay:SetSize(1000, 700)
        local body = Components.new(ui.Layer, overlay, { categoryID = "auto" })
        body:SetPos(480, 30)
        body:SetSize(360, 320)
        local context = Tooltip.registerContext(body, overlay, function(target)
            if target == body then return body.x, body.y end
            return body.x + (target.x or 0), body.y + (target.y or 0)
        end)
        return overlay, body, context
    end
    local overlay, body, hostContext = classicHost(4086)
    local shellInterfaceID = parent.interfaceID
    local buildsA, buildsB, cleanupsA, cleanupsB = 0, 0, 0, 0
    local sequence, rowA, rowB, tooltipA, nestedA
    classicMode.value = 1
    local a = NisPanel.new(parent, {
        categoryID = "auto", x = 120, y = 90, width = 300, height = 200,
        rowBackgroundColours = { 0x24211EFF, 0x2E2825FF },
        rowBackgroundEdgeToEdge = true,
        buildContent = function(owner)
            buildsA = buildsA + 1
            sequence[#sequence + 1] = "build A"
            rowA = owner:AddText("Classic A " .. buildsA)
            for index = 1, 28 do owner:AddText("Scrollable row " .. index) end
            local nested = owner:AddPanel({ height = 80 })
            nestedA = nested:AddText("Nested input")
            for index = 1, 8 do nested:AddText("Nested row " .. index) end
            tooltipA = Tooltip.attach(rowA, owner.content, "Classic tooltip")
            return function()
                expect(rowA.destroyed, nil, "classic cleanup sees live controls")
                expect(Tooltip.getContext(owner.content) ~= nil, true,
                    "classic cleanup precedes context removal")
                cleanupsA = cleanupsA + 1
                sequence[#sequence + 1] = "cleanup A"
            end
        end,
    })
    local b = NisPanel.new(parent, {
        categoryID = "auto", rowBackgroundColours = { 0x24211EFF },
        rowBackgroundEdgeToEdge = true,
        buildContent = function(owner)
            buildsB = buildsB + 1
            sequence[#sequence + 1] = "build B"
            rowB = owner:AddText("Classic B " .. buildsB)
            return function()
                cleanupsB = cleanupsB + 1
                sequence[#sequence + 1] = "cleanup B"
            end
        end,
    })
    local empty = NisPanel.new(parent, {
        categoryID = "auto", buildContent = function() return nil end,
    })
    expect(a.interfaceID, shellInterfaceID, "classic-first shell keeps its original interface")
    expect(a.root.hidden, true, "classic-first enabled shell stays hidden")
    expect(b.root.hidden, true, "second enabled shell stays hidden")
    expect(empty.root.hidden, true, "empty classic-first shell stays hidden")
    expect(a:IsActive(), true, "classic selection does not replace enabled state")
    expect(b:IsActive(), true, "other enabled page remains enabled")
    expect(buildsA, 0, "classic-first constructor does not eagerly build A")
    expect(buildsB, 0, "classic-first constructor does not eagerly build B")
    expect(a.content, nil, "classic-first shell has no mounted content")
    expect(b.content, nil, "unselected classic page has no content")
    a:_SetClassicMode(true)
    b:_SetClassicMode(true)
    empty:_SetClassicMode(true)
    expect(a.root.hidden, true, "idempotent classic suspension hides retained shell")
    expect(a.dragLayer.hidden, true, "classic suspension hides modern drag hitbox")
    expect(a.resize.handles.e.enabled, false, "classic suspension disables resize input")
    sequence = {}
    a:_SetClassicHost(body)
    a:_SyncContent(true)
    expect(buildsA, 1, "selecting A constructs content only once")
    expect(a._scroll.root.parent, body, "scroll viewport mounts on the shared body")
    expect(a.content.interfaceID, overlay.interfaceID, "classic content uses host interface")
    expect(a.interfaceID, shellInterfaceID, "hosting content preserves the shell interface identity")
    expect(a.root.hidden, true, "selected classic page does not expose its modern shell")
    expect(a.scrollbarVisible, true, "classic overflow uses the retained scroll core")
    local firstRow, firstNested, firstContent = rowA, nestedA, a.content
    local firstScroll, firstThumb = a._scroll.root, a._scroll.thumbDrag
    local firstContext = Tooltip.getContext(firstContent)
    expect(firstContext.parentContext, hostContext, "selected content inherits real host tooltip context")
    expect(firstContext.parent, overlay, "tooltip overlay belongs to the shared host's overlay parent")
    expect(firstThumb.parent, overlay, "scrollbar input overlay belongs to host's overlay parent")
    local absoluteX, absoluteY = a._scroll:_AbsolutePosition()
    expect(absoluteX, body.x, "scrollbar overlay origin uses host context x")
    expect(absoluteY, body.y, "scrollbar overlay origin uses host context y")
    tooltipA:Show()
    local firstTooltip = tooltipA.root
    expect(firstTooltip.parent, overlay, "selected content tooltip escapes the scroll clip")
    local rowCategory, rowDynamic = rowA.categoryID, rowA.dynamicID
    expect(ui.Interfaces:GetComponent(overlay.interfaceID, overlay.staticID, rowCategory, rowDynamic),
        rowA, "host's native namespace owns selected control ID")
    expect(a.rowBackgrounds[1] ~= nil, true, "hosted content creates row artwork")
    local firstBackground = a.rowBackgrounds[1]
    a:SetScrollPosition(90)
    expect(a.scrollY, 90, "selected page preserves scroll offset")
    local targetX, targetY = firstContext.position(rowA)
    expect(targetX, body.x + rowA.x, "tooltip x follows the host rather than hidden shell")
    expect(targetY, body.y + rowA.y - a.scrollY, "tooltip y accounts for hosted scroll offset")
    expect(firstThumb.hidden, false, "scroll synchronization ignores the hidden modern root")
    local overlayRoots = {}
    for root in pairs(a.overlays) do overlayRoots[#overlayRoots + 1] = root end
    expect(#overlayRoots > 0, true, "hosted scroll registers input overlays")

    local oldGet = ui.Interfaces.GetComponent
    function ui.Interfaces:GetComponent(packed, ...)
        if packed == id.Component.TOPLEVEL_V2__GAME_AREA then return parent end
        return oldGet(self, packed, ...)
    end
    local focus = var.VarClient.WORLDMAP_FOCUS
    focus.value = 0
    emit("VarTransmit", { var = focus, newValue = 0 })
    expect(WorldMap.isSuspended(), true, "classic host receives world-map focus")
    expect(body.hidden, true, "world map occludes the shared host")
    expect(a.content, firstContent, "map opening retains selected content")
    expect(a._scroll.root, firstScroll, "map opening retains scroll viewport")
    focus.value = -1
    emit("VarTransmit", { var = focus, newValue = -1 })
    emit("Logic")
    ui.Interfaces.GetComponent = oldGet
    expect(WorldMap.isSuspended(), false, "map close resumes shared host")
    expect(body.hidden, false, "map close restores selected shared host")
    expect(a.content, firstContent, "map return does not rebuild content")
    expect(a.scrollY, 90, "map return retains the selected page's scroll offset")
    expect(buildsA, 1, "map return never invokes A builder again")
    body:SetSize(360, 420)
    a._scroll:Refresh()
    expect(a.content, firstContent, "host resize retains content identity")
    expect(a.viewport.height, body.height, "host resize updates content viewport height")
    expect(a._scroll.thumbDrag.hidden, false, "host resize retains scrollbar input")

    a:_SetClassicHost(nil)
    expect(cleanupsA, 1, "outgoing A cleanup runs once")
    expect(a.content, nil, "clearing host releases selected A content")
    expect(a._scroll, nil, "clearing host releases A scroll tree")
    expect(firstRow.destroyed, true, "clearing host destroys A controls")
    expect(firstNested.destroyed, true, "clearing host destroys nested controls")
    expect(firstTooltip.destroyed, true, "clearing host destroys tooltip root")
    expect(firstScroll.destroyed, true, "clearing host destroys scroll viewport")
    expect(firstThumb.destroyed, true, "clearing host destroys sibling scrollbar input")
    expect(firstBackground.destroyed, true, "clearing host destroys row artwork")
    expect(a.interfaceID, shellInterfaceID, "releasing content preserves shell interface identity")
    expect(Tooltip.getContext(firstContent), nil, "clearing host unregisters tooltip context")
    expect(ui.Interfaces:GetComponent(overlay.interfaceID, overlay.staticID, rowCategory, rowDynamic),
        nil, "clearing host frees control ID in host interface")
    expect(next(a.overlays), nil, "clearing host unregisters every content-owned input overlay")
    for _, root in ipairs(overlayRoots) do
        expect(root.destroyed, true, "clearing host destroys each input overlay")
    end
    b:_SetClassicHost(body)
    b:_SyncContent(true)
    expect(sequence[1], "build A", "first classic page builds first")
    expect(sequence[2], "cleanup A", "outgoing cleanup precedes incoming construction")
    expect(sequence[3], "build B", "incoming builder follows outgoing cleanup")
    expect(buildsB, 1, "second page mounts exactly once")
    expect(b.root.hidden, true, "second selected page also keeps modern shell hidden")
    expect(b.rowBackgrounds[1].height, body.height,
        "edge-to-edge row artwork uses the selected host viewport height")
    expect(b.rowBackgrounds[1].height == b.surface.container.height, false,
        "row artwork does not use hidden shell dimensions")
    local firstB = rowB
    b:_SetClassicHost(nil)
    expect(cleanupsB, 1, "B cleanup runs on collapse")
    expect(firstB.destroyed, true, "B controls release before next page")
    empty:_SetClassicHost(body)
    empty:_SyncContent(true)
    expect(empty.content ~= nil, true, "empty builder still mounts a valid viewport")
    empty:_SetClassicHost(nil)
    expect(empty.content, nil, "empty page releases its viewport")
    a:_SetClassicHost(body)
    a:_SyncContent(true)
    expect(buildsA, 2, "reselecting A builds fresh handles")
    expect(rowA == firstRow, false, "reselected page never reuses expired controls")
    expect(a.scrollY, 90, "reselected page restores its own scroll position")
    a:_SetClassicHost(nil)
    expect(cleanupsA, 2, "second A mount also cleans up")
    a:Destroy(); b:Destroy(); empty:Destroy()

    local partial, partialTooltipRoot, buildFailure = nil, nil, true
    local failingBuild = NisPanel.new(parent, {
        categoryID = "auto", buildContent = function(owner)
            partial = owner:AddText("Partial classic construction")
            local partialTooltip = Tooltip.attach(partial, owner.content, "Partial classic tooltip")
            partialTooltip:Show()
            partialTooltipRoot = partialTooltip.root
            if buildFailure then error("injected classic builder failure") end
        end,
    })
    local ok, problem = pcall(function()
        failingBuild:_SetClassicHost(body)
        failingBuild:_SyncContent(true)
    end)
    expect(ok, false, "classic builder error propagates")
    expect(problem:find("injected classic builder failure", 1, true) ~= nil,
        true, "classic builder preserves original failure")
    expect(partial.destroyed, true, "failed classic builder destroys partial controls")
    expect(partialTooltipRoot.destroyed, true, "failed classic builder destroys partial tooltip")
    expect(failingBuild._scroll, nil, "failed classic builder releases scroll tree")
    expect(failingBuild.content, nil, "failed classic builder leaves no content")
    expect(next(failingBuild.overlays), nil, "failed classic builder releases input overlays")
    failingBuild:_SetClassicHost(nil)
    buildFailure = false
    failingBuild:_SetClassicHost(body)
    failingBuild:_SyncContent(true)
    expect(failingBuild.content ~= nil, true, "classic page remains usable after builder failure")
    failingBuild:_SetClassicHost(nil)
    failingBuild:Destroy()

    local cleanupRow, cleanupBuilds = nil, 0
    local failingCleanup = NisPanel.new(parent, {
        categoryID = "auto", buildContent = function(owner)
            cleanupBuilds = cleanupBuilds + 1
            cleanupRow = owner:AddText("Cleanup failure")
            return function() error("injected classic cleanup failure") end
        end,
    })
    failingCleanup:_SetClassicHost(body)
    failingCleanup:_SyncContent(true)
    ok, problem = pcall(function() failingCleanup:_SetClassicHost(nil) end)
    expect(ok, false, "classic cleanup error propagates")
    expect(problem:find("injected classic cleanup failure", 1, true) ~= nil,
        true, "classic cleanup preserves original failure")
    expect(cleanupRow.destroyed, true, "cleanup error still releases controls")
    expect(failingCleanup.content, nil, "cleanup error still clears content")
    expect(failingCleanup._scroll, nil, "cleanup error still releases Scroll")
    expect(next(failingCleanup.overlays), nil, "cleanup error still clears input overlays")
    expect(cleanupBuilds, 1, "cleanup failure cannot build a replacement page")
    failingCleanup:Destroy()
    local recovered = NisPanel.new(parent, {
        categoryID = "auto", buildContent = function(owner) owner:AddText("Recovered") end,
    })
    recovered:_SetClassicHost(body)
    recovered:_SyncContent(true)
    expect(recovered.content ~= nil, true, "shared host remains usable after cleanup failure")
    recovered:_SetClassicHost(nil)
    recovered:Destroy()
    Tooltip.unregisterContext(body)
    overlay:Destroy()

    local lostOverlay, lostHost = classicHost(4087)
    local lost = NisPanel.new(parent, {
        categoryID = "auto", buildContent = function(owner) owner:AddText("Unmount with host") end,
    })
    lost:_SetClassicHost(lostHost)
    lost:_SyncContent(true)
    expect(lost.content.interfaceID, 4087, "unload scenario mounts on another interface")
    Interfaces.unload(4087)
    lost:_SetClassicHost(nil)
    expect(lost.content, nil, "unloaded content host clears Lua ownership")
    expect(lost._scroll, nil, "unloaded content host releases scroll controller")
    expect(next(lost.overlays), nil, "unloaded content host clears overlay registry")
    lost:Destroy()
    Tooltip.unregisterContext(lostHost)
    classicMode.value = 0
end

-- Exercise the complete classic coordinator with real NisPanels, native space
-- reservation, and RibbonButton click hooks. The plugin layer is not the
-- interface that owns the retained modern shells or the native GAME_AREA.
do
    local RibbonBar = require("src/ribbon_bar")
    local Tooltip = require("src/tooltip")
    local ClassicLayout = require("src/core/classic_layout")
    local previousGet = ui.Interfaces.GetComponent
    local previousLayerNew = ui.Layer.new
    local previousNames = {}
    local names = {
        TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP = (4088 << 16) | 51,
        TOPLEVEL_V2__VIEWPORT = (4089 << 16) | 52,
        TOPLEVEL_V2__GAME_AREA = (4089 << 16) | 53,
        TOPLEVEL_V2__GAMEVIEW_WINDOW = (4089 << 16) | 54,
    }
    local nodes = {}
    for name, packed in pairs(names) do
        previousNames[name] = id.Component[name]
        id.Component[name] = packed
    end
    local function native(interfaceID, staticID, owner, x, y, xp, yp, xs, ys, w, h, wp, hp)
        local node = component(nil, "captured native")
        node.interfaceID, node.staticID = interfaceID, staticID
        Interfaces.component(node)
        node.parent = owner
        if owner then
            owner.children[#owner.children + 1] = node
            owner.renderChildren[#owner.renderChildren + 1] = node
        end
        function node:SetPos(px, py, ppx, ppy, psx, psy)
            self.position = { x = px, y = py, xParentPc = ppx or 0, yParentPc = ppy or 0,
                xSelfPc = psx or 0, ySelfPc = psy or 0 }
            self.x = px + (self.parent and self.parent.width or 0) * (ppx or 0)
                - self.width * (psx or 0)
            self.y = py + (self.parent and self.parent.height or 0) * (ppy or 0)
                - self.height * (psy or 0)
        end
        function node:SetSize(sw, sh, spx, spy)
            self.size = { width = sw, height = sh, widthParentPc = spx or 0,
                heightParentPc = spy or 0 }
            self.width = sw + (self.parent and self.parent.width or 0) * (spx or 0)
            self.height = sh + (self.parent and self.parent.height or 0) * (spy or 0)
            local p = self.position
            self:SetPos(p.x, p.y, p.xParentPc, p.yParentPc, p.xSelfPc, p.ySelfPc)
            for _, child in ipairs(self.children) do
                if child.Relayout then child:Relayout() end
            end
            self:EmitResize()
        end
        function node:Relayout()
            local s = self.size
            self:SetSize(s.width, s.height, s.widthParentPc, s.heightParentPc)
        end
        node:SetSize(w, h, wp, hp)
        node:SetPos(x, y, xp, yp, xs, ys)
        nodes[(interfaceID << 16) | staticID] = node
        return node
    end
    local top = native(4088, 51, nil, 0, 0, 0, 0, 0, 0, 3440, 1440, 0, 0)
    local viewport = native(4089, 52, nil, 0, 0, 0, 0, 0, 0, 3440, 1440, 0, 0)
    local area = native(4089, 53, viewport, 0, 0, .5, .5, .5, .5, 0, 0, 1, 1)
    local view = native(4089, 54, viewport, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1)
    local minimap = component(area, "captured minimap")
    minimap:SetSize(250, 250)
    minimap:SetPos(-25, 0, 1, 0, 1, 0)
    local nativeButton = component(area, "captured native ribbon")
    nativeButton:SetSize(32, 34)
    nativeButton:SetPos(-520, 0, 1, 0, 1, 0)
    function ui.Interfaces:GetComponent(packed, ...)
        if select("#", ...) == 0 and nodes[packed]
            and ui.Interfaces:GetInterface(math.floor(packed / 65536)) ~= nil then
            return nodes[packed]
        end
        return previousGet(self, packed, ...)
    end
    local function findSprite(node, icon)
        if node.spriteID == icon then return node end
        for _, child in ipairs(node.children) do
            local result = findSprite(child, icon)
            if result then return result end
        end
    end
    local function rail()
        for _, child in ipairs(top.children) do
            if not child.destroyed and findSprite(child, id.Sprite.RS3_ICON_MENU_SETTINGS) then
                return child
            end
        end
        for _, child in ipairs(top.children) do
            if not child.destroyed and child.kind == "layer" and child.width >= 44
                and child.height == top.height then return child end
        end
    end
    local function button(icon)
        local image = assert(findSprite(assert(rail(), "missing classic rail"), icon),
            "missing real ribbon icon")
        return image.parent
    end
    local function width(expected, label)
        local root = assert(rail(), label .. " rail")
        expectRect(root, top.width - expected, 0, expected, top.height, label .. " full-height rail")
        expect(area.x, 0, label .. " native left edge")
        expect(area.width, viewport.width - expected, label .. " native right edge")
        expect(view.width, viewport.width - expected, label .. " gameview")
        expect(minimap.x, area.width - 275, label .. " minimap right anchor")
        expect(nativeButton.x, area.width - 552, label .. " native button right anchor")
    end
    -- Model a bare category-zero host appearing before categorized artwork,
    -- with non-top-left constructor defaults. Its owner must establish both
    -- placement and rendering order explicitly.
    ui.Layer.new = function(owner, categoryID, dynamicID)
        local layer = previousLayerNew(owner, categoryID, dynamicID)
        if owner and owner.parent == top and categoryID == nil then
            layer:SetPos(0, 20, 0, .5, 0, .5)
            assert(removeRenderChild(owner, layer))
            table.insert(owner.renderChildren, 1, layer)
        end
        return layer
    end
    local function paintAt(node, x, y)
        if node.hidden or node.visibleGlobal == false or node.alpha == 0 then return nil end
        for index = #node.renderChildren, 1, -1 do
            local child = node.renderChildren[index]
            if x >= child.x and x < child.x + child.width
                and y >= child.y and y < child.y + child.height then
                local painted = paintAt(child, x - child.x, y - child.y)
                if painted then return painted end
            end
        end
        if node.kind == "text" or node.kind == "sprite" or node.kind == "rectangle" then return node end
    end
    local function expectTopContent(owner, row, reason)
        local scrollY = owner.scrollY
        owner:SetScrollPosition(0)
        local point = row.xyGlobal
        expect(point.y, 12, reason .. " content starts at the top flow inset")
        expect(paintAt(top, point.x + 1, point.y + 1), row,
            reason .. " text paints above sidebar background")
        local surface = assert(rail())
        local bodyPaint = assert(paintAt(top, surface.x + 5, top.height - 5))
        expect(bodyPaint.spriteID, require("src/core/sprites").NIS_PANEL.content,
            reason .. " content uses the lighter NisPanel backdrop")
        expect(bodyPaint.isTiling, true, reason .. " content backdrop tiles without stretching")
        local railPaint = assert(paintAt(top, surface.x + surface.width - 5, top.height - 5))
        expect(railPaint.spriteID, require("src/core/sprites").HUD_WINDOW.content,
            reason .. " ribbon rail keeps its dark backdrop")
        owner:SetScrollPosition(scrollY)
    end
    local sequence, counts, rows = {}, {}, {}
    local closed = 0
    local function make(name, extra)
        local options = {
            categoryID = "auto", tabIcon = 830000 + string.byte(name), tabText = "Classic " .. name,
            x = 130, y = 80, width = 300, height = 200,
            onClose = function() closed = closed + 1 end,
            buildContent = function(owner)
                counts[name] = (counts[name] or 0) + 1
                sequence[#sequence + 1] = "build " .. name
                rows[name] = owner:AddText("Page " .. name)
                local contentInterfaceID = owner.content.interfaceID
                if name == "A" then
                    for index = 1, 100 do owner:AddText("Scrollable " .. index) end
                    Tooltip.attach(rows[name], owner.content, "Classic page tooltip")
                end
                return function()
                    sequence[#sequence + 1] = "cleanup " .. name
                    if ui.Interfaces:GetInterface(contentInterfaceID) ~= nil then
                        expect(rows[name].destroyed, nil, "cleanup precedes native control release")
                    end
                end
            end,
        }
        for key, value in pairs(extra or {}) do options[key] = value end
        return NisPanel.new(parent, options)
    end
    config.Cursor.CURSOR_OPEN = { id = 7 }
    PersistentDB:SetString("ribbonBarPosition", "top")
    PersistentDB:SetBool("ribbonBarAutoHide", true)
    RibbonBar.Start()
    expect(#top.children, 0, "zero registered panels allocate no classic surface")
    classicMode.value = 1
    local a, b = make("A"), make("B")
    expect(a.root.hidden, true, "classic-first A shell stays hidden")
    expect(b.root.hidden, true, "classic-first B shell stays hidden")
    expect(a.content, nil, "classic-first enabled A does not build")
    expect(b.content, nil, "classic-first enabled B does not build")
    expect(#sequence, 0, "classic starts with no builders")
    expect(#top.children, 1, "two panels share a single independently mounted rail")
    width(44, "classic-first collapse")
    expect(RibbonBar.GetPosition(), "top", "saved modern top preference survives classic")
    expect(RibbonBar.GetAutoHide(), true, "saved modern auto-hide survives classic")
    fire(button(a.tabIcon), ui.Hook.ONCLICK)
    width(404, "first button expands")
    expect(button(a.tabIcon).children[1].spriteID,
        require("src/core/sprites").RIBBON_BUTTON_ACTIVE,
        "selected classic A alone receives the active real button state")
    expect(button(b.tabIcon).children[1].spriteID,
        require("src/core/sprites").RIBBON_BUTTON_NEUTRAL,
        "enabled but unselected B button remains neutral")
    expect(a.content.interfaceID, top.interfaceID, "content mounts in plugin-layer interface")
    expect(a.interfaceID, parent.interfaceID, "modern shell retains separate interface identity")
    expect(a.root.hidden, true, "selected classic page never exposes modern chrome")
    expect(b.content, nil, "unselected enabled B has no content")
    expect(counts.A, 1, "first click builds A exactly once")
    expectTopContent(a, rows.A, "first selected page")
    local firstA, firstRow, firstScroll = a.content, rows.A, a._scroll.root
    a:SetScrollPosition(90)
    local context = assert(Tooltip.getContext(a.content))
    expect(context.parent, top, "tooltips escape to full-screen plugin layer")
    expect(a._scroll.thumbDrag.parent, top, "scroll input uses full-screen plugin layer")
    local px, py = context.position(firstRow)
    expect(px, a._scroll.root.parent.x + firstRow.x + rail().x,
        "hosted tooltip x follows right-aligned sidebar")
    expect(py, firstRow.y - a.scrollY, "hosted tooltip y follows page scroll")
    fire(button(b.tabIcon), ui.Hook.ONCLICK)
    width(404, "switching pages keeps expanded reservation")
    expect(sequence[2], "cleanup A", "A cleanup happens before B builds")
    expect(sequence[3], "build B", "incoming B builds after outgoing cleanup")
    expect(firstRow.destroyed, true, "switch destroys outgoing consumer control")
    expect(firstScroll.destroyed, true, "switch destroys outgoing scroll viewport")
    expect(a.content, nil, "switch clears outgoing page ownership")
    expect(b.content ~= nil, true, "switch mounts one B page")
    expectTopContent(b, rows.B, "replacement page")
    expect(a:IsActive(), true, "switch keeps A enabled")
    expect(closed, 0, "switch never invokes Close callbacks")
    fire(button(b.tabIcon), ui.Hook.ONCLICK)
    width(44, "second B click collapses")
    do
        local surface = assert(rail())
        expect(assert(paintAt(top, surface.x + 5, top.height - 5)).spriteID,
            require("src/core/sprites").HUD_WINDOW.content, "collapsed rail has only the dark backdrop")
    end
    expect(b.content, nil, "collapse releases B page")
    expect(b:IsActive(), true, "collapse leaves B enabled")
    expect(closed, 0, "collapse never invokes Close callbacks")
    a:Show()
    expect(a.content ~= firstA, true, "programmatic Show creates fresh page handles")
    expect(a.scrollY, 90, "reselection restores A scroll position")
    local secondA = a.content
    a:SelectTab()
    a:SetActive(true)
    expect(a.content, secondA, "same-page programmatic selection does not rebuild")
    expect(counts.A, 2, "already-enabled Show and SetActive reuse selected content")
    b:SetActive(true)
    expect(b.content ~= nil, true, "already-enabled SetActive selects other page")
    b:Hide()
    width(44, "hiding selected page collapses")
    expect(b:IsActive(), false, "Hide disables only selected B")
    expect(a:IsActive(), true, "Hide preserves other enabled page")
    a:Show()
    b:Destroy()
    width(404, "removing unselected B preserves A")
    expect(a.content ~= nil, true, "unregistering another page keeps selected content")
    local selectedA = a.content
    a:SetSize(800, 400)
    a:Undock()
    expect(a:DockTo(parent), false, "classic cannot change remembered modern docking")
    expect(a.content, selectedA, "classic sizing leaves selected content mounted")
    local focus = var.VarClient.WORLDMAP_FOCUS
    focus.value = 0
    emit("VarTransmit", { var = focus, newValue = 0 })
    expect(a.content, selectedA, "map focus retains selected content identity")
    focus.value = -1
    emit("VarTransmit", { var = focus, newValue = -1 })
    emit("Logic")
    expect(a.content, selectedA, "map return does not rebuild selected page")
    expect(a.scrollY, 90, "map return keeps scroll position")
    viewport:SetSize(3200, 900)
    top:SetSize(3200, 900)
    game.options.InterfaceScale.setting = 125
    emit("Logic")
    width(404, "viewport and interface-scale resize")
    expect(a.content, selectedA, "resize keeps selected content identity")
    expect(a.scrollY, 90, "resize keeps selected scroll offset")
    expectTopContent(a, rows.A, "resized retained page")
    game.options.InterfaceScale.setting = 100
    viewport:SetSize(3440, 1440)
    top:SetSize(3440, 1440)
    emit("Logic")
    width(404, "viewport resize restored")
    expect(a.content, selectedA, "restored viewport does not rebuild content")
    a:Close()
    width(44, "Close releases and collapses the selected page")
    expect(closed, 1, "explicit Close retains callback semantics")
    expect(a:IsActive(), false, "Close disables selected page")
    a:Destroy()
    expect(#top.children, 0, "last registration removes the classic surface")
    expect(area.width, 3440, "last removal restores native area width")
    expect(area.position.xSelfPc, .5, "last removal restores native self-anchor")
    expect(view.width, 3440, "last removal restores gameview width")
    expect(ClassicLayout.restore(), true, "restoration remains idempotent")
    local partial, partialTooltip
    local failBuilder = make("C", { buildContent = function(owner)
        partial = owner:AddText("Partially built classic page")
        local tooltip = Tooltip.attach(partial, owner.content, "Partial tooltip")
        tooltip:Show()
        partialTooltip = tooltip.root
        error("classic builder exploded")
    end })
    local ok, problem = pcall(function() fire(button(failBuilder.tabIcon), ui.Hook.ONCLICK) end)
    expect(ok, false, "real ribbon propagates builder errors")
    expect(problem:find("classic builder exploded", 1, true) ~= nil, true,
        "real ribbon preserves original builder error")
    width(44, "builder failure collapses reservation")
    expect(partial.destroyed, true, "builder failure releases partial controls")
    expect(partialTooltip.destroyed, true, "builder failure releases partial tooltip")
    expect(failBuilder.content, nil, "builder failure relinquishes page ownership")
    expect(button(failBuilder.tabIcon).children[1].spriteID,
        require("src/core/sprites").RIBBON_BUTTON_NEUTRAL,
        "builder failure synchronizes the real button to collapsed")
    local good = make("D")
    fire(button(good.tabIcon), ui.Hook.ONCLICK)
    width(404, "another page works after builder error")
    expect(good.content ~= nil, true, "healthy panel mounts after failed builder")
    failBuilder:Destroy()
    expect(good.content ~= nil, true, "removing failed unselected panel keeps selected page")
    good:Destroy()
    expect(area.width, 3440, "removing selected final page restores native width")
    expect(#top.children, 0, "removing selected final page retires rail")

    local failingRow
    local failingCleanup = make("E", { buildContent = function(owner)
        failingRow = owner:AddText("Cleanup exception")
        return function() error("classic cleanup exploded") end
    end })
    local replacement = make("F")
    fire(button(failingCleanup.tabIcon), ui.Hook.ONCLICK)
    ok, problem = pcall(function() fire(button(replacement.tabIcon), ui.Hook.ONCLICK) end)
    expect(ok, false, "switching propagates outgoing cleanup errors")
    expect(problem:find("classic cleanup exploded", 1, true) ~= nil, true,
        "switching propagates the original outgoing cleanup error")
    width(44, "cleanup error collapses reservation")
    expect(failingRow.destroyed, true, "cleanup failure still destroys its controls")
    expect(replacement.content, nil, "cleanup failure never builds incoming page")
    expect(button(failingCleanup.tabIcon).children[1].spriteID,
        require("src/core/sprites").RIBBON_BUTTON_NEUTRAL,
        "cleanup failure synchronizes the outgoing button to collapsed")
    failingCleanup:Destroy()
    fire(button(replacement.tabIcon), ui.Hook.ONCLICK)
    expect(replacement.content ~= nil, true, "rail remains usable after cleanup error")
    replacement:Destroy()
    expect(area.width, 3440, "last removal after recovery restores native layout")
    expect(#top.children, 0, "last removal after recovery retires rail")
    -- Reconcile real modern groups on both directions of a base-var mode
    -- transmission. Classic page selection must not rewrite modern records.
    classicMode.value = 0
    transmit(id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP)
    local g = make("G", { id = "classic-ribbon:group-g", x = 80, y = 330 })
    local h = make("H", { id = "classic-ribbon:group-h", x = 500, y = 320 })
    expect(g:DockTo(h), true, "modern group is formed through public docking")
    h:SelectTab()
    local solo = make("L", { id = "classic-ribbon:standalone", x = 215, y = 250 })
    solo:SetSize(320, 230)
    local soloRect = { solo.root.x, solo.root.y, solo.root.width, solo.root.height }
    local soloBuilds = counts.L
    local function saved() return savedLayouts["prettyui.nis-layout.v1"] end
    local originalGroupID = saved().panels["classic-ribbon:group-g"].group
    local originalGroup = copy(saved().groups[originalGroupID])
    local originalG = copy(saved().panels["classic-ribbon:group-g"])
    local originalH = copy(saved().panels["classic-ribbon:group-h"])
    local modernHBuilds = counts.H
    for pass = 1, 2 do
        classicMode.value = 1
        transmit(id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP)
        width(44, "mode entry starts collapsed " .. pass)
        expect(g.root.hidden, true, "mode entry hides modern group shell G")
        expect(h.root.hidden, true, "mode entry hides modern group shell H")
        expect(g.content, nil, "mode entry does not build an unselected group page")
        expect(h.content, nil, "mode entry releases previously visible group content")
        expect(solo.content, nil, "classic entry releases modern standalone content")
        g:Show()
        width(404, "mode entry selects group page " .. pass)
        expect(g.content ~= nil, true, "enabled grouped page mounts in shared host")
        expect(h.content, nil, "modern group selection does not affect classic sidebar")
        expect(saved().groups[originalGroupID].active, originalGroup.active,
            "classic selection preserves saved modern group selection")
        expect(saved().panels["classic-ribbon:standalone"].x, soloRect[1],
            "classic selection does not persist standalone movement")
        if pass == 2 then
            local added = make("I", { id = "classic-ribbon:added-in-classic",
                dockTo = "classic-ribbon:group-g", active = false })
            expect(added.content, nil, "disabled classic-first member has no eager builder")
            expect(added:IsActive(), false, "disabled new page keeps its enabled flag")
            local transient = make("J")
            transient:Show()
            expect(transient.content ~= nil, true, "transient added page can be selected")
            transient:Destroy()
            width(44, "destroying selected transient collapses")
            added:Destroy()
            g:Show()
        end
        classicMode.value = 0
        transmit(id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP)
        expect(area.width, 3440, "mode exit restores native geometry " .. pass)
        expect(view.width, 3440, "mode exit restores gameview geometry " .. pass)
        expect(g.content, nil, "unselected group page is not rebuilt during restore")
        expect(h.content ~= nil, true, "modern saved group selection builds after restore")
        expect(counts.H, modernHBuilds + pass,
            "restoration builds the final selected group page once")
        expectRect(solo.root, soloRect[1], soloRect[2], soloRect[3], soloRect[4],
            "modern standalone bounds survive mode round trip " .. pass)
        expect(counts.L, soloBuilds + pass,
            "standalone content builds once after each complete restoration")
        expect(saved().groups[originalGroupID].active, originalGroup.active,
            "return restores modern selected group member")
        expect(saved().groups[originalGroupID].members[1], originalGroup.members[1],
            "return preserves saved tab order")
        expect(saved().panels["classic-ribbon:group-g"].x, originalG.x,
            "classic presentation does not persist group G position")
        expect(saved().panels["classic-ribbon:group-h"].width, originalH.width,
            "classic presentation does not persist group H dimensions")
        expect(RibbonBar.GetPosition(), "top", "mode exit preserves saved ribbon position")
        expect(RibbonBar.GetAutoHide(), true, "mode exit preserves saved ribbon auto-hide")
    end
    g:Destroy()
    h:Destroy()
    solo:Destroy()
    classicMode.value = 1
    transmit(id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP)
    local remounting = make("K")
    remounting:Show()
    width(404, "selected page before top interface unload")
    local topInterfaceID = top.interfaceID
    Interfaces.unload(topInterfaceID)
    emit("Logic")
    expect(remounting.content, nil, "unloaded plugin host releases selected consumer content")
    expect(area.width, 3440, "top-layer retirement restores live native geometry")
    top = native(4088, 51, nil, 0, 0, 0, 0, 0, 0, 3440, 1440, 0, 0)
    emit("Logic")
    width(44, "remounted plugin layer starts collapsed")
    remounting:Show()
    width(404, "remounted selected page")
    expectTopContent(remounting, rows.K, "remounted page")
    local shutdownBuilds = counts.K
    RibbonBar.Shutdown()
    expect(remounting.content, nil, "shutdown releases selected classic consumer content")
    expect(counts.K, shutdownBuilds, "shutdown never builds modern consumer content")
    expect(area.width, 3440, "shutdown restores reserved native geometry")
    expect(view.width, 3440, "shutdown restores reserved gameview geometry")
    remounting:Destroy()
    classicMode.value = 0
    RibbonBar.Shutdown()
    classicMode.value = 0
    ui.Interfaces.GetComponent = previousGet
    ui.Layer.new = previousLayerNew
    for name in pairs(names) do id.Component[name] = previousNames[name] end
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
