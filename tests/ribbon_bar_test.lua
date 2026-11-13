-- A small native/widget harness: the real RibbonButton owns the click hooks.
local function expect(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local loaded = { [10] = true }
local area
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
    function self:SetPos(x, y, xAnchor, yAnchor)
        self.x, self.y = x, y
        self.xAnchor, self.yAnchor = xAnchor, yAnchor
    end
    function self:SetSize(width, height)
        self.width, self.height = width, height
    end
    function self:Subscribe(hook, action)
        self.subscriptions[hook] = action
    end
    function self:MoveToFront() self.frontMoves = (self.frontMoves or 0) + 1 end
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
local function gameArea(interfaceID)
    local result = component(nil, "area")
    result.interfaceID = interfaceID
    result.width, result.height = 800, 600
    return result
end
area = gameArea(10)
ui = {
    Layer = {}, Sprite = {},
    Hook = { ONCLICK = 1, ONMOUSEOVER = 2, ONMOUSELEAVE = 3 },
    Interfaces = {
        GetComponent = function(_, packed)
            if packed == 1 and area and loaded[area.interfaceID] then return area end
        end,
        GetInterface = function(_, interfaceID)
            if loaded[interfaceID] then return true end
        end,
    },
}
ui.Layer.new = function(parent) return component(parent, "layer") end
ui.Sprite.new = function(parent) return component(parent, "sprite") end
id = { Component = { TOPLEVEL_V2__GAME_AREA = 1 },
    Sprite = setmetatable({}, { __index = function(_, key) return key end }) }
config = { Cursor = { CURSOR_OPEN = { id = 7 } } }
local events = {}
Event = { Logic = {
    Subscribe = function(key, callback) events[key] = callback end,
    Unsubscribe = function(key) events[key] = nil end,
} }
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
    if parent == area then
        expect(options.categoryID, "auto", "shared root uses safe automatic allocation")
        result.ribbonSurface = true
    end
    return result
end
local tooltips = { contexts = 0, unregistered = 0, unbound = 0, hidden = 0, forTarget = {} }
function tooltips.registerContext() tooltips.contexts = tooltips.contexts + 1 end
function tooltips.unregisterContext() tooltips.unregistered = tooltips.unregistered + 1 end
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
    expect(parent, area, "settings use current game area")
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
package.loaded["src/core/wheel"] = { bind = function() end }
package.loaded["src/core/mouse"] = { GetPosition = function() return nil end }
package.loaded["src/window"] = Window

local RibbonBar = require("src/ribbon_bar")
local function click(button)
    return assert(button.root.subscriptions[ui.Hook.ONCLICK], "real RibbonButton hook missing")(button.root)
end
local function buttons()
    if area == nil then return nil, {} end
    local surface
    for _, child in ipairs(area.children) do
        if child.ribbonSurface then surface = child; break end
    end
    local result = {}
    if surface then
        for _, child in ipairs(surface.children) do
            if child.kind == "layer" then result[#result + 1] = child end
        end
    end
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
print("ribbon_bar_test: ok")
