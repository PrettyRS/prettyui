local Layout = require("src/core/layout")
local Cursor = require("src/core/cursor")
local FancyButton = require("src/fancy_button")
local ComboBox = require("src/combo_box")
local List = require("src/list")
local SimpleButton = require("src/simple_button")
local Slider = require("src/slider")
local TextField = require("src/text_field")
local Sprites = require("src/core/sprites")
local Text = require("src/text")
local Tooltip = require("src/tooltip")
local Wheel = require("src/core/wheel")
local Components = require("src/core/components")

local CollapseButton = {}
CollapseButton.__index = CollapseButton

local SEGMENT_SIZE = 20
local MIN_WIDTH = SEGMENT_SIZE * 3
local CONTENT_GAP = 4
local ITEM_GAP = 4
local DEFAULT_INDENT = 20
local TEXT_COLOUR = 0xE7D7B0FF
local DISABLED_TEXT_COLOUR = 0x777777FF
local BODY_LINE_HEIGHT = 18

local function bodyFont(options)
    if options.font ~= nil and config.Font.FromID ~= nil then
        local succeeded, font = pcall(function() return config.Font.FromID(options.font) end)
        if succeeded and font ~= nil then return font end
    end
    return config.Font.MUSEO_SANS_15PT_REGULAR
end

local function bodyLineHeight(font, options)
    if options.lineSpacing ~= nil then return options.lineSpacing end
    if options.font ~= nil then
        local succeeded, baseline = pcall(function() return font.baseline end)
        if succeeded and baseline ~= nil then return baseline end
    end
    return BODY_LINE_HEIGHT
end

local function copyOptions(value)
    local copy = {}
    if type(value) == "table" then
        for key, option in pairs(value) do copy[key] = option end
    end
    return copy
end

local function measureText(text)
    local succeeded, width = pcall(function()
        return config.Font.MUSEO_SANS_15PT_REGULAR:GetStringWidth(text, false)
    end)
    return succeeded and width or #text * 7
end

function CollapseButton.getSize(text, options)
    options = options or {}
    text = tostring(text or "")
    local width = math.max(MIN_WIDTH, measureText(text) + SEGMENT_SIZE * 2)
    return options.width or width, SEGMENT_SIZE
end

local function sprite(parent)
    local component = Components.new(ui.Sprite, parent)
    component.clickthrough = true
    return component
end

function CollapseButton.new(parent, text, options)
    options = options or {}
    local width = CollapseButton.getSize(text, options)

    local self = setmetatable({}, CollapseButton)
    self.text = tostring(text or "")
    self.disabled = options.disabled == true
    self.expanded = options.expanded == true
    self.resizeParent = options.resizeParent == true
    self.hovered = false
    self.pressed = false
    self.indent = options.indent or DEFAULT_INDENT
    self.contentHeight = 0
    self.children = {}
    self.labels = {}
    self.equalizedButtons = {}
    self.onToggle = options.onToggle
    self._onScrollWheel = options._onScrollWheel
    self._scrollController = options._scrollController
    self.hoverCursor = options.hoverCursor or config.Cursor.CURSOR_BLANK
    self.textColour = options.colour or TEXT_COLOUR
    self.disabledTextColour = options.disabledColour or DISABLED_TEXT_COLOUR

    self.interfaceID = parent.interfaceID
    self.root = Components.new(ui.Layer, parent)
    self.root:SetPos(options.x or 0, options.y or 0, options.xAnchor or 0, options.yAnchor or 0)
    self.root:SetSize(width, SEGMENT_SIZE, options.widthAnchor or 0, 0)
    Wheel.bind(self.root, options)

    self.left = sprite(self.root)
    self.left:SetSize(SEGMENT_SIZE, SEGMENT_SIZE)

    self.middle = sprite(self.root)
    self.middle:SetPos(SEGMENT_SIZE, 0)
    self.middle:SetSize(-SEGMENT_SIZE * 2, SEGMENT_SIZE, 1.0)
    self.middle.isTiling = true

    self.right = sprite(self.root)
    self.right:SetPos(-SEGMENT_SIZE, 0, 1.0)
    self.right:SetSize(SEGMENT_SIZE, SEGMENT_SIZE)

    self.label = Components.new(ui.Text, self.root)
    self.label:SetPos(12, 0)
    self.label:SetSize(-12 - SEGMENT_SIZE, SEGMENT_SIZE, 1.0)
    self.label.content = self.text
    self.label.font = id.Font.MUSEO_SANS_15PT_REGULAR
    self.label.rgba = self.textColour
    self.label.isShadowed = options.shadowed ~= false
    self.label.alignHorizontal = ui.AlignMode.TOPLEFT
    self.label.alignVertical = ui.AlignMode.CENTRE
    self.label.maxLines = 1
    self.label.clickthrough = true

    self.content = Components.new(ui.Layer, self.root)
    self.content:SetPos(self.indent, SEGMENT_SIZE + CONTENT_GAP)
    self.content:SetSize(-self.indent, 0, 1.0)
    self.content.hidden = not self.expanded
    self.content.clickthrough = false
    Wheel.bind(self.content, options)

    local parentContext = Tooltip.getContext(parent)
    local tooltipParent = parentContext and parentContext.parent or parent
    self.contentTooltipContext = Tooltip.registerContext(self.content, tooltipParent, function(target)
        local rootX = self.root.x or 0
        local rootY = self.root.y or 0
        if parentContext then rootX, rootY = parentContext.position(self.root) end
        return rootX + (self.content.x or 0) + (target.x or 0),
            rootY + (self.content.y or 0) + (target.y or 0)
    end, parentContext)

    self.root:Subscribe(ui.Hook.ONMOUSEOVER, function()
        if self.disabled then return false end
        self.hovered = true
        self:_UpdateState()
        return true
    end)
    self.root:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        self.hovered = false
        self.pressed = false
        self:_UpdateState()
        return true
    end)
    self.root:Subscribe(ui.Hook.ONCLICK, function()
        if self.disabled then return false end
        self.pressed = true
        self:SetExpanded(not self.expanded)
        return false
    end)
    self.root:Subscribe(ui.Hook.ONRELEASE, function()
        self.pressed = false
        self:_UpdateState()
        return false
    end)

    self:_Resize()
    self:_UpdateState()
    Tooltip.bind(self, self.root, parent, options.tooltip)
    return self
