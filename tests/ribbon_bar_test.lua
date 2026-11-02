local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function component(parent, kind, categoryID, dynamicID)
    local result = {
        kind = kind, children = {}, subscriptions = {}, hidden = false,
        x = 0, y = 0, width = 0, height = 0,
        cursorConfig = {},
        opConfig = { SetOpCursor = function() end, ClearOpCursors = function() end },
    }
    function result:SetPos(x, y, xa, ya)
        self.x = x + (parent and parent.width or 0) * (xa or 0)
        self.y = y + (parent and parent.height or 0) * (ya or 0)
    end
    function result:SetSize(w, h, wa, ha)
        self.width = w + (parent and parent.width or 0) * (wa or 0)
        self.height = h + (parent and parent.height or 0) * (ha or 0)
    end
    function result:SetWidth(w, anchor) self:SetSize(w, self.height, anchor) end
    function result:SetHeight(h, anchor) self:SetSize(self.width, h, nil, anchor) end
    function result:SetScrollSize(w, h) self.scrollWidth, self.scrollHeight = w, h end
    function result:SetScrollPos(x, y) self.scrollX, self.scrollY = x, y end
    function result:Subscribe(hook, name, callback)
        self.subscriptions[hook] = self.subscriptions[hook] or {}
        self.subscriptions[hook][callback and name or "default"] = callback or name
    end
    function result:Unsubscribe(hook, name)
        if self.subscriptions[hook] then self.subscriptions[hook][name or "default"] = nil end
    end
    function result:MoveToFront() end
    function result:MoveToBack() end
    function result:Destroy()
        self.destroyed = true
        for _, child in ipairs(self.children) do child:Destroy() end
    end
    if parent then table.insert(parent.children, result) end
    return Interfaces.component(result, parent, categoryID, dynamicID)
end

local function factory(kind)
    return { new = function(parent, categoryID, dynamicID)
        return component(parent, kind, categoryID, dynamicID)
    end }
end

local area
ui = {
    Layer = factory("layer"), Sprite = factory("sprite"), Text = factory("text"),
    Interfaces = { GetComponent = function() return area end },
    Hook = { ONCLICK = 1, ONHOLD = 2, ONDRAG = 3, ONRELEASE = 4,
        ONDRAGCOMPLETE = 5, ONSCROLLWHEEL = 6, ONMOUSEOVER = 7, ONMOUSELEAVE = 8,
        ONRESIZE = 9 },
    AlignMode = { TOPLEFT = 1, CENTRE = 2 },
}
id = {
    Component = { TOPLEVEL_V2__GAME_AREA = 1 },
    Sprite = setmetatable({}, { __index = function() return 1 end }),
    Font = { MUSEO_SANS_15PT_REGULAR = 1, CINZEL_13PT_BOLD = 2 },
}
local font = {
    baseline = 18,
    GetStringLineCount = function() return 1 end,
    GetStringWidth = function(_, text) return #text * 7 end,
}
config = {
    Font = { MUSEO_SANS_15PT_REGULAR = font, CINZEL_13PT_BOLD = font },
    Cursor = { CURSOR_OPEN = { id = 1 }, CURSOR_GOTO = { id = 2 } },
}
Mouse = { GetPosition = function() return { x = 0, y = 300 } end }
local storage = {}
PersistentDB = {
    GetString = function(_, key) return storage[key] end,
    GetBool = function(_, key) return storage[key] end,
    SetString = function(_, key, value) storage[key] = value end,
    SetBool = function(_, key, value) storage[key] = value end,
}
local tick
Event = { Logic = {
    Subscribe = function(_, callback) tick = callback end,
    Unsubscribe = function() tick = nil end,
} }
local messages = {}
local consolePrint = print
print = function(message) table.insert(messages, message) end

local function newArea()
    local result = component(nil, "game-area")
    result:SetSize(1000, 600)
    return result
end
local function liveChildren(parent, kind)
    local result = {}
    for _, child in ipairs(parent.children) do
        if not child.destroyed and not child.hidden and (kind == nil or child.kind == kind) then
            table.insert(result, child)
        end
    end
    return result
end
local function ribbon()
    return liveChildren(area, "layer")[1]
