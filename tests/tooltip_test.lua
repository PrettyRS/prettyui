local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function component(parent)
    local result = {
        x = 0,
        y = 0,
        width = 0,
        height = 0,
        hidden = false,
        children = {},
        subscriptions = {},
    }
    function result:SetSize(width, height)
        self.width = width
        self.height = height
    end
    function result:SetPos(x, y)
        self.x = x
        self.y = y
    end
    function result:Subscribe(hook, id, callback)
        self.subscriptions[tostring(hook) .. ":" .. id] = callback
    end
    function result:Unsubscribe(hook, id)
        self.subscriptions[tostring(hook) .. ":" .. id] = nil
    end
    function result:MoveToFront()
        self.frontCount = (self.frontCount or 0) + 1
    end
    function result:Destroy()
        self.destroyed = true
    end
    if parent then table.insert(parent.children, result) end
    return Interfaces.component(result, parent)
end

local parent = component()
parent.width = 600
parent.height = 400

ui = {
    Hook = { ONMOUSEOVER = 1, ONMOUSELEAVE = 2, ONMOUSEREPEAT = 3 },
    AlignMode = { TOPLEFT = 1, CENTRE = 2 },
    Layer = { new = function(owner) return component(owner) end },
    Sprite = { new = function(owner) return component(owner) end },
    Text = { new = function(owner)
        local label = component(owner)
        label.enabled = false
        return label
    end },
}

id = {
    Font = { MUSEO_SANS_15PT_REGULAR = 1 },
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
    CONTENT_FRAME = {
        centre = 1,
        top = 2,
        bottom = 3,
        right = 4,
        left = 5,
        topRight = 6,
        topLeft = 7,
        bottomRight = 8,
        bottomLeft = 9,
    },
}

local Tooltip = require("src/tooltip")
local target = component()
target.x = 20
target.y = 30
target.width = 40
target.height = 20
target.clickthrough = true

local tooltip = Tooltip.attach(target, parent, "Hi")
expect(tooltip.width, 26, "initial text is measured")
expect(tooltip.root, nil, "tooltip builds nothing until shown")

expect(tooltip:SetText("A longer tooltip"), true, "tooltip text can be updated")
expect(tooltip.width, 96, "updated text is remeasured")
expect(tooltip.root, nil, "updating a hidden tooltip keeps it unbuilt")

tooltip:Show()
expect(tooltip.label.content, "A longer tooltip", "the label is built with the latest text")
expect(tooltip.root.width, 96, "the tooltip root is built at the latest size")
expect(tooltip.root.hidden, false, "showing builds a visible tooltip")
expect(tooltip.root.x, 66, "tooltip uses the target placement")
local frontCount = tooltip.root.frontCount
expect(tooltip:SetText("Small"), true, "a visible tooltip can be updated")
expect(tooltip.width, 41, "a visible tooltip is remeasured")
expect(tooltip.root.x, 66, "a visible tooltip is repositioned")
expect(tooltip.root.frontCount, frontCount + 1, "a visible tooltip remains in front")

local shownRoot = tooltip.root
tooltip:Hide()
expect(shownRoot.destroyed, true, "hiding releases the tooltip components")
expect(tooltip.root, nil, "hiding drops the released root")
expect(tooltip:SetText("Rebuilt"), true, "a released tooltip can still be updated")
tooltip:Show()
expect(tooltip.label.content, "Rebuilt", "showing again rebuilds with the latest text")

tooltip:Destroy()
expect(tooltip:SetText("Ignored"), false, "destroyed tooltips reject updates")
tooltip:Show()
expect(tooltip.root, nil, "destroyed tooltips cannot be rebuilt")

local eagerTooltip = Tooltip.attach(component(), parent, "Eager", { eager = true, onMouseLeave = function() end })
expect(eagerTooltip.root.hidden, true, "eager tooltips are built up front and hidden")
local eagerRoot = eagerTooltip.root
eagerTooltip:Show()
eagerTooltip:Hide()
expect(eagerTooltip.root, eagerRoot, "tooltips with their own leave handling stay built")
expect(eagerRoot.hidden, true, "tooltips that stay built still hide")
eagerTooltip:Destroy()
expect(eagerRoot.destroyed, true, "destroying releases a tooltip that stayed built")

