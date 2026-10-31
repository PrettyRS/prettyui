local Components = require("src/core/components")
local clamp = require("src/core/math").clamp
local InterfaceMouse = require("src/core/mouse")
local Sprites = require("src/core/sprites")

local Scroll = {}
Scroll.__index = Scroll

local BAR_WIDTH = 16
local BAR_GAP = 2
local ARROW_SIZE = 16
local END_SIZE = 5
local MIN_THUMB_HEIGHT = 24
local DEFAULT_CHILD_TOP_OFFSET = 12
local scrollByContent = {}

local function topRelativeTo(root, ancestor)
    local top = 0
    local current = root
    while current ~= nil and current ~= ancestor do
        top = top + (current.y or 0)
        current = current.parent
    end
    if current ~= ancestor then return nil end
    return top
end

local function inputIsClipped(controller, root)
    local top = topRelativeTo(root, controller.content)
    if top == nil then return false end
    local height = root.height or 0
    while controller do
        top = top - controller.scrollY
        if (controller.isVisible and not controller.isVisible()) or
            top < 0 or top + height > controller.height then
            return true
        end
        local parent = controller.parentScroll
        if parent then
            local offset = topRelativeTo(controller.content, parent.content)
            if offset == nil then return false end
            top = top + offset
        end
        controller = parent
    end
    return false
end

local function sprite(parent, spriteID)
    local component = Components.new(ui.Sprite, parent)
    component.spriteID = spriteID
    component.clickthrough = false
    return component
end

local function findOwnerWindow(context)
    while context do
        if context.ownerWindow then return context.ownerWindow end
        context = context.parentContext
    end
    return nil
end

function Scroll.findOwnerWindow(context)
    return findOwnerWindow(context)
end

