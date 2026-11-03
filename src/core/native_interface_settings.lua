-- The player's own interface settings that PrettyUI components may follow: the
-- "lock interface" customisation toggle and the interface transparency slider.
local NativeInterfaceSettings = {}
local EVENT_ID = "prettyui_native_interface_settings"
local LOCK_VARBIT = "TOPLEVEL_V2_CUSTOMIZATION_LOCK"
-- The lock is a one-bit varbit: the server transmits only its base variable, so that is
-- the id watched, while the lock itself is read from the varbit.
local LOCK_BASE_VAR = "TOPLEVEL_V2_SKINS_VARP"
local TRANSPARENCY_VAR = "TOPLEVEL_V2_TRANSPARENCY"
local TRANSPARENCY_MAX = 255

local function readValue(name)
    local ok, value = pcall(function() return var.VarPlayer[name].value end)
    if ok and type(value) == "number" then return value end
    return 0
end

-- Resolved once at load in case the ids change between game updates. An id the client
-- does not know leaves its setting unwatchable: components then keep their own behaviour.
local function readID(name)
    local ok, varID = pcall(function() return id.VarPlayer[name] end)
    if ok and type(varID) == "number" then return varID end
    return nil
end

local lock = {
    varID = readID(LOCK_BASE_VAR),
    read = function() return readValue(LOCK_VARBIT) ~= 0 end,
    watchers = {},
}

-- 0 is opaque and 1 fully transparent.
local transparency = {
    varID = readID(TRANSPARENCY_VAR),
    read = function() return readValue(TRANSPARENCY_VAR) / TRANSPARENCY_MAX end,
    watchers = {},
}

-- Settings by the id of the variable the server transmits for them.
local settingsByVarID = {}
if lock.varID then settingsByVarID[lock.varID] = lock end
if transparency.varID then settingsByVarID[transparency.varID] = transparency end

local function anyWatched()
    return next(lock.watchers) ~= nil or next(transparency.watchers) ~= nil
end

local function refresh(setting)
    if next(setting.watchers) == nil then return end
    local value = setting.read()
    if value == setting.value then return end
    setting.value = value
    for _, callback in pairs(setting.watchers) do callback(value) end
end

local function onVarTransmit(event)
    local setting = settingsByVarID[event.var.id]
    if setting then refresh(setting) end
end

-- Calls back with the setting's value at once and again whenever it changes, until
-- unwatched; never, if the setting's id was not found. The first watcher of either
-- setting starts listening to the server's variable updates; the last one to leave stops it.
local function watch(setting, owner, callback)
    if setting.varID == nil then return end
    if not anyWatched() then Event.VarTransmit.Subscribe(EVENT_ID, onVarTransmit) end
    if next(setting.watchers) == nil then setting.value = setting.read() end
    setting.watchers[owner] = callback
    callback(setting.value)
end

local function unwatch(setting, owner)
    if setting.watchers[owner] == nil then return end
    setting.watchers[owner] = nil
    if not anyWatched() then Event.VarTransmit.Unsubscribe(EVENT_ID) end
end

function NativeInterfaceSettings.watchLock(owner, callback) watch(lock, owner, callback) end
function NativeInterfaceSettings.unwatchLock(owner) unwatch(lock, owner) end
function NativeInterfaceSettings.watchTransparency(owner, callback) watch(transparency, owner, callback) end
function NativeInterfaceSettings.unwatchTransparency(owner) unwatch(transparency, owner) end

return NativeInterfaceSettings