local owner = {}
local boundTarget = component()
boundTarget.width = 20
boundTarget.height = 20
boundTarget.clickthrough = true
Tooltip.bind(owner, boundTarget, parent, nil)
expect(owner.tooltip, nil, "bindings can start without a tooltip")
expect(Tooltip.set(owner, "Added later"), true, "bindings add tooltips dynamically")
local firstAttachment = owner.tooltip
expect(firstAttachment.options.text, "Added later", "a dynamically added tooltip has the requested text")
expect(Tooltip.set(owner, "Updated in place"), true, "plain text updates an existing attachment")
expect(owner.tooltip, firstAttachment, "plain text preserves the attachment")
expect(firstAttachment.options.text, "Updated in place", "plain text updates its text")
expect(Tooltip.set(owner, { text = "Replacement", width = 140 }), true, "options replace an attachment")
expect(owner.tooltip == firstAttachment, false, "options create a fresh attachment")
expect(firstAttachment.root, nil, "the replaced attachment is destroyed")
expect(owner.tooltip.width, 140, "replacement options take effect")
expect(Tooltip.set(owner, nil), true, "nil removes a bound tooltip")
expect(owner.tooltip, nil, "the removed attachment is cleared")
expect(boundTarget.clickthrough, true, "removing restores the original target interaction")
expect(Tooltip.set(owner, "Added again"), true, "a removed tooltip can be added again")
expect(Tooltip.unbind(owner), true, "bindings can be destroyed")
expect(Tooltip.set(owner, "Ignored"), false, "destroyed bindings reject updates")

