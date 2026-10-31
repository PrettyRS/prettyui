local Components = require("src/core/components")
local ContentMethods = require("src/core/content_methods")
local Cursor = require("src/core/cursor")
local Layout = require("src/core/layout")
local RowBackgrounds = require("src/core/row_backgrounds")
local Scroll = require("src/core/scroll")
local Sprites = require("src/core/sprites")
local Tooltip = require("src/tooltip")
local Wheel = require("src/core/wheel")

local Tabs = {}
Tabs.__index = Tabs

local TabPage = {}
TabPage.__index = TabPage

local DIVIDER_HEIGHT = 60
local TAB_BASELINE = 42
local ICON_WIDTH = 48
local ICON_HEIGHT = 38
local ICON_Y = TAB_BASELINE - ICON_HEIGHT - 1
local ICON_SIZE = 22
local TEXT_HEIGHT = 60
local TEXT_LEFT_WIDTH = 60
local TEXT_RIGHT_WIDTH = 30
local TEXT_MIDDLE_X = 30
local TEXT_MIN_WIDTH = TEXT_LEFT_WIDTH + TEXT_RIGHT_WIDTH
local TEXT_PADDING = 24
local TEXT_LABEL_BREATHING_ROOM = 8
local TEXT_LABEL_X = 8
local DISABLED_TEXT_LABEL_X = 30
local TEXT_LABEL_RIGHT = 8
local TEXT_LABEL_Y = 7
local TEXT_LABEL_HEIGHT = 32
local DEFAULT_WIDTH = 300
local DEFAULT_HEIGHT = 180
local DEFAULT_TAB_GAP = 2
local INACTIVE_TEXT_ALPHA = 0.65
local DISABLED_ALPHA = 0.4
local TEXT_COLOUR = 0xF2E2BCFF

local function copyOptions(options)
    local copy = {}
    if type(options) == "table" then
        for key, value in pairs(options) do copy[key] = value end
    end
    return copy
end

local function normalizeTab(value, index)
    local tab
    if type(value) == "string" then
        tab = { kind = "text", text = value, value = value }
    elseif type(value) == "number" then
        tab = { kind = "icon", icon = value, value = index }
    elseif type(value) == "table" then
        tab = copyOptions(value)
        tab.icon = tab.icon or tab.spriteID
        tab.kind = tab.kind or tab.type or tab.flavour or tab.flavor
        if tab.kind == nil then tab.kind = tab.icon ~= nil and "icon" or "text" end
        tab.text = tostring(tab.text or tab.label or "")
        if tab.value == nil then tab.value = tab.text ~= "" and tab.text or index end
    else
        error("Tabs entries must be text, sprite IDs, or option tables")
    end
    if tab.kind ~= "text" and tab.kind ~= "icon" then
        error("Tabs entry kind must be 'text' or 'icon'")
    end
    if tab.kind == "icon" and type(tab.icon) ~= "number" then
        error("Icon tabs require an icon or spriteID")
    end
    tab.disabled = tab.disabled == true
    tab.hovered = false
    tab.explicitWidth = tab.width
    return tab
end

local function normalizeTabs(values)
    if type(values) ~= "table" or #values == 0 then
        error("Tabs requires a non-empty array")
    end
    local tabs = {}
    for index, value in ipairs(values) do tabs[index] = normalizeTab(value, index) end
    return tabs
end

local function measureTextWidth(tab)
    local succeeded, width = pcall(function()
        return config.Font.MUSEO_SANS_15PT_REGULAR:GetStringWidth(tab.text, false)
    end)
    local labelWidth = succeeded and width or #tab.text * 7
    local padding = TEXT_PADDING
    if tab.disabled then
        padding = DISABLED_TEXT_LABEL_X + TEXT_LABEL_RIGHT + TEXT_LABEL_BREATHING_ROOM
    end
    local required = math.floor(labelWidth + padding)
    return math.max(TEXT_MIN_WIDTH, math.floor(tab.explicitWidth or 0), required)
end

local function tabWidth(tab)
    if tab.kind == "icon" then return ICON_WIDTH end
    return measureTextWidth(tab)
