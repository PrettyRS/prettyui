local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function moveInRenderOrder(component, front)
    local siblings = component.parent and component.parent.renderOrder
    if not siblings then return end
    for index, sibling in ipairs(siblings) do
        if sibling == component then table.remove(siblings, index); break end
    end
    table.insert(siblings, front and #siblings + 1 or 1, component)
end

-- Resolve native size anchors on access, including after an ancestor changes size.
local function component(parent, categoryID, dynamicID)
    local value = { parent = parent, x = 0, y = 0, hidden = false, subscriptions = {},
        opConfig = { ClearOpCursors = function() end, SetOpCursor = function() end }, cursorConfig = {} }
    setmetatable(value, { __index = function(self, key)
        if key == "width" then return (self.w or 0) + (parent and parent.width or 0) * (self.wa or 0) end
        if key == "height" then return (self.h or 0) + (parent and parent.height or 0) * (self.ha or 0) end
    end })
    function value:SetPos(x, y) self.x, self.y = x, y end
    function value:SetY(y) self.y = y end
    function value:SetSize(w, h, wa, ha) self.w, self.h, self.wa, self.ha = w, h, wa, ha end
    function value:SetWidth(w, wa) self.w, self.wa = w, wa end
    function value:SetHeight(h, ha) self.h, self.ha = h, ha end
    function value:SetScrollSize(w, h) self.scrollWidth, self.scrollHeight = w, h end
    function value:SetScrollPos(x, y) self.scrollX, self.scrollY = x, y end
    function value:Subscribe(hook, name, callback) self.subscriptions[hook] = callback or name end
    function value:Unsubscribe(hook) self.subscriptions[hook] = nil end
    function value:MoveToFront() moveInRenderOrder(self, true) end
    function value:MoveToBack() moveInRenderOrder(self, false) end
    function value:Destroy() self.destroyed = true end
    Interfaces.component(value, parent, categoryID, dynamicID)
    if parent then
        -- Exercise a native default order where category-zero content precedes
        -- nonzero artwork, rather than assuming construction order wins.
        local siblings = parent.renderOrder or {}
        parent.renderOrder = siblings
        local position = #siblings + 1
        for index, sibling in ipairs(siblings) do
            if sibling.categoryID > value.categoryID or
                (sibling.categoryID == value.categoryID and sibling.dynamicID > value.dynamicID) then
                position = index
                break
            end
        end
        table.insert(siblings, position, value)
    end
    return value
end

local enum = setmetatable({}, { __index = function(_, key) return key end })
ui = {
    Layer = { new = component }, Sprite = { new = component },
    Text = { new = component }, Rectangle = { new = component },
    Hook = enum, AlignMode = enum,
}
id = { Sprite = enum, Font = enum }
local font = {
    baseline = 18,
    GetStringLineCount = function() return 1 end,
    GetStringWidth = function(_, text) return #text * 7 end,
}
config = { Cursor = enum, Font = { MUSEO_SANS_15PT_REGULAR = font, CINZEL_13PT_BOLD = font } }
Keyboard = { IsAvailable = function() return false end }
Event = { Logic = { Subscribe = function() end, Unsubscribe = function() end } }

local Window = require("src/window")
local Panel = require("src/panel")
local SimpleView = require("src/simple_view")
local parent = component()
parent:SetSize(1000, 800)

local window = Window.new(parent, { title = "Resize", width = 400, height = 300, minHeight = 1 })
local section = window:AddCollapseButton("Details", { resizeParent = true })
section:AddText({ text = "Body", height = 80 })
local following = window:AddText({ text = "Following", height = 24 })
local callbackHeight
section.onToggle = function() callbackHeight = window.root.height end
section:SetExpanded(true)
local expandedHeight = window.root.height
expect(expandedHeight, window.contentHeight + 40, "window fits content plus title and borders")
expect(window.root.width, 400, "fitting preserves width")
expect(callbackHeight, expandedHeight, "onToggle observes resized parent")
expect(window.scrollbarVisible, false, "expanded content fits without overflow")
local expandedY = following.y
section.root.subscriptions[ui.Hook.ONCLICK]()
expect(window.root.height, expandedHeight - 84, "clicking closed shrinks the window")
expect(following.y, expandedY - 84, "following row reflows on close")
expect(window.scrollbarVisible, false, "closing leaves no stale overflow")
local collapsedHeight = window.root.height
for _ = 1, 3 do section:Toggle(); section:Toggle() end
expect(window.root.height, collapsedHeight, "repeated toggles do not drift")

local fixed = Window.new(parent, { width = 400, height = 300 })
local fixedSection = fixed:AddCollapseButton("Fixed")
fixedSection:AddText({ text = "Body", height = 500 })
fixedSection:Toggle()
expect(fixed.root.height, 300, "sections without opt-in keep the parent fixed")
expect(fixed.scrollbarVisible, true, "fixed parent retains scrolling")
fixedSection:Toggle()
expect(fixed.scrollbarVisible, false, "closing the last flow row clears overflow")

local limited = Window.new(parent, { width = 400, height = 140, minHeight = 140, maxHeight = 200 })
local limitedSection = limited:AddCollapseButton("Limited", { resizeParent = true })
limitedSection:AddText({ text = "Large", height = 400 })
limitedSection:Toggle()
expect(limited.root.height, 200, "maximum window height is respected")
expect(limited.scrollbarVisible, true, "content beyond maximum height remains scrollable")
limited:SetScrollPosition(1000)
limitedSection:Toggle()
expect(limited.root.height, 140, "minimum window height is respected")
expect(limited.scrollY, 0, "closing clamps stale scroll position")
limitedSection:Toggle()
expect(limited.root.height, 200, "reopening after clamping does not drift")

local conflicting = Window.new(parent, {
    width = 400, height = 300,
    minWidth = 220, maxWidth = 100,
    minHeight = 140, maxHeight = 80,
})
expect(conflicting.root.width, 220, "minimum width wins over a conflicting maximum at construction")
expect(conflicting.root.height, 140, "minimum height wins over a conflicting maximum at construction")
conflicting:SetSize(500, 400)
expect(conflicting.root.width, 220, "resizing cannot fall below the minimum width")
expect(conflicting.root.height, 140, "resizing cannot fall below the minimum height")
conflicting:Destroy()

local view = SimpleView.new(parent, { width = -100, widthAnchor = 1, height = 200 })
local first = view:AddCollapseButton("First", { resizeParent = true, expanded = true })
first:AddText({ text = "First body", height = 50 })
local second = view:AddCollapseButton("Second", { resizeParent = true, expanded = true })
second:AddText({ text = "Second body", height = 70 })
expect(view.root.height, view.contentHeight, "initially expanded content fits as it is populated")
local bothHeight = view.root.height
first:Toggle()
expect(view.root.height, bothHeight - 54, "closing one section preserves the other")
second:Toggle()
expect(view.root.height, bothHeight - 54 - 74, "closing the last section shrinks measured content")
parent:SetWidth(1100)
expect(view.root.width, 1000, "fitting preserves the parent's width anchor")

local inline = SimpleView.new(parent, { width = 500, height = 300 })
local inlineSection = inline:AddCollapseButton("Inline", { resizeParent = true, width = 100 })
inlineSection:AddText({ text = "Short", height = 30 })
inline:AddText({ text = "Tall neighbour", inline = true, height = 100, width = 100 })
inlineSection:Toggle()
local inlineHeight = inline.root.height
inlineSection:Toggle()
expect(inline.root.height, inlineHeight, "closing a shorter inline child preserves the row height")

local panel = Panel.new(parent, { width = 320, height = 200, popout = true })
local toggles = 0
local panelSection = panel:AddCollapseButton("Panel", { resizeParent = true,
    onToggle = function() toggles = toggles + 1 end })
panelSection:AddText({ text = "Panel body", height = 60 })
panelSection:Toggle()
local panelHeight = panel.height
expect(panel.dock.scroll.height, panel.dockOwner.contentHeight, "docked panel fits content")
expect(panel.overlay.scroll.height, panel.overlayOwner.contentHeight, "popout panel fits content")
expect(panelSection.dock.expanded, true, "proxy toggle opens dock section")
expect(panelSection.overlay.expanded, true, "proxy toggle opens overlay section")
expect(toggles, 1, "paired toggle notifies once")
panel:SetPoppedOut(true)
panelSection.overlay.root.subscriptions[ui.Hook.ONCLICK]()
expect(panel.height, panelHeight - 64, "clicking popout section shrinks the panel")
expect(panelSection.dock.expanded, false, "popout click synchronizes docked section")
expect(toggles, 2, "popout click notifies once")
panel:SetPoppedOut(false)
expect(panel.dock.root.height, panel.height, "docking restores the fitted height")

local tabs = window:AddTabs({ "One", "Two" }, { height = 200 })
local page = tabs:GetPage(1)
local tabSection = page:AddCollapseButton("Tab", { resizeParent = true })
tabSection:AddText({ text = "Tab body", height = 90 })
local afterTabs = window:AddText({ text = "After tabs", height = 24 })
local outerHeight = window.root.height
tabSection:Toggle()
expect(page._scroll.height, page.contentHeight, "tab container fits its page content")
local afterY = afterTabs.y
local tabHeight = tabs.root.height
tabSection:Toggle()
expect(tabs.root.height, tabHeight - 94, "closing resizes the tab container")
expect(afterTabs.y, afterY - 94, "resizing tabs reflows their following sibling")
expect(window.root.height, outerHeight, "resizing the immediate host leaves ancestors fixed")

local Components = require("src/core/components")
local autoWindow = Window.new(parent, { title = "Auto", categoryID = "auto" })
expect(autoWindow.root.categoryID, 0, "auto window root inherits native category zero")
expect(autoWindow.viewport.categoryID, 0, "auto window viewport remains raw-compatible")
expect(autoWindow.content.categoryID, 0, "auto window content remains raw-compatible")
expect(ui.Layer.new(autoWindow.content).categoryID, 0,
    "raw window child inherits category zero")
local autoSection = autoWindow:AddCollapseButton("Auto section")
expect(autoSection.root.categoryID, 0, "collapse root remains a raw-compatible host")
expect(autoSection.content.categoryID, 0, "collapse content remains a raw-compatible host")
expect(autoSection.label.categoryID > 0, true, "collapse controls use managed categories")
expect(ui.Layer.new(autoSection.content).categoryID, 0,
    "raw collapse extension inherits zero")
local autoTabs = autoWindow:AddTabs({ "Page" }, { height = 100 })
expect(autoTabs:GetPage(1).content.categoryID, 0,
    "nested tab page content remains raw-compatible")

local autoView = SimpleView.new(parent, { categoryID = "auto" })
expect(autoView.root.categoryID, 0, "auto SimpleView root remains raw-compatible")
expect(autoView.viewport.categoryID, 0, "auto SimpleView viewport remains raw-compatible")
expect(autoView.content.categoryID, 0, "auto SimpleView content remains raw-compatible")
expect(autoView.upArrow.categoryID > 0, true,
    "auto SimpleView controls use managed categories")
local autoPanel = Panel.new(parent, { categoryID = "auto", popout = true })
expect(autoPanel.dock.root.categoryID, 0, "auto Panel dock root is raw-compatible")
expect(autoPanel.overlay.root.categoryID, 0, "auto Panel overlay root is raw-compatible")
expect(autoPanel.content.categoryID, 0, "auto dock content is raw-compatible")
expect(autoPanel.overlayContent.categoryID, 0, "auto popout content is raw-compatible")
expect(ui.Layer.new(autoPanel.content).categoryID, 0, "raw dock child inherits zero")
expect(ui.Layer.new(autoPanel.overlayContent).categoryID, 0,
    "raw popout child inherits zero")
expect(autoPanel.dock.background.categoryID > 0, true,
    "auto Panel decorations use managed categories")
local function expectPanelForeground(panel_, pairedLabel)
    local surface = panel_.poppedOut and panel_.overlay or panel_.dock
    local label = panel_.poppedOut and pairedLabel.overlay or pairedLabel.dock
    local painted = {}
    local function paint(component_)
        if component_.hidden or component_.destroyed then return end
        painted[#painted + 1] = component_
        for _, child in ipairs(component_.renderOrder or {}) do paint(child) end
    end
    paint(surface.root)
    local backgroundIndex, labelIndex
    for index, component_ in ipairs(painted) do
        if component_ == surface.background then backgroundIndex = index end
        if component_ == label then labelIndex = index end
    end
    assert(backgroundIndex and labelIndex, "visible Panel paints both its background and content")
    assert(backgroundIndex < labelIndex, "Panel content must paint above its background across categories")
end

local panelLabel = autoPanel:AddText("Foreground content")
expectPanelForeground(autoPanel, panelLabel)
autoPanel:SetPoppedOut(true)
expectPanelForeground(autoPanel, panelLabel)
autoPanel:SetSize(360, 200)
expectPanelForeground(autoPanel, panelLabel)
autoPanel:SetPoppedOut(false)
expectPanelForeground(autoPanel, panelLabel)

local legacyOrderPanel = Panel.new(parent, { popout = true })
local legacyLabel = legacyOrderPanel:AddText("Legacy foreground")
expectPanelForeground(legacyOrderPanel, legacyLabel)
legacyOrderPanel:SetPoppedOut(true)
expectPanelForeground(legacyOrderPanel, legacyLabel)
legacyOrderPanel:Destroy()
local managedParent = Components.new(ui.Layer, autoWindow.root)
local layerNew = ui.Layer.new
local nativeCalls = 0
ui.Layer.new = function(...)
    nativeCalls = nativeCalls + 1
    return layerNew(...)
end
local mountedWindow, windowError = pcall(Window.new, managedParent, { categoryID = "auto" })
local mountedPanel, panelError = pcall(Panel.new, parent, {
    categoryID = "auto", overlayParent = managedParent, popout = true,
})
ui.Layer.new = layerNew
expect(mountedWindow, false, "auto Window rejects nonzero dynamic parent")
expect(mountedPanel, false, "auto Panel rejects nonzero overlay before dock creation")
expect(windowError:find("raw-compatible content requires a category-zero parent", 1, true) ~= nil,
    true, "auto Window reports a safe mounting alternative")
expect(panelError:find("raw-compatible content requires a category-zero parent", 1, true) ~= nil,
    true, "auto Panel reports a safe overlay alternative")
expect(nativeCalls, 0, "rejected content constructors do not enter native Layer.new")
local originalLayer = ui.Layer.new
local partialCollapse
ui.Layer.new = function(owner, categoryID, dynamicID)
    if owner == partialCollapse and categoryID == nil then
        error("late collapse content failure")
    end
    local layer = originalLayer(owner, categoryID, dynamicID)
    if owner == parent then partialCollapse = layer end
    return layer
end
local collapseBuilt, collapseError = pcall(
    require("src/collapse_button").new, parent, "Failure", { categoryID = "auto" })
ui.Layer.new = originalLayer
expect(collapseBuilt, false, "late collapse content failure propagates")
expect(collapseError:find("late collapse content failure", 1, true) ~= nil,
    true, "collapse failure retains the original constructor error")
expect(partialCollapse.destroyed, true,
    "failed direct CollapseButton construction destroys its partial root")

local nativeHost = ui.Layer.new(parent)
local legacyParent = ui.Layer.new(nativeHost, 234, 0)
local legacyWindow = Window.new(legacyParent, { title = "Legacy" })
expect(legacyWindow.root.categoryID, legacyParent.categoryID,
    "legacy Window keeps inherited native category")
legacyWindow:Destroy()
autoPanel:Destroy()
autoView:Destroy()
autoWindow:Destroy()

window:Destroy()
fixed:Destroy()
limited:Destroy()
view:Destroy()
inline:Destroy()
panel:Destroy()
print("collapse_resize_test: window limits, repeated toggles, inline flow, anchors, panels and tabs passed")
