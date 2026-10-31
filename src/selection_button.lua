local Components = require("src/core/components")
local Cursor = require("src/core/cursor")
local Sprites = require("src/core/sprites")
local Tooltip = require("src/tooltip")
local Wheel = require("src/core/wheel")

local SelectionButton = {}
SelectionButton.__index = SelectionButton

local BOX_SIZE = 14
local ROW_HEIGHT = 22
local LABEL_X = 22
local MIN_WIDTH = 80
local INLINE_CHOICE_GAP = 12
local TEXT_COLOUR = 0xE7D7B0FF
local DISABLED_TEXT_COLOUR = 0x777777FF

local function normalizeChoice(choice)
    if type(choice) ~= "table" then
        return { text = tostring(choice), value = choice, selected = false }
    end
    local value = choice.value
    local text = choice.text or choice.label
    if text == nil then text = value end
    text = tostring(text or "")
    if value == nil then value = text end
    return {
        text = text,
        value = value,
        selected = choice.selected == true,
        disabled = choice.disabled == true,
        tooltip = choice.tooltip,
    }
end

local function normalizeChoices(choices)
    if type(choices) ~= "table" or #choices == 0 then
        error("Selection button choices must be a non-empty array")
    end
    local normalized = {}
    for index, choice in ipairs(choices) do normalized[index] = normalizeChoice(choice) end
    return normalized
end

local function contains(values, target)
    if type(values) ~= "table" then return false end
    for _, value in ipairs(values) do
        if value == target then return true end
    end
    return values[target] == true
end

