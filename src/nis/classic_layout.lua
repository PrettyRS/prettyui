-- Reserves Classic sidebar space and keeps the native combat bars clear of
-- chat and buttons. Saves scalar layouts for restoration across UI rebuilds.
local NativeInterfaceSettings = require("src/core/native_interface_settings")

local ClassicLayout = {}
local positions = { "x", "y", "xParentPc", "yParentPc", "xSelfPc", "ySelfPc" }
local sizes = { "width", "height", "widthParentPc", "heightParentPc" }
local centeredArea = { 0, 0, 0.5, 0.5, 0.5, 0.5, 0, 0, 1, 1 }
local names = {
    top = "TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP",
    viewport = "TOPLEVEL_V2__VIEWPORT",
    area = "TOPLEVEL_V2__GAME_AREA",
    gameview = "TOPLEVEL_V2__GAMEVIEW_WINDOW",
    hud = "TOPLEVEL_V2__GAMEPLAY_HUDS",
    slayer = "TOPLEVEL_V2__SLAYER_COUNTER_WINDOW",
    chat = "TOPLEVEL_V2__CHAT_WINDOW",
    privateChat = "TOPLEVEL_V2__SPLITPM_WINDOW",
    buttons = "TOPLEVEL_V2__BUTTONS_WINDOW",
    action = "TOPLEVEL_V2__ACTION_WINDOW",
    action2 = "TOPLEVEL_V2__ACTION_WINDOW_2",
    action3 = "TOPLEVEL_V2__ACTION_WINDOW_3",
    action4 = "TOPLEVEL_V2__ACTION_WINDOW_4",
    action5 = "TOPLEVEL_V2__ACTION_WINDOW_5",
}
local actionNames = { "action", "action2", "action3", "action4", "action5" }
local HUD_GAP = 4
local SUSPENDED = "PrettyUI: classic sidebar suspended; native layout is unavailable"
local NO_GAMEVIEW = "PrettyUI: classic sidebar cannot resize the gameview"
local NO_SLAYER = "PrettyUI: classic sidebar cannot move the Slayer counter"
local state, suspendedEnvironment, suspendedReason, optionalEnvironment

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

local function identityValues(value)
    return value.interfaceID, value.staticID, value.categoryID, value.dynamicID
end

local function identity(value)
    if not value then return nil end
    local ok, a, b, c, d = pcall(identityValues, value)
    if not ok or type(a) ~= "number" or type(b) ~= "number" or type(c) ~= "number" or type(d) ~= "number" then
        return nil
    end
    return a .. ":" .. b .. ":" .. c .. ":" .. d, a, b
end

local function readLayout(value, expected)
    local pos, size = value.position, value.size
    local scalars = expected or {}
    for i, field in ipairs(positions) do
        local scalar = pos[field]
        if type(scalar) ~= "number" or expected and scalar ~= expected[i] then
            return nil, "position." .. field, expected and expected[i], scalar
        end
        if not expected then scalars[i] = scalar end
    end
    for i, field in ipairs(sizes) do
        local scalar = size[field]
        if type(scalar) ~= "number" or expected and scalar ~= expected[i + 6] then
            return nil, "size." .. field, expected and expected[i + 6], scalar
        end
        if not expected then scalars[i + 6] = scalar end
    end
    return scalars
end

-- Ownership checks compare live scalars without allocating a snapshot.
local function layout(value, expected)
    local ok, result = pcall(readLayout, value, expected)
    if ok then return result end
end

local function same(a, b, first, last)
    for i = first, last do
        if a[i] ~= b[i] then return false end
    end
    return true
end

local function fullSize(saved)
    return saved[7] == 0 and saved[8] == 0 and saved[9] == 1 and saved[10] == 1
end

local function explicitWidth(saved)
    return saved[9] == 0 and saved[7] > 0
end

local function gameviewWidth(saved, current, width)
    if fullSize(saved.original) then return -width end
    return math.min(saved.original[7], current.width - width - saved.originX)
end

local function originValues(value)
    return value.x, value.y, value.width, value.height
end

local function origin(value)
    local ok, x, y, width, height = pcall(originValues, value)
    if ok and type(x) == "number" and type(y) == "number" and type(width) == "number" and type(height) == "number" then
        return x, y, width, height
    end
end

local function parentOf(value)
    return value.parent
end

