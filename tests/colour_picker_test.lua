local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local mousePosition

local function component(parent, kind, categoryID, dynamicID)
    local result = {
        parent = parent,
        kind = kind,
        hidden = false,
        x = 0,
        y = 0,
        width = 0,
        height = 0,
        subscriptions = {},
    }
    function result:SetPos(x, y)
        self.x, self.y = x, y
    end
    function result:SetSize(width, height)
        self.width, self.height = width, height
    end
    function result:SetX(x) self.x = x end
    function result:SetY(y) self.y = y end
    function result:Subscribe(hook, callback)
        self.subscriptions[hook] = callback
    end
    function result:Unsubscribe(hook)
        self.subscriptions[hook] = nil
    end
    function result:MoveToFront() self.movedToFront = true end
    setmetatable(result, {
        __index = function(self, key)
            if key == "xyGlobal" then
                local origin = self.parent and self.parent.xyGlobal or { x = 0, y = 0 }
                return { x = origin.x + self.x, y = origin.y + self.y }
            end
            if key == "visibleGlobal" then
                return not self.hidden and (not self.parent or self.parent.visibleGlobal)
            end
        end,
    })
    function result:Destroy() self.destroyed = true end
    if parent then
        parent.children = parent.children or {}
        table.insert(parent.children, result)
    end
    return Interfaces.component(result, parent, categoryID, dynamicID)
end

local function canvas(parent, categoryID, dynamicID)
    local result = component(parent, "canvas", categoryID, dynamicID)
    result.rectangles = {}
    function result:Clear()
        self.rectangles = {}
        self.horizontalGradient = nil
        self.verticalGradients = {}
    end
    function result:AddRectangle(x, y, width, height, colour)
        table.insert(self.rectangles, {
            x = x, y = y, width = width, height = height, colour = colour,
        })
    end
    function result:AddGradientH(x, y, width, height, startColour, endColour)
        self.horizontalGradient = {
            x = x, y = y, width = width, height = height,
            startColour = startColour, endColour = endColour,
        }
    end
    function result:AddGradientV(x, y, width, height, startColour, endColour)
        table.insert(self.verticalGradients, {
            x = x, y = y, width = width, height = height,
            startColour = startColour, endColour = endColour,
        })
    end
    return result
end

local function simpleButton(parent, options, action)
    local root = require("src/core/components").new(ui.Layer, parent, options)
    root.kind = "button"
    root:SetPos(options and options.x or 0, options and options.y or 0)
    root:SetSize(options and options.width or 24, options and options.height or 24)
    local content = component(root, "button-content")
    return {
        root = root,
        content = content,
        action = action,
        SetDisabled = function(self, disabled) self.disabled = disabled end,
        SetHoverCursor = function() end,
        Destroy = function(self) self.root:Destroy() end,
    }
end

ui = {
    Rectangle = { new = function(parent, categoryID, dynamicID)
        return component(parent, "rectangle", categoryID, dynamicID)
    end },
    Canvas = { new = canvas },
    Layer = { new = function(parent, categoryID, dynamicID)
        return component(parent, "layer", categoryID, dynamicID)
    end },
    InputField = { new = function(parent, categoryID, dynamicID)
        local field = component(parent, "input", categoryID, dynamicID)
        field.text = {}
        field.containerSprite = {}
        function field:Setup(_, _, maxLength) self.maxLength = maxLength end
        return field
    end },
    Margin = { new = function(left, top, right, bottom)
        return { left = left, top = top, right = right, bottom = bottom }
    end },
    AlignMode = { CENTRE = 1, TOPLEFT = 2 },
    TextContentVisibilityMode = { VISIBLE = 1 },
    InputFieldFilterMode = { NONE = 1 },
    InputFieldKeyHandlingMode = { DEFAULT = 1 },
    InputFieldActionResult = {
        CONTENT_CHANGE = 1, SUBMIT = 2, SUBMIT_ON_ESCAPE = 3, SUBMIT_ON_FOCUS_LOSS = 4,
    },
    Hook = {
        ONCLICK = 1,
        ONHOLD = 2,
        ONDRAG = 3,
        ONRELEASE = 4,
        ONDRAGCOMPLETE = 5,
        ONMOUSEOVER = 6,
        ONMOUSELEAVE = 7,
        ONCONTENTCHANGED = 8,
    },
}