end

local function sprite(parent, spriteID)
    local component = Components.new(ui.Sprite, parent)
    component.spriteID = spriteID
    component.clickthrough = true
    return component
end

local function setTextSprites(tab, sprites)
    tab.left.spriteID = sprites.left
    tab.middle.spriteID = sprites.middle
    tab.right.spriteID = sprites.right
end

function Tabs.getSize(_, options)
    options = options or {}
    return options.width or DEFAULT_WIDTH, options.height or DEFAULT_HEIGHT
end

function Tabs.flowOptions(options)
    local copied = copyOptions(options)
    if copied.x == nil and copied.width == nil and copied.widthAnchor == nil then
        copied.x = 0
        copied.width = 0
        copied.widthAnchor = 1.0
    end
    return copied
end

function Tabs:_UpdateTab(tab)
    local active = self.activeIndex == tab.index
    if tab.kind == "icon" then
        if tab.disabled then
            tab.background.spriteID = Sprites.ICON_TAB.disabled
        elseif active then
            tab.background.spriteID = Sprites.ICON_TAB.active
        elseif tab.hovered then
            tab.background.spriteID = Sprites.ICON_TAB.hovered
        else
            tab.background.spriteID = Sprites.ICON_TAB.inactive
        end
        tab.visual.alpha = 1
        tab.iconSprite.alpha = tab.disabled and DISABLED_ALPHA or 1
    else
        local sprites = tab.disabled and Sprites.TEXT_TAB.disabled or
            (active and Sprites.TEXT_TAB.active or Sprites.TEXT_TAB.inactive)
        setTextSprites(tab, sprites)
        if tab.disabled then
            tab.label.alpha = DISABLED_ALPHA
            tab.label:SetPos(DISABLED_TEXT_LABEL_X, TEXT_LABEL_Y)
            tab.label:SetSize(
                -(DISABLED_TEXT_LABEL_X + TEXT_LABEL_RIGHT),
                TEXT_LABEL_HEIGHT,
                1.0
            )
        elseif active or tab.hovered then
            tab.label.alpha = 1
            tab.label:SetPos(TEXT_LABEL_X, TEXT_LABEL_Y)
            tab.label:SetSize(-(TEXT_LABEL_X + TEXT_LABEL_RIGHT), TEXT_LABEL_HEIGHT, 1.0)
        else
            tab.label.alpha = INACTIVE_TEXT_ALPHA
            tab.label:SetPos(TEXT_LABEL_X, TEXT_LABEL_Y)
            tab.label:SetSize(-(TEXT_LABEL_X + TEXT_LABEL_RIGHT), TEXT_LABEL_HEIGHT, 1.0)
        end
    end
    Cursor.apply(tab.hit, tab.hoverCursor or config.Cursor.CURSOR_GOTO, not tab.disabled)
end

function Tabs:_RefreshZOrder()
    self.divider:MoveToFront()
    local active = self.tabs[self.activeIndex]
    if active then
        active.visual:MoveToFront()
        active.hit:MoveToFront()
    end
end

function Tabs:_LayoutTabs()
    local x = self.tabInset
    for _, tab in ipairs(self.tabs) do
        local width = tabWidth(tab)
        tab.width = width
        tab.visual:SetPos(x, tab.kind == "icon" and ICON_Y or 0)
        tab.visual:SetSize(width, tab.kind == "icon" and ICON_HEIGHT or TEXT_HEIGHT)
        tab.hit:SetPos(x, 0)
        tab.hit:SetSize(width, TAB_BASELINE)
        x = x + width + self.tabGap
    end
end

function Tabs:_CreateIconTab(tab, x, options)
    tab.visual = Components.new(ui.Layer, self.root)
    tab.visual:SetPos(x, ICON_Y)
    tab.visual:SetSize(ICON_WIDTH, ICON_HEIGHT)
    tab.visual.clickthrough = true

    tab.background = sprite(tab.visual, Sprites.ICON_TAB.inactive)
    tab.background:SetSize(ICON_WIDTH, ICON_HEIGHT)

    tab.iconSprite = sprite(tab.visual, tab.icon)
    local iconSize = math.max(1, math.floor(tab.iconSize or options.iconSize or ICON_SIZE))
    tab.iconSprite:SetPos(
        math.floor((ICON_WIDTH - iconSize) / 2),
        math.floor((ICON_HEIGHT - iconSize) / 2)
    )
    tab.iconSprite:SetSize(iconSize, iconSize)