local function buildScroll(parent, options)
    options = options or {}

    local self = setmetatable({}, Scroll)
    self.parent = parent
    self.scrollable = options.scrollable ~= false
    self.scrollStep = options.scrollStep or 32
    self.requestedContentHeight = math.max(0, options.contentHeight or 0)
    self.scrollY = 0
    self.thumbCaptureExpanded = false
    self.parentWheelHandler = options._onScrollWheel
    self.ownerWindow = options.ownerWindow or findOwnerWindow(options.parentContext)
    self.overlayParent = options.overlayParent or parent
    self.overlayInterfaceID = self.overlayParent.interfaceID
    self.position = options.position
    self.isVisible = options.isVisible
    self.onLayout = options.onLayout
    self.clickthrough = options.clickthrough == true
    self.clipTargets = {}
    self.childScrolls = {}

    self.root = Components.new(ui.Layer, parent)
    self.interfaceID = self.root.interfaceID
    self.root:SetPos(
        options.x or 0,
        options.y or 0,
        options.xAnchor or 0,
        options.yAnchor or 0
    )
    self.root:SetSize(
        options.width or 300,
        options.height or 240,
        options.widthAnchor or 0,
        options.heightAnchor or 0
    )
    self.root.clickthrough = self.clickthrough

    self.viewport = Components.new(ui.Layer, self.root)
    self.viewport.clickthrough = self.clickthrough
    self.viewport.enabled = not self.clickthrough

    self.content = Components.new(ui.Layer, self.viewport)
    self.content.clickthrough = self.clickthrough
    self.content.enabled = not self.clickthrough

    -- Follow native ancestry, not tooltip/overlay ancestry: popout surfaces have
    -- independent viewports even when they share a logical content owner.
    local ancestor = parent
    while ancestor do
        local controller = scrollByContent[ancestor]
        if controller then
            self.parentScroll = controller
            controller.childScrolls[self] = true
            break
        end
        ancestor = ancestor.parent
    end
    scrollByContent[self.content] = self

    self.upArrow = sprite(self.root, Sprites.SCROLL_ARROW_UP)
    self.upArrow.clickthrough = self.clickthrough
    self.upArrow.enabled = not self.clickthrough
    self.upArrow:SetPos(-BAR_WIDTH, 0, 1.0)
    self.upArrow:SetSize(BAR_WIDTH, ARROW_SIZE)
    self.upArrow:Subscribe(ui.Hook.ONCLICK, function()
        self:ScrollBy(-self.scrollStep)
        return false
    end)

    self.downArrow = sprite(self.root, Sprites.SCROLL_ARROW_DOWN)
    self.downArrow.clickthrough = self.clickthrough
    self.downArrow.enabled = not self.clickthrough
    self.downArrow:SetPos(-BAR_WIDTH, -ARROW_SIZE, 1.0, 1.0)
    self.downArrow:SetSize(BAR_WIDTH, ARROW_SIZE)
    self.downArrow:Subscribe(ui.Hook.ONCLICK, function()
        self:ScrollBy(self.scrollStep)
        return false
    end)

    self.track = Components.new(ui.Layer, self.root)
    self.track.clickthrough = self.clickthrough
    self.track.enabled = not self.clickthrough
    self.track:SetPos(-BAR_WIDTH, ARROW_SIZE, 1.0)

    self.trackTop = sprite(self.track, Sprites.SCROLL_TRACK_TOP)
    self.trackTop:SetSize(BAR_WIDTH, END_SIZE)
    self.trackCentre = sprite(self.track, Sprites.SCROLL_TRACK_CENTRE)
    self.trackCentre:SetPos(0, END_SIZE)
    self.trackCentre.isTiling = true
    self.trackBottom = sprite(self.track, Sprites.SCROLL_TRACK_BOTTOM)
    self.trackBottom:SetPos(0, -END_SIZE, 0, 1.0)
    self.trackBottom:SetSize(BAR_WIDTH, END_SIZE)

    self.thumb = Components.new(ui.Layer, self.track)
    self.thumb.clickthrough = true
    self.thumbTop = sprite(self.thumb, Sprites.SCROLL_THUMB_TOP)
    self.thumbTop.clickthrough = true
    self.thumbTop:SetSize(BAR_WIDTH, END_SIZE)
    self.thumbCentre = sprite(self.thumb, Sprites.SCROLL_THUMB_CENTRE)
    self.thumbCentre.clickthrough = true
    self.thumbCentre:SetPos(0, END_SIZE)
    self.thumbCentre.isTiling = true
    self.thumbBottom = sprite(self.thumb, Sprites.SCROLL_THUMB_BOTTOM)
    self.thumbBottom.clickthrough = true
    self.thumbBottom:SetPos(0, -END_SIZE, 0, 1.0)
    self.thumbBottom:SetSize(BAR_WIDTH, END_SIZE)

    self.thumbDrag = Components.new(ui.Layer, self.overlayParent)
    self.thumbDrag.clickthrough = self.clickthrough
    self.thumbDrag.enabled = not self.clickthrough
    self.thumbDrag:MoveToFront()
    if self.ownerWindow then
        self.ownerWindow:_RegisterOverlay(self.thumbDrag, function()
            return self:_ShouldShow()
        end, function()
            self:_LayoutThumbDrag()
        end)
    end

    self.thumbDrag:Subscribe(ui.Hook.ONCLICK, function(component, x, y)
        if self.clickthrough or not self.scrollbarVisible then return true end
        InterfaceMouse.BeginScreenCapture(component, x, y)
        local mouse = InterfaceMouse.GetPosition(component, x, y)
        if mouse then self.dragStart = { mouseY = mouse.y, scrollY = self.scrollY } end
        self.thumbCaptureExpanded = false
        return false
    end)
    self.thumbDrag:Subscribe(ui.Hook.ONHOLD, function(component, x, y)
        return self:_UpdateDrag(component, x, y)
    end)
    self.thumbDrag:Subscribe(ui.Hook.ONRELEASE, function() return self:_StopDrag() end)
    self.thumbDrag:Subscribe(ui.Hook.ONDRAGCOMPLETE, function() return self:_StopDrag() end)

    self.track:Subscribe(ui.Hook.ONCLICK, function(_, _, clickY)
        local thumbTravel = self.trackHeight - self.thumbHeight
        local maxScroll = self.scrollHeight - self.height
        if thumbTravel > 0 then
            self:SetScrollPosition((clickY - self.thumbHeight / 2) * maxScroll / thumbTravel)
        end
        return false
    end)

    local function onWheel(component, delta)
        if self.scrollable and self.scrollbarVisible then
            local previous = self.scrollY
            self:ScrollBy(delta * self.scrollStep)
            if self.scrollY ~= previous then return false end
        end
        if self.parentWheelHandler then return self.parentWheelHandler(component, delta) end
        return true
    end
    self._onScrollWheel = onWheel
    self.viewport:Subscribe(ui.Hook.ONSCROLLWHEEL, onWheel)
    self.content:Subscribe(ui.Hook.ONSCROLLWHEEL, onWheel)
    self.track:Subscribe(ui.Hook.ONSCROLLWHEEL, onWheel)
    self.thumbDrag:Subscribe(ui.Hook.ONSCROLLWHEEL, onWheel)
    self.upArrow:Subscribe(ui.Hook.ONSCROLLWHEEL, onWheel)
    self.downArrow:Subscribe(ui.Hook.ONSCROLLWHEEL, onWheel)

    self:Refresh()
    return self
