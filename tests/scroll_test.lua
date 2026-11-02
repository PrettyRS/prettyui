local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function expectInputClipped(field, clipped, message)
    local root = field.root
    expect((root.text.rgba & 0xFF) == 0, clipped, message)
    expect(root.hidden, false, message .. ": field frame remains visible")
    if clipped then
        expect(root.text.isShadowed, false, message .. ": no text shadow escapes")
        expect(root.emptyTextRGBA & 0xFF, 0, message .. ": no placeholder escapes")
        expect(root.caretRGBA & 0xFF, 0, message .. ": no caret escapes")
        expect(root.errorCaretRGBA & 0xFF, 0, message .. ": no error caret escapes")
        expect(root.selectionHighlightRGBA & 0xFF, 0, message .. ": no selection escapes")
    end
end

local rawMousePosition
Mouse = {
    GetPosition = function()
        return rawMousePosition
    end,
}

local function component(parent, kind, categoryID, dynamicID)
    local result = {
        parent = parent,
        kind = kind,
        x = 0,
        y = 0,
        width = 0,
        height = 0,
        hidden = false,
        subscriptions = {},
        opConfig = {
            ClearOpCursors = function() end,
            SetOpCursor = function() end,
        },
        cursorConfig = {},
    }
    function result:SetPos(x, y, xAnchor, yAnchor)
        self.x = x + ((parent and parent.width or 0) * (xAnchor or 0))
        self.y = y + ((parent and parent.height or 0) * (yAnchor or 0))
    end
    function result:SetSize(width, height, widthAnchor, heightAnchor)
        self.width = width + ((parent and parent.width or 0) * (widthAnchor or 0))
        self.height = height + ((parent and parent.height or 0) * (heightAnchor or 0))
    end
    function result:SetWidth(width, widthAnchor)
        self.width = width + ((parent and parent.width or 0) * (widthAnchor or 0))
    end
    function result:SetHeight(height, heightAnchor)
        self.height = height + ((parent and parent.height or 0) * (heightAnchor or 0))
    end
    function result:SetScrollSize(width, height)
        self.scrollWidth, self.scrollHeight = width, height
    end
    function result:SetScrollPos(x, y)
        self.scrollPositionUpdates = (self.scrollPositionUpdates or 0) + 1
        self.scrollX, self.scrollY = x, y
    end
    function result:Subscribe(hook, name, callback)
        self.subscriptions[hook] = callback or name
    end
    function result:Unsubscribe(hook)
        self.subscriptions[hook] = nil
    end
    function result:MoveToFront() end
    function result:MoveToBack() end
    function result:Destroy() self.destroyed = true end
    if parent then
        parent.children = parent.children or {}
        table.insert(parent.children, result)
    end
    return Interfaces.component(result, parent, categoryID, dynamicID)
end

local function factory(kind)
    return { new = function(parent, categoryID, dynamicID)
        return component(parent, kind, categoryID, dynamicID)
    end }
end

local function inputField(parent, categoryID, dynamicID)
    local result = component(parent, "input", categoryID, dynamicID)
    result.text = {}
    result.containerSprite = {}
    function result:Setup(visibility, filterMode, maxLength)
        self.visibility = visibility
        self.filterMode = filterMode
        self.maxLength = maxLength
    end
    return result
end

ui = {
    Layer = factory("layer"),
    InputField = { new = inputField },
    Margin = {
        new = function(left, top, right, bottom)
            return { left = left, top = top, right = right, bottom = bottom }
        end,
    },
    Sprite = factory("sprite"),
    Text = factory("text"),
    Hook = {
        ONCLICK = 1,
        ONHOLD = 2,
        ONDRAG = 3,
        ONRELEASE = 4,
        ONDRAGCOMPLETE = 5,
        ONSCROLLWHEEL = 6,
        ONMOUSEOVER = 7,
        ONMOUSELEAVE = 8,
        ONCONTENTCHANGED = 9,
        ONRESIZE = 10,
    },
    AlignMode = { TOPLEFT = 1, CENTRE = 2 },
    TextContentVisibilityMode = { VISIBLE = 1 },
    InputFieldFilterMode = { NONE = 1 },
    InputFieldKeyHandlingMode = { DEFAULT = 1 },
    InputFieldActionResult = { SUBMIT = 1, CONTENT_CHANGE = 2 },
}

