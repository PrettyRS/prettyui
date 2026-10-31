local Palette = require("src/core/control_palette")
local Tooltip = require("src/tooltip")
local Wheel = require("src/core/wheel")
local Components = require("src/core/components")

local ComboBox = {}
ComboBox.__index = ComboBox

local DEFAULT_WIDTH = 240
local DEFAULT_HEIGHT = 30
local DEFAULT_TEXT_COLOUR = Palette.TEXT

local function entryParts(entry, fallbackID)
    if type(entry) == "table" then
        return tostring(entry.label or entry.text or ""), entry.id or entry.value or fallbackID
    end
    return tostring(entry), fallbackID
end

local function orderedEntries(entries)
    local result = {}
    local hasOrder = false

    for index, entry in ipairs(entries or {}) do
        local label, entryID = entryParts(entry, index)
        local order = type(entry) == "table" and entry.order or nil
        if order ~= nil then
            if type(order) ~= "number" or order ~= math.floor(order) then
                error("ComboBox entry order must be an integer")
            end
            hasOrder = true
        end
        result[index] = {
            entryID = entryID,
            index = index,
            label = label,
            order = order,
        }
    end

    if not hasOrder then return entries or {}, false end

    table.sort(result, function(left, right)
        if left.order ~= right.order then
            if left.order == nil then return false end
            if right.order == nil then return true end
            return left.order < right.order
        end
        if left.label ~= right.label then return left.label < right.label end
        return left.index < right.index
    end)

    return result, true
end

function ComboBox.getSize(options)
    options = options or {}
    return options.width or DEFAULT_WIDTH, options.height or DEFAULT_HEIGHT
end

function ComboBox.new(parent, options)
    options = options or {}
    local _, hasOrder = orderedEntries(options.entries or options.choices or {})
    if hasOrder then
        return require("src/ordered_combo_box").new(parent, options)
    end

    local self = setmetatable({}, ComboBox)
    self.onChange = options.onChange
    self.disabled = options.disabled == true
    self._labelsByID = {}

    self.interfaceID = parent.interfaceID
    self.root = Components.new(ui.ComboField, parent)
    self.root.stylesheetID = options.stylesheetID or id.StyleSheet.COMBO_DEFAULT
    self.root:SetPos(options.x or 0, options.y or 0, options.xAnchor or 0, options.yAnchor or 0)
    self.root:SetSize(
        options.width or DEFAULT_WIDTH,
        options.height or DEFAULT_HEIGHT,
        options.widthAnchor or 0,
        options.heightAnchor or 0
    )
    self.root.entryHeight = options.entryHeight or 24
    self.root.dropdownMaxVisibleEntries = options.maxVisibleEntries or options.dropdownMaxVisibleEntries or 8
    self.root.contentMargin = options.contentMargin or ui.Margin.new(8, 0, 8, 0)
    self.root.headerMargin = options.headerMargin or ui.Margin.new(8, 0, 8, 0)
    self.root.entryText.font = options.font or id.Font.MUSEO_SANS_15PT_REGULAR
    self.root.entryText.rgba = options.colour or options.color or DEFAULT_TEXT_COLOUR
    self.root.entryText.isShadowed = options.shadowed ~= false
    self.root.mouseoverForegroundRGBA = options.hoverTextColour
        or options.hoverTextColor
        or self.root.entryText.rgba
    self.root.mouseoverBackgroundRGBA = options.hoverColour or options.hoverColor or Palette.HOVER
    self.root.selectedForegroundRGBA = options.selectedTextColour
        or options.selectedTextColor
        or self.root.entryText.rgba
    self.root.selectedBackgroundRGBA = options.selectedColour or options.selectedColor or Palette.SELECTED
    self.root.disabledForegroundRGBA = options.disabledTextColour
        or options.disabledTextColor
        or Palette.DISABLED_TEXT
    self.root.selectionHighlightRGBA = options.selectionColour
        or options.selectionColor
        or Palette.SELECTED
    self.root.caretRGBA = options.caretColour or options.caretColor or Palette.CARET
    self.root.errorCaretRGBA = options.errorCaretColour
        or options.errorCaretColor
        or self.root.caretRGBA
    self.root.enabled = not self.disabled
    self.root.clickthrough = self.disabled
    Wheel.bind(self.root, options)

    self:SetEntries(options.entries or options.choices or {}, options.selectedID or options.selected)
    self.root:Subscribe(ui.Hook.ONSELECTIONCHANGED, function(_, entryID, eventType)
        if not self._suppressCallbacks and self.onChange then
            self.onChange(self, entryID, self:GetSelectedLabel(), eventType)
        end
        return false
    end)

    Tooltip.bind(self, self.root, parent, options.tooltip)
    return self