end

function Scroll.new(parent, options)
    return Components.withBatch(parent, function()
        return buildScroll(parent, options)
    end)
end

local function syncOwner(owner, controller)
    owner.viewport = controller.viewport
    owner.content = controller.content
    owner.contentWidth = controller.contentWidth
    owner.contentHeight = controller.contentHeight
    owner.scrollbarVisible = controller.scrollbarVisible
    owner.scrollable = controller.scrollable
    owner.scrollY = controller.scrollY
    owner._onScrollWheel = controller._onScrollWheel
end

-- Content hosts own their styling and geometry while this attachment owns the
-- viewport, scrollbar, and shared public state.
function Scroll.attach(owner, parent, options)
    local attachedOptions = {}
    for key, value in pairs(options or {}) do attachedOptions[key] = value end
    local afterLayout = attachedOptions.onLayout
    attachedOptions.onLayout = function(controller)
        syncOwner(owner, controller)
        if afterLayout then afterLayout(controller) end
    end

    local controller = Scroll.new(parent, attachedOptions)
    owner._scroll = controller
    syncOwner(owner, controller)
    return controller
end

-- Install the common scroll API once on a host class instead of allocating
-- forwarding closures for every instance.
function Scroll.install(class)
    class.SetContentHeight = function(self, contentHeight)
        return self._scroll:SetContentHeight(contentHeight)
    end
    class.SetScrollPosition = function(self, position)
        return self._scroll:SetScrollPosition(position)
    end
    class.ScrollBy = function(self, delta)
        return self._scroll:ScrollBy(delta)
    end
    class.ScrollToChild = function(self, child, topOffset)
        return self._scroll:ScrollToChild(child, topOffset)
    end
    class.SetScrollable = function(self, scrollable)
        return self._scroll:SetScrollable(scrollable)
    end
end

-- Native input text can escape ancestor clipping. Suppress only its content
-- visuals at viewport boundaries; the field frame retains normal native clipping.
function Scroll:RegisterClipTarget(target)
    if target == nil or target.root == nil then return end
    table.insert(self.clipTargets, target)
    self:_RefreshClipTargets()
end

function Scroll:UnregisterClipTarget(target)
    for index = #self.clipTargets, 1, -1 do
        if self.clipTargets[index] == target then
            if target.root and ui.Interfaces:GetInterface(target.interfaceID) ~= nil then
                target:_SetContentClipped(false)
            end
            table.remove(self.clipTargets, index)
        end
    end
end

