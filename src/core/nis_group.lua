local Tooltip = require("src/tooltip")
local NisTabs = require("src/core/nis_tabs")
local Persistence = require("src/core/nis_persistence")
local Components = require("src/core/components")
local sameComponent = Components.sameComponent
local NativeInterfaceSettings = require("src/core/native_interface_settings")
local WorldMap = require("src/core/world_map")
local NisGroup = {}

local panels = setmetatable({}, { __mode = "k" })
local nextOrder = 0
local previewTarget, previewSource

local function loaded(panel)
    return panel and not panel._destroyed and panel.root ~= nil
        and ui.Interfaces:GetInterface(panel.interfaceID) ~= nil
end

local function visible(panel)
    local ghost = panel and panel.dragState and panel.dragState.previewHidden
    return loaded(panel) and not panel._nisHidden and not panel.locked
        and (ghost and panel.parent.visibleGlobal ~= false
            or not panel.root.hidden and panel.root.visibleGlobal ~= false)
end

local function members(panel)
    return panel._nisGroup and panel._nisGroup.members or { panel }
end

local function limits(list)
    local minWidth, minHeight, maxWidth, maxHeight = 64, 49, math.huge, math.huge
    for _, panel in ipairs(list) do
        minWidth = math.max(minWidth, panel.minWidth)
        minHeight = math.max(minHeight, panel.minHeight)
        maxWidth = math.min(maxWidth, panel.maxWidth or math.huge)
        maxHeight = math.min(maxHeight, panel.maxHeight or math.huge)
    end
    if minWidth > maxWidth or minHeight > maxHeight then return nil end
    return minWidth, minHeight, maxWidth, maxHeight
end

local function refresh(group)
    -- Release every outgoing page before allocating the selected page's controls.
    for _, panel in ipairs(group.members) do
        if not panel._nisClassic and loaded(panel) and (panel ~= group.active or panel._nisHidden) then
            panel:_SyncContent(false)
        end
    end
    for _, panel in ipairs(group.members) do
        if loaded(panel) then
            if panel._nisClassic then
                Components.setHidden(panel.root, true)
            else
                local active = panel == group.active and not panel._nisHidden
                if not active then
                    if panel.content then Tooltip.hideContextTooltips(panel.content) end
                    panel._nisTabs:Refresh(nil)
                end
                Components.setHidden(panel.root, not active)
                panel:_SyncContent(active)
                panel:_SyncChrome()
                panel:_SyncOverlays(not active)
                if active then
                    panel._nisTabs:Refresh(group.members, group.active)
                    panel.root:MoveToFront()
                    panel:_SyncOverlays(false)
                end
            end
        end
    end
end

local function setLimits(group)
    local minWidth, minHeight, maxWidth, maxHeight = limits(group.members)
    group.minWidth, group.minHeight = minWidth, minHeight
    group.maxWidth, group.maxHeight = maxWidth, maxHeight
    for _, panel in ipairs(group.members) do
        if panel.resize then
            panel.resize.minWidth, panel.resize.minHeight = minWidth, minHeight
            panel.resize.maxWidth, panel.resize.maxHeight = maxWidth, maxHeight
            panel.resize:Refresh()
        end
    end
end

local function restoreLimits(panel)
    if panel.resize then
        panel.resize.minWidth, panel.resize.minHeight = panel.minWidth, panel.minHeight
        panel.resize.maxWidth = panel.maxWidth or math.huge
        panel.resize.maxHeight = panel.maxHeight or math.huge
        panel.resize:Refresh()
    end
end

local function notify(group)
    Persistence.capture(group.active)
    local snapshot = { table.unpack(group.members) }
    for _, panel in ipairs(snapshot) do
        if loaded(panel) and panel._nisGroup == group then panel:_NotifyBoundsChange() end
    end
end

local function apply(group, x, y, width, height, notifyCallbacks)
    if group.applying then return end
    group.applying = true
    local updating = group.updating or {}
    group.updating = updating
    for index, panel in ipairs(group.members) do
        updating[index] = panel._updatingBounds
        panel._updatingBounds = true
        if loaded(panel) then panel:_ApplyRectSingle(x, y, width, height) end
    end
    for index, panel in ipairs(group.members) do panel._updatingBounds = updating[index] end
    group.applying = nil
    if notifyCallbacks then notify(group) end
end

local function updateStandalone(panel)
    if not loaded(panel) then return end
    if panel._nisClassic then
        Components.setHidden(panel.root, true)
        return
    end
    Components.setHidden(panel.root, panel._nisHidden == true)
    panel:_LayoutBody()
    panel:_SyncContent(not panel._nisHidden)
    panel:RefreshRowBackgrounds()
    panel:_SyncChrome()
    panel:_SyncOverlays(panel.root.hidden)
    panel._nisTabs:Refresh(nil)
end

function NisGroup.register(panel)
    nextOrder = nextOrder + 1
    panel._nisOrder = nextOrder
    if panel._nisHidden == nil then panel._nisHidden = WorldMap.isHidden(panel.root) end
    panels[panel] = true
