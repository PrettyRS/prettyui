local clamp = require("src/core/math").clamp
local hsvToRgb = require("src/core/colour").hsvToRgb
local FancyButton = require("src/fancy_button")
local InterfaceMouse = require("src/core/mouse")
local SimpleButton = require("src/simple_button")
local Sprites = require("src/core/sprites")
local Tooltip = require("src/tooltip")

local ColourPicker = {}
ColourPicker.__index = ColourPicker

local BUTTON_SIZE = 24
local SWATCH_PROPORTION = 0.65
local DEFAULT_COLOUR = 0xFFFFFFFF
local WINDOW_WIDTH = 220
local WINDOW_HEIGHT = 312
local POPUP_GAP = 6
local FIELD_SIZE = 128
local FIELD_X = 16
local FIELD_Y = 12
local HUE_WIDTH = 24
local HUE_X = 156
local HUE_Y = FIELD_Y
local ALPHA_WIDTH = FIELD_SIZE
local ALPHA_HEIGHT = 24
local ALPHA_X = FIELD_X
local ALPHA_Y = FIELD_Y + FIELD_SIZE + 12
local ALPHA_LAYOUT_OFFSET = ALPHA_HEIGHT + 12
local ALPHA_CHECKER_SIZE = 8
local PREVIEW_BUTTON_SIZE = 56
local PREVIEW_SWATCH_SIZE = math.floor(PREVIEW_BUTTON_SIZE * SWATCH_PROPORTION)
local PREVIEW_X = 16
local PREVIEW_Y = 152
local HEX_X = PREVIEW_X + PREVIEW_BUTTON_SIZE + 8
local HEX_Y = PREVIEW_Y + 24
local ACCEPT_Y = 224
local MARKER_SIZE = 9
local WHITE = 0xFFFFFFFF
local BLACK = 0x000000FF
local FRAME_COLOUR = 0x716B61FF
local CHECKER_LIGHT = 0xA8A8A8FF
local CHECKER_DARK = 0x606060FF

local HUE_COLOURS = {
    0xFF0000FF,
    0xFF00FFFF,
    0x0000FFFF,
    0x00FFFFFF,
    0x00FF00FF,
    0xFFFF00FF,
    0xFF0000FF,
}

local function copyOptions(options)
    local copy = {}
    if type(options) == "table" then
        for key, value in pairs(options) do copy[key] = value end
    end
    return copy
end

local function normaliseColour(value)
    value = math.floor(tonumber(value) or DEFAULT_COLOUR)
    return math.tointeger(clamp(value, 0, 0xFFFFFFFF)) or DEFAULT_COLOUR
end

local function unpackColour(colour)
    colour = normaliseColour(colour)
    return math.floor(colour / 0x1000000) % 0x100 / 255,
        math.floor(colour / 0x10000) % 0x100 / 255,
        math.floor(colour / 0x100) % 0x100 / 255,
        colour % 0x100
end

local function packColour(red, green, blue, alpha)
    local r = math.floor(clamp(red, 0, 1) * 255 + 0.5)
    local g = math.floor(clamp(green, 0, 1) * 255 + 0.5)
    local b = math.floor(clamp(blue, 0, 1) * 255 + 0.5)
    local a = clamp(math.floor(alpha or 255), 0, 255)
    return math.tointeger(r * 0x1000000 + g * 0x10000 + b * 0x100 + a)
end

local function rgbToHsv(red, green, blue)
    local maximum = math.max(red, green, blue)
    local minimum = math.min(red, green, blue)
    local delta = maximum - minimum
    local hue = 0
    if delta > 0 then
        if maximum == red then
            hue = ((green - blue) / delta) % 6
        elseif maximum == green then
            hue = (blue - red) / delta + 2
        else
            hue = (red - green) / delta + 4
        end
        hue = hue / 6
    end
    local saturation = maximum == 0 and 0 or delta / maximum
    return hue, saturation, maximum
end