local function record(value, parentKey, baseline)
    local key, interfaceID, staticID = identity(value)
    if not key or not baseline then return nil end
    local ok, parent = pcall(parentOf, value)
    if not ok or identity(parent) ~= parentKey then return nil end
    return {
        key = key,
        interfaceID = interfaceID,
        packed = (interfaceID << 16) | staticID,
        parentKey = parentKey,
        original = baseline,
        written = { table.unpack(baseline) },
    }
end

-- Always resolve through a loaded interface before touching a saved component.
-- An interface object change is a remount, even when all numeric IDs are reused.
local function resolve(saved, interfaceObject)
    if not saved then return nil end
    local ok, loaded = pcall(function()
        return ui.Interfaces:GetInterface(saved.interfaceID)
    end)
    if not ok or not loaded or loaded ~= interfaceObject then return nil, "interface_changed" end
    local found, fresh = pcall(function() return ui.Interfaces:GetComponent(saved.packed) end)
    if not found or not fresh then return nil, "component_unavailable" end
    if identity(fresh) ~= saved.key then return nil, "identity_changed" end
    local parentOK, parent = pcall(parentOf, fresh)
    if not parentOK or identity(parent) ~= saved.parentKey then return nil, "parent_changed" end
    return fresh
end

-- A descriptor is owned only while every scalar still matches our last write.
-- Never rewrite a foreign anchor by merging it with a partial old descriptor.
local function restoreRecord(saved, interfaceObject)
    local fresh = resolve(saved, interfaceObject)
    if not fresh then return true end
    local current = layout(fresh)
    if not current then return false end
    local changedPos = same(current, saved.written, 1, 6) and not same(current, saved.original, 1, 6)
    local changedSize = same(current, saved.written, 7, 10) and not same(current, saved.original, 7, 10)
    if changedPos then
        pcall(function() fresh:SetPos(table.unpack(saved.original, 1, 6)) end)
    end
    if changedSize then
        pcall(function() fresh:SetSize(table.unpack(saved.original, 7, 10)) end)
    end
    -- A setter may apply its change and then throw. Check what remains owned.
    current = layout(fresh)
    if not current then return false end
    if
        same(current, saved.written, 1, 6) and not same(current, saved.original, 1, 6)
        or same(current, saved.written, 7, 10) and not same(current, saved.original, 7, 10)
    then
        return false
    end
    return true
end

local function restoreState()
    if not state then return true end
    local saved = state
    local actionsOK = true
    for _, action in pairs(saved.actions or {}) do
        local called, restored = pcall(restoreRecord, action, saved.interfaceObject)
        actionsOK = called and restored and actionsOK
    end
    local viewCall, gameviewOK = pcall(restoreRecord, saved.gameview, saved.interfaceObject)
    local areaCall, areaOK = pcall(restoreRecord, saved.area, saved.interfaceObject)
    local slayerCall, slayerOK = pcall(restoreRecord, saved.slayer, saved.interfaceObject)
    local privateCall, privateOK = pcall(restoreRecord, saved.privateChat, saved.interfaceObject)
    local complete = actionsOK
        and viewCall
        and gameviewOK
        and areaCall
        and areaOK
        and slayerCall
        and slayerOK
        and privateCall
        and privateOK
    if complete then state = nil end
    return complete
end

function ClassicLayout.restore()
    local result = restoreState()
    suspendedEnvironment, suspendedReason, optionalEnvironment = nil, nil, nil
    return result
end

local function set(saved, fresh, desired, which)
    local current = layout(fresh, saved.written)
    if not current then return false end
    local first, last = which == "position" and 1 or 7, which == "position" and 6 or 10
    if same(current, desired, first, last) then return true end
    -- Mark the intended descriptor before invoking the setter: setters can
    -- mutate their target before raising, and the rollback must still own it.
    for i = first, last do
        saved.written[i] = desired[i]
    end
    if which == "position" then
        fresh:SetPos(table.unpack(desired, 1, 6))
    else
        fresh:SetSize(table.unpack(desired, 7, 10))
    end
    return same(layout(fresh) or {}, desired, first, last)
end

