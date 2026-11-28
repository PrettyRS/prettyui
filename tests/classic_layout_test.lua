-- Classic layout fixture: a separate plugin layer, GAME_AREA under VIEWPORT,
-- and right-anchored native children. Component IDs are synthetic.
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
    for _, field in ipairs(fields) do
        result[field] = descriptor[field]
    end
    return result
end
local function assertDescriptor(actual, expected, fields, message)
    for _, field in ipairs(fields) do
        expect(actual[field], expected[field], message .. "." .. field)
    end
end

local live, components = {}, {}
ui = { Interfaces = {} }
function ui.Interfaces.GetInterface(_, interfaceID) return live[interfaceID] end
function ui.Interfaces.GetComponent(_, packed) return components[packed] end
id = {
    Component = {},
    VarPlayer = {
        TOPLEVEL_V2_CUSTOMIZATION_LOCK = 101,
        TOPLEVEL_V2_SKINS_VARP = 102,
        TOPLEVEL_V2_TRANSPARENCY = 103,
    },
}
local classicValue = 1
var = {
    VarPlayer = {
        TOPLEVEL_V2_LEGACY_INTERFACE = setmetatable({}, {
            __index = function(_, field)
                if field == "value" then return classicValue end
            end,
        }),
        TOPLEVEL_V2_CUSTOMIZATION_LOCK = { value = 0 },
        TOPLEVEL_V2_TRANSPARENCY = { value = 0 },
    },
}
local warnings = {}
log = function(message)
    -- The native binding aborts instead of raising a catchable Lua error when
    -- invoked directly by C pcall without a Lua caller environment.
    assert(debug.getinfo(2, "S").what ~= "C", "native log requires a Lua caller")
    warnings[#warnings + 1] = message
end

local function expectSuspended(width, reason, expected, actual)
    local prefix = "PrettyUI: classic sidebar suspended; native layout is unavailable"
    local message = prefix .. " width=" .. width .. " reason=" .. reason
    if expected ~= nil or actual ~= nil then
        message = message .. " expected=" .. tostring(expected) .. " actual=" .. tostring(actual)
    end
    expect(warnings[#warnings], message, "native suspension cause")
end

local function component(interfaceID, staticID, parent, position, dimensions)
    local item = {
        interfaceID = interfaceID,
        staticID = staticID,
        categoryID = -1,
        dynamicID = -1,
        parent = parent,
        children = {},
        position = position,
        size = dimensions,
        posWrites = 0,
        sizeWrites = 0,
    }
    setmetatable(item, {
        __index = function(self, field)
            if field == "width" then
                return self.size.width + (parent and parent.width or 0) * self.size.widthParentPc
            end
            if field == "height" then
                return self.size.height + (parent and parent.height or 0) * self.size.heightParentPc
            end
            if field == "x" then
                return self.position.x
                    + (parent and parent.width or 0) * self.position.xParentPc
                    - self.width * self.position.xSelfPc
            end
            if field == "y" then
                return self.position.y
                    + (parent and parent.height or 0) * self.position.yParentPc
                    - self.height * self.position.ySelfPc
            end
        end,
    })
    function item:SetPos(x, y, xp, yp, xs, ys)
        if self.isRestricted then error("restricted native component") end
        self.posWrites = self.posWrites + 1
        if self.failPos == "before" then
            self.failPos = nil
            error("native position setter failed")
        end
        local nextPosition = pos(x, y, xp, yp, xs, ys)
        for _, field in ipairs(positionFields) do
            self.position[field] = nextPosition[field]
        end
        if self.failPos == "after" then
            self.failPos = nil
            error("native position setter failed")
        end
    end
    function item:SetSize(w, h, wp, hp)
        if self.isRestricted then error("restricted native component") end
        self.sizeWrites = self.sizeWrites + 1
        if self.failSize == "before" then
            self.failSize = nil
            error("native size setter failed")
        end
        local nextSize = size(w, h, wp, hp)
        for _, field in ipairs(sizeFields) do
            self.size[field] = nextSize[field]
        end
        if self.failSize == "after" then
            self.failSize = nil
            error("native size setter failed")
        end
    end
    function item:GetChild(childStaticID)
        return self.children[childStaticID]
    end
    if parent and staticID then parent.children[staticID] = item end
    if staticID then components[(interfaceID << 16) | staticID] = item end
    live[interfaceID] = live[interfaceID] or {}
    return item
end

local function scene(options)
    options = options or {}
    components, live = {}, {}
    local top = component(4201, 71, nil, pos(0, 0, 0, 0, 0, 0), size(3440, 1440, 0, 0))
    local viewport = component(4202, 75, nil, pos(0, 0, 0, 0, 0, 0), size(3440, 1440, 0, 0))
    local area = component(4202, 81, viewport, pos(0, 0, 0.5, 0.5, 0.5, 0.5), size(0, 0, 1, 1))
    local gameview
    if not options.noGameview then
        gameview = component(4202, 87, viewport, pos(0, 0, 0, 0, 0, 0), size(0, 0, 1, 1))
    end
    -- Native right-anchored wrappers use xSelfPc = 1; children retain local positions.
    local minimapWrapper = component(4202, nil, area, pos(-25, 0, 1, 0, 1, 0), size(250, 250, 0, 0))
    local minimap = component(4202, nil, minimapWrapper, pos(0, 0, 0, 0, 0, 0), size(250, 250, 0, 0))
    local buttons = component(4202, nil, area, pos(-520, 0, 1, 0, 1, 0), size(32, 34, 0, 0))
    -- Captured Slayer HUD: VIEWPORT -> GAMEPLAY_HUDS -> SLAYER_COUNTER_WINDOW.
    -- Its mounted interface follows the window rather than GAME_AREA.
    local hud = component(4202, 91, viewport, pos(0, 0, 0.5, 0.5, 0.5, 0.5), size(0, 0, 1, 1))
    local slayer, slayerContent
    if not options.noSlayer then
        slayer =
            component(4202, 93, options.slayerInArea and area or hud, pos(-245, 2, 1, 0, 1, 0), size(180, 80, 0, 0))
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
        top = top,
        viewport = viewport,
        area = area,
        gameview = gameview,
        minimap = minimap,
        buttons = buttons,
        hud = hud,
        slayer = slayer,
        slayerContent = slayerContent,
        slayerPosition = slayer and copy(slayer.position, positionFields),
        position = copy(area.position, positionFields),
        dimensions = copy(area.size, sizeFields),
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
    expect(globalX(sceneValue.minimap), sceneValue.viewport.width - width - 275, message .. " right-anchored minimap")
    expect(
        globalX(sceneValue.buttons),
        sceneValue.viewport.width - width - 552,
        message .. " native ribbon button/input"
    )
    if sceneValue.slayer then
        expect(
            globalX(sceneValue.slayer),
            sceneValue.viewport.width - width - 425,
            message .. " Slayer containing window"
        )
        expect(
            globalX(sceneValue.slayerContent),
            globalX(sceneValue.slayer) + 12,
            message .. " Slayer child render/input position"
        )
        expect(sceneValue.slayerContent.position.x, 12, message .. " unchanged Slayer child offset")
    end
    if sceneValue.gameview then
        expect(sceneValue.gameview.width, sceneValue.viewport.width - width, message .. " gameview width")
        assertDescriptor(
            sceneValue.gameview.position,
            sceneValue.gameviewPosition,
            positionFields,
            message .. " unchanged gameview position"
        )
    end
end
local function assertRestored(sceneValue, message)
    assertDescriptor(sceneValue.area.position, sceneValue.position, positionFields, message .. " position")
    assertDescriptor(sceneValue.area.size, sceneValue.dimensions, sizeFields, message .. " size")
    if sceneValue.slayer then
        assertDescriptor(
            sceneValue.slayer.position,
            sceneValue.slayerPosition,
            positionFields,
            message .. " Slayer position"
        )
    end
    if sceneValue.gameview then
        assertDescriptor(
            sceneValue.gameview.position,
            sceneValue.gameviewPosition,
            positionFields,
            message .. " gameview position"
        )
        assertDescriptor(sceneValue.gameview.size, sceneValue.gameviewSize, sizeFields, message .. " gameview size")
    end
end
local function writes(item) return item.posWrites, item.sizeWrites end
local function poison(item)
    for key in pairs(item) do
        item[key] = nil
    end
    setmetatable(item, {
        __index = function(_, key) error("read after interface unload: " .. tostring(key)) end,
        __newindex = function(_, key) error("write after interface unload: " .. tostring(key)) end,
    })
end

local ClassicLayout = require("src/nis/classic_layout")

local function reservationFollowsRailAndRestoresOriginalLayout()
    local view = scene()
    local warningCount = #warnings
    expect(ClassicLayout.update(44), true, "collapsed rail reserves native width")
    expect(#warnings, warningCount, "successful reservation emits no diagnostic")
    assertArea(view, 44, "collapsed rail")
    assertDescriptor(
        view.area.position,
        pos(0, 0, 0, 0, 0, 0),
        positionFields,
        "reservation removes centered native anchors"
    )
    local positionWrites, sizeWrites = writes(view.area)
    ClassicLayout.update(44)
    expect(view.area.posWrites, positionWrites, "idle update does not reposition native area")
    expect(view.area.sizeWrites, sizeWrites, "idle update does not resize native area")
    expect(ClassicLayout.update(404), true, "expansion reserves panel body")
    assertArea(view, 404, "expanded rail")
    expect(ClassicLayout.update(44), true, "collapse removes body reservation")
    assertArea(view, 44, "collapsed again")
    ClassicLayout.restore()
    assertRestored(view, "shutdown restores all native descriptors")
    expect(view.area.width, 3440, "restored game area fills viewport")
    ClassicLayout.restore()
end

local function modeExitRestoresNativeOwnership()
    local view = scene()
    classicValue = 0
    expect(ClassicLayout.update(44), false, "modern mode cannot reserve Classic space")
    expect(view.area.sizeWrites, 0, "modern mode does not write native area")
    classicValue = 1
    expect(ClassicLayout.update(44), true, "Classic mode captures native baseline")
    classicValue = 0
    expect(ClassicLayout.update(44), false, "mode exit stops reserving Classic space")
    assertRestored(view, "mode exit restores owned descriptors")
    classicValue = 1
    ClassicLayout.restore()
end

local function slayerPositionIsOptionalAndNeverShiftedTwice()
    local inherited = scene({ slayerInArea = true })
    expect(ClassicLayout.update(404), true, "Slayer under native area inherits inset")
    expect(inherited.slayer.posWrites, 0, "inherited inset is not applied twice")
    ClassicLayout.restore()
    assertRestored(inherited, "inherited Slayer position")

    local unavailable = scene()
    unavailable.slayer.failPos = "after"
    expect(ClassicLayout.update(44), true, "Slayer setter failure does not block game area")
    expect(unavailable.area.width, 3396, "mandatory reservation survives Slayer failure")
    assertDescriptor(
        unavailable.slayer.position,
        unavailable.slayerPosition,
        positionFields,
        "failed Slayer shift rolls back"
    )
    ClassicLayout.restore()

    local foreign = scene()
    ClassicLayout.update(44)
    foreign.slayer.position.y = 31
    local positionWrites = foreign.slayer.posWrites
    ClassicLayout.update(404)
    expect(foreign.slayer.posWrites, positionWrites, "client-owned Slayer position is not overwritten")
    ClassicLayout.restore()
    expect(foreign.slayer.position.y, 31, "client-owned Slayer position survives teardown")
end

local function slayerTransitionWaitsForNativeRightAnchor()
    local view = scene()
    view.slayer:SetPos(3198, 2, 0, 0, 0, 0)
    local writesBefore, warningsBefore = view.slayer.posWrites, #warnings
    expect(ClassicLayout.update(44), true, "Modern Slayer placement does not block Classic area")
    expect(view.slayer.posWrites, writesBefore, "Modern absolute Slayer position is not claimed")
    expect(#warnings, warningsBefore, "transitional Slayer placement is not an optional failure")
    view.slayer:SetPos(-245, 2, 1, 0, 1, 0)
    expect(ClassicLayout.update(44), true, "Classic right anchor is recaptured with unchanged reservation")
    expect(view.slayer.position.x, -289, "right-anchored Slayer receives the rail offset once")
    local shiftedWrites = view.slayer.posWrites
    ClassicLayout.update(44)
    expect(view.slayer.posWrites, shiftedWrites, "unchanged right anchor is not shifted again")
    ClassicLayout.restore()
    expect(view.slayer.position.x, -245, "restoration returns to actual Classic baseline")
    expect(view.slayer.position.xParentPc, 1, "restoration preserves right parent anchor")
    expect(view.slayer.position.xSelfPc, 1, "restoration preserves native self anchor")

    local offscreen = scene()
    offscreen.slayer:SetPos(50, 2, 1, 0, 0, 0)
    writesBefore, warningsBefore = offscreen.slayer.posWrites, #warnings
    ClassicLayout.update(44)
    expect(offscreen.slayer.posWrites, writesBefore, "offscreen right anchor is not captured")
    expect(#warnings, warningsBefore, "offscreen transition does not warn")
    offscreen.slayer:SetPos(-245, 2, 1, 0, 0, 0)
    ClassicLayout.update(44)
    expect(offscreen.slayer.position.x, -289, "onscreen right parent anchor is captured without self anchor")
    ClassicLayout.restore()
    expect(offscreen.slayer.position.x, -245, "restoration uses newly captured native position")
    expect(offscreen.slayer.position.xSelfPc, 0, "restoration preserves newly captured self anchor")
end

local function optionalGameviewCannotBlockMandatoryReservation()
    local missing = scene({ noGameview = true })
    expect(ClassicLayout.update(44), true, "missing gameview does not block native area")
    expect(missing.area.width, 3396, "native area reserves rail without gameview")
    ClassicLayout.restore()
    assertRestored(missing, "missing gameview teardown")

    local failed = scene()
    failed.gameview.failSize = "after"
    expect(ClassicLayout.update(404), true, "gameview setter failure does not block expansion")
    expect(failed.area.width, 3036, "native area still reserves full sidebar")
    assertDescriptor(
        failed.gameview.size,
        failed.gameviewSize,
        sizeFields,
        "partially applied optional size rolls back"
    )
    ClassicLayout.restore()
    assertRestored(failed, "optional setter failure teardown")

    local shifted = scene()
    shifted.gameview.position.x = 7
    local shiftedWrites = shifted.gameview.sizeWrites
    expect(ClassicLayout.update(44), true, "gameview geometry does not block the native area")
    expect(shifted.gameview.sizeWrites, shiftedWrites, "misplaced gameview is not resized")
    ClassicLayout.restore()

    local foreign = scene()
    ClassicLayout.update(44)
    foreign.gameview.size.width = -17
    local gameviewWrites = foreign.gameview.sizeWrites
    expect(ClassicLayout.update(404), true, "foreign gameview does not block native expansion")
    expect(foreign.area.width, 3036, "mandatory reservation expands independently")
    expect(foreign.gameview.sizeWrites, gameviewWrites, "gameview client write is not fought")
    ClassicLayout.restore()
    expect(foreign.area.size.width, 0, "native reservation restored on teardown")
    expect(foreign.gameview.size.width, -17, "foreign gameview write survives teardown")
end

local function explicitGameviewOnlyClaimsActualOverlap()
    local view = scene()
    view.gameview:SetSize(3061, -12, 0, 1)
    view.gameview:SetPos(0, 12, 0, 0, 0, 0)
    local nativePosition = copy(view.gameview.position, positionFields)
    local nativeSize = copy(view.gameview.size, sizeFields)
    local writesBefore, warningsBefore = view.gameview.sizeWrites, #warnings
    expect(ClassicLayout.update(44), true, "explicit gameview fitting inside rail is valid")
    expect(view.gameview.sizeWrites, writesBefore, "fitting pixel width is never claimed or rewritten")
    expect(#warnings, warningsBefore, "fitting explicit gameview does not warn")

    view.gameview:SetSize(3000, -12, 0, 1)
    writesBefore = view.gameview.sizeWrites
    ClassicLayout.update(404)
    expect(view.gameview.sizeWrites, writesBefore, "native rewrite before inset stays client-owned")
    expect(#warnings, warningsBefore, "native rewrite before inset does not warn")

    view.gameview:SetSize(3061, -12, 0, 1)
    ClassicLayout.update(404)
    expect(view.gameview.size.width, 3036, "expansion clips only the overlap past usable right edge")
    expect(view.gameview.width, 3036, "rendered explicit gameview fits expanded rail")
    expect(view.gameview.size.height, -12, "height remains native while inset")
    expect(view.gameview.size.heightParentPc, 1, "vertical relative size remains native")
    ClassicLayout.update(600)
    expect(view.gameview.size.width, 2840, "subsequent reservation recomputes from original native width")
    ClassicLayout.update(300)
    expect(view.gameview.size.width, 3061, "smaller rail restores baseline instead of stretching past it")
    ClassicLayout.update(44)
    assertDescriptor(view.gameview.size, nativeSize, sizeFields, "no overlap restores native pixel size")
    assertDescriptor(view.gameview.position, nativePosition, positionFields, "no overlap preserves anchors")
    writesBefore = view.gameview.sizeWrites
    view.gameview:SetSize(3050, -12, 0, 1)
    ClassicLayout.update(44)
    expect(view.gameview.sizeWrites, writesBefore + 1, "native rewrite after release is not fought")
    expect(view.gameview.size.width, 3050, "latest native width survives a fitting reservation")
    expect(#warnings, warningsBefore, "normal explicit gameview sizing produces no warning")
    ClassicLayout.update(404)
    expect(view.gameview.size.width, 3036, "next overlap starts from latest unclaimed native baseline")
    ClassicLayout.restore()
    expect(view.gameview.size.width, 3050, "teardown restores the latest native explicit width")
    expect(view.gameview.size.height, -12, "teardown preserves latest native height")
end

local function insetExplicitGameviewKeepsBaselineAndProtectsConflicts()
    local view = scene()
    view.gameview:SetPos(120, 14, 0, 0, 0, 0)
    view.gameview:SetSize(3200, -14, 0, 1)
    local nativeSize = copy(view.gameview.size, sizeFields)
    ClassicLayout.update(44)
    expect(view.gameview.size.width, 3200, "inset explicit baseline already fits collapsed rail")
    ClassicLayout.update(404)
    expect(view.gameview.size.width, 2916, "inset gameview loses only 284 overlapping pixels")
    expect(view.gameview.x, 120, "resizing does not move left-pinned origin")
    ClassicLayout.update(300)
    expect(view.gameview.size.width, 3020, "smaller reservation cannot stretch past baseline")
    ClassicLayout.update(44)
    assertDescriptor(view.gameview.size, nativeSize, sizeFields, "collapse restores original native dimensions")
    ClassicLayout.update(404)
    view.gameview.size.width = 2917
    local before, sizeWrites = #warnings, view.gameview.sizeWrites
    ClassicLayout.update(404)
    expect(view.gameview.sizeWrites, sizeWrites, "foreign write after actual adjustment is protected")
    expect(#warnings, before + 1, "genuine size conflict warns once")
    ClassicLayout.restore()
    expect(view.gameview.size.width, 2917, "foreign explicit width survives teardown")

    local unsafe = scene()
    unsafe.gameview:SetSize(3061, 0, 0, 1)
    unsafe.gameview:SetPos(-44, 0, 1, 0, 1, 0)
    local nativeWrites = unsafe.gameview.sizeWrites
    ClassicLayout.update(44)
    expect(unsafe.gameview.sizeWrites, nativeWrites, "unsafe anchor is harmless while rect fits")
    local warningCount = #warnings
    ClassicLayout.update(404)
    expect(unsafe.gameview.sizeWrites, nativeWrites, "unsafe self anchor is never resized")
    expect(#warnings, warningCount + 1, "unsupported overlapping anchor warns")
    ClassicLayout.update(44)
    expect(#warnings, warningCount + 1, "fitting geometry after failure is re-evaluated silently")
    ClassicLayout.update(404)
    expect(#warnings, warningCount + 2, "overlap is re-evaluated after reservation changes again")
    ClassicLayout.restore()
end

local function unsafeNativeLayoutsDoNotClaimReservation()
    local incompatible = scene()
    incompatible.area.size.widthParentPc = 0.9
    expect(ClassicLayout.update(44), false, "non-full-size game area rejects reservation")
    expectSuspended(44, "area.size.widthParentPc", 1, 0.9)
    local warningCount = #warnings
    expect(ClassicLayout.update(44), false, "unchanged bad topology stays suspended")
    expect(#warnings, warningCount, "repeated invalid topology emits no duplicate")
    expect(incompatible.area.sizeWrites, 0, "incompatible area receives no native write")
    ClassicLayout.restore()

    local shifted = scene()
    shifted.viewport.position.x = 7
    local viewportWrites = shifted.area.sizeWrites
    expect(ClassicLayout.update(44), false, "viewport geometry rejects the native reservation")
    expectSuspended(44, "viewport.x", 0, 7)
    expect(shifted.area.sizeWrites, viewportWrites, "shifted viewport receives no native reservation")
    ClassicLayout.restore()

    local missingLayer = scene()
    components[id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP] = nil
    expect(ClassicLayout.update(44), false, "missing separate plugin layer rejects reservation")
    expectSuspended(44, "top.missing")
    warningCount = #warnings
    expect(ClassicLayout.update(44), false, "missing mount remains suspended")
    expect(#warnings, warningCount, "repeated missing mount emits no duplicate")
    expect(missingLayer.area.sizeWrites, 0, "missing mount receives no native write")
    ClassicLayout.restore()

    local failed = scene()
    failed.area.failSize = "after"
    local ok, err = pcall(ClassicLayout.update, 44)
    expect(ok, false, "mandatory setter failure propagates")
    expectSuspended(44, "area.set.size.error")
    assert(tostring(err):find("native size setter failed", 1, true), "original setter error propagates")
    assertRestored(failed, "partially applied mandatory setter rolls back")
    ClassicLayout.restore()

    local ignored = scene()
    function ignored.area.SetSize() end
    expect(ClassicLayout.update(44), false, "ignored native size setter rejects reservation")
    expectSuspended(44, "area.set.size")
    assertRestored(ignored, "ignored setter releases the native position")
    ClassicLayout.restore()

    local noInterface = scene()
    live[4202] = nil
    expect(ClassicLayout.update(44), false, "missing interface rejects reservation")
    expectSuspended(44, "interface.missing")
    expect(noInterface.area.sizeWrites, 0, "unloaded interface receives no write")
    ClassicLayout.restore()

    local unrecordable = scene()
    unrecordable.area.categoryID = nil
    expect(ClassicLayout.update(44), false, "unrecordable area rejects reservation")
    expectSuspended(44, "area.record")
    expect(unrecordable.area.sizeWrites, 0, "unrecordable area receives no write")
    ClassicLayout.restore()

    local unresolvable = scene()
    local getComponent = ui.Interfaces.GetComponent
    local areaReads = 0
    function ui.Interfaces.GetComponent(self, packed)
        if packed == id.Component.TOPLEVEL_V2__GAME_AREA then
            areaReads = areaReads + 1
            if areaReads > 1 then return nil end
        end
        return getComponent(self, packed)
    end
    expect(ClassicLayout.update(44), false, "unresolvable saved area rejects reservation")
    expectSuspended(44, "area.resolve")
    expect(unresolvable.area.sizeWrites, 0, "unresolvable area receives no write")
    ClassicLayout.restore()
    ui.Interfaces.GetComponent = getComponent
end

local function foreignDescriptorsRemainClientOwned()
    local foreignSize = scene()
    expect(ClassicLayout.update(44), true, "reserve before client overwrite")
    foreignSize.area.size.width = 0
    local sizeWrites = foreignSize.area.sizeWrites
    expect(ClassicLayout.update(44), false, "foreign overwrite suspends reservation")
    expectSuspended(44, "area.size.width", -44, 0)
    local warningCount = #warnings
    expect(ClassicLayout.update(44), false, "later update cannot reclaim foreign size")
    expect(#warnings, warningCount, "blocked ownership preserves the original cause without a duplicate")
    expect(foreignSize.area.sizeWrites, sizeWrites, "foreign size is never rewritten")
    ClassicLayout.restore()
    expect(foreignSize.area.size.width, 0, "teardown preserves foreign size")

    local foreignAnchor = scene()
    ClassicLayout.update(44)
    foreignAnchor.area.position.yParentPc = 0.25
    local positionWrites = foreignAnchor.area.posWrites
    ClassicLayout.restore()
    expect(foreignAnchor.area.posWrites, positionWrites, "teardown never writes foreign anchor")
    expect(foreignAnchor.area.position.yParentPc, 0.25, "foreign anchor survives teardown")
    expect(foreignAnchor.area.size.width, 0, "independently owned size restores")
end

local function remountNeverTouchesRetiredNativeHandles()
    local first = scene()
    ClassicLayout.update(44)
    local replacement =
        component(4202, first.area.staticID, first.viewport, pos(29, 0, 0, 0, 0, 0), size(-120, 0, 1, 1))
    poison(first.area)
    ClassicLayout.restore()
    expect(replacement.posWrites + replacement.sizeWrites, 0, "same-ID replacement is not owned")
    expect(replacement.position.x, 29, "replacement keeps its independent placement")
    scene()
    ClassicLayout.update(404)
    live[4202] = nil
    for packed, item in pairs(components) do
        if packed >> 16 == 4202 then
            components[packed] = nil
            poison(item)
        end
    end
    ClassicLayout.restore()

    local retired = scene()
    ClassicLayout.update(404)
    local nextGeneration = scene()
    poison(retired.area)
    poison(retired.gameview)
    poison(retired.slayer)
    expect(ClassicLayout.update(44), true, "same-ID remount captures fresh native targets")
    assertArea(nextGeneration, 44, "remounted game area")
    ClassicLayout.restore()
    assertRestored(nextGeneration, "remounted native generation")
end

local function viewportResizeRecapturesBaselineButRepeatedResetSuspends()
    local view = scene()
    ClassicLayout.update(44)
    for _, field in ipairs(positionFields) do
        view.area.position[field] = view.position[field]
    end
    for _, field in ipairs(sizeFields) do
        view.area.size[field] = view.dimensions[field]
        view.gameview.size[field] = view.gameviewSize[field]
    end
    view.viewport:SetSize(3000, 900, 0, 0)
    view.top:SetSize(3000, 900, 0, 0)
    expect(ClassicLayout.update(44), true, "viewport resize permits recapturing reset baseline")
    assertArea(view, 44, "resized viewport")
    for _, field in ipairs(positionFields) do
        view.area.position[field] = view.position[field]
    end
    for _, field in ipairs(sizeFields) do
        view.area.size[field] = view.dimensions[field]
    end
    local positionWrites, sizeWrites = writes(view.area)
    expect(ClassicLayout.update(44), false, "unconfirmed native reset suspends reservation")
    expect(view.area.posWrites, positionWrites, "reset anchor is not overwritten")
    expect(view.area.sizeWrites, sizeWrites, "reset native width is not overwritten")
    ClassicLayout.restore()
    assertRestored(view, "reset baseline remains client-owned")
end

local function combatScene()
    local view = scene()
    view.viewport:SetSize(1920, 1080, 0, 0)
    view.top:SetSize(1920, 1080, 0, 0)
    view.chat = component(4202, 110, view.area, pos(0, 0, 0, 1, 0, 1), size(550, 188, 0, 0))
    view.strip = component(4202, 111, view.area, pos(0, 0, 1, 1, 1, 1), size(544, 34, 0, 0))
    view.chat.visibleGlobal, view.strip.visibleGlobal = true, true
    id.Component.TOPLEVEL_V2__CHAT_WINDOW = (4202 << 16) | 110
    id.Component.TOPLEVEL_V2__BUTTONS_WINDOW = (4202 << 16) | 111
    view.privateChat = component(4202, 118, view.hud, pos(0, -188, 0, 1, 0, 1), size(550, 275, 0, 0))
    view.privateChat.visibleGlobal = false
    view.privatePosition = copy(view.privateChat.position, positionFields)
    id.Component.TOPLEVEL_V2__SPLITPM_WINDOW = (4202 << 16) | 118
    view.actions, view.actionPositions = {}, {}
    for index = 1, 5 do
        local suffix = index == 1 and "" or "_" .. index
        local offset = index == 1 and -76 or index == 2 and -38 or 0
        local action = component(
            4202,
            111 + index,
            view.area,
            pos(0, offset, 0.5, 1, 0.5, 1),
            size(550, index == 1 and 76 or 38, 0, 0)
        )
        action.visibleGlobal = index <= 3
        view.actions[index] = action
        view.actionPositions[index] = copy(action.position, positionFields)
        id.Component["TOPLEVEL_V2__ACTION_WINDOW" .. suffix] = (4202 << 16) | (111 + index)
    end
    return view
end

local function combatStacksAndRestoresWithoutOscillating()
    local view = combatScene()
    expect(ClassicLayout.update(404), true, "chat collision uses compact layout")
    local main, second, third = table.unpack(view.actions)
    expect(main.x, view.chat.x, "combat cluster aligns with chat")
    expect(second.y, main.y + main.height, "second bar retains its row")
    expect(third.y, second.y + second.height, "third bar retains its row")
    expect(third.y + third.height, view.chat.y, "cluster joins chat without a gap")
    local written = main.posWrites
    expect(ClassicLayout.update(404), true, "compact layout remains stable")
    expect(main.posWrites, written, "idle compact layout does not rewrite bars")
    expect(ClassicLayout.update(44), true, "collapse has enough horizontal space")
    for index, action in ipairs(view.actions) do
        assertDescriptor(action.position, view.actionPositions[index], positionFields, "restored bar")
    end
    expect(ClassicLayout.update(404), true, "reopening stacks again")
    view.actions[4]:SetPos(0, -152, 0.5, 1, 0.5, 1)
    view.actions[5]:SetPos(0, -190, 0.5, 1, 0.5, 1)
    view.actionPositions[4] = copy(view.actions[4].position, positionFields)
    view.actionPositions[5] = copy(view.actions[5].position, positionFields)
    view.actions[4].visibleGlobal, view.actions[5].visibleGlobal = true, true
    expect(ClassicLayout.update(404), true, "all five visible bars join the compact cluster")
    expect(view.actions[4].y + view.actions[4].height, main.y, "fourth bar keeps its relative row")
    expect(view.actions[5].y + view.actions[5].height, view.actions[4].y, "fifth bar keeps its row")
    classicValue = 0
    expect(ClassicLayout.update(404), false, "mode exit restores compact bars")
    classicValue = 1
    for index, action in ipairs(view.actions) do
        assertDescriptor(action.position, view.actionPositions[index], positionFields, "mode exit bar")
    end
    ClassicLayout.restore()
end

local function additionalButtonTriggersCompactLayout()
    local view = combatScene()
    expect(ClassicLayout.update(262), true, "current strip fits the horizontal lane")
    expect(view.actions[1].posWrites, 0, "clear bars remain native")
    view.strip:SetSize(576, 34, 0, 0)
    expect(ClassicLayout.update(262), true, "one more native button triggers stacking")
    expect(view.actions[1].x, view.chat.x, "button collision moves whole cluster")
    expect(view.actions[3].y + view.actions[3].height, view.chat.y, "stack joins chat")
    view.actions[3].visibleGlobal = false
    expect(ClassicLayout.update(262), true, "hiding the bottom bar frees the horizontal lane")
    assertDescriptor(
        view.actions[2].position,
        view.actionPositions[2],
        positionFields,
        "remaining bars return to native placement when clear"
    )
    assertDescriptor(view.actions[3].position, view.actionPositions[3], positionFields, "hidden bar restored")
    view.actions[3].visibleGlobal = true
    expect(ClassicLayout.update(262), true, "showing the colliding bar stacks the cluster again")
    expect(view.actions[3].y + view.actions[3].height, view.chat.y, "reshown bar joins chat")
    view.strip:SetSize(544, 34, 0, 0)
    expect(ClassicLayout.update(262), true, "native strip contraction restores horizontal layout")
    assertDescriptor(view.actions[1].position, view.actionPositions[1], positionFields, "strip contraction")
    ClassicLayout.restore()
end

local function combatWaitsForClassicAnchors()
    local view = combatScene()
    view.strip:SetSize(1000, 34, 0, 0)
    local primary = view.actions[1]
    primary:SetPos(0, 896, 0, 0, 0, 0)
    local initialWrites, messages = primary.posWrites, #warnings
    expect(ClassicLayout.update(44), true, "rail mounts while combat anchors switch")
    expect(view.area.width, 1876, "the rail keeps its reservation during the switch")
    expect(primary.posWrites, initialWrites, "outgoing primary position remains native")
    expect(view.actions[2].posWrites, 0, "mixed anchors do not split the cluster")
    primary:SetPos(0, -76, 0.5, 1, 0.5, 1)
    expect(ClassicLayout.update(44), true, "settled bars can compact without losing the rail")
    expect(primary.x, view.chat.x, "settled combat cluster aligns with chat")
    expect(view.actions[3].y + view.actions[3].height, view.chat.y, "cluster clears chat")
    expect(#warnings, messages, "native anchor transition produces no warning")
    ClassicLayout.restore()
    assertDescriptor(primary.position, view.actionPositions[1], positionFields, "restore uses the Classic baseline")
end

local function disappearingActionDuringRailReservation()
    local view = combatScene()
    view.strip:SetSize(1000, 34, 0, 0)
    expect(ClassicLayout.update(44), true, "collapsed rail initially fits with compact combat bars")
    components[id.Component.TOPLEVEL_V2__ACTION_WINDOW] = nil
    expect(ClassicLayout.update(44), false, "missing compacted action bar suspends the rail")
    expectSuspended(44, "combat.action.component_unavailable")
    local count = #warnings
    ClassicLayout.update(44)
    expect(#warnings, count, "missing action bar stays quiet on repeated ticks")
    ClassicLayout.restore()
end

disappearingActionDuringRailReservation()

local function combatOwnershipAndFailuresAreSafe()
    local view = combatScene()
    ClassicLayout.update(404)
    local expectedX = view.actions[1].position.x
    view.actions[1]:SetPos(12, 16, 0, 0, 0, 0)
    local writesBefore = view.actions[1].posWrites
    expect(ClassicLayout.update(404), false, "native position changes suspend reservation")
    expectSuspended(404, "combat.action.ownership.position.x", expectedX, 12)
    expect(view.actions[1].posWrites, writesBefore, "native position is never fought")
    expect(view.area.width, 1920, "unsafe combat layout releases sidebar reservation")
    ClassicLayout.restore()
    expect(view.actions[1].position.x, 12, "teardown preserves native position")

    view = combatScene()
    view.actions[2].failPos = "after"
    local ok = pcall(ClassicLayout.update, 404)
    expect(ok, false, "combat setter error propagates")
    expectSuspended(404, "combat.error")
    for index, action in ipairs(view.actions) do
        assertDescriptor(action.position, view.actionPositions[index], positionFields, "partial rollback")
    end
    expect(view.area.width, 1920, "partial failure releases reservation")
    ClassicLayout.restore()

    view = combatScene()
    view.chat:SetPos(-10, 0, 0, 1, 0, 1)
    expect(ClassicLayout.update(404), false, "invalid combat chat placement rejects stacking")
    expectSuspended(404, "combat.chat.x")
    expect(view.area.width, 1920, "combat guard rejection rolls back reservation")
    ClassicLayout.restore()

    view = combatScene()
    -- A native compact baseline must not be shifted a second time.
    for index, action in ipairs(view.actions) do
        local original = view.actionPositions[index]
        action:SetPos(0, original.y - 192, 0, 1, 0, 1)
        action.posWrites = 0
    end
    expect(ClassicLayout.update(404), true, "native compact baseline is already safe")
    expect(view.actions[1].posWrites, 0, "native compact placement is left alone")
    ClassicLayout.restore()

    local retired = combatScene()
    ClassicLayout.update(404)
    local fresh = combatScene()
    for _, action in ipairs(retired.actions) do
        poison(action)
    end
    expect(ClassicLayout.update(404), true, "remount resolves fresh combat handles")
    expect(fresh.actions[1].x, fresh.chat.x, "remounted combat bars stack")
    ClassicLayout.restore()
end

local function privateChatFollowsCompactClusterAndRestores()
    local view = combatScene()
    view.privateChat.visibleGlobal = true
    expect(ClassicLayout.update(404), true, "compact cluster makes room for private chat")
    local main, _, third = table.unpack(view.actions)
    expect(third.y + third.height, view.chat.y, "chat and combat frames meet exactly")
    expect(view.privateChat.y + view.privateChat.height, main.y, "private chat clears the whole cluster")
    local pmWrites = view.privateChat.posWrites
    ClassicLayout.update(404)
    expect(view.privateChat.posWrites, pmWrites, "private chat does not drift on idle updates")
    view.chat:SetSize(550, 230, 0, 0)
    expect(ClassicLayout.update(404), true, "chat resize repositions combat and private chat")
    expect(third.y + third.height, view.chat.y, "resized chat still joins combat")
    expect(view.privateChat.y + view.privateChat.height, main.y, "PMs clear resized chat and combat")
    view.privateChat.visibleGlobal = false
    expect(ClassicLayout.update(404), true, "hidden private chat releases its offset")
    assertDescriptor(view.privateChat.position, view.privatePosition, positionFields, "hidden PM position")
    view.privateChat.visibleGlobal = true
    expect(ClassicLayout.update(404), true, "reappearing PMs clear combat")
    expect(view.privateChat.y + view.privateChat.height, main.y, "reappearing PMs stay above combat")
    expect(ClassicLayout.update(44), true, "sidebar collapse restores private chat")
    assertDescriptor(view.privateChat.position, view.privatePosition, positionFields, "collapsed PM position")
    ClassicLayout.update(404)
    ClassicLayout.restore()
    assertDescriptor(view.privateChat.position, view.privatePosition, positionFields, "shutdown PM position")

    view = combatScene()
    view.privateChat.visibleGlobal = true
    view.privateChat:SetPos(800, -188, 0, 1, 0, 1)
    expect(ClassicLayout.update(404), true, "floating PMs outside combat are left alone")
    expect(view.privateChat.position.x, 800, "floating PM horizontal placement survives")
    expect(view.privateChat.position.y, -188, "floating PM vertical placement survives")
    ClassicLayout.restore()

    view = combatScene()
    view.privateChat.visibleGlobal = true
    ClassicLayout.update(404)
    view.privateChat:SetPos(10, 20, 0, 0, 0, 0)
    local writesBefore = view.privateChat.posWrites
    expect(ClassicLayout.update(404), false, "native PM changes suspend compact ownership")
    expect(view.privateChat.posWrites, writesBefore, "native PM changes are not overwritten")
    ClassicLayout.restore()
    expect(view.privateChat.position.y, 20, "shutdown preserves native PM changes")
end

reservationFollowsRailAndRestoresOriginalLayout()
modeExitRestoresNativeOwnership()
slayerPositionIsOptionalAndNeverShiftedTwice()
slayerTransitionWaitsForNativeRightAnchor()
optionalGameviewCannotBlockMandatoryReservation()
explicitGameviewOnlyClaimsActualOverlap()
insetExplicitGameviewKeepsBaselineAndProtectsConflicts()
unsafeNativeLayoutsDoNotClaimReservation()
foreignDescriptorsRemainClientOwned()
remountNeverTouchesRetiredNativeHandles()
viewportResizeRecapturesBaselineButRepeatedResetSuspends()
combatStacksAndRestoresWithoutOscillating()
combatWaitsForClassicAnchors()
additionalButtonTriggersCompactLayout()
combatOwnershipAndFailuresAreSafe()
privateChatFollowsCompactClusterAndRestores()
print("classic_layout_test: native reservation and lifecycle passed")
