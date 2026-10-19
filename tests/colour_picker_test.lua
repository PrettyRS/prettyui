local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local mousePosition

local function component(parent, kind)
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
        end,
    })
    function result:Destroy() self.destroyed = true end
    if parent then
        parent.children = parent.children or {}
        table.insert(parent.children, result)
    end
    return Interfaces.component(result, parent)
end

local function canvas(parent)
    local result = component(parent, "canvas")
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
    local root = component(parent, "button")
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
    Rectangle = { new = function(parent) return component(parent, "rectangle") end },
    Canvas = { new = canvas },
    Layer = { new = function(parent) return component(parent, "layer") end },
    Hook = {
        ONCLICK = 1,
        ONHOLD = 2,
        ONDRAG = 3,
        ONRELEASE = 4,
        ONDRAGCOMPLETE = 5,
        ONMOUSEOVER = 6,
        ONMOUSELEAVE = 7,
    },
}

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
}
package.loaded["src/window"] = {
    new = function(parent, options)
        local root = component(parent, "window")
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
            AddFancyButton = function(_, _, action, buttonOptions)
                local button = simpleButton(content, buttonOptions)
                button.action = action
                return button
            end,
            AddText = function() end,
            AddTextField = function(_, fieldOptions)
                return {
                    onChange = fieldOptions.onChange,
                    SetText = function(self, text) self.text = text end,
                }
            end,
            Show = function() end,
            Close = function() end,
            Destroy = function() end,
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
expect(standard.hexField.text, "#336699", "standard pickers display RGB hex")

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

standard.hexField:SetText("00ffff")
standard.hexField.onChange(standard.hexField, nil, "00ffff")
expect(standard.pendingColour, 0x00FFFF80, "hex input preserves alpha")
expect(standard.preview.rgba, 0x00FFFF80, "hex input updates the preview")
expect(standard.hexField.text, "00ffff", "hex input is not reformatted while editing")
expect(standard:GetValue(), 0x33669980, "hex input remains pending until accepted")

for _, content in ipairs({ "", "#123", "#GG0000" }) do
    standard.hexField.onChange(standard.hexField, nil, content)
    expect(standard.acceptButton.disabled, true, "invalid hex disables acceptance")
    expect(standard.pendingColour, 0x00FFFF80, "invalid hex preserves the pending colour")
end
standard.hexField.onChange(standard.hexField, nil, "#00ffff")
expect(standard.acceptButton.disabled, false, "valid hex enables accepting again")
standard.acceptButton.action()
expect(standard:GetValue(), 0x00FFFF80, "accepting commits the entered hex colour")

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
expect(picker.hexField.text, "#33669980", "the alpha picker displays RGBA hex")

picker.hexField.onChange(picker.hexField, nil, "#33669920")
expect(picker.pendingColour, 0x33669920, "RGBA hex input updates the alpha")
expect(picker.preview.rgba, 0x33669920, "RGBA hex input updates the preview")

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
expect(picker.hexField.text, "#33669900", "the alpha being changed updates the hex field")

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

print("colour_picker_test: ok")