local function environment(loaded, viewport, top, area)
    local x, y, w, h = origin(viewport)
    local tx, ty, tw, th = origin(top)
    local areaLayout = layout(area)
    local topKey, viewportKey, areaKey = identity(top), identity(viewport), identity(area)
    -- Include the area layout so a changed baseline can retry a suspended reservation.
    local signature = table.concat({
        tostring(loaded),
        tostring(topKey),
        tostring(viewportKey),
        tostring(areaKey),
        tostring(x),
        tostring(y),
        tostring(w),
        tostring(h),
        tostring(tx),
        tostring(ty),
        tostring(tw),
        tostring(th),
    }, "/")
    return signature .. "/" .. (areaLayout and table.concat(areaLayout, ":") or "?"),
        signature,
        x,
        y,
        w,
        h,
        tx,
        ty,
        tw,
        th,
        areaLayout,
        viewportKey
end

local function logValue(value)
    if type(value) == "string" then return (value:sub(1, 200):gsub("%c", " ")) end
    if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
    return type(value)
end

local function suspend(signature, width, reason, expected, actual)
    if suspendedEnvironment ~= signature or suspendedReason ~= reason then
        local detail = ""
        if expected ~= nil or actual ~= nil then
            detail = " expected=" .. logValue(expected) .. " actual=" .. logValue(actual)
        end
        warn(SUSPENDED .. " width=" .. width .. " reason=" .. reason .. detail)
    end
    suspendedEnvironment, suspendedReason = signature, reason
    return false
end

local function optionalWarning(signature, width)
    local key = signature .. "/" .. tostring(width)
    if optionalEnvironment ~= key then warn(NO_GAMEVIEW) end
    optionalEnvironment = key
end

local function areaMismatch(actual, expected)
    for i, value in ipairs(expected) do
        if actual[i] ~= value then
            local field = i <= 6 and "position." .. positions[i] or "size." .. sizes[i - 6]
            return false, "area." .. field, value, actual[i]
        end
    end
    return true
end

local function rectangleMatches(name, x, y, w, h, width, height)
    if x ~= 0 then return false, name .. ".x", 0, x end
    if y ~= 0 then return false, name .. ".y", 0, y end
    if w ~= width then return false, name .. ".width", width, w end
    if h ~= height then return false, name .. ".height", height, h end
    return true
end

local function compatible(top, viewport, area, areaLayout, x, y, w, h, tx, ty, tw, th, viewportKey, reserved)
    if not top then return false, "top.missing" end
    if not viewport then return false, "viewport.missing" end
    if not area then return false, "area.missing" end
    if area.isRestricted then return false, "area.restricted" end
    if not areaLayout then return false, "area.layout_unreadable" end
    if not viewportKey then return false, "viewport.identity_unreadable" end
    if not w or w <= 0 then return false, "viewport.width", ">0", w end
    if not h or h <= 0 then return false, "viewport.height", ">0", h end
    if x ~= 0 then return false, "viewport.x", 0, x end
    if y ~= 0 then return false, "viewport.y", 0, y end
    local matches, reason, expected, actual = rectangleMatches("top", tx, ty, tw, th, w, h)
    if not matches then return false, reason, expected, actual end
    matches, reason, expected, actual = areaMismatch(areaLayout, centeredArea)
    if not matches then return false, reason, expected, actual end
    local ok, topParent, viewportParent, areaParent = pcall(
        function()
            return top.parent, viewport.parent, area.parent
        end
    )
    if not ok then return false, "parent.read_failed", "readable", topParent end
    if topParent ~= nil then return false, "top.parent", "root", identity(topParent) or "unknown" end
    if viewportParent ~= nil then return false, "viewport.parent", "root", identity(viewportParent) or "unknown" end
    local parentKey = identity(areaParent)
    if parentKey ~= viewportKey then return false, "area.parent", viewportKey, parentKey end
    local ax, ay, aw, ah = origin(area)
    return rectangleMatches("area", ax, ay, aw, ah, w - (reserved or 0), h)
end

local function updateSavedGameview(current, saved, width, environmentKey)
    local fresh = resolve(saved, current.interfaceObject)
    if fresh and layout(fresh, saved.written) then
        local desiredWidth = gameviewWidth(saved, current, width)
        if not explicitWidth(saved.original) or desiredWidth > 0 then
            if desiredWidth == saved.written[7] then return end
            local desired = { table.unpack(saved.original) }
            desired[7] = desiredWidth
            local ok, applied = pcall(set, saved, fresh, desired, "size")
            if ok and applied then
                current.gameview = desiredWidth ~= saved.original[7] and saved or nil
                return
            end
        end
    end
    if restoreRecord(saved, current.interfaceObject) then current.gameview = nil end
    current.gameviewBlocked = true
    optionalWarning(environmentKey, width)
