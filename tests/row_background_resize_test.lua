local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function component(x, y, width, height, parent, categoryID, dynamicID)
    local value = { parent = parent, x = x, y = y, width = width, height = height }
    function value:SetPos(nextX, nextY)
        self.x, self.y = nextX, nextY
    end
    function value:SetSize(nextWidth, nextHeight, widthAnchor, heightAnchor)
        self.width, self.height = nextWidth, nextHeight
        self.widthAnchor, self.heightAnchor = widthAnchor, heightAnchor
    end
    function value:SetHeight(nextHeight) self.height = nextHeight end
    function value:SetY(nextY) self.y = nextY end
    function value:MoveToBack() self.movedToBack = true end
    function value:Destroy() self.destroyed = true end
    return Interfaces.component(value, parent, categoryID, dynamicID)
end

ui = {
    Rectangle = {
        new = function(parent, categoryID, dynamicID)
            return component(0, 0, 0, 0, parent, categoryID, dynamicID)
        end,
    },
}

package.loaded["src/core/layout"] = nil
package.loaded["src/core/row_backgrounds"] = nil
local Layout = require("src/core/layout")
local RowBackgrounds = require("src/core/row_backgrounds")

local content = component(0, 0, 200, 120)
local collapseRoot = component(14, 12, 172, 20)
local followingRoot = component(14, 40, 172, 20)
local collapse = { root = collapseRoot }
local following = { root = followingRoot }
local owner = {
    interfaceID = content.interfaceID,
    contentHeight = 72,
    _flowLayout = {
        startY = 12,
        minimumContentHeight = 0,
        columnGap = 8,
        paddingLeft = 14,
        paddingRight = 14,
        paddingBottom = 12,
        rowGap = 8,
        nextY = 68,
        row = nil,
    },
    _managedFlowEntries = {
        { component = collapse, placement = { x = 14, y = 12, width = 172, height = 20 } },
        { component = following, placement = { x = 14, y = 40, width = 172, height = 20 } },
    },
    rowBackgrounds = {},
}
function owner:SetContentHeight(height) self.contentHeight = height end
function owner:RefreshRowBackgrounds()
    RowBackgrounds.clear(self.rowBackgrounds, self.interfaceID)
    self.rowBackgrounds = RowBackgrounds.apply(content, 120, self, { 10, 20 }, false)
end

owner:RefreshRowBackgrounds()
local oldBackground = owner.rowBackgrounds[1]
expect(oldBackground.height, 28, "collapsed row background matches header height")

Layout.resize(owner, collapse, 60)
expect(collapseRoot.height, 60, "collapse flow row receives expanded height")
expect(followingRoot.y, 80, "following row moves below expanded collapse")
expect(oldBackground.destroyed, true, "expansion destroys stale row background")
expect(owner.rowBackgrounds[1].height, 68, "row background expands with collapse content")
expect(owner.rowBackgrounds[2].y, 76, "following row background moves with reflow")

print("row_background_resize_test: ok")
