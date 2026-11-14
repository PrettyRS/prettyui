-- Reserve space in the classic native UI's containing GAME_AREA. The Slayer
-- counter lives outside it, so move its containing HUD window as one unit.
-- No native handles or mutable descriptors are used as saved geometry.
local NativeInterfaceSettings = require("src/core/native_interface_settings")

local ClassicLayout = {}
local positions = { "x", "y", "xParentPc", "yParentPc", "xSelfPc", "ySelfPc" }
local sizes = { "width", "height", "widthParentPc", "heightParentPc" }
local names = {
    top = "TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP",
    viewport = "TOPLEVEL_V2__VIEWPORT",
    area = "TOPLEVEL_V2__GAME_AREA",
    gameview = "TOPLEVEL_V2__GAMEVIEW_WINDOW",
    hud = "TOPLEVEL_V2__GAMEPLAY_HUDS",
    slayer = "TOPLEVEL_V2__SLAYER_COUNTER_WINDOW",
}
local SUSPENDED = "PrettyUI: classic sidebar suspended; native layout is unavailable"
local NO_GAMEVIEW = "PrettyUI: classic sidebar cannot resize the gameview"
local NO_SLAYER = "PrettyUI: classic sidebar cannot move the Slayer counter"
local state, suspendedEnvironment, optionalEnvironment

local function warn(message)
    if type(log) == "function" then
        -- Native log resolves plugin ownership from its Lua caller's _ENV.
        pcall(function() log(message) end)
    end
end

local function component(name)
    local packed = id.Component[names[name]]
    return packed and ui.Interfaces:GetComponent(packed) or nil
end
local function child(parent, name)
    local packed = id.Component[names[name]]
    return parent and type(packed) == "number" and parent:GetChild(packed & 0xffff) or nil
end


local function identity(value)
    if not value then return nil end
    local ok, a, b, c, d = pcall(function()
        return value.interfaceID, value.staticID, value.categoryID, value.dynamicID
    end)
    if not ok or type(a) ~= "number" or type(b) ~= "number"
        or type(c) ~= "number" or type(d) ~= "number" then return nil end
    return a .. ":" .. b .. ":" .. c .. ":" .. d, a, b
end

local function layout(value)
    local ok, result = pcall(function()
        local pos, size, scalars = value.position, value.size, {}
        for i, field in ipairs(positions) do
            scalars[i] = pos[field]
            if type(scalars[i]) ~= "number" then return nil end
        end
        for i, field in ipairs(sizes) do
            scalars[i + 6] = size[field]
            if type(scalars[i + 6]) ~= "number" then return nil end
        end
        return scalars
    end)
    if ok then return result end
end

local function same(a, b, first, last)
    for i = first, last do if a[i] ~= b[i] then return false end end
    return true
end

local function fullSize(saved)
    return saved[7] == 0 and saved[8] == 0 and saved[9] == 1 and saved[10] == 1
end

local function origin(value)
    local ok, x, y, width, height = pcall(function()
        return value.x, value.y, value.width, value.height
    end)
    if ok and type(x) == "number" and type(y) == "number"
        and type(width) == "number" and type(height) == "number" then
        return x, y, width, height
    end
end

local function record(value, parentKey, baseline)
    local key, interfaceID, staticID = identity(value)
    if not key or not baseline then return nil end
    local ok, parent = pcall(function() return value.parent end)
    if not ok or identity(parent) ~= parentKey then return nil end
    return { key = key, interfaceID = interfaceID, packed = (interfaceID << 16) | staticID,
        parentKey = parentKey, original = baseline, written = { table.unpack(baseline) } }
end

-- Always resolve through a loaded interface before touching a saved component.
-- An interface object change is a remount, even when all numeric IDs are reused.
local function resolve(saved, interfaceObject)
    if not saved then return nil end
    local ok, loaded = pcall(function()
        return ui.Interfaces:GetInterface(saved.interfaceID)
    end)
    if not ok or not loaded or loaded ~= interfaceObject then return nil end
    local found, fresh = pcall(function() return ui.Interfaces:GetComponent(saved.packed) end)
    if not found or identity(fresh) ~= saved.key then return nil end
    local parentOK, parent = pcall(function() return fresh.parent end)
    if not parentOK or identity(parent) ~= saved.parentKey then return nil end
    return fresh
