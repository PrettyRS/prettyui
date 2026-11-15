local Persistence = {}
local sameComponent = require("src/core/components").sameComponent
local WorldMap = require("src/core/world_map")
local database = PersistentDB
local KEY = "prettyui.nis-layout.v1"
local state
local live = {}
local restoring = false

local function load()
    if state then return end
    assert(database, "NisPanel persistence requires PersistentDB")
    state = database:GetStructuredData(KEY) or { panels = {}, groups = {}, nextGroup = 0 }
end

local function flush()
    assert(database:SetStructuredData(KEY, state) ~= false, "Could not save NisPanel layout")
end

local function set(record, key, value)
    if record[key] == value then return false end
    record[key] = value
    return true
end

local function geometry(record, root)
    local changed = set(record, "x", root.x)
    changed = set(record, "y", root.y) or changed
    changed = set(record, "width", root.width) or changed
    return set(record, "height", root.height) or changed
end

local function loaded(panel)
    return panel and not panel._destroyed and panel.root
        and ui.Interfaces:GetInterface(panel.interfaceID) ~= nil
end

local function busy(panel)
    return panel._nisNative or panel._nisNativeDetaching or panel._nisNativeTransaction
        or panel.dragState or panel._nisTabPress or panel._nisTabTransaction
        or panel.resize and panel.resize.dragState
end

function Persistence.prepare(options)
    if options.id == nil then
        assert(options.dockTo == nil, "NisPanel dockTo requires an id")
        return options
    end
    assert(type(options.id) == "string" and options.id ~= "", "NisPanel id must be a nonempty string")
    assert(options.dockTo == nil or type(options.dockTo) == "string" and options.dockTo ~= ""
        and options.dockTo ~= options.id, "NisPanel dockTo must identify another panel")
    load()
    assert(live[options.id] == nil, "NisPanel id is already in use: " .. options.id)
    local record = state.panels[options.id]
    if not record then return options end
    local restored = {}
    for key, value in pairs(options) do restored[key] = value end
    restored.x, restored.y = record.x, record.y
    restored.width, restored.height = record.width, record.height
    restored.xAnchor, restored.yAnchor = nil, nil
    restored.active = record.active ~= false
    return restored
end

