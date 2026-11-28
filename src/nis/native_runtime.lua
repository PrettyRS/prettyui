-- Owns native Logic/Draw subscriptions and restoration-batch timing.
local WorldMap = require("src/core/world_map")
local NativeInterfaceSettings = require("src/core/native_interface_settings")

local NativeRuntime = {}
local IDLE_AUDIT_TICKS = 8

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

    local function visibleLayoutMatches(group)
        local host = group.hosts[group.current]
        local frame, chrome, content = host.frame, host.chrome, host.content
        if
            frame.x ~= chrome.x
            or frame.y ~= chrome.y
            or frame.width ~= chrome.width
            or frame.height ~= chrome.height
        then
            return false
        end
        local panel = group.active or group.members[1]
        local root, inset = panel.root, host.grouped and 0 or Host.HEIGHT
        if
            root.x ~= frame.x + content.x
            or root.y ~= frame.y + content.y + inset
            or root.width ~= content.width
            or root.height ~= math.max(0, content.height - inset)
        then
            return false
        end
        if group.nativeRoots then
            for _, saved in ipairs(group.nativeRoots) do
                if saved.component.width < 0 or saved.component.height < 0 then return false end
            end
        end
        if group.active then
            for _, flag in ipairs(host.flags) do
                if not flag.component.hidden then return false end
            end
            local artwork = group.artwork
            if artwork and artwork.component[artwork.field] == artwork.original then return false end
        end
        return true
    end

    -- Observe visible changes every tick. Hidden copies and native anchors have
    -- no complete change notification, so still audit the whole dock periodically.
    local function idle(group)
        if not group.nextAudit or Runtime.logicSequence >= group.nextAudit then return false end
        if
            group.pending
            or group.nativeSort
            or group.tabDrag
            or group.dockPreview
            or group.incomingPreview
            or group.selectionHandoff
            or group.split
            or group.lockTransition
            or group.transient
            or group.paintPending
            or group.needsConceal
            or group.mapSelection
            or group.failure
        then
            return false
        end
        return live(group) and not nativeRowChanged(group, true) and visibleLayoutMatches(group)
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
        if changed or selectionChanged or settledSort then
            group.nextAudit = nil
            actions.saveGroup(group)
        else
            group.nextAudit = Runtime.logicSequence + IDLE_AUDIT_TICKS
        end
        if group.mapSelection then
            local panel = group.mapSelection
            group.mapSelection = nil
            if group.bindings[panel] then actions.select(panel) end
        end
    end

    local function updateGroup(group)
        syncObservers(group)
        syncClientSort(group)
        -- A retired handle in the idle probe needs a rebind, not a detach.
        local readable, quiet = pcall(idle, group)
        if readable and quiet then return end
        if group.nativeSort and (editingLocked(group) or group.nativeSort.mapCancelled) then
            finishNativeSort(group, nil, true)
        end
        local settledSort = advanceSort(group)
        if settledSort == nil then return end
        local changed = reconcile(group)
        if changed == nil then
            suspend(group)
            return
        end
        for _, host in ipairs(group.hosts) do
            if not validHost(group, host) then error("native host retired or changed topology") end
        end
        updateSelection(group, changed, settledSort)
    end

    local function recoverGroup(group, problem)
        warn(problem)
        local members = { table.unpack(group.members) }
        for _, panel in ipairs(members) do
            actions.detach(panel)
        end
        if not group.dead and #group.members == 0 then actions.finishGroup(group) end
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
                actions.releaseDeferred(panel)
            elseif
                Runtime.logicSequence >= pending[panel]
                and not panel._nisClassic
                and not panel.dragState
                and not panel._nisTabPress
                and not (panel.resize and panel.resize.dragState)
            then
                actions.restorePending(panel)
                if panel._nisNative then panel._nisNative.group.nextAudit = nil end
            end
        end
        actions.finishRestoreBatch()
        Runtime.restoringBatch = false
        Preview.validate()
        Runtime.stop()
        -- Reconcile one shared group at a time; native clients own frame geometry.
        for groupIndex = #groups, 1, -1 do
            tickGroup(groups[groupIndex])
        end
    end

    local function drawGroup(group)
        local member = group.members[1]
        if group.dead or not member or group.mapPaused or member._nisTopLevelHidden then return end
        if not live(group) or group.area.visibleGlobal == false then return end
        if group.nativePress or group.nativeSort or group.pending or group.selectionHandoff then
            local ok, problem = pcall(syncClientSort, group)
            if not ok then
                group.failure = problem
                return
            end
        end
        if group.nativeSort then
            syncObservers(group)
            presentNativeSort(group)
            return
        end
        if group.paintPending then
            if actions.sync(member) and selectedFrame(group) then raiseGroup(group) end
            group.paintPending = nil
            return
        end
        local readOK, changed = pcall(nativeRowChanged, group)
        if not readOK then
            group.failure = changed
        elseif changed then
            if actions.sync(member) and selectedFrame(group) then raiseGroup(group) end
            group.paintPending = nil
        elseif group.incomingPreview then
            -- Native drag painting can raise the frame even at a stationary
            -- pointer. Raise only clickthrough artwork while it owns capture.
            group.hosts[group.current].chrome:MoveToFront()
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
