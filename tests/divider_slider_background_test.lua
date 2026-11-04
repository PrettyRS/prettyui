local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function component(parent, categoryID, dynamicID)
    local value = {}
    function value:SetPos(x, y, xAnchor, yAnchor)
        self.x, self.y, self.xAnchor, self.yAnchor = x, y, xAnchor, yAnchor
    end
    function value:SetSize(width, height, widthAnchor, heightAnchor)
        self.width, self.height = width, height
        self.widthAnchor, self.heightAnchor = widthAnchor, heightAnchor
    end
    function value:SetX(x) self.x = x end
    function value:SetWidth(width) self.width = width end
    function value:Subscribe() end
    function value:MoveToBack() end
    function value:MoveToFront() end
    function value:Destroy() self.destroyed = true end
    return Interfaces.component(value, parent, categoryID, dynamicID)
end

ui = {
    Sprite = { new = component },
    Layer = { new = component },
    Rectangle = { new = component },
    Hook = { ONCLICK = 1, ONMOUSEOVER = 2, ONMOUSELEAVE = 3, ONRELEASE = 4,
        ONHOLD = 5, ONDRAG = 6, ONDRAGCOMPLETE = 7 },
}
config = { Cursor = { CURSOR_BLANK = 0 } }
package.loaded["src/core/sprites"] = {
    DIVIDER = 1,
    SLIDER = {
        backingEnd = 2, backingTile = 3, barEnd = 4, barTile = 5,
        thumb = { normal = 6, disabled = 7 },
        decrease = { normal = 8, disabled = 9 },
        increase = { normal = 10, disabled = 11 },
    },
}
package.loaded["src/tooltip"] = { bind = function() end, unbind = function() end }
package.loaded["src/core/wheel"] = { bind = function() end }
package.loaded["src/core/cursor"] = { apply = function() end }
package.loaded["src/core/mouse"] = { EndCapture = function() end }

local Layout = require("src/core/layout")
local RowBackgrounds = require("src/core/row_backgrounds")
local Host = {}
require("src/core/content_methods").installSingle(Host)
local host = setmetatable({
    content = component(), contentHeight = 0, contentWidth = 400,
    rowBackgroundColours = { 0x24211EFF, 0x2E2825FF }, rowBackgrounds = {},
}, { __index = Host })
function host:SetContentHeight(height) self.contentHeight = height end
function host:RefreshRowBackgrounds()
    RowBackgrounds.clear(self.rowBackgrounds, self.interfaceID)
    self.rowBackgrounds = RowBackgrounds.apply(
        self.content, 320, self, self.rowBackgroundColours, false)
end
Layout.configure(host)

local divider = host:AddDivider()
expect(divider.root.x, 0, "divider starts at content edge")
expect(divider.root.width, 0, "divider has no fixed-width inset")
expect(divider.root.widthAnchor, 1, "divider fills content width")
expect(host._managedFlowEntries[1].placement.rowBackground, false, "divider excluded by default")
host:RefreshRowBackgrounds()
expect(#host.rowBackgrounds, 0, "unpainted divider consumes no background")

local slider = host:AddSlider({ value = 50, rowBackgroundGroup = "controls" })
expect(slider:GetValue(), 50, "slider remains interactive")
expect(#host.rowBackgrounds, 1, "adding slider paints its flow row")
expect(host.rowBackgrounds[1].rgba, 0x24211EFF, "slider uses first background colour")
expect(host.rowBackgrounds[1].y, slider.root.y - 4, "background covers slider row")

local separator = host:AddDivider({ rowBackgroundGroup = "controls" })
expect(host._managedFlowEntries[3].placement.rowBackground, false, "grouped divider still excluded")
host:RefreshRowBackgrounds()
local second = host:AddSlider({ rowBackgroundGroup = "controls" })
expect(#host.rowBackgrounds, 2, "divider splits consecutive slider background groups")
expect(host.rowBackgrounds[2].rgba, 0x2E2825FF, "second slider advances background colour")
expect(host.rowBackgrounds[2].y, second.root.y - 4, "second slider background aligned")

second:Destroy()
separator:Destroy()
slider:Destroy()
divider:Destroy()
local paintedDivider = host:AddDivider({ rowBackground = true })
host:RefreshRowBackgrounds()
expect(#host.rowBackgrounds, 1, "explicitly included divider receives a background")
paintedDivider:Destroy()
local Components = require("src/core/components")
local Slider = require("src/slider")
local nativeHost = ui.Layer.new(host.content)
local autoSlider = Slider.new(nativeHost, { categoryID = "auto" })
expect(autoSlider.root.categoryID > 0, true, "opted-in slider root uses managed IDs")
expect(autoSlider.thumbDrag.categoryID > 0, true,
    "slider thumb drag inherits the opted-in slider policy")
autoSlider:Destroy()
local autoHost = Components.new(ui.Layer, host.content, { categoryID = "auto" })
local legacySlider = Slider.new(autoHost, { _categoryPolicy = "legacy" })
expect(legacySlider.thumbDrag.categoryID, autoHost.categoryID,
    "legacy thumb drag overrides the physical host's auto policy")
legacySlider:Destroy()

print("divider_slider_background_test: ok")