end

local function nativeGameviewWidth(current, baseline, vx, vy, vw, vh, width)
    if fullSize(baseline) then
        if vx ~= 0 or vy ~= 0 or vw ~= current.width or vh ~= current.height then return nil end
        return -width
    end
    if
        not vx
        or not vy
        or not vw
        or not vh
        or vx < 0
        or vy < 0
        or vw <= 0
        or vh <= 0
        or vx + vw > current.width
        or vy + vh > current.height
    then
        return nil
    end
    local usableWidth = current.width - width
    if vx + vw <= usableWidth then return baseline[7] end
    if vw ~= baseline[7] or baseline[5] ~= 0 or usableWidth <= vx then return nil end
    return usableWidth - vx
end

local function updateGameview(current, width, environmentKey, viewportKey)
    local saved = current.gameview
    if current.gameviewBlocked then return end
    if saved then return updateSavedGameview(current, saved, width, environmentKey) end
    local view = component("gameview")
    local key = identity(view)
    local baseline = layout(view)
    local vx, vy, vw, vh = origin(view)
    local signature = environmentKey
        .. "/"
        .. tostring(width)
        .. "/"
        .. tostring(key)
        .. "/"
        .. (baseline and table.concat(baseline, ":") or "?")
        .. "/"
        .. tostring(vx)
        .. ":"
        .. tostring(vy)
        .. ":"
        .. tostring(vw)
        .. ":"
        .. tostring(vh)
    if current.optionalFailed == signature then return end
    local parentOK, parent = pcall(function() return view and view.parent end)
    local desiredWidth
    if
        view
        and not view.isRestricted
        and baseline
        and (fullSize(baseline) or explicitWidth(baseline))
        and parentOK
        and identity(parent) == viewportKey
    then
        desiredWidth = nativeGameviewWidth(current, baseline, vx, vy, vw, vh, width)
    end
    if not desiredWidth then
        current.optionalFailed = signature
        optionalWarning(environmentKey, width)
        return
    end
    if desiredWidth == baseline[7] then
        current.optionalFailed = nil
        optionalEnvironment = nil
        return
    end
    saved = record(view, viewportKey, baseline)
    if not saved then
        current.optionalFailed = signature
        optionalWarning(environmentKey, width)
        return
    end
    local desired = { table.unpack(baseline) }
    desired[7] = desiredWidth
    saved.originX = vx
    current.gameview = saved
    local ok, applied = pcall(set, saved, view, desired, "size")
    if not ok or not applied then
        if restoreRecord(saved, current.interfaceObject) then current.gameview = nil end
        current.optionalFailed = signature
        optionalWarning(environmentKey, width)
    else
        current.optionalFailed = nil
        optionalEnvironment = nil
    end
end

local function captureSlayer(current)
    local hud = component("hud")
    local target = child(hud, "slayer")
    if
        not target
        or target.isRestricted
        or not hud
        or identity(hud.parent) ~= current.viewportKey
        or identity(target.parent) ~= identity(hud)
    then
        return nil
    end
    local hx, hy, hw, hh = origin(hud)
    local hudLayout = layout(hud)
    if
        not hudLayout
        or not fullSize(hudLayout)
        or hx ~= 0
        or hy ~= 0
        or hw ~= current.width
        or hh ~= current.height
    then
        return nil
    end
    local baseline = layout(target)
    local sx, sy, sw, sh = origin(target)
    if
        not baseline
        or baseline[3] ~= 1
        or not sx
        or not sy
        or not sw
        or not sh
        or sx < 0
        or sy < 0
        or sw <= 0
        or sh <= 0
        or sx + sw > hw
        or sy + sh > hh
    then
        return nil
    end
    return record(target, identity(hud), baseline)
end

local function updateSlayer(current, width)
    if current.slayerBlocked then return end
    if width == 0 and not current.slayer then return end
    local saved = current.slayer
    if not saved then
        saved = captureSlayer(current)
        if not saved then return end
        current.slayer = saved
    end
    local fresh = resolve(saved, current.interfaceObject)
    -- Even an unchanged reservation must still yield to a foreign descriptor.
    if fresh and saved.written[1] == saved.original[1] - width and layout(fresh, saved.written) then
        return
    end
    local desired = { table.unpack(saved.original) }
    desired[1] = desired[1] - width
    local ok, applied = pcall(set, saved, fresh, desired, "position")
    if ok and applied then
        if desired[1] == saved.original[1] then current.slayer = nil end
        return
    end
    if restoreRecord(saved, current.interfaceObject) then current.slayer = nil end
    current.slayerBlocked = true
    warn(NO_SLAYER)