local function hsvColour(hue, saturation, value, alpha)
    local red, green, blue = hsvToRgb(hue, saturation, value)
    return packColour(red, green, blue, alpha)
end

local function rectangle(parent, x, y, width, height, colour, fill)
    local component = ui.Rectangle.new(parent)
    component:SetPos(x, y)
    component:SetSize(width, height)
    component.fill = fill ~= false
    component.rgba = colour
    component.clickthrough = true
    return component
end

function ColourPicker.getSize(options)
    options = options or {}
    local size = options.buttonSize or options.size or BUTTON_SIZE
    return options.width or size, options.height or size
end

function ColourPicker.new(parent, options)
    options = options or {}
    local self = setmetatable({}, ColourPicker)
    self.parent = parent
    self.options = copyOptions(options)
    self.onChange = options.onChange
    self.disabled = options.disabled == true
    self.alphaSlider = options.alphaSlider == true or options.showAlpha == true
    self.colour = normaliseColour(
        options.value or options.colour or options.defaultColour
    )
    self.value = self.colour
    local context = Tooltip.getContext(parent)
    self.windowParent = options.windowParent or options.overlayParent or
        (context and context.parent) or parent
    if options.windowParent == nil and options.overlayParent == nil then
        while self.windowParent.parent ~= nil do
            self.windowParent = self.windowParent.parent
        end
    end

    local buttonOptions = copyOptions(options)
    local width, height = ColourPicker.getSize(options)
    buttonOptions.width = width
    buttonOptions.height = height
    buttonOptions.size = nil
    buttonOptions.buttonSize = nil
    self.button = SimpleButton.new(parent, Sprites.CLOSE, function()
        self:Open()
    end, buttonOptions)
    self.root = self.button.root

    if self.button.content then self.button.content:Destroy() end
    local swatchSize = clamp(
        math.floor(math.min(width, height) * SWATCH_PROPORTION),
        2,
        math.min(width, height) - 6
    )
    local swatchX = math.floor((width - swatchSize) / 2)
    local swatchY = math.floor((height - swatchSize) / 2)
    self.swatchFrame = rectangle(
        self.root, swatchX - 1, swatchY - 1, swatchSize + 2, swatchSize + 2, BLACK
    )
    self.swatch = rectangle(
        self.root, swatchX, swatchY, swatchSize, swatchSize, self.colour
    )
    self.button.content = self.swatch
    self:SetDisabled(self.disabled)
    return self
end

function ColourPicker:_PickerWindowBounds()
    local minimumHeight = WINDOW_HEIGHT +
        (self.alphaSlider and ALPHA_LAYOUT_OFFSET or 0)
    local width = math.max(
        WINDOW_WIDTH,
        math.floor(self.options.windowWidth or WINDOW_WIDTH)
    )
    local height = math.max(
        minimumHeight,
        math.floor(self.options.windowHeight or minimumHeight)
    )
    local x = self.options.windowX or self.options.pickerX
    local y = self.options.windowY or self.options.pickerY
    if x == nil or y == nil then
        local context = Tooltip.getContext(self.parent)
        local swatchX, swatchY
        if context and context.active ~= false and context.position then
            swatchX, swatchY = context.position(self.root)
            if context.parent ~= self.windowParent then
                local contextPosition = context.parent.xyGlobal
                local parentPosition = self.windowParent.xyGlobal
                swatchX = swatchX + contextPosition.x - parentPosition.x
                swatchY = swatchY + contextPosition.y - parentPosition.y
            end
        else
            local swatchPosition = self.root.xyGlobal
            local parentPosition = self.windowParent.xyGlobal
            swatchX = swatchPosition.x - parentPosition.x
            swatchY = swatchPosition.y - parentPosition.y
        end
        if x == nil then
            x = clamp(swatchX, 0, math.max(0, self.windowParent.width - width))
        end
        if y == nil then
            y = swatchY + self.root.height + POPUP_GAP
            if y + height > self.windowParent.height then
                y = swatchY - height - POPUP_GAP
            end
            y = clamp(y, 0, math.max(0, self.windowParent.height - height))
        end
    end
    return x, y, width, height
