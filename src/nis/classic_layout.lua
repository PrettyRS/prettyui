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
    if not ok or type(a) ~= "number" or type(b) ~= "number"
        or type(c) ~= "number" or type(d) ~= "number" then return nil end
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
    for i = first, last do if a[i] ~= b[i] then return false end end
    return true
end

local function fullSize(saved)
    return saved[7] == 0 and saved[8] == 0 and saved[9] == 1 and saved[10] == 1
end

local function originValues(value)
    return value.x, value.y, value.width, value.height
end

local function origin(value)
    local ok, x, y, width, height = pcall(originValues, value)
    if ok and type(x) == "number" and type(y) == "number"
        and type(width) == "number" and type(height) == "number" then
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
    local changedPos = same(current, saved.written, 1, 6)
        and not same(current, saved.original, 1, 6)
    local changedSize = same(current, saved.written, 7, 10)
        and not same(current, saved.original, 7, 10)
    if changedPos then
        pcall(function() fresh:SetPos(table.unpack(saved.original, 1, 6)) end)
    end
    if changedSize then
        pcall(function() fresh:SetSize(table.unpack(saved.original, 7, 10)) end)
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
    local actionsOK = true
    for _, action in pairs(saved.actions or {}) do
        local called, restored = pcall(restoreRecord, action, saved.interfaceObject)
        actionsOK = called and restored and actionsOK
    end
    local viewCall, gameviewOK = pcall(restoreRecord, saved.gameview, saved.interfaceObject)
    local areaCall, areaOK = pcall(restoreRecord, saved.area, saved.interfaceObject)
    local slayerCall, slayerOK = pcall(restoreRecord, saved.slayer, saved.interfaceObject)
    local privateCall, privateOK = pcall(restoreRecord, saved.privateChat, saved.interfaceObject)
    local complete = actionsOK and viewCall and gameviewOK and areaCall and areaOK
        and slayerCall and slayerOK and privateCall and privateOK
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
    if not current then return false, "ownership" end
    local first, last = which == "position" and 1 or 7, which == "position" and 6 or 10
    if same(current, desired, first, last) then return true end
    -- Mark the intended descriptor before invoking the setter: setters can
    -- mutate their target before raising, and the rollback must still own it.
    for i = first, last do saved.written[i] = desired[i] end
    if which == "position" then fresh:SetPos(table.unpack(desired, 1, 6))
    else fresh:SetSize(table.unpack(desired, 7, 10)) end
    if not same(layout(fresh) or {}, desired, first, last) then return false, "readback" end
    return true
end

local function environment(loaded, viewport, top, area)
    local x, y, w, h = origin(viewport)
    local tx, ty, tw, th = origin(top)
    local areaLayout = layout(area)
    local topKey, viewportKey, areaKey = identity(top), identity(viewport), identity(area)
    -- Include the area layout so a changed baseline can retry a suspended reservation.
    local signature = table.concat({ tostring(loaded), tostring(topKey), tostring(viewportKey),
        tostring(areaKey), tostring(x), tostring(y), tostring(w), tostring(h),
        tostring(tx), tostring(ty), tostring(tw), tostring(th) }, "/")
    return signature .. "/" .. (areaLayout and table.concat(areaLayout, ":") or "?"),
        signature, x, y, w, h, tx, ty, tw, th, areaLayout, viewportKey
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

local function optionalWarning(signature)
    if optionalEnvironment ~= signature then warn(NO_GAMEVIEW) end
    optionalEnvironment = signature
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

local function compatible(top, viewport, area, areaLayout, x, y, w, h, tx, ty, tw, th,
        viewportKey, reserved)
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
    local ok, topParent, viewportParent, areaParent = pcall(function()
        return top.parent, viewport.parent, area.parent
    end)
    if not ok then return false, "parent.read_failed", "readable", topParent end
    if topParent ~= nil then return false, "top.parent", "root", identity(topParent) or "unknown" end
    if viewportParent ~= nil then return false, "viewport.parent", "root", identity(viewportParent) or "unknown" end
    local parentKey = identity(areaParent)
    if parentKey ~= viewportKey then return false, "area.parent", viewportKey, parentKey end
    local ax, ay, aw, ah = origin(area)
    return rectangleMatches("area", ax, ay, aw, ah, w - (reserved or 0), h)
end