end

-- A descriptor is owned only while every scalar still matches our last write.
-- Never rewrite a foreign anchor by merging it with a partial old descriptor.
local function restoreRecord(saved, interfaceObject)
    local fresh = resolve(saved, interfaceObject)
    if not fresh then return true end
    local current = layout(fresh)
    if not current then return false end
    local desired = { table.unpack(current) }
    local changedPos = same(current, saved.written, 1, 6)
        and not same(current, saved.original, 1, 6)
    local changedSize = same(current, saved.written, 7, 10)
        and not same(current, saved.original, 7, 10)
    if changedPos then
        for i = 1, 6 do desired[i] = saved.original[i] end
    end
    if changedSize then
        for i = 7, 10 do desired[i] = saved.original[i] end
    end
    if changedPos then
        pcall(function() fresh:SetPos(table.unpack(desired, 1, 6)) end)
    end
    if changedSize then
        pcall(function() fresh:SetSize(table.unpack(desired, 7, 10)) end)
    end
    -- A setter may apply its change and then throw. Check what remains owned.
    current = layout(fresh)
    if not current then return false end
    if same(current, saved.written, 1, 6) and not same(current, saved.original, 1, 6)
        or same(current, saved.written, 7, 10) and not same(current, saved.original, 7, 10) then
        return false
    end
    return true
end

local function restoreState()
    if not state then return true end
    local saved = state
    local viewCall, gameviewOK = pcall(restoreRecord, saved.gameview, saved.interfaceObject)
    local areaCall, areaOK = pcall(restoreRecord, saved.area, saved.interfaceObject)
    local slayerCall, slayerOK = pcall(restoreRecord, saved.slayer, saved.interfaceObject)
    local complete = viewCall and gameviewOK and areaCall and areaOK and slayerCall and slayerOK
    if complete then state = nil end
    return complete
end

function ClassicLayout.restore()
    local result = restoreState()
    suspendedEnvironment, optionalEnvironment = nil, nil
    return result
end

local function set(saved, fresh, desired, which)
    local current = layout(fresh)
    if not current or not same(current, saved.written, 1, 10) then return false end
    local first, last = which == "position" and 1 or 7, which == "position" and 6 or 10
    if same(current, desired, first, last) then return true end
    -- Mark the intended descriptor before invoking the setter: setters can
    -- mutate their target before raising, and the rollback must still own it.
    for i = first, last do saved.written[i] = desired[i] end
    if which == "position" then fresh:SetPos(table.unpack(desired, 1, 6))
    else fresh:SetSize(table.unpack(desired, 7, 10)) end
    return same(layout(fresh) or {}, desired, first, last)
end

local function environment(loaded, viewport, top, area)
    local x, y, w, h = origin(viewport)
    local tx, ty, tw, th = origin(top)
    local areaLayout = layout(area)
    local topKey, viewportKey, areaKey = identity(top), identity(viewport), identity(area)
    -- Scalar baseline is included for failed compatibility checks, so an
    -- actually changed native environment can become eligible without a tick fight.
    local signature = table.concat({ tostring(loaded), tostring(topKey), tostring(viewportKey),
        tostring(areaKey), tostring(x), tostring(y), tostring(w), tostring(h),
        tostring(tx), tostring(ty), tostring(tw), tostring(th) }, "/")
    return signature .. "/" .. (areaLayout and table.concat(areaLayout, ":") or "?"),
        signature, x, y, w, h, tx, ty, tw, th, areaLayout, viewportKey
end

local function suspend(signature)
    if suspendedEnvironment ~= signature then warn(SUSPENDED) end
    suspendedEnvironment = signature
    return false
end

