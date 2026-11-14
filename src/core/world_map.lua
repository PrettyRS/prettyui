-- World-map focus is temporary occlusion, not a user-requested Hide/Close.
-- Track only PrettyUI roots; native components and nested controls keep their
-- own visibility. Resolve roots by ID at transitions instead of retaining
-- native handles across top-level rebuilds.
local WorldMap = {}
local EVENT_ID = "prettyui_world_map"
local roots = setmetatable({}, { __mode = "k" })
local records = {}
local watchers = setmetatable({}, { __mode = "k" })
local listening, focused, suspended, waiting = false, false, false, false

local function readFocus()
    for _, domain in ipairs({ "VarClient", "VarPlayer" }) do
        local ok, value = pcall(function()
            local focus = var[domain].WORLDMAP_FOCUS
            if focus.configName == "WORLDMAP_FOCUS" then return focus.value end
        end)
        if ok and type(value) == "number" then return value ~= -1 end
    end
end

local function resolve(saved)
    if ui.Interfaces:GetInterface(saved.interfaceID) == nil then return nil end
    return ui.Interfaces:GetComponent(saved.interfaceID, saved.staticID, saved.categoryID, saved.dynamicID)
end

local function eachRoot(callback)
    for key, saved in pairs(records) do
        local current = resolve(saved)
        if current then
            callback(current, saved)
        else
            records[key] = nil
        end
    end
end

local function notify(value)
    for _, callback in pairs(watchers) do callback(value) end
end

local function stopWaiting()
    if waiting then Event.Logic.Unsubscribe(EVENT_ID); waiting = false end
end

local function resume()
    if focused then return end
    local area = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
    -- The focus-close event may precede the client's top-level restoration.
    if not area or area.visibleGlobal == false or area.width <= 0 or area.height <= 0 then return end
    stopWaiting()
    suspended = false
    eachRoot(function(root, saved) root.hidden = saved.hidden end)
    notify(false)
end

local function setFocus(value)
    focused = value
    if value then
        stopWaiting()
        if suspended then return end
        eachRoot(function(root, saved) saved.hidden = root.hidden == true end)
        suspended = true
        -- Cancel gestures before hiding their capture surfaces. Callers must
        -- not interpret the world's disappearing native frames as undocking.
        notify(true)
        eachRoot(function(root) root.hidden = true end)
    elseif suspended and not waiting then
        waiting = true
        Event.Logic.Subscribe(EVENT_ID, resume)
    end
end

function WorldMap.start(force)
    if listening or not Event or not Event.VarTransmit or not Event.Logic then return end
    local value = readFocus()
    if value == nil and not force then return end
    listening = true
    Event.VarTransmit.Subscribe(EVENT_ID, function(event)
        if event.var.configName == "WORLDMAP_FOCUS" then setFocus(event.newValue ~= -1) end
    end)
    if value ~= nil then setFocus(value) end
end

function WorldMap.isSuspended()
    return suspended
end

function WorldMap.track(root)
    WorldMap.start()
    local packed = (root.interfaceID << 16) | root.staticID
    local key = packed .. ":" .. root.categoryID .. ":" .. root.dynamicID
    local saved = { interfaceID = root.interfaceID, staticID = root.staticID,
        categoryID = root.categoryID, dynamicID = root.dynamicID,
        key = key, hidden = root.hidden == true }
    roots[root], records[key] = saved, saved
    if suspended then root.hidden = true end
end

-- Destroyed roots must leave the registry immediately: tooltips and drag
-- feedback can create thousands of short-lived surfaces between map opens.
-- An older handle must not remove a new native root that reused its ID.
function WorldMap.untrack(root)
    local saved = roots[root]
    if not saved then return end
    roots[root] = nil
    if records[saved.key] == saved then records[saved.key] = nil end
end

function WorldMap.setHidden(component, hidden)
    local saved = roots[component]
    if saved then saved = records[saved.key] or saved end
    if saved then saved.hidden = hidden == true end
    component.hidden = suspended and saved ~= nil or hidden
end

function WorldMap.isHidden(component)
    local saved = suspended and roots[component]
    if saved then saved = records[saved.key] or saved end
    if saved then return saved.hidden end
    return component.hidden == true
end

function WorldMap.watch(owner, callback)
    WorldMap.start()
    watchers[owner] = callback
    callback(suspended)
end

function WorldMap.unwatch(owner)
    watchers[owner] = nil
end

function WorldMap.shutdown()
    stopWaiting()
    if listening then Event.VarTransmit.Unsubscribe(EVENT_ID) end
    eachRoot(function(root, saved) root.hidden = saved.hidden end)
    roots, records, watchers = setmetatable({}, { __mode = "k" }), {},
        setmetatable({}, { __mode = "k" })
    listening, focused, suspended = false, false, false
end

return WorldMap
