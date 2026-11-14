-- A small native/widget harness: the real RibbonButton owns the click hooks.
local function expect(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local loaded = {}
local area, top, viewport, gameview
local staticComponents = {}
local classicMode, modeReads = 0, 0
local nextDynamic = 0
local function component(parent, kind)
    nextDynamic = nextDynamic + 1
    local self = {
        kind = kind, parent = parent, children = {}, subscriptions = {},
        interfaceID = parent and parent.interfaceID or 10,
        staticID = parent and parent.staticID or 61,
        categoryID = 1, dynamicID = nextDynamic,
        width = 0, height = 0, x = 0, y = 0,
        cursorConfig = {}, opConfig = { SetOpCursor = function() end },
    }
    function self:SetPos(x, y, xAnchor, yAnchor, xSelf, ySelf)
        self.posWrites = (self.posWrites or 0) + 1
        self.x, self.y = x, y
        self.xAnchor, self.yAnchor = xAnchor, yAnchor
        self.xSelf, self.ySelf = xSelf, ySelf
    end
    function self:SetSize(width, height, widthParentPc, heightParentPc)
        self.sizeWrites = (self.sizeWrites or 0) + 1
        self.width, self.height = width, height
        self.widthParentPc, self.heightParentPc = widthParentPc, heightParentPc
    end
    function self:SetScrollSize(width, height, widthParentPc, heightParentPc)
        self.scrollWidth, self.scrollHeight = width, height
        self.scrollWidthParentPc, self.scrollHeightParentPc = widthParentPc, heightParentPc
    end
    function self:SetScrollPos(x, y) self.scrollX, self.scrollY = x, y end
    function self:Subscribe(hook, keyOrAction, action)
        self.subscriptions[hook] = action or keyOrAction
    end
    function self:MoveToFront() self.frontMoves = (self.frontMoves or 0) + 1 end
    function self:MoveToBack()
        if parent then
            for index, child in ipairs(parent.children) do
                if child == self then table.remove(parent.children, index); break end
            end
            table.insert(parent.children, 1, self)
        end
    end
    function self:Destroy()
        while #self.children > 0 do self.children[#self.children]:Destroy() end
        self.destroyed = true
        if parent then
            for index, child in ipairs(parent.children) do
                if child == self then table.remove(parent.children, index); break end
            end
        end
    end
    if parent then parent.children[#parent.children + 1] = self end
    return self
end
local function native(interfaceID, staticID, parent, position, dimensions)
    local result = component(parent, "native")
    result.interfaceID, result.staticID, result.categoryID, result.dynamicID =
        interfaceID, staticID, -1, -1
    result.x, result.y, result.width, result.height = nil, nil, nil, nil
    result.position, result.size = position, dimensions
    result.posWrites, result.sizeWrites = 0, 0
    setmetatable(result, { __index = function(self, field)
        if field == "width" then
            return self.size.width + (parent and parent.width or 0) * self.size.widthParentPc
        elseif field == "height" then
            return self.size.height + (parent and parent.height or 0) * self.size.heightParentPc
        elseif field == "x" then
            return self.position.x + (parent and parent.width or 0) * self.position.xParentPc
                - self.width * self.position.xSelfPc
        elseif field == "y" then
            return self.position.y + (parent and parent.height or 0) * self.position.yParentPc
                - self.height * self.position.ySelfPc
        end
    end })
    function result:SetPos(x, y, xp, yp, xs, ys)
        if self.isRestricted then error("native position restricted") end
        self.posWrites = self.posWrites + 1
        self.position = { x = x, y = y, xParentPc = xp, yParentPc = yp, xSelfPc = xs, ySelfPc = ys }
    end
    function result:SetSize(w, h, wp, hp)
        if self.isRestricted or self.failSize then error("native size restricted") end
        self.sizeWrites = self.sizeWrites + 1
        self.size = { width = w, height = h, widthParentPc = wp, heightParentPc = hp }
    end
    staticComponents[(interfaceID << 16) | staticID] = result
    loaded[interfaceID] = loaded[interfaceID] or {}
    return result
end
local function gameArea(interfaceID, width, height)
    width, height = width or 800, height or 600
    top = native(interfaceID + 1000, 71, nil,
        { x = 0, y = 0, xParentPc = 0, yParentPc = 0, xSelfPc = 0, ySelfPc = 0 },
        { width = width, height = height, widthParentPc = 0, heightParentPc = 0 })
    viewport = native(interfaceID, 75, nil,
        { x = 0, y = 0, xParentPc = 0, yParentPc = 0, xSelfPc = 0, ySelfPc = 0 },
        { width = width, height = height, widthParentPc = 0, heightParentPc = 0 })
    local result = native(interfaceID, 81, viewport,
        { x = 0, y = 0, xParentPc = .5, yParentPc = .5, xSelfPc = .5, ySelfPc = .5 },
        { width = 0, height = 0, widthParentPc = 1, heightParentPc = 1 })
    gameview = native(interfaceID, 87, viewport,
        { x = 0, y = 0, xParentPc = 0, yParentPc = 0, xSelfPc = 0, ySelfPc = 0 },
        { width = 0, height = 0, widthParentPc = 1, heightParentPc = 1 })
    if id then
        id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP = ((interfaceID + 1000) << 16) | 71
        id.Component.TOPLEVEL_V2__VIEWPORT = (interfaceID << 16) | 75
        id.Component.TOPLEVEL_V2__GAME_AREA = (interfaceID << 16) | 81
        id.Component.TOPLEVEL_V2__GAMEVIEW_WINDOW = (interfaceID << 16) | 87
    end
    return result
end
area = gameArea(10)
ui = {
    Layer = {}, Sprite = {},
    Hook = { ONCLICK = 1, ONMOUSEOVER = 2, ONMOUSELEAVE = 3, ONSCROLLWHEEL = 4 },
    Interfaces = {
        GetComponent = function(_, a, b, c, d)
            if d ~= nil then
                if not loaded[a] then return nil end
                local function search(node)
                    if node.interfaceID == a and node.staticID == b
                        and node.categoryID == c and node.dynamicID == d then return node end
                    for _, child in ipairs(node.children or {}) do
                        local found = search(child)
                        if found then return found end
                    end
                end
                return search(staticComponents[(a << 16) | b] or {})
            end
            local packed = b and (a << 16) | b or a
            local result = staticComponents[packed]
            return result and loaded[result.interfaceID] and result or nil
        end,
        GetInterface = function(_, interfaceID) return loaded[interfaceID] end,
    },
}
ui.Layer.new = function(parent) return component(parent, "layer") end
ui.Sprite.new = function(parent) return component(parent, "sprite") end
id = {
    Component = {
        TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP = (1010 << 16) | 71,
        TOPLEVEL_V2__VIEWPORT = (10 << 16) | 75,
        TOPLEVEL_V2__GAME_AREA = (10 << 16) | 81,
        TOPLEVEL_V2__GAMEVIEW_WINDOW = (10 << 16) | 87,
    },
    VarPlayer = {
        TOPLEVEL_V2_GENERAL_VARP = 101, TOPLEVEL_V2_CUSTOMIZATION_LOCK = 102,
        TOPLEVEL_V2_SKINS_VARP = 103, TOPLEVEL_V2_TRANSPARENCY = 104,
    },
    Sprite = setmetatable({}, { __index = function(_, key) return key end }),
}
var = { VarPlayer = {
    TOPLEVEL_V2_LEGACY_INTERFACE = setmetatable({}, { __index = function(_, key)
        if key == "value" then modeReads = modeReads + 1; return classicMode end
    end }),
    TOPLEVEL_V2_CUSTOMIZATION_LOCK = { value = 0 },
    TOPLEVEL_V2_TRANSPARENCY = { value = 0 },
} }
config = { Cursor = { CURSOR_OPEN = { id = 7 } } }
local events, varEvents = {}, {}
Event = {
    Logic = {
        Subscribe = function(key, callback) events[key] = callback end,
        Unsubscribe = function(key) events[key] = nil end,
    },
    VarTransmit = {
        Subscribe = function(key, callback) varEvents[key] = callback end,
        Unsubscribe = function(key) varEvents[key] = nil end,
    },
}
local db = { ribbonBarPosition = "right", ribbonBarAutoHide = false }
PersistentDB = {
    GetString = function(_, key) return db[key] end,
    GetBool = function(_, key) return db[key] end,
    SetString = function(_, key, value) db[key] = value end,
    SetBool = function(_, key, value) db[key] = value end,
}
local components = { roots = {} }
function components.sameComponent(first, second)
    return first == second or first ~= nil and second ~= nil
        and first.interfaceID == second.interfaceID and first.staticID == second.staticID
        and first.categoryID == second.categoryID and first.dynamicID == second.dynamicID
end
function components.new(nativeType, parent, options)
    local result = nativeType.new(parent)
    if parent == area or parent == top then
        expect(options.categoryID, "auto", "shared root uses safe automatic allocation")
        result.categoryID = 0
        result.ribbonSurface = true
    end
    return result
end
function components.newContent(parent)
    local result = ui.Layer.new(parent)
    result.categoryID = 0
    return result
end
function components.setHidden(target, hidden) target.hidden = hidden == true end
local tooltips = { contexts = 0, unregistered = 0, unbound = 0, hidden = 0, forTarget = {},
    contextOrigins = {}, contextParents = {} }
function tooltips.registerContext(owner, parent, origin)
    tooltips.contexts = tooltips.contexts + 1
    tooltips.contextOrigins[owner], tooltips.contextParents[owner] = origin, parent
end
function tooltips.unregisterContext(owner)
    tooltips.unregistered = tooltips.unregistered + 1
    tooltips.contextOrigins[owner], tooltips.contextParents[owner] = nil, nil
end
function tooltips.hideContextTooltips() tooltips.hidden = tooltips.hidden + 1 end
function tooltips.moveContextTooltipsToFront() end
function tooltips.bind(owner, target, _, text)
    owner.tooltipValue = text
    owner.tooltipTarget = target
    tooltips.forTarget[target] = text
end
function tooltips.set(owner, text)
    owner.tooltipValue = text
    tooltips.forTarget[owner.tooltipTarget] = text
    return true
end
function tooltips.unbind(owner)
    tooltips.forTarget[owner.tooltipTarget] = nil
    owner.tooltipTarget, owner.tooltipValue = nil, nil
    tooltips.unbound = tooltips.unbound + 1
end
local map = { suspended = false, watches = {} }
function map.watch(owner, callback)
    map.watches[owner] = callback
    callback(map.suspended)
end
function map.unwatch(owner) map.watches[owner] = nil end
function map.isSuspended() return map.suspended end
local windows = {}
local Window = {}
function Window.new(parent, options)
    expect(parent, classicMode == 1 and top or area, "settings use current mode's full game parent")
    expect(options.categoryID, "auto", "settings use automatic allocation")
    local instance = { options = options, content = {}, controls = {} }
    windows[#windows + 1] = instance
    function instance:AddTitle(text) self.content[#self.content + 1] = text end
    function instance:AddText(text) self.content[#self.content + 1] = text end
    function instance:AddRadioButton(values)
        local result = { values = values }
        function result:SetSelectedValue(value) self.selected = value end
        self.controls.position = result
        return result
    end
    function instance:AddCheckboxButton(values)
        local result = { values = values }
        function result:SetSelected(_, value) self.selected = value end
        self.controls.autoHide = result
        return result
    end
    function instance:Show() self.visible = true end
    function instance:Close() self.options.onClose(); self.visible = false end
    function instance:Destroy() self.destroyed = true end
    return instance
end
package.loaded["src/core/components"] = components
package.loaded["src/tooltip"] = tooltips
package.loaded["src/core/world_map"] = map
package.loaded["src/core/wheel"] = require("src/core/wheel")
package.loaded["src/core/mouse"] = { GetPosition = function() return nil end }
package.loaded["src/window"] = Window

package.loaded["src/core/nis_group"] = { resume = function() end }
package.loaded["src/core/nis_persistence"] = { setActive = function() return false end }
package.loaded["src/core/nis_native"] = {
    remember = function() return nil end, register = function() end,
}
local RibbonBar = require("src/ribbon_bar")
local function click(button)
    return assert(button.root.subscriptions[ui.Hook.ONCLICK], "real RibbonButton hook missing")(button.root)
end
local function buttons()
    local surface
    for _, parent in ipairs({ area, top }) do
        if parent and loaded[parent.interfaceID] then
            for _, child in ipairs(parent.children) do
                if child.ribbonSurface and not child.destroyed then surface = child; break end
            end
        end
        if surface then break end
    end
    local result = {}
    local function collect(node)
        if node.kind == "layer" and node.subscriptions[ui.Hook.ONCLICK] then
            result[#result + 1] = node
        end
        for _, child in ipairs(node.children) do collect(child) end
    end
    if surface then collect(surface) end
    return surface, result
end
local function panel(icon, text, active)
    local result = {
        parent = area, root = component(area, "panel shell"),
        interfaceID = area.interfaceID, tabIcon = icon, tabText = text,
        active = active, calls = 0,
    }
    function result:IsActive() return self.active end
    function result:SetActive(value)
        self.active = value
        self.calls = self.calls + 1
    end
    return result
end
RibbonBar.Start()
expect(RibbonBar.GetPosition(), "right", "stored ribbon placement restored")
expect(events.prettyui_ribbon_bar ~= nil, true, "logic mount listener installed")
expect(buttons(), nil, "zero panels do not allocate ribbon")
expect(modeReads, 0, "zero registrations never consult live classic mode")
assert(events.prettyui_ribbon_bar)()
expect(modeReads, 0, "zero-registration logic avoids mode/native lookup")
local first = panel("first tab icon", "First", true)
local second = panel("second tab icon", nil, true)
RibbonBar.register(first)
RibbonBar.register(second) -- No stable ID is required.
local surface, roots = buttons()
expect(surface ~= nil, true, "ribbon mounts after registration")
expect(#roots, 3, "settings plus both panels have buttons")
expect(roots[2].children[2].spriteID, first.tabIcon, "first tab icon matches")
expect(roots[3].children[2].spriteID, second.tabIcon, "second tab icon matches")
expect(roots[3].children[2].spriteID ~= roots[2].children[2].spriteID, true, "icons do not substitute")
expect(roots[2].parent, surface, "first button belongs to ribbon")
expect(roots[3].parent, surface, "second button belongs to ribbon")
expect(tooltips.forTarget[roots[2]], "First", "tooltip matches tab text")
expect(tooltips.forTarget[roots[3]], "Panel", "missing tab text uses Panel")
expect(roots[2].children[1].spriteID, id.Sprite.RS3_BTN_MENU_7_3,
    "unselected but enabled tab is active")
expect(roots[3].children[1].spriteID, id.Sprite.RS3_BTN_MENU_7_3,
    "another unselected enabled tab is active")
local idleSizeWrites, idleButtonMoves = surface.sizeWrites, roots[2].posWrites
for _ = 1, 20 do events.prettyui_ribbon_bar() end
expect(surface.sizeWrites, idleSizeWrites, "idle ribbon does not retrigger root resize/layout")
expect(roots[2].posWrites, idleButtonMoves, "idle ribbon leaves button layout untouched")
local buttonOne, buttonTwo = roots[2], roots[3]
click({ root = buttonTwo })
RibbonBar.sync(second)
expect(second.calls, 1, "button toggles panel via SetActive")
expect(second:IsActive(), false, "click deactivates an unselected panel")
expect(second.root ~= nil, true, "deactivation retains the shell")
expect(buttonTwo.children[1].spriteID, id.Sprite.RS3_BTN_MENU_7_2, "inactive button clears active highlight")
local _, afterToggle = buttons()
expect(#afterToggle, 3, "inactive panel keeps its ribbon button")
click({ root = buttonTwo })
expect(second:IsActive(), true, "second click reactivates panel")
expect(buttonTwo.children[1].spriteID, id.Sprite.RS3_BTN_MENU_7_3, "reactivated highlight restores")
expect(buttonOne.x, 6, "vertical first panel x position")
expect(buttonTwo.y, 6 + 2 * (32 + 2), "second panel retains order")
second.tabIcon, second.tabText = "updated tab icon", "Updated"
RibbonBar.sync(second)
expect(buttonTwo.children[2].spriteID, second.tabIcon, "sync refreshes tab icon")
expect(tooltips.forTarget[buttonTwo], "Updated", "sync refreshes tab tooltip")
click({ root = roots[1] })
expect(#windows, 1, "cog opens ribbon settings window")
expect(windows[1].options.title, "Ribbon settings", "window is dedicated to ribbon")
expect(#windows[1].content, 2, "settings contain only ribbon controls")
expect(windows[1].controls.position.values[3].value, "top", "position options retained")
expect(windows[1].controls.autoHide.values[1].value, "autoHide", "auto-hide option retained")
expect(first.calls + second.calls, 2, "settings cog does not touch panel activation")
click({ root = roots[1] })
expect(windows[1].visible, false, "cog closes the settings window")
RibbonBar.SetPosition("top")
RibbonBar.SetAutoHide(true)
expect(db.ribbonBarPosition, "top", "position uses original storage key")
expect(db.ribbonBarAutoHide, true, "auto-hide uses original storage key")
expect(RibbonBar.GetAutoHide(), true, "auto-hide accessor returns current setting")
expect(buttonTwo.x, 6 + 2 * (32 + 2), "top position lays buttons horizontally")
local animationSizeWrites, animationButtonMoves = surface.sizeWrites, buttonTwo.posWrites
events.prettyui_ribbon_bar()
expect(surface.y, -8, "auto-hide advances one slide step")
for _ = 1, 10 do events.prettyui_ribbon_bar() end
expect(surface.y, -44, "auto-hide reaches the hidden top edge")
expect(surface.sizeWrites, animationSizeWrites, "slide animation does not resize the ribbon")
expect(buttonTwo.posWrites, animationButtonMoves, "slide animation retains child layout")
RibbonBar.SetAutoHide(false)
for _ = 1, 10 do events.prettyui_ribbon_bar() end
expect(surface.y, 0, "disabling auto-hide slides the ribbon fully into view")
RibbonBar.SetAutoHide(true)
map.suspended = true
map.watches[surface](true)
expect(tooltips.hidden, 1, "map hides ribbon tooltips")
expect(second:IsActive(), true, "map occlusion does not deactivate panels")
map.suspended = false
RibbonBar.unregister(first)
expect(buttonOne.destroyed, true, "unregister releases the panel button")
local _, remaining = buttons()
expect(#remaining, 2, "first unregister keeps the surface and other panel")
expect(remaining[2], buttonTwo, "remaining button is retained")
RibbonBar.unregister(second)
expect(surface.destroyed, true, "unregister last destroys ribbon surface")
expect(windows[1].destroyed, true, "last unregister destroys settings window")
expect(tooltips.unregistered, 1, "last unregister cleans tooltip context")
expect(map.watches[surface], nil, "last unregister cleans map watcher")
expect(buttons(), nil, "last unregister removes ribbon from game area")
expect(tooltips.forTarget[buttonOne], nil, "unregister releases button tooltip")
expect(tooltips.forTarget[buttonTwo], nil, "last unregister releases button tooltip")

local retired = panel("retired", "Old panel", true)
RibbonBar.register(retired)
local oldSurface, oldButtons = buttons()
loaded[10] = nil
area = nil
assert(events.prettyui_ribbon_bar)()
expect(tooltips.unregistered, 2, "unloaded interface retires tooltip context")
expect(map.watches[oldSurface], nil, "unloaded interface retires world-map watcher")
expect(#oldButtons, 2, "old surface had a settings and panel button")
area = gameArea(20)
loaded[20] = true
assert(events.prettyui_ribbon_bar)()
expect(buttons(), nil, "remount cannot resurrect stale panel buttons")
local fresh = panel("fresh tab icon", "Fresh", false)
RibbonBar.register(fresh)
local freshSurface, freshButtons = buttons()
expect(freshSurface ~= oldSurface, true, "remount uses a fresh surface")
expect(#freshButtons, 2, "remount has only fresh panel")
expect(freshButtons[2].children[2].spriteID, fresh.tabIcon, "fresh icon matches tab")
RibbonBar.unregister(fresh)
local destroyedPanel = panel("destroyed", "Destroyed", true)
RibbonBar.register(destroyedPanel)
destroyedPanel._destroyed = true
assert(events.prettyui_ribbon_bar)()
expect(buttons(), nil, "logic retires panels destroyed without unregister")
local replaced = panel("replaced", "Replaced", true)
RibbonBar.register(replaced)
area = gameArea(30)
loaded[30] = true
local arriving = panel("arriving", "Arriving", true)
RibbonBar.register(arriving)
local _, arrivingButtons = buttons()
expect(#arrivingButtons, 2, "registration during remount retains the new panel only")
expect(arrivingButtons[2].children[2].spriteID, arriving.tabIcon, "new registration survives remount cleanup")
RibbonBar.unregister(arriving)
RibbonBar.Shutdown()
expect(events.prettyui_ribbon_bar, nil, "shutdown unsubscribes logic")
expect(next(map.watches), nil, "shutdown leaves no map watcher")
expect(tooltips.contexts, tooltips.unregistered, "every tooltip context is retired")

-- The real button hooks now drive a shared Classic sidebar, not two
-- independent modern shell activations. Panel doubles model only the alternate
-- content-host contract; the rail, buttons, geometry and native helper are real.
local function mode(value)
    classicMode = value
    assert(varEvents.prettyui_ribbon_bar, "base-variable listener missing")({
        var = { id = id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP },
    })
end
local function tick() assert(events.prettyui_ribbon_bar, "logic listener missing")() end
local function buttonNamed(text)
    local _, roots = buttons()
    for _, rootButton in ipairs(roots) do
        if tooltips.forTarget[rootButton] == text then return rootButton end
    end
    error("button not found: " .. text)
end
local function clickRoot(rootButton)
    return click({ root = rootButton })
end
local function screenLeft(surface)
    return (surface.xAnchor or 0) * top.width + surface.x
        - (surface.xSelf or 0) * surface.width
end
local function rail(width, description)
    local surface = assert(buttons(), description .. " surface absent")
    expect(surface.parent, top, description .. " mounts outside reduced GAME_AREA")
    expect(surface.width, width, description .. " visible width")
    expect(surface.height, top.height, description .. " full screen height")
    expect(screenLeft(surface), top.width - width, description .. " flush right")
    expect(surface.y, 0, description .. " starts at top")
    expect(area.x, 0, description .. " native left edge")
    expect(area.width, viewport.width - width, description .. " native reserved width")
    return surface
end
local lifecycle = {}
local function classicPanel(name, enabled)
    local result = panel("icon-" .. name, name, enabled)
    result.builds, result.releases = 0, 0
    result._contentReady = true
    function result:_SetClassicMode(value)
        self._nisClassic = value
        if value then self._contentReady = false
        else self:_SetClassicHost(nil); self._nisClassicState = nil end
        self.root.hidden = value
    end
    function result:_SetClassicHost(host)
        if self.classicHost == host then return end
        if self.classicHost then
            self.releases = self.releases + 1
            lifecycle[#lifecycle + 1] = self.tabText .. ":release"
        end
        self.classicHost = host
        if host then
            self.builds = self.builds + 1
            lifecycle[#lifecycle + 1] = self.tabText .. ":build"
        end
    end
    function result:SetActive(value)
        self.active, self.calls = value, self.calls + 1
        if classicMode == 1 then
            if value then RibbonBar.selectClassic(self, false)
            elseif RibbonBar.isClassicSelected(self) then RibbonBar.selectClassic(self, true) end
        end
        RibbonBar.sync(self)
    end
    function result:_LayoutBody() end
    function result:_SyncChrome() end
    function result:_SyncOverlays() end
    function result:_SyncContent() end
    function result:RefreshRowBackgrounds() end
    return result
end

area = gameArea(40, 3440, 1440)
RibbonBar.Start()
local a, b, disabled = classicPanel("A", true), classicPanel("B", true), classicPanel("Disabled", false)
RibbonBar.register(a)
RibbonBar.register(b)
RibbonBar.register(disabled)
local modernBefore = assert(buttons())
classicMode = 1
assert(varEvents.prettyui_ribbon_bar)({ var = { id = id.VarPlayer.TOPLEVEL_V2_SKINS_VARP } })
expect(buttons(), modernBefore, "unrelated var transmission does not switch ribbon mode")
classicMode = 0
expect(varEvents.prettyui_ribbon_bar ~= nil, true, "VarTransmit subscription installed")
mode(1)
expect(modernBefore.destroyed, true, "mode entry retires the modern ribbon surface")
local classicSurface = rail(44, "classic mode entry")
expect(a.root.hidden and b.root.hidden and disabled.root.hidden, true, "modern panel shells hidden")
expect(a.builds + b.builds + disabled.builds, 0, "enabled classic panels do not eagerly build")
expect(RibbonBar.isClassicSelected(a), false, "mode entry starts collapsed despite enabled panels")
expect(gameview.width, 3396, "gameview reservation follows the rail")
expect(buttonNamed("Ribbon settings").x, 6, "collapsed settings stays on 44-unit rail")
expect(buttonNamed("Ribbon settings").y, 6, "settings stays fixed at top")
expect(area.position.xParentPc, 0, "reservation explicitly replaces centered parent anchor")
expect(area.position.xSelfPc, 0, "reservation explicitly replaces centered self anchor")
expect(area.position.yParentPc, 0, "reservation explicitly replaces vertical parent anchor")
expect(area.position.ySelfPc, 0, "reservation explicitly replaces vertical self anchor")
expect(tooltips.contextParents[classicSurface], top, "classic tooltip uses full-screen top layer")
expect(buttonNamed("A").children[1].spriteID, id.Sprite.RS3_BTN_MENU_7_2,
    "enabled but unselected A has no highlight")
expect(buttonNamed("B").children[1].spriteID, id.Sprite.RS3_BTN_MENU_7_2,
    "enabled but unselected B has no highlight")
local aButton, bButton = buttonNamed("A"), buttonNamed("B")
clickRoot(aButton)
rail(404, "A expanded")
expect(gameview.width, 3036, "expanded gameview reserves the full content and rail")
expect(a.classicHost.parent, classicSurface, "selected body is a child of full-screen rail")
expect(a.classicHost.width, 360, "selected body owns fixed content width")
expect(a.classicHost.height, 1440, "selected body fills screen height")
expect(tooltips.contextParents[a.classicHost], top,
    "selected content tooltip context uses the unparented full-screen layer")
local bodyOriginX, bodyOriginY = tooltips.contextOrigins[a.classicHost]({ x = 0, y = 0 })
expect(bodyOriginX, screenLeft(classicSurface), "content tooltips align with body left edge")
expect(bodyOriginY, 0, "content tooltips align with screen top")
expect(buttonNamed("Ribbon settings").x, 366, "expanded settings stays in rightmost rail")
expect(RibbonBar.isClassicSelected(a), true, "first button selects A")
expect(a.builds, 1, "A built exactly once")
expect(b.builds, 0, "B remains unbuilt")
expect(aButton.children[1].spriteID, id.Sprite.RS3_BTN_MENU_7_3, "A selected highlight")
local expandedSizeWrites, bodySizeWrites = classicSurface.sizeWrites, a.classicHost.sizeWrites
local expandedButtonMoves = aButton.posWrites
for _ = 1, 20 do tick() end
expect(classicSurface.sizeWrites, expandedSizeWrites, "idle expanded sidebar does not resize its shell")
expect(a.classicHost.sizeWrites, bodySizeWrites, "idle expanded sidebar does not resize consumer content")
expect(aButton.posWrites, expandedButtonMoves, "idle expanded sidebar does not relayout icons")
expect(a.builds, 1, "idle sidebar retains the current content mount")
clickRoot(bButton)
rail(404, "B replaces A")
expect(RibbonBar.isClassicSelected(b), true, "second button selects B")
expect(a:IsActive() and b:IsActive(), true, "selection does not change enabled state")
expect(lifecycle[2], "A:release", "outgoing content released before replacement")
expect(lifecycle[3], "B:build", "incoming content built after cleanup")
expect(aButton.children[1].spriteID, id.Sprite.RS3_BTN_MENU_7_2, "A clears selected highlight")
expect(bButton.children[1].spriteID, id.Sprite.RS3_BTN_MENU_7_3, "B alone highlighted")
clickRoot(bButton)
rail(44, "selected button collapses")
expect(RibbonBar.isClassicSelected(b), false, "B collapse clears selection")
expect(b:IsActive(), true, "collapse does not disable B")
expect(b.releases, 1, "B content released on collapse")
local nativeWrites = area.posWrites + area.sizeWrites + gameview.sizeWrites
tick()
expect(area.posWrites + area.sizeWrites + gameview.sizeWrites, nativeWrites,
    "repeated reconciliation does not rewrite unchanged native descriptors")
expect(gameview.width, 3396, "gameview collapse is not cumulative")
expect(RibbonBar.selectClassic(a, false), true, "programmatic already-enabled selection works")
rail(404, "programmatic selection")
expect(RibbonBar.selectClassic(a, false), true, "same-page selection succeeds without rebuild")
expect(a.builds, 2, "same-page selection reuses content")
expect(RibbonBar.selectClassic(a, true), true, "toggle collapses selected panel")
rail(44, "programmatic collapse")
top:SetSize(45, 120, 0, 0)
viewport:SetSize(45, 120, 0, 0)
tick()
rail(44, "one-unit native area")
expect(RibbonBar.selectClassic(a, false), false, "zero-width body cannot expand")
expect(a.builds, 2, "zero-width body does not build content")
top:SetSize(3440, 1440, 0, 0)
viewport:SetSize(3440, 1440, 0, 0)
tick()
rail(44, "normal viewport restores rail without selecting")
local disabledButton = buttonNamed("Disabled")
clickRoot(disabledButton)
rail(404, "disabled first click")
expect(disabled:IsActive(), true, "disabled first click enables panel")
expect(RibbonBar.isClassicSelected(disabled), true, "disabled first click does not double-collapse")
expect(disabled.builds, 1, "disabled panel builds once")
expect(RibbonBar.selectClassic({ root = area, interfaceID = area.interfaceID }, false), false,
    "unregistered page cannot select")
local gone = classicPanel("Gone", true)
RibbonBar.register(gone)
gone._destroyed = true
expect(RibbonBar.selectClassic(gone, false), false, "destroyed page cannot select")
tick()
expect(buttons() ~= nil, true, "destroyed registration is pruned without discarding live rail")
local settingsButtonRoot = buttonNamed("Ribbon settings")
clickRoot(settingsButtonRoot)
local classicSettings = windows[#windows]
expect(#classicSettings.content, 2, "classic settings keep title and explanatory text")
expect(classicSettings.content[2],
    "Classic Interface uses a fixed right sidebar; position and auto-hide apply in Modern Interface.",
    "classic settings state saved-modern-only preference")
expect(classicSettings.controls.position, nil, "classic settings have no position control")
expect(classicSettings.controls.autoHide, nil, "classic settings have no auto-hide control")
expect(RibbonBar.GetPosition(), "top", "saved modern position survives classic entry")
expect(RibbonBar.GetAutoHide(), true, "saved modern auto-hide survives classic entry")
expect(db.ribbonBarPosition, "top", "classic layout does not overwrite saved position")
expect(db.ribbonBarAutoHide, true, "classic layout does not overwrite auto-hide")
clickRoot(settingsButtonRoot)
expect(classicSettings.visible, false, "classic settings cog closes window")

local writes = area.posWrites + area.sizeWrites
map.suspended = true
map.watches[classicSurface](true)
tick()
expect(area.posWrites + area.sizeWrites, writes, "map occlusion pauses native writes")
expect(RibbonBar.isClassicSelected(disabled), true, "map occlusion retains selection")
expect(disabled.releases, 0, "map occlusion does not rebuild page")
map.suspended = false
map.watches[classicSurface](false)
tick()
expect(RibbonBar.isClassicSelected(disabled), true, "map close retains selected page")
top:SetSize(200, 220, 0, 0)
viewport:SetSize(200, 220, 0, 0)
tick()
rail(199, "narrow viewport clamps expanded sidebar")
expect(disabled.builds, 1, "resizing retains selected content")
expect(disabled.classicHost ~= nil, true, "resizing retains selected host")
expect(disabled.classicHost.width, 155, "narrow body keeps one native-area unit")
expect(disabled.classicHost.height, 220, "narrow body fills resized height")
top:SetSize(3440, 1440, 0, 0)
viewport:SetSize(3440, 1440, 0, 0)
tick()
rail(404, "full-width resize restores expanded sidebar")

-- A clipped icon list must keep every real button reachable by the wheel.
top:SetSize(3440, 180, 0, 0)
viewport:SetSize(3440, 180, 0, 0)
local overflow = {}
for index = 1, 12 do
    local entry = classicPanel("Overflow " .. index, true)
    overflow[index] = entry
    RibbonBar.register(entry)
end
tick()
local lastButton = buttonNamed("Overflow 12")
local scrollLayer = lastButton.parent
while scrollLayer and not scrollLayer.subscriptions[ui.Hook.ONSCROLLWHEEL] do
    scrollLayer = scrollLayer.parent
end
expect(scrollLayer ~= nil, true, "icon-list viewport binds mouse wheel")
expect(scrollLayer.x, 360, "icon-list viewport stays in rightmost 44-unit rail")
expect(scrollLayer.y, 40, "icon-list starts below fixed settings button")
expect(scrollLayer.height < 12 * 34, true, "icon-list viewport clips overflowing buttons")
expect(scrollLayer.scrollHeight > scrollLayer.height, true, "icon list exposes scrolling range")
for _ = 1, 20 do scrollLayer.subscriptions[ui.Hook.ONSCROLLWHEEL](scrollLayer, 1) end
expect(scrollLayer.scrollY > 0, true, "wheel reaches icons below the initial viewport")
expect(lastButton.enabled ~= false and lastButton.clickthrough ~= true, true,
    "scrolled final real button remains clickable")
local firstOverflow = buttonNamed("Overflow 1")
expect(firstOverflow.hidden, true, "off-viewport first icon is clipped from display")
expect(firstOverflow.enabled, false, "off-viewport first icon cannot intercept input")
clickRoot(firstOverflow)
expect(RibbonBar.isClassicSelected(disabled), true,
    "off-viewport button hook cannot replace the selected page")
expect(overflow[1].builds, 0, "off-viewport button does not construct content")
local tooltipOrigin = assert(tooltips.contextOrigins[scrollLayer])
local tipX, tipY = tooltipOrigin(lastButton)
expect(tipX, screenLeft(classicSurface) + scrollLayer.x + lastButton.x,
    "scrolled tooltip follows the icon-list horizontal origin")
expect(tipY, scrollLayer.y + lastButton.y - scrollLayer.scrollY,
    "scrolled tooltip subtracts the visible list offset")
clickRoot(lastButton)
expect(RibbonBar.isClassicSelected(overflow[12]), true, "last scrolled real button selects its page")
expect(disabled.releases, 1, "last selection releases prior content")
rail(404, "overflow selection retains expanded width")
for index = 1, 11 do RibbonBar.unregister(overflow[index]) end
tick()
expect(scrollLayer.scrollY <= math.max(0, (scrollLayer.scrollHeight or 0) - scrollLayer.height),
    true, "removing icons clamps scroll position")
expect(RibbonBar.isClassicSelected(overflow[12]), true, "removing other icons keeps selection")
top:SetSize(3440, 1440, 0, 0)
viewport:SetSize(3440, 1440, 0, 0)
tick()
expect(scrollLayer.scrollY, 0, "growing viewport resets obsolete icon scroll")
rail(404, "icon-list resize preserves reservation")
RibbonBar.unregister(overflow[12])
rail(44, "selected icon removal collapses")
expect(overflow[12].releases, 1, "selected removal releases host")
clickRoot(buttonNamed("Ribbon settings"))
expect(classicSettings.visible, true, "settings reopens on the same classic surface")
mode(0)
expect(classicSettings.destroyed, true, "mode exit destroys open classic settings")
expect(area.width, 3440, "mode exit restores native width")
expect(area.position.xParentPc, .5, "mode exit restores original parent anchor")
expect(area.position.xSelfPc, .5, "mode exit restores original self anchor")
expect(gameview.width, 3440, "mode exit restores gameview width")
expect(classicSurface.destroyed, true, "mode exit retires classic surface")
expect(RibbonBar.GetPosition(), "top", "modern mode restores saved ribbon position")
expect(a.root.hidden, false, "modern mode restores panel shell")
mode(1)
rail(44, "second mode entry starts collapsed")
expect(RibbonBar.isClassicSelected(a), false, "mode reentry never restores old selection")
RibbonBar.unregister(a)
RibbonBar.unregister(b)
RibbonBar.unregister(disabled)
expect(buttons(), nil, "last classic unregister removes rail")
expect(area.width, 3440, "last classic unregister restores native area")
expect(gameview.width, 3440, "last classic unregister restores gameview")
expect(tooltips.forTarget[aButton], nil, "unregister releases classic button tooltip")
expect(tooltips.forTarget[bButton], nil, "last unregister releases classic tooltip")

-- An optional gameview setter failure is not an excuse to hide a safely
-- reserved native rail. The mandatory target's foreign overwrite is.
area = gameArea(50, 3440, 1440)
gameview.failSize = true
local optional = classicPanel("Optional", true)
RibbonBar.register(optional)
rail(44, "gameview failure still shows collapsed rail")
expect(gameview.width, 3440, "optional gameview stays unchanged after setter failure")
clickRoot(buttonNamed("Optional"))
rail(404, "gameview failure still permits expansion")
expect(gameview.width, 3440, "optional target remains untouched during expansion")
RibbonBar.unregister(optional)
expect(area.width, 3440, "optional scene restores mandatory geometry")
area = gameArea(60, 3440, 1440)
local foreign = classicPanel("Foreign", true)
RibbonBar.register(foreign)
rail(44, "foreign overwrite setup")
area:SetSize(-24, 0, 1, 1)
tick()
expect(buttons(), nil, "foreign native overwrite withholds overlapping classic surface")
expect(RibbonBar.selectClassic(foreign, false), false, "mandatory unavailable rejects selection")
RibbonBar.unregister(foreign)
area = gameArea(70, 3440, 1440)
area.position.xParentPc = 0 -- Still a full-size child, but not centered at origin.
local incompatible = classicPanel("Incompatible", true)
RibbonBar.register(incompatible)
expect(buttons(), nil, "incompatible mandatory topology cannot show overlay-only rail")
expect(RibbonBar.selectClassic(incompatible, false), false,
    "incompatible mandatory topology cannot select a page")
expect(incompatible.builds, 0, "incompatible native layout never builds content")
area.position.xParentPc = .5
tick()
rail(44, "compatible topology becomes available")
local retiring = assert(buttons())
local contextsBeforeUnload = tooltips.unregistered
loaded[top.interfaceID] = nil
tick()
expect(buttons(), nil, "unloaded top layer retires rail without reusing stale handles")
expect(tooltips.unregistered > contextsBeforeUnload, true,
    "top-layer retirement releases every tooltip context")
expect(map.watches[retiring], nil, "top-layer retirement unhooks map")
expect(area.width, 3440, "top-layer retirement restores native reservation")
top = native(1070, 71, nil,
    { x = 0, y = 0, xParentPc = 0, yParentPc = 0, xSelfPc = 0, ySelfPc = 0 },
    { width = 3440, height = 1440, widthParentPc = 0, heightParentPc = 0 })
tick()
rail(44, "remounted top layer starts collapsed")
clickRoot(buttonNamed("Incompatible"))
rail(404, "remounted top layer expands")
local retiredExpanded = assert(buttons())
loaded[area.interfaceID] = nil
tick()
expect(buttons(), nil, "unloaded viewport retires expanded rail")
expect(map.watches[retiredExpanded], nil, "expanded retirement removes map observer")
expect(incompatible.releases, 1, "expanded retirement releases selected content")
area = gameArea(71, 3440, 1440)
local remounted = classicPanel("Remounted", true)
RibbonBar.register(remounted)
rail(44, "new viewport remount starts collapsed")
clickRoot(buttonNamed("Remounted"))
rail(404, "new viewport remount expands")
expect(remounted.builds, 1, "remount selects only the new live page")
RibbonBar.Shutdown()
expect(remounted.releases, 1, "shutdown releases selected classic host")
expect(area.width, 3440, "shutdown restores live native geometry")
expect(gameview.width, 3440, "shutdown restores live gameview geometry")
-- Repeated shutdown cannot reattach shells, write retired handles, or leak observers.
RibbonBar.Shutdown()
expect(varEvents.prettyui_ribbon_bar, nil, "shutdown unsubscribes base-variable listener")
expect(events.prettyui_ribbon_bar, nil, "shutdown unsubscribes logic listener")
expect(next(map.watches), nil, "shutdown cleans all map watchers")
expect(tooltips.contexts, tooltips.unregistered, "all classic and modern tooltip contexts retire")
print("ribbon_bar_test: ok")