end

function CollapseButton:_ExpandedHeight()
    if not self.expanded or self.contentHeight == 0 then return SEGMENT_SIZE end
    return SEGMENT_SIZE + CONTENT_GAP + self.contentHeight
end

function CollapseButton:_Resize()
    local height = self:_ExpandedHeight()
    if self.flowOwner then
        Layout.resize(self.flowOwner, self, height)
        if self.resizeParent and self.flowOwner._FitContent then
            self.flowOwner:_FitContent()
        end
    else
        self.root:SetHeight(height)
    end
end

function CollapseButton:_SetContentHeight(height)
    self.contentHeight = height
    self.content:SetHeight(height)
    self:_Resize()
end

function CollapseButton:_NextContentY(options)
    if options.y ~= nil then return options.y end
    if self.contentHeight == 0 then return 0 end
    return self.contentHeight + (options.marginTop or ITEM_GAP)
end

function CollapseButton:BindFlow(owner)
    self.flowOwner = owner
    self:_Resize()
    return self
end

function CollapseButton:_EqualizeButtonWidths()
    local width = 0
    for _, entry in ipairs(self.equalizedButtons) do
        if entry.button.root then width = math.max(width, entry.preferredWidth) end
    end
    for _, entry in ipairs(self.equalizedButtons) do
        if entry.button.root then entry.button.root:SetWidth(width) end
    end
end

function CollapseButton:_RegisterEqualizedButton(button, preferredWidth)
    local entry = { button = button, preferredWidth = preferredWidth }
    table.insert(self.equalizedButtons, entry)
    button._onPreferredWidthChanged = function(_, width)
        entry.preferredWidth = width
        self:_EqualizeButtonWidths()
    end
    self:_EqualizeButtonWidths()
end

function CollapseButton:AddSimpleButton(content, action, options)
    options = copyOptions(options)
    if options._onScrollWheel == nil then options._onScrollWheel = self._onScrollWheel end
    local width, height = SimpleButton.getSize(content, options)
    options.x = options.x or 0
    options.y = self:_NextContentY(options)
    local button = SimpleButton.new(self.content, content, action, options)
    table.insert(self.children, button)
    if type(content) == "string" then self:_RegisterEqualizedButton(button, width) end
    self:_SetContentHeight(math.max(self.contentHeight, options.y + height))
    return button
end

function CollapseButton:AddFancyButton(text, action, options)
    options = copyOptions(options)
    if options._onScrollWheel == nil then options._onScrollWheel = self._onScrollWheel end
    local width, height = FancyButton.getSize(text, options)
    options.x = options.x or 0
    options.y = self:_NextContentY(options)
    local button = FancyButton.new(self.content, text, action, options)
    table.insert(self.children, button)
    self:_RegisterEqualizedButton(button, width)
    self:_SetContentHeight(math.max(self.contentHeight, options.y + height))
    return button
end


