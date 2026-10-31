local List = require("src/list")
local Palette = require("src/core/control_palette")
local Tooltip = require("src/tooltip")
local Wheel = require("src/core/wheel")
local clamp = require("src/core/math").clamp
local Components = require("src/core/components")

local OrderedComboBox = {}
OrderedComboBox.__index = OrderedComboBox

local DEFAULT_WIDTH = 240
local DEFAULT_HEIGHT = 30
local DEFAULT_ENTRY_HEIGHT = 24
local DEFAULT_MAX_VISIBLE_ENTRIES = 8
local DEFAULT_TEXT_COLOUR = Palette.TEXT
local BUTTON_WIDTH = 24
local CONTENT_TOP_INSET = 3

local function entryParts(entry, fallbackID)
    if type(entry) == "table" then
        return tostring(entry.label or entry.text or ""), entry.id or entry.value or fallbackID
    end
    return tostring(entry), fallbackID
end

function OrderedComboBox.sortEntries(entries)
    local result = {}
    for index, entry in ipairs(entries or {}) do
        local label, entryID = entryParts(entry, index)
        local order = type(entry) == "table" and entry.order or nil
        if order ~= nil and (type(order) ~= "number" or order ~= math.floor(order)) then
            error("ComboBox entry order must be an integer")
        end
        result[index] = {
            id = entryID,
            label = label,
            order = order,
            index = index,
        }
    end
    table.sort(result, function(left, right)
        if left.order ~= right.order then
            if left.order == nil then return false end
            if right.order == nil then return true end
            return left.order < right.order
        end
        if left.label ~= right.label then return left.label < right.label end
        return left.index < right.index
    end)
    return result
end

local function findOwnerWindow(context)
    while context do
        if context.ownerWindow then return context.ownerWindow end
        context = context.parentContext
    end
end

