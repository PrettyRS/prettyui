local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
    end
end

local function expectTrue(actual, message)
    if actual ~= true then
        error(message .. ": expected true, got " .. tostring(actual))
    end
end

local function expectFalse(actual, message)
    if actual then
        error(message .. ": expected false, got " .. tostring(actual))
    end
end

Vector4 = { new = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end }

local windows = {}
local layers = {}

local function fakeLayer(parent)
    local layer = {
        parent = parent,
        clickthrough = false,
        destroyed = false,
        raiseCount = 0,
    }
    function layer:SetPos() end
    function layer:SetSize() end
    function layer:MoveToFront()
        self.raiseCount = (self.raiseCount or 0) + 1
    end
    function layer:Destroy()
        self.destroyed = true
    end
    layers[#layers + 1] = layer
    return layer
end

local function fakeRect(parent)
    local rect = { parent = parent, fill = false, clickthrough = false, colour = nil }
    function rect:SetPos() end
    function rect:SetSize() end
    return rect
end

local function fakeWindow(parent, options)
    local window = {
        parent = parent,
        options = options,
        title = options.title,
        onClose = options.onClose,
        destroyOnClose = options.destroyOnClose == true,
        buttons = {},
        texts = {},
        shown = false,
        destroyed = false,
        raiseCount = 0,
    }
    function window:AddText(text)
        self.texts[#self.texts + 1] = text
    end
    function window:AddFancyButton(label, action, opts)
        opts = opts or {}
        local button = { label = label, action = action, opts = opts, disabled = opts.disabled == true }
        function button:SetDisabled(disabled)
            self.disabled = disabled == true
        end
        self.buttons[#self.buttons + 1] = button
        return button
    end
    function window:Show()
        self.shown = true
        self.raiseCount = self.raiseCount + 1
    end
    function window:Close()
        if self.onClose then self.onClose(self) end
        if self.destroyOnClose then self:Destroy() end
    end
    function window:Destroy()
        self.destroyed = true
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
    getSize = function(text, _opts)
        if text == "CANCEL" or text == "CONFIRM" then return 150, 27 end
        return 80, 27
    end,
}
package.loaded["src/dialog"] = nil

local Dialog = require("src/dialog")

local function button(window, label)
    for _, item in ipairs(window.buttons) do
        if item.label == label then return item end
    end
    return nil
end

local function resetHost()
    windows = {}
    layers = {}
end

local parent = { id = "p" }

local failed = pcall(function() Dialog.new(nil, { title = "X" }) end)
expectFalse(failed, "nil parent should error")

resetHost()
Dialog.dismissAll(parent)
local dialog = Dialog.new(parent, {
    title = "Msg",
    content = function(window) window:AddText("hello") end,
    actions = { { label = "Close" } },
})
expect(Dialog.depth(parent), 1, "omitted onClick depth")
expect(dialog.window.texts[1], "hello", "content text")
button(dialog.window, "Close").action()
expect(Dialog.depth(parent), 0, "omitted onClick pops")
expectTrue(dialog.window.destroyed, "omitted onClick destroys")

resetHost()
Dialog.dismissAll(parent)
local clicks = 0
dialog = Dialog.new(parent, {
    actions = {
        {
            label = "Go",
            onClick = function()
                clicks = clicks + 1
                return clicks >= 2
            end,
        },
    },
})
button(dialog.window, "Go").action()
expect(Dialog.depth(parent), 1, "false stays")
button(dialog.window, "Go").action()
expect(Dialog.depth(parent), 0, "true pops")

resetHost()
Dialog.dismissAll(parent)
dialog = Dialog.new(parent, {
    actions = {
        { label = "Close" },
        { label = "Save to file", disabled = true },
    },
})
button(dialog.window, "Save to file").action()
expect(Dialog.depth(parent), 1, "disabled does not pop")
button(dialog.window, "Close").action()
expect(Dialog.depth(parent), 0, "close pops after disabled")

resetHost()
Dialog.dismissAll(parent)
dialog = Dialog.new(parent, {
    width = 100,
    actions = {
        { label = "CANCEL" },
        { label = "CONFIRM" },
    },
})
local cancel = button(dialog.window, "CANCEL")
local confirm = button(dialog.window, "CONFIRM")
local contentWidth = dialog.window.options.width - 16
expectTrue(contentWidth + cancel.opts.x >= 0, "window grows to keep the left action inside its content")
expectTrue(cancel.opts.x + 150 <= confirm.opts.x, "footer actions do not overlap")
expectTrue(confirm.opts.x + 150 <= 0, "right action stays inside the content edge")
Dialog.dismissAll(parent)

resetHost()
Dialog.dismissAll(parent)
local dismissed = 0
local clicked = 0
dialog = Dialog.new(parent, {
    onDismiss = function() dismissed = dismissed + 1 end,
    actions = {
        {
            label = "Close",
            onClick = function()
                clicked = clicked + 1
                return true
            end,
        },
    },
})
dialog.window:Close()
expect(dismissed, 1, "X fires onDismiss")
expect(clicked, 0, "X does not fire action")
expect(Dialog.depth(parent), 0, "X pops")

resetHost()
Dialog.dismissAll(parent)
dismissed = 0
dialog = Dialog.new(parent, {
    onDismiss = function() dismissed = dismissed + 1 end,
    actions = { { label = "Close" } },
})
button(dialog.window, "Close").action()
expect(dismissed, 0, "footer close does not fire onDismiss")
expect(Dialog.depth(parent), 0, "footer close pops")

resetHost()
Dialog.dismissAll(parent)
local first = Dialog.new(parent, { title = "A", actions = { { label = "Close" } } })
local second = Dialog.new(parent, { title = "B", actions = { { label = "Close" } } })
expect(Dialog.depth(parent), 2, "stack depth")
button(second.window, "Close").action()
expect(Dialog.depth(parent), 1, "pop top")
expectTrue(second.window.destroyed, "top destroyed")
expectFalse(first.window.destroyed, "bottom remains")
Dialog.dismissAll(parent)
expect(Dialog.depth(parent), 0, "dismissAll empty")
expectTrue(first.window.destroyed, "dismissAll destroys remaining")

resetHost()
local other = { id = "other" }
Dialog.dismissAll(parent)
Dialog.dismissAll(other)
Dialog.new(parent, { title = "A" })
Dialog.new(other, { title = "B" })
expect(Dialog.depth(parent), 1, "parent stack isolated")
expect(Dialog.depth(other), 1, "other stack isolated")
Dialog.dismissAll(other)
expect(Dialog.depth(parent), 1, "dismissAll other leaves parent")
Dialog.dismissAll(parent)

resetHost()
Dialog.dismissAll(parent)
local save = { label = "Save", disabled = true, onClick = function() return true end }
dialog = Dialog.new(parent, { actions = { save } })
expect(save.button, nil, "action has no button field")
expect(save.setDisabled, nil, "action has no setDisabled field")
local saveButton = button(dialog.window, "Save")
expectTrue(saveButton.disabled, "starts disabled")
saveButton.action()
expect(Dialog.depth(parent), 1, "disabled click stays")
dialog:SetActionDisabled(save, false)
expectFalse(saveButton.disabled, "SetActionDisabled(false) enables the button")
expectTrue(save.disabled, "SetActionDisabled does not write action.disabled")
saveButton.action()
expect(Dialog.depth(parent), 0, "enabled click pops")

resetHost()
Dialog.dismissAll(parent)
local go = { label = "Go", onClick = function() return true end }
dialog = Dialog.new(parent, { actions = { go } })
local goButton = button(dialog.window, "Go")
dialog:SetActionDisabled(go, true)
expectTrue(goButton.disabled, "SetActionDisabled(true) disables the button")
goButton.action()
expect(Dialog.depth(parent), 1, "disabled after enable does not pop")
Dialog.dismissAll(parent)

resetHost()
Dialog.dismissAll(parent)
dialog = Dialog.new(parent, { actions = { { label = "Close" } } })
local unknownFailed = pcall(function()
    dialog:SetActionDisabled({ label = "Nope" }, true)
end)
expectFalse(unknownFailed, "unknown action raises")
Dialog.dismissAll(parent)

print("dialog_test: ok")