id = {
    Font = {
        MUSEO_SANS_15PT_REGULAR = 1,
        CINZEL_13PT_BOLD = 2,
    },
    StyleSheet = {
        INPUT_DEFAULT = 1,
    },
}

local font = {
    baseline = 18,
    GetStringLineCount = function() return 1 end,
    GetStringWidth = function(_, text) return #text * 7 end,
}
config = {
    Cursor = { CURSOR_GOTO = 1 },
    Font = {
        MUSEO_SANS_15PT_REGULAR = font,
        CINZEL_13PT_BOLD = font,
    },
}

package.loaded["src/core/sprites"] = {
    SCROLL_ARROW_UP = 1,
    SCROLL_ARROW_DOWN = 2,
    SCROLL_TRACK_TOP = 3,
    SCROLL_TRACK_CENTRE = 4,
    SCROLL_TRACK_BOTTOM = 5,
    SCROLL_THUMB_TOP = 6,
    SCROLL_THUMB_CENTRE = 7,
    SCROLL_THUMB_BOTTOM = 8,
    DIVIDER = 9,
    CHECKBOX_BUTTON = { empty = 1, selected = 2, emptyHovered = 3, selectedHovered = 4 },
    TEXT_TAB = {
        inactive = { left = 10, middle = 11, right = 12 },
        active = { left = 13, middle = 14, right = 15 },
        disabled = { left = 16, middle = 17, right = 18 },
    },
}

local Scroll = require("src/core/scroll")
local parent = component(nil, "parent")
parent.width = 640
parent.height = 480

local forwarded = 0
local scroll = Scroll.new(parent, {
    width = 300,
    height = 100,
    _onScrollWheel = function()
        forwarded = forwarded + 1
        return false
    end,
})

expect(scroll.scrollable, true, "scrolling defaults to enabled")
expect(scroll.scrollbarVisible, false, "bar starts hidden without overflow")
expect(scroll.contentWidth, 300, "hidden bar does not reserve width")

scroll:SetContentHeight(180)
expect(scroll.scrollbarVisible, true, "bar appears when content overflows")
expect(scroll.contentWidth, 282, "visible bar reserves its width and gap")
expect(scroll.track.hidden, false, "track is visible during overflow")

local anchor = component(scroll.content, "anchor")
anchor:SetPos(0, 90)
scroll:ScrollToChild(anchor)
expect(scroll.scrollY, 78, "scroll-to-child leaves the default inset above a native child")
scroll:ScrollToChild({ root = anchor }, 24)
expect(scroll.scrollY, 66, "scroll-to-child accepts control wrappers and a custom inset")
anchor:SetPos(0, 175)
scroll:ScrollToChild(anchor)
expect(scroll.scrollY, 80, "scroll-to-child clamps anchors near the end of the content")
anchor:SetPos(0, 5)
scroll:ScrollToChild(anchor)
expect(scroll.scrollY, 0, "scroll-to-child clamps anchors near the start of the content")

local handled = scroll.content.subscriptions[ui.Hook.ONSCROLLWHEEL](scroll.content, 1)
expect(handled, false, "wheel input is consumed while scrolling")
expect(scroll.scrollY, 32, "wheel input advances by the configured step")

scroll:SetScrollPosition(0)
scroll.content.subscriptions[ui.Hook.ONSCROLLWHEEL](scroll.content, -1)
expect(forwarded, 1, "wheel input forwards to a parent at the scroll boundary")

scroll:SetScrollable(false)
expect(scroll.scrollbarVisible, false, "disabled scrolling hides the bar")
expect(scroll.scrollY, 0, "disabled scrolling resets the viewport")
expect(scroll.contentWidth, 300, "disabled scrolling restores content width")

