local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function component(parent, kind, categoryID, dynamicID)
    local result = {
        kind = kind,
        x = 0,
        y = 0,
        width = 0,
        height = 0,
        subscriptions = {},
    }
    function result:SetPos(x, y)
        self.x, self.y = x, y
    end
    function result:SetSize(width, height, widthAnchor, heightAnchor)
        self.width = width + ((parent and parent.width or 0) * (widthAnchor or 0))
        self.height = height + ((parent and parent.height or 0) * (heightAnchor or 0))
    end
    function result:Subscribe(hook, idOrCallback, callback)
        self.subscriptions[hook] = callback or idOrCallback
    end
    function result:Destroy()
        self.destroyed = true
    end
    if parent then
        parent.children = parent.children or {}
        parent.children[#parent.children + 1] = result
    end
    return Interfaces.component(result, parent, categoryID, dynamicID)
end

local function factory(kind)
    return { new = function(parent, categoryID, dynamicID)
        return component(parent, kind, categoryID, dynamicID)
    end }
end

ui = {
    Layer = factory("layer"),
    Sprite = factory("sprite"),
    Text = factory("text"),
    Hook = {
        ONMOUSEOVER = 1,
        ONMOUSELEAVE = 2,
        ONCLICK = 3,
    },
    AlignMode = {
        TOPLEFT = 1,
        CENTRE = 2,
    },
}

local font = {
    GetStringWidth = function(_, text)
        return #text * 10
    end,
}
id = { Font = { MUSEO_SANS_15PT_REGULAR = font } }
config = {
    Font = { MUSEO_SANS_15PT_REGULAR = font },
    Cursor = {
        CURSOR_TICK = 1,
        CURSOR_CROSS = 2,
    },
}

package.loaded["src/core/cursor"] = { apply = function() end }
package.loaded["src/core/sprites"] = {
    CHECKBOX_BUTTON = {
        empty = 1,
        emptyHovered = 2,
        selected = 3,
        selectedHovered = 4,
    },
    RADIO_BUTTON = {
        empty = 5,
        emptyHovered = 6,
        selected = 7,
        selectedHovered = 8,
    },
}
package.loaded["src/core/wheel"] = { bind = function() end }
package.loaded["src/tooltip"] = {
    getContext = function() return nil end,
    registerContext = function() return {} end,
    unregisterContext = function() end,
    bind = function() return nil end,
    set = function() return true end,
    unbind = function() end,
}

package.loaded["src/selection_button"] = nil
local SelectionButtons = require("src/selection_button")
local CheckboxButton = SelectionButtons.CheckboxButton
local RadioButton = SelectionButtons.RadioButton

local choices = {
    { text = "Audio", value = "audio" },
    { text = "Animations", value = "animations" },
}

local verticalWidth, verticalHeight = CheckboxButton.getSize(choices, {})
local inlineWidth, inlineHeight = CheckboxButton.getSize(choices, { inline = true })
expect(verticalHeight, 44, "checkbox choices stack by default")
expect(inlineHeight, 22, "inline checkbox choices use one row")
expect(inlineWidth > verticalWidth, true, "inline checkbox width includes every choice")

local parent = component(nil, "parent")
parent.width = 400
parent.height = 300

local inline = CheckboxButton.new(parent, choices, {
    inline = true,
    width = 240,
})
expect(inline.root.height, 22, "inline checkbox root has one-row height")
expect(inline.items[1].row.y, 0, "first inline checkbox starts on the row")
expect(inline.items[2].row.y, 0, "second inline checkbox shares the row")
expect(inline.items[2].row.x > inline.items[1].row.x, true, "inline checkbox choices advance horizontally")

local vertical = CheckboxButton.new(parent, choices, { width = 240 })
expect(vertical.root.height, 44, "default checkbox root retains stacked height")
expect(vertical.items[1].row.x, 0, "stacked checkbox starts at the left edge")
expect(vertical.items[2].row.x, 0, "stacked checkbox choices share the left edge")
expect(vertical.items[2].row.y, 22, "stacked checkbox choices advance vertically")

local radio = RadioButton.new(parent, choices, {
    inline = true,
    width = 240,
})
expect(radio.root.height, 22, "inline radio root has one-row height")
expect(radio.items[1].row.y, 0, "first inline radio starts on the row")
expect(radio.items[2].row.y, 0, "second inline radio shares the row")
expect(radio.items[2].row.x > radio.items[1].row.x, true, "inline radio choices advance horizontally")

local Layout = require("src/core/layout")
local Host = {}
require("src/core/content_methods").installSingle(Host)

for _, method in ipairs({ "AddCheckboxButton", "AddRadioButton" }) do
    local content = component(nil, "content")
    content.width = 800
    local owner = setmetatable({ content = content, contentWidth = content.width }, { __index = Host })
    Layout.configure(owner)
    local function addSpacer(width, height)
        local placed = Layout.place(owner, { width = width, height = height })
        local root = component(content, "spacer")
        root:SetPos(placed.x, placed.y)
        root:SetSize(placed.width, placed.height)
        return Layout.manage(owner, root, placed)
    end
    local prefix = addSpacer(1, 10)
    local swatch = addSpacer(48, 48)
    local controls = {}
    for _, text in ipairs({ "Show tile marker", "Fill tile marker", "Mark entire NPC size" }) do
        controls[#controls + 1] = owner[method](owner, { text }, { inline = true })
    end
    local function checkRow()
        local previous = swatch
        for _, control in ipairs(controls) do
            expect(control.root.y, swatch.y, method .. " shares the colour swatch row")
            expect(control.root.x, previous.x + previous.width + 8,
                method .. " follows the previous control without overlap")
            previous = control.root
        end
        expect(previous.x + previous.width <= content.width - 14, true,
            method .. " leaves room for all three inline controls")
    end
    checkRow()
    prefix:Destroy()
    checkRow()
    Layout.destroyManaged(owner)
    expect(controls[1].root, nil, method .. " is destroyed with its flow owner")
end

print("selection_button_test: ok")