end

function ColourPicker:_PickerYOffset()
    return self.alphaSlider and ALPHA_LAYOUT_OFFSET or 0
end

function ColourPicker:_DrawHueSpectrum()
    self.hueCanvas:Clear()
    for index = 1, #HUE_COLOURS - 1 do
        local top = math.floor((index - 1) * FIELD_SIZE / (#HUE_COLOURS - 1))
        local bottom = math.floor(index * FIELD_SIZE / (#HUE_COLOURS - 1))
        self.hueCanvas:AddGradientV(
            0, top, HUE_WIDTH, bottom - top,
            HUE_COLOURS[index], HUE_COLOURS[index + 1]
        )
    end
end

function ColourPicker:_DrawColourField()
    self.fieldCanvas:Clear()
    for x = 0, FIELD_SIZE - 1 do
        local value = x / (FIELD_SIZE - 1)
        self.fieldCanvas:AddGradientV(
            x, 0, 1, FIELD_SIZE,
            hsvColour(self.pendingHue, 1, value, 255),
            hsvColour(self.pendingHue, 0, value, 255)
        )
    end
end

function ColourPicker:_DrawAlphaCheckerboard()
    if self.alphaCheckerCanvas == nil then return end
    self.alphaCheckerCanvas:Clear()
    for y = 0, ALPHA_HEIGHT - 1, ALPHA_CHECKER_SIZE do
        for x = 0, ALPHA_WIDTH - 1, ALPHA_CHECKER_SIZE do
            local light = (math.floor(x / ALPHA_CHECKER_SIZE) +
                math.floor(y / ALPHA_CHECKER_SIZE)) % 2 == 0
            self.alphaCheckerCanvas:AddRectangle(
                x,
                y,
                math.min(ALPHA_CHECKER_SIZE, ALPHA_WIDTH - x),
                math.min(ALPHA_CHECKER_SIZE, ALPHA_HEIGHT - y),
                light and CHECKER_LIGHT or CHECKER_DARK
            )
        end
    end
end

function ColourPicker:_DrawAlphaSpectrum()
    if self.alphaCanvas == nil then return end
    self.alphaCanvas:Clear()
    local red, green, blue = hsvToRgb(
        self.pendingHue, self.pendingSaturation, self.pendingValue
    )
    self.alphaCanvas:AddGradientH(
        0,
        0,
        ALPHA_WIDTH,
        ALPHA_HEIGHT,
        packColour(red, green, blue, 0),
        packColour(red, green, blue, 255)
    )
end

function ColourPicker:_UpdatePickerVisuals(redrawField, syncHexField)
    self.pendingColour = hsvColour(
        self.pendingHue, self.pendingSaturation, self.pendingValue, self.pendingAlpha
    )
    if redrawField then self:_DrawColourField() end

    local fieldMarkerX = math.floor(self.pendingValue * (FIELD_SIZE - 1) + 0.5)
    local fieldMarkerY = math.floor(
        (1 - self.pendingSaturation) * (FIELD_SIZE - 1) + 0.5
    )
    self.fieldMarkerHorizontal:SetPos(
        FIELD_X + fieldMarkerX - math.floor(MARKER_SIZE / 2),
        FIELD_Y + fieldMarkerY
    )
    self.fieldMarkerVertical:SetPos(
        FIELD_X + fieldMarkerX,
        FIELD_Y + fieldMarkerY - math.floor(MARKER_SIZE / 2)
    )

    local hueY = math.floor((1 - self.pendingHue) * (FIELD_SIZE - 1) + 0.5)
    self.hueMarkerShadow:SetY(HUE_Y + hueY - 2)
    self.hueMarker:SetY(HUE_Y + hueY - 1)
    if self.alphaSlider then
        self:_DrawAlphaSpectrum()
        local alphaX = math.floor(
            self.pendingAlpha / 255 * (ALPHA_WIDTH - 1) + 0.5
        )
        self.alphaMarkerShadow:SetX(ALPHA_X + alphaX - 2)
        self.alphaMarker:SetX(ALPHA_X + alphaX - 1)
    end
    self.preview.rgba = self.pendingColour
    if syncHexField ~= false then
        self.hexField:SetText(self.alphaSlider
            and string.format("#%08X", self.pendingColour)
            or string.format("#%06X", math.floor(self.pendingColour / 0x100)))
        self.acceptButton:SetDisabled(false)
    end
end

function ColourPicker:_SetPendingColour(colour, syncHexField)
    local red, green, blue, alpha = unpackColour(colour)
    self.pendingHue, self.pendingSaturation, self.pendingValue =
        rgbToHsv(red, green, blue)
    self.pendingAlpha = alpha
    self:_UpdatePickerVisuals(true, syncHexField)
end

function ColourPicker:_PickerContentPosition()
    return (self.pickerWindow.root.x or 0) + (self.pickerWindow.content.x or 0),
        (self.pickerWindow.root.y or 0) + (self.pickerWindow.content.y or 0)
end

function ColourPicker:_PickerLocalMousePosition(layer, x, y)
    local mouse = InterfaceMouse.GetPosition(layer, x, y)
    if mouse == nil then return nil, nil end
    if layer ~= nil and x ~= nil and y ~= nil then return mouse.x, mouse.y end
    local contentX, contentY = self:_PickerContentPosition()
    return mouse.x - contentX, mouse.y - contentY
end

function ColourPicker:_UpdateFieldFromMouse(layer, x, y)
    local mouseX, mouseY = self:_PickerLocalMousePosition(layer, x, y)
    if mouseX == nil then return false end
    self.pendingValue = clamp(
        (mouseX - FIELD_X) / (FIELD_SIZE - 1), 0, 1
    )
    self.pendingSaturation = 1 - clamp(
        (mouseY - FIELD_Y) / (FIELD_SIZE - 1), 0, 1
    )
    self:_UpdatePickerVisuals(false)
    return false
end

function ColourPicker:_UpdateHueFromMouse(layer, x, y)
    local _, mouseY = self:_PickerLocalMousePosition(layer, x, y)
    if mouseY == nil then return false end
    local ratio = clamp((mouseY - HUE_Y) / (FIELD_SIZE - 1), 0, 1)
    local hue = 1 - ratio
    local changed = hue ~= self.pendingHue
    self.pendingHue = hue
    self:_UpdatePickerVisuals(changed)
    return false
end

function ColourPicker:_UpdateAlphaFromMouse(layer, x, y)
    local mouseX = self:_PickerLocalMousePosition(layer, x, y)
    if mouseX == nil then return false end
    local ratio = clamp(
        (mouseX - ALPHA_X) / (ALPHA_WIDTH - 1), 0, 1
    )
    self.pendingAlpha = math.floor(ratio * 255 + 0.5)
    self:_UpdatePickerVisuals(false)
    return false
end

function ColourPicker:_BeginPickerDrag(kind, layer, x, y)
    self.dragTarget = kind
    self.dragCaptureExpanded = false
    layer = layer or (kind == "hue" and self.hueHit) or
        (kind == "alpha" and self.alphaHit) or self.fieldHit
    InterfaceMouse.BeginCapture(layer)
    if kind == "hue" then
        self:_UpdateHueFromMouse(layer, x, y)
    elseif kind == "alpha" then
        self:_UpdateAlphaFromMouse(layer, x, y)
    else
        self:_UpdateFieldFromMouse(layer, x, y)
    end
    return false
end

function ColourPicker:_UpdatePickerDrag(kind, layer, x, y, expandCapture)
    if self.dragTarget ~= kind then return false end
    if kind == "hue" then
        self:_UpdateHueFromMouse(layer, x, y)
    elseif kind == "alpha" then
        self:_UpdateAlphaFromMouse(layer, x, y)
    else
        self:_UpdateFieldFromMouse(layer, x, y)
    end
    if expandCapture ~= false and not self.dragCaptureExpanded then
        self.dragCaptureExpanded = true
        layer:SetPos(0, 0)
        layer:SetSize(0, 0, 1.0, 1.0)
        layer:MoveToFront()
    end
    return false
end

function ColourPicker:_StopPickerDrag(kind, layer, x, y)
    if self.dragTarget == kind then
        self:_UpdatePickerDrag(kind, layer, x, y, false)
        self.dragTarget = nil
    end
    self.dragCaptureExpanded = false
    InterfaceMouse.EndCapture(layer)
    self.fieldHit:SetPos(FIELD_X, FIELD_Y)
    self.fieldHit:SetSize(FIELD_SIZE, FIELD_SIZE)
    self.hueHit:SetPos(HUE_X, HUE_Y)
    self.hueHit:SetSize(HUE_WIDTH, FIELD_SIZE)
    if self.alphaHit then
        self.alphaHit:SetPos(ALPHA_X, ALPHA_Y)
        self.alphaHit:SetSize(ALPHA_WIDTH, ALPHA_HEIGHT)
    end
    return false
end

function ColourPicker:_BindPickerDrag(layer, kind)
    layer:Subscribe(ui.Hook.ONCLICK, function(component, x, y)
        return self:_BeginPickerDrag(kind, component, x, y)
    end)
    layer:Subscribe(ui.Hook.ONHOLD, function(component, x, y)
        return self:_UpdatePickerDrag(kind, component, x, y)
    end)
    layer:Subscribe(ui.Hook.ONDRAG, function(component, x, y)
        return self:_UpdatePickerDrag(kind, component, x, y)
    end)
    layer:Subscribe(ui.Hook.ONRELEASE, function(component, x, y)
        return self:_StopPickerDrag(kind, component, x, y)
    end)
    layer:Subscribe(ui.Hook.ONDRAGCOMPLETE, function(component, _, x, y)
        return self:_StopPickerDrag(kind, component, x, y)
    end)
end

function ColourPicker:_ClearPickerReferences()
    self.dragTarget = nil
    self.dragCaptureExpanded = false
    self.pickerWindow = nil
    self.fieldCanvas = nil
    self.hueCanvas = nil
    self.alphaCheckerCanvas = nil
    self.alphaCanvas = nil
    self.fieldHit = nil
    self.hueHit = nil
    self.alphaHit = nil
    self.fieldMarkerHorizontal = nil
    self.fieldMarkerVertical = nil
    self.hueMarkerShadow = nil
    self.hueMarker = nil
    self.alphaMarkerShadow = nil
    self.alphaMarker = nil
    self.previewButton = nil
    self.preview = nil
    self.hexField = nil
    self.acceptButton = nil
end

function ColourPicker:Open()
    if self.disabled then return false end
    if self.pickerWindow and self.pickerWindow.root then
        self.pickerWindow:Show()
        return true
    end

    local Window = require("src/window")
    local pickerX, pickerY, pickerWidth, pickerHeight = self:_PickerWindowBounds()
    local pickerYOffset = self:_PickerYOffset()
    local picker
    picker = Window.new(self.windowParent, {
        title = self.options.windowTitle or self.options.title or "Colour picker",
        x = pickerX,
        y = pickerY,
        width = pickerWidth,
        height = pickerHeight,
        minWidth = WINDOW_WIDTH,
        minHeight = WINDOW_HEIGHT + pickerYOffset,
        destroyOnClose = true,
        onClose = function()
            if self.pickerWindow == picker then self:_ClearPickerReferences() end
        end,
    })
    self.pickerWindow = picker

    self.fieldCanvas = ui.Canvas.new(picker.content)
    self.fieldCanvas:SetPos(FIELD_X, FIELD_Y)
    self.fieldCanvas:SetSize(FIELD_SIZE, FIELD_SIZE)
    self.fieldCanvas.clickthrough = true

    self.hueCanvas = ui.Canvas.new(picker.content)
    self.hueCanvas:SetPos(HUE_X, HUE_Y)
    self.hueCanvas:SetSize(HUE_WIDTH, FIELD_SIZE)
    self.hueCanvas.clickthrough = true
    self:_DrawHueSpectrum()

    if self.alphaSlider then
        self.alphaCheckerCanvas = ui.Canvas.new(picker.content)
        self.alphaCheckerCanvas:SetPos(ALPHA_X, ALPHA_Y)
        self.alphaCheckerCanvas:SetSize(ALPHA_WIDTH, ALPHA_HEIGHT)
        self.alphaCheckerCanvas.clickthrough = true
        self:_DrawAlphaCheckerboard()

        self.alphaCanvas = ui.Canvas.new(picker.content)
        self.alphaCanvas:SetPos(ALPHA_X, ALPHA_Y)
        self.alphaCanvas:SetSize(ALPHA_WIDTH, ALPHA_HEIGHT)
        self.alphaCanvas.clickthrough = true
    end

    rectangle(
        picker.content, FIELD_X, FIELD_Y, FIELD_SIZE, FIELD_SIZE, FRAME_COLOUR, false
    )
    rectangle(
        picker.content, HUE_X, HUE_Y, HUE_WIDTH, FIELD_SIZE, FRAME_COLOUR, false
    )
    if self.alphaSlider then
        rectangle(
            picker.content,
            ALPHA_X,
            ALPHA_Y,
            ALPHA_WIDTH,
            ALPHA_HEIGHT,
            FRAME_COLOUR,
            false
        )
    end

    self.fieldMarkerHorizontal = rectangle(
        picker.content, FIELD_X, FIELD_Y, MARKER_SIZE, 1, WHITE
    )
    self.fieldMarkerVertical = rectangle(
        picker.content, FIELD_X, FIELD_Y, 1, MARKER_SIZE, WHITE
    )
    self.hueMarkerShadow = rectangle(
        picker.content, HUE_X - 3, HUE_Y, HUE_WIDTH + 6, 4, BLACK
    )
    self.hueMarker = rectangle(
        picker.content, HUE_X - 3, HUE_Y, HUE_WIDTH + 6, 2, WHITE
    )
    if self.alphaSlider then
        self.alphaMarkerShadow = rectangle(
            picker.content, ALPHA_X, ALPHA_Y - 3, 4, ALPHA_HEIGHT + 6, BLACK
        )
        self.alphaMarker = rectangle(
            picker.content, ALPHA_X, ALPHA_Y - 3, 2, ALPHA_HEIGHT + 6, WHITE
        )
    end

    self.previewButton = picker:AddSimpleButton(
        Sprites.CLOSE,
        nil,
        {
            absolute = true,
            x = PREVIEW_X,
            y = PREVIEW_Y + pickerYOffset,
            width = PREVIEW_BUTTON_SIZE,
            height = PREVIEW_BUTTON_SIZE,
        }
    )
    if self.previewButton.content then self.previewButton.content:Destroy() end
    local previewInset = math.floor((PREVIEW_BUTTON_SIZE - PREVIEW_SWATCH_SIZE) / 2)
    self.preview = rectangle(
        self.previewButton.root,
        previewInset,
        previewInset,
        PREVIEW_SWATCH_SIZE,
        PREVIEW_SWATCH_SIZE,
        self.colour
    )
    self.previewButton.content = self.preview
    self.previewButton:SetHoverCursor(nil)
    self.previewButton.root:Unsubscribe(ui.Hook.ONMOUSEOVER)
    self.previewButton.root:Unsubscribe(ui.Hook.ONMOUSELEAVE)
    self.previewButton.root:Unsubscribe(ui.Hook.ONCLICK)
    self.previewButton.root:Unsubscribe(ui.Hook.ONRELEASE)
    self.previewButton.root.clickthrough = true

    picker:AddText({
        text = "Hex code",
        absolute = true,
        x = HEX_X,
        y = PREVIEW_Y + pickerYOffset,
        width = 100,
        height = 24,
    })

    self.hexField = picker:AddTextField({
        absolute = true,
        x = HEX_X,
        y = HEX_Y + pickerYOffset,
        width = 100,
        height = 30,
        maxLength = self.alphaSlider and 9 or 7,
        placeholder = self.alphaSlider and "#RRGGBBAA" or "#RRGGBB",
        onChange = function(_, _, content)
            local hex = content:match("^#?(%x+)$")
            local colour = hex and tonumber(hex, 16)
            if colour then
                if #hex == 6 then
                    colour = colour * 0x100 + self.pendingAlpha
                elseif #hex ~= 8 or not self.alphaSlider then
                    colour = nil
                end
            end
            self.acceptButton:SetDisabled(colour == nil)
            if colour then self:_SetPendingColour(colour, false) end
        end,
        onSubmit = function()
            if not self.acceptButton.disabled then self:_UpdatePickerVisuals(false) end
        end,
    })

    self.fieldHit = ui.Layer.new(picker.content)
    self.fieldHit:SetPos(FIELD_X, FIELD_Y)
    self.fieldHit:SetSize(FIELD_SIZE, FIELD_SIZE)
    self.fieldHit.clickthrough = false
    self.hueHit = ui.Layer.new(picker.content)
    self.hueHit:SetPos(HUE_X, HUE_Y)
    self.hueHit:SetSize(HUE_WIDTH, FIELD_SIZE)
    self.hueHit.clickthrough = false
    if self.alphaSlider then
        self.alphaHit = ui.Layer.new(picker.content)
        self.alphaHit:SetPos(ALPHA_X, ALPHA_Y)
        self.alphaHit:SetSize(ALPHA_WIDTH, ALPHA_HEIGHT)
        self.alphaHit.clickthrough = false
    end
    self:_BindPickerDrag(self.fieldHit, "field")
    self:_BindPickerDrag(self.hueHit, "hue")
    if self.alphaHit then self:_BindPickerDrag(self.alphaHit, "alpha") end

    local acceptText = self.options.acceptText or "Accept"
    local acceptWidth = FancyButton.getSize(acceptText, {
        width = self.options.acceptWidth or 126,
    })
    self.acceptButton = picker:AddFancyButton(acceptText, function()
        self:SetValue(self.pendingColour)
        if self.pickerWindow == picker then picker:Close() end
    end, {
        absolute = true,
        x = math.floor((picker.content.width - acceptWidth) / 2),
        y = ACCEPT_Y + pickerYOffset,
        width = acceptWidth,
        variant = self.options.acceptVariant or "positive",
    })

    self:_SetPendingColour(self.colour)
    self.fieldHit:MoveToFront()
    self.hueHit:MoveToFront()
    if self.alphaHit then self.alphaHit:MoveToFront() end
    return true
end

function ColourPicker:GetValue()
    return self.colour
end

function ColourPicker:SetValue(colour, notify)
    colour = normaliseColour(colour)
    local changed = colour ~= self.colour
    self.colour = colour
    self.value = colour
    if self.swatch then
        self.swatch.rgba = colour
        self.swatch:MoveToFront()
    end
    if self.pickerWindow and self.pickerWindow.root then self:_SetPendingColour(colour) end
    if changed and notify ~= false and self.onChange then self.onChange(self, colour) end
    return changed
end

ColourPicker.GetColour = ColourPicker.GetValue
ColourPicker.SetColour = ColourPicker.SetValue

function ColourPicker:SetDisabled(disabled)
    self.disabled = disabled == true
    self.button:SetDisabled(self.disabled)
end

function ColourPicker:Close()
    if self.pickerWindow then self.pickerWindow:Close() end
end

function ColourPicker:Destroy()
    if self.pickerWindow then
        self.pickerWindow:Destroy()
        self:_ClearPickerReferences()
    end
    if self.button then
        self.button:Destroy()
        self.button = nil
    end
    self.root = nil
    self.parent = nil
    self.windowParent = nil
    self.onChange = nil
end

return ColourPicker