end

local function overlaps(x, y, width, height, obstacle)
    return obstacle
        and obstacle.visibleGlobal
        and x < obstacle.x + obstacle.width + HUD_GAP
        and x + width + HUD_GAP > obstacle.x
        and y < obstacle.y + obstacle.height + HUD_GAP
        and y + height + HUD_GAP > obstacle.y
end

local function privateChatShift(current, area, chat, clusterWidth, clusterHeight, target, saved)
    if clusterHeight <= 0 or not target or not target.visibleGlobal or target.width <= 0 or target.height <= 0 then
        return 0
    end
    local parent = target.parent
    local parentKey = identity(parent)
    if parentKey ~= identity(area) then
        -- Split PMs normally live under the full-viewport gameplay HUD.
        local hud = component("hud")
        local hx, hy, hw, hh = origin(hud)
        local hudLayout = layout(hud)
        if
            not hud
            or parentKey ~= identity(hud)
            or identity(hud.parent) ~= current.viewportKey
            or not hudLayout
            or not fullSize(hudLayout)
            or hx ~= 0
            or hy ~= 0
            or hw ~= current.width
            or hh ~= current.height
        then
            return nil
        end
    end
    local x, y = target.x, target.y
    if saved then
        local original = saved.original
        x = original[1] + parent.width * original[3] - target.width * original[5]
        y = original[2] + parent.height * original[4] - target.height * original[6]
    end
    local bottom = y + target.height
    if x < chat.x + clusterWidth and x + target.width > chat.x and y < chat.y and bottom > chat.y - clusterHeight then
        -- Retain the native PM-to-chat clearance above the inserted bars.
        return math.floor(math.min(0, chat.y - bottom) - clusterHeight), parentKey
    end
    return 0, parentKey
end

local function updatePrivateChat(current, area, chat, clusterWidth, clusterHeight)
    local saved = current.privateChat
    local target
    if saved then
        target = resolve(saved, current.interfaceObject)
        if not target or not layout(target, saved.written) then return false, "combat.privateChat.ownership" end
    elseif clusterHeight > 0 then
        target = component("privateChat")
    end
    local shift, parentKey = privateChatShift(current, area, chat, clusterWidth, clusterHeight, target, saved)
    if shift == nil then return false, "combat.privateChat.parent" end
    if shift ~= 0 and not saved then
        if target.isRestricted then return false, "combat.privateChat.restricted" end
        saved = record(target, parentKey, layout(target))
        if not saved then return false, "combat.privateChat.record" end
        current.privateChat = saved
    end
    if shift == 0 then
        if not restoreRecord(saved, current.interfaceObject) then return false, "combat.privateChat.restore" end
        current.privateChat = nil
        return true
    end
    local desired = { table.unpack(saved.original) }
    desired[2] = desired[2] + shift
    if not set(saved, target, desired, "position") then return false, "combat.privateChat.set" end
    return true
end

local function ownedAction(current, saved, name)
    local target, why = resolve(saved, current.interfaceObject)
    if not target then return nil, "combat." .. name .. "." .. why end
    local ok, matches, field, expected, actual = pcall(readLayout, target, saved.written)
    if not ok then return nil, "combat." .. name .. ".layout_unreadable" end
    if not matches then return nil, "combat." .. name .. ".ownership." .. field, expected, actual end
    return target
end

local function combatBounds(current, area, areaKey, chat, buttons)
    local targets = {}
    local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
    local collision = false
    for index, name in ipairs(actionNames) do
        local saved = current.actions and current.actions[index]
        local target
        if saved then
            local reason, expected, actual
            target, reason, expected, actual = ownedAction(current, saved, name)
            if not target then return nil, reason, expected, actual end
        else
            target = component(name)
        end
        if target and target.visibleGlobal and identity(target.parent) == areaKey then
            local x, y = target.x, target.y
            if saved then
                local original = saved.original
                x = original[1] + area.width * original[3] - target.width * original[5]
                y = original[2] + area.height * original[4] - target.height * original[6]
            end
            local width, height = target.width, target.height
            if width > 0 and height > 0 then
                targets[index] = target
                left, top = math.min(left, x), math.min(top, y)
                right, bottom = math.max(right, x + width), math.max(bottom, y + height)
                collision = collision or overlaps(x, y, width, height, chat) or overlaps(x, y, width, height, buttons)
            end
        end
    end
    return targets, left, top, right, bottom, collision