end

function ComboBox:Add(label, entryID)
    label = tostring(label)
    local result = self.root:Add(label, entryID)
    if result then self._labelsByID[entryID] = label end
    return result
end

function ComboBox:Remove(entryID)
    local result = self.root:Remove(entryID)
    if result then self._labelsByID[entryID] = nil end
    return result
end

function ComboBox:Clear()
    self.root:Clear()
    self._labelsByID = {}
end

function ComboBox:SetEntries(entries, selectedID)
    local _, hasOrder = orderedEntries(entries)
    self._labelsByID = {}
    for index, entry in ipairs(entries or {}) do
        local label, entryID = entryParts(entry, index)
        self._labelsByID[entryID] = label
    end

    if hasOrder then
        error("ordered entries require a ComboBox constructed with ordered entries")
    end

    local entriesMap = {}
    local labels = {}
    local selectedLabel
    local hasUniqueLabels = true

    for index, entry in ipairs(entries or {}) do
        local label, entryID = entryParts(entry, index)
        if entriesMap[label] ~= nil then
            hasUniqueLabels = false
        else
            entriesMap[label] = entryID
            labels[#labels + 1] = label
        end
        if entryID == selectedID then selectedLabel = label end
    end

    if selectedID ~= nil and selectedLabel ~= nil and hasUniqueLabels then
        local setEntriesResult = self.root:SetEntries(entriesMap, selectedID)
        if self.root.hasSelection and self.root.selectedID == selectedID then
            return setEntriesResult
        end

        -- Some client builds interpret selectedID as the one-based position
        -- of the label after sorting instead of as the map's explicit ID.
        table.sort(labels)
        for position, label in ipairs(labels) do
            if label == selectedLabel then
                local fallbackResult = self.root:SetEntries(entriesMap, position)
                if self.root.hasSelection and self.root.selectedID == selectedID then
                    return fallbackResult
                end
                break
            end
        end
    end

    self.root:Clear()
    for index, entry in ipairs(entries or {}) do
        local label, entryID = entryParts(entry, index)
        self.root:Add(label, entryID)
    end
    if selectedID ~= nil then self:Select(selectedID, false) end
end

function ComboBox:Select(entryID, triggerEvents)
    self._suppressCallbacks = triggerEvents ~= true
    local result = self.root:Select(entryID, triggerEvents == true)
    self._suppressCallbacks = false
    return result
end

function ComboBox:GetSelectedID()
    return self.root.hasSelection and self.root.selectedID or nil
end

function ComboBox:GetSelectedLabel()
    if not self.root.hasSelection then return nil end
    return self._labelsByID[self.root.selectedID] or self.root.selectedLabel
end

function ComboBox:SetDisabled(disabled)
    self.disabled = disabled == true
    self.root.enabled = not self.disabled
    self.root.clickthrough = self.disabled
end

function ComboBox:SetTooltip(value)
    return Tooltip.set(self, value)
end

function ComboBox:Destroy()
    Tooltip.unbind(self)
    if self.root then
        if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.root:Destroy() end
        self.root = nil
    end
end

return ComboBox