local function optionalWarning(signature)
    if optionalEnvironment ~= signature then warn(NO_GAMEVIEW) end
    optionalEnvironment = signature
end

local function compatible(top, viewport, area, areaLayout, x, y, w, h, tx, ty, tw, th,
        viewportKey, reserved)
    if not (top and viewport and area and not area.isRestricted and areaLayout and viewportKey
        and x == 0 and y == 0 and w > 0 and h > 0
        and tx == 0 and ty == 0 and tw == w and th == h
        and fullSize(areaLayout)
        and same(areaLayout, { 0, 0, 0.5, 0.5, 0.5, 0.5 }, 1, 6)) then return false end
    local ok, topParent, viewportParent, areaParent = pcall(function()
        return top.parent, viewport.parent, area.parent
    end)
    if not ok or topParent ~= nil or viewportParent ~= nil
        or identity(areaParent) ~= viewportKey then return false end
    local ax, ay, aw, ah = origin(area)
    return ax == 0 and ay == 0 and aw == w - (reserved or 0) and ah == h
end

local function updateGameview(current, width, environmentKey, viewportKey)
    local saved = current.gameview
    if current.gameviewBlocked then return end
    if saved then
        local fresh = resolve(saved, current.interfaceObject)
        if not fresh or not same(layout(fresh) or {}, saved.written, 1, 10) then
            if restoreRecord(saved, current.interfaceObject) then current.gameview = nil end
            current.gameviewBlocked = true
            optionalWarning(environmentKey)
            return
        end
        if saved.written[7] == saved.original[7] - width then return end
        local desired = { table.unpack(saved.original) }
        desired[7] = desired[7] - width
        local ok, applied = pcall(set, saved, fresh, desired, "size")
        if ok and applied then return end
        if restoreRecord(saved, current.interfaceObject) then current.gameview = nil end
        current.gameviewBlocked = true
        optionalWarning(environmentKey)
        return
    end
    local view = component("gameview")
    local key = identity(view)
    local baseline = layout(view)
    local vx, vy, vw, vh = origin(view)
    local signature = environmentKey .. "/" .. tostring(key) .. "/"
        .. (baseline and table.concat(baseline, ":") or "?") .. "/"
        .. tostring(vx) .. ":" .. tostring(vy) .. ":" .. tostring(vw) .. ":" .. tostring(vh)
    if current.optionalFailed == signature then return end
    local parentOK, parent = pcall(function() return view and view.parent end)
    if not view or view.isRestricted or not baseline or not fullSize(baseline) or not parentOK
        or identity(parent) ~= viewportKey or vx ~= 0 or vy ~= 0
        or vw ~= current.width or vh ~= current.height then
        current.optionalFailed = signature
        optionalWarning(environmentKey)
        return
    end
    saved = record(view, viewportKey, baseline)
    if not saved then
        current.optionalFailed = signature
        optionalWarning(environmentKey)
        return
    end
    local desired = { table.unpack(baseline) }
    desired[7] = -width
    current.gameview = saved
    local ok, applied = pcall(set, saved, view, desired, "size")
    if not ok or not applied then
        if restoreRecord(saved, current.interfaceObject) then current.gameview = nil end
        current.optionalFailed = signature
        optionalWarning(environmentKey)
    else
        current.optionalFailed = nil
        optionalEnvironment = nil
    end
end

local function updateSlayer(current, width)
    if current.slayerBlocked then return end
    local saved = current.slayer
    if not saved then
        local hud = component("hud")
        local target = child(hud, "slayer")
        if not target or target.isRestricted or not hud
            or identity(hud.parent) ~= current.viewportKey
            or identity(target.parent) ~= identity(hud) then return end
        local hx, hy, hw, hh = origin(hud)
        local hudLayout = layout(hud)
        if not hudLayout or not fullSize(hudLayout) or hx ~= 0 or hy ~= 0
            or hw ~= current.width or hh ~= current.height then return end
        saved = record(target, identity(hud), layout(target))
        if not saved then return end
        current.slayer = saved
    end
    local fresh = resolve(saved, current.interfaceObject)
    -- Even an unchanged reservation must still yield to a foreign descriptor.
    if fresh and saved.written[1] == saved.original[1] - width
        and same(layout(fresh) or {}, saved.written, 1, 10) then return end
    local desired = { table.unpack(saved.original) }
    desired[1] = desired[1] - width
    local ok, applied = pcall(set, saved, fresh, desired, "position")
    if ok and applied then return end
    if restoreRecord(saved, current.interfaceObject) then current.slayer = nil end
    current.slayerBlocked = true
    warn(NO_SLAYER)