id = {
    StyleSheet = { INPUT_DEFAULT = 1 },
    Font = { MUSEO_SANS_15PT_REGULAR = 1 },
}
config = { Font = { MUSEO_SANS_15PT_REGULAR = {
    GetStringWidth = function(_, text)
        local width = 0
        for character in text:gmatch(".") do
            width = width + (character == "1" and 5 or 8)
        end
        return width
    end,
} } }
package.loaded["src/core/wheel"] = { bind = function() end }

package.loaded["src/fancy_button"] = {
    getSize = function(_, options) return options.width end,
}
local mouseCaptureOrigins = {}
package.loaded["src/core/mouse"] = {
    GetPosition = function(component, x, y)
        if component and x ~= nil and y ~= nil then
            local origin = mouseCaptureOrigins[component] or component
            return { x = origin.x + x, y = origin.y + y }
        end
        return mousePosition
    end,
    BeginCapture = function(component)
        mouseCaptureOrigins[component] = { x = component.x, y = component.y }
    end,
    EndCapture = function(component)
        mouseCaptureOrigins[component] = nil
    end,
}
package.loaded["src/simple_button"] = {
    new = function(parent, _, action, options) return simpleButton(parent, options, action) end,
}
package.loaded["src/core/sprites"] = { CLOSE = 1 }
local contexts = {}
package.loaded["src/tooltip"] = {
    getContext = function(parent) return contexts[parent] end,
    bind = function() end,
}
package.loaded["src/window"] = {
    new = function(parent, options)
        local root = require("src/core/components").new(ui.Layer, parent, options)
        root.kind = "window"
        root:SetPos(options.x, options.y)
        root:SetSize(options.width, options.height)
        local content = component(root, "window-content")
        content:SetPos(8, 32)
        content:SetSize(options.width - 16, options.height - 40)
        local window = {
            root = root,
            content = content,
            AddSimpleButton = function(_, _, _, buttonOptions)
                return simpleButton(content, buttonOptions)
            end,
            AddTextField = function(_, fieldOptions)
                return require("src/text_field").new(content, fieldOptions)
            end,
            AddFancyButton = function(_, _, action, buttonOptions)
                local button = simpleButton(content, buttonOptions)
                button.action = action
                return button
            end,
            Show = function() end,
            Close = function(self)
                if options.onClose then options.onClose() end
                self:Destroy()
            end,
            Destroy = function(self) self.root:Destroy() end,
        }
        return window
    end,
}

package.loaded["src/colour_picker"] = nil
local ColourPicker = require("src/colour_picker")
local parent = component(nil, "parent")

local standard = ColourPicker.new(parent, { value = 0x33669980 })
expect(standard:Open(), true, "a standard picker opens")
expect(standard.alphaCanvas, nil, "the alpha slider is opt-in")

mousePosition = { x = 1000, y = 1000 }
standard.fieldHit.subscriptions[ui.Hook.ONCLICK](standard.fieldHit, 63, 63)
expect(
    standard.fieldMarkerVertical.x,
    79,
    "the field marker uses the hook's component-local x coordinate"
)
expect(
    standard.fieldMarkerHorizontal.y,
    75,
    "the field marker uses the hook's component-local y coordinate"
)
standard.fieldHit.subscriptions[ui.Hook.ONRELEASE](standard.fieldHit, 63, 63)