end

local function componentInArea(target, areaKey)
    if target and identity(target.parent) ~= areaKey then return nil end
    return target
end

-- The mode flag can switch before all native bars switch their anchors.
-- Moving even one bar now would record the outgoing layout as its baseline.
local function combatAnchorsReady(targets, areaHeight)
    for _, target in pairs(targets) do
        if target.position.yParentPc ~= 1 or target.y < 0 or target.y + target.height > areaHeight then return false end
    end
    return true
end

local function updateCombat(current, area)
    local areaKey = identity(area)
    local chat, buttons = component("chat"), component("buttons")
    chat, buttons = componentInArea(chat, areaKey), componentInArea(buttons, areaKey)
    local targets, left, top, right, bottom, collision = combatBounds(current, area, areaKey, chat, buttons)
    if not targets then return false, left, top, right end
    if not collision or not combatAnchorsReady(targets, area.height) then
        local privateOK, privateReason = updatePrivateChat(current, area, nil, 0, 0)
        if not privateOK then return false, privateReason end
        for index, saved in pairs(current.actions or {}) do
            if not restoreRecord(saved, current.interfaceObject) then
                return false, "combat." .. actionNames[index] .. ".restore"
            end
            current.actions[index] = nil
        end
        return true
    end
    -- Keep every bar's relative offset, placing the entire cluster above chat.
    -- Evaluate the original anchors, not our last write, to avoid oscillation.
    if not chat then return false, "combat.chat.missing" end
    if not chat.visibleGlobal then return false, "combat.chat.hidden" end
    if chat.x < 0 then return false, "combat.chat.x" end
    if chat.x + right - left > area.width then return false, "combat.chat.width" end
    if chat.y - (bottom - top) < 0 then return false, "combat.chat.height" end
    local dx, dy = math.floor(chat.x - left), math.floor(chat.y - bottom)
    local privateOK, privateReason = updatePrivateChat(current, area, chat, right - left, bottom - top)
    if not privateOK then return false, privateReason end
    current.actions = current.actions or {}
    for index, target in pairs(targets) do
        if not current.actions[index] then
            if target.isRestricted then return false, "combat." .. actionNames[index] .. ".restricted" end
            local saved = record(target, areaKey, layout(target))
            if not saved then return false, "combat." .. actionNames[index] .. ".record" end
            current.actions[index] = saved
        end
    end
    for index, saved in pairs(current.actions) do
        local target = targets[index]
        if target then
            local desired = { table.unpack(saved.original) }
            desired[1], desired[2] = desired[1] + dx, desired[2] + dy
            if not set(saved, target, desired, "position") then
                return false, "combat." .. actionNames[index] .. ".set"
            end
        else
            if not restoreRecord(saved, current.interfaceObject) then
                return false, "combat." .. actionNames[index] .. ".restore"
            end
            current.actions[index] = nil
        end
    end
    return true
end

local function rollbackAndSuspend(previous, signature, width, reason, expected, actual)
    restoreState()
    previous.blocked, previous.blockedEnvironment = true, signature
    previous.blockedReason, previous.blockedExpected, previous.blockedActual = reason, expected, actual
    state = previous
    return suspend(signature, width, reason, expected, actual)
end

local function rejectAreaChange(previous, signature, width, fresh)
    local current = layout(fresh)
    if current then
        local _, reason, expected, actual = areaMismatch(current, previous.area.written)
        return rollbackAndSuspend(previous, signature, width, reason or "area.layout_changed", expected, actual)
    end
    return rollbackAndSuspend(previous, signature, width, "area.layout_unreadable")
end

local function mandatoryFailure(previous, signature, width, ok, result, reason, expected, actual)
    rollbackAndSuspend(previous, signature, width, reason, expected, actual)
    if not ok then error(result, 0) end
    return false
end

