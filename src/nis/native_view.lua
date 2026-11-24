-- Owns synthetic tabs, mixed-row placement and docked-page visibility.
-- Coordinator callbacks keep selection and restoration policy out of rendering.
local Components = require("src/core/components")
local Sprites = require("src/core/sprites")
local Tooltip = require("src/tooltip")
local Cursor = require("src/core/cursor")
local InterfaceMouse = require("src/core/mouse")
local TabLayout = require("src/nis/native_tab_layout")
local Overflow = require("src/nis/native_overflow")
local Divider = require("src/nis/native_divider")

local art = Sprites.NIS_PANEL

local View = {}

function View.new(Host, actions)
    local HEIGHT, WIDTH, SEAM = Host.HEIGHT, Host.WIDTH, Host.SEAM

    local function restoreFlag(group, saved)
        if not saved.changed then return end
        if Host.live(group) and Host.identity(saved.component) == saved.key then
            Components.setHidden(saved.component, saved.hidden)
        end
        saved.changed = false
    end

    local function conceal(_group, host)
        local changed = false
        for _, saved in ipairs(host.flags) do
            saved.changed = true -- setter may apply before throwing
            if not saved.component.hidden then
                Components.setHidden(saved.component, true)
                changed = true
            end
        end
        return changed
    end

    local function anotherSelectedBackground(saved)
        for _, bg in ipairs(saved.host.backgrounds) do
            if
                bg.key ~= saved.key
                and bg.component.visible
                and not bg.component.hidden
                and Host.spriteID(bg.component) == art.tabSelected
            then
                return true
            end
        end
        return false
    end

    local function restoreArtwork(group)
        local saved = group.artwork
        if not saved then return end
        if Host.live(group) and Host.identity(saved.component) == saved.key then
            local current = saved.component[saved.field]
            if current == art.tabUnselected and not anotherSelectedBackground(saved) then
                saved.component[saved.field] = saved.original
            end
        end
        group.artwork = nil
    end

    local function hideSeams(group)
        for _, host in ipairs(group.hosts) do
            if host.seam and not host.seam.hidden then Components.setHidden(host.seam, true) end
        end
    end

    local function selectTab(tab, selected)
        local value = selected and art.tabSelected or art.tabUnselected
        if tab.background.spriteID ~= value then tab.background.spriteID = value end
        local height = selected and HEIGHT or HEIGHT - SEAM
        if tab.artwork.height ~= height then tab.artwork:SetSize(WIDTH, height) end
        if tab.seam.hidden == not selected then Components.setHidden(tab.seam, selected) end
    end

    local function nativePage(group)
        hideSeams(group)
        restoreArtwork(group)
        for _, host in ipairs(group.hosts) do
            for _, saved in ipairs(host.flags) do
                restoreFlag(group, saved)
            end
            if host.nativeTab then selectTab(host.nativeTab, false) end
        end
        group.active, group.pending, group.needsConceal = nil, nil, nil
    end

    local function borrow(group, host)
        if group.artwork then return end
        local chosen
        for _, bg in ipairs(host.backgrounds) do
            if
                bg.component.visibleGlobal
                and not bg.component.hidden
                and Host.spriteID(bg.component) == art.tabSelected
            then
                if chosen then return end -- Multiple selected backgrounds are ambiguous.
                chosen = bg
            end
        end
        if not chosen then return end -- the native getter need not reflect the painted page
        local saved = {
            component = chosen.component,
            key = chosen.key,
            field = chosen.field,
            original = art.tabSelected,
            host = host,
        }
        group.artwork = saved -- before a setter that can partially apply
        chosen.component[chosen.field] = art.tabUnselected -- Native tabs paint from the editor sprite field.
        if chosen.component[chosen.field] ~= art.tabUnselected then error("native editor-field write failed") end
    end

    local function ownSprite(parent, resource)
        local item = Components.new(ui.Sprite, parent)
        item.sprite, item.clickthrough = resource, true
        return item
    end

    local function releaseTab(tab)
        if tab.tooltipAttachment then tab.tooltipAttachment:Hide() end
        Tooltip.unbind(tab, "tooltipAttachment")
        if tab.hit and ui.Interfaces:GetInterface(tab.interfaceID) then tab.hit:Destroy() end
        tab.hit, tab.retained, tab.dragOwner = nil, nil, nil
    end

    local Tab = {}
    Tab.__index = Tab
    Tab.Release = releaseTab

    local function destroyTab(tab)
        if tab.visual and ui.Interfaces:GetInterface(tab.frameID) then tab.visual:Destroy() end
        tab.visual = nil
        if tab.retained then
            -- The drag gesture owns the enlarged GAME_AREA capture until release.
            if tab.tooltipAttachment then tab.tooltipAttachment:Hide() end
            Tooltip.unbind(tab, "tooltipAttachment")
        else
            tab:Release()
        end
    end

    local function makeVisual(tab, host, icon)
        tab.host, tab.frameID = host, host.owner
        tab.visual = Components.new(ui.Layer, host.overflow.viewport, { _categoryPolicy = "auto" })
        tab.visual:SetSize(WIDTH, HEIGHT)
        tab.visual.clickthrough = true
        -- Clip inactive artwork instead of relying on the separator sprite to
        -- cover it: transparent separator pixels must reveal the native strip.
        tab.artwork = Components.new(ui.Layer, tab.visual)
        tab.artwork:SetSize(WIDTH, HEIGHT - SEAM)
        tab.artwork:SetScrollSize(WIDTH, HEIGHT)
        tab.artwork.clickthrough = true
        tab.background = ownSprite(tab.artwork, art.tabUnselected)
        tab.background:SetSize(WIDTH, HEIGHT)
        local iconSprite = ownSprite(tab.artwork, icon)
        iconSprite:SetPos(8, 2)
        iconSprite:SetSize(24, 24)
        -- Only the selected tab may paint through the separator.
        tab.seam = ownSprite(tab.visual, art.tabBarTile)
        tab.seam:SetPos(0, HEIGHT - SEAM)
        tab.seam:SetSize(WIDTH, SEAM)
        tab.seam.isTiling = true
    end

    local function newTab(group, host, panel, icon, native)
        local tab = setmetatable({
            member = panel,
            frameID = host.owner,
            interfaceID = panel.interfaceID,
            host = host,
            group = group,
            native = native,
        }, Tab)
        group.constructingTab = tab
        makeVisual(tab, host, icon)
        tab.hit = Components.new(ui.Layer, panel.parent, {
            _categoryPolicy = Components.policyOf(panel.root),
        })
        tab.hit:SetSize(WIDTH, HEIGHT)
        tab.hit.clickthrough = false
        Components.setHidden(tab.hit, true)
        tab.hit.enabled = false
        Cursor.apply(tab.hit, nil, false)
        if native then
            tab.hit:Subscribe(ui.Hook.ONCLICK, function()
                local ok, problem = pcall(function()
                    nativePage(group)
                    actions.sync(panel)
                end)
                if not ok then group.failure = problem end
                return false
            end)
        else
            tab.hit:Subscribe(ui.Hook.ONCLICK, function(component, x, y)
                local actor = tab.dragOwner or panel
                local ok, problem = pcall(function()
                    actor:_BeginNativeTabDrag(component, x, y, tab)
                    actions.select(panel)
                end)
                if not ok then group.failure = problem end
                return false
            end)
            local function move(component, x, y)
                local actor = tab.dragOwner or panel
                local ok, problem = pcall(function() actor:_MoveNativeTabDrag(component, x, y) end)
                if not ok then group.failure = problem end
                return false
            end
            tab.hit:Subscribe(ui.Hook.ONHOLD, move)
            tab.hit:Subscribe(ui.Hook.ONDRAG, move)
            local function stop(component, x, y)
                local actor = tab.dragOwner or panel
                local ok, problem = pcall(function() actor:_StopNativeTabDrag(component, x, y) end)
                if not ok then group.failure = problem end
                return false
            end
            tab.hit:Subscribe(ui.Hook.ONRELEASE, stop)
            tab.hit:Subscribe(
                ui.Hook.ONDRAGCOMPLETE,
                function(component, _, x, y)
                    return stop(component, x, y)
                end
            )
            Tooltip.bind(tab, tab.hit, panel.parent, {
                text = panel.tabText or "Panel",
                placement = "above",
                placementFallback = false,
            }, "tooltipAttachment")
        end
        group.constructingTab = nil
        return tab
    end

    local function alignTab(tab, x, y, show, sorting)
        if not tab.visual then return end
        local view = tab.host.overflow
        tab.x, tab.y = x, y
        local vx, vy = x - view.viewport.x, y - view.viewport.y
        if tab.visual.x ~= vx or tab.visual.y ~= vy then tab.visual:SetPos(vx, vy) end
        if tab.visual.hidden == show then Components.setHidden(tab.visual, not show) end
        local hit = tab.hit
        if hit and not tab.retained then
            local left, width = view:Clip(x, WIDTH)
            tab.clipOffset = left - x
            local tx, ty = Host.rectInParent(tab.member or tab.group.members[1], tab.host.frame)
            tx, ty = tx + left, ty + y
            if hit.x ~= tx or hit.y ~= ty then hit:SetPos(tx, ty) end
            if hit.width ~= width then hit:SetSize(width, HEIGHT) end
            local input = show and width > 0 and not sorting and not tab.group.incomingPreview
            if hit.hidden == input then Components.setHidden(hit, not input) end
            if hit.enabled ~= input then hit.enabled = input end
            if input and not tab.shown then hit:MoveToFront() end
            if not input and tab.tooltipAttachment then tab.tooltipAttachment:Hide() end
            tab.shown = input
        end
    end

    local function cancelScrollCapture(scroll)
        if not scroll then return end
        if scroll.dragStart and scroll.thumbDrag then
            InterfaceMouse.EndCapture(scroll.thumbDrag)
            scroll.dragStart = nil
            scroll.thumbCaptureExpanded = false
            Components.setHidden(scroll.thumbDrag, true)
        end
        for child in pairs(scroll.childScrolls or {}) do
            cancelScrollCapture(child)
        end
    end

    local function suspendPanel(panel, binding)
        if not panel.root or not ui.Interfaces:GetInterface(panel.interfaceID) then return end
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

    local function suspend(group)
        group.transient = true
        for _, panel in ipairs(group.members) do
            local binding = group.bindings[panel]
            for _, tab in ipairs(binding.tabs) do
                if tab.visual then alignTab(tab, tab.x or 0, tab.y or 0, false) end
            end
            suspendPanel(panel, binding)
        end
        for _, host in ipairs(group.hosts) do
            if host.nativeTab and host.nativeTab.visual then
                alignTab(host.nativeTab, host.nativeTab.x, host.nativeTab.y, false)
            end
            if host.seam and not host.seam.hidden then Components.setHidden(host.seam, true) end
            if host.grouped then Divider.restore(host) end
            if host.chrome and not host.chrome.hidden then Components.setHidden(host.chrome, true) end
            if host.overflow then host.overflow:Hide() end
        end
    end

    local function nativeCount(host)
        return host.grouped and #host.backgrounds or 1
    end

    local function beforeNative(group, panel, host)
        return math.min(group.bindings[panel].beforeNative or nativeCount(host), nativeCount(host))
    end

    local function nativeOffset(group, host, nativeIndex, excluded)
        local offset = 0
        for _, panel in ipairs(group.members) do
            if panel ~= excluded and beforeNative(group, panel, host) < nativeIndex then offset = offset + WIDTH end
        end
        return offset
    end
    local function previewOffset(group, nativeIndex)
        local preview = group and group.dockPreview
        return preview and preview.insertion.beforeNative < nativeIndex and preview.count * WIDTH or 0
    end

    local function ownX(group, host, memberIndex, ignorePreview)
        local count = beforeNative(group, group.members[memberIndex], host)
        local x
        if count == 0 then
            x = host.grouped and host.backgrounds[1].layout.x or 0
        elseif host.grouped then
            local bg = host.backgrounds[count]
            x = bg.layout.x + bg.component.width
        else
            x = WIDTH
        end
        local preview = not ignorePreview and group.dockPreview
        local gap = preview and memberIndex >= preview.insertion.index and preview.count * WIDTH or 0
        return Host.tabOrigin(host) + x + (memberIndex - 1) * WIDTH + gap
    end

    local function destinationAt(group, host, center, excluded, before, sourceIndex)
        local destination = 1
        local origin = Host.tabOrigin(host)
        for index, member in ipairs(group.members) do
            if member ~= excluded then
                local count = beforeNative(group, member, host)
                local midpoint = ownX(group, host, index, true) - origin + WIDTH / 2
                if
                    count > before
                    or count == before and (center < midpoint or center == midpoint and sourceIndex > index)
                then
                    break
                end
                destination = destination + 1
            end
        end
        return destination
    end

    local function insertionAt(group, host, center, excluded)
        local before, destination, sourceIndex = 0, 1, group and #group.members + 1 or 1
        if group then
            for index, member in ipairs(group.members) do
                if member == excluded then
                    sourceIndex = index
                    break
                end
            end
        end
        if host.grouped then
            for index, bg in ipairs(host.backgrounds) do
                local offset = group and nativeOffset(group, host, index, excluded) or 0
                if center <= bg.layout.x + offset + bg.component.width / 2 then break end
                before = index
            end
        elseif center > (group and nativeOffset(group, host, 1, excluded) or 0) + WIDTH / 2 then
            before = 1
        end
        if group then destination = destinationAt(group, host, center, excluded, before, sourceIndex) end
        return before, destination, sourceIndex
    end

    local function startSlides(group)
        for _, member in ipairs(group.members) do
            for _, tab in ipairs(group.bindings[member].tabs) do
                if tab.visual then tab.slideX = tab.x + Host.tabScroll(tab.host) end
            end
        end
        for _, host in ipairs(group.hosts) do
            if host.nativeTab then
                host.nativeTab.slideX = host.nativeTab.x + Host.tabScroll(host)
            else
                for _, bg in ipairs(host.backgrounds) do
                    host.nativeSlides[bg.key] = bg.layout.offset
                end
            end
        end
    end

    local function slide(x, target)
        local delta = target - x
        return x + (delta > 0 and 1 or -1) * math.ceil(math.abs(delta) * 0.4)
    end

    -- The client's captured tab follows the pointer, not the slot that it
    -- will occupy on release. Pack peers around its actual footprint, without
    -- moving that component or changing the saved insertion points.
    local function clearGhost(x, width, left, right)
        if x < right and x + width > left then return right end
        return x
    end

    local function incomingSlots(group, host)
        if group.incomingPreview ~= host.key or not host.previewSource then return nil end
        local source = host.backgrounds[host.previewSource].component
        local left, right = source.x, source.x + source.width
        -- A native repaint can move the icon and badge one draw after their
        -- background. Reserve those visible pixels without touching capture.
        for _, record in ipairs(host.nativeLayout) do
            local child = record.component
            if record.nativeSlot == host.previewSource and child.visible and not child.hidden then
                left, right = math.min(left, child.x), math.max(right, child.x + child.width)
            end
        end
        local slots = host.previewSlots or { native = {}, own = {} }
        host.previewSlots = slots
        local x, member, peers = 0, 1, #host.backgrounds - 1
        for before = 0, peers do
            while member <= #group.members do
                local binding = group.bindings[group.members[member]]
                if math.min(binding.beforeNative or peers, peers) ~= before then break end
                x = clearGhost(x, WIDTH, left, right)
                slots.own[member] = x
                x, member = x + WIDTH, member + 1
            end
            local index = before + 1
            if index >= host.previewSource then index = index + 1 end
            local bg = host.backgrounds[index]
            if bg then
                local width = bg.component.width
                x = clearGhost(x, width, left, right)
                slots.native[index] = x - bg.layout.x
                x = x + width
            end
        end
        slots.used = math.max(x, right)
        return slots
    end

    local function alignIncomingTabs(host, slots)
        for _, saved in ipairs(host.nativeLayout) do
            local index = saved.nativeSlot
            if index and index ~= host.previewSource then
                assert(TabLayout.move(saved, slots.native[index]) ~= false, "native preview peer position overwritten")
            end
        end
    end

    local function alignNativeTabs(group, host, animate)
        if not host.grouped then return end
        for index, bg in ipairs(host.backgrounds) do
            local offset = nativeOffset(group, host, index) + previewOffset(group, index)
            if animate then offset = host.nativeSlides[bg.key] or offset end
            for _, saved in ipairs(host.nativeLayout) do
                -- Direct children carry native backgrounds, icons, badges and
                -- input; descendants follow their native parent automatically.
                local center = saved.x + saved.width / 2
                if
                    saved.width <= bg.component.width
                    and center >= bg.layout.x
                    and center < bg.layout.x + bg.component.width
                then
                    assert(TabLayout.move(saved, offset) ~= false, "native tab position overwritten")
                end
            end
        end
    end

    local function selectedNative(host)
        local chosen
        for _, bg in ipairs(host.backgrounds) do
            if
                bg.component.visibleGlobal
                and not bg.component.hidden
                and Host.spriteID(bg.component) == art.tabSelected
            then
                if chosen then return nil end
                chosen = bg
            end
        end
        return chosen
    end

    local function alignDivider(group, host, frameIndex, show)
        if not host.grouped then return end
        if not show then
            Divider.restore(host)
            return
        end
        local x, width
        if group.active then
            for _, panel in ipairs(group.members) do
                if panel == group.active then
                    local tab = group.bindings[panel].tabs[frameIndex]
                    x, width = tab.x, WIDTH
                    break
                end
            end
        else
            local selected = selectedNative(host)
            if selected then
                x = host.tabs.x + selected.component.x - (host.tabs.scrollX or 0)
                width = selected.component.width
            end
        end
        if not x then
            Divider.restore(host)
            return
        end
        local clipped, visibleWidth = host.overflow:Clip(x, width)
        Divider.align(host, clipped - host.backdrop.x, visibleWidth)
    end

    local function rowExtent(group, host, slots)
        if slots then return slots.used end
        return host.used + WIDTH * (#group.members + (group.dockPreview and group.dockPreview.count or 0))
    end

    local function scrollPosition(group, current, slots)
        local host = group.hosts[current]
        local total = rowExtent(group, host, slots)
        local width = Overflow.width(host, total)
        local scroll = group.tabScroll
        if scroll == nil then scroll = host.grouped and host.tabs.scrollX or 0 end
        scroll = scroll or 0
        if
            not group.scrollRequested
            and host.grouped
            and host.overflow
            and host.tabs.scrollX ~= nil
            and host.tabs.scrollX ~= host.overflow.scrollX
        then
            scroll = host.tabs.scrollX
        end
        local reveal = group.revealTab
            or host.overflow and host.overflow.bandWidth ~= host.content.width and group.active
        if reveal and not group.tabDrag and not group.nativeSort then
            for index, member in ipairs(group.members) do
                if member == reveal then
                    local left = ownX(group, host, index) - Host.tabOrigin(host)
                    scroll = math.min(scroll, left)
                    scroll = math.max(scroll, left + WIDTH - width)
                    break
                end
            end
        end
        group.tabScroll = math.max(0, math.min(scroll, total - width))
        group.revealTab, group.scrollRequested = nil, nil
        return group.tabScroll
    end

    local function alignHostChrome(group, host, band, scroll, show, preview)
        local chrome = host.chrome
        local x, y, width, height = Host.rectInParent(group.members[1], host.frame)
        if chrome.x ~= x or chrome.y ~= y then chrome:SetPos(x, y) end
        if chrome.width ~= width or chrome.height ~= height then chrome:SetSize(width, height) end
        if chrome.hidden == show then Components.setHidden(chrome, not show) end
        host.overflow:Layout(
            rowExtent(group, host, preview),
            scroll,
            show,
            not group.tabDrag and not group.incomingPreview
        )
        if host.tabBuffer then
            if host.tabBuffer.x ~= band.x or host.tabBuffer.y ~= band.y then
                host.tabBuffer:SetPos(band.x, band.y)
            end
            if host.tabBuffer.width ~= band.width then host.tabBuffer:SetSize(band.width, HEIGHT - SEAM) end
        end
    end

    local function alignHostNativeTab(group, host, band, scroll, show)
        if not host.nativeTab then return end
        local target = Host.tabOrigin(host) + nativeOffset(group, host, 1) + previewOffset(group, 1)
        local slideX = (group.tabDrag or group.dockPreview) and show and host.nativeTab.slideX or target
        alignTab(host.nativeTab, (slideX or target) - scroll, band.y, show)
        selectTab(host.nativeTab, not group.active and show)
    end

    local function alignMemberTab(group, host, band, scroll, show, hostIndex, index, panel, preview)
        local tab = group.bindings[panel].tabs[hostIndex]
        local target = preview and Host.tabOrigin(host) + preview.own[index] or ownX(group, host, index)
        local drag = group.tabDrag
        local tabX = target
        if (drag or group.dockPreview) and show then
            if drag and drag.panel == panel then
                tabX = drag.x - host.chrome.x + scroll
            else
                tabX = tab.slideX or target
            end
        end
        alignTab(tab, tabX - scroll, band.y, show)
        selectTab(tab, show and group.active == panel)
    end

    local function alignSeam(group, host, scroll, show)
        local seam = host.seam
        if not seam then return end
        local selected = show and group.active ~= nil and group.artwork ~= nil and group.artwork.host == host
        if selected then
            local bg = group.artwork.component
            local x, width = host.overflow:Clip(host.tabs.x + bg.x - scroll, bg.width)
            local y = host.tabs.y + HEIGHT - SEAM
            x, y = x - host.overflow.viewport.x, y - host.overflow.viewport.y
            if seam.x ~= x or seam.y ~= y then seam:SetPos(x, y) end
            if seam.width ~= width or seam.height ~= SEAM then seam:SetSize(width, SEAM) end
        end
        if seam.hidden == selected then Components.setHidden(seam, not selected) end
    end

    local function alignHost(group, host, hostIndex, current, scroll, slots)
        local show = hostIndex == current
        local band = Host.tabBand(host)
        local preview = show and slots
        alignHostChrome(group, host, band, scroll, show, preview)
        alignHostNativeTab(group, host, band, scroll, show)
        if host.divider then
            local dx, dy = band.x, band.y + HEIGHT - SEAM
            if host.divider.x ~= dx or host.divider.y ~= dy then host.divider:SetPos(dx, dy) end
            if host.divider.width ~= band.width then host.divider:SetSize(band.width, SEAM) end
        end
        if preview then
            alignIncomingTabs(host, preview)
        else
            alignNativeTabs(group, host, (group.tabDrag ~= nil or group.dockPreview ~= nil) and show)
        end
        for index, panel in ipairs(group.members) do
            alignMemberTab(group, host, band, scroll, show, hostIndex, index, panel, preview)
        end
        alignDivider(group, host, hostIndex, show)
        alignSeam(group, host, scroll, show)
    end

    local function alignPanelBounds(panel, x, y, width, height)
        local old = panel._updatingBounds
        panel._updatingBounds = true
        local ok, problem = pcall(function()
            panel.root:SetPos(x, y)
            panel.root:SetSize(width, height)
            panel.width, panel.height = width, height
            panel:_LayoutBody()
            panel:RefreshRowBackgrounds()
        end)
        panel._updatingBounds = old
        if not ok then error(problem) end
    end

    local function alignPanelVisibility(panel, visible)
        if not visible then cancelScrollCapture(panel._scroll) end
        Components.setHidden(panel.root, not visible)
        panel.root.enabled = visible
        if not visible and panel.content then Tooltip.hideContextTooltips(panel.content) end
        if panel._scroll then panel._scroll:_RefreshClipTargets() end
    end

    local function alignPanel(group, host, current, panel)
        local binding = group.bindings[panel]
        if not panel.root or not ui.Interfaces:GetInterface(panel.interfaceID) then return end
        local x, y, width, height = Host.rectInParent(panel, host.content)
        if not group.grouped then
            y, height = y + HEIGHT, height - HEIGHT
        end
        local changed = panel.root.x ~= x
            or panel.root.y ~= y
            or panel.root.width ~= width
            or panel.root.height ~= height
        if changed or binding.visible == nil then alignPanelBounds(panel, x, y, width, height) end
        local visible = group.active == panel and panel._nisHidden ~= true
        local visibilityChanged = binding.visible ~= visible
            or panel.root.hidden == visible
            or panel.root.enabled ~= visible
        if visibilityChanged then alignPanelVisibility(panel, visible) end
        if not group.attaching and not actions.isRestoringBatch() then panel:_SyncContent(visible) end
        if changed or visibilityChanged then
            panel:_SyncChrome()
            panel:_SyncOverlays(not visible)
        end
        binding.visible = visible
        binding.current = current
    end

    local function align(group)
        local current = Host.selectedFrame(group)
        if not current then error("native group has no unique visible frame") end
        local slots = incomingSlots(group, group.hosts[current])
        local scroll = scrollPosition(group, current, slots)
        for i, host in ipairs(group.hosts) do
            alignHost(group, host, i, current, scroll, slots)
        end
        group.current = current
        -- Attachment aligns once before selecting the incoming page. That temporary
        -- selection is not a content deactivation; commit the lifecycle afterward.
        if not group.attaching and not actions.isRestoringBatch() then
            for _, panel in ipairs(group.members) do
                if panel ~= group.active or panel._nisHidden then panel:_SyncContent(false) end
            end
        end
        local host = group.hosts[current]
        for _, panel in ipairs(group.members) do
            alignPanel(group, host, current, panel)
        end
    end

    local function raiseGroup(group)
        local host = group.hosts[group.current]
        host.chrome:MoveToFront()
        if group.active then
            group.active.root:MoveToFront()
            group.active:_SyncOverlays(false)
        end
        local function raiseTab(tab)
            if tab and tab.shown and tab.hit and not tab.retained then tab.hit:MoveToFront() end
        end
        raiseTab(host.nativeTab)
        for _, panel in ipairs(group.members) do
            raiseTab(group.bindings[panel].tabs[group.current])
        end
        host.overflow:Raise()
    end

    return {
        restoreFlag = restoreFlag,
        conceal = conceal,
        restoreArtwork = restoreArtwork,
        hideSeams = hideSeams,
        nativePage = nativePage,
        borrow = borrow,
        ownSprite = ownSprite,
        selectTab = selectTab,
        destroyTab = destroyTab,
        makeVisual = makeVisual,
        newTab = newTab,
        alignTab = alignTab,
        cancelScrollCapture = cancelScrollCapture,
        suspend = suspend,
        beforeNative = beforeNative,
        nativeOffset = nativeOffset,
        previewOffset = previewOffset,
        ownX = ownX,
        insertionAt = insertionAt,
        startSlides = startSlides,
        slide = slide,
        scrollPosition = scrollPosition,
        align = align,
        raiseGroup = raiseGroup,
    }
end

return View
