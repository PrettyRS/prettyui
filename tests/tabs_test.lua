local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function component(parent, kind, categoryID, dynamicID)
    local result = {
        kind = kind,
        hidden = false,
        opConfig = {
            ClearOpCursors = function() end,
            SetOpCursor = function() end,
        },
        cursorConfig = {},
    }
    function result:SetPos(x, y, xAnchor, yAnchor)
        self.x, self.y, self.xAnchor, self.yAnchor = x, y, xAnchor, yAnchor
    end
    function result:SetSize(width, height, widthAnchor, heightAnchor)
        self.width, self.height = width, height
        self.widthAnchor, self.heightAnchor = widthAnchor, heightAnchor
    end
    function result:SetScrollSize(width, height)
        self.scrollWidth, self.scrollHeight = width, height
    end
    function result:SetScrollPos(x, y)
        self.scrollX, self.scrollY = x, y
    end
    function result:Subscribe() end
    function result:MoveToFront() end
    function result:Destroy()
        if self.destroyed then return end
        self.destroyed = true
        for _, child in ipairs(self.children or {}) do child:Destroy() end
    end
    if parent then
        parent.children = parent.children or {}
        table.insert(parent.children, result)
    end
    return Interfaces.component(result, parent, categoryID, dynamicID)
end

local function componentFactory(kind)
    return { new = function(parent, categoryID, dynamicID)
        return component(parent, kind, categoryID, dynamicID)
    end }
end

ui = {
    Layer = componentFactory("layer"),
    Sprite = componentFactory("sprite"),
    Text = componentFactory("text"),
    Hook = {
        ONMOUSEOVER = 1,
        ONMOUSELEAVE = 2,
        ONCLICK = 3,
        ONHOLD = 4,
        ONDRAG = 5,
        ONRELEASE = 6,
        ONDRAGCOMPLETE = 7,
        ONSCROLLWHEEL = 8,
    },
    AlignMode = { CENTRE = 0 },
}

id = {
    Font = { MUSEO_SANS_15PT_REGULAR = 1 },
}

config = {
    Cursor = { CURSOR_GOTO = 1 },
    Font = {
        MUSEO_SANS_15PT_REGULAR = {
            GetStringWidth = function(_, text) return #text * 7 end,
        },
    },
}

local tabPageInstalled = false
local tabPageInstallOptions
package.loaded["src/core/content_methods"] = {
    installSingle = function(_, options)
        tabPageInstalled = true
        tabPageInstallOptions = options
    end,
}
package.loaded["src/core/cursor"] = {
    apply = function() end,
}
package.loaded["src/core/layout"] = {
    configure = function() end,
    destroyManaged = function() end,
}
local appliedRowColours
package.loaded["src/core/row_backgrounds"] = {
    clear = function() end,
    apply = function(_, _, _, colours, edgeToEdge)
        appliedRowColours = colours
        expect(edgeToEdge, false, "tab page row backgrounds default to padded bounds")
        return {}
    end,
}
package.loaded["src/core/sprites"] = {
    DIVIDER = 1,
    ICON_TAB = { inactive = 2, hovered = 3, active = 4, disabled = 5 },
    TEXT_TAB = {
        inactive = { left = 6, middle = 7, right = 8 },
        active = { left = 9, middle = 10, right = 11 },
        disabled = { left = 12, middle = 13, right = 14 },
    },
}
hiddenTooltipContexts = {}
package.loaded["src/tooltip"] = {
    getContext = function() return nil end,
    registerContext = function() return {} end,
    bind = function() return nil end,
    set = function() return true end,
    unbind = function() return true end,
    unregisterContext = function() end,
    hideContextTooltips = function(collection) hiddenTooltipContexts[collection] = true end,
}
package.loaded["src/core/wheel"] = {
    bind = function() end,
}

local Tabs = require("src/tabs")
local parent = component(nil, "parent")
local tabs = Tabs.new(parent, { "Misc" }, {
    rowBackgroundColours = { 10, 20 },
})
local tab = tabs:GetTab(1)