local function reserveMandatory(previous, fresh, reservedWidth, signature)
    -- Ownership and topology were checked above; unchanged widths need no
    -- desired descriptor or repeated setter-side layout reads.
    if previous.reservedWidth ~= reservedWidth then
        local desired = { 0, 0, 0, 0, 0, 0, -reservedWidth, 0, 1, 1 }
        local stage = "position"
        local ok, applied = pcall(function()
            if not set(previous.area, fresh, desired, "position") then return false end
            stage = "size"
            return set(previous.area, fresh, desired, "size")
        end)
        if not ok or not applied then
            local reason = "area.set." .. stage .. (ok and "" or ".error")
            return mandatoryFailure(previous, signature, reservedWidth, ok, applied, reason)
        end
    end
    local combatOK, combatApplied, reason, wanted, observed = pcall(updateCombat, previous, fresh)
    if not combatOK or not combatApplied then
        return mandatoryFailure(
            previous,
            signature,
            reservedWidth,
            combatOK,
            combatApplied,
            combatOK and reason or "combat.error",
            wanted,
            observed
        )
    end
    return true
end

local function reservationChanged(previous, loaded, width, height, viewportKey)
    return not loaded
        or loaded ~= previous.interfaceObject
        or previous.width ~= width
        or previous.height ~= height
        or previous.viewportKey ~= viewportKey
end

local function reserveOptional(previous, reservedWidth, generation, viewportKey)
    local optionalOK = pcall(updateGameview, previous, reservedWidth, generation, viewportKey)
    if not optionalOK then
        previous.gameviewBlocked = true
        optionalWarning(generation, reservedWidth)
    end
    local slayerOK = pcall(updateSlayer, previous, reservedWidth)
    if not slayerOK then
        previous.slayerBlocked = true
        warn(NO_SLAYER)
    end
end

function ClassicLayout.update(reservedWidth)
    if not NativeInterfaceSettings.isClassicUI() then
        ClassicLayout.restore()
        return false
    end
    assert(
        type(reservedWidth) == "number" and reservedWidth >= 0 and reservedWidth % 1 == 0,
        "classic reserved width must be a nonnegative integer"
    )

    local top, viewport, area = component("top"), component("viewport"), component("area")
    local interfaceID = (id.Component[names.viewport] or 0) >> 16
    local loaded = ui.Interfaces:GetInterface(interfaceID)
    local signature, generation, x, y, w, h, tx, ty, tw, th, areaLayout, viewportKey =
        environment(loaded, viewport, top, area)
    local previous = state
    if previous and reservationChanged(previous, loaded, w, h, viewportKey) then
        if not restoreState() then return suspend(signature, reservedWidth, "restore.failed") end
        previous = nil
        signature, generation, x, y, w, h, tx, ty, tw, th, areaLayout, viewportKey =
            environment(loaded, viewport, top, area)
    end
    if previous and previous.blocked then
        return suspend(
            previous.blockedEnvironment,
            reservedWidth,
            previous.blockedReason,
            previous.blockedExpected,
            previous.blockedActual
        )
    end
    local fresh = previous and resolve(previous.area, loaded)
    if fresh and not layout(fresh, previous.area.written) then
        return rejectAreaChange(previous, signature, reservedWidth, fresh)
    end
    local allowed, reason, expected, actual = compatible(
        top,
        viewport,
        area,
        previous and previous.area.original or areaLayout,
        x,
        y,
        w,
        h,
        tx,
        ty,
        tw,
        th,
        viewportKey,
        previous and previous.reservedWidth
    )
    if not allowed then
        if previous then
            if not restoreState() then
                previous.blocked, previous.blockedEnvironment = true, signature
                previous.blockedReason, previous.blockedExpected, previous.blockedActual = reason, expected, actual
                state = previous
            else
                signature = environment(loaded, viewport, top, area)
            end
        end
        return suspend(signature, reservedWidth, reason, expected, actual)
    end
    if not previous then
        if not loaded then return suspend(signature, reservedWidth, "interface.missing") end
        local saved = record(area, viewportKey, areaLayout)
        if not saved then return suspend(signature, reservedWidth, "area.record") end
        previous = { interfaceObject = loaded, viewportKey = viewportKey, width = w, height = h, area = saved }
        state = previous
        fresh = resolve(saved, loaded)
    end
    if not fresh then
        restoreState()
        return suspend(signature, reservedWidth, "area.resolve")
    end
    if not reserveMandatory(previous, fresh, reservedWidth, signature) then return false end
    previous.reservedWidth = reservedWidth
    suspendedEnvironment, suspendedReason = nil, nil
    reserveOptional(previous, reservedWidth, generation, viewportKey)
    return true
end

return ClassicLayout
