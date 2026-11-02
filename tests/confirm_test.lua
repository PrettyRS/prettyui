local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
    end
end

local function expectFalse(actual, message)
    if actual then
        error(message .. ": expected false, got " .. tostring(actual))
    end
end

Vector4 = { new = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end }

local windows = {}

local function fakeLayer(parent, categoryID, dynamicID)
    local layer = { parent = parent, clickthrough = false, destroyed = false }
    function layer:SetPos() end
    function layer:SetSize() end
    function layer:MoveToFront() end
    function layer:Destroy()
        self.destroyed = true
    end
    return Interfaces.component(layer, parent, categoryID, dynamicID)
end

local function fakeRect(parent, categoryID, dynamicID)
    local rect = { parent = parent, fill = false, clickthrough = false, colour = nil }
    function rect:SetPos() end
    function rect:SetSize() end
    return Interfaces.component(rect, parent, categoryID, dynamicID)
end

local function fakeWindow(parent, options)
    Interfaces.component(parent)
    local root = require("src/core/components").new(ui.Layer, parent, options)
    local window = {
        root = root,
        parent = parent,
        options = options,
        title = options.title,
        onClose = options.onClose,
        destroyOnClose = options.destroyOnClose == true,
        buttons = {},
        texts = {},
        destroyed = false,
    }
    function window:AddText(text)
        self.texts[#self.texts + 1] = text
    end
    function window:AddFancyButton(label, action, opts)
        local button = { label = label, action = action, opts = opts or {} }
        self.buttons[#self.buttons + 1] = button
        return button
    end
    function window:Show() end
    function window:Close()
        if self.onClose then self.onClose(self) end
        if self.destroyOnClose then self:Destroy() end
    end
    function window:Destroy()
        if self.destroyed then return end
        self.destroyed = true
        self.root:Destroy()
    end
    windows[#windows + 1] = window
    return window
end

ui = {
    Layer = { new = fakeLayer },
    Rectangle = { new = fakeRect },
}

package.loaded["src/window"] = { new = fakeWindow }
package.loaded["src/fancy_button"] = {
    getSize = function(_text, _opts) return 80, 27 end,
}
package.loaded["src/dialog"] = nil
package.loaded["src/confirm"] = nil

local Dialog = require("src/dialog")
local Confirm = require("src/confirm")

local function button(window, label)
    for _, item in ipairs(window.buttons) do
        if item.label == label then return item end
    end
    return nil
end

local parent = { id = "c" }

local notices = {}
log = function(message) notices[#notices + 1] = message end
local staticHost = Interfaces.component({ id = "confirm-static" })
local nativeHost = ui.Layer.new(staticHost)
local autoConfirm = Confirm.new(nativeHost, {
    body = "Ready?", categoryID = "auto",
})
expect(autoConfirm.window.root.categoryID > 0, true,
    "auto Confirm constructs a managed native window root")
expect(#notices, 0, "an auto-only confirmation does not emit a category deprecation notice")
button(autoConfirm.window, "CONFIRM").action()
expect(Dialog.depth(nativeHost), 0, "auto confirmation still closes from its action")
local foreignAuto = require("src/core/components").new(ui.Layer, nativeHost, {
    categoryID = "auto",
})
expect(foreignAuto.categoryID > 0, true, "host can contain unrelated auto controls")
local legacyConfirm = Confirm.new(nativeHost, { body = "Existing consumer" })
expect(legacyConfirm.window.root.categoryID, 0,
    "legacy Confirm remains native inherited beside auto components")
button(legacyConfirm.window, "CANCEL").action()

Dialog.dismissAll(parent)
local saw = {}
local dialog = Confirm.new(parent, {
    body = "Delete?",
    onConfirm = function()
        saw[#saw + 1] = "ok"
    end,
    onCancel = function()
        saw[#saw + 1] = "no"
    end,
})
expect(dialog.window.texts[1], "Delete?", "confirm body")
button(dialog.window, "CANCEL").action()
expect(#saw, 1, "cancel callback count")
expect(saw[1], "no", "cancel callback")
expect(Dialog.depth(parent), 0, "cancel pops")

saw = {}
dialog = Confirm.new(parent, {
    onConfirm = function()
        saw[#saw + 1] = "ok"
    end,
    onCancel = function()
        saw[#saw + 1] = "no"
    end,
})
button(dialog.window, "CONFIRM").action()
expect(#saw, 1, "confirm callback count")
expect(saw[1], "ok", "confirm callback")
expect(Dialog.depth(parent), 0, "confirm pops")

saw = {}
dialog = Confirm.new(parent, {
    onConfirm = function() saw[#saw + 1] = "ok" end,
    onCancel = function() saw[#saw + 1] = "no" end,
})
dialog.window:Close()
expect(#saw, 1, "X callback count")
expect(saw[1], "no", "X is cancel")
expect(Dialog.depth(parent), 0, "X pops")

dialog = Confirm.new(parent, {
    onConfirm = function() return false end,
})
button(dialog.window, "CONFIRM").action()
expect(Dialog.depth(parent), 1, "false onConfirm stays")
expectFalse(dialog.window.destroyed, "false onConfirm does not destroy")
Dialog.dismissAll(parent)

print("confirm_test: ok")