function Scroll:_RefreshClipTargets()
    for index = #self.clipTargets, 1, -1 do
        local target = self.clipTargets[index]
        local root = target.root
        if root == nil then
            table.remove(self.clipTargets, index)
        else
            target:_SetContentClipped(inputIsClipped(self, root))
        end
    end
    for child in pairs(self.childScrolls) do child:_RefreshClipTargets() end
end

function Scroll:_ShouldShow()
    return self.scrollbarVisible and
        (self.isVisible == nil or self.isVisible() == true)
end

function Scroll:_AbsolutePosition()
    if self.position then return self.position(self.root) end
    return self.root.x or 0, self.root.y or 0
end

function Scroll:_LayoutThumbDrag()
    if self.thumbDrag == nil or self.root == nil or self.track == nil or self.thumb == nil or
        ui.Interfaces:GetInterface(self.interfaceID) == nil or
        ui.Interfaces:GetInterface(self.overlayInterfaceID) == nil then return end
    -- The first ONHOLD expands this layer across the overlay parent so later
    -- events continue outside the scrollbar. Window overlay synchronization can
    -- run during SetScrollPosition; do not collapse the active capture back onto
    -- the visual thumb until release.
    if self.dragStart ~= nil then return end
    local rootX, rootY = self:_AbsolutePosition()
    self.thumbDrag:SetPos(
        rootX + (self.track.x or 0) + (self.thumb.x or 0),
        rootY + (self.track.y or 0) + (self.thumb.y or 0)
    )
    self.thumbDrag:SetSize(BAR_WIDTH, self.thumbHeight)
    self.thumbDrag.hidden = not self:_ShouldShow()
end

function Scroll:_Layout()
    self.width = math.max(1, self.root.width or 1)
    self.height = math.max(1, self.root.height or 1)
    self.contentHeight = self.requestedContentHeight
    self.scrollHeight = math.max(self.contentHeight, self.height)
    self.scrollbarVisible = self.scrollable and self.requestedContentHeight > self.height
    self.contentWidth = math.max(
        1,
        self.width - (self.scrollbarVisible and BAR_WIDTH + BAR_GAP or 0)
    )
    self.trackHeight = math.max(1, self.height - ARROW_SIZE * 2)
    self.thumbHeight = clamp(
        math.floor(self.trackHeight * self.height / self.scrollHeight),
        math.min(MIN_THUMB_HEIGHT, self.trackHeight),
        self.trackHeight
    )

    self.viewport:SetSize(self.contentWidth, 0, 0, 1.0)
    self.viewport:SetScrollSize(self.contentWidth, self.scrollHeight)
    self.content:SetSize(self.contentWidth, self.scrollHeight)
    self.track:SetSize(BAR_WIDTH, self.trackHeight)
    self.trackCentre:SetSize(BAR_WIDTH, math.max(1, self.trackHeight - END_SIZE * 2))
    self.thumb:SetSize(BAR_WIDTH, self.thumbHeight)
    self.thumbCentre:SetSize(BAR_WIDTH, math.max(1, self.thumbHeight - END_SIZE * 2))

    self.track.hidden = not self.scrollbarVisible
    self.upArrow.hidden = not self.scrollbarVisible
    self.downArrow.hidden = not self.scrollbarVisible
    self:SetScrollPosition(self.scrollY)
end

function Scroll:Refresh()
    if self.root then self:_Layout() end
end

function Scroll:SetScrollPosition(position)
    local maxScroll = self.scrollable and math.max(0, self.scrollHeight - self.height) or 0
    self.scrollY = clamp(math.floor(position or 0), 0, maxScroll)
    self.viewport:SetScrollPos(0, self.scrollY)
    self:_RefreshClipTargets()

    local thumbY = 0
    local thumbTravel = self.trackHeight - self.thumbHeight
    if maxScroll > 0 and thumbTravel > 0 then
        thumbY = math.floor(self.scrollY / maxScroll * thumbTravel)
    end
    self.thumb:SetPos(0, thumbY)
    if self.dragStart == nil then self:_LayoutThumbDrag() end
    if self.onLayout then self.onLayout(self) end
    if self.ownerWindow and self.ownerWindow.root then
        self.ownerWindow:_SyncOverlays(self.ownerWindow.root.hidden == true)
    end