end

function Tabs:_CreateTextTab(tab, x, width)
    tab.visual = Components.new(ui.Layer, self.root)
    tab.visual:SetPos(x, 0)
    tab.visual:SetSize(width, TEXT_HEIGHT)
    tab.visual.clickthrough = true

    tab.left = sprite(tab.visual, Sprites.TEXT_TAB.inactive.left)
    tab.left:SetSize(TEXT_LEFT_WIDTH, TEXT_HEIGHT)

    tab.middle = sprite(tab.visual, Sprites.TEXT_TAB.inactive.middle)
    tab.middle:SetPos(TEXT_MIDDLE_X, 0)
    tab.middle:SetSize(-(TEXT_MIDDLE_X + TEXT_RIGHT_WIDTH), TEXT_HEIGHT, 1.0)
    tab.middle.isTiling = true

    tab.right = sprite(tab.visual, Sprites.TEXT_TAB.inactive.right)
    tab.right:SetPos(-TEXT_RIGHT_WIDTH, 0, 1.0)
    tab.right:SetSize(TEXT_RIGHT_WIDTH, TEXT_HEIGHT)

    tab.label = Components.new(ui.Text, tab.visual)
    tab.label:SetPos(TEXT_LABEL_X, TEXT_LABEL_Y)
    tab.label:SetSize(-(TEXT_LABEL_X + TEXT_LABEL_RIGHT), TEXT_LABEL_HEIGHT, 1.0)
    tab.label.content = tab.text
    tab.label.font = id.Font.MUSEO_SANS_15PT_REGULAR
    tab.label.rgba = tab.colour or TEXT_COLOUR
    tab.label.isShadowed = tab.shadowed ~= false
    tab.label.alignHorizontal = ui.AlignMode.CENTRE
    tab.label.alignVertical = ui.AlignMode.CENTRE
    tab.label.maxLines = 1
    tab.label.clickthrough = true
end

function Tabs:_CreateTab(tab, x, options)
    local width = tabWidth(tab)
    tab.index = #self.tabs + 1
    tab.width = width
    if tab.kind == "icon" then
        self:_CreateIconTab(tab, x, options)
    else
        self:_CreateTextTab(tab, x, width)
    end

    tab.hit = Components.new(ui.Layer, self.root)
    tab.hit:SetPos(x, 0)
    tab.hit:SetSize(width, TAB_BASELINE)
    tab.hit.clickthrough = false
    Wheel.bind(tab.hit, options)

    tab.hit:Subscribe(ui.Hook.ONMOUSEOVER, function()
        if tab.disabled then return false end
        tab.hovered = true
        self:_UpdateTab(tab)
        return true
    end)
    tab.hit:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        tab.hovered = false
        self:_UpdateTab(tab)
        return true
    end)
    tab.hit:Subscribe(ui.Hook.ONCLICK, function()
        if tab.disabled then return false end
        self:SetActive(tab.index)
        return false
    end)

    Tooltip.bind(tab, tab.hit, self.root, tab.tooltip, "tooltipAttachment")
    table.insert(self.tabs, tab)
    return width
end

