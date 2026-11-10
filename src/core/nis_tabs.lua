local Components = require("src/core/components")
local Cursor = require("src/core/cursor")
local Sprites = require("src/core/sprites")
local Tooltip = require("src/tooltip")

local NisTabs = {}
NisTabs.__index = NisTabs

NisTabs.HEIGHT = 28
NisTabs.WIDTH = 40

local CORNER = 4
local ICON = 24
local NAV_WIDTH = 8

local function sprite(view, parent, spriteID, opaque)
    local part = Components.new(ui.Sprite, parent)
    part.spriteID = spriteID
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

local function clearTabs(view, preserveInputs)
    local isLoaded = loaded(view)
    if not preserveInputs then
        for _, tab in ipairs(view.tabs) do
            if tab.retained then
                if tab.tooltipAttachment then tab.tooltipAttachment:Hide() end
                Tooltip.unbind(tab, "tooltipAttachment")
            else
                tab:Release()
            end
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
    visual:SetPos(x, 0)
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
    tab.preview, tab.x = preview, x
    tab.background = sprite(view, visual,
        selected and Sprites.NIS_PANEL.tabSelected or Sprites.NIS_PANEL.tabUnselected)
    tab.background:SetSize(NisTabs.WIDTH, NisTabs.HEIGHT)
    tab.iconSprite = sprite(view, visual, panel.tabIcon, true)
    tab.iconSprite:SetPos((NisTabs.WIDTH - ICON) / 2, 2)
    tab.iconSprite:SetSize(ICON, ICON)
    if not preview and not tab.hit then
        tab.hit = Components.new(ui.Layer, view.panel.parent, {
            _categoryPolicy = Components.policyOf(view.panel.root),
        })
        tab.hit:SetSize(NisTabs.WIDTH, NisTabs.HEIGHT)
        tab.hit.clickthrough = false
        tab.hit.hidden = true
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
        tab.hit:Subscribe(ui.Hook.ONDRAGCOMPLETE, function(component, _, px, py)
            return release(component, px, py)
        end)
        Tooltip.bind(tab, tab.hit, view.panel.parent, {
            text = tabText(panel),
            placement = "above",
            placementFallback = false,
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
    hit.hidden = true
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
    self.root.hidden = true
    return self
end

function NisTabs:Sync(hidden)
    if not loaded(self) then return end
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
    if self.root.width ~= width then self.root:SetSize(width, NisTabs.HEIGHT) end
    local visible = self.visible == true and not hidden and root.hidden ~= true
    self.root.hidden = not visible
    if visible then self.root:MoveToFront() end
    for _, tab in ipairs(self.tabs) do
        local hit = tab.hit
        if hit and not tab.retained then
            if hit.x ~= x + tab.x or hit.y ~= y then hit:SetPos(x + tab.x, y) end
            hit.hidden = not visible
            hit.enabled = visible
            if visible then hit:MoveToFront() end
        end
    end
    for _, item in ipairs(self.navigationHits) do
        local hit = item.component
        if hit.x ~= x + item.x or hit.y ~= y then hit:SetPos(x + item.x, y) end
        hit.hidden = not visible
        hit.enabled = visible
        if visible then hit:MoveToFront() end
    end
end

-- Coordinates are in the panel's native parent's space. The invisible band is
-- intentionally hit-testable for a standalone panel during a docking preview.
function NisTabs:Contains(parentX, parentY)
    if not loaded(self) or self.panel.root.hidden == true then return false end
    local root = self.panel.root
    local left = root.x + CORNER
    local top = root.y + (self.panel.locked and 0 or 12) + CORNER
    return parentX >= left and parentX < left + root.width - CORNER * 2
        and parentY >= top and parentY < top + NisTabs.HEIGHT
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
    local priorActive, priorPreview, priorPage = self.active, self.previewPanel, self.pageIndex
    local root = self.panel.root
    local bandWidth = math.max(0, root.width - CORNER * 2)
    local bandY = (self.panel.locked and 0 or 12) + CORNER
    if visible and not self.pageDirty and self.parts
        and self.bandWidth == bandWidth and self.bandY == bandY
        and self.previewPanel == previewPanel
        and self.members and #self.members == #members then
        local unchanged = true
        for index, member in ipairs(members) do
            if self.members[index] ~= member then unchanged = false; break end
        end
        for _, tab in ipairs(self.tabs) do
            if not tab.preview and tab.hit == nil then unchanged = false; break end
        end
        if unchanged and self.active == active then
            self:Sync(root.hidden == true)
            return
        end
    end
    if not visible or bandWidth < NisTabs.WIDTH then
        clearTabs(self)
        self.visible = false
        self:Sync(root.hidden == true)
        return
    end

    local activeIndex = 1
    for index, member in ipairs(members) do
        if member == active then activeIndex = index; break end
    end
    local total = #members + (previewPanel and 1 or 0)
    local capacity = math.floor(bandWidth / NisTabs.WIDTH)
    local overflow = total > capacity
    local slots = capacity
    if overflow then slots = math.max(1, math.floor((bandWidth - NAV_WIDTH * 2) / NisTabs.WIDTH)) end
    local narrowPreview = previewPanel ~= nil and slots == 1
    local page
    if narrowPreview then
        if priorPreview ~= previewPanel then
            page = total
        elseif priorActive ~= active then
            page = activeIndex
        else
            page = math.max(1, math.min(total, priorPage or total))
        end
    end
    -- Rebuild artwork, not the native targets of an in-flight press or drag.
    local previousTabs = self.tabs
    clearTabs(self, true)
    self.visible = true
    self.parts = Components.new(ui.Layer, self.root)
    self.parts:SetSize(0, 0, 1.0, 1.0)
    self.parts.clickthrough = true

    local art = Sprites.NIS_PANEL
    local bar = sprite(self, self.parts, art.tabBarTile)
    bar:SetPos(0, NisTabs.HEIGHT - CORNER)
    bar:SetSize(bandWidth, CORNER)
    bar.isTiling = true

    if narrowPreview then
        if page <= #members then
            makeTab(self, members[page], 0, members[page] == active, false, previousTabs)
        else
            makeTab(self, previewPanel, 0, false, true, previousTabs)
        end
        local function showPage(nextPage)
            self.pageIndex = nextPage
            self.pageDirty = true
            self:Refresh(self.members, self.active, self.previewPanel)
        end
        navigation(self, NisTabs.WIDTH, "<",
            page > 1 and function() showPage(page - 1) end or nil)
        navigation(self, NisTabs.WIDTH + NAV_WIDTH, ">",
            page < total and function() showPage(page + 1) end or nil)
    else
        local previewVisible = previewPanel ~= nil
        local memberSlots = previewVisible and slots - 1 or slots
        local first = math.max(1, math.min(activeIndex - memberSlots + 1, #members - memberSlots + 1))
        for index = first, math.min(#members, first + memberSlots - 1) do
            makeTab(self, members[index], (index - first) * NisTabs.WIDTH,
                members[index] == active, false, previousTabs)
        end
        if previewVisible then
            makeTab(self, previewPanel, #self.tabs * NisTabs.WIDTH, false, true, previousTabs)
        end
        if overflow then
            local navX = slots * NisTabs.WIDTH
            if members[activeIndex - 1] then
                navigation(self, navX, "<", function()
                    self.panel:_SelectNisTab(members[activeIndex - 1])
                end)
            end
            if members[activeIndex + 1] then
                navigation(self, navX + NAV_WIDTH, ">", function()
                    self.panel:_SelectNisTab(members[activeIndex + 1])
                end)
            end
        end
    end
    -- Block unused strip space without laying an input mask over the tabs.
    local function blockGap(left, right)
        if right <= left then return end
        local gap = Components.new(ui.Layer, self.parts)
        gap:SetPos(left, 0)
        gap:SetSize(right - left, NisTabs.HEIGHT)
        gap.clickthrough = false
    end
    local used = #self.tabs * NisTabs.WIDTH
    for _, item in ipairs(self.navigationHits) do
        blockGap(used, item.x)
        used = item.x + NAV_WIDTH
    end
    blockGap(used, bandWidth)
    for _, tab in ipairs(previousTabs) do
        if not tab.reused and not tab.retained then tab:Release() end
        tab.reused = nil
    end
    self.members = {}
    for index, member in ipairs(members) do self.members[index] = member end
    self.active, self.previewPanel = active, previewPanel
    self.pageIndex, self.pageDirty = page, false
    self.bandWidth, self.bandY = bandWidth, bandY
    self:Sync(root.hidden == true)
end

function NisTabs:SetAlpha(alpha)
    self.alpha = math.max(0, math.min(1, alpha or 1))
    if not loaded(self) then return end
    for _, part in ipairs(self.visuals) do part.alpha = self.alpha end
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
