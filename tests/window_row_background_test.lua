local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function component(parent, categoryID, dynamicID)
    local value = { parent = parent, subscriptions = {} }
    function value:SetPos(x, y, xAnchor, yAnchor)
        self.x, self.y = x, y
        self.xAnchor, self.yAnchor = xAnchor, yAnchor
    end
    function value:SetSize(width, height, widthAnchor, heightAnchor)
        self.width, self.height = width, height
        self.widthAnchor, self.heightAnchor = widthAnchor, heightAnchor
    end
    function value:MoveToFront() self.movedToFront = true end
    function value:MoveToBack() self.movedToBack = true end
    function value:Subscribe(hook, callback) self.subscriptions[hook] = callback end
    function value:Destroy() self.destroyed = true end
    return Interfaces.component(value, parent, categoryID, dynamicID)
end

local created = {}
ui = {
    AlignMode = { CENTRE = 1 },
    Hook = {
        ONCLICK = 1,
        ONMOUSEOVER = 2,
        ONMOUSELEAVE = 3,
    },
    Layer = { new = component },
    Sprite = { new = component },
    Rectangle = {
        new = function(parent, categoryID, dynamicID)
            local rectangle = component(parent, categoryID, dynamicID)
            created[#created + 1] = rectangle
            return rectangle
        end,
    },
}
id = { Font = { CINZEL_13PT_BOLD = 1 } }

package.loaded["src/core/sprites"] = {
    WINDOW_BACKGROUND = 1,
    BORDER_LEFT = 2,
    BORDER_BOTTOM = 3,
    BORDER_CORNER = 4,
    TITLEBAR_LEFT = 5,
    TITLEBAR_CENTRE_LEFT = 6,
    TITLEBAR_CENTRE = 7,
    TITLEBAR_CENTRE_RIGHT = 8,
    TITLEBAR_RIGHT = 9,
    CLOSE = 10,
    CLOSE_ACTIVE = 11,
}
package.loaded["src/core/content_methods"] = { installSingle = function() end }
package.loaded["src/text"] = { title = function(parent) return component(parent) end }
package.loaded["src/tooltip"] = {
    getContext = function() return nil end,
    registerContext = function() return {} end,
    bind = function() end,
    unbind = function() end,
    unregisterContext = function() end,
    hideContextTooltips = function() end,
}
package.loaded["src/core/layout"] = {
    configure = function(owner)
        owner._managedFlowEntries = {}
        owner._flowLayout = { paddingLeft = 14, paddingRight = 14 }
    end,
    destroyManaged = function() end,
}
package.loaded["src/core/mouse"] = { EndCapture = function() end }
package.loaded["src/core/scroll"] = {
    attach = function(owner, _, options)
        owner.viewport = component()
        owner.content = component(owner.viewport)
        owner.contentHeight = options.contentHeight or 0
        owner._scroll = {
            height = 88,
            Refresh = function() end,
            Destroy = function(self) self.destroyed = true end,
        }
    end,
    install = function() end,
}

package.loaded["src/window"] = nil
local Window = require("src/window")
local window = Window.new(component(), {
    width = 300,
    height = 140,
    contentHeight = 88,
    rowBackgroundColors = { 0x24211EFF, 0x2E2825FF },
})
window._managedFlowEntries = {
    { placement = { y = 10, height = 24 } },
    { placement = { y = 10, height = 24 } },
    { placement = { y = 54, height = 24 } },
    { placement = { y = 54, height = 24 } },
    { placement = { y = 5, height = 80, _flowAbsolute = true } },
}

expect(window.rowBackgroundEdgeToEdge, false, "edge-to-edge backgrounds default off")
window:RefreshRowBackgrounds()
expect(#window.rowBackgrounds, 2, "window gets one backdrop per flow row")
expect(window.rowBackgrounds[1].rgba, 0x24211EFF, "first row uses first colour")
expect(window.rowBackgrounds[2].rgba, 0x2E2825FF, "second row uses second colour")
expect(window.rowBackgrounds[1].x, 10, "standard backdrop pads beyond the row's left edge")
expect(window.rowBackgrounds[1].width, -20, "standard backdrop pads beyond the row's right edge")
expect(window.rowBackgrounds[1].y, 6, "standard backdrop pads above the row")
expect(window.rowBackgrounds[1].height, 32, "standard backdrop pads below the row")
expect(window.rowBackgrounds[1].widthAnchor, 1.0, "standard backdrop fills padded row width")
expect(window.rowBackgrounds[1].movedToBack, true, "backdrop stays behind controls")

local standardBackground = window.rowBackgrounds[1]
for index = 1, 4 do
    window._managedFlowEntries[index].placement.rowBackgroundGroup = "section"
end
table.insert(window._managedFlowEntries, 5, {
    placement = { y = 38, height = 8, rowBackground = false },
})
window:RefreshRowBackgrounds()
expect(standardBackground.destroyed, true, "grouping removes stale row backdrops")
expect(#window.rowBackgrounds, 2, "an excluded row separates matching groups")
expect(window.rowBackgrounds[1].y, 6, "background before an exclusion keeps outer padding")
expect(window.rowBackgrounds[1].height, 32, "background includes padding before an excluded row")
expect(window.rowBackgrounds[2].y, 50, "background resumes with padding after an excluded row")
expect(window.rowBackgrounds[1].rgba, 0x24211EFF, "excluded row does not consume a colour")
expect(window.rowBackgrounds[2].rgba, 0x2E2825FF, "colour sequence advances across visible regions")

local splitBackground = window.rowBackgrounds[1]
table.remove(window._managedFlowEntries, 5)
window:RefreshRowBackgrounds()
expect(splitBackground.destroyed, true, "removing an exclusion rebuilds row backdrops")
expect(#window.rowBackgrounds, 1, "consecutive rows with one group share a backdrop")
expect(window.rowBackgrounds[1].y, 6, "group backdrop pads above its first row")
expect(window.rowBackgrounds[1].height, 76, "group backdrop pads below its final row")
expect(window.rowBackgrounds[1].rgba, 0x24211EFF, "group advances the colour once")

local groupedBackground = window.rowBackgrounds[1]
for index = 1, 4 do
    window._managedFlowEntries[index].placement.rowBackgroundGroup = nil
end
table.insert(window._managedFlowEntries, 5, {
    placement = { y = 38, height = 8, rowBackground = false },
})
window.rowBackgroundEdgeToEdge = true
window:RefreshRowBackgrounds()
expect(groupedBackground.destroyed, true, "mode change removes grouped row backdrops")
expect(window.rowBackgrounds[1].x, 0, "edge backdrop reaches the left edge")
expect(window.rowBackgrounds[1].width, 0, "edge backdrop reaches the right edge")
expect(window.rowBackgrounds[1].y, 0, "edge backdrop fills top padding")
expect(window.rowBackgrounds[1].height, 32, "edge backdrop stops before an excluded row")
expect(window.rowBackgrounds[2].y, 54, "edge backdrop resumes after an excluded row")
local activeBackground = window.rowBackgrounds[1]
window:Destroy()
expect(activeBackground.destroyed, true, "destroy removes row backdrops")

print("window_row_background_test: ok")