end
local function click(target)
    target.subscriptions[ui.Hook.ONCLICK].default()
end

local RibbonBar = require("src/ribbon_bar")
area = newArea()
RibbonBar.Start()
tick()
expect(#liveChildren(area), 0, "startup without registrations leaves no ribbon or settings")
expect(#messages, 0, "unused ribbon emits no deprecation notice")
expect(pcall(RibbonBar.Register, {}), false, "registration still requires an ID")
expect(#messages, 0, "invalid registration emits no deprecation notice")

local first = RibbonBar.Register({
    id = "first-plugin", categoryID = "auto", onClick = function() end,
})
expect(#liveChildren(ribbon(), "layer"), 2, "first plugin exposes its button and settings")
expect(#messages, 1, "first registration emits a notice")
assert(messages[1]:find("deprecated", 1, true) and messages[1]:find("first-plugin", 1, true),
    "notice identifies the deprecated API's consumer")
local firstRibbon = ribbon()
expect(firstRibbon.categoryID, 0, "the shared ribbon root inherits the static native host category")
expect(liveChildren(firstRibbon, "sprite")[1].categoryID > 0, true,
    "an auto-first ribbon frame allocates managed native IDs")
expect(liveChildren(firstRibbon, "layer")[2].categoryID > 0, true,
    "an auto entry button allocates managed native IDs")
expect(RibbonBar.Register({ id = "first-plugin" }), first, "duplicate registration updates the same handle")
expect(#messages, 1, "updating an existing registration does not repeat the notice")
expect(liveChildren(firstRibbon, "layer")[2].categoryID, 0,
    "updated legacy entry stays native inherited despite an auto shared ribbon")
local second = RibbonBar.Register({ id = "second-plugin" })
expect(#messages, 2, "another consumer receives its own notice")
first:Destroy()
expect(#liveChildren(ribbon(), "layer"), 2, "remaining plugin keeps settings available")

click(liveChildren(ribbon(), "layer")[1])
local opened = liveChildren(area, "layer")
second:Destroy()
expect(#liveChildren(area), 0, "last removal destroys ribbon and open settings")
for _, surface in ipairs(opened) do expect(surface.destroyed, true, "open surfaces are destroyed") end
tick()
expect(#liveChildren(area), 0, "logic tick cannot resurrect an unused ribbon")
expect(second:Destroy(), false, "repeated removal is harmless")

RibbonBar.SetPosition("top")
RibbonBar.SetAutoHide(true)
local returning = RibbonBar.Register({ id = "returning-plugin" })
expect(#liveChildren(ribbon(), "layer"), 2, "registration remounts after last removal")
expect(RibbonBar.GetPosition(), "top", "placement survives empty state")
expect(RibbonBar.GetAutoHide(), true, "auto-hide survives empty state")
click(liveChildren(ribbon(), "layer")[1])
Interfaces.unload()
area = nil
tick()
area = newArea()
tick()
expect(#liveChildren(ribbon(), "layer"), 2, "registered buttons remount after interface reload")
expect(#messages, 3, "remounting does not emit another notice")
returning:Destroy()

area = nil
local offline = RibbonBar.Register({ id = "offline-plugin" })
expect(#messages, 4, "registration while logged out still warns")
area = newArea()
tick()
expect(#liveChildren(ribbon(), "layer"), 2, "offline registration mounts on login")
offline:Destroy()
local mixedLegacy = RibbonBar.Register({ id = "legacy-first" })
local legacyRibbon = ribbon()
local mixedAuto = RibbonBar.Register({ id = "auto-second", categoryID = "auto" })
expect(ribbon(), legacyRibbon, "adding auto to a live legacy ribbon does not recreate shared chrome")
expect(liveChildren(legacyRibbon, "layer")[3].categoryID > 0, true,
    "an auto entry allocates independently of a legacy shared ribbon")
mixedAuto:Destroy()
mixedLegacy:Destroy()
RibbonBar.Shutdown()
expect(tick, nil, "shutdown removes logic subscription")
expect(#liveChildren(area), 0, "shutdown leaves no ribbon surfaces")
print = consolePrint
print("ribbon_bar_test: visibility, settings teardown, notices, auto-hide and interface reload passed")