end

function Scroll:_UpdateDrag(component, x, y)
    local mouse = InterfaceMouse.GetPosition(component, x, y)
    if self.dragStart and mouse then
        if not self.thumbCaptureExpanded then
            self.thumbCaptureExpanded = true
            self.dragStart.mouseY = mouse.y
            self.dragStart.scrollY = self.scrollY
            self.thumbDrag:SetPos(0, 0)
            self.thumbDrag:SetSize(0, 0, 1.0, 1.0)
            self.thumbDrag:MoveToFront()
            return false
        end

        local thumbTravel = self.trackHeight - self.thumbHeight
        local maxScroll = self.scrollHeight - self.height
        if thumbTravel > 0 then
            local nextPosition = clamp(math.floor(
                self.dragStart.scrollY +
                (mouse.y - self.dragStart.mouseY) * maxScroll / thumbTravel
            ), 0, maxScroll)
            if nextPosition ~= self.scrollY then self:SetScrollPosition(nextPosition) end
        end
    end
    return false
end

function Scroll:_StopDrag()
    InterfaceMouse.EndCapture(self.thumbDrag)
    self.dragStart = nil
    self.thumbCaptureExpanded = false
    self:_LayoutThumbDrag()
    return false
end

function Scroll:ScrollBy(delta)
    self:SetScrollPosition(self.scrollY + delta)
end

function Scroll:ScrollToChild(child, topOffset)
    local root = child and (child.root or child) or nil
    if root == nil or root.y == nil then return end
    if topOffset == nil then topOffset = DEFAULT_CHILD_TOP_OFFSET end
    self:SetScrollPosition(root.y - topOffset)
end

function Scroll:SetContentHeight(contentHeight)
    self.requestedContentHeight = math.max(0, math.floor(contentHeight or 0))
    self:_Layout()
end

function Scroll:SetScrollable(scrollable)
    self.scrollable = scrollable ~= false
    if not self.scrollable then self.scrollY = 0 end
    self:_Layout()
end

function Scroll:SetClickthrough(clickthrough)
    self.clickthrough = clickthrough == true
    self.root.clickthrough = self.clickthrough
    self.viewport.clickthrough = self.clickthrough
    self.viewport.enabled = not self.clickthrough
    self.content.clickthrough = self.clickthrough
    self.content.enabled = not self.clickthrough
    self.track.clickthrough = self.clickthrough
    self.track.enabled = not self.clickthrough
    self.upArrow.clickthrough = self.clickthrough
    self.upArrow.enabled = not self.clickthrough
    self.downArrow.clickthrough = self.clickthrough
    self.downArrow.enabled = not self.clickthrough
    self.thumbDrag.clickthrough = self.clickthrough
    self.thumbDrag.enabled = not self.clickthrough
    self:_LayoutThumbDrag()
end

function Scroll:SetSize(width, height, widthAnchor, heightAnchor)
    self.root:SetSize(width, height, widthAnchor or 0, heightAnchor or 0)
    self:_Layout()
end

function Scroll:Destroy()
    self:_StopDrag()
    scrollByContent[self.content] = nil
    if self.parentScroll then
        self.parentScroll.childScrolls[self] = nil
        self.parentScroll = nil
    end
    for child in pairs(self.childScrolls) do child.parentScroll = nil end
    self.childScrolls = {}
    if self.thumbDrag then
        if self.ownerWindow then self.ownerWindow:_UnregisterOverlay(self.thumbDrag) end
        if ui.Interfaces:GetInterface(self.overlayInterfaceID) ~= nil then self.thumbDrag:Destroy() end
        self.thumbDrag = nil
    end
    if self.root then
        if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.root:Destroy() end
        self.root = nil
    end
    self.clipTargets = {}
    self.ownerWindow = nil
    self.overlayParent = nil
    self.parent = nil
end

return Scroll
