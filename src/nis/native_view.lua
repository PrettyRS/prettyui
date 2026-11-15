-- Owns synthetic tabs, mixed-row placement and docked-page visibility.
-- Coordinator callbacks keep selection and restoration policy out of rendering.
local Components = require("src/core/components")
local Sprites = require("src/core/sprites")
local Tooltip = require("src/tooltip")
local Cursor = require("src/core/cursor")
local InterfaceMouse = require("src/core/mouse")
local TabLayout = require("src/nis/native_tab_layout")
local Overflow = require("src/nis/native_overflow")

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

    local function conceal(group, host)
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

    local function restoreArtwork(group)
        local saved = group.artwork
        if not saved then return end
        if Host.live(group) and Host.identity(saved.component) == saved.key then
            local current = saved.component[saved.field]
            if current == art.tabUnselected then
                local another = false
                for _, bg in ipairs(saved.host.backgrounds) do
                    if bg.key ~= saved.key and bg.component.visible and not bg.component.hidden
                        and Host.spriteID(bg.component) == art.tabSelected then another = true; break end
                end
                if not another then saved.component[saved.field] = saved.original end
            end
        end
        group.artwork = nil
    end

    local function hideSeams(group)
        for _, host in ipairs(group.hosts) do
            if host.seam and not host.seam.hidden then Components.setHidden(host.seam, true) end
        end
    end

    local function nativePage(group)
        hideSeams(group)
        restoreArtwork(group)
        for _, host in ipairs(group.hosts) do
            for _, saved in ipairs(host.flags) do restoreFlag(group, saved) end
            if host.nativeTab then host.nativeTab.background.spriteID = art.tabUnselected end
        end
        group.active, group.pending, group.needsConceal = nil, nil, nil
    end

    local function borrow(group, host)
        if group.artwork then return end
        local chosen
        for _, bg in ipairs(host.backgrounds) do
            if bg.component.visibleGlobal and not bg.component.hidden
                and Host.spriteID(bg.component) == art.tabSelected then
                if chosen then return end -- Multiple selected backgrounds are ambiguous.
                chosen = bg
            end
        end
        if not chosen then return end -- the native getter need not reflect the painted page
        local saved = { component = chosen.component, key = chosen.key, field = chosen.field,
            original = art.tabSelected, host = host }
        group.artwork = saved -- before a setter that can partially apply
        chosen.component[chosen.field] = art.tabUnselected -- Native tabs paint from the editor sprite field.
        if chosen.component[chosen.field] ~= art.tabUnselected then error("native editor-field write failed") end
    end

    local function ownSprite(parent, resource)
        local item = Components.new(ui.Sprite, parent)
        item.spriteID, item.clickthrough = resource, true
        return item
    end

    local function selectTab(tab, selected)
        local value = selected and art.tabSelected or art.tabUnselected
        if tab.background.spriteID ~= value then tab.background.spriteID = value end
        if tab.seam.hidden == (not selected) then Components.setHidden(tab.seam, selected) end
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
        tab.background = ownSprite(tab.visual, art.tabUnselected)
        tab.background:SetSize(WIDTH, HEIGHT)
        -- Unselected tab sprites can paint over the native strip's divider.
        tab.seam = ownSprite(tab.visual, art.tabBarTile)
        tab.seam:SetPos(0, HEIGHT - SEAM)
        tab.seam:SetSize(WIDTH, SEAM)
        tab.seam.isTiling = true
        local iconSprite = ownSprite(tab.visual, icon)
        iconSprite:SetPos(8, 2)
        iconSprite:SetSize(24, 24)
    end

    local function newTab(group, host, panel, icon, native)
        local tab = setmetatable({ member = panel, frameID = host.owner,
            interfaceID = panel.interfaceID, host = host, group = group, native = native }, Tab)
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
            tab.hit:Subscribe(ui.Hook.ONDRAGCOMPLETE, function(component, _, x, y)
                return stop(component, x, y)
            end)
            Tooltip.bind(tab, tab.hit, panel.parent, {
                text = panel.tabText or "Panel", placement = "above", placementFallback = false,
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
            local input = show and width > 0 and not sorting
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
        for child in pairs(scroll.childScrolls or {}) do cancelScrollCapture(child) end
    end

    local function suspend(group)
        group.transient = true
        for _, panel in ipairs(group.members) do
            local binding = group.bindings[panel]
            for _, tab in ipairs(binding.tabs) do
                if tab.visual then alignTab(tab, tab.x or 0, tab.y or 0, false) end
            end
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
        for _, host in ipairs(group.hosts) do
            if host.nativeTab and host.nativeTab.visual then
                alignTab(host.nativeTab, host.nativeTab.x, host.nativeTab.y, false)
            end
            if host.seam and not host.seam.hidden then Components.setHidden(host.seam, true) end
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

    local function insertionAt(group, host, center, excluded)
        local before, destination, sourceIndex = 0, 1, group and #group.members + 1 or 1
        if group then
            for index, member in ipairs(group.members) do
                if member == excluded then sourceIndex = index; break end
            end
        end
        local origin = group and Host.tabOrigin(host)
        if host.grouped then
            for index, bg in ipairs(host.backgrounds) do
                local offset = group and nativeOffset(group, host, index, excluded) or 0
                if center <= bg.layout.x + offset + bg.component.width / 2 then break end
                before = index
            end
        elseif center > (group and nativeOffset(group, host, 1, excluded) or 0) + WIDTH / 2 then
            before = 1
        end
        if group then
            for index, member in ipairs(group.members) do
                if member ~= excluded then
                    local count = beforeNative(group, member, host)
                    local midpoint = ownX(group, host, index, true) - origin + WIDTH / 2
                    if count > before or count == before and (center < midpoint
                        or center == midpoint and sourceIndex > index) then break end
                    destination = destination + 1
                end
            end
        end
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

    local function alignNativeTabs(group, host, animate)
        if not host.grouped then return end
        for index, bg in ipairs(host.backgrounds) do
            local offset = nativeOffset(group, host, index) + previewOffset(group, index)
            if animate then offset = host.nativeSlides[bg.key] or offset end
            for _, saved in ipairs(host.nativeLayout) do
                -- Direct children carry native backgrounds, icons, badges and
                -- input; descendants follow their native parent automatically.
                local center = saved.x + saved.width / 2
                if saved.width <= bg.component.width and center >= bg.layout.x
                    and center < bg.layout.x + bg.component.width then
                    assert(TabLayout.move(saved, offset) ~= false, "native tab position overwritten")
                end
            end
        end
    end

    local function scrollPosition(group, current)
        local host = group.hosts[current]
        local total = host.used + WIDTH * (#group.members + (group.dockPreview and group.dockPreview.count or 0))
        local width = Overflow.width(host, total)
        local scroll = group.tabScroll
        if scroll == nil then scroll = host.grouped and host.tabs.scrollX or 0 end
        scroll = scroll or 0
        if not group.scrollRequested and host.grouped and host.overflow
            and host.tabs.scrollX ~= nil and host.tabs.scrollX ~= host.overflow.scrollX then
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

    local function align(group)
        local current = Host.selectedFrame(group)
        if not current then error("native group has no unique visible frame") end
        local scroll = scrollPosition(group, current)
        for i, host in ipairs(group.hosts) do
            local show = i == current
            local band = Host.tabBand(host)
            local chrome = host.chrome
            local x, y, width, height = Host.rectInParent(group.members[1], host.frame)
            if chrome.x ~= x or chrome.y ~= y then chrome:SetPos(x, y) end
            if chrome.width ~= width or chrome.height ~= height then chrome:SetSize(width, height) end
            if chrome.hidden == show then Components.setHidden(chrome, not show) end
            host.overflow:Layout(host.used + WIDTH * (#group.members
                + (group.dockPreview and group.dockPreview.count or 0)), scroll, show, not group.tabDrag)
            if host.tabBuffer then
                if host.tabBuffer.x ~= band.x or host.tabBuffer.y ~= band.y then
                    host.tabBuffer:SetPos(band.x, band.y)
                end
                if host.tabBuffer.width ~= band.width then host.tabBuffer:SetSize(band.width, HEIGHT - SEAM) end
            end
            if host.nativeTab then
                local target = Host.tabOrigin(host) + nativeOffset(group, host, 1) + previewOffset(group, 1)
                local x = (group.tabDrag or group.dockPreview) and show and host.nativeTab.slideX or target
                alignTab(host.nativeTab, (x or target) - scroll, band.y, show)
                selectTab(host.nativeTab, not group.active and show)
            end
            if host.divider then
                local dx, dy = band.x, band.y + HEIGHT - SEAM
                if host.divider.x ~= dx or host.divider.y ~= dy then host.divider:SetPos(dx, dy) end
                if host.divider.width ~= band.width then host.divider:SetSize(band.width, SEAM) end
            end
            alignNativeTabs(group, host, (group.tabDrag ~= nil or group.dockPreview ~= nil) and show)
            for index, panel in ipairs(group.members) do
                local tab = group.bindings[panel].tabs[i]
                local target = ownX(group, host, index)
                local drag = group.tabDrag
                local x = target
                if (drag or group.dockPreview) and show then
                    if drag and drag.panel == panel then
                        x = drag.x - chrome.x + scroll
                    else
                        x = tab.slideX or target
                    end
                end
                alignTab(tab, x - scroll, band.y, show)
                selectTab(tab, show and group.active == panel)
            end
            local seam = host.seam
            if seam then
                local selected = show and group.active ~= nil
                    and group.artwork ~= nil and group.artwork.host == host
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
            local binding = group.bindings[panel]
            if panel.root and ui.Interfaces:GetInterface(panel.interfaceID) then
                local x, y, width, height = Host.rectInParent(panel, host.content)
                if not group.grouped then y, height = y + HEIGHT, height - HEIGHT end
                local changed = panel.root.x ~= x or panel.root.y ~= y
                    or panel.root.width ~= width or panel.root.height ~= height
                if changed or binding.visible == nil then
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
                local visible = group.active == panel and panel._nisHidden ~= true
                local visibilityChanged = binding.visible ~= visible or panel.root.hidden == visible
                    or panel.root.enabled ~= visible
                if visibilityChanged then
                    if not visible then cancelScrollCapture(panel._scroll) end
                    Components.setHidden(panel.root, not visible)
                    panel.root.enabled = visible
                    if not visible and panel.content then Tooltip.hideContextTooltips(panel.content) end
                    if panel._scroll then panel._scroll:_RefreshClipTargets() end
                end
                if not group.attaching and not actions.isRestoringBatch() then panel:_SyncContent(visible) end
                if changed or visibilityChanged then
                    panel:_SyncChrome()
                    panel:_SyncOverlays(not visible)
                end
                binding.visible = visible
                binding.current = current
            end
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
