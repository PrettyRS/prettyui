-- A small native/widget harness: the real RibbonButton owns the click hooks.
local function expect(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local loaded = {}
local area, top, viewport, gameview, gamecontent, render, inventory, chat, action
local staticComponents = {}
local classicMode = 0
local nextDynamic = 0
local function component(parent, kind)
    nextDynamic = nextDynamic + 1
    local result = {
        kind = kind,
        parent = parent,
        children = {},
        subscriptions = {},
        interfaceID = parent and parent.interfaceID or 10,
        staticID = parent and parent.staticID or 61,
        categoryID = 1,
        dynamicID = nextDynamic,
        width = 0,
        height = 0,
        x = 0,
        y = 0,
        cursorConfig = {},
        opConfig = { SetOpCursor = function() end, ClearOpCursors = function() end },
    }
    function result:SetPos(x, y, xAnchor, yAnchor, xSelf, ySelf)
        self.posWrites = (self.posWrites or 0) + 1
        self.x, self.y = x, y
        self.xAnchor, self.yAnchor = xAnchor, yAnchor
        self.xSelf, self.ySelf = xSelf, ySelf
    end
    function result:SetSize(width, height, widthParentPc, heightParentPc)
        self.sizeWrites = (self.sizeWrites or 0) + 1
        self.width, self.height = width, height
        self.widthParentPc, self.heightParentPc = widthParentPc, heightParentPc
    end
    function result:SetScrollSize(width, height, widthParentPc, heightParentPc)
        self.scrollWidth, self.scrollHeight = width, height
        self.scrollWidthParentPc, self.scrollHeightParentPc = widthParentPc, heightParentPc
    end
    function result:SetScrollPos(x, y)
        self.scrollX, self.scrollY = x, y
    end
    function result:Subscribe(hook, keyOrAction, callback)
        self.subscriptions[hook] = callback or keyOrAction
    end
    function result:MoveToFront() self.frontMoves = (self.frontMoves or 0) + 1 end
    function result:MoveToBack()
        if parent then
            for index, child in ipairs(parent.children) do
                if child == self then
                    table.remove(parent.children, index)
                    break
                end
            end
            table.insert(parent.children, 1, self)
        end
    end
    function result:Destroy()
        while #self.children > 0 do
            self.children[#self.children]:Destroy()
        end
        self.destroyed = true
        if parent then
            for index, child in ipairs(parent.children) do
                if child == self then
                    table.remove(parent.children, index)
                    break
                end
            end
        end
    end
    if parent then parent.children[#parent.children + 1] = result end
    return result
end
local function native(interfaceID, staticID, parent, position, dimensions)
    local result = component(parent, "native")
    result.interfaceID, result.staticID, result.categoryID, result.dynamicID = interfaceID, staticID, -1, -1
    result.x, result.y, result.width, result.height = nil, nil, nil, nil
    result.position, result.size = position, dimensions
    result.posWrites, result.sizeWrites = 0, 0
    setmetatable(result, {
        __index = function(self, field)
            if field == "width" then
                return self.size.width + (parent and parent.width or 0) * self.size.widthParentPc
            elseif field == "height" then
                return self.size.height + (parent and parent.height or 0) * self.size.heightParentPc
            elseif field == "x" then
                return self.position.x
                    + (parent and parent.width or 0) * self.position.xParentPc
                    - self.width * self.position.xSelfPc
            elseif field == "y" then
                return self.position.y
                    + (parent and parent.height or 0) * self.position.yParentPc
                    - self.height * self.position.ySelfPc
            end
        end,
    })
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
    top = native(
        interfaceID + 1000,
        71,
        nil,
        { x = 0, y = 0, xParentPc = 0, yParentPc = 0, xSelfPc = 0, ySelfPc = 0 },
        { width = width, height = height, widthParentPc = 0, heightParentPc = 0 }
    )
    viewport = native(
        interfaceID,
        75,
        nil,
        { x = 0, y = 0, xParentPc = 0, yParentPc = 0, xSelfPc = 0, ySelfPc = 0 },
        { width = width, height = height, widthParentPc = 0, heightParentPc = 0 }
    )
    local result = native(
        interfaceID,
        81,
        viewport,
        { x = 0, y = 0, xParentPc = 0.5, yParentPc = 0.5, xSelfPc = 0.5, ySelfPc = 0.5 },
        { width = 0, height = 0, widthParentPc = 1, heightParentPc = 1 }
    )
    gameview = native(
        interfaceID,
        87,
        viewport,
        { x = 0, y = 0, xParentPc = 0, yParentPc = 0, xSelfPc = 0, ySelfPc = 0 },
        { width = 0, height = 0, widthParentPc = 1, heightParentPc = 1 }
    )
    gamecontent = native(
        interfaceID,
        88,
        gameview,
        { x = 0, y = 0, xParentPc = 0, yParentPc = 0, xSelfPc = 0, ySelfPc = 0 },
        { width = 0, height = 0, widthParentPc = 1, heightParentPc = 1 }
    )
    render = native(
        interfaceID,
        89,
        gamecontent,
        { x = 0, y = 0, xParentPc = 0, yParentPc = 0, xSelfPc = 0, ySelfPc = 0 },
        { width = 0, height = 0, widthParentPc = 1, heightParentPc = 1 }
    )
    gameview.visibleGlobal, gamecontent.visibleGlobal, render.visibleGlobal = true, true, true
    inventory = native(
        interfaceID,
        91,
        result,
        { x = 0, y = 0, xParentPc = 1, yParentPc = 1, xSelfPc = 1, ySelfPc = 1 },
        { width = 212, height = 312, widthParentPc = 0, heightParentPc = 0 }
    )
    chat = native(
        interfaceID,
        92,
        result,
        { x = 0, y = 0, xParentPc = 0, yParentPc = 1, xSelfPc = 0, ySelfPc = 1 },
        { width = 550, height = 188, widthParentPc = 0, heightParentPc = 0 }
    )
    action = native(
        interfaceID,
        93,
        result,
        { x = 0, y = 0, xParentPc = 0.5, yParentPc = 1, xSelfPc = 0.5, ySelfPc = 1 },
        { width = 550, height = 150, widthParentPc = 0, heightParentPc = 0 }
    )
    inventory.visibleGlobal, chat.visibleGlobal, action.visibleGlobal = true, false, false
    if id then
        id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP = ((interfaceID + 1000) << 16) | 71
        id.Component.TOPLEVEL_V2__VIEWPORT = (interfaceID << 16) | 75
        id.Component.TOPLEVEL_V2__GAME_AREA = (interfaceID << 16) | 81
        id.Component.TOPLEVEL_V2__GAMEVIEW_WINDOW = (interfaceID << 16) | 87
        id.Component.TOPLEVEL_V2__GAMEVIEW_WINDOW_CONTENT = (interfaceID << 16) | 88
        id.Component.TOPLEVEL_V2__RENDER_LAYER = (interfaceID << 16) | 89
        id.Component.TOPLEVEL_V2__INVENTORY_WINDOW = (interfaceID << 16) | 91
        id.Component.TOPLEVEL_V2__CHAT_WINDOW = (interfaceID << 16) | 92
        id.Component.TOPLEVEL_V2__ACTION_WINDOW = (interfaceID << 16) | 93
    end
    return result
end
ui = {
    Layer = {},
    Sprite = {},
    Hook = { ONCLICK = 1, ONMOUSEOVER = 2, ONMOUSELEAVE = 3, ONSCROLLWHEEL = 4, ONRELEASE = 5, ONRESIZE = 6 },
    Interfaces = {
        GetComponent = function(_, a, b, c, d)
            if d ~= nil then
                if not loaded[a] then return nil end
                local function search(node)
                    if
                        node.interfaceID == a
                        and node.staticID == b
                        and node.categoryID == c
                        and node.dynamicID == d
                    then
                        return node
                    end
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
Plugin = { resources = {
    encounter = { runtimeSprite = {} },
    alternate = { runtimeSprite = {} },
} }
ui.Sprite.new = function(parent)
    local result = component(parent, "sprite")
    return setmetatable(result, {
        __index = function(self, key)
            if key == "sprite" then return rawget(self, "_sprite") end
            if key == "spriteID" then return rawget(self, "_spriteID") end
        end,
        __newindex = function(self, key, value)
            if key == "spriteID" then
                assert(type(value) == "number", "spriteID accepts built-in numeric IDs only")
                rawset(self, "_spriteID", value)
                rawset(self, "_sprite", value)
            elseif key == "sprite" then
                assert(
                    type(value) == "number" or (type(value) == "table" and value.runtimeSprite),
                    "sprite accepts numeric IDs or loaded image resources"
                )
                rawset(self, "_spriteID", type(value) == "number" and value or nil)
                rawset(self, "_sprite", type(value) == "number" and value or value.runtimeSprite)
                rawset(self, "spriteWrites", (self.spriteWrites or 0) + 1)
            else
                rawset(self, key, value)
            end
        end,
    })
end
local nextSpriteID = 1000
id = {
    Font = { CINZEL_18PT_BOLD = 1 },
    Component = {
        TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP = (1010 << 16) | 71,
        TOPLEVEL_V2__VIEWPORT = (10 << 16) | 75,
        TOPLEVEL_V2__GAME_AREA = (10 << 16) | 81,
        TOPLEVEL_V2__GAMEVIEW_WINDOW = (10 << 16) | 87,
    },
    VarPlayer = {
        TOPLEVEL_V2_GENERAL_VARP = 101,
        TOPLEVEL_V2_CUSTOMIZATION_LOCK = 102,
        TOPLEVEL_V2_SKINS_VARP = 103,
        TOPLEVEL_V2_TRANSPARENCY = 104,
    },
    Sprite = setmetatable({}, {
        __index = function(self, key)
            local spriteID = nextSpriteID
            nextSpriteID = nextSpriteID + 1
            rawset(self, key, spriteID)
            return spriteID
        end,
    }),
}
var = {
    VarPlayer = {
        TOPLEVEL_V2_LEGACY_INTERFACE = setmetatable({}, {
            __index = function(_, key)
                if key == "value" then return classicMode end
            end,
        }),
        TOPLEVEL_V2_CUSTOMIZATION_LOCK = { value = 0 },
        TOPLEVEL_V2_TRANSPARENCY = { value = 0 },
    },
}
config = { Cursor = { CURSOR_OPEN = { id = 7 } } }
local events, varEvents = {}, {}
local settingsEvents = {}
Event = {
    Logic = {
        Subscribe = function(key, callback) events[key] = callback end,
        Unsubscribe = function(key) events[key] = nil end,
    },
    VarTransmit = {
        Subscribe = function(key, callback) varEvents[key] = callback end,
        Unsubscribe = function(key) varEvents[key] = nil end,
    },
    SettingsLayerReady = {
        Subscribe = function(key, callback) settingsEvents[key] = callback end,
        Unsubscribe = function(key) settingsEvents[key] = nil end,
    },
}
local db = { ribbonBarPosition = "right", ribbonBarAutoHide = false }
PersistentDB = {
    GetString = function(_, key) return db[key] end,
    GetBool = function(_, key) return db[key] end,
    GetInt = function(_, key) return db[key] end,
    SetInt = function(_, key, value) db[key] = value end,
    SetString = function(_, key, value) db[key] = value end,
    SetBool = function(_, key, value) db[key] = value end,
}
local components = { roots = {} }
function components.sameComponent(first, second)
    return first == second
        or first ~= nil
            and second ~= nil
            and first.interfaceID == second.interfaceID
            and first.staticID == second.staticID
            and first.categoryID == second.categoryID
            and first.dynamicID == second.dynamicID
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
local tooltips = {
    contexts = 0,
    unregistered = 0,
    unbound = 0,
    hidden = 0,
    forTarget = {},
    contextOrigins = {},
    contextParents = {},
}
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
local windows, views = {}, {}
local function contentHost(hostOptions)
    local instance = { options = hostOptions, content = {}, controls = {} }
    function instance:AddTitle(text) self.content[#self.content + 1] = text end
    function instance:AddText(text)
        local result = { content = text }
        self.content[#self.content + 1] = result
        return result
    end
    function instance.AddSlider(host, sliderOptions)
        local result = { options = sliderOptions, value = sliderOptions.value }
        function result:SetValue(value)
            assert(not instance.destroyed, "updating a destroyed settings host")
            self.value = value
        end
        host.controls.cap = result
        return result
    end
    function instance.AddComboBox(host, comboOptions)
        local result = { options = comboOptions, selected = comboOptions.selectedID }
        function result:Select(value)
            assert(not instance.destroyed, "updating a destroyed settings host")
            self.selected = value
        end
        host.controls.position = result
        return result
    end
    function instance.AddCheckboxButton(host, values, checkboxOptions)
        local result = { options = checkboxOptions, selected = {} }
        function result:IsSelected(value)
            return self.selected[value] == true
        end
        function result:SetSelected(key, value)
            assert(not instance.destroyed, "updating a destroyed settings host")
            self.selected[key] = value
        end
        for _, choice in ipairs(values) do
            result.selected[choice.value] = choice.selected
            host.controls[choice.value] = result
        end
        return result
    end
    function instance:Show() self.visible = true end
    function instance:Close()
        self.options.onClose()
        self.visible = false
    end
    function instance:SetSize(width, height)
        self.width, self.height = width, height
    end
    function instance:Destroy()
        self.destroyed = true
        if self.root then self.root:Destroy() end
    end
    function instance:Refresh() self.refreshes = (self.refreshes or 0) + 1 end
    function instance.RefreshRowBackgrounds() end
    return instance
end
local Window = {}
function Window.new(parent, options)
    expect(classicMode, 0, "Classic settings never open a floating window")
    expect(parent, area, "Modern settings use the game area")
    expect(options.categoryID, "auto", "settings use automatic allocation")
    local instance = contentHost(options)
    instance.interfaceID = parent.interfaceID
    windows[#windows + 1] = instance
    return instance
end
package.loaded["src/simple_view"] = {
    new = function(parent, options)
        local instance = contentHost(options)
        instance.parent = parent
        instance.interfaceID = parent.interfaceID
        instance.root = component(parent, "settings view")
        instance:SetSize(options.width, options.height)
        views[#views + 1] = instance
        return instance
    end,
}
package.loaded["src/core/components"] = components
package.loaded["src/tooltip"] = tooltips
package.loaded["src/core/world_map"] = map
package.loaded["src/core/wheel"] = require("src/core/wheel")
package.loaded["src/core/mouse"] = { GetPosition = function() return nil end }
package.loaded["src/window"] = Window

package.loaded["src/nis/group"] = { resume = function() end }
package.loaded["src/nis/persistence"] = { setActive = function() return false end }
package.loaded["src/nis/native"] = {
    remember = function() return nil end,
    register = function() end,
}
local RibbonBar = require("src/ribbon_bar")
local function click(button)
    return assert(button.root.subscriptions[ui.Hook.ONCLICK], "real RibbonButton hook missing")(button.root)
end
local function ribbonSurfaceIn(parent)
    for _, child in ipairs(parent.children) do
        if child.ribbonSurface and not child.destroyed then return child end
    end
end

local function findRibbonSurface()
    for _, parent in ipairs({ area, top }) do
        if parent and loaded[parent.interfaceID] then
            local surface = ribbonSurfaceIn(parent)
            if surface then return surface end
        end
    end
end

local function buttons()
    local surface = findRibbonSurface()
    local result = {}
    local function collect(node)
        if node.subscriptions[ui.Hook.ONCLICK] and tooltips.forTarget[node] then
            if tooltips.forTarget[node] == "PrettyUI settings" then
                table.insert(result, 1, node)
            else
                result[#result + 1] = node
            end
        end
        for _, child in ipairs(node.children) do
            collect(child)
        end
    end
    if surface then collect(surface) end
    return surface, result
end
local function panel(icon, text, active)
    local result = {
        parent = area,
        root = component(area, "panel shell"),
        interfaceID = area.interfaceID,
        tabIcon = icon,
        tabText = text,
        active = active,
        calls = 0,
    }
    function result:IsActive() return self.active end
    function result:SetActive(value)
        self.active = value
        self.calls = self.calls + 1
    end
    return result
end
local function start(interfaceID, modeValue)
    classicMode = modeValue or 0
    map.suspended = false
    area = gameArea(interfaceID, 3440, 1440)
    RibbonBar.Start()
end

local function tick()
    assert(events.prettyui_ribbon_bar, "logic listener missing")()
end

local Settings = require("src/settings")

local function modernRegistrationAndSettings()
    db.ribbonBarPosition, db.ribbonBarAutoHide = "right", false
    start(10)
    expect(Settings.get("ribbonBarPosition"), "right", "stored position")
    tick()
    expect(buttons(), nil, "no surface without registrations")

    local first = panel(Plugin.resources.encounter, "First", true)
    local second = panel(9001, nil, true)
    RibbonBar.register(first)
    RibbonBar.register(second)
    local surface, roots = buttons()
    expect(#roots, 3, "settings and both panels appear in registration order")
    expect(roots[2].children[2].sprite, Plugin.resources.encounter.runtimeSprite, "resource icon")
    expect(roots[3].children[2].spriteID, 9001, "numeric icon")
    expect(tooltips.forTarget[roots[3]], "Panel", "unnamed panel tooltip")

    click({ root = roots[3] })
    expect(second:IsActive(), false, "click disables panel")
    expect(second.root ~= nil, true, "panel shell survives deactivation")
    local _, inactiveRoots = buttons()
    expect(#inactiveRoots, 3, "disabled panel retains its button")
    click({ root = roots[3] })
    expect(second:IsActive(), true, "another click reactivates panel")

    second.tabIcon, second.tabText = Plugin.resources.alternate, "Updated"
    RibbonBar.sync(second)
    expect(roots[3].children[2].sprite, Plugin.resources.alternate.runtimeSprite, "synced resource icon")
    expect(tooltips.forTarget[roots[3]], "Updated", "synced tooltip")
    second.tabIcon = 9002
    RibbonBar.sync(second)
    expect(roots[3].children[2].spriteID, 9002, "synced built-in icon")

    click({ root = roots[1] })
    local settings = windows[#windows]
    expect(
        settings.controls.position ~= nil and settings.controls.autoHide ~= nil,
        true,
        "modern settings show position and auto-hide"
    )
    click({ root = roots[1] })
    expect(settings.visible, false, "settings cog closes window")
    Settings.set("ribbonBarPosition", "top")
    Settings.set("ribbonBarAutoHide", true)
    expect(db.ribbonBarPosition, "top", "position persisted")
    expect(db.ribbonBarAutoHide, true, "auto-hide persisted")
    expect(
        roots[2].parent.x + roots[2].x - roots[1].x - roots[1].width,
        2,
        "top ribbon keeps a normal button gap after the compact cog"
    )
    tick()
    expect(surface.y, -8, "auto-hide slides by one step")
    for _ = 1, 10 do
        tick()
    end
    expect(surface.y, -44, "auto-hide reaches hidden edge")
    Settings.set("ribbonBarAutoHide", false)
    for _ = 1, 10 do
        tick()
    end
    expect(surface.y, 0, "disabling auto-hide returns bar into view")
    map.suspended = true
    map.watches[surface](true)
    expect(second:IsActive(), true, "world map occlusion does not disable panels")
    map.suspended = false

    RibbonBar.unregister(first)
    expect(roots[2].destroyed, true, "unregistration destroys only its button")
    expect(buttons(), surface, "other registration keeps the ribbon")
    RibbonBar.unregister(second)
    expect(surface.destroyed, true, "last registration retires surface")
    expect(settings.destroyed, true, "settings destroyed with surface")
    expect(map.watches[surface], nil, "map observer removed")
    expect(tooltips.forTarget[roots[3]], nil, "button tooltip unbound")
    RibbonBar.Shutdown()
    expect(events.prettyui_ribbon_bar, nil, "shutdown unsubscribes logic")
end

local function modernRemountDiscardsStalePanels()
    start(20)
    local old = panel(9003, "Old", true)
    RibbonBar.register(old)
    local oldSurface = assert(buttons())
    loaded[area.interfaceID] = nil
    area = nil
    tick()
    expect(map.watches[oldSurface], nil, "unloaded interface removes map observer")
    area = gameArea(21, 3440, 1440)
    tick()
    expect(buttons(), nil, "new interface does not resurrect old registration")

    local fresh = panel(Plugin.resources.encounter, "Fresh", true)
    RibbonBar.register(fresh)
    local surface, roots = buttons()
    expect(surface ~= oldSurface, true, "new interface mounts a new surface")
    expect(#roots, 2, "only fresh registration remounts")
    RibbonBar.unregister(fresh)
    local destroyed = panel(9004, "Destroyed", true)
    RibbonBar.register(destroyed)
    destroyed._destroyed = true
    tick()
    expect(buttons(), nil, "logic prunes destroyed panels without unregister")
    RibbonBar.Shutdown()
    expect(next(map.watches), nil, "remount shutdown leaves no map observer")
end

modernRegistrationAndSettings()
modernRemountDiscardsStalePanels()

-- Classic sidebar tests use panel doubles for the content-host contract and
-- actual RibbonButton hooks, rail geometry and native layout reservation.
local function mode(value)
    classicMode = value
    assert(varEvents.prettyui_ribbon_bar, "base-variable listener missing")({
        var = { id = id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP },
    })
end
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
    return (surface.xAnchor or 0) * top.width + surface.x - (surface.xSelf or 0) * surface.width
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
local function croppedGameview(reserved, description)
    local visibleWidth = viewport.width - reserved
    expect(gameview.width, visibleWidth, description .. " native window clips at sidebar")
    expect(gameview.size.widthParentPc, 0, description .. " clipped window uses absolute width")
    expect(gameview.height, viewport.height, description .. " native window keeps height")
    expect(gamecontent.parent, gameview, description .. " content belongs to gameview")
    expect(gamecontent.width, visibleWidth, description .. " content fills clipped window")
    expect(gamecontent.height, viewport.height, description .. " content fills window height")
    expect(render.parent, gamecontent, description .. " render belongs to content")
    expect(render.visibleGlobal, true, description .. " render remains visible")
    expect(render.width, viewport.width, description .. " render keeps full native viewport width")
    expect(render.height, viewport.height, description .. " render keeps native height")
    expect(render.size.widthParentPc, 0, description .. " render uses absolute width")
    expect(render.x, -math.floor(reserved / 2), description .. " native viewport remains centered")
end
local lifecycle = {}
local nextPanelIcon = 10000
local function classicPanel(name, enabled)
    nextPanelIcon = nextPanelIcon + 1
    local result = panel(nextPanelIcon, name, enabled)
    result.builds, result.releases = 0, 0
    result._contentReady = true
    function result:_SetClassicMode(value)
        self._nisClassic = value
        if value then
            self._contentReady = false
        else
            self:_SetClassicHost(nil)
            self._nisClassicState = nil
        end
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
            if value then
                RibbonBar.selectClassic(self, false)
            elseif RibbonBar.isClassicSelected(self) then
                RibbonBar.selectClassic(self, true)
            end
        end
        RibbonBar.sync(self)
    end
    function result._LayoutBody() end
    function result._SyncChrome() end
    function result._SyncOverlays() end
    function result._SyncContent() end
    function result.RefreshRowBackgrounds() end
    return result
end

local function classicSelectionAndModeTransitions()
    db.ribbonBarPosition, db.ribbonBarAutoHide = "top", true
    lifecycle = {}
    start(40)
    local a, b, disabled = classicPanel("A", true), classicPanel("B", true), classicPanel("Disabled", false)
    a.tabIcon = Plugin.resources.encounter
    RibbonBar.register(a)
    RibbonBar.register(b)
    RibbonBar.register(disabled)
    local modern = assert(buttons())
    classicMode = 1
    varEvents.prettyui_ribbon_bar({ var = { id = id.VarPlayer.TOPLEVEL_V2_SKINS_VARP } })
    expect(buttons(), modern, "unrelated variable does not switch mode")
    classicMode = 0
    gameview:SetSize(3400, 0, 0, 1)
    mode(1)
    expect(modern.destroyed, true, "entering Classic retires modern surface")
    local surface = rail(44, "collapsed Classic rail")
    expect(a.root.hidden, true, "modern panel shell hidden")
    expect(a.builds + b.builds, 0, "Classic content is lazy")
    expect(gameview.width, 3400, "Classic HUD reserves space before native gameview settles")
    for _ = 1, 9 do
        mode(1) -- extra var notifications must not consume logic ticks
        tick()
    end
    expect(gameview.width, 3400, "nine logic ticks leave outgoing gameview untouched")
    expect(render.size.widthParentPc, 1, "render remains native while the mode switch settles")
    gameview:SetSize(0, 0, 1, 1) -- late native Classic layout
    tick()
    croppedGameview(44, "collapsed rail")
    expect(
        buttonNamed("A").children[2].sprite,
        Plugin.resources.encounter.runtimeSprite,
        "Classic button renders resource icon"
    )

    clickRoot(buttonNamed("A"))
    rail(344, "selected content")
    croppedGameview(344, "expanded rail")
    expect(a.classicHost.parent, surface, "selected content belongs to full-screen rail")
    expect(a.classicHost.width, 300, "selected content width")
    expect(a.builds, 1, "selected content builds on first click")
    expect(b.builds, 0, "unselected content remains unbuilt")
    local aButton = buttonNamed("A")
    a.tabIcon = Plugin.resources.alternate
    RibbonBar.sync(a)
    expect(aButton.children[2].sprite, Plugin.resources.alternate.runtimeSprite, "selected button syncs resource icon")
    clickRoot(buttonNamed("B"))
    expect(lifecycle[2], "A:release", "old content releases before replacement")
    expect(lifecycle[3], "B:build", "new content builds after release")
    expect(a:IsActive() and b:IsActive(), true, "selection does not disable panels")
    clickRoot(buttonNamed("B"))
    rail(44, "collapsed selection")
    croppedGameview(44, "collapsed selection")
    expect(b.releases, 1, "collapse releases content")
    expect(b:IsActive(), true, "collapse keeps panel enabled")
    expect(RibbonBar.selectClassic(a, false), true, "API selects enabled panel")
    rail(344, "programmatic selection")
    croppedGameview(344, "programmatic selection")
    expect(RibbonBar.selectClassic(a, true), true, "API toggles selected panel closed")
    top:SetSize(45, 120, 0, 0)
    viewport:SetSize(45, 120, 0, 0)
    tick()
    rail(44, "one-unit game area")
    expect(RibbonBar.selectClassic(a, false), false, "no space for body prevents selection")
    top:SetSize(3440, 1440, 0, 0)
    viewport:SetSize(3440, 1440, 0, 0)
    tick()
    croppedGameview(44, "programmatic collapse")
    rail(44, "programmatic collapse")
    clickRoot(buttonNamed("Disabled"))
    expect(RibbonBar.isClassicSelected(disabled), true, "first click enables and selects disabled panel")
    expect(disabled.builds, 1, "disabled panel builds once")
    expect(RibbonBar.selectClassic({ root = area }, false), false, "unregistered panel cannot select")

    clickRoot(buttonNamed("PrettyUI settings"))
    local settings = views[#views]
    expect(settings.parent.parent, surface, "Classic settings mount inside the sidebar body")
    expect(RibbonBar.isClassicSelected(disabled), false, "settings replace the selected page")
    expect(
        settings.controls.position ~= nil and settings.controls.autoHide ~= nil,
        true,
        "Classic settings can edit all Modern ribbon preferences"
    )
    expect(Settings.get("ribbonBarPosition"), "top", "Classic mode preserves modern position")
    expect(Settings.get("ribbonBarAutoHide"), true, "Classic mode preserves modern auto-hide")
    clickRoot(buttonNamed("PrettyUI settings"))
    expect(settings.destroyed, true, "settings cog closes and destroys sidebar settings")
    rail(44, "closing settings collapses sidebar")
    clickRoot(buttonNamed("Disabled"))
    expect(disabled.builds, 2, "leaving settings permits rebuilding panel content")
    clickRoot(buttonNamed("PrettyUI settings"))
    settings = views[#views]
    map.suspended = true
    map.watches[surface](true)
    tick()
    expect(settings.destroyed, nil, "map overlay retains settings page")
    map.suspended = false
    map.watches[surface](false)
    top:SetSize(200, 220, 0, 0)
    viewport:SetSize(200, 220, 0, 0)
    tick()
    rail(44, "insufficient space collapses settings")
    expect(settings.destroyed, true, "settings never shrink below inventory width")
    top:SetSize(3440, 1440, 0, 0)
    viewport:SetSize(3440, 1440, 0, 0)
    tick()
    rail(44, "growing viewport leaves sidebar collapsed")
    clickRoot(buttonNamed("PrettyUI settings"))
    settings = views[#views]
    rail(344, "settings reopen at full width")

    mode(0)
    expect(settings.destroyed, true, "mode exit destroys Classic settings")
    expect(area.width, 3440, "mode exit restores native game area")
    expect(gameview.width, 3440, "mode exit restores full native gameview")
    expect(render.position.x, 0, "mode exit restores render origin")
    expect(render.size.widthParentPc, 1, "mode exit restores render width descriptor")
    expect(surface.destroyed, true, "mode exit destroys Classic surface")
    expect(a.root.hidden, false, "modern panel shell restored")
    expect(
        buttonNamed("A").children[2].sprite,
        Plugin.resources.alternate.runtimeSprite,
        "modern button retains updated icon"
    )
    mode(1)
    rail(44, "mode reentry starts collapsed")
    for _ = 1, 10 do
        tick()
    end
    croppedGameview(44, "mode reentry")
    expect(RibbonBar.isClassicSelected(a), false, "old selection does not return")
    RibbonBar.Shutdown()
    expect(area.width, 3440, "shutdown restores native geometry")
    expect(gameview.width, 3440, "shutdown restores native gameview")
    expect(render.position.x, 0, "shutdown restores render origin")
    expect(next(map.watches), nil, "shutdown removes map observers")
end

local function classicFixedWidthGameview()
    start(46, 1)
    gameview:SetSize(3000, 0, 0, 1)
    local owner = classicPanel("Fixed width", true)
    RibbonBar.register(owner)
    rail(44, "fixed-width collapsed rail")
    expect(gameview.width, 3000, "already-fitting native window remains untouched")
    clickRoot(buttonNamed("Fixed width"))
    rail(344, "fixed-width expanded sidebar")
    expect(gameview.width, 3000, "native gameview fitting beside expanded sidebar remains untouched")
    expect(render.size.widthParentPc, 1, "already-fitting render retains native fill width")
    expect(render.position.x, 0, "already-fitting render retains native origin")
    clickRoot(buttonNamed("Fixed width"))
    gameview:SetSize(3300, 0, 0, 1)
    tick()
    rail(44, "overlapping fixed-width rail")
    expect(gameview.width, 3300, "fixed-width gameview fits beside collapsed rail")
    clickRoot(buttonNamed("Fixed width"))
    rail(344, "overlapping fixed-width sidebar")
    croppedGameview(344, "overlapping fixed-width sidebar")
    clickRoot(buttonNamed("Fixed width"))
    rail(44, "fixed-width collapse")
    expect(gameview.width, 3300, "collapse restores exact native fixed width")
    expect(gameview.size.width, 3300, "collapse restores fixed-width descriptor")
    expect(gameview.size.widthParentPc, 0, "collapse restores fixed-width anchor")
    expect(render.position.x, 0, "collapse restores native render origin")
    expect(render.size.widthParentPc, 1, "collapse restores native render sizing")
    RibbonBar.Shutdown()
end
local function classicWidthProtectsChatAndInventory()
    start(45, 1)
    local owner = classicPanel("Responsive", true)
    RibbonBar.register(owner)
    chat.visibleGlobal, action.visibleGlobal = true, true
    top:SetSize(1920, 1080, 0, 0)
    viewport:SetSize(1920, 1080, 0, 0)
    tick()
    clickRoot(buttonNamed("Responsive"))
    rail(344, "1080p sidebar retains preferred width")
    local host = owner.classicHost
    expect(host.width, 300, "compact combat placement preserves sidebar space")
    assert(host.width >= inventory.width, "sidebar must be at least inventory width")
    expect(action.x, chat.x, "compact bars align with chat")
    expect(chat.y - (action.y + action.height), 0, "compact bars join the chat frame")

    top:SetSize(2560, 1440, 0, 0)
    viewport:SetSize(2560, 1440, 0, 0)
    tick()
    rail(344, "larger display restores preferred width")
    expect(owner.classicHost, host, "resize retains mounted content")
    expect(owner.builds, 1, "resize does not rebuild content")

    top:SetSize(1920, 1080, 0, 0)
    viewport:SetSize(1920, 1080, 0, 0)
    tick()
    inventory:SetSize(380, 312, 0, 0)
    tick()
    rail(424, "sidebar grows to fit a wider inventory")
    expect(owner.classicHost.width, 380, "inventory floor uses live native width")
    expect(chat.y - (action.y + action.height), 0, "resized bars remain flush with chat")
    expect(owner.releases, 0, "inventory changes retain content")
    clickRoot(buttonNamed("Responsive"))
    rail(44, "collapse releases sidebar space")
    expect(action.position.xParentPc, 0.5, "collapse restores centred native anchor")
    expect(action.position.x, 0, "collapse removes compact offset")
    expect(action.y + action.height, viewport.height, "collapse restores bottom-aligned bars")
    RibbonBar.Shutdown()
end

local function classicOverflowKeepsButtonsReachable()
    start(50, 1)
    local selected = classicPanel("Selected", true)
    RibbonBar.register(selected)
    clickRoot(buttonNamed("Selected"))
    local surface = rail(344, "selected page before overflow")
    top:SetSize(3440, 180, 0, 0)
    viewport:SetSize(3440, 180, 0, 0)
    local overflow = {}
    for index = 1, 12 do
        overflow[index] = classicPanel("Overflow " .. index, true)
        RibbonBar.register(overflow[index])
    end
    tick()
    local last = buttonNamed("Overflow 12")
    local scroll = last.parent
    while scroll and not scroll.subscriptions[ui.Hook.ONSCROLLWHEEL] do
        scroll = scroll.parent
    end
    assert(scroll, "Classic icon list must bind the mouse wheel")
    expect(scroll.height < scroll.scrollHeight, true, "icons overflow clipped viewport")
    for _ = 1, 20 do
        scroll.subscriptions[ui.Hook.ONSCROLLWHEEL](scroll, 1)
    end
    expect(scroll.scrollY > 0, true, "wheel reveals hidden buttons")
    local first = buttonNamed("Overflow 1")
    expect(first.enabled, false, "clipped button cannot intercept clicks")
    clickRoot(first)
    expect(RibbonBar.isClassicSelected(selected), true, "clipped button cannot replace selection")
    local tooltipX, tooltipY = tooltips.contextOrigins[scroll](last)
    expect(tooltipX, screenLeft(surface) + scroll.x + last.x, "scrolled tooltip x")
    expect(tooltipY, scroll.y + last.y - scroll.scrollY, "scrolled tooltip y")
    clickRoot(last)
    expect(RibbonBar.isClassicSelected(overflow[12]), true, "last scrolled button selects page")
    for index = 1, 11 do
        RibbonBar.unregister(overflow[index])
    end
    tick()
    expect(
        scroll.scrollY <= math.max(0, scroll.scrollHeight - scroll.height),
        true,
        "removing icons clamps scroll offset"
    )
    top:SetSize(3440, 1440, 0, 0)
    viewport:SetSize(3440, 1440, 0, 0)
    tick()
    expect(scroll.scrollY, 0, "growing viewport resets icon scroll")
    RibbonBar.unregister(overflow[12])
    rail(44, "removing selected page collapses sidebar")
    expect(overflow[12].releases, 1, "selected page releases content on unregister")
    RibbonBar.Shutdown()
end

local function modernOverflowAndCap()
    db.ribbonBarButtonCap, db.ribbonBarAutoHide = 3, false
    start(55)
    local panels = {}
    for index = 1, 23 do
        panels[index] = classicPanel("Modern " .. index, false)
        RibbonBar.register(panels[index])
    end
    expect(Settings.get("ribbonBarButtonCap"), 3, "saved button cap restored")
    local surface = assert(buttons())
    local cog = buttonNamed("PrettyUI settings")
    expect(cog.spriteID, id.Sprite.RS3_ICON_SETTINGS_30PX_2, "cog uses the settings sprite")
    local previous, nextArrow
    for _, child in ipairs(surface.children) do
        if child.spriteID == id.Sprite.RS3_ICON_ACCORDION_5 then previous = child end
        if child.spriteID == id.Sprite.RS3_ICON_ACCORDION_2 then nextArrow = child end
    end
    for _, edge in ipairs({ "left", "right", "top" }) do
        Settings.set("ribbonBarPosition", edge)
        local first, last = buttonNamed("Modern 1"), buttonNamed("Modern 23")
        local list = first.parent
        local wheel = list.subscriptions[ui.Hook.ONSCROLLWHEEL]
        wheel(list, -100)
        local visible = 0
        for index = 1, 23 do
            if not buttonNamed("Modern " .. index).hidden then visible = visible + 1 end
        end
        expect(visible, 3, edge .. " obeys configured cap")
        expect(previous.hidden, true, edge .. " hides previous at start")
        expect(nextArrow.hidden, false, edge .. " indicates more buttons")
        expect(cog.parent, surface, edge .. " cog stays outside viewport")
        clickRoot(last)
        expect(panels[23]:IsActive(), false, edge .. " offscreen click cannot toggle a panel")
        clickRoot(nextArrow)
        expect(previous.hidden, false, edge .. " previous appears after arrow scrolling")
        expect(nextArrow.hidden, false, edge .. " both directions available in middle")
        wheel(list, 100)
        expect(nextArrow.hidden, true, edge .. " hides next at end")
        expect(last.hidden, false, edge .. " last panel reachable")
        expect(first.enabled, false, edge .. " first panel cannot intercept clicks")
        clickRoot(last)
        expect(panels[23]:IsActive(), true, edge .. " scrolled panel activates")
        panels[23]:SetActive(false)
        local x, y = tooltips.contextOrigins[list](last)
        local originX, originY = tooltips.contextOrigins[surface]({ x = 0, y = 0 })
        expect(x, originX + list.x + last.x - (list.scrollX or 0), edge .. " tooltip tracks horizontal scroll")
        expect(y, originY + list.y + last.y - (list.scrollY or 0), edge .. " tooltip tracks vertical scroll")
        clickRoot(cog)
        local settings = windows[#windows]
        settings.controls.cap.options.onChange(nil, 1)
        expect(Settings.get("ribbonBarButtonCap"), 1, "settings control changes cap")
        expect(db.ribbonBarButtonCap, 1, "cap persisted")
        wheel(list, 100)
        expect(last.hidden, false, "last panel remains reachable with a one-button cap")
        clickRoot(cog)
        Settings.set("ribbonBarButtonCap", 3)
    end
    area:SetSize(140, 140, 0, 0)
    tick()
    expect(surface.width <= area.width, true, "ribbon fits a smaller game area")
    Settings.set("ribbonBarPosition", "right")
    expect(surface.height <= area.height, true, "vertical ribbon fits a smaller game area")
    for index = 1, 22 do
        RibbonBar.unregister(panels[index])
    end
    local last = buttonNamed("Modern 23")
    expect(last.hidden, false, "removing buttons clamps scroll to remaining panel")
    expect(last.parent.scrollY, 0, "removing overflow resets scroll")
    expect(previous.hidden and nextArrow.hidden, true, "no indicators without overflow")
    RibbonBar.Shutdown()
end

local function classicUnavailableNativeLayoutAndRemount()
    local previousLog, diagnostics = log, {}
    log = function(message) diagnostics[#diagnostics + 1] = message end
    start(60, 1)
    gameview.failSize = true
    local optional = classicPanel("Optional", true)
    RibbonBar.register(optional)
    rail(44, "gameview failure still allows reservation")
    expect(#diagnostics, 1, "failed optional crop reports its diagnostic once")
    assert(diagnostics[1]:find("gameview", 1, true), "optional diagnostic identifies the gameview")
    tick()
    expect(#diagnostics, 1, "repeated layout checks do not spam optional crop warnings")
    clickRoot(buttonNamed("Optional"))
    rail(344, "gameview failure still allows selection")
    expect(gameview.width, 3440, "failed optional gameview remains client-owned")
    RibbonBar.unregister(optional)
    expect(area.width, 3440, "last unregister restores mandatory reservation")

    area = gameArea(61, 3440, 1440)
    local foreign = classicPanel("Foreign", true)
    RibbonBar.register(foreign)
    rail(44, "foreign overwrite setup")
    area:SetSize(-24, 0, 1, 1)
    tick()
    expect(buttons(), nil, "foreign native overwrite suspends the rail")
    local foreignDiagnostic = diagnostics[#diagnostics]
    assert(foreignDiagnostic:find("reason=area.", 1, true), "foreign layout diagnostic identifies the area")
    assert(foreignDiagnostic:find("expected=", 1, true), "foreign layout diagnostic includes expected geometry")
    assert(foreignDiagnostic:find("actual=", 1, true), "foreign layout diagnostic includes observed geometry")
    expect(RibbonBar.selectClassic(foreign, false), false, "unavailable native area rejects selection")
    RibbonBar.unregister(foreign)

    area = gameArea(62, 3440, 1440)
    area.position.xParentPc = 0
    local incompatible = classicPanel("Incompatible", true)
    RibbonBar.register(incompatible)
    expect(buttons(), nil, "incompatible topology cannot mount a rail")
    area.position.xParentPc = 0.5
    tick()
    local oldSurface = rail(44, "compatible layout becomes available")
    loaded[top.interfaceID] = nil
    tick()
    expect(buttons(), nil, "unloaded top layer retires Classic rail")
    expect(map.watches[oldSurface], nil, "top-layer unload removes map observer")
    expect(area.width, 3440, "unloaded layer restores native reservation")

    top = native(
        1062,
        71,
        nil,
        { x = 0, y = 0, xParentPc = 0, yParentPc = 0, xSelfPc = 0, ySelfPc = 0 },
        { width = 3440, height = 1440, widthParentPc = 0, heightParentPc = 0 }
    )
    tick()
    rail(44, "replacement top layer remounts collapsed")
    clickRoot(buttonNamed("Incompatible"))
    rail(344, "replacement top layer supports selection")
    loaded[area.interfaceID] = nil
    tick()
    expect(incompatible.releases, 1, "interface unload releases selected content")
    area = gameArea(64, 3440, 1440)
    local newPanel = classicPanel("New", true)
    RibbonBar.register(newPanel)
    rail(44, "fresh viewport starts collapsed")
    croppedGameview(44, "fresh viewport cold start")
    clickRoot(buttonNamed("New"))
    rail(344, "fresh viewport supports selection")
    croppedGameview(344, "fresh viewport selected")
    RibbonBar.Shutdown()
    expect(newPanel.releases, 1, "shutdown releases selected content")
    expect(area.width, 3440, "shutdown restores current native geometry")
    expect(events.prettyui_ribbon_bar, nil, "shutdown unsubscribes logic")
    expect(varEvents.prettyui_ribbon_bar, nil, "shutdown unsubscribes mode listener")
    expect(tooltips.contexts, tooltips.unregistered, "all tooltip contexts retired")
    log = previousLog
end

local function sharedNativeSettingsLifecycle()
    start(70)
    local mountSettings = assert(settingsEvents.prettyui_ribbon_bar)
    local parent = component(area, "native settings layer")
    parent:SetSize(440, 500)
    mountSettings({ component = parent })
    local nativeSettings = views[#views]
    expect(buttons(), nil, "native settings are available without panel registrations")
    expect(
        nativeSettings.controls.allowClassicMovement:IsSelected("allowClassicMovement"),
        false,
        "Classic movement is opt-in"
    )
    expect(
        nativeSettings.controls.respectInterfaceLock:IsSelected("respectInterfaceLock"),
        true,
        "Modern respects the lock by default"
    )
    nativeSettings.controls.respectInterfaceLock.options.onChange(nil, nil, "respectInterfaceLock", false)
    nativeSettings.controls.position.options.onChange(nil, 1)
    nativeSettings.controls.autoHide.options.onChange(nil, nil, "autoHide", false)
    nativeSettings.controls.cap.options.onChange(nil, 4)
    expect(Settings.get("ribbonBarPosition"), "left", "native settings update saved placement")
    expect(Settings.get("ribbonBarButtonCap"), 4, "native settings update saved cap without panels")

    local owner = classicPanel("Settings sync", false)
    RibbonBar.register(owner)
    clickRoot(buttonNamed("PrettyUI settings"))
    local floating = windows[#windows]
    expect(floating.controls.cap.value, 4, "floating settings load native edits")
    floating.controls.autoHide.options.onChange(nil, nil, "autoHide", true)
    expect(
        nativeSettings.controls.autoHide:IsSelected("autoHide"),
        true,
        "floating changes synchronize to native settings"
    )
    expect(
        floating.controls.respectInterfaceLock:IsSelected("respectInterfaceLock"),
        false,
        "floating settings load the Modern override"
    )
    nativeSettings.controls.position.options.onChange(nil, 3)
    expect(floating.controls.position.selected, 3, "native changes synchronize to floating settings")
    mode(1)
    expect(nativeSettings.destroyed, nil, "mode change preserves native settings")
    clickRoot(buttonNamed("PrettyUI settings"))
    local sidebar = views[#views]
    expect(sidebar.controls.position.selected, 3, "Classic settings expose saved placement")
    expect(sidebar.controls.autoHide:IsSelected("autoHide"), true, "Classic settings expose saved auto-hide")
    sidebar.controls.allowClassicMovement.options.onChange(nil, nil, "allowClassicMovement", true)
    expect(
        nativeSettings.controls.allowClassicMovement:IsSelected("allowClassicMovement"),
        true,
        "Classic movement edits synchronize to native settings"
    )
    sidebar.controls.cap.options.onChange(nil, 6)
    expect(nativeSettings.controls.cap.value, 6, "Classic changes synchronize to native settings")
    nativeSettings.controls.position.options.onChange(nil, 2)
    expect(sidebar.controls.position.selected, 2, "native changes synchronize to Classic settings")
    rail(344, "editing Modern preferences leaves Classic sidebar fixed")
    RibbonBar.unregister(owner)
    expect(sidebar.destroyed, true, "last panel unregister destroys sidebar settings")
    expect(nativeSettings.destroyed, nil, "last panel unregister preserves native settings")
    nativeSettings.controls.cap.options.onChange(nil, 7)
    expect(Settings.get("ribbonBarButtonCap"), 7, "native settings still work without the ribbon")

    mountSettings({ component = parent })
    local replacement = views[#views]
    expect(nativeSettings.destroyed, true, "remount destroys old settings view")
    expect(parent.destroyed, nil, "remount preserves the client-owned layer")
    expect(replacement.controls.cap.value, 7, "remount loads current saved settings")
    replacement.controls.cap.options.onChange(nil, 8)
    expect(db.ribbonBarButtonCap, 8, "remounted settings remain interactive")
    RibbonBar.Shutdown()
    expect(replacement.destroyed, true, "shutdown destroys native settings")
    expect(parent.destroyed, nil, "shutdown preserves the client-owned layer")
    expect(settingsEvents.prettyui_ribbon_bar, nil, "shutdown unsubscribes native settings")

    start(71)
    assert(settingsEvents.prettyui_ribbon_bar)({ component = area })
    local reopened = views[#views].controls
    expect(reopened.allowClassicMovement:IsSelected("allowClassicMovement"), true, "Classic opt-in survives restart")
    expect(reopened.respectInterfaceLock:IsSelected("respectInterfaceLock"), false, "Modern override survives restart")
    RibbonBar.Shutdown()
end

classicSelectionAndModeTransitions()
classicWidthProtectsChatAndInventory()
classicFixedWidthGameview()
classicOverflowKeepsButtonsReachable()
classicUnavailableNativeLayoutAndRemount()
modernOverflowAndCap()
sharedNativeSettingsLifecycle()
print("ribbon_bar_test: ok")