-- Keep absent plugins in the logical group. Runtime groups contain only loaded panels.
local function join(ids, active)
    local combined, seen, oldGroups = {}, {}, {}
    local key
    for _, panelID in ipairs(ids) do
        local groupID = state.panels[panelID].group
        local group = groupID and state.groups[groupID]
        if group and not oldGroups[groupID] then
            key = key or groupID
            oldGroups[groupID] = true
            for _, memberID in ipairs(group.members) do
                if not seen[memberID] then
                    combined[#combined + 1], seen[memberID] = memberID, true
                end
            end
        end
        if not seen[panelID] then
            combined[#combined + 1], seen[panelID] = panelID, true
        end
    end
    -- Reorder loaded members without moving the slots of missing members.
    local included, ordered, index = {}, {}, 1
    for _, panelID in ipairs(ids) do included[panelID] = true end
    for _, panelID in ipairs(combined) do
        if included[panelID] then
            ordered[#ordered + 1] = ids[index]
            index = index + 1
        else
            ordered[#ordered + 1] = panelID
        end
    end
    if #ordered < 2 then return false end
    if key then
        local old = state.groups[key]
        local same = old.active == active and #old.members == #ordered
        for i, panelID in ipairs(ordered) do same = same and old.members[i] == panelID end
        local count = 0
        for _ in pairs(oldGroups) do count = count + 1 end
        if same and count == 1 then return false end
    else
        state.nextGroup = state.nextGroup + 1
        key = tostring(state.nextGroup)
    end
    for groupID in pairs(oldGroups) do state.groups[groupID] = nil end
    state.groups[key] = { members = ordered, active = active }
    for _, panelID in ipairs(ordered) do
        state.panels[panelID].group = key
        state.panels[panelID].dockTo = nil
        state.panels[panelID].native = nil
        if live[panelID] then live[panelID]._nisNativePending = nil end
    end
    return true
end

local function restore(groups, affected)
    restoring = true
    for groupID in pairs(affected) do
        local saved = state.groups[groupID]
        local members, parent, active = {}, nil, nil
        for _, panelID in ipairs(saved.members) do
            local panel = live[panelID]
            if loaded(panel) and not panel._nisClassic and not panel._nisHidden then
                if parent == nil then parent = panel.parent end
                if sameComponent(panel.parent, parent) then
                    panel:_CancelDrag()
                    if panel.resize then panel.resize:Cancel() end
                    members[#members + 1] = panel
                    if panelID == saved.active then active = panel end
                end
            end
        end
        if #members > 0 then
            local record = state.panels[saved.active] or state.panels[members[1]._nisPersistenceID]
            if #members > 1 then
                groups.restore({
                    members = members, active = active or members[1],
                    x = record.x, y = record.y, width = record.width, height = record.height,
                }, false)
            else
                local panel = members[1]
                local width = math.max(panel.minWidth, math.min(panel.maxWidth or math.huge, record.width))
                local height = math.max(panel.minHeight, math.min(panel.maxHeight or math.huge, record.height))
                panel:_ApplyRectSingle(
                    math.max(0, math.min(record.x, panel.parent.width - width)),
                    math.max(0, math.min(record.y, panel.parent.height - height)), width, height)
            end
            for _, panel in ipairs(members) do
                local root = panel.root
                panel._lastBounds = { root.x, root.y, root.width, root.height }
            end
        end
    end
    restoring = false
end

function Persistence.register(panel, options, groups)
    if options.id == nil then return end
    panel._nisPersistenceID = options.id
    live[options.id] = panel
    local changed = false
    local affected = {}
    local existing = state.panels[options.id]
    if existing and existing.group then affected[existing.group] = true end
    panel._nisNativePending = existing and existing.native
    if not state.panels[options.id] then
        local record = { dockTo = options.dockTo, active = not panel._nisHidden }
        geometry(record, panel.root)
        state.panels[options.id] = record
        changed = true
    end
    for panelID, record in pairs(state.panels) do
        local target = record.dockTo and state.panels[record.dockTo]
        if target then
            local targetID = record.dockTo
            record.dockTo = nil
            join({ targetID, panelID }, panelID)
            local group = state.groups[record.group]
            if group then
                affected[record.group] = true
                for _, memberID in ipairs(group.members) do
                    geometry(state.panels[memberID], target)
                end
            end
            changed = true
        end
    end
    for groupID in pairs(affected) do
        if state.groups[groupID] == nil then affected[groupID] = nil end
    end
    restore(groups, affected)
    if changed then flush() end
end

-- Activation changes runtime membership, not the remembered logical layout.
function Persistence.setActive(panel, active, groups)
    local panelID = panel._nisPersistenceID
    if not panelID then return false end
    local record = state.panels[panelID]
    if set(record, "active", active) then flush() end
    if not active or panel._nisClassic then return false end
    panel._nisNativePending = record.native
    if record.group then
        restore(groups, { [record.group] = true })
        return true
    end
    return false
end

function Persistence.bounds(panel)
    local panelID = panel._nisPersistenceID
    if panel._nisClassic or WorldMap.isSuspended() or not panelID or restoring or not loaded(panel)
        or panel._nisHidden or busy(panel) then return end
    local record = state.panels[panelID]
    local group = record.group and state.groups[record.group]
    local changed = false
    if group then
        for _, memberID in ipairs(group.members) do
            changed = geometry(state.panels[memberID], panel.root) or changed
        end
    else
        changed = geometry(record, panel.root)
    end
    if changed then
        record.dockTo = nil
        record.native, panel._nisNativePending = nil, nil
        flush()
    end
end

function Persistence.capture(panel)
    if panel._nisClassic or WorldMap.isSuspended()
        or restoring or not state or not loaded(panel) then return end
    local group = panel._nisGroup
    if not group then return Persistence.bounds(panel) end
    for _, member in ipairs(group.members) do
        if member._nisClassic then return end
    end
    local ids = {}
    for _, member in ipairs(group.members) do
        if busy(member) then return end
        if member._nisPersistenceID then ids[#ids + 1] = member._nisPersistenceID end
    end
    if #ids == 0 then return end
    local changed = join(ids, group.active._nisPersistenceID or ids[1])
    local record = state.panels[ids[1]]
    local saved = record.group and state.groups[record.group]
    for _, panelID in ipairs(saved and saved.members or ids) do
        changed = geometry(state.panels[panelID], group.active.root) or changed
    end
    if changed then flush() end
end

-- Persist names and standalone bounds only, never native component handles.
function Persistence.native(panel, snapshot)
    local panelID = panel._nisPersistenceID
    if panel._nisClassic or WorldMap.isSuspended() or not panelID or restoring then return end
    local record = state.panels[panelID]
    local old = record.native
    local changed = geometry(record, snapshot.free)
    local same = old and old.frame == snapshot.frame and old.index == snapshot.index
        and old.beforeNative == snapshot.beforeNative
        and old.selected == snapshot.selected and #old.frames == #snapshot.frames
    if same then
        for index, frame in ipairs(snapshot.frames) do
            if old.frames[index] ~= frame then same = false; break end
        end
    end
    if changed or not same then
        record.native = snapshot
        flush()
    end
end

function Persistence.detach(panel)
    local panelID = panel._nisPersistenceID
    if panel._nisClassic or not panelID or restoring then return end
    local record = state.panels[panelID]
    local group = record.group and state.groups[record.group]
    local changed = record.group ~= nil or record.dockTo ~= nil or record.native ~= nil
    if group then
        for index, memberID in ipairs(group.members) do
            if memberID == panelID then table.remove(group.members, index); break end
        end
        if group.active == panelID then
            local selected
            for _, memberID in ipairs(group.members) do
                local member = live[memberID]
                if loaded(member) and not member._nisHidden then
                    selected = selected or memberID
                    if not member.root.hidden then selected = memberID; break end
                end
            end
            group.active = selected or group.members[1]
        end
        if #group.members < 2 then
            for _, memberID in ipairs(group.members) do state.panels[memberID].group = nil end
            state.groups[record.group] = nil
        end
    end
    record.group, record.dockTo, record.native = nil, nil, nil
    panel._nisNativePending = nil
    if loaded(panel) then changed = geometry(record, panel.root) or changed end
    if changed then flush() end
end

function Persistence.unregister(panel)
    local panelID = panel._nisPersistenceID
    if not panelID then return end
    if not panel._nisClassic and not state.panels[panelID].native then Persistence.bounds(panel) end
    live[panelID] = nil
    panel._nisPersistenceID = nil
end

return Persistence