local function measureChoiceWidth(choice)
    local normalized = normalizeChoice(choice)
    local succeeded, width = pcall(function()
        return config.Font.MUSEO_SANS_15PT_REGULAR:GetStringWidth(normalized.text, false)
    end)
    return LABEL_X + (succeeded and width or #normalized.text * 7)
end

local function measureWidth(choices)
    local widest = 0
    for _, choice in ipairs(choices) do
        widest = math.max(widest, measureChoiceWidth(choice))
    end
    return math.max(MIN_WIDTH, widest)
end

local function measureInlineWidth(choices)
    local width = 0
    for index, choice in ipairs(choices) do
        if index > 1 then width = width + INLINE_CHOICE_GAP end
        width = width + measureChoiceWidth(choice)
    end
    return math.max(MIN_WIDTH, width)
end

function SelectionButton.getSize(choices, options)
    options = options or {}
    local choicesInline = options.inline == true
    local width = options.width
    if width == nil then
        width = choicesInline and measureInlineWidth(choices) or measureWidth(choices)
    end
    return width, choicesInline and ROW_HEIGHT or #choices * ROW_HEIGHT
end

local function buildSelectionButton(kind, parent, choices, options)
    options = options or {}
    local items = normalizeChoices(choices)
    local choicesInline = options.inline == true
    local width, height = SelectionButton.getSize(items, options)

    local self = setmetatable({}, SelectionButton)
    self.kind = kind
    self.items = items
    self.disabled = options.disabled == true
    self.onChange = options.onChange
    self.textColour = options.colour or TEXT_COLOUR
    self.disabledTextColour = options.disabledColour or DISABLED_TEXT_COLOUR
    self.tickCursor = options.tickCursor or config.Cursor.CURSOR_TICK
    self.crossCursor = options.crossCursor or config.Cursor.CURSOR_CROSS
    self.selectedValue = nil
    self.selectedValues = {}
    self.selectedSet = {}

    if kind == "radio" then
        local requested = options.selectedValue
        local hasRequested = requested ~= nil
        for _, item in ipairs(items) do
            if self.selectedValue == nil and ((hasRequested and item.value == requested) or
                (not hasRequested and item.selected)) then
                item.selected = true
                self.selectedValue = item.value
            else
                item.selected = false
            end
        end
    else
        for _, item in ipairs(items) do
            item.selected = contains(options.selectedValues, item.value) or item.selected
        end
        self:_RebuildSelectedValues()
    end

    self.interfaceID = parent.interfaceID
    self.root = Components.new(ui.Layer, parent)
    self.root:SetPos(options.x or 0, options.y or 0, options.xAnchor or 0, options.yAnchor or 0)
    self.root:SetSize(width, height, options.widthAnchor or 0, 0)
    self.root.clickthrough = false
    Wheel.bind(self.root, options)

    local parentContext = Tooltip.getContext(parent)
    local tooltipParent = parentContext and parentContext.parent or parent
    self.optionTooltipContext = Tooltip.registerContext(self.root, tooltipParent, function(target)
        local rootX = self.root.x or 0
        local rootY = self.root.y or 0
        if parentContext then rootX, rootY = parentContext.position(self.root) end
        return rootX + (target.x or 0), rootY + (target.y or 0)
    end, parentContext)

    local nextX = 0
    for index, item in ipairs(items) do
        local row = Components.new(ui.Layer, self.root)
        if choicesInline then
            local rowWidth = measureChoiceWidth(item)
            row:SetPos(nextX, 0)
            row:SetSize(rowWidth, ROW_HEIGHT)
            nextX = nextX + rowWidth + INLINE_CHOICE_GAP
        else
            row:SetPos(0, (index - 1) * ROW_HEIGHT)
            row:SetSize(0, ROW_HEIGHT, 1.0)
        end
        item.row = row
        item.hovered = false
        Wheel.bind(row, options)

        item.box = Components.new(ui.Sprite, row)
        item.box:SetPos(0, math.floor((ROW_HEIGHT - BOX_SIZE) / 2))
        item.box:SetSize(BOX_SIZE, BOX_SIZE)
        item.box.clickthrough = true

        item.label = Components.new(ui.Text, row)
        item.label:SetPos(LABEL_X, 0)
        item.label:SetSize(-LABEL_X, ROW_HEIGHT, 1.0)
        item.label.content = item.text
        item.label.font = id.Font.MUSEO_SANS_15PT_REGULAR
        item.label.rgba = self.textColour
        item.label.isShadowed = options.shadowed ~= false
        item.label.alignHorizontal = ui.AlignMode.TOPLEFT
        item.label.alignVertical = ui.AlignMode.CENTRE
        item.label.maxLines = 1
        item.label.clickthrough = true

        row:Subscribe(ui.Hook.ONMOUSEOVER, function()
            if self.disabled or item.disabled then return false end
            item.hovered = true
            self:_UpdateItem(item)
            return true
        end)
        row:Subscribe(ui.Hook.ONMOUSELEAVE, function()
            item.hovered = false
            self:_UpdateItem(item)
            return true
        end)
        row:Subscribe(ui.Hook.ONCLICK, function()
            if self.disabled or item.disabled then return false end
            if self.kind == "radio" then
                if item.selected then return false end
                self:SetSelectedValue(item.value)
            else
                self:SetSelected(item.value, not item.selected)
            end
            return false
        end)

        Tooltip.bind(item, row, self.root, item.tooltip, "tooltipAttachment")
        self:_UpdateItem(item)
    end

    Tooltip.bind(self, self.root, parent, options.tooltip)
    return self
end

function SelectionButton.new(kind, parent, choices, options)
    return Components.withBatch(parent, function()
        return buildSelectionButton(kind, parent, choices, options)
    end)
end

function SelectionButton:_RebuildSelectedValues()
    self.selectedValues = {}
    self.selectedSet = {}
    for _, item in ipairs(self.items) do
        if item.selected then
            table.insert(self.selectedValues, item.value)
            self.selectedSet[item.value] = true
        end
    end
end

function SelectionButton:_UpdateItem(item)
    local sprites = self.kind == "radio" and Sprites.RADIO_BUTTON or Sprites.CHECKBOX_BUTTON
    if item.selected then
        item.box.spriteID = item.hovered and sprites.selectedHovered or sprites.selected
    else
        item.box.spriteID = item.hovered and sprites.emptyHovered or sprites.empty
    end

    local interactive = not self.disabled and not item.disabled
    local cursor = nil
    if interactive then
        if self.kind == "checkbox" and item.selected then
            cursor = self.crossCursor
        elseif not item.selected then
            cursor = self.tickCursor
        end
    end
    Cursor.apply(item.row, cursor, interactive and cursor ~= nil)
    item.row.enabled = interactive
    item.row.clickthrough = not interactive
    item.label.rgba = interactive and self.textColour or self.disabledTextColour
end

function SelectionButton:_UpdateAll()
    for _, item in ipairs(self.items) do self:_UpdateItem(item) end
end

function SelectionButton:GetSelectedValue()
    return self.selectedValue
end

function SelectionButton:SetSelectedValue(value, notify)
    if self.kind ~= "radio" then return false end
    local match = nil
    if value ~= nil then
        for _, item in ipairs(self.items) do
            if item.value == value then match = item break end
        end
        if match == nil then return false end
    end
    if self.selectedValue == value then return true end
    for _, item in ipairs(self.items) do item.selected = item == match end
    self.selectedValue = value
    self:_UpdateAll()
    if notify ~= false and self.onChange then self.onChange(self, value) end
    return true
end

function SelectionButton:GetSelectedValues()
    local values = {}
    for index, value in ipairs(self.selectedValues) do values[index] = value end
    return values
end

function SelectionButton:IsSelected(value)
    if self.kind == "radio" then return self.selectedValue == value end
    return self.selectedSet[value] == true
end

function SelectionButton:SetSelected(value, selected, notify)
    if self.kind ~= "checkbox" then return false end
    local match = nil
    for _, item in ipairs(self.items) do
        if item.value == value then match = item break end
    end
    if match == nil then return false end
    selected = selected == true
    if match.selected == selected then return true end
    match.selected = selected
    self:_RebuildSelectedValues()
    self:_UpdateItem(match)
    if notify ~= false and self.onChange then
        self.onChange(self, self:GetSelectedValues(), value, selected)
    end
    return true
end

function SelectionButton:SetDisabled(disabled)
    self.disabled = disabled == true
    for _, item in ipairs(self.items) do item.hovered = false end
    self:_UpdateAll()
end

function SelectionButton:SetTooltip(value)
    return Tooltip.set(self, value)
end

function SelectionButton:SetOptionTooltip(value, tooltip)
    for _, item in ipairs(self.items) do
        if item.value == value then
            item.tooltip = tooltip
            return Tooltip.set(item, tooltip, "tooltipAttachment")
        end
    end
    return false
end

function SelectionButton:Destroy()
    for _, item in ipairs(self.items) do Tooltip.unbind(item, "tooltipAttachment") end
    if self.root then
        Tooltip.unregisterContext(self.root)
        self.optionTooltipContext = nil
    end
    Tooltip.unbind(self)
    if self.root then
        if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.root:Destroy() end
        self.root = nil
    end
    self.items = {}
end

return {
    CheckboxButton = {
        getSize = SelectionButton.getSize,
        new = function(parent, choices, options)
            return SelectionButton.new("checkbox", parent, choices, options)
        end,
    },
    RadioButton = {
        getSize = SelectionButton.getSize,
        new = function(parent, choices, options)
            return SelectionButton.new("radio", parent, choices, options)
        end,
    },
}