function OrderedComboBox.new(parent, options)
    options = options or {}
    local self = setmetatable({}, OrderedComboBox)
    self.parent = parent
    self.context = Tooltip.getContext(parent)
    self.overlayParent = options.overlayParent or (self.context and self.context.parent) or parent
    self.ownerWindow = findOwnerWindow(self.context)
    self.onChange = options.onChange
    self.disabled = options.disabled == true
    self.open = false
    self.entryHeight = options.entryHeight or DEFAULT_ENTRY_HEIGHT
    self.maxVisibleEntries = options.maxVisibleEntries
        or options.dropdownMaxVisibleEntries
        or DEFAULT_MAX_VISIBLE_ENTRIES
    self.entries = {}
    self.entriesByID = {}
    self._pendingInputContents = {}

    self.interfaceID = parent.interfaceID
    self.root = Components.new(ui.Layer, parent)
    self.root:SetPos(options.x or 0, options.y or 0, options.xAnchor or 0, options.yAnchor or 0)
    self.root:SetSize(
        options.width or DEFAULT_WIDTH,
        options.height or DEFAULT_HEIGHT,
        options.widthAnchor or 0,
        options.heightAnchor or 0
    )
    Wheel.bind(self.root, options)

    -- Keep the native frame and dropdown-button artwork as the visual shell.
    self.shell = Components.new(ui.ComboField, self.root)
    self.shell.stylesheetID = options.stylesheetID or id.StyleSheet.COMBO_DEFAULT
    self.shell:SetSize(0, 0, 1.0, 1.0)
    self.shell.clickthrough = true

    self.input = Components.new(ui.InputField, self.root)
    self.input.stylesheetID = options.inputStylesheetID or id.StyleSheet.INPUT_DEFAULT
    self.input:SetSize(-BUTTON_WIDTH, 0, 1.0, 1.0)
    self.input:Setup(
        ui.TextContentVisibilityMode.VISIBLE,
        ui.InputFieldFilterMode.NONE,
        options.maxLength or 0
    )
    self.input.inputMode = options.inputMode or ui.InputFieldKeyHandlingMode.DEFAULT
    self.input.contentMargin = options.contentMargin
        or ui.Margin.new(8, CONTENT_TOP_INSET, 4, 0)
    self.input.text.font = options.font or id.Font.MUSEO_SANS_15PT_REGULAR
    self.input.text.rgba = options.colour or options.color or DEFAULT_TEXT_COLOUR
    self.input.text.isShadowed = options.shadowed ~= false
    self.input.emptyTextRGBA = options.placeholderColour
        or options.placeholderColor
        or Palette.DISABLED_TEXT
    self.input.caretRGBA = options.caretColour or options.caretColor or Palette.CARET
    self.input.selectionHighlightRGBA = options.selectionColour
        or options.selectionColor
        or Palette.SELECTED
    self.input.containerSprite.alpha = 0

    self.button = Components.new(ui.Layer, self.root)
    self.button:SetPos(-BUTTON_WIDTH, 0, 1.0, 0)
    self.button:SetSize(BUTTON_WIDTH, 0, 0, 1.0)
    self.button.clickthrough = false
    self.input:MoveToFront()
    self.button:MoveToFront()

    self.dropdown = List.new(self.overlayParent, {
        width = options.width or DEFAULT_WIDTH,
        height = self.entryHeight + 2,
        entryHeight = self.entryHeight,
        font = options.font,
        colour = options.colour or options.color,
        disabledColour = options.disabledTextColour or options.disabledTextColor,
        backgroundColour = options.dropdownBackgroundColour or options.dropdownBackgroundColor,
        borderColour = options.dropdownBorderColour or options.dropdownBorderColor,
        hoverColour = options.hoverColour or options.hoverColor,
        selectedColour = options.selectedColour or options.selectedColor,
        shadowed = options.shadowed,
        _onEntryClick = function(_, entryID)
            self:Select(entryID, true, ui.SelectionChangeEvent.SELECTED)
            self:_Close()
        end,
    })
    self.dropdown.root.hidden = true

    self.input:Subscribe(ui.Hook.ONCLICK, function()
        if not self.disabled then self:_Open() end
        return false
    end)
    self.button:Subscribe(ui.Hook.ONCLICK, function()
        if self.disabled then return false end
        if self.open then self:_Close() else self:_Open() end
        return false
    end)
    self.input:Subscribe(ui.Hook.ONCONTENTCHANGED, function(_, reason, content)
        for index, pending in ipairs(self._pendingInputContents) do
            if pending == content then
                -- Content events are asynchronous and some client builds omit
                -- intermediate values when assignments occur in quick succession.
                for _ = 1, index do table.remove(self._pendingInputContents, 1) end
                return false
            end
        end
        if reason == ui.InputFieldActionResult.SUBMIT_ON_ESCAPE then
            self:_Close()
            return false
        end
        if reason == ui.InputFieldActionResult.SUBMIT_ON_FOCUS_LOSS then
            if not self.dropdown.root.isMouseOver and not self.button.isMouseOver then
                self:_Close()
            end
            return false
        end
        self:_Filter(content)
        if reason == ui.InputFieldActionResult.SUBMIT then
            local first = self:_FirstVisibleEntry()
            if first then self:Select(first.id, true) end
            self:_Close()
        elseif not self.open then
            self:_Open(false)
        end
        return false
    end)

    self:SetEntries(options.entries or options.choices or {}, options.selectedID or options.selected)
    self:SetDisabled(self.disabled)
    Tooltip.bind(self, self.root, parent, options.tooltip)

    if self.ownerWindow then
        self.ownerWindow:_RegisterOverlay(
            self.dropdown.root,
            function() return self.open end,
            function() self:_LayoutDropdown() end
        )
    end
    return self
end

