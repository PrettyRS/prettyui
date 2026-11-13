-- The captured Classic topology has a separate full-screen plugin layer, an
-- origin-zero GAME_AREA child of VIEWPORT, and right-anchored native children.
-- IDs below are deliberately fixture IDs, not client/capture component numbers.
local function expect(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local positionFields = { "x", "y", "xParentPc", "yParentPc", "xSelfPc", "ySelfPc" }
local sizeFields = { "width", "height", "widthParentPc", "heightParentPc" }
local function pos(x, y, xp, yp, xs, ys)
    return { x = x, y = y, xParentPc = xp, yParentPc = yp, xSelfPc = xs, ySelfPc = ys }
end
local function size(w, h, wp, hp)
    return { width = w, height = h, widthParentPc = wp, heightParentPc = hp }
end
local function copy(descriptor, fields)
    local result = {}
    for _, field in ipairs(fields) do result[field] = descriptor[field] end
    return result
end
local function assertDescriptor(actual, expected, fields, message)
    for _, field in ipairs(fields) do expect(actual[field], expected[field], message .. "." .. field) end
end

local live, components = {}, {}
ui = { Interfaces = {} }
function ui.Interfaces:GetInterface(interfaceID) return live[interfaceID] end
function ui.Interfaces:GetComponent(packed) return components[packed] end
id = { Component = {}, VarPlayer = {
    TOPLEVEL_V2_CUSTOMIZATION_LOCK = 101,
    TOPLEVEL_V2_SKINS_VARP = 102,
    TOPLEVEL_V2_TRANSPARENCY = 103,
} }
local classicValue = 1
var = { VarPlayer = {
    TOPLEVEL_V2_LEGACY_INTERFACE = setmetatable({}, { __index = function(_, field)
        if field == "value" then return classicValue end
    end }),
    TOPLEVEL_V2_CUSTOMIZATION_LOCK = { value = 0 },
    TOPLEVEL_V2_TRANSPARENCY = { value = 0 },
} }
local warnings = {}
log = function(message)
    -- The native binding aborts instead of raising a catchable Lua error when
    -- invoked directly by C pcall without a Lua caller environment.
    assert(debug.getinfo(2, "S").what ~= "C", "native log requires a Lua caller")
    warnings[#warnings + 1] = message
end
local function warningCount(message)
    local count = 0
    for _, warning in ipairs(warnings) do
        if tostring(warning):find(message, 1, true) then count = count + 1 end
    end
    return count
end

local function component(interfaceID, staticID, parent, position, dimensions)
    local item = {
        interfaceID = interfaceID, staticID = staticID, categoryID = -1, dynamicID = -1,
        parent = parent, position = position, size = dimensions, posWrites = 0, sizeWrites = 0,
    }
    setmetatable(item, { __index = function(self, field)
        if field == "width" then return self.size.width + (parent and parent.width or 0) * self.size.widthParentPc end
        if field == "height" then return self.size.height + (parent and parent.height or 0) * self.size.heightParentPc end
        if field == "x" then
            return self.position.x + (parent and parent.width or 0) * self.position.xParentPc
                - self.width * self.position.xSelfPc
        end
        if field == "y" then
            return self.position.y + (parent and parent.height or 0) * self.position.yParentPc
                - self.height * self.position.ySelfPc
        end
    end })
    function item:SetPos(x, y, xp, yp, xs, ys)
        if self.isRestricted then error("restricted native component") end
        self.posWrites = self.posWrites + 1
        if self.failPos == "before" then self.failPos = nil; error("native position setter failed") end
        local nextPosition = pos(x, y, xp, yp, xs, ys)
        for _, field in ipairs(positionFields) do self.position[field] = nextPosition[field] end
        if self.failPos == "after" then self.failPos = nil; error("native position setter failed") end
    end
    function item:SetSize(w, h, wp, hp)
        if self.isRestricted then error("restricted native component") end
        self.sizeWrites = self.sizeWrites + 1
        if self.failSize == "before" then self.failSize = nil; error("native size setter failed") end
        local nextSize = size(w, h, wp, hp)
        for _, field in ipairs(sizeFields) do self.size[field] = nextSize[field] end
        if self.failSize == "after" then self.failSize = nil; error("native size setter failed") end
    end
    if staticID then components[(interfaceID << 16) | staticID] = item end
    live[interfaceID] = live[interfaceID] or {}
    return item
end

local function scene(options)
    options = options or {}
    components, live = {}, {}
    local top = component(4201, 71, nil, pos(0, 0, 0, 0, 0, 0), size(3440, 1440, 0, 0))
    local viewport = component(4202, 75, nil, pos(0, 0, 0, 0, 0, 0), size(3440, 1440, 0, 0))
    local area = component(4202, 81, viewport, pos(0, 0, .5, .5, .5, .5), size(0, 0, 1, 1))
    local gameview
    if not options.noGameview then
        gameview = component(4202, 87, viewport, pos(0, 0, 0, 0, 0, 0), size(0, 0, 1, 1))
    end
    -- The client capture uses positive xSelfPc = 1 on its right-anchored
    -- wrappers; model those exact coefficients, not a sign convention guessed
    -- from generic layout examples. Children stay fixed inside the wrapper.
    local minimapWrapper = component(4202, nil, area, pos(-25, 0, 1, 0, 1, 0), size(250, 250, 0, 0))
    local minimap = component(4202, nil, minimapWrapper, pos(0, 0, 0, 0, 0, 0), size(250, 250, 0, 0))
    local buttons = component(4202, nil, area, pos(-520, 0, 1, 0, 1, 0), size(32, 34, 0, 0))
    -- Captured Slayer HUD: VIEWPORT -> GAMEPLAY_HUDS -> SLAYER_COUNTER_WINDOW.
    -- Its mounted interface follows the window rather than GAME_AREA.
    local hud = component(4202, 91, viewport, pos(0, 0, .5, .5, .5, .5), size(0, 0, 1, 1))
    local slayer, slayerContent
    if not options.noSlayer then
        slayer = component(4202, 93, options.slayerInArea and area or hud,
            pos(-245, 2, 1, 0, 1, 0), size(180, 80, 0, 0))
        slayerContent = component(4203, 7, slayer, pos(12, 4, 0, 0, 0, 0), size(120, 40, 0, 0))
    end
    id.Component = {
        TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP = (4201 << 16) | 71,
        TOPLEVEL_V2__VIEWPORT = (4202 << 16) | 75,
        TOPLEVEL_V2__GAME_AREA = (4202 << 16) | 81,
        TOPLEVEL_V2__GAMEVIEW_WINDOW = (4202 << 16) | 87,
        TOPLEVEL_V2__GAMEPLAY_HUDS = (4202 << 16) | 91,
        TOPLEVEL_V2__SLAYER_COUNTER_WINDOW = (4202 << 16) | 93,
    }
    return {
        top = top, viewport = viewport, area = area, gameview = gameview,
        minimap = minimap, buttons = buttons,
        hud = hud, slayer = slayer, slayerContent = slayerContent,
        slayerPosition = slayer and copy(slayer.position, positionFields),
        position = copy(area.position, positionFields), dimensions = copy(area.size, sizeFields),
        gameviewPosition = gameview and copy(gameview.position, positionFields),
        gameviewSize = gameview and copy(gameview.size, sizeFields),
    }
end
local function globalX(item)
    return item.x + (item.parent and globalX(item.parent) or 0)
end
local function assertArea(sceneValue, width, message)
    local area = sceneValue.area
    expect(area.x, 0, message .. " native left edge")
    expect(area.width, sceneValue.viewport.width - width, message .. " native width")
    expect(area.height, sceneValue.viewport.height, message .. " native height")
    expect(globalX(sceneValue.minimap), sceneValue.viewport.width - width - 275,
        message .. " right-anchored minimap")
    expect(globalX(sceneValue.buttons), sceneValue.viewport.width - width - 552,
        message .. " native ribbon button/input")
    if sceneValue.slayer then
        expect(globalX(sceneValue.slayer), sceneValue.viewport.width - width - 425,
            message .. " Slayer containing window")
        expect(globalX(sceneValue.slayerContent), globalX(sceneValue.slayer) + 12,
            message .. " Slayer child render/input position")
        expect(sceneValue.slayerContent.position.x, 12, message .. " unchanged Slayer child offset")
    end
    if sceneValue.gameview then
        expect(sceneValue.gameview.width, sceneValue.viewport.width - width, message .. " gameview width")
        assertDescriptor(sceneValue.gameview.position, sceneValue.gameviewPosition, positionFields,
            message .. " unchanged gameview position")
    end
end
local function assertRestored(sceneValue, message)
    assertDescriptor(sceneValue.area.position, sceneValue.position, positionFields, message .. " position")
    assertDescriptor(sceneValue.area.size, sceneValue.dimensions, sizeFields, message .. " size")
    if sceneValue.slayer then
        assertDescriptor(sceneValue.slayer.position, sceneValue.slayerPosition, positionFields,
            message .. " Slayer position")
    end
    if sceneValue.gameview then
        assertDescriptor(sceneValue.gameview.position, sceneValue.gameviewPosition, positionFields,
            message .. " gameview position")
        assertDescriptor(sceneValue.gameview.size, sceneValue.gameviewSize, sizeFields,
            message .. " gameview size")
    end
end
local function writes(item) return item.posWrites, item.sizeWrites end
local function poison(item)
    for key in pairs(item) do item[key] = nil end
    setmetatable(item, {
        __index = function(_, key) error("read after interface unload: " .. tostring(key)) end,
        __newindex = function(_, key) error("write after interface unload: " .. tostring(key)) end,
    })
end

local capture = scene()
local ClassicLayout = require("src/core/classic_layout")
expect(ClassicLayout.update(44), true, "collapsed Classic rail reserves native width")
assertArea(capture, 44, "collapsed rail")
expect(globalX(capture.minimap), 3121, "captured minimap coordinate at 3440 minus 44")
expect(globalX(capture.buttons), 2844, "captured native buttons at 3440 minus 44")
assertDescriptor(capture.area.position, pos(0, 0, 0, 0, 0, 0), positionFields,
    "native self-anchor must not shift left boundary when resized")
assertDescriptor(capture.area.size, size(-44, 0, 1, 1), sizeFields, "collapsed reserved size")
local areaPos, areaSize = writes(capture.area)
local gamePos, gameSize = writes(capture.gameview)
expect(areaPos, 1, "first reservation positions GAME_AREA once")
expect(areaSize, 1, "first reservation sizes GAME_AREA once")
expect(gamePos, 0, "gameview keeps its original position")
expect(gameSize, 1, "first reservation sizes gameview once")
expect(capture.top.posWrites + capture.top.sizeWrites, 0, "plugin build layer remains full screen")
expect(capture.viewport.posWrites + capture.viewport.sizeWrites, 0, "viewport geometry remains untouched")
expect(capture.slayer.posWrites, 1, "collapsed rail shifts Slayer once")
expect(capture.slayer.sizeWrites, 0, "Slayer retains native dimensions")
expect(ClassicLayout.update(44), true, "repeated collapsed tick succeeds")
expect(capture.area.posWrites, areaPos, "repeated tick does not rewrite native position")
expect(capture.area.sizeWrites, areaSize, "repeated tick does not rewrite native size")
expect(capture.gameview.posWrites, gamePos, "repeated tick does not rewrite gameview position")
expect(capture.gameview.sizeWrites, gameSize, "repeated tick does not rewrite gameview size")
expect(capture.slayer.posWrites, 1, "repeated tick does not accumulate Slayer displacement")
expect(ClassicLayout.update(404), true, "expanded Classic rail reserves icon rail and body")
assertArea(capture, 404, "expanded rail")
expect(globalX(capture.minimap), 2761, "expanded minimap x")
expect(globalX(capture.buttons), 2484, "expanded native buttons x")
expect(capture.area.posWrites, 1, "expansion does not repeat top-left positioning")
expect(capture.area.sizeWrites, 2, "expansion applies one native width change")
expect(capture.gameview.sizeWrites, 2, "expansion applies one gameview width change")
expect(globalX(capture.slayer), 2611, "expanded Slayer position includes full 404-unit reservation")
expect(ClassicLayout.update(44), true, "collapsing derives width from original descriptors")
assertArea(capture, 44, "collapsed again")
expect(capture.area.sizeWrites, 3, "collapse applies one native width change")
expect(capture.gameview.sizeWrites, 3, "collapse applies one gameview width change")
ClassicLayout.restore()
assertRestored(capture, "teardown restores all ten original scalars per target")
expect(capture.area.x, 0, "original full-size center anchor resolves at x zero")
expect(capture.area.width, 3440, "original full native width returns")
expect(capture.area.posWrites, 2, "teardown restores original native position once")
expect(capture.area.sizeWrites, 4, "teardown restores original native size once")
expect(capture.gameview.posWrites, 0, "teardown never writes unchanged gameview position")
expect(capture.gameview.sizeWrites, 4, "teardown restores original gameview size once")
expect(capture.slayer.posWrites, 4, "Slayer collapses and restores without cumulative displacement")
ClassicLayout.restore()

-- Classic mode must be consulted on every update; mode exit gives native
-- ownership back even if the caller has not explicitly restored yet.
local mode = scene()
classicValue = 0
expect(ClassicLayout.update(44), false, "modern mode cannot reserve the native UI")
expect(mode.area.posWrites + mode.area.sizeWrites, 0, "modern mode makes no native writes")
classicValue = 2
expect(ClassicLayout.update(44), false, "non-one mode cannot reserve the native UI")
classicValue = 1
expect(ClassicLayout.update(44), true, "mode reentry captures a compatible baseline")
classicValue = 0
expect(ClassicLayout.update(44), false, "mode exit cannot claim Classic reservation")
assertRestored(mode, "mode exit restores owned native descriptors")
classicValue = 1
ClassicLayout.restore()

-- A counter already parented under GAME_AREA inherits the inset, not a second
-- explicit shift. Absent counters can appear after the sidebar is mounted.
do
    local inherited = scene({ slayerInArea = true })
    expect(ClassicLayout.update(404), true, "Slayer under native game area inherits reservation")
    assertArea(inherited, 404, "Slayer inherited inset")
    expect(inherited.slayer.posWrites, 0, "already inset Slayer is not shifted twice")
    ClassicLayout.restore()
    assertRestored(inherited, "inherited Slayer restoration")
    local late = scene({ noSlayer = true })
    expect(ClassicLayout.update(44), true, "absent Slayer does not block sidebar reservation")
    late.slayer = component(4202, 93, late.hud, pos(-245, 2, 1, 0, 1, 0), size(180, 80, 0, 0))
    late.slayerContent = component(4203, 7, late.slayer, pos(12, 4, 0, 0, 0, 0), size(120, 40, 0, 0))
    late.slayerPosition = copy(late.slayer.position, positionFields)
    expect(ClassicLayout.update(404), true, "late Slayer receives current expanded reservation")
    assertArea(late, 404, "late Slayer")
    ClassicLayout.restore()
    assertRestored(late, "late Slayer restoration")
end

do
    local slayerWarning = "PrettyUI: classic sidebar cannot move the Slayer counter"
    for _, failure in ipairs({ "before", "after" }) do
        local partial = scene()
        partial.slayer.failPos = failure
        local beforeWarnings = warningCount(slayerWarning)
        expect(ClassicLayout.update(44), true, "Slayer setter failure keeps native sidebar reservation")
        expect(partial.area.width, 3396, "Slayer failure does not undo mandatory native reservation")
        assertDescriptor(partial.slayer.position, partial.slayerPosition, positionFields,
            "failed Slayer shift rolls back its owned position")
        local count = partial.slayer.posWrites
        ClassicLayout.update(404)
        expect(partial.slayer.posWrites, count, "failed Slayer setter is not retried each tick")
        expect(warningCount(slayerWarning), beforeWarnings + 1, "Slayer failure logs once")
        ClassicLayout.restore()
        assertRestored(partial, "Slayer setter failure restoration")
    end
    local restrictedSlayer = scene()
    restrictedSlayer.slayer.isRestricted = true
    expect(ClassicLayout.update(44), true, "restricted Slayer does not block native reservation")
    expect(restrictedSlayer.slayer.posWrites, 0, "restricted Slayer receives no writes")
    ClassicLayout.restore()
    local foreignSlayer = scene()
    ClassicLayout.update(44)
    foreignSlayer.slayer.position.y = 31
    local count = foreignSlayer.slayer.posWrites
    ClassicLayout.update(404); ClassicLayout.update(404)
    expect(foreignSlayer.slayer.posWrites, count, "foreign Slayer position is not fought on later ticks")
    ClassicLayout.restore()
    expect(foreignSlayer.slayer.position.y, 31, "foreign Slayer placement survives teardown")
    local nativeSize = scene()
    ClassicLayout.update(44)
    nativeSize.slayer.size.height = 160
    ClassicLayout.restore()
    assertRestored(nativeSize, "Slayer restoration preserves independent native sizing")
    expect(nativeSize.slayer.height, 160, "Slayer dimensions remain client-owned")
end

-- An optional target never prevents mandatory native UI reservation.
local absent = scene({ noGameview = true })
expect(ClassicLayout.update(44), true, "missing gameview is optional")
assertArea(absent, 44, "missing gameview")
local optionalWarning = "PrettyUI: classic sidebar cannot resize the gameview"
expect(warningCount(optionalWarning), 1, "missing optional gameview reports its limitation")
expect(ClassicLayout.update(44), true, "missing gameview still reserves on subsequent ticks")
expect(warningCount(optionalWarning), 1, "optional warning is emitted only once per environment")
ClassicLayout.restore()
assertRestored(absent, "missing gameview teardown")
local incompatibleGameview = scene()
incompatibleGameview.gameview.size.width = -15
expect(ClassicLayout.update(44), true, "incompatible gameview does not block native reservation")
expect(incompatibleGameview.area.width, 3396, "incompatible gameview still shifts native UI")
expect(incompatibleGameview.gameview.width, 3425, "incompatible gameview layout is preserved")
ClassicLayout.restore()
expect(incompatibleGameview.area.size.width, 0, "incompatible gameview teardown restores native UI")
expect(incompatibleGameview.gameview.size.width, -15, "incompatible gameview stays untouched on teardown")
local restricted = scene()
restricted.gameview.isRestricted = true
expect(ClassicLayout.update(44), true, "restricted gameview is optional")
expect(restricted.area.width, 3396, "restricted gameview still shifts native UI")
expect(restricted.gameview.width, 3440, "restricted gameview is not resized")
ClassicLayout.restore()
assertRestored(restricted, "restricted gameview teardown")
for _, failure in ipairs({ "before", "after" }) do
    local optional = scene()
    optional.gameview.failSize = failure
    expect(ClassicLayout.update(404), true, "optional gameview " .. failure .. " error does not block reservation")
    expect(optional.area.width, 3036, "optional failure preserves mandatory native reservation")
    assertDescriptor(optional.gameview.size, optional.gameviewSize, sizeFields,
        "optional " .. failure .. " failure rolls back its size")
    ClassicLayout.restore()
    assertRestored(optional, "optional " .. failure .. " failure teardown")
end

-- Mandatory topology is deliberately strict: no overlay-only rail is safe.
local incompatible = scene()
incompatible.area.size.widthParentPc = .9
expect(ClassicLayout.update(44), false, "non-full-size GAME_AREA rejects reservation")
expect(incompatible.area.posWrites + incompatible.area.sizeWrites, 0, "invalid topology is never written")
local suspendedWarning = "PrettyUI: classic sidebar suspended; native layout is unavailable"
local suspensionCount = warningCount(suspendedWarning)
expect(suspensionCount, 1, "incompatible layout reports suspension through native-safe logging")
expect(ClassicLayout.update(44), false, "incompatible topology remains suspended on repeated ticks")
expect(warningCount(suspendedWarning), suspensionCount, "mandatory suspension logs once per environment")
ClassicLayout.restore()
local missingTop = scene()
components[id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP] = nil
expect(ClassicLayout.update(44), false, "missing separate plugin top layer suspends Classic sidebar")
expect(missingTop.area.posWrites + missingTop.area.sizeWrites, 0, "missing mount makes no native writes")
ClassicLayout.restore()
local blocked = scene()
blocked.area.isRestricted = true
expect(ClassicLayout.update(44), false, "restricted mandatory target cannot reserve space")
expect(blocked.area.posWrites + blocked.area.sizeWrites, 0, "restricted mandatory target is not touched")
ClassicLayout.restore()
for _, failure in ipairs({ "before", "after" }) do
    local partial = scene()
    partial.area.failSize = failure
    local ok, err = pcall(ClassicLayout.update, 44)
    expect(ok, false, "mandatory " .. failure .. " failure propagates")
    assert(tostring(err):find("native size setter failed", 1, true), "original mandatory setter error propagates")
    assertRestored(partial, "mandatory " .. failure .. " partial write rolled back")
    ClassicLayout.restore()
end
local firstSetter = scene()
firstSetter.area.failPos = "after"
local ok, err = pcall(ClassicLayout.update, 44)
expect(ok, false, "first mandatory setter failure propagates")
assert(tostring(err):find("native position setter failed", 1, true), "first setter retains its original error")
assertRestored(firstSetter, "first setter partial mutation rolled back")
ClassicLayout.restore()

local foreign = scene()
expect(ClassicLayout.update(44), true, "begin owning a compatible native target")
foreign.area.size.width = 0 -- Client script restores width without notifying the helper.
areaPos, areaSize = writes(foreign.area)
expect(ClassicLayout.update(44), false, "unexpected client overwrite cannot be re-applied every tick")
expect(ClassicLayout.update(44), false, "repeated overwrite remains suspended")
expect(foreign.area.posWrites, areaPos + 1, "suspension restores the still-owned position once")
expect(foreign.area.sizeWrites, areaSize, "foreign overwrite receives no size writes")
ClassicLayout.restore()
expect(foreign.area.size.width, 0, "foreign size edit is preserved on teardown")
local changedAnchor = scene()
expect(ClassicLayout.update(44), true, "own native descriptors before foreign anchor change")
changedAnchor.area.position.yParentPc = .25
areaPos = changedAnchor.area.posWrites
ClassicLayout.restore()
expect(changedAnchor.area.posWrites, areaPos, "foreign anchor descriptor is never overwritten")
expect(changedAnchor.area.position.yParentPc, .25, "foreign anchor survives teardown")
expect(changedAnchor.area.size.width, 0, "independently owned size can still restore")

-- Replacement uses identical numeric IDs but a different native component
-- object/layout. Never probe a retired handle or restore onto the newcomer.
local remounted = scene()
expect(ClassicLayout.update(44), true, "initial native generation reserves space")
local oldArea = remounted.area
local replacement = component(4202, oldArea.staticID, remounted.viewport,
    pos(29, 0, 0, 0, 0, 0), size(-120, 0, 1, 1))
poison(oldArea)
ClassicLayout.restore()
expect(replacement.position.x, 29, "same-ID replacement retains independent placement")
expect(replacement.size.width, -120, "same-ID replacement retains independent width")
expect(replacement.posWrites + replacement.sizeWrites, 0, "replacement is never treated as owned")
expect(remounted.slayer.position.x, -245, "same-interface replacement teardown restores owned Slayer position")
expect(ClassicLayout.update(44), false, "incompatible replacement does not inherit stale ownership")
ClassicLayout.restore()

-- An unloaded interface poisons even ID reads. The helper can only use cached
-- interface IDs, discard its old records and find fresh components on remount.
local unloaded = scene()
expect(ClassicLayout.update(404), true, "reserve space before interface unload")
live[4202] = nil
for packed, item in pairs(components) do
    if packed >> 16 == 4202 then components[packed] = nil; poison(item) end
end
ClassicLayout.restore()
local newGeneration = scene()
expect(ClassicLayout.update(44), true, "a fresh native generation can reserve space")
assertArea(newGeneration, 44, "new interface generation")
ClassicLayout.restore()
assertRestored(newGeneration, "new generation teardown")

local resized = scene()
expect(ClassicLayout.update(404), true, "reserve before viewport resize")
resized.viewport:SetSize(3000, 900, 0, 0)
resized.top:SetSize(3000, 900, 0, 0)
expect(ClassicLayout.update(44), true, "confirmed viewport resize reuses uncropped baseline")
assertArea(resized, 44, "resized viewport")
expect(resized.area.height, 900, "resize retains full viewport height")
expect(ClassicLayout.update(404), true, "viewport resize still supports expansion")
assertArea(resized, 404, "resized expanded viewport")
ClassicLayout.restore()
assertRestored(resized, "viewport resize teardown restores descriptors")
expect(resized.area.width, 3000, "restored percent-based area follows current viewport width")

-- An optional native script taking over GAMEVIEW_WINDOW cannot disable or
-- repeatedly overwrite the mandatory GAME_AREA reservation.
local optionalOverwrite = scene()
expect(ClassicLayout.update(44), true, "optional foreign overwrite starts from owned gameview")
optionalOverwrite.gameview.size.width = -17
local optionalWrites = optionalOverwrite.gameview.sizeWrites
local optionalWarningCount = warningCount(optionalWarning)
expect(ClassicLayout.update(44), true, "gameview foreign overwrite keeps native reservation available")
assertArea({ area = optionalOverwrite.area, viewport = optionalOverwrite.viewport,
    minimap = optionalOverwrite.minimap, buttons = optionalOverwrite.buttons }, 44,
    "gameview foreign overwrite")
expect(optionalOverwrite.gameview.size.width, -17, "foreign gameview size remains client-owned")
expect(ClassicLayout.update(404), true, "gameview conflict does not prevent native expansion")
expect(optionalOverwrite.area.width, 3036, "mandatory native area expands despite optional conflict")
expect(ClassicLayout.update(404), true, "same optional conflict keeps succeeding on later ticks")
expect(optionalOverwrite.gameview.sizeWrites, optionalWrites,
    "foreign gameview overwrite is not fought by repeated setters")
expect(warningCount(optionalWarning), optionalWarningCount + 1,
    "one optional warning describes the newly unavailable gameview")
ClassicLayout.restore()
expect(optionalOverwrite.area.size.width, 0, "optional conflict teardown restores native area")
expect(optionalOverwrite.gameview.size.width, -17, "optional conflict teardown preserves foreign edit")

-- A genuine remount can reuse every numeric ID without reusing old component
-- objects. Poison both retained target handles to catch accidental ID reads.
local compatibleRemount = scene()
expect(ClassicLayout.update(404), true, "reserve before same-ID compatible remount")
local previousArea, previousGameview = compatibleRemount.area, compatibleRemount.gameview
local freshRemount = scene()
poison(previousArea)
poison(previousGameview)
poison(compatibleRemount.slayer)
expect(ClassicLayout.update(44), true, "same-ID remount independently recaptures compatible baseline")
assertArea(freshRemount, 44, "same-ID compatible remount")
expect(freshRemount.area.posWrites, 1, "fresh remount positions only the new native target")
expect(freshRemount.area.sizeWrites, 1, "fresh remount sizes only the new native target")
expect(freshRemount.gameview.sizeWrites, 1, "fresh remount sizes only the new gameview")
ClassicLayout.restore()
assertRestored(freshRemount, "same-ID compatible remount teardown")

-- A confirmed viewport resize permits a freshly reset native baseline to be
-- reserved once; the same reset without another environment transition must
-- suspend instead of fighting a client script on every logic tick.
local resetOnResize = scene()
expect(ClassicLayout.update(44), true, "reserve before native-script resize reset")
for _, field in ipairs(positionFields) do
    resetOnResize.area.position[field] = resetOnResize.position[field]
end
for _, field in ipairs(sizeFields) do
    resetOnResize.area.size[field] = resetOnResize.dimensions[field]
    resetOnResize.gameview.size[field] = resetOnResize.gameviewSize[field]
end
resetOnResize.viewport:SetSize(3000, 900, 0, 0)
resetOnResize.top:SetSize(3000, 900, 0, 0)
expect(ClassicLayout.update(44), true, "confirmed viewport resize recaptures client-reset baseline")
assertArea(resetOnResize, 44, "confirmed resize and baseline reset")
for _, field in ipairs(positionFields) do
    resetOnResize.area.position[field] = resetOnResize.position[field]
end
for _, field in ipairs(sizeFields) do
    resetOnResize.area.size[field] = resetOnResize.dimensions[field]
end
local resetPosWrites, resetSizeWrites = writes(resetOnResize.area)
expect(ClassicLayout.update(44), false, "unconfirmed repeat reset suspends mandatory reservation")
expect(resetOnResize.area.posWrites, resetPosWrites, "foreign baseline reset gets no position setter")
expect(resetOnResize.area.sizeWrites, resetSizeWrites, "foreign baseline reset gets no size setter")
local suspendedPosWrites, suspendedSizeWrites = writes(resetOnResize.area)
expect(ClassicLayout.update(44), false, "subsequent ticks cannot retry a repeated foreign reset")
expect(resetOnResize.area.posWrites, suspendedPosWrites, "repeated reset never writes position again")
expect(resetOnResize.area.sizeWrites, suspendedSizeWrites, "repeated reset never writes size again")
expect(resetOnResize.area.size.width, 0, "unconfirmed reset retains client-native full width")
ClassicLayout.restore()
assertRestored(resetOnResize, "post-conflict teardown leaves reset baseline intact")

print("classic_layout_test: native reservation and lifecycle passed")
