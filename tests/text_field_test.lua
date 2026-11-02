local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function inputField(parent, categoryID, dynamicID)
    local result = {
        text = {},
        containerSprite = {},
    }

    function result:SetPos(x, y)
        self.x, self.y = x, y
    end

    function result:SetSize(width, height)
        self.width, self.height = width, height
    end

    function result:Setup(visibility, filterMode, maxLength)
        self.visibility = visibility
        self.filterMode = filterMode
        self.maxLength = maxLength
    end

    function result:Subscribe(hook, callback)
        self.subscriptions = self.subscriptions or {}
        self.subscriptions[hook] = callback
    end

    function result:Destroy()
        self.destroyed = true
    end

    return Interfaces.component(result, parent, categoryID, dynamicID)
end

ui = {
    InputField = {
        new = inputField,
    },
    Margin = {
        new = function(left, top, right, bottom)
            return {
                left = left,
                top = top,
                right = right,
                bottom = bottom,
            }
        end,
    },
    Hook = {
        ONCONTENTCHANGED = 1,
    },
    TextContentVisibilityMode = {
        VISIBLE = 1,
    },
    InputFieldFilterMode = {
        NONE = 1,
    },
    InputFieldKeyHandlingMode = {
        DEFAULT = 1,
    },
    InputFieldActionResult = {
        SUBMIT = 1,
        CONTENT_CHANGE = 2,
    },
}

id = {
    StyleSheet = {
        INPUT_DEFAULT = 1,
    },
    Font = {
        MUSEO_SANS_15PT_REGULAR = 1,
    },
}

package.loaded["src/core/control_palette"] = {
    TEXT = 0xFFFFFFFF,
    CARET = 0xFFFFFFFF,
    SELECTED = 0xFFFFFFFF,
}
package.loaded["src/tooltip"] = {
    bind = function() end,
    unbind = function() end,
    set = function() end,
}
package.loaded["src/core/wheel"] = {
    bind = function() end,
}

package.path = "prettyui/?.lua;" .. package.path
package.loaded["src/text_field"] = nil
local TextField = require("src/text_field")

local standard = TextField.new(Interfaces.component({}), {})
expect(standard.root.contentMargin.left, 8, "default left inset")
expect(standard.root.contentMargin.top, 3, "default vertical correction")
expect(standard.root.contentMargin.right, 8, "default right inset")
expect(standard.root.contentMargin.bottom, 0, "default bottom inset")

local customMargin = ui.Margin.new(1, 2, 3, 4)
local custom = TextField.new(Interfaces.component({}), {
    contentMargin = customMargin,
})
expect(custom.root.contentMargin, customMargin, "custom margin remains unchanged")

print("text_field_test: ok")
