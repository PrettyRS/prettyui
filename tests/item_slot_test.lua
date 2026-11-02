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
        frontMoves = 0,
    }
    function result:SetPos(x, y)
        self.x, self.y = x, y
    end
    function result:SetSize(width, height)
        self.width, self.height = width, height
    end
    function result:SetAssociatedObject(objectID)
        self.associatedObjectID = objectID
        self.rgb = 0xFFFFFF
        self.alpha = 1
    end
    function result:MoveToFront()
        self.frontMoves = self.frontMoves + 1
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
    Rectangle = factory("rectangle"),
    Sprite = factory("sprite"),
    ObjectQuantityDisplayMode = {
        NEVER = 0,
        MULTIPLE = 1,
    },
}

package.loaded["src/core/sprites"] = { ITEM_SLOT_BACKGROUND = 10 }
package.loaded["src/core/wheel"] = { bind = function() end }
package.loaded["src/tooltip"] = {
    attach = function() return nil end,
}
package.loaded["src/item_slot"] = nil
local ItemSlot = require("src/item_slot")

local parent = component(nil, "parent")
local enabled = ItemSlot.new(parent, { id = 100 }, {})
expect(enabled.disabled, false, "item slots are enabled by default")
expect(enabled.disabledOverlay.kind, "rectangle", "disabled overlay uses a filled rectangle")
expect(enabled.disabledOverlay.x, enabled.item.x, "disabled overlay matches item x")
expect(enabled.disabledOverlay.y, enabled.item.y, "disabled overlay matches item y")
expect(enabled.disabledOverlay.width, enabled.item.width, "disabled overlay matches item width")
expect(enabled.disabledOverlay.height, enabled.item.height, "disabled overlay matches item height")
expect(enabled.disabledOverlay.fill, true, "disabled overlay is filled")
expect(enabled.disabledOverlay.rgba, 0x000000FF, "disabled overlay is black")
expect(enabled.disabledOverlay.alpha, 0.55, "disabled overlay is 55 percent opaque")
expect(enabled.disabledOverlay.clickthrough, true, "disabled overlay does not capture input")
expect(enabled.disabledOverlay.hidden, true, "enabled item has no overlay")
expect(enabled.item.alpha, 1, "enabled item remains opaque")

local disabled = ItemSlot.new(parent, { id = 200 }, {
    disabled = true,
    itemInset = 6,
})
expect(disabled.disabledOverlay.x, 6, "custom inset positions disabled overlay")
expect(disabled.disabledOverlay.width, 28, "custom inset sizes disabled overlay")
expect(disabled.disabledOverlay.hidden, false, "disabled option shows overlay")
expect(disabled.disabledOverlay.frontMoves, 1, "visible overlay is moved above the item")
expect(disabled.item.alpha, 0.75, "disabled item model is slightly transparent")
expect(disabled.disabledOverlay.fill, true, "disabled overlay remains filled")
expect(disabled.disabledOverlay.rgba, 0x000000FF, "disabled overlay remains black")
expect(disabled.disabledOverlay.alpha, 0.55, "disabled overlay remains 55 percent opaque")

disabled:SetDisabled(false)
expect(disabled.disabled, false, "SetDisabled records enabled state")
expect(disabled.disabledOverlay.hidden, true, "SetDisabled false hides overlay")
expect(disabled.item.alpha, 1, "SetDisabled false restores item opacity")

disabled:SetDisabled(true)
expect(disabled.disabled, true, "SetDisabled records disabled state")
expect(disabled.disabledOverlay.hidden, false, "SetDisabled true shows overlay")
expect(disabled.disabledOverlay.frontMoves, 2, "re-enabled overlay returns above the item")
expect(disabled.item.alpha, 0.75, "SetDisabled true reduces item opacity")

disabled:SetObject(nil)
expect(disabled.disabledOverlay.hidden, true, "empty disabled slot has no overlay")

disabled:SetObject({ id = 201 })
expect(disabled.disabledOverlay.hidden, false, "new item restores disabled overlay")
expect(disabled.disabledOverlay.frontMoves, 3, "restored overlay covers replacement item")
expect(disabled.item.alpha, 0.75, "replacement item retains disabled transparency")

print("item_slot_test: ok")