end

function NisGroup.clearPreview(source)
    if source ~= nil and previewSource ~= source then return end
    local target = previewTarget
    previewTarget, previewSource = nil, nil
    if loaded(target) and not target._nisClassic then
        local group = target._nisGroup
        target._nisTabs:Refresh(group and group.members or nil,
            group and group.active or target)
    end
end

function NisGroup.clearPanel(panel)
    if previewTarget == panel or previewSource == panel
        or previewTarget and previewTarget._nisGroup and previewTarget._nisGroup == panel._nisGroup
        or previewSource and previewSource._nisGroup and previewSource._nisGroup == panel._nisGroup then
        NisGroup.clearPreview()
    end
end

local function eligible(source, target, includeMembers)
    if source._nisNative or target._nisNative
        or not visible(source) or not visible(target) or source == target
        or not sameComponent(source.parent, target.parent)
        or source._nisGroup == target._nisGroup and source._nisGroup then
        return false
    end
    local sourceGroup, targetGroup = source._nisGroup, target._nisGroup
    if sourceGroup and sourceGroup.active ~= source then return false end
    if targetGroup and targetGroup.active ~= target then return false end
    local combined = includeMembers and {} or nil
    local minWidth, minHeight, maxWidth, maxHeight = 64, 49, math.huge, math.huge
    for side = 1, 2 do
        local owner = side == 1 and target or source
        local list = owner._nisGroup and owner._nisGroup.members
        for index = 1, list and #list or 1 do
            local panel = list and list[index] or owner
            if not loaded(panel) or panel.locked or panel._nisHidden then return false end
            minWidth = math.max(minWidth, panel.minWidth)
            minHeight = math.max(minHeight, panel.minHeight)
            maxWidth = math.min(maxWidth, panel.maxWidth or math.huge)
            maxHeight = math.min(maxHeight, panel.maxHeight or math.huge)
            if combined then combined[#combined + 1] = panel end
        end
    end
    if minWidth > maxWidth or minHeight > maxHeight then return false end
    local root = target.root
    if root.width < minWidth or root.width > maxWidth
        or root.height < minHeight or root.height > maxHeight then return false end
    return true, combined
end

function NisGroup.candidate(source, x, y)
    local best, order
    for target in pairs(panels) do
        if target ~= source and target._nisOrder > (order or 0)
            and visible(target) and target._nisTabs:Contains(x, y) and eligible(source, target) then
            best, order = target, target._nisOrder
        end
    end
    return best
end

function NisGroup.preview(source, target)
    if not target and not previewTarget then return end
    if previewTarget == target and previewSource == source then return end
    NisGroup.clearPreview()
    if not target or not eligible(source, target) then return end
    previewTarget, previewSource = target, source
    target._nisTabs:Refresh(members(target), target._nisGroup and target._nisGroup.active or target, source)
end

function NisGroup.select(panel)
    local group = panel._nisGroup
    if not group or group.active == panel or not loaded(panel) or panel._nisHidden then return end
    local active = group.active
    local press = active._nisTabPress
    if press and press.member ~= panel then active:_CancelDrag() end
    if active.dragState then active:_CancelDrag() end
    if active.resize and active.resize.dragState then
        active.resize:Cancel()
        notify(group)
    end
    group = panel._nisGroup
    if not group or group.active == panel or not loaded(panel) or panel._nisHidden then return end
    NisGroup.clearPanel(panel)
    active = group.active
    local oldView, newView = active._nisTabs, panel._nisTabs
    active._nisTabs, panel._nisTabs = newView, oldView
    newView.panel, oldView.panel = active, panel
    group.active = panel
    refresh(group)
    Persistence.capture(panel)
end

function NisGroup.reorder(panel, pointerX)
    local group = panel._nisGroup
    if not group or group.active ~= panel or not loaded(panel) then return false end
    if NativeInterfaceSettings.isLocked() then return false end
    for _, member in ipairs(group.members) do
        if member.locked then return false end
    end
    local view = panel._nisTabs
    local first = view.tabs[1] and view.tabs[1].member
    local firstIndex, sourceIndex = 1, nil
    for index, member in ipairs(group.members) do
        if member == first then firstIndex = index end
        if member == panel then sourceIndex = index end
    end
    if not sourceIndex then return false end
    local slot = math.floor((pointerX - panel.root.x - 4) / NisTabs.WIDTH)
    local destination = math.max(1, math.min(#group.members, firstIndex + slot))
    if sourceIndex == destination then return false end
    table.remove(group.members, sourceIndex)
    table.insert(group.members, destination, panel)
    view:Refresh(group.members, panel)
    return true
end

function NisGroup.dock(source, target, notifyCallbacks)
    local ok, combined = eligible(source, target, true)
    if not ok then return false end
    NisGroup.clearPreview()
    local sourceGroup, targetGroup = source._nisGroup, target._nisGroup
    local targetRoot = target.root
    local x, y, width, height = targetRoot.x, targetRoot.y, targetRoot.width, targetRoot.height
    if sourceGroup then
        for _, panel in ipairs(sourceGroup.members) do panel._nisGroup = nil end
        sourceGroup.members = {}
        sourceGroup.active = nil
    end
    local group = targetGroup or { members = { target }, active = target }
    if not targetGroup then target._nisGroup = group end
    for _, panel in ipairs(combined) do
        if panel ~= target and panel._nisGroup ~= group then
            group.members[#group.members + 1] = panel
            panel._nisGroup = group
        end
    end
    group.active = source
    setLimits(group)
    apply(group, x, y, width, height, false)
    refresh(group)
    if notifyCallbacks ~= false then notify(group) end
    return true
end

function NisGroup.undock(panel)
    local group = panel._nisGroup
    if not group then return end
    NisGroup.clearPanel(panel)
    for index, member in ipairs(group.members) do
        if member == panel then table.remove(group.members, index); break end
    end
    panel._nisGroup = nil
    restoreLimits(panel)
    updateStandalone(panel)
    if group.active == panel then group.active = group.members[1] end
    if #group.members == 1 then
        local survivor = group.members[1]
        survivor._nisGroup = nil
        restoreLimits(survivor)
        updateStandalone(survivor)
    elseif #group.members > 1 then
        setLimits(group)
        refresh(group)
    end
    group.members = #group.members > 1 and group.members or {}
end

function NisGroup.unregister(panel)
    NisGroup.clearPanel(panel)
    NisGroup.undock(panel)
    panels[panel] = nil
end

function NisGroup.apply(panel, x, y, width, height, notifyCallbacks)
    local group = panel._nisGroup
    if group then
        apply(group, x, y, width, height, notifyCallbacks)
    else
        panel:_ApplyRectSingle(x, y, width, height)
        if notifyCallbacks then panel:_NotifyBoundsChange() end
    end
end

function NisGroup.boundsChanged(panel)
    local group = panel._nisGroup
    if not group or group.applying then return false end
    local root = panel.root
    apply(group, root.x, root.y, root.width, root.height, true)
    return true
end

function NisGroup.limits(panel)
    local group = panel._nisGroup
    if group then return group.minWidth, group.minHeight, group.maxWidth, group.maxHeight end
    return panel.minWidth, panel.minHeight, panel.maxWidth, panel.maxHeight
end

function NisGroup.notify(panel)
    if panel._nisGroup then notify(panel._nisGroup) end
end


function NisGroup.snapshot(panel)
    local group = panel._nisGroup
    if not group then return nil end
    local root = group.active.root
    return {
        members = { table.unpack(group.members) },
        active = group.active,
        x = root.x, y = root.y, width = root.width, height = root.height,
    }
end

-- Rejoin a live peer's current group without losing tabs added while disabled.
-- Identified panels use the persistent logical group instead of these handles.
function NisGroup.resume(panel, snapshot)
    local anchor
    for _, peer in ipairs(snapshot.members) do
        if peer ~= panel and loaded(peer) and not peer._nisHidden and not peer._nisNative
            and sameComponent(peer.parent, panel.parent) then
            anchor = peer
            break
        end
    end
    if not anchor then return false end
    local current = anchor._nisGroup and anchor._nisGroup.members or { anchor }
    local included, ordered = { [panel] = true }, {}
    for _, peer in ipairs(current) do included[peer] = true end
    for _, peer in ipairs(snapshot.members) do
        if included[peer] then
            ordered[#ordered + 1] = peer
            included[peer] = nil
        end
    end
    for _, peer in ipairs(current) do
        if included[peer] then ordered[#ordered + 1] = peer end
    end
    local root = anchor.root
    return NisGroup.restore({
        members = ordered, active = panel,
        x = root.x, y = root.y, width = root.width, height = root.height,
    }, false)
end

function NisGroup.restore(snapshot, notifyCallbacks)
    if not snapshot then return false end
    local owner = snapshot.members[1]
    for _, panel in ipairs(snapshot.members) do
        if not loaded(panel) or panel._nisHidden or not sameComponent(panel.parent, owner.parent) then
            return false
        end
    end
    local minWidth, minHeight, maxWidth, maxHeight = limits(snapshot.members)
    if not minWidth then return false end
    local width = math.max(minWidth, math.min(maxWidth, snapshot.width))
    local height = math.max(minHeight, math.min(maxHeight, snapshot.height))
    local x = math.max(0, math.min(snapshot.x, owner.parent.width - width))
    local y = math.max(0, math.min(snapshot.y, owner.parent.height - height))
    for _, panel in ipairs(snapshot.members) do NisGroup.undock(panel) end
    local group = { members = snapshot.members, active = snapshot.active }
    for _, panel in ipairs(group.members) do panel._nisGroup = group end
    setLimits(group)
    apply(group, x, y, width, height, false)
    refresh(group)
    if notifyCallbacks ~= false then notify(group) end
    return true
end

return NisGroup
