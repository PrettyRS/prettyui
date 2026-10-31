local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function component(parent)
    local result = { x = 0, y = 0, children = {} }
    function result:SetSize(width, height)
        self.width, self.height = width, height
    end
    function result:SetPos(x, y)
        self.x, self.y = x, y
    end
    function result:Destroy()
        self.destroyed = true
        for _, child in ipairs(self.children) do child:Destroy() end
    end
    if parent then table.insert(parent.children, result) end
    return Interfaces.component(result, parent)
end

local subscriptions = {}
local function subscriptionCount()
    local count = 0
    for _ in pairs(subscriptions) do count = count + 1 end
    return count
end

Event = {
    Logic = {
        Subscribe = function(name, callback) subscriptions[name] = callback end,
        Unsubscribe = function(name) subscriptions[name] = nil end,
    },
}
ui = {
    Layer = { new = component },
    Sprite = { new = component },
}
id = {
    Sprite = setmetatable({}, { __index = function(_, name) return name end }),
    Component = { TOPLEVEL_V2__ROOT = 1, TOPLEVEL_V2__GAME_AREA = 2 },
}
local parent = component()
parent:SetSize(500, 400)
ui.Interfaces.GetComponent = function() return parent end
Vector3 = {
    new = function(x, y, z) return { x = x, y = y, z = z } end,
}
ScreenConvert = {
    Vector3ToScreen = function(position)
        return { x = position.x, y = position.z - position.y / 64 }
    end,
}
local function entity(x, z)
    return {
        isValid = true,
        aabb = { maxY = 128 },
        config = { overlayHeight = -1 },
        position = setmetatable({ x = x, y = 0, z = z }, {
            __add = function(a, b)
                return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }
            end,
        }),
    }
end

local OverheadBar = require("src/overhead_bar")
local npc = entity(200, 200)
local bar = assert(OverheadBar.forNPC(npc, { value = 0.5 }))
expect(bar.fillClip.width, 28, "half fill clips the foreground")
expect(bar.fill.width, 56, "foreground is not stretched")
expect(bar.root.x, 172, "bar is horizontally centered above NPC")
expect(bar.root.y, 183, "NPC bar sits just above its current bounding box")
npc.position.x = 220
subscriptions[bar.eventID]()
expect(bar.root.x, 192, "bar follows moving NPC")
npc.aabb.maxY = 512
subscriptions[bar.eventID]()
expect(bar.root.y, 177, "NPC bar follows changes in the NPC's height")
npc.position.y = 640
npc.aabb.maxY = 768
subscriptions[bar.eventID]()
expect(bar.root.y, 173, "NPC bounding-box top is a world-space coordinate")
npc.position.y = 0
npc.aabb.maxY = 512
npc.config.overlayHeight = 256
subscriptions[bar.eventID]()
expect(bar.root.y, 181, "NPC-specific overlay height takes priority over bounding box")
npc.config.overlayHeight = -1
local overrideBar = assert(OverheadBar.forNPC(npc, { heightAboveGround = 320 }))
expect(overrideBar.root.y, 180, "explicit NPC height overrides bounding box")
npc.aabb.maxY = 768
subscriptions[overrideBar.eventID]()
expect(overrideBar.root.y, 180, "explicit NPC height remains fixed")
overrideBar:Destroy()
bar:SetValue(0)
expect(bar.fillClip.width, 0, "empty bar hides the fill")
bar:SetVariant("health.large")
bar:SetValue(0.5)
expect(bar.root.width, 120, "variant changes size")
expect(bar.fillClip.width, 60, "variant changes fill scale")
bar:SetValue(2)
expect(bar.fillClip.width, 120, "fill is clamped to full width")
npc.position.x = 900
subscriptions[bar.eventID]()
expect(bar.root.hidden, true, "offscreen NPC hides bar")
npc.position.x = 220
subscriptions[bar.eventID]()
expect(bar.root.hidden, false, "returning NPC shows bar")

local loc = entity(100, 200)
local locBar = assert(OverheadBar.forLoc(loc, { variant = "progress.green" }))
expect(locBar.root.y, 179, "Loc retains its fixed default height")
loc.isHidden = true
expect(locBar:Update(), false, "hidden Loc has no overhead bar")
expect(locBar.root.hidden, true, "hidden Loc hides its sprite")
loc.isHidden = false
expect(locBar:Update(), true, "visible Loc restores bar")
loc.isValid = false
subscriptions[locBar.eventID]()
expect(locBar.root, nil, "invalid Loc discards its bar")
expect(subscriptions[locBar.eventID], nil, "invalid Loc unsubscribes")

local player = entity(300, 200)
local playerBar = assert(OverheadBar.forPlayer(player, { variant = "adrenaline.large" }))
expect(playerBar.root.width, 120, "player uses chosen overhead variant")
expect(playerBar.root.y, 170, "player retains its fixed default height")
playerBar:Destroy()
expect(subscriptions[playerBar.eventID], nil, "destroy unsubscribes player bar")

local discarded = entity(400, 200)
local before = subscriptionCount()
local oldConvert = ScreenConvert.Vector3ToScreen
ScreenConvert.Vector3ToScreen = function(position)
    discarded.isValid = false
    return oldConvert(position)
end
local transient = OverheadBar.forNPC(discarded)
expect(transient, nil, "invalidated target is rejected during construction")
expect(subscriptionCount(), before, "construction invalidation leaves no subscription")
ScreenConvert.Vector3ToScreen = oldConvert

Interfaces.unload(parent.interfaceID)
subscriptions[bar.eventID]()
expect(bar.root, nil, "interface unload discards retained bars")
expect(next(subscriptions), nil, "interface unload removes event handlers")
OverheadBar.Shutdown()

print("overhead_bar_test: ok")
