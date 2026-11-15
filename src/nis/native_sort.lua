-- Observes client-owned tab dragging without taking over native input or ordering.
local Components = require("src/core/components")
local Tooltip = require("src/tooltip")
local InterfaceMouse = require("src/core/mouse")
local TabLayout = require("src/nis/native_tab_layout")
local WorldMap = require("src/core/world_map")

local NativeSort = {}

function NativeSort.new(Host, View, warn)
    local identity = Host.identity
    local component = Host.component
    local same = Host.same
    local editingLocked = Host.editingLocked
    local spriteID = Host.spriteID
    local tabBand = Host.tabBand
    local tabOrigin = Host.tabOrigin
    local tabScroll = Host.tabScroll
    local capture = Host.capture
    local selectedFrame = Host.selectedFrame
    local rectInParent = Host.rectInParent
    local HEIGHT = Host.HEIGHT
    local WIDTH = Host.WIDTH
    local SEAM = Host.SEAM
    local restoreArtwork = View.restoreArtwork
    local hideSeams = View.hideSeams
    local nativePage = View.nativePage
    local selectTab = View.selectTab
    local alignTab = View.alignTab
    local cancelScrollCapture = View.cancelScrollCapture
    local startSlides = View.startSlides
    local slide = View.slide
    local scrollPosition = View.scrollPosition

    -- During a client-owned native drag, the native source is a ghost: its
    -- background may leave the strip before its icon or the other frame copies
    -- move. Keep an independent press-time mixed row for our tabs. Only the
    -- non-dragged native children are displaced, using TabLayout's captured
    -- baselines (never the source's client-interpolated position).
    local function sortRow(group, host, source, sourceIndex)
        local row, natives = {}, {}
        local before = {}
        for _, panel in ipairs(group.members) do
            before[panel] = group.bindings[panel].beforeNative
        end
        for index, bg in ipairs(host.backgrounds) do
            local entry = { icon = bg.icon, width = bg.component.width,
                x = bg.layout.x, native = true, nativeIndex = index }
            natives[index] = entry
            if index == sourceIndex then source.entry = entry end
        end
        if not host.grouped then
            natives[1] = { width = WIDTH, x = 0, native = true, nativeIndex = 1 }
        end
        for count = 0, #natives do
            for _, panel in ipairs(group.members) do
                if math.min(before[panel] or #natives, #natives) == count then
                    row[#row + 1] = { panel = panel, width = WIDTH }
                end
            end
            if natives[count + 1] then row[#row + 1] = natives[count + 1] end
        end
        local x = host.grouped and host.backgrounds[1].layout.x or 0
        for _, entry in ipairs(row) do
            entry.slideX = x
            x = x + entry.width
        end
        return row, before, natives
    end

    local function alignSortTab(tab, x, y, show)
        alignTab(tab, x, y, show, true)
    end

    local function mapSortTab(host, bg)
        local mapped = { key = bg.key, component = bg.component, icon = bg.icon, children = {} }
        for _, child in ipairs(host.nativeLayout) do
            local center = child.x + child.width / 2
            if child.width <= bg.component.width and center >= bg.layout.x
                and center < bg.layout.x + bg.component.width then
                mapped.children[#mapped.children + 1] = { key = child.key, x = child.x - bg.layout.x }
                if child.width == 24 and child.height == 24 and child.component.y == 2
                    and spriteID(child.component) == bg.icon then mapped.iconKey = child.key end
            end
        end
        return mapped
    end

    local function sortChildren(group, host, sort, pointerSampled)
        local tabs = component(host.spec.TABS)
        if not tabs or identity(tabs) ~= identity(host.tabs)
            or not same(tabs.parent, host.frame) then return nil end
        host.tabs = tabs
        local children, byKey = {}, {}
        tabs:IterateDynamicComponents(function(child)
            local key = identity(child)
            if key and same(child.parent, tabs) and not byKey[key] then
                children[#children + 1], byKey[key] = child, child
            end
            return false
        end)
        if #children == 0 then return nil end
        local mapped = sort.mapped[host.key]
        local replaced, changed = #mapped ~= #sort.natives, false
        for _, bg in ipairs(mapped) do
            if not bg then
                changed = true
            elseif bg.component ~= byKey[bg.key] then
                replaced = true
                break
            end
            if bg and bg.iconKey and (not byKey[bg.iconKey] or spriteID(byKey[bg.iconKey]) ~= bg.icon) then
                changed = true
            end
        end
        local fresh = replaced or changed
        if fresh then
            -- Native sorting can repaint different icons into the same objects.
            -- Release offsets we still own before recapturing that in-place row;
            -- replacement objects must never receive the old objects' restoration.
            if not replaced then TabLayout.restore(tabs) end
            TabLayout.forget(tabs)
            local ok, rebuilt = pcall(capture, host.spec, group.area, true)
            local matched = {}
            if ok and rebuilt then
                for _, entry in ipairs(sort.natives) do
                    local choice
                    for _, bg in ipairs(rebuilt.backgrounds) do
                        if bg.icon == entry.icon and not matched[bg.key] then
                            if choice then choice = nil; break end
                            choice = bg
                        end
                    end
                    if choice then matched[choice.key] = true end
                    mapped[entry.nativeIndex] = choice and mapSortTab(rebuilt, choice) or false
                end
            else
                for index = 1, #sort.natives do mapped[index] = false end
            end
        end
        local records = TabLayout.capture(tabs, children)
        if not records then return nil end
        local source = host.key == sort.sourceHost and sort.source.entry
            and mapped[sort.source.entry.nativeIndex]
        local sourceConflict = false
        for _, record in ipairs(records) do
            if source and record.key == source.key then
                sourceConflict = record._conflicted
                break
            end
        end
        -- Accept native baseline resets during dragging and release reflow.
        TabLayout.track(tabs, records, fresh or sourceConflict or sort.clientCopies or sort.finishing)
        local saved = {}
        for _, record in ipairs(records) do saved[record.key] = record end
        for _, bg in ipairs(mapped) do
            if bg and byKey[bg.key] then bg.component = byKey[bg.key] end
        end
        -- Only the original source host supplies drag geometry. After its handle
        -- is rebuilt, the last pointer/source position remains authoritative.
        if host.key == sort.sourceHost and not fresh and not sort.finishing
            and not sort.cancelled and not pointerSampled and sort.source.entry then
            local source = mapped[sort.source.entry.nativeIndex]
            local record = source and saved[source.key]
            if record and type(record.component.x) == "number" then
                sort.sourceX = record.component.x
            end
        end
        return saved, mapped, fresh
    end

    local function sampleSortPointer(sort)
        if sort.finishing or sort.cancelled or not sort.pointerStart then return false end
        local pointer = InterfaceMouse.GetPosition()
        if not pointer then return false end
        sort.sourceX = sort.sourceStart + pointer.x - sort.pointerStart
        return true
    end

    local function positionSortRow(sort, sourceX)
        local row, source = sort.row, sort.source.entry
        if not source or type(sourceX) ~= "number" then return end
        local sourceIndex
        for index, entry in ipairs(row) do
            if entry == source then sourceIndex = index; break end
        end
        if not sourceIndex then return end
        local destination, x = 1, sort.baseX
        local center, leading = sourceX + source.width / 2, sourceX <= sort.baseX
        for index, entry in ipairs(row) do
            if entry ~= source then
                local midpoint = x + entry.width / 2
                if leading or center < midpoint or center == midpoint and sourceIndex > index then break end
                destination = destination + 1
            end
            -- Compare against occupied mixed slots, including the source's slot,
            -- so an unchanged native source does not displace following own tabs.
            x = x + entry.width
        end
        table.remove(row, sourceIndex)
        table.insert(row, destination, source)
    end

    local function presentNativeSort(group)
        local sort = group.nativeSort
        if not sort or editingLocked(group) then return end
        for _, host in ipairs(group.hosts) do
            local frame = component(host.spec.frame)
            if frame and identity(frame) == host.key then host.frame = frame end
        end
        local current = selectedFrame(group)
        if current then group.current = current end
        local scroll = scrollPosition(group, current or group.current)
        local pointerSampled = sampleSortPointer(sort)
        local layouts = {}
        for index, host in ipairs(group.hosts) do
            if host.grouped then layouts[index] = sortChildren(group, host, sort, pointerSampled) end
        end
        if sort.source.entry and not sort.cancelled then positionSortRow(sort, sort.sourceX) end
        -- Advance one mixed row, then project it onto every native frame copy.
        -- Independent per-copy animation drifts when native scripts repaint a row.
        local slotX = sort.baseX
        for _, entry in ipairs(sort.row) do
            entry.slideX = sort.finishing and slotX or slide(entry.slideX, slotX)
            slotX = slotX + entry.width
        end
        for index, host in ipairs(group.hosts) do
            -- The client can hide every frame copy while lifting its drag ghost.
            -- Our GAME_AREA artwork must retain the last visible mixed strip.
            local show = index == (current or group.current)
            local band = tabBand(host)
            local chrome = host.chrome
            local x, y, width, height = rectInParent(group.members[1], host.frame)
            if chrome.x ~= x or chrome.y ~= y then chrome:SetPos(x, y) end
            if chrome.width ~= width or chrome.height ~= height then chrome:SetSize(width, height) end
            if chrome.hidden == show then Components.setHidden(chrome, not show) end
            host.overflow:Layout(host.used + WIDTH * #group.members, scroll, show, false)
            if host.tabBuffer then
                if host.tabBuffer.x ~= band.x or host.tabBuffer.y ~= band.y then
                    host.tabBuffer:SetPos(band.x, band.y)
                end
                if host.tabBuffer.width ~= band.width then
                    host.tabBuffer:SetSize(band.width, HEIGHT - SEAM)
                end
            end
            if host.divider then
                local dy = band.y + HEIGHT - SEAM
                if host.divider.x ~= band.x or host.divider.y ~= dy then
                    host.divider:SetPos(band.x, dy)
                end
                if host.divider.width ~= band.width then
                    host.divider:SetSize(band.width, SEAM)
                end
            end
            local saved, mapped = layouts[index], sort.mapped[host.key]
            local nativeCountBefore, syntheticX = 0, nil
            for _, entry in ipairs(sort.row) do
                if entry.native then
                    nativeCountBefore = nativeCountBefore + 1
                    if not host.grouped then syntheticX = entry.slideX end
                    if saved and mapped and (entry ~= sort.source.entry
                        or sort.finishing and (not sort.clientCopies or current)) then
                        local bg = mapped[entry.nativeIndex]
                        local record = bg and saved[bg.key]
                        if record then
                            local x = entry.slideX
                            -- Move each tab's icon, badge and real input together.
                            -- Descendants follow their direct native parent.
                            for _, relative in ipairs(bg.children) do
                                local child = saved[relative.key]
                                if child and not child._entry.blocked then
                                    assert(TabLayout.move(child, x + relative.x - child.x) ~= false,
                                        "native sort peer position overwritten")
                                end
                            end
                        end
                    end
                else
                    if show then group.bindings[entry.panel].beforeNative = nativeCountBefore end
                    local tab = group.bindings[entry.panel].tabs[index]
                    tab.slideX = tabOrigin(host) + entry.slideX
                    alignSortTab(tab, tab.slideX - scroll, band.y, show)
                    selectTab(tab, show and group.active == entry.panel)
                end
            end
            if host.nativeTab then
                local nativeX = tabOrigin(host) + (syntheticX or 0)
                alignSortTab(host.nativeTab, nativeX - scroll, band.y, show)
            end
            if host.seam then Components.setHidden(host.seam, true) end
        end
        for _, panel in ipairs(group.members) do
            local binding = group.bindings[panel]
            if panel.root and ui.Interfaces:GetInterface(panel.interfaceID) then
                if not panel.root.hidden or panel.root.enabled ~= false then
                    cancelScrollCapture(panel._scroll)
                    Components.setHidden(panel.root, true)
                    panel.root.enabled = false
                    if panel.content then Tooltip.hideContextTooltips(panel.content) end
                    if panel._scroll then panel._scroll:_RefreshClipTargets() end
                    panel:_SyncChrome()
                    panel:_SyncOverlays(true)
                end
                binding.visible = false
            end
        end
        -- Native drag scripts raise their frame after our Logic callback. Only
        -- raise clickthrough artwork; the client must retain the real tab capture.
        group.hosts[group.current].chrome:MoveToFront()
    end

    -- Native scripts retain their page, source capture and final native order;
    -- our listeners only release the temporary mixed-row presentation.
    local function stopSortInputs(group)
        local sort = group.nativeSort
        if not sort then return end
        local failed
        if sort.keySubscribed then
            -- The native binding resolves its plugin from a Lua caller; passing it
            -- directly to C pcall loses that owner and can abort the client.
            local ok, problem = pcall(function() Event.KeyDown.Unsubscribe(group.hookID) end)
            if not ok then failed = problem end
            if ok then sort.keySubscribed = nil end
        end
        if sort.focusSubscribed then
            local ok, problem = pcall(function() Event.WindowFocusChanged.Unsubscribe(group.hookID) end)
            if not ok then failed = failed or problem end
            if ok then sort.focusSubscribed = nil end
        end
        if failed then error(failed) end
    end

    local function finishNativeSort(group, hook, cancelled)
        local sort = group.nativeSort
        if not sort or hook and sort.source ~= hook then
            return
        end
        if WorldMap.isSuspended() then sort.mapCancelled = true; return end
        local pointerSampled = sampleSortPointer(sort)
        if not pointerSampled and not cancelled and sort.source.entry and not sort.finishing then
            local source = sort.mapped[sort.sourceHost][sort.source.entry.nativeIndex]
            if source and source.component == sort.source.component then
                local ok, x = pcall(function() return sort.source.component.x end)
                if ok and type(x) == "number" and x ~= sort.sourceStart then sort.sourceX = x end
            end
        end
        sort.finishing = true
        if cancelled and not sort.cancelled then
            group.nativePress = nil
            sort.cancelled = true
            sort.row = { table.unpack(sort.originalRow) }
            for _, panel in ipairs(group.members) do
                group.bindings[panel].beforeNative = sort.before[panel]
            end
            for index, panel in ipairs(sort.members) do group.members[index] = panel end
            presentNativeSort(group)
        elseif not cancelled then
            presentNativeSort(group)
        end
    end

    local function nativeSortPress(group, hook, x, y)
        for _, host in ipairs(group.hosts) do
            local saved = host.nativeByKey and host.nativeByKey[hook.key]
            local stripPress = identity(host.tabs) == hook.key
            if saved or stripPress then
                local center = saved and saved.x + saved.width / 2 or x and x + tabScroll(host)
                for index, bg in ipairs(host.backgrounds) do
                    local left = stripPress and bg.component.x or bg.layout.x
                    if center and center >= left and center < left + bg.component.width then
                        InterfaceMouse.CalibrateFromHook(hook.component, x, y)
                        local pointer = InterfaceMouse.GetPosition()
                        return { host = host.key, index = index, x = bg.component.x,
                            pointerX = pointer and pointer.x }
                    end
                end
            end
        end
    end

    local function beginNativeSort(group, hook, x, y, press)
        if group.nativeSort or group.dead or #group.members == 0 or editingLocked(group) then return end
        press = press or hook.sortPress or nativeSortPress(group, hook, x, y)
        if not press then return end
        local host
        for _, candidate in ipairs(group.hosts) do
            if candidate.key == press.host then host = candidate; break end
        end
        if not host then return end
        local sort = { source = hook, sourceHost = host.key, mapped = {},
            sourceStart = press.x, sourceX = press.x, pointerStart = press.pointerX,
            members = { table.unpack(group.members) },
            baseX = host.grouped and host.backgrounds[1].layout.x or 0 }
        local row, before, natives = sortRow(group, host, sort.source, press.index)
        sort.row, sort.before, sort.natives = row, before, natives
        sort.originalRow = { table.unpack(row) }
        for _, copy in ipairs(group.hosts) do
            sort.mapped[copy.key] = {}
            for index, bg in ipairs(copy.backgrounds) do
                sort.mapped[copy.key][index] = mapSortTab(copy, bg)
            end
        end
        nativePage(group)
        -- The captured source stays in mixed-row coordinates. Subtracting its
        -- old own-tab offset would move it logically before the pointer moves.
        group.nativeSort = sort
        startSlides(group)
        presentNativeSort(group)
        sort.keySubscribed = true
        Event.KeyDown.Subscribe(group.hookID, function(event)
            if event.gameKey == GameKey.ESCAPE then
                finishNativeSort(group, nil, true)
            end
        end)
        sort.focusSubscribed = true
        Event.WindowFocusChanged.Subscribe(group.hookID, function(event)
            if event.hasFocus == false then finishNativeSort(group, nil, true) end
        end)
    end

    -- Native scripts hand capture between frame copies: RELEASE can arrive before
    -- the drag begins, with no subsequent ONDRAG/ONHOLD on the original component.
    -- Retain the group's press across that handoff. Two previously bound copies at
    -- the same bounds identify the live native drag; one visible copy ends it.
    local function syncClientSort(group)
        if not group.nativePress and not (group.nativeSort and group.nativeSort.clientCopies) then return end
        local count, first, sameBounds = 0, nil, true
        for _, host in ipairs(group.hosts) do
            local frame = component(host.spec.frame)
            if frame and identity(frame) == host.key and same(frame.parent, group.area) then
                host.frame = frame
                if frame.visibleGlobal then
                    count = count + 1
                    if first and (frame.x ~= first.x or frame.y ~= first.y
                        or frame.width ~= first.width or frame.height ~= first.height) then sameBounds = false end
                    first = first or frame
                end
            end
        end
        if editingLocked(group) then group.nativePress = nil; return end
        local sort = group.nativeSort
        if count > 1 and sameBounds then
            if not sort and group.nativePress then
                local press = group.nativePress
                beginNativeSort(group, press.hook, nil, nil, press)
                sort = group.nativeSort
            end
            if sort then
                sort.clientCopies = true
                if not sort.cancelled then sort.finishing = nil end
            end
        elseif count == 1 and sort and sort.clientCopies then
            -- There may be no final hook after the client has taken over capture.
            finishNativeSort(group, nil, sort.cancelled)
            group.nativePress = nil
        end
    end

    local function nativeSortReady(group)
        local selected = selectedFrame(group)
        if not selected then return false end
        local sort, previous = group.nativeSort, group.hosts[selected]
        local ok, current = pcall(capture, previous.spec, group.area, true)
        if not ok or not current then return false end
        if current.key ~= previous.key or current.grouped ~= group.grouped then
            return false
        end
        if group.grouped then
            if #current.backgrounds > #sort.natives then return false end
            local remaining, x = {}, sort.baseX
            for _, entry in ipairs(sort.natives) do remaining[entry.icon] = (remaining[entry.icon] or 0) + 1 end
            for _, bg in ipairs(current.backgrounds) do
                if bg.layout.x ~= x then return false end
                if not remaining[bg.icon] or remaining[bg.icon] == 0 then
                    return false
                end
                remaining[bg.icon] = remaining[bg.icon] - 1
                x = x + bg.component.width
            end
            if #current.backgrounds < #sort.natives then
                local before = 0
                for _, entry in ipairs(sort.row) do
                    if entry.native then
                        if remaining[entry.icon] > 0 then
                            remaining[entry.icon] = remaining[entry.icon] - 1
                        else
                            before = before + 1
                        end
                    else
                        group.bindings[entry.panel].beforeNative = before
                    end
                end
            end
        end
        for _, host in ipairs(group.hosts) do
            local captured, copy = pcall(capture, host.spec, group.area, true)
            local saved = group.frames[host.key]
            if saved then
                saved.sortPending = host.key ~= current.key and (not captured or not copy
                    or copy.signature ~= current.signature) or nil
            end
        end
        return true
    end

    local observedHooks = {
        ui.Hook.ONCLICK, ui.Hook.ONHOLD, ui.Hook.ONDRAG,
        ui.Hook.ONRELEASE, ui.Hook.ONDRAGCOMPLETE,
    }

    local function subscribeHook(group, hook, kind, callback)
        hook.component:Subscribe(kind, group.hookID, callback)
        hook.subscribed[kind] = true
    end

    local function unsubscribeHook(group, hook, kind)
        if not hook.subscribed[kind] then return end
        hook.component:Unsubscribe(kind, group.hookID)
        hook.subscribed[kind] = nil
    end

    local function restoreDragRendering(hook)
        if not hook.overlayRendering then return end
        local config = hook.component.dragConfig
        if config.renderBehaviour == ui.DragRenderBehaviour.OPAQUE_OVERLAY then
            config.renderBehaviour = ui.DragRenderBehaviour.OPAQUE
        end
        hook.overlayRendering = nil
    end

    local function overlayDragRendering(hook)
        local config = hook.component.dragConfig
        -- Preserve native invisible and translucent drag modes.
        if config.renderBehaviour == ui.DragRenderBehaviour.OPAQUE then
            hook.overlayRendering = true
            config.renderBehaviour = ui.DragRenderBehaviour.OPAQUE_OVERLAY
        end
    end

    local function unsubscribeHost(group, hook)
        if hook.removed then return end
        local failed
        local ok, problem = pcall(restoreDragRendering, hook)
        if not ok then failed = problem end
        for _, kind in ipairs(observedHooks) do
            if hook.subscribed[kind] then
                -- Retired same-ID drag sources can still deliver their release.
                -- Remove only registrations this observer actually installed.
                local ok, problem = pcall(function() unsubscribeHook(group, hook, kind) end)
                if not ok then failed = failed or problem end
            end
        end
        if failed then warn(failed) end
        hook.removed = true
    end

    local function stopObservingDrag(group, hook)
        restoreDragRendering(hook)
        -- Removing drag listeners disarms client capture; early callback returns do not.
        for _, kind in ipairs(observedHooks) do
            if kind ~= ui.Hook.ONCLICK then unsubscribeHook(group, hook, kind) end
        end
        hook.dragObserved, hook.pressX, hook.pressY = false, nil, nil
        hook.sortPress = nil
    end

    local function observeHost(group, hook, dragEnabled)
        local function observe(callback)
            return function(...)
                if WorldMap.isSuspended() then return true end
                local ok, problem = pcall(callback, ...)
                if not ok then group.failure = problem end
                return true -- never intercept original native listeners/scripts
            end
        end
        if not hook.subscribed[ui.Hook.ONCLICK] then
            subscribeHook(group, hook, ui.Hook.ONCLICK, observe(function(_, x, y)
                if hook.dragObserved and editingLocked(group) then stopObservingDrag(group, hook) end
                if hook.dragObserved then
                    hook.pressX, hook.pressY = x, y
                    hook.sortPress = nativeSortPress(group, hook, x, y)
                    if hook.sortPress and not group.nativeSort then
                        hook.sortPress.hook = hook
                        group.nativePress = hook.sortPress
                    end
                end
                if not group.dead and not group.nativeSort and #group.members > 0 and selectedFrame(group) then
                    group.pending, group.paintPending = true, true
                    hideSeams(group) -- immediate, before native script/listener processing
                    restoreArtwork(group)
                end
            end))
        end
        if not dragEnabled then
            -- Keep native selection subscribed without arming a drag while locked.
            stopObservingDrag(group, hook)
            return
        end
        overlayDragRendering(hook)
        subscribeHook(group, hook, ui.Hook.ONHOLD, observe(function(_, x, y)
            if group.dead or group.nativeSort or editingLocked(group)
                or type(x) ~= "number" or type(y) ~= "number" then return end
            if type(hook.pressX) == "number" and type(hook.pressY) == "number" then
                if x ~= hook.pressX or y ~= hook.pressY then beginNativeSort(group, hook, x, y) end
            else
                hook.pressX, hook.pressY = x, y
            end
        end))
        subscribeHook(group, hook, ui.Hook.ONDRAG, observe(function(_, x, y)
            beginNativeSort(group, hook, x, y)
        end))
        local function released()
            hook.pressX, hook.pressY = nil, nil
            finishNativeSort(group, hook)
            hook.sortPress = nil
        end
        subscribeHook(group, hook, ui.Hook.ONRELEASE, observe(released))
        subscribeHook(group, hook, ui.Hook.ONDRAGCOMPLETE, observe(released))
        hook.dragObserved = true
    end

    local function syncObservers(group)
        local dragEnabled = not editingLocked(group)
        for _, hook in ipairs(group.hooks) do
            if not hook.removed and hook.dragObserved ~= dragEnabled then
                observeHost(group, hook, dragEnabled)
            end
            if not hook.removed and hook.dragObserved then overlayDragRendering(hook) end
        end
    end

    local function subscribeHost(group, component)
        local key = identity(component)
        if not key then return end
        local hook = group.hookKeys[key]
        if hook and hook.component == component then return end
        if hook then
            unsubscribeHost(group, hook)
            for index, previous in ipairs(group.hooks) do
                if previous == hook then table.remove(group.hooks, index); break end
            end
        end
        hook = { component = component, key = key, subscribed = {} }
        group.hookKeys[key] = hook
        group.hooks[#group.hooks + 1] = hook -- before partially successful Subscribe
        observeHost(group, hook, not editingLocked(group))
    end

    local function releaseObservers(group)
        local failed
        for _, hook in ipairs(group.hooks) do
            local ok, problem = pcall(unsubscribeHost, group, hook)
            if not ok then failed = failed or problem end
        end
        group.hooks, group.hookKeys = {}, {}
        if failed then error(failed) end
    end

    return {
        presentNativeSort = presentNativeSort,
        stopSortInputs = stopSortInputs,
        finishNativeSort = finishNativeSort,
        syncClientSort = syncClientSort,
        nativeSortReady = nativeSortReady,
        syncObservers = syncObservers,
        subscribeHost = subscribeHost,
        releaseObservers = releaseObservers,
    }
end

return NativeSort
