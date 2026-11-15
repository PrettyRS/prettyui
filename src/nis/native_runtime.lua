-- Owns native Logic/Draw subscriptions and restoration-batch timing.
local WorldMap = require("src/core/world_map")
local NativeInterfaceSettings = require("src/core/native_interface_settings")

local RESIZE_SETTLE_TICKS = 8 -- 160 ms at the client's fixed 50 Hz logic rate.

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
    local tabBand = Host.tabBand
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

    -- Keep native row discovery/reconciliation deferred while the visible page
    -- follows the live bounds through its normal layout and overflow handling.
    local function deferResize(group)
        local state = group.resizeState
        if group.failure or group.attaching or group.nativeSort
            or group.tabDrag or group.dockPreview or group.pending or group.lockTransition
            or group.transient and not state then
            group.resizeState = nil
            return false
        end
        local current = selectedFrame(group)
        local host = current and group.hosts[current]
        if not host or current ~= group.current or not live(group)
            or not same(component(host.spec.frame), host.frame)
            or not same(host.frame.parent, group.area) then
            group.resizeState = nil
            return false
        end
        local width, height = host.frame.width, host.frame.height
        local contentWidth, contentHeight = host.content.width, host.content.height
        if not state then
            -- Content-only reflows (for example lock/unlock) are not resize gestures.
            if width == host.chrome.width and height == host.chrome.height then return false end
            checkCapacity(group)
            reconcileRoots(group)
            local view = host.overflow
            state = { width = width, height = height,
                contentWidth = contentWidth, contentHeight = contentHeight, tick = Runtime.logicSequence,
                viewportWidth = view.viewport.width, viewportHeight = view.viewport.height,
                rightGutter = math.max(0, view.bandWidth - (view.x - host.content.x) - view.width) }
            group.resizeState = state
            suspend(group, true)
            return true
        end
        if width ~= state.width or height ~= state.height
            or contentWidth ~= state.contentWidth or contentHeight ~= state.contentHeight then
            checkCapacity(group)
            reconcileRoots(group)
            state.width, state.height = width, height
            state.contentWidth, state.contentHeight = contentWidth, contentHeight
            state.tick = Runtime.logicSequence
        end
        if Runtime.logicSequence - state.tick < RESIZE_SETTLE_TICKS then return true end
        group.resizeState = nil
        for _, copy in ipairs(group.hosts) do copy.tabReset = true end
        return false, true
    end

    local function tick()
        if WorldMap.isSuspended() or NativeInterfaceSettings.isClassicUI() then return end
        Runtime.logicSequence = Runtime.logicSequence + 1
        -- Commit content visibility only after all due native members have rejoined.
        Runtime.restoringBatch = true
        for panel in pairs(pending) do
            if not panel._nisNativePending or panel._destroyed or not panel.root
                or not ui.Interfaces:GetInterface(panel.interfaceID) then
                pending[panel] = nil
            elseif Runtime.logicSequence >= pending[panel] and not panel._nisClassic
                and not panel.dragState and not panel._nisTabPress
                and not (panel.resize and panel.resize.dragState) then
                actions.restorePending(panel)
            end
        end
        Runtime.restoringBatch = false
        Preview.validate()
        Runtime.stop()
        -- Reconcile one shared group at a time; native clients own frame geometry.
        for index = #groups, 1, -1 do
            local group = groups[index]
            if not group.dead and #group.members > 0 and (group.area.visibleGlobal == false
                or group.members[1]._nisTopLevelHidden
                or group.mapPaused and not mapReady(group)) then
                group.mapPaused = true
                suspend(group)
            elseif not group.dead and #group.members > 0 then
                group.mapPaused = nil
                group.capacityLost = nil
                local ok, problem = pcall(function()
                    local resizing, settledResize = deferResize(group)
                    if resizing then return end
                    syncObservers(group)
                    syncClientSort(group)
                    if group.nativeSort and (editingLocked(group) or group.nativeSort.mapCancelled) then
                        finishNativeSort(group, nil, true)
                    end
                    local settledSort = false
                    if group.nativeSort then
                        if not live(group) then error("native interface retired") end
                        local mounted = false
                        for _, host in ipairs(group.hosts) do
                            local frame = component(host.spec.frame)
                            if frame and identity(frame) == host.key
                                and same(frame.parent, group.area) then mounted = true; break end
                        end
                        -- Client-owned dragging can temporarily hide every copy.
                        if not mounted then error("native group closed") end
                        if group.failure then error(group.failure) end
                        local ready = group.nativeSort.finishing and nativeSortReady(group)
                        if not ready then
                            presentNativeSort(group)
                            return
                        end
                        stopSortInputs(group)
                        group.nativeSort = nil
                        settledSort = true
                    end
                    -- A reservation reflow can temporarily shrink even visible
                    -- hosts. Preserve the whole group before discovery can mistake
                    -- an uncapturable row for a native tab split.
                    checkCapacity(group)
                    local changed = reconcile(group)
                    if changed == nil then suspend(group); return end
                    checkCapacity(group)
                    if settledSort then
                        -- Native sort completion can be followed by one delayed
                        -- baseline repaint, just like the lock reflow path.
                        for _, host in ipairs(group.hosts) do host.tabReset = true end
                    end
                    for _, host in ipairs(group.hosts) do
                        if not validHost(group, host) then error("native host resized out of capacity or retired") end
                    end
                    local current = selectedFrame(group)
                    local selectionChanged = group.pending or current ~= group.current
                    if group.pending then nativePage(group) end
                    if current then
                        if group.active and (group.needsConceal
                            or not changed and group.transient and current ~= group.current) then
                            moveActive(group, current)
                        elseif not changed and current ~= group.current and not group.lockTransition then
                            nativePage(group)
                        end
                        group.transient = nil
                        local rootReflow = reconcileRoots(group)
                        local lockReflow = reconcileLock(group, current)
                        local repainted = reconcilePage(group, current)
                        local drag = group.tabDrag or group.dockPreview
                        if drag then
                            local host = group.hosts[current]
                            local band = tabBand(host)
                            for index, panel in ipairs(group.members) do
                                if panel ~= drag.panel then
                                    local tab = group.bindings[panel].tabs[current]
                                    local target = ownX(group, host, index)
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
                        if group.failure then error(group.failure) end
                        align(group)
                        if settledResize then group.resizeRaisePending = true end
                        if lockReflow or repainted or rootReflow or settledSort then raiseGroup(group) end
                        if changed or selectionChanged or settledSort then actions.saveGroup(group) end
                        if group.mapSelection then
                            local panel = group.mapSelection
                            group.mapSelection = nil
                            if group.bindings[panel] then actions.select(panel) end
                        end
                    else
                        suspend(group)
                    end
                end)
                if not ok then
                    warn(problem)
                    local members = { table.unpack(group.members) }
                    local remembered = group.capacityLost and {} or nil
                    if remembered then
                        for _, panel in ipairs(members) do remembered[panel] = actions.remember(panel) end
                    end
                    for _, panel in ipairs(members) do actions.detach(panel) end
                    if not group.dead and #group.members == 0 then actions.finishGroup(group) end
                    if remembered then
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
                end
            end
        end
    end

    local function beforeDraw()
        if WorldMap.isSuspended() or NativeInterfaceSettings.isClassicUI() then return end
        for index = #groups, 1, -1 do
            local group = groups[index]
            if not group.dead and #group.members > 0 then
                local resizing, settledResize = false, false
                if not group.mapPaused and not group.members[1]._nisTopLevelHidden
                    and live(group) and group.area.visibleGlobal ~= false then
                    local ok, result, settled = pcall(deferResize, group)
                    if not ok then
                        group.failure, resizing = result, true
                    else
                        resizing, settledResize = result, settled
                        if not resizing then
                            local sorted, problem = pcall(syncClientSort, group)
                            if not sorted then group.failure = problem end
                        end
                    end
                end
                if resizing then
                    local ok, problem = pcall(View.presentResize, group)
                    if not ok then group.failure = problem end
                elseif group.nativeSort then
                    if not group.mapPaused and not group.members[1]._nisTopLevelHidden
                        and live(group) and group.area.visibleGlobal ~= false then
                        syncObservers(group)
                        -- Native input can move the band and raise its opaque frame
                        -- after Logic, including multiple paints between logic ticks.
                        presentNativeSort(group)
                    end
                elseif not resizing and not group.mapPaused and not group.members[1]._nisTopLevelHidden
                    and live(group) and group.area.visibleGlobal ~= false then
                    local ok, changed = pcall(nativeRowChanged, group)
                    if not ok then
                        group.failure = changed
                    elseif group.paintPending or changed or settledResize then
                        -- Reacquire the final native row and stacking before painting.
                        if actions.sync(group.members[1]) and selectedFrame(group) then raiseGroup(group) end
                        group.paintPending = nil
                        group.resizeRaisePending = nil
                    elseif group.resizeRaisePending then
                        if selectedFrame(group) then raiseGroup(group) end
                        group.resizeRaisePending = nil
                    end
                end
            end
        end
        Preview.draw()
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