end

function ClassicLayout.update(reservedWidth)
    if not NativeInterfaceSettings.isClassicUI() then
        ClassicLayout.restore()
        return false
    end
    assert(type(reservedWidth) == "number" and reservedWidth >= 0
        and reservedWidth % 1 == 0, "classic reserved width must be a nonnegative integer")

    local top, viewport, area = component("top"), component("viewport"), component("area")
    local interfaceID = (id.Component[names.viewport] or 0) >> 16
    local loaded = ui.Interfaces:GetInterface(interfaceID)
    local signature, generation, x, y, w, h, tx, ty, tw, th, areaLayout, viewportKey =
        environment(loaded, viewport, top, area)
    local previous = state
    if previous and (not loaded or loaded ~= previous.interfaceObject
        or previous.width ~= w or previous.height ~= h or previous.viewportKey ~= viewportKey) then
        if not restoreState() then return suspend(signature) end
        previous = nil
        signature, generation, x, y, w, h, tx, ty, tw, th, areaLayout, viewportKey =
            environment(loaded, viewport, top, area)
    end
    if previous and previous.blocked then return suspend(previous.blockedEnvironment) end
    local fresh = previous and resolve(previous.area, loaded)
    if fresh and not same(layout(fresh) or {}, previous.area.written, 1, 10) then
        restoreState()
        previous.blocked, previous.blockedEnvironment = true, signature
        state = previous
        return suspend(signature)
    end
    if not compatible(top, viewport, area, previous and previous.area.original or areaLayout,
        x, y, w, h, tx, ty, tw, th, viewportKey,
        previous and previous.reservedWidth) then
        if previous then
            if not restoreState() then
                previous.blocked, previous.blockedEnvironment = true, signature
                state = previous
            else
                signature = environment(loaded, viewport, top, area)
            end
        end
        return suspend(signature)
    end
    if not previous then
        local saved = record(area, viewportKey, areaLayout)
        if not loaded or not saved then return suspend(signature) end
        previous = { interfaceObject = loaded, viewportKey = viewportKey,
            width = w, height = h, area = saved }
        state = previous
        fresh = resolve(saved, loaded)
    end
    if not fresh then
        restoreState()
        return suspend(signature)
    end
    -- Ownership and topology were checked above; unchanged widths need no
    -- desired descriptor or repeated setter-side layout reads.
    if previous.reservedWidth ~= reservedWidth then
        local desired = { 0, 0, 0, 0, 0, 0, -reservedWidth, 0, 1, 1 }
        local ok, applied = pcall(function()
            return set(previous.area, fresh, desired, "position")
                and set(previous.area, fresh, desired, "size")
        end)
        if not ok or not applied then
            restoreState()
            previous.blocked, previous.blockedEnvironment = true, signature
            state = previous
            suspend(signature)
            if not ok then error(applied, 0) end
            return false
        end
    end
    previous.reservedWidth = reservedWidth
    suspendedEnvironment = nil
    local optionalOK = pcall(updateGameview, previous, reservedWidth, generation, viewportKey)
    if not optionalOK then
        previous.gameviewBlocked = true
        optionalWarning(generation)
    end
    local slayerOK = pcall(updateSlayer, previous, reservedWidth)
    if not slayerOK then
        previous.slayerBlocked = true
        warn(NO_SLAYER)
    end
    return true
end

return ClassicLayout
