local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local created = {}
ui = {
    Rectangle = {
        new = function(parent, categoryID, dynamicID)
            local rectangle = { parent = parent }
            function rectangle:SetPos(x, y)
                self.x, self.y = x, y
            end
            function rectangle:SetSize(width, height, widthAnchor, heightAnchor)
                self.width, self.height = width, height
                self.widthAnchor, self.heightAnchor = widthAnchor, heightAnchor
            end
            function rectangle:MoveToBack()
                self.movedToBack = true
            end
            function rectangle:Destroy()
                self.destroyed = true
            end
            created[#created + 1] = rectangle
            return Interfaces.component(rectangle, parent, categoryID, dynamicID)
        end,
    },
}

local emptyModule = {}
package.loaded["src/core/sprites"] = { HUD_WINDOW = {} }
package.loaded["src/colour_picker"] = emptyModule
package.loaded["src/combo_box"] = emptyModule
package.loaded["src/core/content_methods"] = {
    installPaired = function() end,
}
package.loaded["src/core/cursor"] = emptyModule
package.loaded["src/core/mouse"] = emptyModule
package.loaded["src/list"] = emptyModule
package.loaded["src/core/layout"] = emptyModule
package.loaded["src/core/scroll"] = {
    install = function() end,
}
package.loaded["src/slider"] = emptyModule
package.loaded["src/text_field"] = emptyModule
package.loaded["src/tabs"] = emptyModule
package.loaded["src/tooltip"] = emptyModule
package.loaded["src/core/wheel"] = emptyModule

package.loaded["src/panel"] = nil
local Panel = require("src/panel")
local entries = {
    { placement = { y = 10, height = 24 } },
    { placement = { y = 10, height = 24 } },
    { placement = { y = 54, height = 24 } },
    { placement = { y = 54, height = 24 } },
    { placement = { y = 54, height = 24 } },
}
local panel = setmetatable({
    dock = {
        content = Interfaces.component({ name = "dock" }),
        interfaceID = 1,
        container = { height = 88 },
    },
    overlay = {
        content = Interfaces.component({ name = "overlay" }),
        interfaceID = 1,
        container = { height = 88 },
    },
    dockOwner = { _managedFlowEntries = entries, contentHeight = 88 },
    overlayOwner = { _managedFlowEntries = entries, contentHeight = 88 },
    rowBackgroundColours = { 0x24211EFF, 0x2E2825FF },
    rowBackgroundEdgeToEdge = true,
    dockRowBackgrounds = {},
    overlayRowBackgrounds = {},
}, Panel)

panel:RefreshRowBackgrounds()
expect(#panel.dockRowBackgrounds, 2, "dock gets one backdrop per flow row")
expect(#panel.overlayRowBackgrounds, 2, "overlay gets one backdrop per flow row")
expect(panel.dockRowBackgrounds[1].rgba, 0x24211EFF, "title row uses first colour")
expect(panel.dockRowBackgrounds[2].rgba, 0x2E2825FF, "button row uses second colour")
expect(panel.dockRowBackgrounds[1].x, 0, "title backdrop reaches the left edge")
expect(panel.dockRowBackgrounds[1].width, 0, "title backdrop reaches the right edge")
expect(panel.dockRowBackgrounds[1].y, 0, "title backdrop fills top padding")
expect(panel.dockRowBackgrounds[1].height, 44, "title backdrop ends between rows")
expect(panel.dockRowBackgrounds[2].y, 44, "button backdrop begins between rows")
expect(panel.dockRowBackgrounds[2].height, 44, "button backdrop fills bottom half")
expect(
    panel.dockRowBackgrounds[1].height + panel.dockRowBackgrounds[2].height,
    88,
    "edge-to-edge row backdrops cover the full panel content height")
expect(panel.dockRowBackgrounds[1].widthAnchor, 1.0, "backdrop fills panel width")
expect(panel.dockRowBackgrounds[1].movedToBack, true, "backdrop stays behind controls")

local oldBackground = panel.dockRowBackgrounds[1]
panel:RefreshRowBackgrounds()
expect(oldBackground.destroyed, true, "refresh removes stale row backdrops")

print("panel_row_background_test: ok")
