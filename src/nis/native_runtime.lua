-- Owns native Logic/Draw subscriptions and restoration-batch timing.
local WorldMap = require("src/core/world_map")
local NativeInterfaceSettings = require("src/core/native_interface_settings")

local NativeRuntime = {}

function NativeRuntime.new(Host, View, Sort, Reconcile, Preview, groups, pending, actions)
    local Runtime = { logicSequence = 0, restoringBatch = false }
    local subscribed = false
    local EVENT_ID = "prettyui_nis_native"
    local warn = actions.warn

    local identity = Host.identity
    local component = Host.component
    local same = Host.same
    local live = Host.live
    local mapReady = Host.mapReady
    local editingLocked = Host.editingLocked
    local tabOrigin = Host.tabOrigin
    local selectedFrame = Host.selectedFrame
    local checkCapacity = Host.checkCapacity
    local validHost = Host.validHost
    local nativePage = View.nativePage
    local suspend = View.suspend
    local nativeOffset = View.nativeOffset
    local previewOffset = View.previewOffset
    local ownX = View.ownX
    local slide = View.slide
    local align = View.align
    local raiseGroup = View.raiseGroup
    local presentNativeSort = Sort.presentNativeSort
    local stopSortInputs = Sort.stopSortInputs
    local finishNativeSort = Sort.finishNativeSort
    local syncClientSort = Sort.syncClientSort
    local nativeSortReady = Sort.nativeSortReady
    local syncObservers = Sort.syncObservers
    local reconcile = Reconcile.reconcile
    local moveActive = Reconcile.moveActive
    local reconcilePage = Reconcile.reconcilePage
    local reconcileLock = Reconcile.reconcileLock
    local reconcileRoots = Reconcile.reconcileRoots
    local nativeRowChanged = Reconcile.nativeRowChanged

    function Runtime.stop()
        if subscribed and #groups == 0 and next(pending) == nil and not Preview.active() then
            Event.Logic.Unsubscribe(EVENT_ID)
            Event.Draw.Unsubscribe(EVENT_ID)
            subscribed = false
        end
    end

    local function advanceSort(group)
        if not group.nativeSort then return false end
        if not live(group) then error("native interface retired") end
        local mounted = false
        for _, host in ipairs(group.hosts) do
            local frame = component(host.spec.frame)
            if frame and identity(frame) == host.key and same(frame.parent, group.area) then
                mounted = true
                break
            end
        end
        -- Client-owned dragging can temporarily hide every copy.
        if not mounted then error("native group closed") end
        if group.failure then error(group.failure) end
        if not (group.nativeSort.finishing and nativeSortReady(group)) then
            presentNativeSort(group)
            return nil
        end
        stopSortInputs(group)
        group.nativeSort = nil
        return true
    end

    local function animateDrag(group, current, drag)
        local host = group.hosts[current]
        for memberIndex, panel in ipairs(group.members) do
            if panel ~= drag.panel then
                local tab = group.bindings[panel].tabs[current]
                local target = ownX(group, host, memberIndex)
                tab.slideX = slide(tab.slideX or target, target)
            end
        end
        if host.nativeTab then
            local target = tabOrigin(host) + nativeOffset(group, host, 1) + previewOffset(group, 1)
            host.nativeTab.slideX = slide(host.nativeTab.slideX or target, target)
        else
            for nativeIndex, bg in ipairs(host.backgrounds) do
                local target = nativeOffset(group, host, nativeIndex) + previewOffset(group, nativeIndex)
                host.nativeSlides[bg.key] = slide(host.nativeSlides[bg.key] or target, target)
            end
        end
    end

    local function updateSelection(group, changed, settledSort)
        local current = selectedFrame(group)
        local selectionChanged = group.pending or current ~= group.current
        if group.pending then nativePage(group) end
        if not current then
            suspend(group)
            return
        end
        if group.active and (group.needsConceal or not changed and group.transient and current ~= group.current) then
            moveActive(group, current)
        elseif not changed and current ~= group.current and not group.lockTransition then
            nativePage(group)
        end
        group.transient = nil
        local rootReflow = reconcileRoots(group)
        local lockReflow = reconcileLock(group, current)
        local repainted = reconcilePage(group, current)
        local drag = group.tabDrag or group.dockPreview
        if drag then animateDrag(group, current, drag) end
        if group.failure then error(group.failure) end
        align(group)
        if lockReflow or repainted or rootReflow or settledSort then raiseGroup(group) end
        if changed or selectionChanged or settledSort then actions.saveGroup(group) end
        if group.mapSelection then
            local panel = group.mapSelection
            group.mapSelection = nil
            if group.bindings[panel] then actions.select(panel) end
        end
    end

    local function updateGroup(group)
        syncObservers(group)
        syncClientSort(group)
        if group.nativeSort and (editingLocked(group) or group.nativeSort.mapCancelled) then
            finishNativeSort(group, nil, true)
        end
        local settledSort = advanceSort(group)
        if settledSort == nil then return end
        -- A reservation reflow can temporarily shrink even visible
        -- hosts. Preserve the whole group before discovery can mistake
        -- an uncapturable row for a native tab split.
        checkCapacity(group)
        local changed = reconcile(group)
        if changed == nil then
            suspend(group)
            return
        end
        checkCapacity(group)
        if settledSort then
            -- Native sort completion can be followed by one delayed
            -- baseline repaint, just like the lock reflow path.
            for _, host in ipairs(group.hosts) do
                host.tabReset = true
            end
        end
        for _, host in ipairs(group.hosts) do
            if not validHost(group, host) then error("native host resized out of capacity or retired") end
        end
        updateSelection(group, changed, settledSort)
    end

    local function recoverGroup(group, problem)
        warn(problem)
        local members = { table.unpack(group.members) }
        local remembered = group.capacityLost and {} or nil
        if remembered then
            for _, panel in ipairs(members) do
                remembered[panel] = actions.remember(panel)
            end
        end
        for _, panel in ipairs(members) do
            actions.detach(panel)
        end
        if not group.dead and #group.members == 0 then actions.finishGroup(group) end
        if not remembered then return end
        -- Release unsafe geometry, not logical membership. Native
        -- layout owns when these named hosts have room again.
        for _, panel in ipairs(members) do
            if not panel._nisNative then
                panel._nisNativePending = remembered[panel]
                pending[panel] = 0
            end
        end
        Runtime.start()
    end

    local function groupHidden(group)
        return group.area.visibleGlobal == false
            or group.members[1]._nisTopLevelHidden
            or group.mapPaused and not mapReady(group)
    end

    local function tickGroup(group)
        if group.dead or #group.members == 0 then return end
        if groupHidden(group) then
            group.mapPaused = true
            suspend(group)
            return
        end
        group.mapPaused = nil
        group.capacityLost = nil
        local ok, problem = pcall(updateGroup, group)
        if not ok then recoverGroup(group, problem) end
    end

    local function tick()
        if WorldMap.isSuspended() or NativeInterfaceSettings.isClassicUI() then return end
        Runtime.logicSequence = Runtime.logicSequence + 1
        -- Commit content visibility only after all due native members have rejoined.
        Runtime.restoringBatch = true
        for panel in pairs(pending) do
            if
                not panel._nisNativePending
                or panel._destroyed
                or not panel.root
                or not ui.Interfaces:GetInterface(panel.interfaceID)
            then
                pending[panel] = nil
            elseif
                Runtime.logicSequence >= pending[panel]
                and not panel._nisClassic
                and not panel.dragState
                and not panel._nisTabPress
                and not (panel.resize and panel.resize.dragState)
            then
                actions.restorePending(panel)
            end
        end
        Runtime.restoringBatch = false
        Preview.validate()
        Runtime.stop()
        -- Reconcile one shared group at a time; native clients own frame geometry.
        for groupIndex = #groups, 1, -1 do
            tickGroup(groups[groupIndex])
        end
    end

    local function drawReady(group)
        return not group.mapPaused
            and not group.members[1]._nisTopLevelHidden
            and live(group)
            and group.area.visibleGlobal ~= false
    end

    local function drawGroup(group)
        if group.dead or #group.members == 0 then return end
        if drawReady(group) then
            local ok, problem = pcall(syncClientSort, group)
            if not ok then group.failure = problem end
        end
        if not drawReady(group) then return end
        if group.nativeSort then
            syncObservers(group)
            -- Native input can move the band and raise its opaque frame
            -- after Logic, including multiple paints between logic ticks.
            presentNativeSort(group)
            return
        end
        local rowOk, changed = pcall(nativeRowChanged, group)
        if not rowOk then
            group.failure = changed
        elseif group.paintPending or changed then
            -- Reacquire the final native row and stacking before painting.
            if actions.sync(group.members[1]) and selectedFrame(group) then raiseGroup(group) end
            group.paintPending = nil
        end
    end

    local function beforeDraw()
        if WorldMap.isSuspended() or NativeInterfaceSettings.isClassicUI() then return end
        for index = #groups, 1, -1 do
            drawGroup(groups[index])
        end
    end

    function Runtime.start()
        if subscribed then return end
        Event.Logic.Subscribe(EVENT_ID, function()
            local ok, problem = pcall(tick)
            Runtime.restoringBatch = false -- Also release the guard if a native getter throws.
            if not ok then warn(problem) end
        end)
        Event.Draw.Subscribe(EVENT_ID, function()
            local ok, problem = pcall(beforeDraw)
            if not ok then warn(problem) end
        end)
        subscribed = true
    end

    function Runtime.shutdown()
        if subscribed then
            Event.Logic.Unsubscribe(EVENT_ID)
            Event.Draw.Unsubscribe(EVENT_ID)
            subscribed = false
        end
    end

    return Runtime
end

return NativeRuntime
