local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function component(parent, kind)
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
    function result:Destroy() self.destroyed = true end
    if parent then
        parent.children = parent.children or {}
        table.insert(parent.children, result)
    end
    return Interfaces.component(result, parent)
end

local function componentFactory(kind)
    return { new = function(parent) return component(parent, kind) end }
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

print("tabs_test: ok")