scroll:SetScrollable(true)
expect(scroll.scrollbarVisible, true, "re-enabling restores overflow behavior")
scroll:SetContentHeight(100)
expect(scroll.scrollbarVisible, false, "bar hides again when overflow is removed")
scroll:SetContentHeight(0)
scroll:SetSize(300, 50)
expect(scroll.scrollbarVisible, false, "resizing an empty view does not create false overflow")

scroll:Destroy()
expect(scroll.root, nil, "destroy releases the scroll surface")

local SimpleView = require("src/simple_view")
local simpleView = SimpleView.new(parent, { width = 120, height = 80 })
expect(simpleView.scrollbarVisible, false, "simple views start without a scrollbar")
simpleView:SetContentHeight(120)
expect(simpleView.scrollbarVisible, true, "simple views expose shared overflow behavior")
simpleView:Destroy()

local Window = require("src/window")
local window = Window.new(parent, { width = 300, height = 150 })
expect(window.scrollable, true, "window content defaults to scrollable")
expect(window.scrollbarVisible, false, "window bar starts hidden")
local rows = {}
for index = 1, 5 do
    rows[index] = window:AddText({ text = "Row " .. index, height = 30 })
end
expect(window.scrollbarVisible, true, "flow layout overflow reveals the window bar")
local removedY = rows[2].y
rows[2]:Destroy()
expect(rows[3].y, removedY, "destroying text reclaims its flow row")
expect(#window._managedFlowEntries, 4, "destroyed text leaves the flow registry")
local replacement = window:AddText({ text = "Replacement", height = 30 })
expect(replacement.y, rows[5].y + rows[5].height + 2, "new text follows the reflowed rows")
local clippedField = window:AddTextField({ text = "Viewport clipping regression" })
expectInputClipped(clippedField, true, "text below the viewport is transparent")
window:ScrollToChild(clippedField, 0)
expectInputClipped(clippedField, false, "text is restored when scrolled into view")
window:SetScrollPosition(0)
expectInputClipped(clippedField, true, "text is transparent again after leaving the viewport")
window:SetScrollPosition(10)
expect(window.scrollY, 10, "installed host methods keep public scroll state synchronized")
window:ScrollToChild(rows[4], 4)
expect(
    window.scrollY,
    math.min(rows[4].y - 4, window._scroll.scrollHeight - window._scroll.height),
    "installed hosts expose scroll-to-child"
)

window:SetScrollPosition(0)
local thumbDrag = window._scroll.thumbDrag
local clickX, clickY = 1, 1
rawMousePosition = {
    x = thumbDrag.x + clickX,
    y = thumbDrag.y + clickY,
}
thumbDrag.subscriptions[ui.Hook.ONCLICK](thumbDrag, clickX, clickY)
expect(thumbDrag.width, 16, "thumb capture stays local until the first hold")
local scrollPositionUpdates = window._scroll.viewport.scrollPositionUpdates
thumbDrag.subscriptions[ui.Hook.ONHOLD](thumbDrag, clickX, clickY)
expect(thumbDrag.width, parent.width, "first hold expands the thumb capture")
expect(window.scrollY, 0, "capture expansion does not rewind or advance scrolling")
expect(
    window._scroll.viewport.scrollPositionUpdates,
    scrollPositionUpdates,
    "capture expansion skips native scroll writes"
)

rawMousePosition = {
    x = rawMousePosition.x,
    y = rawMousePosition.y + 40,
}
thumbDrag.subscriptions[ui.Hook.ONHOLD](
    thumbDrag,
    rawMousePosition.x,
    rawMousePosition.y
)
expect(
    thumbDrag.width,
    parent.width,
    "window overlay synchronization preserves the expanded thumb capture"
)
local draggedScrollY = window.scrollY
expect(draggedScrollY > 0, true, "thumb hold advances the scroll position")
local dragStartHandler = thumbDrag.subscriptions[ui.Hook.ONDRAG]
if dragStartHandler then dragStartHandler(thumbDrag, clickX, clickY) end
expect(
    window.scrollY,
    draggedScrollY,
    "drag-start coordinates do not rewind an active thumb drag"
)
scrollPositionUpdates = window._scroll.viewport.scrollPositionUpdates
thumbDrag.subscriptions[ui.Hook.ONHOLD](
    thumbDrag,
    rawMousePosition.x,
    rawMousePosition.y
)
expect(
    window._scroll.viewport.scrollPositionUpdates,
    scrollPositionUpdates,
    "a stationary scrollbar drag skips duplicate native scroll writes"
)
thumbDrag.subscriptions[ui.Hook.ONRELEASE]()
expect(thumbDrag.width, 16, "thumb capture returns to the visual thumb after release")

local fixedWindow = Window.new(parent, {
    width = 300,
    height = 150,
    scrollable = false,
})
for index = 1, 5 do
    fixedWindow:AddText({ text = "Row " .. index, height = 30 })
end
expect(fixedWindow.scrollbarVisible, false, "scrollable=false keeps a wrapper unscrolled")
window:Destroy()
fixedWindow:Destroy()

local Panel = require("src/panel")
local panelTargets = {}
local fakePanel = {
    dock = { scroll = { ScrollToChild = function(_, child, offset)
        panelTargets.dock, panelTargets.dockOffset = child, offset
    end } },
    overlay = { scroll = { ScrollToChild = function(_, child, offset)
        panelTargets.overlay, panelTargets.overlayOffset = child, offset
    end } },
}
local pairedChild = { dock = {}, overlay = {} }
Panel.ScrollToChild(fakePanel, pairedChild, 9)
expect(panelTargets.dock, pairedChild.dock, "panels scroll their dock child")
expect(panelTargets.overlay, pairedChild.overlay, "panels scroll their popout child")
expect(panelTargets.dockOffset, 9, "panels forward the dock inset")
expect(panelTargets.overlayOffset, 9, "panels forward the popout inset")

local trackerWindow = Window.new(parent, {
    title = "Achievement Tracker",
    width = 600,
    height = 600,
})
local trackerTabs = trackerWindow:AddTabs(
    { "General", "Debug" },
    { height = -20, heightAnchor = 1.0 }
)
local generalPage = trackerTabs:GetPage(1)
expect(
    trackerTabs.root.height,
    trackerWindow.content.height - 20,
    "anchored tab height preserves its negative parent offset"
)

for index = 1, 13 do
    generalPage:AddText({
        text = index == 13 and "Add server" or "Server row " .. index,
        height = 30,
        marginBottom = 8,
    })
end
expect(
    generalPage.scrollbarVisible,
    true,
    "tab page scrolling starts when tracker rows exceed the visible page"
)
generalPage:SetScrollPosition(10000)
local addRow = generalPage._managedFlowEntries[#generalPage._managedFlowEntries].component
expect(
    addRow.y + addRow.height - generalPage.scrollY <= generalPage._scroll.height,
    true,
    "the final add row is reachable at the bottom of the scroll range"
)
trackerWindow:Destroy()

local clippingWindow = Window.new(parent, { width = 500, height = 400 })
local clippingTabs = clippingWindow:AddTabs({ "NPCs", "Objects" }, { height = 260 })
local clippingPage = clippingTabs:GetPage(1)
local inputChanges = 0
local tabField = clippingPage:AddTextField({
    text = "26773, 31635", y = 40, width = 120,
    colour = 0x12345680, placeholderColour = 0x23456760,
    caretColour = 0x34567840, selectionColour = 0x45678920,
    onChange = function() inputChanges = inputChanges + 1 end,
})
tabField.root.errorCaretRGBA = 0x56789A80
clippingPage:SetContentHeight(1000)
clippingPage:SetScrollPosition(tabField.root.y)
expectInputClipped(tabField, false, "input touching the tab divider retains its text")
clippingPage:ScrollBy(1)
expectInputClipped(tabField, true, "partially clipped input text cannot draw over the tab divider")
clippingPage:SetScrollPosition(tabField.root.y + tabField.root.height)
expectInputClipped(tabField, true, "input text wholly above the tab page stays transparent")
clippingPage:SetScrollPosition(0)
expectInputClipped(tabField, false, "input text returns when fully inside the tab page")
tabField.root:SetPos(14, clippingPage._scroll.height - tabField.root.height + 1)
clippingPage:SetScrollPosition(0)
expectInputClipped(tabField, true, "input text crossing the lower tab page edge is transparent")
clippingPage:ScrollBy(1)
expectInputClipped(tabField, false, "input text exactly inside the lower edge is restored")
tabField.root:SetPos(14, 40)
clippingPage:SetScrollPosition(0)
clippingTabs:SetActive(2)
expectInputClipped(tabField, true, "inactive tab input text is transparent")
clippingTabs:SetActive(1)
expectInputClipped(tabField, false, "reactivating the tab restores its input text")
tabField.root.hidden = true
clippingPage:SetScrollPosition(41)
clippingPage:SetScrollPosition(0)
expect(tabField.root.hidden, true, "clipping does not unhide a caller-hidden input")
tabField.root.hidden = false

local nestedTabs = clippingPage:AddTabs({ "Nested" }, { y = 60, height = 200 })
local nestedPage = nestedTabs:GetPage(1)
local nestedField = nestedPage:AddTextField({ text = "Nested input", y = 20, width = 120 })
nestedPage:SetContentHeight(500)
local nestedTop = nestedTabs.root.y + nestedTabs.content.y + nestedField.root.y
clippingPage:SetScrollPosition(nestedTop)
expectInputClipped(nestedField, false, "nested input text at its parent viewport edge is visible")
clippingPage:ScrollBy(1)
expectInputClipped(nestedField, true, "parent scrolling clips nested tab input text")
nestedPage:SetScrollPosition(0)
expectInputClipped(nestedField, true, "child refresh cannot undo parent text clipping")
clippingPage:SetScrollPosition(0)
expectInputClipped(nestedField, false, "parent scrolling back restores nested input text")
nestedPage:SetScrollPosition(nestedField.root.y + 1)
clippingPage:SetScrollPosition(10)
expectInputClipped(nestedField, true, "parent refresh cannot undo child text clipping")
nestedPage:SetScrollPosition(0)
expectInputClipped(nestedField, false, "nested input text restores only when all viewports allow it")
clippingPage:SetScrollPosition(0)
clippingWindow:SetContentHeight(1000)
local windowTop = clippingTabs.root.y + clippingTabs.content.y + nestedTop
clippingWindow:SetScrollPosition(windowTop + 1)
expectInputClipped(nestedField, true, "window scrolling updates deeply nested tab input text clipping")
clippingWindow:SetScrollPosition(0)
expectInputClipped(nestedField, false, "deeply nested input text returns after window scrolling")
expect(tabField:GetText(), "26773, 31635", "clipping preserves input contents")
expect(inputChanges, 0, "clipping does not emit input changes")
expect(tabField.root.text.rgba, 0x12345680, "clipping restores custom text colour and alpha")
expect(tabField.root.text.isShadowed, true, "clipping restores the text shadow")
expect(tabField.root.emptyTextRGBA, 0x23456760, "clipping restores placeholder colour")
expect(tabField.root.caretRGBA, 0x34567840, "clipping restores caret colour")
expect(tabField.root.errorCaretRGBA, 0x56789A80, "clipping restores error caret colour")
expect(tabField.root.selectionHighlightRGBA, 0x45678920, "clipping restores selection colour")
clippingWindow:Destroy()

-- Exercise real paired content methods on two independent scroll/layout owners.
local dockView = SimpleView.new(parent, { width = 300, height = 400 })
local overlayView = SimpleView.new(parent, { width = 360, height = 400 })
local inlinePanel = setmetatable({
    dockOwner = dockView,
    overlayOwner = overlayView,
    dock = { content = dockView.content },
    overlay = { content = overlayView.content },
}, Panel)
local prefix = inlinePanel:AddText("Temporary row")
local title = inlinePanel:AddTitle("Options")
local checks = inlinePanel:AddCheckboxButton({ "One", "Two" }, { inline = true })
local label = inlinePanel:AddText("Name:")
local field = inlinePanel:AddTextField({ inline = true })
local following = inlinePanel:AddText("Next row")

local function checkInlineLayout()
    for _, side in ipairs({ "dock", "overlay" }) do
        local heading, boxes = title[side], checks[side]
        expect(boxes.root.y >= heading.y + heading.height + 8, true,
            side .. " inline checkboxes start below the title and its gap")
        expect(boxes.items[1].row.y, boxes.items[2].row.y,
            side .. " checkbox choices still share one row")
        local text, input = label[side], field[side].root
        expect(input.y, text.y, side .. " inline text field shares the label row")
        expect(input.x, text.x + font:GetStringWidth(text.content) + 4 + 8,
            side .. " inline text field follows the rendered label")
        expect(input.x + input.width, text.parent.width - 14,
            side .. " default inline field fills only the remaining row width")
        expect(following[side].y >= input.y + input.height + 8, true,
            side .. " following text clears the taller inline field")
    end
end
checkInlineLayout()
prefix:Destroy()
checkInlineLayout()

local fixedLabel = inlinePanel:AddText({ text = "Fixed:", width = 110 })
local fixedField = inlinePanel:AddTextField({ inline = true, width = 100 })
expect(fixedField.dock.root.x, fixedLabel.dock.x + 110 + 8,
    "explicit label width takes precedence over measured text")
following:Destroy()
expect(fixedField.dock.root.x, fixedLabel.dock.x + 110 + 8,
    "explicit label width is preserved during reflow")
checks:Destroy()
label:Destroy()
expect(field.dock.root.x, 14, "removing the label moves its field to the row start")
expect(field.dock.root.x + field.dock.root.width, dockView.content.width - 14,
    "removing the label expands the field to the remaining content width")
dockView:Destroy()
overlayView:Destroy()

-- Logout arrives after native interfaces are gone. Retained handles deliberately
-- reject every read/write so this exercises the unsafe path, not tolerant mocks.
local callbacks = {}
Event = { Logic = {
    Subscribe = function(key, callback) callbacks[key] = callback end,
    Unsubscribe = function(key) callbacks[key] = nil end,
} }
Keyboard = { IsAvailable = function() return false end }
config.Cursor.CURSOR_OPEN = { id = 1 }
package.loaded["src/core/sprites"].CONTENT_FRAME = {}
package.loaded["src/core/sprites"].HUD_WINDOW = {}
package.loaded["src/core/sprites"].SPRITE_BUTTONS = {
    POPOUT = { neutral = 1 }, DOCK = { neutral = 1 },
}
local closed = 0
local logoutWindow = Window.new(parent, {
    title = "Logout", width = 400, height = 300,
    rowBackgroundColours = { 0x24211EFF },
    onClose = function() closed = closed + 1 end,
})
local logoutTabs = logoutWindow:AddTabs({ "Markers" }, { height = 200 })
local logoutPage = logoutTabs:GetPage(1)
logoutPage:AddText("Marker settings")
logoutPage:AddTextField({ text = "Unsaved label" })
local logoutPanel = logoutPage:AddPanel({ width = 250, height = 100 })
logoutPanel:AddText("Preset")
local logoutButton = logoutWindow:AddRibbonButton(1, function() end, { tooltip = "Markers" })
logoutButton.tooltip:Show()
logoutWindow._scroll.dragStart = { mouseY = 10 }
Interfaces.unload()
logoutButton:SetActive(false)
logoutWindow:Close()
logoutWindow:Destroy()
logoutWindow:Destroy()
expect(closed, 1, "logout close still invokes the plugin callback")
expect(logoutWindow.root, nil, "logout releases the dead window")
expect(next(callbacks), nil, "logout removes panel event subscriptions")

local loginParent = component(nil, "parent")
loginParent.width, loginParent.height = 640, 480
local loginWindow = Window.new(loginParent, { width = 300, height = 150 })
loginWindow:Close()
loginWindow:Show()
expect(loginWindow.root.hidden, false, "new login creates a usable window")
loginWindow:Destroy()

print("scroll_test: ok")