function CollapseButton:AddSlider(options)
    options = copyOptions(options)
    if options._onScrollWheel == nil then options._onScrollWheel = self._onScrollWheel end
    local _, height = Slider.getSize(options)
    options.x = options.x or 0
    options.y = self:_NextContentY(options)
    options.width = options.width or 0
    options.widthAnchor = options.widthAnchor == nil and 1.0 or options.widthAnchor
    local slider = Slider.new(self.content, options)
    table.insert(self.children, slider)
    self:_SetContentHeight(math.max(self.contentHeight, options.y + height))
    return slider
end

local function addFullWidthControl(self, module, options)
    options = copyOptions(options)
    if options._onScrollWheel == nil then options._onScrollWheel = self._onScrollWheel end
    if options._scrollController == nil then
        options._scrollController = self._scrollController
    end
    local _, height = module.getSize(options)
    options.x = options.x or 0
    options.y = self:_NextContentY(options)
    options.width = options.width or 0
    options.widthAnchor = options.widthAnchor == nil and 1.0 or options.widthAnchor
    local component = module.new(self.content, options)
    table.insert(self.children, component)
    self:_SetContentHeight(math.max(self.contentHeight, options.y + height))
    return component
end

function CollapseButton:AddTextField(options)
    return addFullWidthControl(self, TextField, options)
end

function CollapseButton:AddKeybindField(options)
    return addFullWidthControl(self, require("src/keybind_field"), options)
end

function CollapseButton:AddComboBox(options)
    return addFullWidthControl(self, ComboBox, options)
end

function CollapseButton:AddList(options)
    return addFullWidthControl(self, List, options)
end

function CollapseButton:AddText(value)
    local options = type(value) == "table" and copyOptions(value) or { text = tostring(value or "") }
    if options._onScrollWheel == nil then options._onScrollWheel = self._onScrollWheel end
    options.text = tostring(options.text or "")
    options.x = options.x or 0
    options.y = self:_NextContentY(options)
    local availableWidth = math.max(1, (self.root.width or MIN_WIDTH) - self.indent)
    if options.height == nil then
        local font = bodyFont(options)
        local succeeded, lines = pcall(function()
            return font:GetStringLineCount(
                options.text, availableWidth, false, false, false
            )
        end)
        options.height = math.max(24, (succeeded and lines or 1) * bodyLineHeight(font, options) + 6)
    end
    options.width = options.width or 0
    options.widthAnchor = options.widthAnchor == nil and 1.0 or options.widthAnchor
    local label = Text.new(self.content, options)
    table.insert(self.labels, label)
    self:_SetContentHeight(math.max(self.contentHeight, options.y + options.height))
    return label
end

function CollapseButton:SetExpanded(expanded)
    expanded = expanded == true
    if self.expanded == expanded then return end
    self.expanded = expanded
    self.content.hidden = not expanded
    self:_Resize()
    self:_UpdateState()
    if self.onToggle then self.onToggle(self, expanded) end
end

function CollapseButton:Toggle()
    if not self.disabled then self:SetExpanded(not self.expanded) end
end

function CollapseButton:SetDisabled(disabled)
    self.disabled = disabled == true
    self.hovered = false
    self.pressed = false
    self:_UpdateState()
end

function CollapseButton:SetText(text)
    self.text = tostring(text or "")
    self.label.content = self.text
end

function CollapseButton:SetHoverCursor(cursor)
    self.hoverCursor = cursor
    self:_UpdateCursor()
end

function CollapseButton:SetTooltip(value)
    return Tooltip.set(self, value)
end

function CollapseButton:_UpdateCursor()
    Cursor.apply(self.root, self.hoverCursor, not self.disabled)
end

function CollapseButton:_UpdateState()
    self.root.enabled = not self.disabled
    self.root.clickthrough = self.disabled
    local state = "neutral"
    if self.disabled then
        state = "disabled"
    elseif self.expanded or self.pressed then
        state = "active"
    elseif self.hovered then
        state = "hovered"
    end
    local sprites = Sprites.COLLAPSE_BUTTON[state]
    self:_UpdateCursor()
    self.label.rgba = self.disabled and self.disabledTextColour or self.textColour
    self.left.spriteID = sprites.left
    self.middle.spriteID = sprites.middle
    self.right.spriteID = sprites.right
end

function CollapseButton:Destroy()
    local loaded = ui.Interfaces:GetInterface(self.interfaceID) ~= nil
    if self.content then
        Tooltip.unregisterContext(self.content)
        self.contentTooltipContext = nil
    end
    for index = #self.children, 1, -1 do
        local child = self.children[index]
        if child then
            child:Destroy()
        end
    end
    self.children = {}
    if loaded then
        for index = #self.labels, 1, -1 do
            local label = self.labels[index]
            if label then label:Destroy() end
        end
    end
    self.labels = {}
    self.equalizedButtons = {}
    Tooltip.unbind(self)
    if self.root then
        if loaded then self.root:Destroy() end
        self.root = nil
        self.content = nil
    end
end

return CollapseButton
