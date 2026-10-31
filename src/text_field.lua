local Components = require("src/core/components")
local Palette = require("src/core/control_palette")
local Tooltip = require("src/tooltip")
local Wheel = require("src/core/wheel")

local TextField = {}
TextField.__index = TextField

local DEFAULT_WIDTH = 240
local DEFAULT_HEIGHT = 30
local DEFAULT_TEXT_COLOUR = Palette.TEXT
local DEFAULT_PLACEHOLDER_COLOUR = 0x99958DFF
local INPUT_MARGIN = 8
local CONTENT_TOP_INSET = 3
local defaultInputSprite = nil

function TextField.SetDefaultSprite(sprite)
    defaultInputSprite = sprite
end

function TextField.getSize(options)
    options = options or {}
    return options.width or DEFAULT_WIDTH, options.height or DEFAULT_HEIGHT
end

function TextField.new(parent, options)
    options = options or {}
    local self = setmetatable({}, TextField)
    self.onChange = options.onChange
    self.onSubmit = options.onSubmit
    self.disabled = options.disabled == true
    self._scrollController = options._scrollController

    self.interfaceID = parent.interfaceID
    self.root = Components.new(ui.InputField, parent)
    self.root.stylesheetID = options.stylesheetID or id.StyleSheet.INPUT_DEFAULT
    self.root:SetPos(options.x or 0, options.y or 0, options.xAnchor or 0, options.yAnchor or 0)
    self.root:SetSize(
        options.width or DEFAULT_WIDTH,
        options.height or DEFAULT_HEIGHT,
        options.widthAnchor or 0,
        options.heightAnchor or 0
    )
    self.root:Setup(
        options.visibility or ui.TextContentVisibilityMode.VISIBLE,
        options.filterMode or options.filter or ui.InputFieldFilterMode.NONE,
        options.maxLength or 9999
    )
    self.root.inputMode = options.inputMode or ui.InputFieldKeyHandlingMode.DEFAULT
    self.root.emptyText = options.placeholder or options.emptyText or ""
    self.root.content = tostring(options.text or options.content or "")
    self.root.contentMargin = options.contentMargin
        or ui.Margin.new(8, CONTENT_TOP_INSET, 8, 0)
    self.root.text.font = options.font or id.Font.MUSEO_SANS_15PT_REGULAR
    self.root.text.rgba = options.colour or options.color or DEFAULT_TEXT_COLOUR
    self.root.text.isShadowed = options.shadowed ~= false
    self.root.emptyTextRGBA = options.placeholderColour or options.placeholderColor or DEFAULT_PLACEHOLDER_COLOUR
    self.root.caretRGBA = options.caretColour or options.caretColor or Palette.CARET
    self.root.selectionHighlightRGBA = options.selectionColour
        or options.selectionColor
        or Palette.SELECTED
    self.root.enabled = not self.disabled
    self.root.clickthrough = self.disabled
    Wheel.bind(self.root, options)

    local backgroundSprite = options.inputSprite or defaultInputSprite
    if backgroundSprite then
        self.root.containerSprite.sprite = backgroundSprite
        self.root.containerSprite.visualMargins = ui.Margin.new(INPUT_MARGIN)
        self.root.containerSprite.isTiling = true
    end

    self.root:Subscribe(ui.Hook.ONCONTENTCHANGED, function(_, reason, content)
        if self._suppressCallbacks then return false end
        if self.onChange then self.onChange(self, reason, content) end
        if self.onSubmit and reason == ui.InputFieldActionResult.SUBMIT then
            self.onSubmit(self, content)
        end
        return false
    end)

    Tooltip.bind(self, self.root, parent, options.tooltip)
    if self._scrollController then self._scrollController:RegisterClipTarget(self) end
    return self
end

function TextField:GetText()
    return self.root and self.root.content or ""
end

function TextField:SetText(value, triggerCallback)
    if not self.root then return end
    local content = tostring(value or "")
    self._suppressCallbacks = true
    self.root.content = content
    self._suppressCallbacks = false
    if triggerCallback == true and self.onChange then
        self.onChange(self, ui.InputFieldActionResult.CONTENT_CHANGE, content)
    end
end

function TextField:SetPlaceholder(value)
    if self.root then self.root.emptyText = tostring(value or "") end
end

function TextField:SetDisabled(disabled)
    self.disabled = disabled == true
    if self.root then
        self.root.enabled = not self.disabled
        self.root.clickthrough = self.disabled
    end
end

function TextField:_SetContentClipped(clipped)
    local root = self.root
    if root == nil then return end
    local appearance = self._unclippedAppearance
    if clipped then
        if appearance then return end
        self._unclippedAppearance = {
            textRGBA = root.text.rgba,
            isShadowed = root.text.isShadowed,
            emptyTextRGBA = root.emptyTextRGBA,
            caretRGBA = root.caretRGBA,
            errorCaretRGBA = root.errorCaretRGBA,
            selectionHighlightRGBA = root.selectionHighlightRGBA,
        }
        root.text.rgba = 0
        root.text.isShadowed = false
        root.emptyTextRGBA = 0
        root.caretRGBA = 0
        root.errorCaretRGBA = 0
        root.selectionHighlightRGBA = 0
    elseif appearance then
        root.text.rgba = appearance.textRGBA
        root.text.isShadowed = appearance.isShadowed
        root.emptyTextRGBA = appearance.emptyTextRGBA
        root.caretRGBA = appearance.caretRGBA
        root.errorCaretRGBA = appearance.errorCaretRGBA
        root.selectionHighlightRGBA = appearance.selectionHighlightRGBA
        self._unclippedAppearance = nil
    end
end

function TextField:SetTooltip(value)
    return Tooltip.set(self, value)
end

function TextField:Destroy()
    if self._scrollController then
        self._scrollController:UnregisterClipTarget(self)
        self._scrollController = nil
    end
    self._unclippedAppearance = nil
    Tooltip.unbind(self)
    if self.root then
        if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.root:Destroy() end
        self.root = nil
    end
end

return TextField