-- Dispatch hover only to input-enabled text, rather than calling Show directly.
local function dispatchMouse(target, hook, x, y)
    if target.enabled == false or target.hidden then return end
    local prefix = tostring(hook) .. ":"
    for key, callback in pairs(target.subscriptions) do
        if key:sub(1, #prefix) == prefix then callback(target, x, y) end
    end
end

local Text = require("src/text")
local Host = {}
require("src/core/content_methods").installSingle(Host)
local textContent = component(parent)
textContent.width = 400
local textOwner = setmetatable({ content = textContent, contentWidth = 400 }, { __index = Host })
require("src/core/layout").configure(textOwner)
local textOriginY, scrollY = 100, 20
Tooltip.registerContext(textContent, parent, function(label)
    return label.x + 180, label.y + textOriginY - scrollY
end)
local childCount = #parent.children
local label = textOwner:AddText({ text = "Hover me", width = 400, tooltip = "Text details" })
expect(#parent.children, childCount, "text tooltip builds nothing until hovered")
dispatchMouse(label, ui.Hook.ONMOUSEOVER, 12, 4)
local textOverlay = parent.children[#parent.children]
expect(textOverlay.hidden, false, "hovering flow text shows its tooltip")
local cursorX = label.x + 180 + 12
local cursorY = label.y + textOriginY - scrollY + 4
expect(textOverlay.x > cursorX and textOverlay.x < cursorX + 24, true,
    "wide text anchors its tooltip near the cursor, not the row edge")
expect(textOverlay.y, cursorY, "cursor placement uses the scrolled overlay coordinate space")
dispatchMouse(label, ui.Hook.ONMOUSEREPEAT, 50, 8)
expect(textOverlay.x > cursorX + 38 and textOverlay.x < cursorX + 62, true,
    "tooltip follows cursor movement within the text")
scrollY = 40
dispatchMouse(label, ui.Hook.ONMOUSEREPEAT, 50, 8)
expect(textOverlay.y, label.y + textOriginY - scrollY + 8,
    "cursor placement follows changes in the scroll context")
dispatchMouse(label, ui.Hook.ONMOUSEREPEAT, 390, 8)
expect(textOverlay.x + textOverlay.width < label.x + 180 + 390, true,
    "tooltip flips left when the cursor is near the right edge")
textOriginY = 400
dispatchMouse(label, ui.Hook.ONMOUSEREPEAT, 12, 8)
expect(textOverlay.y + textOverlay.height < label.y + textOriginY - scrollY + 8, true,
    "tooltip flips above when the cursor is near the bottom edge")
expect(textOverlay.x >= 0 and textOverlay.x + textOverlay.width <= parent.width
    and textOverlay.y >= 0 and textOverlay.y + textOverlay.height <= parent.height, true,
    "cursor-aligned tooltip stays inside the overlay parent")
Tooltip.hideContextTooltips(textContent)
expect(textOverlay.destroyed, true, "hiding the context releases its tooltip")
childCount = #parent.children
dispatchMouse(label, ui.Hook.ONMOUSEREPEAT, 12, 8)
expect(#parent.children, childCount, "mouse repeat does not reopen a hidden context tooltip")
dispatchMouse(label, ui.Hook.ONMOUSEOVER, 12, 8)
textOverlay = parent.children[#parent.children]
dispatchMouse(label, ui.Hook.ONMOUSELEAVE)
expect(textOverlay.destroyed, true, "leaving flow text releases its tooltip")

local plainLabel = Text.new(textContent, { text = "Plain text" })
local plainHover = false
plainLabel:Subscribe(ui.Hook.ONMOUSEOVER, "test_hover", function() plainHover = true end)
dispatchMouse(plainLabel, ui.Hook.ONMOUSEOVER)
expect(plainHover, false, "text without a tooltip retains its native input behavior")
local fixedLabel = Text.new(textContent, {
    text = "Fixed tooltip",
    tooltip = { text = "Explicit placement", x = 42, y = 48 },
})
dispatchMouse(fixedLabel, ui.Hook.ONMOUSEOVER, 100, 10)
local fixedOverlay = parent.children[#parent.children]
dispatchMouse(fixedLabel, ui.Hook.ONMOUSEREPEAT, 150, 15)
expect(fixedOverlay.x, 42, "explicit tooltip x overrides cursor placement")
expect(fixedOverlay.y, 48, "explicit tooltip y overrides cursor placement")
dispatchMouse(label, ui.Hook.ONMOUSEOVER, 12, 8)
textOverlay = parent.children[#parent.children]
Tooltip.unregisterContext(textContent)
expect(textOverlay.destroyed, true, "destroying the text context removes its visible tooltip")

local contextCollection = component()
local context = Tooltip.registerContext(
    contextCollection,
    parent,
    function(item) return item.x, item.y end)
local contextTarget = component()
contextTarget.width = 20
contextTarget.height = 20
local contextTooltip = Tooltip.attach(contextTarget, contextCollection, "Context")
contextTooltip:Show()

local childCollection = component()
Tooltip.registerContext(
    childCollection,
    parent,
    function(item) return item.x, item.y end,
    context)
local childTarget = component()
childTarget.width = 20
childTarget.height = 20
local childTooltip = Tooltip.attach(childTarget, childCollection, "Child")
childTooltip:Show()

Tooltip.hideContextTooltips(contextCollection)
expect(contextTooltip.root, nil, "context tooltip hides with its window")
expect(childTooltip.root, nil, "nested panel tooltip hides with its window")
local deadOwner = {}
local deadTarget = component()
Tooltip.bind(deadOwner, deadTarget, parent, "Logout")
local deadTooltip = deadOwner.tooltip
Interfaces.unload()
deadTooltip:Hide()
deadTooltip:Show()
expect(deadTooltip:SetText("Ignored"), false, "dead tooltip rejects native updates")
expect(Tooltip.set(deadOwner, "Ignored"), false, "dead binding cannot recreate components")
deadTooltip:Destroy()
deadTooltip:Destroy()
expect(deadTooltip.root, nil, "dead tooltip drops its root without native access")
Tooltip.unregisterContext(contextCollection)
expect(Tooltip.getContext(contextCollection), nil, "logout removes tooltip contexts")
Tooltip.unbind(deadOwner)

-- Target and overlay may belong to different interfaces.
local overlayParent = component()
local separateTarget = component({ interfaceID = 2, children = {} })
local separateTooltip = Tooltip.attach(separateTarget, overlayParent, "Separate interface")
separateTooltip:Show()
local survivingRoot = separateTooltip.root
Interfaces.unload(2)
separateTooltip:Show()
separateTooltip:Destroy()
expect(survivingRoot.destroyed, true, "target unload still cleans a live overlay")

local survivingTarget = component()
survivingTarget.clickthrough = true
local separateParent = component({ interfaceID = 2, children = {} })
local lostOverlay = Tooltip.attach(survivingTarget, separateParent, "Separate overlay")
Interfaces.unload(2)
lostOverlay:Hide()
lostOverlay:Destroy()
expect(survivingTarget.clickthrough, true, "overlay unload still restores a live target")

print("tooltip_test: ok")