local function explicitGameviewEligible(baseline, vx, vy, vw, vh, width, height, reserved)
    if not (vx and vy and vw and vh and vx >= 0 and vy >= 0 and vw > 0 and vh > 0
        and vx + vw <= width and vy + vh <= height) then return false end
    return vx + vw <= width - reserved or baseline[5] == 0 and vx < width - reserved
end

local function gameviewCompatible(view, baseline, parentOK, parent, viewportKey,
        vx, vy, vw, vh, width, height, reserved)
    if not view or view.isRestricted or not baseline or not parentOK
        or identity(parent) ~= viewportKey then return false end
    local explicit = baseline[9] == 0 and baseline[7] > 0
    if not fullSize(baseline) and not explicit then return false end
    if explicit then
        return explicitGameviewEligible(baseline, vx, vy, vw, vh, width, height, reserved), true
    end
    return vx == 0 and vy == 0 and vw == width and vh == height, false
end

local function desiredGameviewWidth(saved, width, viewportWidth)
    if saved.explicitX then return math.min(saved.original[7], viewportWidth - width - saved.explicitX) end
    return saved.original[7] - width
end

local function blockGameview(current, saved, environmentKey)
    if restoreRecord(saved, current.interfaceObject) then current.gameview = nil end
    current.gameviewBlocked = true
    optionalWarning(environmentKey)
end

local function updateOwnedGameview(current, width, environmentKey, saved)
    local fresh = resolve(saved, current.interfaceObject)
    if not fresh or not layout(fresh, saved.written) then
        blockGameview(current, saved, environmentKey)
        return
    end
    local desiredWidth = desiredGameviewWidth(saved, width, current.width)
    if saved.explicitX and desiredWidth <= 0 then
        blockGameview(current, saved, environmentKey)
        return
    end
    if desiredWidth == saved.original[7] then
        if restoreRecord(saved, current.interfaceObject) then
            current.gameview = nil
            current.optionalFailed = nil
            optionalEnvironment = nil
            return
        end
        current.gameviewBlocked = true
        optionalWarning(environmentKey)
        return
    end
    if saved.written[7] == desiredWidth then return end
    local desired = { table.unpack(saved.original) }
    desired[7] = desiredWidth
    local ok, applied = pcall(set, saved, fresh, desired, "size")
    if ok and applied then return end
    blockGameview(current, saved, environmentKey)
end

local function updateGameview(current, width, environmentKey, viewportKey)
    if current.gameviewBlocked then return end
    if current.gameview then
        updateOwnedGameview(current, width, environmentKey, current.gameview)
        return
    end
    local view = component("gameview")
    local key = identity(view)
    local baseline = layout(view)
    local vx, vy, vw, vh = origin(view)
    local signature = environmentKey .. "/" .. width .. "/" .. tostring(key) .. "/"
        .. (baseline and table.concat(baseline, ":") or "?") .. "/"
        .. tostring(vx) .. ":" .. tostring(vy) .. ":" .. tostring(vw) .. ":" .. tostring(vh)
    if current.optionalFailed == signature then return end
    local parentOK, parent = pcall(function() return view and view.parent end)
    local eligible, explicit = gameviewCompatible(view, baseline,
        parentOK, parent, viewportKey, vx, vy, vw, vh, current.width, current.height, width)
    if not eligible then
        current.optionalFailed = signature
        optionalWarning(environmentKey)
        return
    end
    local desiredWidth = explicit and math.min(baseline[7], current.width - width - vx) or -width
    if desiredWidth == baseline[7] then
        current.optionalFailed = nil
        optionalEnvironment = nil
        return
    end
    local saved = record(view, viewportKey, baseline)
    if not saved then
        current.optionalFailed = signature
        optionalWarning(environmentKey)
        return
    end
    saved.explicitX = explicit and vx or nil
    local desired = { table.unpack(baseline) }
    desired[7] = desiredWidth
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

local function visibleClassicSlayer(target, width, height)
    local baseline = layout(target)
    if not baseline or baseline[3] ~= 1 then return nil end
    local x, y, w, h = origin(target)
    if x and y and w and h and x >= 0 and y >= 0 and w > 0 and h > 0
        and x + w <= width and y + h <= height then return baseline end
end

local function captureSlayer(current)
    local hud = component("hud")
    local target = child(hud, "slayer")
    if not target or target.isRestricted or not hud
        or identity(hud.parent) ~= current.viewportKey
        or identity(target.parent) ~= identity(hud) then return nil end
    local hx, hy, hw, hh = origin(hud)
    local hudLayout = layout(hud)
    if not hudLayout or not fullSize(hudLayout) or hx ~= 0 or hy ~= 0
        or hw ~= current.width or hh ~= current.height then return nil end
    return record(target, identity(hud), visibleClassicSlayer(target, hw, hh))
