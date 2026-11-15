-- Native docking coordinator: public operations, membership and saved restoration.
local Components = require("src/core/components")
local Sprites = require("src/core/sprites")
local Persistence = require("src/nis/persistence")
local NisGroup = require("src/nis/group")
local NativeInterfaceSettings = require("src/core/native_interface_settings")
local WorldMap = require("src/core/world_map")

local Native = {}
local groups, byFrame = {}, {}
local pending = {} -- Panel -> earliest native logic sequence for restoration.
local restoring = false
local restorePending, finishGroup, Runtime
local nextHook = 0
local art = Sprites.NIS_PANEL

local function warn(message)
    if type(log) == "function" then pcall(function() log("PrettyUI native docking: " .. tostring(message)) end) end
end

local Host = require("src/nis/native_host").new(byFrame)
local View = require("src/nis/native_view").new(Host, {
    sync = function(panel) return Native.sync(panel) end,
    select = function(panel) return Native.select(panel) end,
    isRestoringBatch = function() return Runtime.restoringBatch end,
})
local Sort = require("src/nis/native_sort").new(Host, View, warn)
local Reconcile = require("src/nis/native_reconcile").new(Host, View, Sort, byFrame, {
    sync = function(panel) return Native.sync(panel) end,
    logicSequence = function() return Runtime.logicSequence end,
    warn = warn,
})
local Preview = require("src/nis/native_preview").new(Host, View, {
    startTick = function() Runtime.start() end,
    stopTick = function() Runtime.stop() end,
})

local saveGroup
Runtime = require("src/nis/native_runtime").new(Host, View, Sort, Reconcile, Preview, groups, pending, {
    restorePending = function(panel) restorePending(panel) end,
    saveGroup = function(group) saveGroup(group) end,
    finishGroup = function(group) return finishGroup(group) end,
    remember = function(panel) return Native.remember(panel) end,
    detach = function(panel) return Native.detach(panel) end,
    select = function(panel) return Native.select(panel) end,
    sync = function(panel) return Native.sync(panel) end,
    warn = warn,
})

local identity = Host.identity
local component = Host.component
local same = Host.same
local live = Host.live
local mapReady = Host.mapReady
local editingLocked = Host.editingLocked
local applyLayout = Host.applyLayout
local tabBand = Host.tabBand
local tabOrigin = Host.tabOrigin
local tabScroll = Host.tabScroll
local capture = Host.capture
local nativeRootsFor = Host.nativeRootsFor
local discover = Host.discover
local related = Host.related
local resolve = Host.resolve
local frameGroup = Host.frameGroup
local selectedFrame = Host.selectedFrame
local rectInParent = Host.rectInParent
local freeRect = Host.freeRect
local captureAt = Host.captureAt
local captureHiddenGroup = Host.captureHiddenGroup
local indexSpecs = Host.indexSpecs
local validHost = Host.validHost
local HEIGHT = Host.HEIGHT
local WIDTH = Host.WIDTH
local conceal = View.conceal
local nativePage = View.nativePage
local borrow = View.borrow
local destroyTab = View.destroyTab
local newTab = View.newTab
local beforeNative = View.beforeNative
local insertionAt = View.insertionAt
local startSlides = View.startSlides
local align = View.align
local raiseGroup = View.raiseGroup
local presentNativeSort = Sort.presentNativeSort
local finishNativeSort = Sort.finishNativeSort
local syncObservers = Sort.syncObservers
local createHost = Reconcile.createHost
local reconcile = Reconcile.reconcile
local moveActive = Reconcile.moveActive
local reconcilePage = Reconcile.reconcilePage
local reconcileLock = Reconcile.reconcileLock
local reconcileRoots = Reconcile.reconcileRoots
local specByID = Host.specByID