local function configurePage(tabs, index, options)
    local page = setmetatable({}, TabPage)
    page.tabs = tabs
    page.index = index
    page.root = Components.new(ui.Layer, tabs.content)
    page.root:SetSize(0, 0, 1.0, 1.0)
    page.root.clickthrough = true
    page.root.hidden = true

    local parentContext = tabs.tooltipContext
    local tooltipParent = parentContext and parentContext.parent or tabs.parent
    local tab = tabs.tabs[index]
    local scrollable = tab.scrollable
    if scrollable == nil then scrollable = options.scrollable end
    local contentHeight = tab.contentHeight
    if contentHeight == nil then contentHeight = options.contentHeight end
    Scroll.attach(page, page.root, {
        width = 0,
        height = 0,
        widthAnchor = 1.0,
        heightAnchor = 1.0,
        contentHeight = contentHeight,
        scrollable = scrollable,
        scrollStep = options.scrollStep,
        _onScrollWheel = options._onScrollWheel,
        parentContext = parentContext,
        overlayParent = tooltipParent,
        isVisible = function() return page.root.hidden ~= true end,
        position = function(scrollRoot)
            local rootX = tabs.root.x or 0
            local rootY = tabs.root.y or 0
            if parentContext and parentContext.parentContext then
                rootX, rootY = parentContext.parentContext.position(tabs.root)
            end
            return rootX + (tabs.content.x or 0) + (page.root.x or 0) +
                    (scrollRoot.x or 0),
                rootY + (tabs.content.y or 0) + (page.root.y or 0) +
                    (scrollRoot.y or 0)
        end,
    })
    Layout.configure(page, options.contentLayout)
    page.rowBackgroundColours = tab.rowBackgroundColours
        or tab.rowBackgroundColors
        or options.rowBackgroundColours
        or options.rowBackgroundColors
        or {}
    page.rowBackgroundEdgeToEdge = tab.rowBackgroundEdgeToEdge
    if page.rowBackgroundEdgeToEdge == nil then
        page.rowBackgroundEdgeToEdge = options.rowBackgroundEdgeToEdge == true
    end
    page.rowBackgrounds = {}

    page.tooltipContext = Tooltip.registerContext(page.content, tooltipParent, function(target)
        local rootX, rootY = page._scroll:_AbsolutePosition()
        return rootX + (target.x or 0),
            rootY + (target.y or 0) - page._scroll.scrollY
    end, parentContext)
    return page
end

function Tabs.new(parent, values, options)
    options = options or {}
    local normalized = normalizeTabs(values)
    local width, height = Tabs.getSize(normalized, options)
    local heightAnchor = options.heightAnchor or 0
    local rootHeight = height
    if heightAnchor == 0 then
        rootHeight = math.max(TAB_BASELINE + 1, height)
    end

    local self = setmetatable({}, Tabs)
    self.parent = parent
    self.tabs = {}
    self.pages = {}
    self.activeIndex = nil
    self.onChange = options.onChange
    self.scrollable = options.scrollable ~= false
    self.tabGap = math.max(0, math.floor(options.tabGap or DEFAULT_TAB_GAP))
    self.tabInset = math.max(0, math.floor(options.tabInset or 0))

    self.root = Components.new(ui.Layer, parent)
    self.interfaceID = self.root.interfaceID
    self.root:SetPos(options.x or 0, options.y or 0, options.xAnchor or 0, options.yAnchor or 0)
    self.root:SetSize(width, rootHeight, options.widthAnchor or 0, heightAnchor)
    self.root.clickthrough = true
    Wheel.bind(self.root, options)

    local parentContext = Tooltip.getContext(parent)
    local tooltipParent = parentContext and parentContext.parent or parent
    self.tooltipContext = Tooltip.registerContext(self.root, tooltipParent, function(target)
        local rootX = self.root.x or 0
        local rootY = self.root.y or 0
        if parentContext then rootX, rootY = parentContext.position(self.root) end
        return rootX + (target.x or 0), rootY + (target.y or 0)
    end, parentContext)

    local x = self.tabInset
    for _, tab in ipairs(normalized) do
        x = x + self:_CreateTab(tab, x, options) + self.tabGap
    end

    self.divider = sprite(self.root, Sprites.DIVIDER)
    self.divider:SetPos(0, 0)
    self.divider:SetSize(0, DIVIDER_HEIGHT, 1.0)
    self.divider.isTiling = true
    Wheel.bind(self.divider, options)

    self.content = Components.new(ui.Layer, self.root)
    self.content:SetPos(0, TAB_BASELINE)
    self.content:SetSize(0, -TAB_BASELINE, 1.0, 1.0)
    self.content.clickthrough = true
    Wheel.bind(self.content, options)

    for index = 1, #self.tabs do
        self.pages[index] = configurePage(self, index, options)
    end

    local initial = math.floor(options.activeIndex or 1)
    if self.tabs[initial] == nil or self.tabs[initial].disabled then
        for index, tab in ipairs(self.tabs) do
            if not tab.disabled then initial = index break end
        end
    end
    self:SetActive(initial, false)
    Tooltip.bind(self, self.root, parent, options.tooltip)
    return self