end

local function updateSlayer(current, width)
    if current.slayerBlocked then return end
    local saved = current.slayer
    if not saved then
        saved = captureSlayer(current)
        if not saved then return end
        current.slayer = saved
    end
    local fresh = resolve(saved, current.interfaceObject)
    -- Even an unchanged reservation must still yield to a foreign descriptor.
    local owned = fresh and layout(fresh, saved.written)
    if owned and saved.written[1] == saved.original[1] - width then return end
    local desired = { table.unpack(saved.original) }
    desired[1] = desired[1] - width
    local ok, applied = pcall(set, saved, fresh, desired, "position")
    if ok and applied then return end
    if restoreRecord(saved, current.interfaceObject) then current.slayer = nil end
    current.slayerBlocked = true
    warn(NO_SLAYER)
end

local function overlaps(x, y, width, height, obstacle)
    return obstacle and obstacle.visibleGlobal and x < obstacle.x + obstacle.width + HUD_GAP
        and x + width + HUD_GAP > obstacle.x
        and y < obstacle.y + obstacle.height + HUD_GAP
        and y + height + HUD_GAP > obstacle.y
end

local function updatePrivateChat(current, area, chat, clusterWidth, clusterHeight)
    local saved = current.privateChat
    local target
    if saved then
        target = resolve(saved, current.interfaceObject)
        if not target then return false, "combat.privateChat.resolve" end
        if not layout(target, saved.written) then return false, "combat.privateChat.ownership" end
    elseif clusterHeight > 0 then
        target = component("privateChat")
    end
    local shift = 0
    if clusterHeight > 0 and target and target.visibleGlobal
        and target.width > 0 and target.height > 0 then
        local parent = target.parent
        local parentKey = identity(parent)
        if parentKey ~= identity(area) then
            -- Split PMs normally live under the full-viewport gameplay HUD.
            local hud = component("hud")
            local hx, hy, hw, hh = origin(hud)
            local hudLayout = layout(hud)
            if not hud or parentKey ~= identity(hud) or identity(hud.parent) ~= current.viewportKey
                or not hudLayout or not fullSize(hudLayout) or hx ~= 0 or hy ~= 0
                or hw ~= current.width or hh ~= current.height then return false, "combat.privateChat.hud" end
        end
        local x, y = target.x, target.y
        if saved then
            local original = saved.original
            x = original[1] + parent.width * original[3] - target.width * original[5]
            y = original[2] + parent.height * original[4] - target.height * original[6]
        end
        local bottom = y + target.height
        if x < chat.x + clusterWidth and x + target.width > chat.x
            and y < chat.y and bottom > chat.y - clusterHeight then
            -- Retain the native PM-to-chat clearance above the inserted bars.
            shift = math.floor(math.min(0, chat.y - bottom) - clusterHeight)
        end
        if shift ~= 0 and not saved then
            if target.isRestricted then return false, "combat.privateChat.restricted" end
            saved = record(target, parentKey, layout(target))
            if not saved then return false, "combat.privateChat.record" end
            current.privateChat = saved
        end
    end
    if shift == 0 then
        if not restoreRecord(saved, current.interfaceObject) then return false, "combat.privateChat.restore" end
        current.privateChat = nil
        return true
    end
    local desired = { table.unpack(saved.original) }
    desired[2] = desired[2] + shift
    local applied, why = set(saved, target, desired, "position")
    if not applied then return false, "combat.privateChat.position." .. why end
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
    if chat and identity(chat.parent) ~= areaKey then chat = nil end
    if buttons and identity(buttons.parent) ~= areaKey then buttons = nil end
    local targets = {}
    local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
    local collision = false
    for index, name in ipairs(actionNames) do
        local saved = current.actions and current.actions[index]
        local target
        if saved then
            local reason, expected, actual
            target, reason, expected, actual = ownedAction(current, saved, name)
            if not target then return false, reason, expected, actual end
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
                collision = collision or overlaps(x, y, width, height, chat)
                    or overlaps(x, y, width, height, buttons)
            end
        end
    end
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
    if chat.x + right - left > area.width then return false, "combat.cluster.width" end
    if chat.y - (bottom - top) < 0 then return false, "combat.cluster.height" end
    local dx, dy = math.floor(chat.x - left), math.floor(chat.y - bottom)
    local privateOK, privateReason = updatePrivateChat(current, area, chat, right - left, bottom - top)
    if not privateOK then return false, privateReason end
    current.actions = current.actions or {}
    for index, target in pairs(targets) do
        if not current.actions[index] then
            local name = actionNames[index]
            local saved = record(target, areaKey, layout(target))
            if not saved then return false, "combat." .. name .. ".record" end
            if target.isRestricted then return false, "combat." .. name .. ".restricted" end
            current.actions[index] = saved
        end
    end
    for index, saved in pairs(current.actions) do
        local target = targets[index]
        if target then
            local desired = { table.unpack(saved.original) }
            desired[1], desired[2] = desired[1] + dx, desired[2] + dy
            local applied, why = set(saved, target, desired, "position")
            if not applied then return false, "combat." .. actionNames[index] .. ".position." .. why end
        else
            if not restoreRecord(saved, current.interfaceObject) then
                return false, "combat." .. actionNames[index] .. ".restore"
            end
            current.actions[index] = nil
        end
    end
    return true
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
        if not restoreState() then return suspend(signature, reservedWidth, "restore.failed") end
        previous = nil
        signature, generation, x, y, w, h, tx, ty, tw, th, areaLayout, viewportKey =
            environment(loaded, viewport, top, area)
    end
    if previous and previous.blocked then
        return suspend(previous.blockedEnvironment, reservedWidth, previous.blockedReason,
            previous.blockedExpected, previous.blockedActual)
    end
    local fresh = previous and resolve(previous.area, loaded)
    if fresh and not layout(fresh, previous.area.written) then
        local actualLayout = layout(fresh)
        local _, reason, expected, actual
        if actualLayout then _, reason, expected, actual = areaMismatch(actualLayout, previous.area.written) end
        restoreState()
        previous.blocked, previous.blockedEnvironment = true, signature
        previous.blockedReason = reason or "area.layout_unreadable"
        previous.blockedExpected, previous.blockedActual = expected, actual
        state = previous
        return suspend(signature, reservedWidth, previous.blockedReason, expected, actual)
    end
    local matches, reason, expected, actual = compatible(top, viewport, area,
        previous and previous.area.original or areaLayout,
        x, y, w, h, tx, ty, tw, th, viewportKey, previous and previous.reservedWidth)
    if not matches then
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
        previous = { interfaceObject = loaded, viewportKey = viewportKey,
            width = w, height = h, area = saved }
        state = previous
        fresh = resolve(saved, loaded)
    end
    if not fresh then
        restoreState()
        return suspend(signature, reservedWidth, "area.resolve")
    end
    -- Ownership and topology were checked above; unchanged widths need no
    -- desired descriptor or repeated setter-side layout reads.
    if previous.reservedWidth ~= reservedWidth then
        local desired = { 0, 0, 0, 0, 0, 0, -reservedWidth, 0, 1, 1 }
        local failedPart = "position"
        local ok, applied, failedReason = pcall(function()
            local positionOK, why = set(previous.area, fresh, desired, "position")
            if not positionOK then return false, "area.position." .. why end
            failedPart = "size"
            local sizeOK, sizeWhy = set(previous.area, fresh, desired, "size")
            if not sizeOK then return false, "area.size." .. sizeWhy end
            return true
        end)
        if not ok or not applied then
            local cause = ok and failedReason or "area.set." .. failedPart .. ".exception"
            restoreState()
            previous.blocked, previous.blockedEnvironment = true, signature
            previous.blockedReason = cause
            state = previous
            suspend(signature, reservedWidth, cause)
            if not ok then error(applied, 0) end
            return false
        end
    end
    local combatOK, combatApplied, combatReason, wanted, observed = pcall(updateCombat, previous, fresh)
    if not combatOK or not combatApplied then
        local cause = combatOK and combatReason or "combat.exception"
        restoreState()
        previous.blocked, previous.blockedEnvironment = true, signature
        previous.blockedReason, previous.blockedExpected, previous.blockedActual = cause, wanted, observed
        state = previous
        suspend(signature, reservedWidth, cause, wanted, observed)
        if not combatOK then error(combatApplied, 0) end
        return false
    end
    previous.reservedWidth = reservedWidth
    suspendedEnvironment, suspendedReason = nil, nil
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