expect(tabPageInstalled, true, "tab pages install shared content helpers")
local tabPageExclusions = tabPageInstallOptions and tabPageInstallOptions.exclude or {}
expect(tabPageExclusions.AddPanel, nil, "tab pages expose non-popout panels")
expect(tabPageExclusions.AddTabs, nil, "tab pages expose nested tabs")
local page = tabs:GetPage(1)
page:RefreshRowBackgrounds()
expect(appliedRowColours[1], 10, "tab pages inherit row background colours")
expect(appliedRowColours[2], 20, "tab pages preserve alternating row colours")
expect(tab.width, 90, "short text leaves enough room for both end sprites")
expect(tab.left.width + 30 <= tab.width, true, "the left and right end sprites do not overlap")
expect(tab.middle.width, -60, "the middle strip is anchored between both caps")

tabs:SetDisabled(1, true)
expect(tab.width, 90, "disabled styling preserves the safe minimum width")

local tooltipTabs = Tabs.new(parent, { { text = "One" }, { text = "Two" } }, { height = 100 })
hiddenTooltipContexts = {}
tooltipTabs:SetActive(2)
expect(hiddenTooltipContexts[tooltipTabs:GetPage(1).content], true, "leaving a tab hides its tooltips")
expect(hiddenTooltipContexts[tooltipTabs:GetPage(2).content], nil, "the new tab's tooltips are left alone")

local Components = require("src/core/components")
local autoTabs = Tabs.new(parent, { "Auto" }, { categoryID = "auto" })
local autoPage = autoTabs:GetPage(1)
expect(autoTabs.root.categoryID, 0, "auto tabs root remains raw-compatible")
expect(autoTabs.content.categoryID, 0, "auto tabs outer content stays in category zero")
expect(autoPage.root.categoryID, 0, "auto page root stays in category zero")
expect(autoPage.content.categoryID, 0, "auto page scroll content stays in category zero")
expect(autoTabs:GetTab(1).visual.categoryID > 0, true,
    "auto tab visuals use managed categories")
expect(ui.Layer.new(autoPage.content).categoryID, 0,
    "raw page extension inherits category zero")
expect(Components.new(ui.Text, autoPage.content).categoryID > 0, true,
    "managed page controls inherit auto allocation")

local badMount = Components.new(ui.Layer, autoTabs.root)
local nativeLayer = ui.Layer.new
local nativeAttempts = 0
ui.Layer.new = function(...)
    nativeAttempts = nativeAttempts + 1
    return nativeLayer(...)
end
local validMount, mountError = pcall(Tabs.new, badMount, { "Rejected" },
    { categoryID = "auto" })
ui.Layer.new = nativeLayer
expect(validMount, false, "auto tabs reject a nonzero parent")
expect(mountError:find("raw-compatible content requires a category-zero parent", 1, true) ~= nil,
    true, "auto tabs rejection is actionable")
expect(nativeAttempts, 0, "rejected tabs create no native roots")

local originalLayer = ui.Layer.new
local constructed = {}
local zeroLayers = 0
ui.Layer.new = function(owner, categoryID, dynamicID)
    if categoryID == nil and owner and owner.categoryID == 0 then
        zeroLayers = zeroLayers + 1
        if zeroLayers == 4 then error("late page scroll failure") end
    end
    local layer = originalLayer(owner, categoryID, dynamicID)
    constructed[#constructed + 1] = layer
    return layer
end
local validBatch, batchError = pcall(Tabs.new, parent, { "One" },
    { categoryID = "auto" })
ui.Layer.new = originalLayer
expect(validBatch, false, "late page scroll failure propagates")
expect(batchError:find("late page scroll failure", 1, true) ~= nil,
    true, "late page scroll preserves the native error")
for _, layer in ipairs(constructed) do
    expect(layer.destroyed, true, "failed direct tabs construction destroys its native subtree")
end
print("tabs_test: ok")