end

function Tabs:BindFlow(owner)
    self.flowOwner = owner
    return self
end

function TabPage:_FitContent()
    local tabs = self.tabs
    local height = math.max(TAB_BASELINE + 1, self.contentHeight + TAB_BASELINE)
    if tabs.flowOwner then
        Layout.resize(tabs.flowOwner, tabs, height)
    else
        tabs.root:SetHeight(height)
    end
    for _, page in ipairs(tabs.pages) do
        page._scroll:Refresh()
        page:RefreshRowBackgrounds()
    end
end

function Tabs:SetActive(index, notify)
    index = math.tointeger(index)
    local tab = index and self.tabs[index] or nil
    if tab == nil or tab.disabled then return false end
    local previous = self.activeIndex
    self.activeIndex = index
    for pageIndex, page in ipairs(self.pages) do
        page.root.hidden = pageIndex ~= index
        page._scroll:Refresh()
    end
    for _, entry in ipairs(self.tabs) do self:_UpdateTab(entry) end
    self:_RefreshZOrder()
    if notify ~= false and previous ~= index and self.onChange then
        self.onChange(self, index, tab.value, self.pages[index])
    end
    return true
end

function Tabs:GetActiveIndex()
    return self.activeIndex
end

function Tabs:GetTab(index)
    return self.tabs[index]
end

function Tabs:GetPage(index)
    return self.pages[index]
end

function Tabs:SetTooltip(value)
    return Tooltip.set(self, value)
end

function Tabs:SetTabTooltip(index, value)
    local tab = self.tabs[index]
    if tab == nil then return false end
    tab.tooltip = value
    return Tooltip.set(tab, value, "tooltipAttachment")
end

function Tabs:SetDisabled(index, disabled)
    local tab = self.tabs[index]
    if tab == nil then return false end
    tab.disabled = disabled == true
    tab.hovered = false
    if tab.disabled and self.activeIndex == index then
        for nextIndex, candidate in ipairs(self.tabs) do
            if not candidate.disabled then
                self:SetActive(nextIndex)
                break
            end
        end
    end
    self:_LayoutTabs()
    self:_UpdateTab(tab)
    self:_RefreshZOrder()
    return true
end

function Tabs:SetScrollable(scrollable)
    self.scrollable = scrollable ~= false
    for _, page in ipairs(self.pages) do page:SetScrollable(self.scrollable) end
end

function TabPage:RefreshRowBackgrounds()
    RowBackgrounds.clear(self.rowBackgrounds, self.interfaceID)
    self.rowBackgrounds = RowBackgrounds.apply(
        self.content,
        self._scroll.height,
        self,
        self.rowBackgroundColours,
        self.rowBackgroundEdgeToEdge)
end

function Tabs:Destroy()
    if self.root then Tooltip.unregisterContext(self.root) end
    for _, tab in ipairs(self.tabs) do Tooltip.unbind(tab, "tooltipAttachment") end
    for _, page in ipairs(self.pages) do
        RowBackgrounds.clear(page.rowBackgrounds, page.interfaceID)
        page.rowBackgrounds = {}
        if page.content then Tooltip.unregisterContext(page.content) end
        Layout.destroyManaged(page)
        if page._scroll then page._scroll:Destroy() page._scroll = nil end
    end
    self.pages = {}
    self.tabs = {}
    Tooltip.unbind(self)
    if self.root then
        if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.root:Destroy() end
        self.root = nil
    end
end

-- A page is a normal single-surface content host, including nested panels and tabs.
ContentMethods.installSingle(TabPage)
Scroll.install(TabPage)

return Tabs
