local Components = require("src/core/components")
local Cursor = require("src/core/cursor")
local Sprites = require("src/core/sprites")
local Tooltip = require("src/tooltip")
local Trace = require("src/nis/dock_trace")

local NisTabs = {}
NisTabs.__index = NisTabs

NisTabs.HEIGHT = 28
NisTabs.WIDTH = 40

local CORNER = 4
local ICON = 24
local NAV_WIDTH = 8

local function sprite(view, parent, spriteID, opaque, iconPanel)
    local part = Components.new(ui.Sprite, parent)
    if iconPanel and Trace.enabled(view.panel, iconPanel) then
        local ok, problem = pcall(function()
            part.sprite = spriteID
        end)
        if not ok then
            Trace.log(
                "tab-icon-assignment-failed",
                "owner",
                Trace.panel(view.panel),
                "member",
                Trace.panel(iconPanel),
                "icon",
                spriteID,
                "error",
                problem
            )
            error(problem, 0)
        end
    else
        part.sprite = spriteID
    end
    part.clickthrough = true
    part.alpha = opaque and 1 or view.alpha
    if not opaque then view.visuals[#view.visuals + 1] = part end
    return part
end

local function loaded(view)
    return view.root ~= nil and ui.Interfaces:GetInterface(view.interfaceID) ~= nil
end

local function tabText(panel)
    return panel.tabText or "Panel"
end

local Tab = {}
Tab.__index = Tab

function Tab:Release()
    if self.tooltipAttachment then self.tooltipAttachment:Hide() end
    Tooltip.unbind(self, "tooltipAttachment")
    if self.hit then
        if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.hit:Destroy() end
        self.hit = nil
    end
    self.retained, self.dragOwner = nil, nil
end

local function discardTab(tab)
    if not tab.retained then return tab:Release() end
    if tab.tooltipAttachment then tab.tooltipAttachment:Hide() end
    Tooltip.unbind(tab, "tooltipAttachment")
end

local function clearTabs(view, preserveInputs)
    local isLoaded = loaded(view)
    if not preserveInputs then
        for _, tab in ipairs(view.tabs) do
            discardTab(tab)
        end
    end
    view.tabs = {}
    if view.parts then
        if isLoaded then view.parts:Destroy() end
        view.parts = nil
    end
    for _, item in ipairs(view.navigationHits) do
        if isLoaded then item.component:Destroy() end
    end
    view.navigationHits = {}
    view.visuals = {}
    view.members = nil
end

local function makeTab(view, panel, x, selected, preview, previousTabs)
    local visual = Components.new(ui.Layer, view.parts)
    visual:SetSize(NisTabs.WIDTH, NisTabs.HEIGHT)
    visual.clickthrough = true

    local tab
    if not preview then
        for _, previous in ipairs(previousTabs) do
            if not previous.preview and previous.member == panel and previous.hit then
                tab = previous
                tab.reused = true
                break
            end
        end
    end
    tab = tab or setmetatable({ member = panel, interfaceID = view.interfaceID }, Tab)
    tab.preview, tab.targetX = preview, x
    tab.x = view.dragMember and tab.x or x
    tab.x = tab.x or x
    tab.visual = visual
    visual:SetPos(tab.x, 0)
    tab.background = sprite(view, visual, selected and Sprites.NIS_PANEL.tabSelected or Sprites.NIS_PANEL.tabUnselected)
    tab.background:SetSize(NisTabs.WIDTH, NisTabs.HEIGHT)
    -- Native getters expose the resolved sprite, not the plugin resource wrapper.
    tab.icon = panel.tabIcon
    tab.iconSprite = sprite(view, visual, panel.tabIcon, true, panel)
    tab.iconSprite:SetPos((NisTabs.WIDTH - ICON) / 2, 2)
    tab.iconSprite:SetSize(ICON, ICON)
    tab.seam = sprite(view, visual, Sprites.NIS_PANEL.tabBarTile)
    tab.seam:SetPos(0, NisTabs.HEIGHT - CORNER)
    tab.seam:SetSize(NisTabs.WIDTH, CORNER)
    tab.seam.isTiling = true
    Components.setHidden(tab.seam, selected)
    if not preview and not tab.hit then
        tab.hit = Components.new(ui.Layer, view.panel.parent, {
            _categoryPolicy = Components.policyOf(view.panel.root),
        })
        tab.hit:SetSize(NisTabs.WIDTH, NisTabs.HEIGHT)
        tab.hit.clickthrough = false
        Components.setHidden(tab.hit, true)
        tab.hit.enabled = false
        -- Lua owns the gesture, as for header dragging and resize handles.
        -- Native self-dragging would also move/hide this capture component.
        Cursor.apply(tab.hit, nil, false)
        tab.hit:Subscribe(ui.Hook.ONCLICK, function(component, px, py)
            local actor = tab.dragOwner or view.panel
            if not actor.locked then
                actor:_BeginNisTabDrag(panel, component, px, py, tab)
            end
            actor:_SelectNisTab(panel)
            return false
        end)
        local function move(component, px, py)
            local actor = tab.dragOwner or view.panel
            if actor then actor:_MoveNisTabDrag(component, px, py) end
            return false
        end
        tab.hit:Subscribe(ui.Hook.ONHOLD, move)
        tab.hit:Subscribe(ui.Hook.ONDRAG, move)
        local function release(component, px, py)
            local actor = tab.dragOwner or view.panel
            if actor then actor:_StopNisTabDrag(component, px, py) end
            return false
        end
        tab.hit:Subscribe(ui.Hook.ONRELEASE, release)
        tab.hit:Subscribe(
            ui.Hook.ONDRAGCOMPLETE,
            function(component, _, px, py)
                return release(component, px, py)
            end
        )
        Tooltip.bind(tab, tab.hit, view.panel.parent, {
            text = tabText(panel),
            _nisTab = true,
        }, "tooltipAttachment")
    end
    view.tabs[#view.tabs + 1] = tab
end

local function navigation(view, x, text, action)
    if action == nil then return end
    local arrow = sprite(view, view.parts, Sprites.SCROLL_ARROW_UP, true)
    arrow:SetPos(x, 6)
    arrow:SetSize(NAV_WIDTH, 16)
    arrow.rotationDegrees = text == "<" and -90 or 90
    local hit = Components.new(ui.Layer, view.panel.parent, {
        _categoryPolicy = Components.policyOf(view.panel.root),
    })
    hit:SetSize(NAV_WIDTH, NisTabs.HEIGHT)
    hit.clickthrough = false
    Components.setHidden(hit, true)
    hit.enabled = false
    Cursor.apply(hit, nil, false)
    hit:Subscribe(ui.Hook.ONCLICK, function()
        action()
        return false
    end)
    view.navigationHits[#view.navigationHits + 1] = { component = hit, x = x }
end

function NisTabs.new(panel)
    local self = setmetatable({
        panel = panel,
        interfaceID = panel.interfaceID,
        alpha = panel.transparencyScale or 1,
        visuals = {},
        tabs = {},
        navigationHits = {},
        single = { panel },
    }, NisTabs)
    self.root = Components.new(ui.Layer, panel.parent, {
        _categoryPolicy = Components.policyOf(panel.root),
    })
    self.root:SetPos(panel.root.x + CORNER, panel.root.y + (panel.locked and 0 or 12) + CORNER)
    self.root:SetSize(math.max(0, panel.root.width - CORNER * 2), NisTabs.HEIGHT)
    self.root.clickthrough = true
    self.root.alpha = 1
    Components.setHidden(self.root, true)
    return self
end

local function syncTooltips(tabs, visible)
    for _, tab in ipairs(tabs) do
        local tooltip = tab.tooltipAttachment
        if tooltip then
            if visible and not tab.retained then
                tooltip:_RefreshIfVisible()
            else
                tooltip:Hide()
            end
        end
    end
end

local function syncHit(hit, x, y, height, visible)
    if hit.x ~= x or hit.y ~= y then hit:SetPos(x, y) end
    if hit.height ~= height then hit:SetHeight(height) end
    Components.setHidden(hit, not visible)
    hit.enabled = visible
    if visible then hit:MoveToFront() end
end

function NisTabs:Sync(hidden)
    if not loaded(self) then
        syncTooltips(self.tabs, false)
        return
    end
    local root = self.panel.root
    local x = root.x + CORNER
    local y = root.y + (self.panel.locked and 0 or 12) + CORNER
    if self.root.x ~= x or self.root.y ~= y then self.root:SetPos(x, y) end
    local width = math.max(0, root.width - CORNER * 2)
    if not hidden and self.parts and self.bandWidth ~= width then
        -- Divider, gap blockers and overflow controls share the strip's width.
        self:Refresh(self.members, self.active, self.previewPanel)
        return
    end
    local height = math.max(0, math.min(NisTabs.HEIGHT, root.y + root.height - y))
    if self.root.width ~= width or self.root.height ~= height then self.root:SetSize(width, height) end
    local visible = self.visible == true
        and not hidden
        and root.hidden ~= true
        and root.enabled ~= false
        and root.visibleGlobal ~= false
    Components.setHidden(self.root, not visible)
    if visible then self.root:MoveToFront() end
    for _, tab in ipairs(self.tabs) do
        local hit = tab.hit
        if hit and not tab.retained then
            syncHit(hit, x + tab.x, y, height, visible)
        end
    end
    for _, item in ipairs(self.navigationHits) do
        syncHit(item.component, x + item.x, y, height, visible)
    end
    syncTooltips(self.tabs, visible)
end

-- Coordinates are in the panel's native parent's space. The invisible band is
-- intentionally hit-testable for a standalone panel during a docking preview.
function NisTabs:Contains(parentX, parentY)
    if not loaded(self) or self.panel.root.hidden == true then return false end
    local root = self.panel.root
    local left = root.x + CORNER
    local top = root.y + (self.panel.locked and 0 or 12) + CORNER
    return parentX >= left
        and parentX < left + root.width - CORNER * 2
        and parentY >= top
        and parentY < math.min(top + NisTabs.HEIGHT, root.y + root.height)
end

-- Drag retention ends at the last tab or navigation control; docking uses the full strip.
function NisTabs:ContainsDrag(parentX, parentY)
    if not self:Contains(parentX, parentY) then return false end
    local right = 0
    for _, tab in ipairs(self.tabs) do
        right = math.max(right, tab.targetX + NisTabs.WIDTH)
    end
    for _, item in ipairs(self.navigationHits) do
        right = math.max(right, item.x + NAV_WIDTH)
    end
    return parentX < self.panel.root.x + CORNER + right
end

function NisTabs:SetDrag(member, parentX, gripX)
    self.dragMember = member
    for _, tab in ipairs(self.tabs) do
        if tab.member == member then
            tab.x = math.floor(parentX - self.root.x - gripX + 0.5)
            tab.visual:SetPos(tab.x, 0)
            tab.visual:MoveToFront()
            break
        end
    end
end

-- Logic runs at 50 Hz: ease displaced peers into their new slots, preserving
-- their current positions if the pointer reverses before the slide completes.
function NisTabs:StepDrag()
    if not self.dragMember or not loaded(self) then return end
    for _, tab in ipairs(self.tabs) do
        if tab.member ~= self.dragMember and tab.x ~= tab.targetX then
            local delta = tab.targetX - tab.x
            tab.x = tab.x + (delta > 0 and 1 or -1) * math.ceil(math.abs(delta) * 0.4)
            tab.visual:SetPos(tab.x, 0)
        end
    end
    self:Sync(self.panel.root.hidden == true)
end

function NisTabs:FinishDrag()
    self.dragMember = nil
    if not loaded(self) then return end
    for _, tab in ipairs(self.tabs) do
        tab.x = tab.targetX
        tab.visual:SetPos(tab.x, 0)
    end
    self:Sync(self.panel.root.hidden == true)
end

local function sameStrip(view, members, active, previewPanel, bandWidth, bandY)
    if
        view.pageDirty
        or not view.parts
        or view.bandWidth ~= bandWidth
        or view.bandY ~= bandY
        or view.previewPanel ~= previewPanel
        or not view.members
        or #view.members ~= #members
    then
        return false
    end
    for index, member in ipairs(members) do
        if view.members[index] ~= member then return false end
    end
    for _, tab in ipairs(view.tabs) do
        if not tab.preview and (tab.hit == nil or tab.icon ~= tab.member.tabIcon) then
            return false
        end
    end
    return view.active == active
end

-- Selection artwork can change without rebuilding native press targets.
local function updateSelectionArtwork(view, members, active, previewPanel, bandWidth, bandY)
    if
        previewPanel ~= nil
        or not view.parts
        or view.pageDirty
        or view.bandWidth ~= bandWidth
        or view.bandY ~= bandY
        or view.previewPanel ~= nil
        or not view.members
        or #view.members ~= #members
        or #members > math.floor(bandWidth / NisTabs.WIDTH)
        or #view.tabs ~= #members
    then
        return false
    end
    for index, member in ipairs(members) do
        local tab = view.tabs[index]
        if view.members[index] ~= member or tab.member ~= member or tab.hit == nil or tab.icon ~= member.tabIcon then
            return false
        end
    end
    for _, tab in ipairs(view.tabs) do
        local selected = tab.member == active
        local spriteID = selected and Sprites.NIS_PANEL.tabSelected or Sprites.NIS_PANEL.tabUnselected
        if tab.background.spriteID ~= spriteID then tab.background.spriteID = spriteID end
        Components.setHidden(tab.seam, selected)
    end
    view.active = active
    return true
end

local function narrowPage(view, previewPanel, active, activeIndex, total)
    if view.previewPanel ~= previewPanel then return total end
    if view.active ~= active then return activeIndex end
    return math.max(1, math.min(total, view.pageIndex or total))
end

local function drawStrip(view, bandWidth)
    view.parts = Components.new(ui.Layer, view.root)
    view.parts:SetSize(0, 0, 1.0, 1.0)
    view.parts.clickthrough = true
    local art = Sprites.NIS_PANEL
    local buffer = sprite(view, view.parts, art.tabBufferTile)
    buffer:SetSize(bandWidth, NisTabs.HEIGHT - CORNER)
    buffer.isTiling = true
    local bar = sprite(view, view.parts, art.tabBarTile)
    bar:SetPos(0, NisTabs.HEIGHT - CORNER)
    bar:SetSize(bandWidth, CORNER)
    bar.isTiling = true
end

local function narrowTabs(view, members, active, previewPanel, previousTabs, page, total)
    if page <= #members then
        makeTab(view, members[page], 0, members[page] == active, false, previousTabs)
    else
        makeTab(view, previewPanel, 0, false, true, previousTabs)
    end
    local function showPage(nextPage)
        view.pageIndex = nextPage
        view.pageDirty = true
        view:Refresh(view.members, view.active, view.previewPanel)
    end
    navigation(view, NisTabs.WIDTH, "<", page > 1 and function() showPage(page - 1) end or nil)
    navigation(view, NisTabs.WIDTH + NAV_WIDTH, ">", page < total and function() showPage(page + 1) end or nil)
end

local function wideTabs(view, members, active, previewPanel, previousTabs, slots, activeIndex, overflow)
    local memberSlots = previewPanel ~= nil and slots - 1 or slots
    local first = math.max(1, math.min(activeIndex - memberSlots + 1, #members - memberSlots + 1))
    for index = first, math.min(#members, first + memberSlots - 1) do
        makeTab(view, members[index], (index - first) * NisTabs.WIDTH, members[index] == active, false, previousTabs)
    end
    if previewPanel ~= nil then
        makeTab(view, previewPanel, #view.tabs * NisTabs.WIDTH, false, true, previousTabs)
    end
    if not overflow then return end
    local navX = slots * NisTabs.WIDTH
    if members[activeIndex - 1] then
        navigation(
            view,
            navX,
            "<",
            function()
                view.panel:_SelectNisTab(members[activeIndex - 1])
            end
        )
    end
    if members[activeIndex + 1] then
        navigation(
            view,
            navX + NAV_WIDTH,
            ">",
            function()
                view.panel:_SelectNisTab(members[activeIndex + 1])
            end
        )
    end
end

-- Block unused strip space without laying an input mask over the tabs.
local function blockGap(view, left, right)
    if right <= left then return end
    local gap = Components.new(ui.Layer, view.parts)
    gap:SetPos(left, 0)
    gap:SetSize(right - left, NisTabs.HEIGHT)
    gap.clickthrough = false
end

local function blockUnusedStrip(view, bandWidth)
    local used = #view.tabs * NisTabs.WIDTH
    for _, item in ipairs(view.navigationHits) do
        blockGap(view, used, item.x)
        used = item.x + NAV_WIDTH
    end
    blockGap(view, used, bandWidth)
end

local function releasePreviousTabs(previousTabs)
    for _, tab in ipairs(previousTabs) do
        if not tab.reused then
            if tab.retained and tab.tooltipAttachment then tab.tooltipAttachment:Hide() end
            if not tab.retained then tab:Release() end
        end
        tab.reused = nil
    end
end

local function raiseDraggedTab(view)
    if not view.dragMember then return end
    for _, tab in ipairs(view.tabs) do
        if tab.member == view.dragMember then
            tab.visual:MoveToFront()
            break
        end
    end
end

function NisTabs:Refresh(members, active, previewPanel)
    if not loaded(self) then
        clearTabs(self)
        return
    end
    self.single[1] = self.panel
    local visible = previewPanel ~= nil or members ~= nil and #members >= 2
    members = members or self.single
    if #members == 0 then members = self.single end
    active = active or members[1]
    local root = self.panel.root
    local bandWidth = math.max(0, root.width - CORNER * 2)
    local bandY = (self.panel.locked and 0 or 12) + CORNER
    if visible and sameStrip(self, members, active, previewPanel, bandWidth, bandY) then
        self:Sync(root.hidden == true)
        return
    end
    if visible and updateSelectionArtwork(self, members, active, previewPanel, bandWidth, bandY) then
        self:Sync(root.hidden == true)
        return
    end
    if not visible or bandWidth < NisTabs.WIDTH then
        clearTabs(self)
        self.visible = false
        self:Sync(root.hidden == true)
        return
    end

    local activeIndex = 1
    for index, member in ipairs(members) do
        if member == active then
            activeIndex = index
            break
        end
    end
    local total = #members + (previewPanel and 1 or 0)
    local capacity = math.floor(bandWidth / NisTabs.WIDTH)
    local overflow = total > capacity
    local slots = capacity
    if overflow then slots = math.max(1, math.floor((bandWidth - NAV_WIDTH * 2) / NisTabs.WIDTH)) end
    local narrowPreview = previewPanel ~= nil and slots == 1
    local page = narrowPreview and narrowPage(self, previewPanel, active, activeIndex, total) or nil
    -- Rebuild artwork, not the native targets of an in-flight press or drag.
    local previousTabs = self.tabs
    clearTabs(self, true)
    self.visible = true
    drawStrip(self, bandWidth)

    if narrowPreview then
        narrowTabs(self, members, active, previewPanel, previousTabs, page, total)
    else
        wideTabs(self, members, active, previewPanel, previousTabs, slots, activeIndex, overflow)
    end
    blockUnusedStrip(self, bandWidth)
    releasePreviousTabs(previousTabs)
    self.members = {}
    for index, member in ipairs(members) do
        self.members[index] = member
    end
    self.active, self.previewPanel = active, previewPanel
    self.pageIndex, self.pageDirty = page, false
    self.bandWidth, self.bandY = bandWidth, bandY
    raiseDraggedTab(self)
    self:Sync(root.hidden == true)
end

function NisTabs:SetAlpha(alpha)
    self.alpha = math.max(0, math.min(1, alpha or 1))
    if not loaded(self) then return end
    for _, part in ipairs(self.visuals) do
        part.alpha = self.alpha
    end
end

function NisTabs:Destroy()
    clearTabs(self)
    if self.root then
        if loaded(self) then self.root:Destroy() end
        self.root = nil
    end
    self.panel = nil
end

return NisTabs
