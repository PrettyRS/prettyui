local Interfaces = require("tests/interface_fixture")
local function expect(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local events = { Logic = {}, VarTransmit = {} }
Event = {}
for name, callbacks in pairs(events) do
    Event[name] = {
        Subscribe = function(key, callback) callbacks[key] = callback end,
        Unsubscribe = function(key) callbacks[key] = nil end,
    }
end
local function emit(name, payload)
    for _, callback in pairs(events[name]) do callback(payload) end
end
local focus = { configName = "WORLDMAP_FOCUS", value = 0 }
var = { VarClient = { WORLDMAP_FOCUS = focus } }
id = { Component = { TOPLEVEL_V2__GAME_AREA = (1477 << 16) | 61 } }
ui = { Interfaces = {}, Layer = {} }
function ui.Layer.new(parent, category, dynamic)
    local root = Interfaces.component({ parent = parent, children = {}, hidden = false }, parent, category, dynamic)
    function root:Destroy()
        for _, child in ipairs(self.children) do child:Destroy() end
        self.destroyed = true
    end
    return root
end
local area = Interfaces.component({ interfaceID = 1477, staticID = 61,
    width = 1000, height = 700, visibleGlobal = true, children = {} })
local Components = require("src/core/components")
local WorldMap = require("src/core/world_map")
local root = Components.new(ui.Layer, area, { categoryID = "auto" })
expect(root.hidden, true, "loading PrettyUI while the map is already open suppresses its first root")
Components.setHidden(root, false)
expect(root.hidden, true, "root visibility writes cannot bypass an already-open map")
local child = Components.new(ui.Layer, root)
Components.setHidden(child, true)
local function map(value)
    focus.value = value
    emit("VarTransmit", { var = focus, newValue = value })
end
emit("VarTransmit", { var = { configName = "OTHER_VARIABLE" }, newValue = -1 })
expect(root.hidden, true, "unrelated variable updates cannot resume overlays")
map(-1)
area.visibleGlobal = false
emit("Logic")
expect(root.hidden, true, "focus close alone cannot resume a missing game area")
map(2)
emit("Logic")
expect(root.hidden, true, "reopening during deferred restoration keeps overlays suppressed")
map(-1)
area.visibleGlobal = true
emit("Logic")
expect(root.hidden, false, "initially suppressed root restores its requested visibility")
expect(child.hidden, true, "suspension does not change nested control visibility")
map(0)
root:Destroy()
-- Native dynamic IDs may be reused while the map is open. A dead handle must
-- neither be touched on resume nor overwrite its replacement's visibility.
local replacement = Components.new(ui.Layer, area, { categoryID = "auto" })
Components.setHidden(replacement, true)
map(-1)
emit("Logic")
expect(replacement.hidden, true, "retired roots cannot overwrite replacement visibility")
Components.setHidden(replacement, false)
do
    -- Native UI outlives temporary Lua handles to it. The suspension registry
    -- must retain identity metadata, not depend on one handle remaining alive.
    local alias = setmetatable({}, { __index = replacement,
        __newindex = function(_, key, value) replacement[key] = value end })
    WorldMap.track(alias)
end
collectgarbage("collect")
map(0)
expect(replacement.hidden, true, "collecting a temporary Lua handle cannot exempt its native root")
map(-1)
emit("Logic")
expect(replacement.hidden, false, "native roots restore after temporary Lua handles are collected")
replacement:Destroy()
WorldMap.shutdown()
print("world_map_test: ok")