local accepted
local picker = ColourPicker.new(parent, {
    value = 0x33669980,
    alphaSlider = true,
    onChange = function(_, colour) accepted = colour end,
})
expect(picker:Open(), true, "an alpha picker opens")
expect(picker.alphaCanvas.x, 16, "the alpha bar aligns with the palette")
expect(picker.alphaCanvas.y, 152, "the alpha bar sits below the palette")
expect(picker.alphaCanvas.width, 128, "the alpha bar matches the palette width")
expect(picker.alphaCanvas.height, 24, "the alpha bar matches the hue bar thickness")
expect(#picker.alphaCheckerCanvas.rectangles, 48, "the alpha bar draws a checkerboard")
expect(
    picker.alphaCanvas.horizontalGradient.startColour,
    0x33669900,
    "the alpha gradient starts transparent"
)
expect(
    picker.alphaCanvas.horizontalGradient.endColour,
    0x336699FF,
    "the alpha gradient ends opaque"
)
expect(picker.alphaMarker.x, 79, "the alpha marker reflects the initial alpha")

local contentX = picker.pickerWindow.root.x + picker.pickerWindow.content.x
mousePosition = { x = contentX, y = 0 }
picker.alphaHit.subscriptions[ui.Hook.ONCLICK](picker.alphaHit, 127, 12)
expect(picker.dragTarget, "alpha", "pressing the alpha bar begins an alpha drag")
expect(picker.alphaHit.width, 128, "the hit area remains stable on the initial click")
picker.alphaHit.subscriptions[ui.Hook.ONHOLD](picker.alphaHit, 127, 12)
expect(picker.alphaHit.width, 0, "the drag target expands across the picker")
expect(picker.pendingColour, 0x336699FF, "the right edge selects full opacity")

picker.alphaHit.subscriptions[ui.Hook.ONRELEASE](picker.alphaHit, 0, 12)
expect(picker.dragTarget, nil, "releasing the alpha bar ends the drag")
expect(picker.alphaHit.x, 16, "the alpha hit area returns to the bar")
expect(picker.alphaHit.width, 128, "the alpha hit area restores its width")
expect(picker.pendingColour, 0x33669900, "the left edge selects full transparency")

picker.acceptButton.action()
expect(accepted, 0x33669900, "accepting reports the selected alpha")

local screen = component(nil, "screen")
screen:SetPos(12, 18)
screen:SetSize(1280, 720)
local settingsLayer = component(screen, "settings")
settingsLayer:SetPos(100, 60)
settingsLayer:SetSize(590, 357)
local contentLayer = component(settingsLayer, "content")
contentLayer:SetPos(14, 120)
contentLayer:SetSize(540, 210)
local ownerRoot = component(contentLayer, "owner-window")
ownerRoot:SetPos(25, 30)
ownerRoot:SetSize(400, 200)
local nestedContent = component(ownerRoot, "nested-content")
contexts[nestedContent] = {
    parent = contentLayer,
}
local scrollY = 0
contexts[nestedContent].position = function(target)
    return target.xyGlobal.x - contentLayer.xyGlobal.x,
        target.xyGlobal.y - contentLayer.xyGlobal.y - scrollY
end
local nested = ColourPicker.new(nestedContent, { alphaSlider = true })
nested:Open()
expect(nested.root.parent, nestedContent, "the swatch stays in its original layout")
expect(nested.pickerWindow.root.parent, screen, "the popup escapes both clipping layers")
expect(
    nested.pickerWindow.root.xyGlobal.x,
    nested.root.xyGlobal.x,
    "the popup aligns with the opening swatch across nested parents"
)
expect(
    nested.pickerWindow.root.xyGlobal.y,
    nested.root.xyGlobal.y + nested.root.height + 6,
    "the popup opens immediately below the swatch"
)

local scrolled = ColourPicker.new(nestedContent, { x = 32, y = 200 })
scrollY = 120
scrolled.button.action()
expect(
    scrolled.pickerWindow.root.xyGlobal.x,
    scrolled.root.xyGlobal.x,
    "a scrolled popup aligns horizontally with its clicked button"
)
expect(
    scrolled.pickerWindow.root.xyGlobal.y,
    scrolled.root.xyGlobal.y - scrollY + scrolled.root.height + 6,
    "a scrolled popup opens beside the button's visible position"
)

local direct = ColourPicker.new(contentLayer, {})
direct:Open()
expect(direct.pickerWindow.root.parent, screen, "native mounts escape without a tooltip context")

local explicit = ColourPicker.new(nestedContent, {
    windowParent = settingsLayer,
    overlayParent = screen,
    windowX = 7,
    windowY = 9,
})
explicit:Open()
expect(explicit.pickerWindow.root.parent, settingsLayer, "explicit window parent takes precedence")
expect(explicit.pickerWindow.root.x, 7, "explicit x stays relative to the selected parent")
expect(explicit.pickerWindow.root.y, 9, "explicit y stays relative to the selected parent")

local overlay = ColourPicker.new(nestedContent, { overlayParent = settingsLayer })
overlay:Open()
expect(overlay.pickerWindow.root.parent, settingsLayer, "explicit overlay parent is retained")
expect(
    overlay.pickerWindow.root.xyGlobal.x,
    overlay.root.xyGlobal.x,
    "explicit overlay coordinates still align with the swatch"
)

local edge = ColourPicker.new(screen, { x = 1240, y = 680, alphaSlider = true })
edge:Open()
local edgeRoot = edge.pickerWindow.root
expect(edgeRoot.x + edgeRoot.width, screen.width, "right-edge placement stays on screen")
expect(edgeRoot.y + edgeRoot.height + 6, edge.root.y, "bottom-edge placement flips above")

local partial = ColourPicker.new(screen, { x = 1240, y = 680, windowX = -5 })
partial:Open()
expect(partial.pickerWindow.root.x, -5, "explicit x is not clamped")
expect(
    partial.pickerWindow.root.y + partial.pickerWindow.root.height + 6,
    partial.root.y,
    "automatic y still flips when only x is overridden"
)

local smallScreen = component(nil, "small-screen")
smallScreen:SetSize(100, 100)
local oversized = ColourPicker.new(smallScreen, {})
oversized:Open()
expect(oversized.pickerWindow.root.x, 0, "oversized popup keeps its left edge reachable")
expect(oversized.pickerWindow.root.y, 0, "oversized popup keeps its title bar reachable")

local optionOwner = component(screen, "picker-option-owner")
local optedIn = ColourPicker.new(optionOwner, {
    categoryID = "auto", windowParent = screen,
})
expect(optedIn:Open(), true, "an opted-in picker still opens its detached window")
expect(optedIn.pickerWindow.root.parent, screen, "picker popup still uses its physical overlay host")
expect(optedIn.pickerWindow.root.categoryID, 0, "popup root inherits its static native host")
local Components = require("src/core/components")
expect(Components.new(ui.Layer, optedIn.pickerWindow.content).categoryID > 0, true,
    "detached popup descendants follow the picker's managed policy")
optedIn:Close()
expect(optedIn:Open(), true, "an opted-in picker reopens after closing")
expect(Components.new(ui.Layer, optedIn.pickerWindow.content).categoryID > 0, true,
    "a reopened popup retains its owner's auto mode")
optedIn:Close()

local autoScreenHost = Components.new(ui.Layer, screen, { categoryID = "auto" })
local legacyPicker = ColourPicker.new(optionOwner, { windowParent = autoScreenHost })
expect(legacyPicker:Open(), true, "a legacy picker opens on the shared physical host")
expect(Components.new(ui.Layer, legacyPicker.pickerWindow.content).categoryID, 0,
    "legacy popup descendants do not inherit an unrelated auto picker policy")
legacyPicker:Close()

local valueNotifications = 0
local raw = ColourPicker.new(screen, {
    value = 0x33669980,
    onChange = function() valueNotifications = valueNotifications + 1 end,
})
local function beginValue(picker)
    local root = picker.valueField.root
    root.subscriptions[ui.Hook.ONCLICK](root)
end
local function editValue(picker, text, reason)
    local root = picker.valueField.root
    root.content = text
    root.subscriptions[ui.Hook.ONCONTENTCHANGED](
        root, reason or ui.InputFieldActionResult.CONTENT_CHANGE, text)
end

local function expectCaptionAligned(picker)
    local field = picker.valueField.root
    local preview = picker.previewButton.root
    local textWidth = config.Font.MUSEO_SANS_15PT_REGULAR:GetStringWidth(
        picker.valueField:GetText(), false)
    local centre = preview.x + preview.width / 2
    expect(math.abs(field.x + field.contentMargin.left + textWidth / 2 - centre) <= 0.5,
        true, "raw value text shares the preview centre with proportional glyph widths")
    expect(math.abs(picker.valueUnderline.x + picker.valueUnderline.width / 2 - centre) <= 0.5,
        true, "the hover underline shares the preview centre")
    expect(picker.valueUnderline.width, textWidth, "the hover underline fits the text")
    expect(field.y - preview.y - preview.height,
        picker.acceptButton.root.y - field.y - field.height,
        "the value field has balanced gaps above and below")
end

raw:Open()
expect(raw.valueField:GetText(), "#33669980", "the caption shows the selected RGBA hex code")
expect(raw.valueField.root.containerSprite.rgba, 0, "the idle caption has no input chrome")
expect(raw.valueUnderline.hidden, true, "the idle caption has no underline")
local caption = raw.valueField.root
expectCaptionAligned(raw)
caption.subscriptions[ui.Hook.ONMOUSEOVER]()
expect(raw.valueUnderline.hidden, false, "hover underlines the editable caption")
caption.subscriptions[ui.Hook.ONMOUSELEAVE]()
expect(raw.valueUnderline.hidden, true, "leaving hides the underline")
beginValue(raw)
expect(raw.valueEditing, true, "clicking the caption begins editing")
expect(caption.containerSprite.rgba, 0xFFFFFFFF, "editing reveals the input chrome")
editValue(raw, "#aBcDeF40")
expect(raw.preview.rgba, 0xABCDEF40, "mixed-case hex edits update the preview")
expect(raw.pendingAlpha, 0x40, "packed-value edits synchronize opacity")
expect(raw.alphaCanvas, nil, "packed opacity also works without the optional alpha slider")
expect(raw.valueField:GetText(), "#aBcDeF40", "typing is not rewritten")
expect(raw:GetValue(), 0x33669980, "preview edits do not commit")
expect(valueNotifications, 0, "preview edits do not notify consumers")
editValue(raw, "#aBcDeF40", ui.InputFieldActionResult.SUBMIT)
expect(raw.valueEditing, false, "Enter returns to caption mode")
expect(raw.valueField:GetText(), "#ABCDEF40", "finishing uses uppercase RGBA hex notation")
expect(caption.containerSprite.rgba, 0, "finishing hides the input chrome")
expect(raw:GetValue(), 0x33669980, "Enter does not accept the colour")
-- Native input may retain keyboard focus after Enter.
editValue(raw, "112233")
expect(raw.valueEditing, true, "typing after Enter resumes editing")
expect(raw.preview.rgba, 0x11223340, "six-digit RGB preserves the pending alpha")
expectCaptionAligned(raw)
editValue(raw, "112233", ui.InputFieldActionResult.SUBMIT_ON_FOCUS_LOSS)
expect(raw.valueEditing, false, "focus loss returns to caption mode")
expect(raw.valueField:GetText(), "#11223340", "focus loss includes the preserved alpha byte")
beginValue(raw)
editValue(raw, "#99887766")
editValue(raw, "#99887766", ui.InputFieldActionResult.SUBMIT_ON_ESCAPE)
expect(raw.pendingColour, 0x11223340, "Escape restores the value from before this edit")
expect(raw.valueField:GetText(), "#11223340", "Escape restores the caption")
raw:Close()
expect(raw:GetValue(), 0x33669980, "closing cancels all provisional edits")
raw:Open()
expect(raw.valueField:GetText(), "#33669980", "reopening discards cancelled edits")
beginValue(raw)
editValue(raw, "#11223380")
raw.acceptButton.action()
expect(raw:GetValue(), 0x11223380, "Accept commits the exact packed value")
expect(valueNotifications, 1, "Accept notifies exactly once")
expect(raw.pickerWindow, nil, "Accept closes the picker")

raw:Open()
beginValue(raw)
for _, invalid in ipairs({
    "", "#", "#12345", "1122334", "GG112233", "0x112233", "#100000000",
}) do
    editValue(raw, invalid)
    expect(raw.acceptButton.disabled, true, "incomplete or invalid hex disables Accept")
    expect(raw.preview.rgba, 0x11223380, "invalid edits retain the last valid preview")
    raw.acceptButton.action()
    expect(raw.pickerWindow ~= nil, true, "invalid input cannot confirm a stale colour")
end
editValue(raw, "", ui.InputFieldActionResult.SUBMIT_ON_FOCUS_LOSS)
expect(raw.valueEditing, false, "focus loss exits incomplete input")
expect(raw.valueField:GetText(), "#11223380", "incomplete input restores the last valid value")
expect(raw.acceptButton.disabled, false, "discarding incomplete input restores Accept")
beginValue(raw)
editValue(raw, "00000000")
expect(raw.preview.rgba, 0, "fully transparent black remains a valid colour")
expect(raw.acceptButton.disabled, false, "valid input restores Accept")
raw.acceptButton.action()
expect(raw:GetValue(), 0, "Accept preserves all zero RGBA bytes")

raw:Open()
beginValue(raw)
editValue(raw, "#FFFFFFFF")
raw:SetValue(0x10203040, false)
expect(raw.valueField:GetText(), "#10203040", "external changes resync the caption")
expect(raw.preview.rgba, 0x10203040, "external changes resync the preview")
expect(raw.valueEditing, false, "external changes end the previous edit")
raw.valueField.root.subscriptions[ui.Hook.ONCONTENTCHANGED](
    raw.valueField.root, ui.InputFieldActionResult.CONTENT_CHANGE, "#FFFFFFFF")
expect(raw.pendingColour, 0x10203040, "late native notifications cannot restore stale text")
expect(raw.valueEditing, false, "late native notifications cannot reopen editing")
beginValue(raw)
editValue(raw, "")
raw.hueHit.subscriptions[ui.Hook.ONCLICK](raw.hueHit, 12, 0)
expect(raw.valueEditing, false, "dragging the picker returns to caption mode")
expect(raw.valueField:GetText(), string.format("#%08X", raw.pendingColour),
    "dragging keeps the caption synchronized")
expect(raw.acceptButton.disabled, false, "dragging replaces incomplete value input")
raw.hueHit.subscriptions[ui.Hook.ONRELEASE](raw.hueHit, 12, 0)
raw:Close()
raw:SetDisabled(true)
expect(raw:Open(), false, "disabled swatches cannot open the picker")
raw:SetDisabled(false)
raw:Open()
beginValue(raw)
local destroyedWindow = raw.pickerWindow
raw:Destroy()
expect(destroyedWindow.root.destroyed, true, "destroying the control removes its popup")
expect(raw.valueField, nil, "destroying the control releases its editor")

local alphaValue = ColourPicker.new(screen, { value = 0x33669980, alphaSlider = true })
alphaValue:Open()
beginValue(alphaValue)
editValue(alphaValue, "#FF000040")
expect(alphaValue.pendingHue, 0, "packed-value edits synchronize hue")
expect(alphaValue.fieldMarkerVertical.x, 143, "packed-value edits synchronize value")
expect(alphaValue.fieldMarkerHorizontal.y, 12, "packed-value edits synchronize saturation")
expect(alphaValue.alphaMarker.x, 47, "packed-value edits synchronize the alpha marker")
alphaValue.alphaHit.subscriptions[ui.Hook.ONCLICK](alphaValue.alphaHit, 127, 12)
expect(alphaValue.valueField:GetText(), "#FF0000FF", "the alpha slider updates the caption")
alphaValue.alphaHit.subscriptions[ui.Hook.ONRELEASE](alphaValue.alphaHit, 127, 12)
alphaValue:Destroy()

local upperBound = ColourPicker.new(screen, { value = 0xFFFFFFFF })
upperBound:Open()
expect(upperBound.valueField:GetText(), "#FFFFFFFF", "the largest RGBA hex code fits the caption")
beginValue(upperBound)
editValue(upperBound, "#FFFFFFFE")
expect(upperBound.pendingColour, 0xFFFFFFFE, "large packed values retain their low alpha byte")
editValue(upperBound, "#FFFFFFFF")
upperBound.acceptButton.action()
expect(upperBound:GetValue(), 0xFFFFFFFF, "the maximum unsigned packed value can be accepted")
upperBound:Destroy()

print("colour_picker_test: ok")
