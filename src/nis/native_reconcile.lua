-- Rebinds native hosts and restores only the layout, artwork and hooks owned by docking.
local Components = require("src/core/components")
local Sprites = require("src/core/sprites")
local TabLayout = require("src/nis/native_tab_layout")
local Divider = require("src/nis/native_divider")
local Overflow = require("src/nis/native_overflow")
local Split = require("src/nis/native_split")

local NativeReconcile = {}

function NativeReconcile.new(Host, View, Sort, byFrame, actions)
    local art = Sprites.NIS_PANEL
    local warn = actions.warn
    local positions = { "x", "y", "xParentPc", "yParentPc", "xSelfPc", "ySelfPc" }
    local sizes = { "width", "height", "widthParentPc", "heightParentPc" }
    local hostFields = { "frame", "content", "scroll", "tabs", "backdrop", "tabControls",
        "backgrounds", "children", "nativeLayout", "nativeByKey",
        "previewIncoming", "previewSource", "previewTargetX", "previewTargetY" }

    local identity = Host.identity
    local component = Host.component
    local same = Host.same
    local live = Host.live
    local applyLayout = Host.applyLayout
    local spriteID = Host.spriteID
    local tabBand = Host.tabBand
    local capture = Host.capture
    local familiarRootsFor = Host.familiarRootsFor
    local discover = Host.discover
    local related = Host.related
    local selectedFrame = Host.selectedFrame
    local HEIGHT = Host.HEIGHT
    local SEAM = Host.SEAM
    local restoreFlag = View.restoreFlag
    local conceal = View.conceal
    local restoreArtwork = View.restoreArtwork
    local nativePage = View.nativePage
    local borrow = View.borrow
    local ownSprite = View.ownSprite
    local destroyTab = View.destroyTab
    local makeVisual = View.makeVisual
    local newTab = View.newTab
    local raiseGroup = View.raiseGroup
    local stopSortInputs = Sort.stopSortInputs
    local subscribeHost = Sort.subscribeHost
    local releaseObservers = Sort.releaseObservers

    local function createHost(group, host, chrome)
        host.flags = {}
        host.nativeSlides = {}
        if host.grouped then TabLayout.track(host.tabs, host.nativeLayout) end
        host.chrome = chrome or Components.new(ui.Layer, group.area, { _categoryPolicy = "auto" })
        if not chrome then
            host.chrome.clickthrough, host.chrome.enabled = true, false
            Components.setHidden(host.chrome, true)
        end
        host.overflow = Overflow.new(host, group.area, function(delta)
            if group.dead or group.nativeSort or group.tabDrag then return end
            group.tabScroll = (group.tabScroll or 0) + delta
            group.scrollRequested = true
            if actions.sync(group.members[1]) then raiseGroup(group) end
        end)
        local edit = component(host.spec.EDIT_BLOCK)
        if edit and not same(edit.parent, host.frame) then
            error("native edit layer is outside its frame")
        end
        local function remember(comp)
            if comp then
                host.flags[#host.flags + 1] = {
                    component = comp, key = identity(comp), hidden = comp.hidden,
                }
            end
        end
        if group.nativeRoots then
            for _, saved in ipairs(group.nativeRoots) do remember(saved.component) end
        else
            remember(host.content)
        end
        remember(host.scroll)
        remember(edit)
        subscribeHost(group, host.tabs)
        for _, child in ipairs(host.children) do subscribeHost(group, child) end
        if group.grouped then
            host.seam = Components.new(ui.Sprite, host.overflow.viewport, { _categoryPolicy = "auto" })
            host.seam.spriteID = art.tabBarTile
            host.seam.isTiling = true
            host.seam.enabled, host.seam.clickthrough = false, true
            Components.setHidden(host.seam, true)
        else
            host.tabBuffer = ownSprite(host.chrome, art.tabBufferTile)
            host.tabBuffer:SetSize(tabBand(host).width, HEIGHT - SEAM)
            host.tabBuffer.isTiling = true
            host.divider = Components.new(ui.Sprite, host.chrome, { _categoryPolicy = "auto" })
            host.divider.spriteID = art.tabBarTile
            host.divider.isTiling = true
            host.divider.enabled, host.divider.clickthrough = false, true
            -- The fill and divider must stay behind the clipped tab artwork.
            host.overflow.viewport:MoveToFront()
            -- The native-page input is created after the first member supplies a
            -- GAME_AREA parent. No client-hidden native tab strip is revealed.
        end
    end

    local function matchingHost(a, b)
        if a.key ~= b.key or a.owner ~= b.owner or a.grouped ~= b.grouped
            or a.previewSource ~= b.previewSource or a.previewIncoming ~= b.previewIncoming
            or a.signature ~= b.signature or a.used ~= b.used
            or a.nativeIcon ~= b.nativeIcon
            or not same(a.content, b.content) or not same(a.scroll, b.scroll)
            or not same(a.tabs, b.tabs) or not same(a.backdrop, b.backdrop)
            or #a.backgrounds ~= #b.backgrounds or #a.children ~= #b.children then return false end
        for i, bg in ipairs(a.backgrounds) do
            if bg.key ~= b.backgrounds[i].key then return false end
        end
        for i, child in ipairs(a.children) do
            if not same(child, b.children[i]) then return false end
        end
        return true
    end

    local function acceptTabRepaint(fresh, previous)
        if not fresh._conflicted then return false end
        if fresh.original[1] ~= previous.original[1] + (previous.correction or 0) then return false end
        for index = 2, #previous.original do
            if fresh.original[index] ~= previous.original[index] then return false end
        end
        fresh._conflicted = false
        return true
    end

    -- Equal public IDs establish membership, not a native object's lifetime.
    -- Always adopt the current lookup handles, including unchanged-ID rebuilds.
    local function refreshHost(group, host, current)
        -- A matching row can repaint one child at a time during an incoming
        -- native drag. A return to that child's exact anchors is not a new
        -- native layout; keep its mixed slot even on consecutive Draws.
        if current.nativeLayout then
            for _, fresh in ipairs(current.nativeLayout) do
                local previous = host.nativeByKey[fresh.key]
                local reset = acceptTabRepaint(fresh, previous)
                if (reset or fresh.offset ~= previous.offset) and current.frame.visibleGlobal then
                    group.paintPending = true
                end
            end
        end
        if Divider.changed(host) and current.frame.visibleGlobal then group.paintPending = true end
        for _, field in ipairs(hostFields) do host[field] = current[field] end
        if host.grouped then
            TabLayout.track(host.tabs, host.nativeLayout, current.previewIncoming or group.lockTransition ~= nil)
        end
        if host.overflow then host.overflow.host = host end
        local roots = group.nativeRoots
        if roots and host.spec.name == "TOPLEVEL_V2__LORE_WINDOW" then
            local currentRoots = familiarRootsFor(host, roots)
            if not currentRoots then error("unrecognized familiar page layout") end
            local unavailable = component(host.spec.EDIT_BLOCK).visible == true
            local availabilityChanged = group.familiarUnavailable ~= unavailable
            group.familiarUnavailable = unavailable
            local retained = {}
            for _, saved in ipairs(currentRoots) do retained[saved.key] = true end
            for index = #host.flags, 1, -1 do
                local flag = host.flags[index]
                for _, saved in ipairs(roots) do
                    if saved.key == flag.key and not retained[saved.key] then
                        -- Dismissal can unparent a still-live page rather than
                        -- unload it. Release our inset before a later remount.
                        local fresh = saved.changed and component(saved.packed)
                        if fresh and identity(fresh) == saved.key and fresh.parent == nil then
                            saved.component = fresh
                            applyLayout(fresh, saved.original)
                            Components.setHidden(fresh, saved.hidden)
                            saved.changed = false
                        end
                        table.remove(host.flags, index)
                        break
                    end
                end
            end
            group.nativeRoots, roots = currentRoots, currentRoots
            for _, saved in ipairs(roots) do
                if not saved.changed then
                    saved.changed = true -- setters can partially apply before throwing
                    applyLayout(saved.component, saved.inset)
                    host.flags[#host.flags + 1] = {
                        component = saved.component, key = saved.key, hidden = saved.hidden,
                    }
                elseif availabilityChanged then
                    saved.baselineReset = true
                end
            end
        elseif roots then
            for _, saved in ipairs(roots) do
                local fresh = component(saved.packed)
                if not fresh or identity(fresh) ~= saved.key or not same(fresh.parent, host.content) then
                    error("native content root retired")
                end
                saved.component = fresh
            end
        end
        local edit = component(host.spec.EDIT_BLOCK)
        local contentKey, scrollKey, editKey = identity(host.content), identity(host.scroll), identity(edit)
        for _, saved in ipairs(host.flags) do
            local fresh
            if roots then
                for _, root in ipairs(roots) do
                    if saved.key == root.key then fresh = root.component; break end
                end
            end
            if not fresh then
                if saved.key == contentKey then fresh = host.content
                elseif saved.key == scrollKey then fresh = host.scroll
                elseif saved.key == editKey then fresh = edit end
            end
            if not fresh then error("native concealment component retired") end
            saved.component = fresh
        end
        local artwork = group.artwork
        if artwork and artwork.host == host then
            for _, bg in ipairs(host.backgrounds) do
                if bg.key == artwork.key then artwork.component = bg.component; break end
            end
        end
        subscribeHost(group, host.tabs)
        for _, child in ipairs(host.children) do subscribeHost(group, child) end
    end

    local function nativeIconAt(host, index)
        if not host.grouped and index == 1 then return host.nativeIcon end
        local bg = host.backgrounds[index]
        return bg and bg.icon
    end

    -- The preview may already contain the incoming page in a different slot.
    -- Removing that page from both rows must leave the same ordered peers.
    local function matchesReturn(previous, host, icon)
        local count = previous.grouped and #previous.backgrounds or 1
        if #host.backgrounds < count or #host.backgrounds > count + 1 then return false end
        local index, seen = 1, false
        for _, bg in ipairs(host.backgrounds) do
            if bg.icon == icon then
                if seen then return false end
                seen = true
            else
                if nativeIconAt(previous, index) == icon then index = index + 1 end
                if nativeIconAt(previous, index) ~= bg.icon then return false end
                index = index + 1
            end
        end
        if nativeIconAt(previous, index) == icon then index = index + 1 end
        return seen and index > count
    end

    local function confirmsJoin(group, found, host, preferred)
        if not host.grouped then return false end
        for _, other in ipairs(found) do
            if group.frames[other.key] and related(host, other) then return true end
        end
        -- The returning page can be selected before *any* resident copy repaints.
        -- Require its former frame identity, its icon and the last visible nest position.
        local icon = group.departed and group.departed[host.key]
        return icon and host.frame.x == preferred.chrome.x and host.frame.y == preferred.chrome.y
            and matchesReturn(preferred, host, icon)
    end

    local function ordinaryAnchor(group, found, preferred)
        local incoming
        for _, host in ipairs(found) do
            if host.previewIncoming and host.frame.visibleGlobal
                and (not byFrame[host.key] or byFrame[host.key] == group) then
                if incoming then incoming = nil; break end
                incoming = host
            end
        end
        if incoming then return incoming end
        local visible
        for _, host in ipairs(found) do
            local resident = group.frames[host.key]
            if resident and host.frame.visibleGlobal and (host.grouped or not group.grouped)
                and (host.key ~= group.incomingPreview or host.previewIncoming) then
                if host.key == preferred.key and (not group.incomingPreview
                    or host.previewIncoming) then return host end
                if not visible or not resident.sortPending then visible = host end
            end
        end
        if visible then return visible end
        for _, host in ipairs(found) do
            if host.frame.visibleGlobal and not byFrame[host.key] and confirmsJoin(group, found, host, preferred) then
                return host
            end
        end
        return nil
    end

    local function sameLayout(comp, saved)
        local pos, size = comp.position, comp.size
        local matches = true
        for index, field in ipairs(positions) do
            local value = pos[field]
            if type(value) ~= "number" then return nil end
            if value ~= saved[index] then matches = false end
        end
        for index, field in ipairs(sizes) do
            local value = size[field]
            if type(value) ~= "number" then return nil end
            if value ~= saved[index + 6] then matches = false end
        end
        return matches
    end

    local function adoptStandalone(group, host)
        local roots = Host.nativeRootsFor(host)
        if not roots then error("remaining native page has no compatible standalone content") end
        group.grouped, group.nativeRoots = false, roots
        for _, root in ipairs(roots) do
            root.changed = true
            applyLayout(root.component, root.inset)
        end
    end

    local function insetRoot(saved, host, edit)
        local fresh = component(saved.packed)
        if not fresh then return nil end
        if same(fresh.parent, host.content) and identity(fresh) == saved.key then return fresh end
        if not same(fresh, edit) then return nil end
        -- Familiar placeholders are dynamic children of the packed edit layer.
        local root
        edit:IterateDynamicComponents(function(child)
            if same(child.parent, edit) and identity(child) == saved.key then root = child; return true end
            return false
        end)
        return root
    end

    local function releaseStandaloneInset(group, host)
        local edit = component(host.spec.EDIT_BLOCK)
        for _, saved in ipairs(group.nativeRoots) do
            local fresh = insetRoot(saved, host, edit)
            if fresh and sameLayout(fresh, saved.inset) then
                applyLayout(fresh, saved.original)
            end
        end
        group.nativeRoots, group.familiarUnavailable, group.grouped = nil, nil, true
    end

    local function retainFrame(group, saved, captured, anchor, split, oldSignature)
        if not captured then
            if split and split.away[saved.key] then return false end
            local frame = component(saved.spec.frame)
            return frame and identity(frame) == saved.key and same(frame.parent, group.area) and not frame.visibleGlobal
        end
        if related(anchor, captured) then
            saved.sortPending = nil
            return true
        end
        -- A second painted copy is not a second overlay target, but its known
        -- frame identity remains part of the nest while the client hands off.
        if anchor.grouped and captured.grouped and captured.signature == anchor.signature
            and captured.frame.x == anchor.frame.x and captured.frame.y == anchor.frame.y then
            saved.sortPending = nil
            return true
        end
        if group.incomingPreview and group.previewPeers and group.previewPeers[saved.key]
            and captured.grouped and (captured.signature == group.previewBase.signature
                or captured.signature == anchor.signature) then
            saved.sortPending = true
            return true
        end
        if captured.frame.visibleGlobal then
            saved.sortPending = nil
            return false
        end
        -- The visible row already grew; an unchanged hidden copy still belongs to it.
        if captured.signature == oldSignature then saved.sortPending = true end
        return saved.sortPending
    end

    local function previewSettled(group, anchor, found)
        if not group.incomingPreview or not anchor.previewIncoming then return false end
        local source = anchor.backgrounds[anchor.previewSource]
        local icon = source and anchor.nativeByKey[source.iconKey]
        if not source or source.component.x ~= source.layout.x or not icon
            or icon.component.x ~= source.layout.x + math.floor((source.layout.width - 24) / 2) then return false end
        for _, peer in ipairs(found) do
            if group.previewPeers[peer.key] and peer.frame.visibleGlobal then return false end
        end
        return true
    end

    local function updatePreview(group, preferred, anchor, found)
        if previewSettled(group, anchor, found) then
            group.incomingPreview = nil
            anchor = capture(anchor.spec, group.area, true)
            if not anchor then error("settled native preview has no coherent row") end
            for index, host in ipairs(found) do
                if host.key == anchor.key then found[index] = anchor; break end
            end
        end
        if not anchor.previewIncoming then
            group.incomingPreview, group.previewBase, group.previewPeers = nil, nil, nil
            return anchor
        end
        if not group.incomingPreview then
            -- Keep the resident order, not the moving row's provisional order.
            group.previewBase = {
                owner = preferred.owner, grouped = true, backgrounds = preferred.backgrounds,
                signature = preferred.signature, candidate = anchor.key,
                previewTargetX = anchor.frame.x, previewTargetY = anchor.frame.y,
            }
            group.previewPeers = {}
            for key in pairs(group.frames) do group.previewPeers[key] = true end
        end
        group.incomingPreview = anchor.key
        if group.active then nativePage(group) end
        return anchor
    end

    -- A former frame identity anchors the group. Rectangles and matching tab
    -- art alone cannot confer ownership of an unrelated native window.
    local function reconcile(group)
        if not live(group) then error("native interface retired") end
        local preferred = group.hosts[group.current]
        local found = discover(group.area, group.previewBase or preferred)
        local previous = {}
        for _, host in ipairs(group.hosts) do previous[host.key] = host end
        local split = group.split
        local anchor
        if split then
            local removed
            anchor, removed = Split.anchor(group, found)
            if anchor then
                Split.settle(group, anchor, removed)
                if not removed then split = nil end
            end
        else
            anchor = ordinaryAnchor(group, found, preferred)
        end
        if not anchor then
            -- Selection can hide every resident before the returned frame is
            -- published. Discover first; suspend only if there is no live row.
            for _, host in pairs(group.frames) do
                local frame = component(host.spec.frame)
                if frame and same(frame.parent, group.area) then
                    local tabs = component(host.spec.TABS)
                    if split or not frame.visibleGlobal or group.grouped and tabs and tabs.visible then return nil end
                end
            end
            error("native host closed or changed to an unsupported arrangement")
        end
        anchor = updatePreview(group, preferred, anchor, found)
        local hosts = {}
        for _, host in ipairs(found) do
            if related(anchor, host) then
                if byFrame[host.key] and byFrame[host.key] ~= group then
                    error("native host belongs to another docked group")
                end
                hosts[#hosts + 1] = host
            end
        end
        -- A visible bound frame owns its strip. Hidden copies can retain the
        -- preview order until clicked; keep their membership, not their stale row.
        local membershipChanged = false
        local oldSignature = anchor.frame.visibleGlobal and preferred.signature
        for key, saved in pairs(group.frames) do
            local captured
            for _, host in ipairs(found) do
                if host.key == key then captured = host; break end
            end
            if not retainFrame(group, saved, captured, anchor, split, oldSignature) then
                if split and (split.away[key] or captured and not captured.grouped) then
                    group.departed = group.departed or {}
                    group.departed[key] = split.backgrounds[split.index].icon
                end
                group.frames[key] = nil
                membershipChanged = true
                if byFrame[key] == group then byFrame[key] = nil end
            end
        end
        for _, host in ipairs(hosts) do
            if group.departed and not host.previewIncoming then group.departed[host.key] = nil end
            if not group.frames[host.key] then
                group.frames[host.key] = { key = host.key, spec = host.spec }
                membershipChanged = true
            end
            byFrame[host.key] = group
        end
        local changed = #hosts ~= #group.hosts
        if not changed then
            for i, host in ipairs(hosts) do
                if not matchingHost(group.hosts[i], host) then changed = true; break end
            end
        end
        if not changed then
            for i, host in ipairs(hosts) do refreshHost(group, group.hosts[i], host) end
            return membershipChanged
        end

        local active, savedFlags, oldTabs = group.active, {}, {}
        restoreArtwork(group)
        for _, host in ipairs(group.hosts) do
            if host.grouped then
                Divider.restore(host)
                TabLayout.restore(host.tabs)
            end
            if host.overflow then host.overflow:Restore() end
            for _, flag in ipairs(host.flags) do
                if flag.key then savedFlags[flag.key] = flag.hidden end
                restoreFlag(group, flag)
            end
        end
        if group.grouped and not anchor.grouped then adoptStandalone(group, anchor) end
        if not group.grouped and anchor.grouped then releaseStandaloneInset(group, preferred) end
        releaseObservers(group)
        for _, panel in ipairs(group.members) do
            local tabs = {}
            for i, host in ipairs(group.hosts) do tabs[host.key] = group.bindings[panel].tabs[i] end
            oldTabs[panel] = tabs
        end
        local oldOverflows = {}
        local nativeTabs = {}
        for _, host in ipairs(group.hosts) do
            if host.overflow then oldOverflows[#oldOverflows + 1] = host.overflow end
            if not group.frames[host.key] then byFrame[host.key] = nil end
            nativeTabs[host.key] = host.nativeTab
            for _, key in ipairs({ "tabBuffer", "seam", "divider" }) do
                if host[key] and live(group) then host[key]:Destroy() end
            end
        end
        group.current = nil
        group.hosts = hosts
        for i, host in ipairs(hosts) do
            local fresh = capture(host.spec, group.area, true, host.previewIncoming and group.previewBase)
            if not fresh or fresh.key ~= host.key then error("native row changed during tab restoration") end
            hosts[i] = fresh
        end
        for i, host in ipairs(hosts) do
            byFrame[host.key] = group
            if host.key == preferred.key then group.current = i end
            createHost(group, host, previous[host.key] and previous[host.key].chrome)
            previous[host.key] = nil -- its chrome was reused; only removed rows remain
            for _, flag in ipairs(host.flags) do
                if flag.key and savedFlags[flag.key] ~= nil then flag.hidden = savedFlags[flag.key] end
            end
        end
        group.current = group.current or selectedFrame(group) or 1
        for _, panel in ipairs(group.members) do
            local binding, tabs = group.bindings[panel], oldTabs[panel]
            local updated = {}
            for i, host in ipairs(hosts) do
                local tab = tabs[host.key]
                if tab then
                    if tab.visual and live(group) then tab.visual:Destroy() end
                    makeVisual(tab, host, panel.tabIcon or art.defaultIcon)
                    tabs[host.key] = nil
                else
                    tab = newTab(group, host, panel, panel.tabIcon or art.defaultIcon, false)
                end
                updated[i] = tab
            end
            binding.tabs = updated
            for _, tab in pairs(tabs) do destroyTab(tab) end
        end
        for _, host in ipairs(hosts) do
            local tab = nativeTabs[host.key]
            if tab and not group.grouped then
                if tab.visual and live(group) then tab.visual:Destroy() end
                makeVisual(tab, host, host.nativeIcon)
                host.nativeTab = tab
                nativeTabs[host.key] = nil
            elseif not group.grouped then
                host.nativeTab = newTab(group, host, group.members[1], host.nativeIcon, true)
            end
        end
        for _, tab in pairs(nativeTabs) do destroyTab(tab) end
        for _, view in ipairs(oldOverflows) do view:Destroy() end
        for _, oldHost in pairs(previous) do
            if oldHost.chrome and live(group) then oldHost.chrome:Destroy() end
        end
        if active and not group.pending then
            local current = selectedFrame(group)
            if current then
                local host = hosts[current]
                if group.grouped then borrow(group, host) end
                conceal(group, host)
                group.needsConceal = nil
            else
                group.needsConceal = true
            end
        end
        -- Native drop scripts may raise their frame after Logic. Present the new
        -- row's artwork and input together at the following Draw.
        group.paintPending = true
        return true
    end

    local function moveActive(group, current)
        restoreArtwork(group)
        for _, host in ipairs(group.hosts) do
            for _, flag in ipairs(host.flags) do restoreFlag(group, flag) end
        end
        local host = group.hosts[current]
        if group.grouped then borrow(group, host) end
        conceal(group, host)
        group.needsConceal = nil
    end

    local function reconcilePage(group, current)
        if not group.active then return false end
        local host, artwork = group.hosts[current], group.artwork
        if artwork and (artwork.host ~= host or artwork.component[artwork.field] ~= art.tabUnselected) then
            restoreArtwork(group)
        end
        if group.grouped and not group.artwork then borrow(group, host) end
        -- Preserve the active PrettyUI page when native scripts repaint its host.
        local changed = conceal(group, host)
        return changed or artwork ~= group.artwork
    end

    -- Restore the active page's artwork once after the native lock-state reflow.
    local function reconcileLock(group, current)
        if not group.lockTransition then return end
        if group.active then
            local host = group.hosts[current]
            if current ~= group.current then
                moveActive(group, current)
            else
                local saved = group.artwork
                if saved and (saved.host ~= host or saved.component[saved.field] ~= art.tabUnselected) then
                    restoreArtwork(group)
                end
                if group.grouped and not group.artwork then borrow(group, host) end
                conceal(group, host)
                group.needsConceal = nil
            end
        end
        group.lockTransition = nil
        return true
    end

    local function reconcileRoots(group)
        local changed = false
        if not group.nativeRoots then return changed end
        for _, saved in ipairs(group.nativeRoots) do
            if saved.changed then
                local matches = sameLayout(saved.component, saved.inset)
                if matches == nil then error("native content layout retired") end
                if not matches then
                    if not saved.baselineReset or not sameLayout(saved.component, saved.original) then
                        error("native script overwrote tab inset")
                    end
                    local parent, expected = saved.component.parent, saved.inset
                    if parent.width * expected[9] + expected[7] <= 0
                        or parent.height * expected[10] + expected[8] <= 0 then
                        error("native content root resized below its bounds")
                    end
                    -- One baseline reset per lock/familiar-availability transition.
                    -- Keep the allowance across idle ticks for deferred reflow.
                    saved.baselineReset = nil
                    applyLayout(saved.component, expected)
                    if not sameLayout(saved.component, expected) then
                        error("native reflow did not retain tab inset")
                    end
                    changed = true
                end
                if saved.component.width <= 0 or saved.component.height <= 0 then
                    error("native content root resized below its bounds")
                end
            end
        end
        return changed
    end

    -- Native scripts can repaint rows after Logic, reusing components with new
    -- icons. Detect those changes before Draw updates artwork and input positions.
    local function nativeRowChanged(group)
        local selected = selectedFrame(group)
        if selected ~= group.current then return true end
        local host = group.hosts[selected]
        if host and host.tabs.visible ~= host.grouped then return true end
        if not host or not host.grouped then return false end
        if group.incomingPreview and host.key == group.incomingPreview
            and (host.frame.x ~= host.previewTargetX or host.frame.y ~= host.previewTargetY) then return true end
        if Divider.changed(host) then return true end
        if not group.incomingPreview and Host.incomingPreview(group, host) then return true end
        if host.overflow and (host.tabs.x ~= host.overflow.x
            or host.tabs.width ~= host.overflow.width or host.tabs.scrollX ~= host.overflow.scrollX
            or host.content.width ~= host.overflow.bandWidth) then return true end
        local changed, count = false, 0
        host.tabs:IterateDynamicComponents(function(child)
            if not same(child.parent, host.tabs) then return false end
            count = count + 1
            local saved = host.nativeByKey[identity(child)]
            if not saved or saved.component ~= child or child.x ~= saved.x + saved.offset then
                changed = true
                return true
            end
            if saved.tabIcon and spriteID(child) ~= saved.tabIcon then
                changed = true
                return true
            end
            return false
        end)
        return changed or count ~= #host.children
    end

    local function releaseGroup(group)
        local failed
        local function attempt(callback)
            local ok, problem = pcall(callback)
            if not ok then failed = failed or problem end
        end
        attempt(function() stopSortInputs(group); group.nativeSort = nil end)
        if group.constructingTab then
            attempt(function() destroyTab(group.constructingTab); group.constructingTab = nil end)
        end
        attempt(function() nativePage(group) end)
        attempt(function() releaseObservers(group) end)
        for _, host in ipairs(group.hosts) do
            if host.grouped then
                attempt(function() Divider.restore(host) end)
                attempt(function() TabLayout.restore(host.tabs) end)
            end
        end
        if group.nativeRoots then
            for _, saved in ipairs(group.nativeRoots) do
                if saved.changed then
                    attempt(function()
                        if live(group) and identity(saved.component) == saved.key
                            and ui.Interfaces:GetInterface(saved.owner) ~= nil then
                            applyLayout(saved.component, saved.original)
                            Components.setHidden(saved.component, saved.hidden)
                        end
                        saved.changed = false
                    end)
                end
            end
        end
        for _, host in ipairs(group.hosts) do
            if host.nativeTab then attempt(function() destroyTab(host.nativeTab); host.nativeTab = nil end) end
            if host.seam then
                attempt(function() if live(group) then host.seam:Destroy() end; host.seam = nil end)
            end
            if host.overflow then
                attempt(function() host.overflow:Destroy(); host.overflow = nil end)
            end
            for _, key in ipairs({ "tabBuffer", "seam", "divider", "chrome" }) do
                local owned = host[key]
                if owned then
                    attempt(function()
                        if live(group) then owned:Destroy() end
                        host[key] = nil
                    end)
                end
            end
        end
        if failed then
            group.failure = failed
            warn(failed)
            return false
        end
        return true
    end

    return {
        createHost = createHost,
        reconcile = reconcile,
        moveActive = moveActive,
        reconcilePage = reconcilePage,
        reconcileLock = reconcileLock,
        reconcileRoots = reconcileRoots,
        nativeRowChanged = nativeRowChanged,
        releaseGroup = releaseGroup,
    }
end

return NativeReconcile