function OrderedComboBox:_SetInput(value)
    local content = tostring(value or "")
    if self.input.content == content then return end
    self._pendingInputContents[#self._pendingInputContents + 1] = content
    self.input.content = content
end

function OrderedComboBox:_LayoutDropdown()
    local x, y = self.root.x or 0, self.root.y or 0
    if self.context and self.context.active then x, y = self.context.position(self.root) end
    local width = math.max(1, self.root.width or DEFAULT_WIDTH)
    local visible = 0
    for _, entry in ipairs(self.entries) do
        if entry.visible then visible = visible + 1 end
    end
    local rows = clamp(visible, 1, self.maxVisibleEntries)
    local height = rows * self.entryHeight + 2
    local rootHeight = self.root.height or DEFAULT_HEIGHT
    local dropdownY = y + rootHeight
    local parentHeight = self.overlayParent and (self.overlayParent.height or 0) or 0
    if parentHeight > 0 and dropdownY + height > parentHeight and y >= height then
        dropdownY = y - height
    end
    self.dropdown.root:SetPos(x, dropdownY)
    self.dropdown:SetSize(width, height)
    self.dropdown:SetScrollPosition(0)
end

function OrderedComboBox:_FirstVisibleEntry()
    for _, entry in ipairs(self.entries) do
        if entry.visible then return entry end
    end
end

function OrderedComboBox:_Filter(value)
    local query = string.lower(tostring(value or ""))
    for _, entry in ipairs(self.entries) do
        entry.visible = query == ""
            or string.find(string.lower(entry.label), query, 1, true) ~= nil
        self.dropdown:SetEntryVisible(entry.id, entry.visible)
    end
    if self.selectedID and self.entriesByID[self.selectedID]
        and self.entriesByID[self.selectedID].visible then
        self.dropdown:SetSelected(self.selectedID, true, false)
    end
    self:_LayoutDropdown()
end

function OrderedComboBox:_Open(clearInput)
    if self.disabled then return end
    self.open = true
    if clearInput ~= false then self:_SetInput("") end
    self:_Filter(self.input.content)
    self.dropdown.root.hidden = false
    self.dropdown.root:MoveToFront()
end

function OrderedComboBox:_Close()
    self.open = false
    self.dropdown.root.hidden = true
    self:_SetInput(self.selectedLabel or "")
end

function OrderedComboBox:Add(label, entryID)
    if entryID == nil or self.entriesByID[entryID] then return false end
    local entries = {}
    for _, entry in ipairs(self.entries) do
        entries[#entries + 1] = { label = entry.label, id = entry.id, order = entry.order }
    end
    entries[#entries + 1] = { label = tostring(label), id = entryID }
    self:SetEntries(entries, self.selectedID)
    return true
end

function OrderedComboBox:Remove(entryID)
    if not self.entriesByID[entryID] then return false end
    local entries = {}
    for _, entry in ipairs(self.entries) do
        if entry.id ~= entryID then
            entries[#entries + 1] = { label = entry.label, id = entry.id, order = entry.order }
        end
    end
    self:SetEntries(entries, self.selectedID == entryID and nil or self.selectedID)
    return true
end

function OrderedComboBox:Clear()
    self.entries = {}
    self.entriesByID = {}
    self.selectedID = nil
    self.selectedLabel = nil
    self.dropdown:Clear()
    self:_Close()
end

function OrderedComboBox:SetEntries(entries, selectedID)
    self.entries = OrderedComboBox.sortEntries(entries)
    self.entriesByID = {}
    local listEntries = {}
    for _, entry in ipairs(self.entries) do
        entry.visible = true
        self.entriesByID[entry.id] = entry
        listEntries[#listEntries + 1] = { label = entry.label, id = entry.id }
    end
    self.dropdown:SetEntries(listEntries)
    local selectionID = self.entriesByID[selectedID] and selectedID
        or (self.entries[1] and self.entries[1].id)
    if selectionID then self:Select(selectionID, false) else self:_Close() end
end

function OrderedComboBox:Select(entryID, triggerEvents, eventType)
    local entry = self.entriesByID[entryID]
    if not entry then return false end
    self.selectedID = entry.id
    self.selectedLabel = entry.label
    self.dropdown:SetSelected(entry.id, true, false)
    self:_SetInput(entry.label)
    if triggerEvents == true and self.onChange then
        self.onChange(
            self,
            entry.id,
            entry.label,
            eventType or ui.SelectionChangeEvent.SELECTED
        )
    end
    return true
end

function OrderedComboBox:GetSelectedID()
    return self.selectedID
end

function OrderedComboBox:GetSelectedLabel()
    return self.selectedLabel
end

function OrderedComboBox:SetDisabled(disabled)
    self.disabled = disabled == true
    self.shell.enabled = not self.disabled
    self.input.enabled = not self.disabled
    self.input.clickthrough = self.disabled
    self.button.enabled = not self.disabled
    self.button.clickthrough = self.disabled
    self.dropdown:SetDisabled(self.disabled)
    if self.disabled then self:_Close() end
end

function OrderedComboBox:SetTooltip(value)
    return Tooltip.set(self, value)
end

function OrderedComboBox:Destroy()
    Tooltip.unbind(self)
    if self.ownerWindow and self.dropdown and self.dropdown.root then
        self.ownerWindow:_UnregisterOverlay(self.dropdown.root)
    end
    if self.dropdown then self.dropdown:Destroy() self.dropdown = nil end
    if self.root then
        if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.root:Destroy() end
        self.root = nil
    end
    self.entries = {}
    self.entriesByID = {}
    self._pendingInputContents = {}
end

return OrderedComboBox
