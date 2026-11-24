-- Reads native interface settings and resolves the movement lock for PrettyUI widgets.
local Settings = require("src/settings")
local NativeInterfaceSettings = {}
local EVENT_ID = "prettyui_native_interface_settings"
local LOCK_VARBIT = "TOPLEVEL_V2_CUSTOMIZATION_LOCK"
-- The lock is a one-bit varbit: the server transmits only its base variable, so that is
-- the id watched, while the lock itself is read from the varbit.
local LOCK_BASE_VAR = "TOPLEVEL_V2_SKINS_VARP"
local CLASSIC_VARBIT = "TOPLEVEL_V2_LEGACY_INTERFACE"
local CLASSIC_BASE_VAR = "TOPLEVEL_V2_GENERAL_VARP"
local TRANSPARENCY_VAR = "TOPLEVEL_V2_TRANSPARENCY"
local TRANSPARENCY_MAX = 255

local function varValue(name)
    return var.VarPlayer[name].value
end

local function readValue(name)
    local ok, value = pcall(varValue, name)
    if ok and type(value) == "number" then return value end
    return 0
end

function NativeInterfaceSettings.isClassicUI()
    return readValue(CLASSIC_VARBIT) == 1
end

-- Resolved once at load in case the ids change between game updates. An id the client
-- does not know leaves its setting unwatchable: components then keep their own behaviour.
local function readID(name)
    local ok, varID = pcall(function() return id.VarPlayer[name] end)
    if ok and type(varID) == "number" then return varID end
    return nil
end

local function transparencyTransmitID()
    local varID = readID(TRANSPARENCY_VAR)
    if varID == nil then return nil end
    local ok, isVarBit = pcall(function()
        return var.VarPlayer[TRANSPARENCY_VAR].isVarBit
    end)
    if not ok or isVarBit ~= true then return varID end
    local baseOK, baseID = pcall(function()
        local base = var.VarPlayer[TRANSPARENCY_VAR].baseVar
        return base and base.id
    end)
    if baseOK and type(baseID) == "number" then return baseID end
    return nil
end

local lock = {
    varID = readID(LOCK_BASE_VAR),
    read = function() return readValue(LOCK_VARBIT) ~= 0 end,
    watchers = {},
}

local classicTransmitID = readID(CLASSIC_BASE_VAR)
local canWatchMovement = classicTransmitID ~= nil or lock.varID ~= nil
local movement = {
    read = function()
        if NativeInterfaceSettings.isClassicUI() then
            return not Settings.get("allowClassicMovement") and "classic"
        end
        return Settings.get("respectInterfaceLock") and lock.read() and "modern"
    end,
    watchers = {},
}

-- 0 is opaque and 1 fully transparent.
local transparency = {
    varID = transparencyTransmitID(),
    read = function() return readValue(TRANSPARENCY_VAR) / TRANSPARENCY_MAX end,
    watchers = {},
}

local function anyWatched()
    return next(lock.watchers) ~= nil
        or next(transparency.watchers) ~= nil
        or (canWatchMovement and next(movement.watchers) ~= nil)
end

local function refresh(setting)
    if next(setting.watchers) == nil then return end
    local value = setting.read()
    if value == setting.value then return end
    setting.value = value
    for _, callback in pairs(setting.watchers) do
        callback(value)
    end
end

local function onVarTransmit(event)
    local varID = event.var.id
    -- Both varbits may share one base variable; refresh every affected setting.
    if varID == lock.varID then refresh(lock) end
    if varID == transparency.varID then refresh(transparency) end
    if varID == classicTransmitID or varID == lock.varID then refresh(movement) end
end

-- VarTransmit only reports server updates. The client's own interface controls
-- can change the effective lock or mode without a matching transmission.
local function pollMovementLock()
    refresh(movement)
end

-- Calls back with the current value at once and again whenever it changes.
-- Subscribe to native updates only while a watched setting has a transmit ID.
local function watch(setting, owner, callback)
    local wasWatching = anyWatched()
    if next(setting.watchers) == nil then setting.value = setting.read() end
    setting.watchers[owner] = callback
    if not wasWatching and anyWatched() then Event.VarTransmit.Subscribe(EVENT_ID, onVarTransmit) end
    callback(setting.value)
end

local function unwatch(setting, owner)
    if setting.watchers[owner] == nil then return end
    local wasWatching = anyWatched()
    setting.watchers[owner] = nil
    if wasWatching and not anyWatched() then Event.VarTransmit.Unsubscribe(EVENT_ID) end
end

function NativeInterfaceSettings.isLocked() return lock.read() end
function NativeInterfaceSettings.watchLock(owner, callback)
    if lock.varID ~= nil then watch(lock, owner, callback) end
end
function NativeInterfaceSettings.unwatchLock(owner) unwatch(lock, owner) end
function NativeInterfaceSettings.watchTransparency(owner, callback)
    if transparency.varID ~= nil then watch(transparency, owner, callback) end
end
function NativeInterfaceSettings.unwatchTransparency(owner) unwatch(transparency, owner) end

local function onMovementPreferenceChanged(key)
    if key == "allowClassicMovement" or key == "respectInterfaceLock" then refresh(movement) end
end

function NativeInterfaceSettings.watchMovementLock(owner, callback)
    if next(movement.watchers) == nil then
        Settings.watch(movement, onMovementPreferenceChanged)
        if canWatchMovement then Event.Logic.Subscribe(EVENT_ID, pollMovementLock) end
    end
    watch(
        movement,
        owner,
        function(state)
            callback(owner, state == "classic" or (state == "modern" and owner.respectInterfaceLock))
        end
    )
end

function NativeInterfaceSettings.unwatchMovementLock(owner)
    if movement.watchers[owner] == nil then return end
    unwatch(movement, owner)
    if next(movement.watchers) == nil then
        if canWatchMovement then Event.Logic.Unsubscribe(EVENT_ID) end
        Settings.unwatch(movement)
    end
end

return NativeInterfaceSettings