function Native.candidate(panel, x, y)
    if WorldMap.isSuspended() or NativeInterfaceSettings.isClassicUI()
        or panel and panel._nisClassic then return nil end
    if not panel or panel._nisNative or not panel.root or panel.locked
        or not ui.Interfaces:GetInterface(panel.interfaceID) then return nil end
    local area = component(id.Component.TOPLEVEL_V2__GAME_AREA)
    if not area then return nil end
    if not same(panel.parent, area) then return nil end
    local origin = panel.parent.xyGlobal
    local px, py = origin.x + x, origin.y + y
    indexSpecs()
    local found, grouped
    for _, spec in pairs(specByID) do
        local ok, host = pcall(captureAt, spec, area, px, py)
        if ok and host then
            found = found or {}
            found[#found + 1] = host
            grouped = grouped or host.grouped
        end
    end
    if not found then return nil end
    -- Only grouped candidates need hidden frame copies for signature/capacity
    -- checks. Unrelated visible rows and hidden standalone pages need no capture.
    if grouped then
        for _, spec in pairs(specByID) do
            local ok, host = pcall(captureHiddenGroup, spec, area)
            if ok and host then found[#found + 1] = host end
        end
    end
    local best
    for _, host in ipairs(found) do
        if host.frame.visibleGlobal then
            local band = tabBand(host)
            local top = band.xyGlobal
            local targetY = host.grouped and top.y or host.frame.xyGlobal.y
            if px >= top.x and px < top.x + band.width
                and py >= targetY and py < top.y + HEIGHT then
                local occupied = frameGroup(host)
                local capacity = not (occupied and occupied.nativeSort)
                local height = host.content.height - (host.grouped and 0 or HEIGHT)
                for _, member in ipairs(panel._nisGroup and panel._nisGroup.members or { panel }) do
                    if host.content.width < member.minWidth or height < member.minHeight
                        or host.content.width > (member.maxWidth or math.huge)
                        or height > (member.maxHeight or math.huge) then capacity = false end
                end
                if capacity
                    and (occupied or not host.content.hidden and (not host.scroll or not host.scroll.hidden))
                    and (occupied or host.grouped or nativeRootsFor(host)) then
                    if best then return nil end
                    best = host
                end
            end
        end
    end
    return best
end

function Native.rect(panel, host)
    indexSpecs()
    local spec = specByID[resolve(host)]
    if not spec then return nil end
    local frame = component(spec.frame)
    if not frame or not panel or not panel.parent then return nil end
    local x, y, width, height = rectInParent(panel, frame)
    return { x = x, y = y, width = width, height = height }
end

function Native.remember(panel, frames, index)
    local binding = panel._nisNative
    if not binding then return nil end
    local group = binding.group
    if not frames then
        frames = {}
        for _, host in pairs(group.frames) do frames[#frames + 1] = host.spec.name end
        table.sort(frames)
    end
    if not index then
        for position, member in ipairs(group.members) do
            if member == panel then index = position; break end
        end
    end
    return {
        frame = group.hosts[group.current].spec.name, frames = frames,
        index = index, beforeNative = binding.beforeNative,
        selected = group.active == panel, free = binding.free,
    }
end

saveGroup = function(group)
    if WorldMap.isSuspended() then return end
    if restoring or group.attaching or group.tabDrag or group.nativeSort or group.dockPreview then return end
    for _, member in ipairs(group.members) do
        if member._nisNativeTransaction then return end
    end
    local frames = {}
    for _, host in pairs(group.frames) do frames[#frames + 1] = host.spec.name end
    table.sort(frames)
    for index, panel in ipairs(group.members) do
        Persistence.native(panel, Native.remember(panel, frames, index))
    end
end

local function removeGroup(group)
    group.dead = true
    for key in pairs(group.frames) do
        if byFrame[key] == group then byFrame[key] = nil end
    end
    for index, member in ipairs(groups) do
        if member == group then table.remove(groups, index); break end
    end
    Runtime.stop()
end

finishGroup = function(group)
    if not Reconcile.releaseGroup(group) then return false end
    removeGroup(group)
    return true
end

Native.clearPreview = Preview.clear
Native.preview = Preview.show

local function buildGroup(host, area)
    local found = discover(area)
    local hosts = {}
    for _, other in ipairs(found) do
        if related(host, other) then
            if byFrame[other.key] then return nil end
            hosts[#hosts + 1] = other
        end
    end
    if #hosts == 0 then return nil end
    local current
    for i, item in ipairs(hosts) do
        if item.frame.visibleGlobal then
            if current then return nil end
            current = i
        end
    end
    if not current then return nil end
    local group = { area = area, owner = host.owner,
        hosts = hosts, frames = {}, members = {}, bindings = {}, hooks = {}, hookKeys = {},
        grouped = host.grouped, current = current }
    for _, item in ipairs(hosts) do group.frames[item.key] = { key = item.key, spec = item.spec } end
    if not host.grouped then
        group.nativeRoots = nativeRootsFor(host)
        if not group.nativeRoots then return nil end
        if host.spec.name == "TOPLEVEL_V2__LORE_WINDOW" then
            group.familiarUnavailable = component(host.spec.EDIT_BLOCK).visible == true
        end
    end
    return group
end

local function abandonMember(group, panel)
    local binding = group.bindings[panel]
    if not binding then return end
    if group.tabDrag then
        group.tabDrag = nil
        for _, member in ipairs(group.members) do
            for _, tab in ipairs(group.bindings[member].tabs) do tab.slideX = nil end
        end
    end
    for _, tab in ipairs(binding.tabs) do destroyTab(tab) end
    group.bindings[panel] = nil
    for index, member in ipairs(group.members) do
        if member == panel then table.remove(group.members, index); break end
    end
    panel._nisNative = nil
    local nativeOK, nativeError = true, nil
    if group.active == panel then nativeOK, nativeError = pcall(nativePage, group) end
    if panel.root and ui.Interfaces:GetInterface(panel.interfaceID) then
        local rect = binding.free
        panel.root:SetPos(rect.x, rect.y)
        panel.root:SetSize(rect.width, rect.height)
        panel.width, panel.height = rect.width, rect.height
        Components.setHidden(panel.root, panel._nisHidden == true)
        panel.root.enabled = true
        if panel.dragBounds then
            panel.dragBounds:Clamp()
            panel.dragBounds:RememberPosition()
        end
        if panel._scroll then panel._scroll:_RefreshClipTargets() end
        panel:_LayoutBody()
        panel:_SyncContent(not panel._nisHidden)
        panel:RefreshRowBackgrounds()
        if not panel.root.hidden then panel.root:MoveToFront() end
        panel:_SyncChrome()
        panel:_SyncOverlays(panel.root.hidden)
        panel:_NotifyBoundsChange()
    end
    if not nativeOK then error(nativeError) end
end

function Native.detach(panel)
    if panel and not restoring then
        panel._nisNativePending, panel._nisNativeActivating, pending[panel] = nil, nil, nil
        Runtime.stop()
    end
    local binding = panel and panel._nisNative
    if not binding then return false end
    local group = binding.group
    panel._nisNativeDetaching = true
    local ok, problem = pcall(abandonMember, group, panel)
    panel._nisNativeDetaching = nil
    if not ok then warn(problem); group.failure = problem; return false end
    if #group.members == 0 then return finishGroup(group) end
    for _, host in ipairs(group.hosts) do
        if host.nativeTab then host.nativeTab.member = group.members[1] end
    end
    if group.nativeSort then
        -- A member may be destroyed mid-gesture. The remaining mixed row must
        -- not retain that panel's visual or insertion snapshot.
        local sort = group.nativeSort
        for index = #sort.row, 1, -1 do
            if sort.row[index].panel == panel then table.remove(sort.row, index) end
        end
        for index = #sort.originalRow, 1, -1 do
            if sort.originalRow[index].panel == panel then table.remove(sort.originalRow, index) end
        end
        sort.before[panel] = nil
        for index = #sort.members, 1, -1 do
            if sort.members[index] == panel then table.remove(sort.members, index) end
        end
        presentNativeSort(group)
        return true
    end
    if selectedFrame(group) then
        local valid, issue = pcall(align, group)
        if not valid then warn(issue); group.failure = issue end
        return valid
    end
    return true
end
local function attach(panel, group, free)
    local binding = { group = group, free = free or freeRect(panel), tabs = {} }
    if #group.members == 0 then group.locked = panel.locked end
    group.members[#group.members + 1] = panel
    group.bindings[panel] = binding
    panel._nisNative = binding
    for index, host in ipairs(group.hosts) do
        binding.tabs[index] = newTab(group, host, panel, panel.tabIcon or art.defaultIcon, false)
    end
    if not group.grouped and #group.members == 1 then
        for _, host in ipairs(group.hosts) do
            host.nativeTab = newTab(group, host, panel, host.nativeIcon, true)
        end
    end
    return binding
end

local function dock(panel, target, savedFree, insertion)
    if NativeInterfaceSettings.isClassicUI() or panel and panel._nisClassic then return false end
    if not panel or panel._nisNative or panel.locked and not restoring or not panel.root
        or not ui.Interfaces:GetInterface(panel.interfaceID) then return false end
    local area = component(id.Component.TOPLEVEL_V2__GAME_AREA)
    if not area then return false end
    if not same(panel.parent, area) then return false end
    indexSpecs()
    local key = resolve(target)
    local spec = specByID[key]
    if not spec then return false end
    local okCapture, host = pcall(capture, spec, area, true)
    if not okCapture or not host or not host.frame.visibleGlobal then return false end
    local group = frameGroup(host)
    if group and (group.failure or group.nativeSort or not live(group)
        or group.grouped ~= host.grouped) then return false end
    if group then
        local refreshed, settled = pcall(reconcile, group)
        if not refreshed or settled == nil or group.failure or not byFrame[host.key] then return false end
    end
    if not group and (host.content.hidden or host.scroll and host.scroll.hidden) then return false end
    if not group then group = buildGroup(host, area) end
    if not group then return false end
    local members = panel._nisGroup and { table.unpack(panel._nisGroup.members) } or { panel }
    for _, member in ipairs(members) do
        if member._nisClassic or member._nisNative or member.locked and not restoring
            or member._nisHidden or not member.root or not same(member.parent, panel.parent)
            or not ui.Interfaces:GetInterface(member.interfaceID) then return false end
    end
    for _, item in ipairs(group.hosts) do
        local height = item.content.height - (group.grouped and 0 or HEIGHT)
        for _, member in ipairs(members) do
            if item.content.width < member.minWidth or height < member.minHeight
                or item.content.width > (member.maxWidth or math.huge)
                or height > (member.maxHeight or math.huge) then return false end
        end
    end
    local oldGroup = NisGroup.snapshot(panel)
    local frees = {}
    for index, member in ipairs(members) do frees[index] = member == panel and savedFree or freeRect(member) end
    local created = #group.members == 0
    group.attaching = true
    local success, problem = pcall(function()
        if created then
            nextHook = nextHook + 1
            group.hookID = "prettyui_nis_native_" .. nextHook
            groups[#groups + 1] = group
            for _, item in ipairs(group.hosts) do
                byFrame[item.key] = group
                item.flags = {} -- cleanup is valid even before chrome construction
            end
            if group.nativeRoots then
                for _, saved in ipairs(group.nativeRoots) do
                    saved.changed = true -- setters can partially apply before throwing
                    applyLayout(saved.component, saved.inset)
                end
            end
            for _, item in ipairs(group.hosts) do createHost(group, item) end
        end
        for index, member in ipairs(members) do
            if member._nisGroup then NisGroup.undock(member) end
            if not restoring then Persistence.detach(member) end
            attach(member, group, frees[index])
        end
        if insertion then
            for index, member in ipairs(members) do
                local binding = group.bindings[member]
                binding.beforeNative = insertion.beforeNative
                for position, candidate in ipairs(group.members) do
                    if candidate == member then table.remove(group.members, position); break end
                end
                table.insert(group.members, math.min(insertion.index + index - 1, #group.members + 1), member)
            end
        end
        Runtime.start()
        align(group)
        assert(Native.select(panel), "native page selection failed")
        group.attaching = nil
        align(group)
    end)
    group.attaching = nil
    if not success then
        if group.constructingTab then
            local cleanupOK, cleanupError = pcall(destroyTab, group.constructingTab)
            if not cleanupOK then warn(cleanupError) end
            group.constructingTab = nil
        end
        warn(problem)
        for _, member in ipairs(members) do
            if member._nisNative and member._nisNative.group == group then Native.detach(member) end
        end
        if created and #group.members == 0 and not group.dead then finishGroup(group) end
        if oldGroup then NisGroup.restore(oldGroup, false) end
        return false
    end
    saveGroup(group)
    return true
end

function Native.dock(panel, target, savedFree, insertion)
    if WorldMap.isSuspended() or NativeInterfaceSettings.isClassicUI()
        or panel and panel._nisClassic then return false end
    return dock(panel, target, savedFree, insertion)
end

-- Rebind by named host identity once the native layout is available. Startup
-- restoration is allowed while locked; explicit docking still is not.
restorePending = function(panel)
    if WorldMap.isSuspended() or NativeInterfaceSettings.isClassicUI()
        or panel._nisClassic then return end
    local snapshot = panel._nisNativePending
    if not snapshot or panel._nisHidden or panel._nisGroup then return end
    restoring = true
    local ok, restored = pcall(function()
        local targets = { snapshot.frame }
        for _, name in ipairs(snapshot.frames) do
            if name ~= snapshot.frame then targets[#targets + 1] = name end
        end
        for _, name in ipairs(targets) do
            local target = component(id.Component[name])
            if target and target.visibleGlobal then
                local previous = byFrame[identity(target)]
                local active = previous and previous.active
                if dock(panel, target, snapshot.free) then
                    local binding = panel._nisNative
                    local group = binding.group
                    binding.restoreIndex = snapshot.index
                    binding.beforeNative = snapshot.beforeNative
                    if panel._nisNativeActivating then
                        for index, member in ipairs(group.members) do
                            if member == panel then table.remove(group.members, index); break end
                        end
                        table.insert(group.members, math.min(snapshot.index, #group.members + 1), panel)
                    else
                        table.sort(group.members, function(a, b)
                            local first, second = beforeNative(group, a, group.hosts[group.current]),
                                beforeNative(group, b, group.hosts[group.current])
                            if first ~= second then return first < second end
                            return (group.bindings[a].restoreIndex or math.huge)
                                < (group.bindings[b].restoreIndex or math.huge)
                        end)
                    end
                    if panel._nisNativeActivating or snapshot.selected then
                        Native.select(panel)
                    elseif active then
                        Native.select(active)
                    else
                        nativePage(group)
                        align(group)
                    end
                    return true
                end
            end
        end
        return false
    end)
    restoring = false
    if ok and restored then
        panel._nisNativePending, panel._nisNativeActivating, pending[panel] = nil, nil, nil
    elseif not ok then
        warn(restored)
    end
end

function Native.register(panel, activating, delayTicks)
    if NativeInterfaceSettings.isClassicUI() or panel._nisClassic
        or not panel._nisNativePending then return end
    panel._nisNativeActivating = activating == true
    local delay = delayTicks or 0
    pending[panel] = Runtime.logicSequence + delay
    Runtime.start()
    if delay == 0 then restorePending(panel) end
end

function Native.lockChanged(panel, locked)
    local binding = panel._nisNative
    if not binding then return end
    local group = binding.group
    if group.locked ~= locked then
        group.locked, group.lockTransition = locked, true
        if not WorldMap.isSuspended() then
            finishNativeSort(group, nil, true)
            local ok, problem = pcall(syncObservers, group)
            if not ok then group.failure = problem end
        end
        for _, host in ipairs(group.hosts) do host.tabReset = true end
        if group.nativeRoots then
            for _, saved in ipairs(group.nativeRoots) do saved.baselineReset = true end
        end
        for _, member in ipairs(group.members) do
            for _, tab in ipairs(group.bindings[member].tabs) do tab.shown = false end
        end
    end
end

function Native.select(panel)
    local binding = panel and panel._nisNative
    if not binding then return false end
    local group = binding.group
    if WorldMap.isSuspended() then
        group.mapSelection = panel
        return true
    end
    if panel._nisTopLevelHidden then return false end
    if group.nativeSort then return false end
    local ok, selected = pcall(function()
        local changed = reconcile(group)
        if changed == nil then return false end
        local current = selectedFrame(group)
        if not current then return false end
        if not validHost(group, group.hosts[current]) then error("native frame unavailable") end
        reconcileRoots(group)
        if group.pending then
            nativePage(group)
        elseif group.active and (group.needsConceal
            or not changed and group.transient and current ~= group.current) then
            moveActive(group, current)
        elseif not changed and group.current ~= current and not group.lockTransition then
            nativePage(group)
        end
        group.transient = nil
        reconcileLock(group, current)
        local host = group.hosts[current]
        if not group.active then
            if group.grouped then borrow(group, host) end
            conceal(group, host)
        end
        group.active, group.current = panel, current
        group.revealTab = panel
        reconcilePage(group, current)
        align(group)
        -- Show first; only reorder GAME_AREA siblings, never native artwork.
        raiseGroup(group)
        saveGroup(group)
        return true
    end)
    if not ok then group.failure = selected; warn(selected); return false end
    return selected
end

function Native.sync(panel)
    if WorldMap.isSuspended() then return false end
    local binding = panel and panel._nisNative
    if not binding then return false end
    local group = binding.group
    if panel._nisTopLevelHidden or group.mapPaused and not mapReady(group) then return false end
    local ok, problem = pcall(function()
        if group.nativeSort then return end
        if reconcile(group) == nil then return end
        if group.pending then nativePage(group) end
        local current = selectedFrame(group)
        if not current then return end
        local rootReflow = reconcileRoots(group)
        if group.active and group.needsConceal then moveActive(group, current) end
        local lockReflow = reconcileLock(group, current)
        local repainted = reconcilePage(group, current)
        align(group)
        if lockReflow or repainted or rootReflow then raiseGroup(group) end
        saveGroup(group)
    end)
    if not ok then group.failure = problem; warn(problem); return false end
    return true
end
-- Native relative order remains client-owned; PrettyUI insertion points are
-- presentation offsets, applied to native artwork and its real input together.
function Native.reorder(panel, pointerX, gripX)
    if WorldMap.isSuspended() then return false end
    local binding = panel and panel._nisNative
    if not binding or type(pointerX) ~= "number" or type(gripX) ~= "number" then return false end
    local group = binding.group
    if group.nativeSort or editingLocked(group) then return false end
    local current = selectedFrame(group)
    if not current then return false end
    local host = group.hosts[current]
    local frameX = rectInParent(panel, host.frame)
    local stripX = frameX + tabOrigin(host) - tabScroll(host)
    local drag = group.tabDrag
    if drag and drag.panel ~= panel then return false end
    if not drag then
        drag = { panel = panel }
        group.tabDrag = drag
        startSlides(group)
    end
    drag.x = math.floor(pointerX - gripX + 0.5)
    local before, destination, sourceIndex = insertionAt(group, host, drag.x - stripX + WIDTH / 2, panel)
    table.remove(group.members, sourceIndex)
    binding.beforeNative = before
    table.insert(group.members, destination, panel)
    align(group)
    local tab = binding.tabs[current]
    if tab.visual then tab.visual:MoveToFront() end
    return true
end

-- Finishing with the press-time snapshot cancels both reorder and selection.
-- Finishing without one commits the order (unless a tear-out transaction is
-- still pending); detached tab input remains owned by the press/capture.
function Native.finishTabDrag(panel, snapshot)
    local binding = panel and panel._nisNative
    if not binding then return false end
    local group = binding.group
    if group.tabDrag and group.tabDrag.panel ~= panel then return false end
    group.tabDrag = nil
    if snapshot then binding.beforeNative = snapshot.beforeNative end
    if snapshot and snapshot.index then
        for index, member in ipairs(group.members) do
            if member == panel then
                table.remove(group.members, index)
                table.insert(group.members, math.min(snapshot.index, #group.members + 1), panel)
                break
            end
        end
    end
    for _, member in ipairs(group.members) do
        for _, tab in ipairs(group.bindings[member].tabs) do tab.slideX = nil end
    end
    for _, host in ipairs(group.hosts) do
        if host.nativeTab then host.nativeTab.slideX = nil end
    end
    if snapshot then
        local active = snapshot.active
        if active and group.bindings[active] then
            if group.active ~= active then return Native.select(active) end
        elseif not active then
            nativePage(group)
        end
    end
    local current = selectedFrame(group)
    if current then align(group) end
    saveGroup(group)
    return true
end

local function occupiedBounds(panel, group, host)
    local band = tabBand(host)
    local origin, parentOrigin = band.xyGlobal, panel.parent.xyGlobal
    local left = origin.x - parentOrigin.x
    local width = math.min(host.used + #group.members * WIDTH, host.overflow.width)
    if not host.grouped then left = left + host.overflow.x - band.x end
    return left, origin.y - parentOrigin.y, width, HEIGHT
end

function Native.contains(panel, x, y)
    local binding = panel and panel._nisNative
    if not binding then return false end
    local group = binding.group
    local current = selectedFrame(group)
    local host = current and group.hosts[current]
    if not host then return false end
    local left, top, width, height = occupiedBounds(panel, group, host)
    return x >= left and x < left + width
        and y >= top and y < top + height
end

function Native.snapshot(panel)
    local binding = panel and panel._nisNative
    if not binding then return nil end
    local group, index = binding.group, nil
    for i, member in ipairs(group.members) do
        if member == panel then index = i; break end
    end
    local frames = {}
    for _, host in pairs(group.frames) do frames[#frames + 1] = host.spec.frame end
    local current = selectedFrame(group) or group.current
    local x, y, width, height = occupiedBounds(panel, group, group.hosts[current])
    return { frame = group.hosts[current].spec.frame, frames = frames, index = index,
        beforeNative = binding.beforeNative,
        free = { x = binding.free.x, y = binding.free.y,
            width = binding.free.width, height = binding.free.height },
        selected = group.active == panel, active = group.active,
        tabBounds = { x = x, y = y, width = width, height = height } }
end

function Native.restore(panel, snapshot)
    if not snapshot or panel._nisNative then return false end
    if not Native.dock(panel, snapshot.frame, snapshot.free) then
        local restored = false
        for _, frame in ipairs(snapshot.frames) do
            if frame ~= snapshot.frame and Native.dock(panel, frame, snapshot.free) then
                restored = true
                break
            end
        end
        if not restored then return false end
    end
    local group = panel._nisNative.group
    panel._nisNative.beforeNative = snapshot.beforeNative
    if snapshot.index then
        for index, member in ipairs(group.members) do
            if member == panel then
                table.remove(group.members, index)
                table.insert(group.members, math.min(snapshot.index, #group.members + 1), panel)
                break
            end
        end
    end
    if snapshot.active and group.bindings[snapshot.active] then
        return Native.select(snapshot.active)
    end
    if not snapshot.active then
        nativePage(group)
    elseif snapshot.selected then
        return Native.select(panel)
    end
    return Native.sync(panel)
end

function Native.shutdown()
    Native.clearPreview()
    for panel in pairs(pending) do
        panel._nisNativePending = nil
        pending[panel] = nil
    end
    local complete = true
    local existing = { table.unpack(groups) }
    for _, group in ipairs(existing) do
        local members = { table.unpack(group.members) }
        for _, panel in ipairs(members) do
            if not Native.detach(panel) then complete = false end
        end
        if not group.dead and #group.members == 0 and not finishGroup(group) then
            complete = false
        end
    end
    -- Shutdown restores native state, but keeps persisted named memberships.
    Runtime.shutdown()
    return complete
end

WorldMap.watch(Native, function(suspended)
    if not suspended then return end
    for _, group in ipairs(groups) do
        group.mapPaused, group.lockTransition = true, true
        if group.nativeSort then group.nativeSort.mapCancelled = true end
        for _, host in ipairs(group.hosts) do host.tabReset = true end
        for _, saved in ipairs(group.nativeRoots or {}) do saved.baselineReset = true end
    end
end)

return Native
