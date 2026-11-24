-- Owns the transient docking preview; never changes native membership.
local Components = require("src/core/components")
local Sprites = require("src/core/sprites")
local TabLayout = require("src/nis/native_tab_layout")
local Overflow = require("src/nis/native_overflow")
local WorldMap = require("src/core/world_map")

local NativePreview = {}

function NativePreview.new(Host, View, actions)
    local Preview = {}
    local previewState
    local art = Sprites.NIS_PANEL

    local identity = Host.identity
    local component = Host.component
    local same = Host.same
    local live = Host.live
    local tabBand = Host.tabBand
    local tabScroll = Host.tabScroll
    local frameGroup = Host.frameGroup
    local selectedFrame = Host.selectedFrame
    local rectInParent = Host.rectInParent
    local HEIGHT = Host.HEIGHT
    local WIDTH = Host.WIDTH
    local SEAM = Host.SEAM
    local ownSprite = View.ownSprite
    local insertionAt = View.insertionAt
    local startSlides = View.startSlides
    local slide = View.slide
    local align = View.align

    -- A candidate is a freshly captured native host. Preview owns only GAME_AREA
    -- components; it never parents artwork to a native frame or changes membership.
    function Preview.clear(panel)
        local state = previewState
        if not state or panel and state.panel ~= panel then return end
        local failed
        local function attempt(callback)
            local ok, problem = pcall(callback)
            if not ok then failed = failed or problem end
        end
        if state.group then
            local group = state.group
            if group.dockPreview == state then group.dockPreview = nil end
            if not group.dead and live(group) and not group.nativeSort and selectedFrame(group) then
                attempt(function() align(group) end)
            end
        elseif state.host and state.host.grouped then
            attempt(function() TabLayout.restore(state.host.tabs) end)
        end
        if state.overflow then attempt(function() state.overflow:Destroy() end) end
        if state.chrome then
            attempt(function()
                if
                    ui.Interfaces:GetInterface(state.interfaceID) ~= nil
                    and same(state.area, component(id.Component.TOPLEVEL_V2__GAME_AREA))
                then
                    state.chrome:Destroy()
                end
                state.chrome = nil
            end)
        end
        if failed then error(failed) end
        previewState = nil
        actions.stopTick()
    end

    local function validCandidate(panel, host, group)
        return host
            and panel
            and not panel._destroyed
            and panel.root
            and ui.Interfaces:GetInterface(panel.interfaceID)
            and same(panel.parent, component(id.Component.TOPLEVEL_V2__GAME_AREA))
            and host.frame
            and host.spec
            and not (group and group.nativeSort)
            and identity(component(host.spec.frame)) == host.key
    end

    local function stalePreview(state, panel, host, group, members, synthetic)
        return state.panel ~= panel
            or state.key ~= host.key
            or state.group ~= group
            or state.grouped ~= host.grouped
            or state.count ~= (members and #members or 1)
            or state.nativeIcon ~= host.nativeIcon
            or not state.buffer
            or not state.divider
            or #state.tabs ~= state.count
            or synthetic and not state.nativeTab
    end

    local function addSyntheticTab(state, host)
        local nativeTab = Components.new(ui.Layer, state.overflow.viewport, { _categoryPolicy = "auto" })
        nativeTab:SetPos(tabBand(host).x, tabBand(host).y)
        nativeTab:SetSize(WIDTH, HEIGHT)
        nativeTab.clickthrough = true
        local background = ownSprite(nativeTab, art.tabUnselected)
        background:SetSize(WIDTH, HEIGHT)
        local icon = ownSprite(nativeTab, host.nativeIcon)
        icon:SetPos(8, 2)
        icon:SetSize(24, 24)
        local seam = ownSprite(nativeTab, art.tabBarTile)
        seam:SetPos(0, HEIGHT - SEAM)
        seam:SetSize(WIDTH, SEAM)
        seam.isTiling = true
        state.nativeTab = nativeTab
    end

    local function addMemberTabs(state, panel, members)
        for index = 1, state.count do
            local member = members and members[index] or panel
            local visual = Components.new(ui.Layer, state.overflow.viewport, { _categoryPolicy = "auto" })
            visual:SetSize(WIDTH, HEIGHT)
            visual.clickthrough = true
            local background = ownSprite(
                visual,
                member == (panel._nisGroup and panel._nisGroup.active or panel) and art.tabSelected or art.tabUnselected
            )
            background:SetSize(WIDTH, HEIGHT)
            local icon = ownSprite(visual, member.tabIcon or art.defaultIcon)
            icon:SetPos(8, 2)
            icon:SetSize(24, 24)
            if background.spriteID == art.tabUnselected then
                local seam = ownSprite(visual, art.tabBarTile)
                seam:SetPos(0, HEIGHT - SEAM)
                seam:SetSize(WIDTH, SEAM)
                seam.isTiling = true
            end
            state.tabs[index] = visual
        end
    end

    local function createPreview(panel, host, group, members, synthetic)
        local chrome = Components.new(ui.Layer, panel.parent, { _categoryPolicy = "auto" })
        chrome.clickthrough, chrome.enabled = true, false
        local state = {
            panel = panel,
            area = panel.parent,
            key = host.key,
            frame = host.spec.frame,
            interfaceID = panel.interfaceID,
            group = group,
            host = host,
            grouped = host.grouped,
            nativeIcon = host.nativeIcon,
            nativeSlides = {},
            count = members and #members or 1,
            chrome = chrome,
            tabs = {},
            insertion = {},
        }
        previewState = state -- cleanup also covers partially constructed previews
        state.previewHost = {
            chrome = chrome,
            frame = host.frame,
            owner = host.owner,
            grouped = host.grouped,
            content = host.content,
            tabs = host.tabs,
            tabControls = host.tabControls,
            manageNative = not group,
        }
        state.overflow = Overflow.new(state.previewHost, panel.parent, nil)
        state.buffer = ownSprite(state.overflow.viewport, art.tabBufferTile)
        state.buffer.isTiling = true
        state.divider = ownSprite(state.overflow.viewport, art.tabBarTile)
        state.divider.isTiling = true
        if synthetic then addSyntheticTab(state, host) end
        addMemberTabs(state, panel, members)
        if group then startSlides(group) end
        actions.startTick()
        return state
    end

    local function displaceNativeTabs(state, host, before)
        TabLayout.track(host.tabs, host.nativeLayout)
        for nativeIndex, bg in ipairs(host.backgrounds) do
            local target = before < nativeIndex and state.count * WIDTH or 0
            local offset = slide(state.nativeSlides[bg.key] or bg.layout.offset, target)
            state.nativeSlides[bg.key] = offset
            for _, saved in ipairs(host.nativeLayout) do
                local center = saved.x + saved.width / 2
                if
                    saved.width <= bg.component.width
                    and center >= bg.layout.x
                    and center < bg.layout.x + bg.component.width
                then
                    assert(TabLayout.move(saved, offset) ~= false, "native preview position overwritten")
                end
            end
        end
    end

    local function layoutPreviewTiles(state, host, group, before, index, band, occupied)
        local previewHost = state.previewHost
        previewHost.frame, previewHost.content, previewHost.tabs, previewHost.tabControls =
            host.frame, host.content, host.tabs, host.tabControls
        local scroll = state.overflow:Layout(
            occupied + state.count * WIDTH,
            group and group.tabScroll or tabScroll(host),
            true,
            false
        )
        local viewport = state.overflow.viewport
        local bufferX = state.overflow.x + ((host.grouped or group) and occupied + state.count * WIDTH or 0) - scroll
        local bufferWidth = math.max(0, state.overflow.x + state.overflow.width - bufferX)
        bufferX = bufferX - viewport.x
        local bandY = band.y - viewport.y
        if state.buffer.x ~= bufferX or state.buffer.y ~= bandY then state.buffer:SetPos(bufferX, bandY) end
        if state.buffer.width ~= bufferWidth then state.buffer:SetSize(bufferWidth, HEIGHT - SEAM) end
        if state.divider.x ~= bufferX or state.divider.y ~= bandY + HEIGHT - SEAM then
            state.divider:SetPos(bufferX, bandY + HEIGHT - SEAM)
        end
        if state.divider.width ~= bufferWidth then state.divider:SetSize(bufferWidth, SEAM) end
        if state.nativeTab then
            local target = state.overflow.x + (before == 0 and state.count * WIDTH or 0) - scroll - viewport.x
            state.nativeTab:SetPos(slide(state.nativeTab.x, target), bandY)
        end
        local base = 0
        if before > 0 then
            local bg = host.grouped and host.backgrounds[before]
            base = bg and bg.layout.x + bg.component.width or WIDTH
        elseif host.grouped then
            base = host.backgrounds[1].layout.x
        end
        for memberIndex, visual in ipairs(state.tabs) do
            local tx = state.overflow.x + base + (index + memberIndex - 2) * WIDTH - scroll - viewport.x
            local ty = bandY
            if visual.x ~= tx or visual.y ~= ty then visual:SetPos(tx, ty) end
        end
    end

    local function preview(panel, host, pointerX)
        local occupiedGroup = host and frameGroup(host)
        if not validCandidate(panel, host, occupiedGroup) then
            Preview.clear(panel)
            return nil
        end
        local members = panel._nisGroup and panel._nisGroup.members
        local state = previewState
        local synthetic = not host.grouped and not occupiedGroup
        if state and stalePreview(state, panel, host, occupiedGroup, members, synthetic) then
            Preview.clear()
            state = nil
        end
        if not state then state = createPreview(panel, host, occupiedGroup, members, synthetic) end
        local x, y, width, height = rectInParent(panel, host.frame)
        local chrome, band = state.chrome, tabBand(host)
        local occupied = host.used + (occupiedGroup and #occupiedGroup.members or 0) * WIDTH
        local before, index = insertionAt(
            occupiedGroup,
            host,
            (pointerX or x + band.x + occupied - tabScroll(host)) - x - band.x + tabScroll(host)
        )
        state.insertion.beforeNative, state.insertion.index = before, index
        state.host = host
        if occupiedGroup then
            occupiedGroup.dockPreview = state
            align(occupiedGroup)
            occupiedGroup.hosts[occupiedGroup.current].chrome:MoveToFront()
        elseif host.grouped then
            displaceNativeTabs(state, host, before)
        end
        if chrome.x ~= x or chrome.y ~= y then chrome:SetPos(x, y) end
        if chrome.width ~= width or chrome.height ~= height then chrome:SetSize(width, height) end
        layoutPreviewTiles(state, host, occupiedGroup, before, index, band, occupied)
        chrome:MoveToFront()
        return chrome, state.insertion
    end

    function Preview.show(panel, host, pointerX)
        if WorldMap.isSuspended() then return nil end
        local ok, chrome, insertion = pcall(preview, panel, host, pointerX)
        if not ok then
            Preview.clear(panel)
            error(chrome)
        end
        return chrome, insertion
    end

    function Preview.validate()
        if previewState then
            local state = previewState
            if
                state.panel._destroyed
                or not state.panel.root
                or not state.panel.dragState
                or not ui.Interfaces:GetInterface(state.panel.interfaceID)
                or not same(state.panel.parent, component(id.Component.TOPLEVEL_V2__GAME_AREA))
                or identity(component(state.frame)) ~= state.key
            then
                Preview.clear(state.panel)
            end
        end
    end

    function Preview.active()
        return previewState ~= nil
    end

    return Preview
end

return NativePreview
