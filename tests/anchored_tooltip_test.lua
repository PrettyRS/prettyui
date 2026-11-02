local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function component(parent, categoryID, dynamicID)
    local result = {
        x = 0,
        y = 0,
        width = 0,
        height = 0,
        hidden = false,
        children = {},
    }
    function result:SetSize(width, height)
        self.width = width
        self.height = height
    end
    function result:SetPos(x, y)
        self.x = x
        self.y = y
    end
    function result:MoveToBack()
        self.movedToBack = true
    end
    function result:Destroy()
        if self.destroyed then return end
        self.destroyed = true
        for _, child in ipairs(self.children) do child:Destroy() end
    end
    if parent then table.insert(parent.children, result) end
    return Interfaces.component(result, parent, categoryID, dynamicID)
end

local logicHandlers = {}
Event = {
    Logic = {
        Subscribe = function(eventID, callback) logicHandlers[eventID] = callback end,
        Unsubscribe = function(eventID) logicHandlers[eventID] = nil end,
    },
}

ui = {
    Layer = { new = function(owner, categoryID, dynamicID)
        return component(owner, categoryID, dynamicID)
    end },
    Sprite = { new = function(owner, categoryID, dynamicID)
        return component(owner, categoryID, dynamicID)
    end },
    Rectangle = { new = function(owner, categoryID, dynamicID)
        return component(owner, categoryID, dynamicID)
    end },
    Text = { new = function(owner, categoryID, dynamicID)
        return component(owner, categoryID, dynamicID)
    end },
    AlignMode = { CENTRE = 1 },
}

id = {
    Font = {
        MUSEO_SANS_13PT_BOLD = 1,
    },
}

local font = {
    baseline = 16,
    GetStringWidth = function(_, text) return #text * 5 end,
    GetStringHeightAndLineCount = function() return 18 end,
}
config = {
    Font = { MUSEO_SANS_15PT_REGULAR = font },
}

package.loaded["src/core/sprites"] = {
    ANCHORED_TOOLTIP = {
        border = {
            topLeft = 1,
            top = 2,
            side = 3,
            bottomLeft = 4,
        },
    },
}

local AnchoredTooltip = require("src/anchored_tooltip")
local parent = component()
parent.width = 600
parent.height = 400

local tooltip = AnchoredTooltip.new(parent, {
    anchor = function() return { x = 200, y = 200 } end,
    text = "Hi",
})
expect(tooltip.width, 34, "initial text is measured")
expect(tooltip.root.hidden, false, "anchored tooltip starts visible")

expect(tooltip:SetText("A longer tooltip"), true, "anchored tooltip text can be updated")
expect(tooltip.label.content, "A longer tooltip", "the anchored label is updated")
expect(tooltip.width, 104, "anchored text is remeasured")
expect(tooltip.root.width, 104, "the anchored root is resized")
expect(tooltip.topRight.x, 94, "the top-right border follows the new width")
expect(tooltip.bottomLeft.y, tooltip.height - 10, "the bottom border follows the new height")
expect(tooltip.root.hidden, false, "the updated anchored tooltip stays visible")

tooltip:Destroy()
expect(tooltip:SetText("Ignored"), false, "destroyed anchored tooltips reject updates")

local custom = AnchoredTooltip.new(parent, {
    anchor = function() return { x = 200, y = 200 } end,
    content = function() end,
})
expect(custom:SetText("Unsupported"), false, "custom-content tooltips reject text updates")
custom:Destroy()

local Components = require("src/core/components")
local callbackRan = false
local auto = AnchoredTooltip.new(parent, {
    categoryID = "auto",
    anchor = function() return { x = 160, y = 180 } end,
    content = function(owner, content)
        expect(owner.root.categoryID, 0, "tooltip root is zero before content callback")
        expect(content.categoryID, 0, "tooltip content is zero before content callback")
        expect(ui.Layer.new(content).categoryID, 0, "raw callback child inherits zero")
        expect(Components.new(ui.Text, content).categoryID > 0, true,
            "managed callback child uses auto allocation")
        callbackRan = true
    end,
})
expect(callbackRan, true, "auto anchored tooltip invokes its content callback")
auto:Destroy()

local autoHost = Components.new(ui.Layer, parent, { categoryID = "auto" })
local nonzero = Components.new(ui.Layer, autoHost)
local beforeMount = #nonzero.children
local mounted, mountError = pcall(AnchoredTooltip.new, nonzero, {
    categoryID = "auto", anchor = function() return { x = 1, y = 1 } end,
})
expect(mounted, false, "auto anchored tooltip rejects nonzero dynamic parents")
expect(mountError:find("raw-compatible content requires a category-zero parent", 1, true) ~= nil,
    true, "unsafe anchored tooltip mount has actionable guidance")
expect(#nonzero.children, beforeMount, "rejected tooltip creates no native root")

local originalLayer = ui.Layer.new
local failedRoot
ui.Layer.new = function(owner, categoryID, dynamicID)
    if owner ~= parent and owner and owner.categoryID == 0 and categoryID == nil then
        error("late anchored content failure")
    end
    local layer = originalLayer(owner, categoryID, dynamicID)
    if owner == parent then failedRoot = layer end
    return layer
end
local built, buildError = pcall(AnchoredTooltip.new, parent, {
    categoryID = "auto", anchor = function() return { x = 1, y = 1 } end,
})
ui.Layer.new = originalLayer
expect(built, false, "late anchored content failure propagates")
expect(buildError:find("late anchored content failure", 1, true) ~= nil,
    true, "anchored tooltip preserves original failure")
expect(failedRoot.destroyed, true, "anchored tooltip batch destroys its partial root")

print("anchored_tooltip_test: ok")
