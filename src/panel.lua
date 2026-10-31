local Components = require("src/core/components")
local Sprites = require("src/core/sprites")
local ColourPicker = require("src/colour_picker")
local ComboBox = require("src/combo_box")
local ContentMethods = require("src/core/content_methods")
local Cursor = require("src/core/cursor")
local InterfaceMouse = require("src/core/mouse")
local List = require("src/list")
local Layout = require("src/core/layout")
local Scroll = require("src/core/scroll")
local RowBackgrounds = require("src/core/row_backgrounds")
local Slider = require("src/slider")
local TextField = require("src/text_field")
local Tabs = require("src/tabs")
local Tooltip = require("src/tooltip")
local Wheel = require("src/core/wheel")
local clamp = require("src/core/math").clamp
local DragFeedback = require("src/core/drag_feedback")
local DragBounds = require("src/core/drag_bounds")
local Resize = require("src/core/resize")

local Panel = {}
Panel.__index = Panel

local PanelContent = {}
PanelContent.__index = PanelContent
Scroll.install(PanelContent)
local function refreshPanelRows(panel, surface, owner, key)
    RowBackgrounds.clear(panel[key], surface.interfaceID)
    panel[key] = RowBackgrounds.apply(
        surface.content,
        surface.container.height,
        owner,
        panel.rowBackgroundColours,
        panel.rowBackgroundEdgeToEdge)
end

function PanelContent:RefreshRowBackgrounds()
    local panel = self._rowBackgroundPanel
    local surface = self._rowBackgroundSurface
    local key = self._rowBackgroundKey
    if panel == nil or surface == nil or key == nil then return end
    refreshPanelRows(panel, surface, self, key)
end


local BORDER_SIZE = 4
local TOGGLE_SIZE = 20
local TOGGLE_INSET = 4
local DEFAULT_WIDTH = 300
local DEFAULT_HEIGHT = 160
local DEFAULT_POPOUT_X = 80
local DEFAULT_POPOUT_Y = 80
local DRAG_EVENT_ID = "prettyui_panel_drag"
local dragPanels = {}

local function isAltDown()
    return Keyboard.IsAvailable() and not Keyboard.IsBlocked() and Keyboard.IsAltDown()
end

local function pollAltDrag()
    local active = isAltDown()
    for panel in pairs(dragPanels) do
        if panel.dockBounds then panel.dockBounds:Refresh() end
        if panel.overlayBounds then panel.overlayBounds:Refresh() end
        panel:_SetAltDragActive(active)
    end
end

local function registerAltDrag(panel)
    local wasEmpty = next(dragPanels) == nil
    dragPanels[panel] = true
    if wasEmpty then Event.Logic.Subscribe(DRAG_EVENT_ID, pollAltDrag) end
end

local function unregisterAltDrag(panel)
    dragPanels[panel] = nil
    if next(dragPanels) == nil then Event.Logic.Unsubscribe(DRAG_EVENT_ID) end
end

local function clampAlpha(value)
    return clamp(tonumber(value) or 1, 0, 1)
end

local function copyOptions(value)
    local copy = {}
    if type(value) == "table" then
        for key, option in pairs(value) do copy[key] = option end
    end
    return copy
end

local function sprite(parent, spriteID)
    local component = Components.new(ui.Sprite, parent)
    component.spriteID = spriteID
    component.clickthrough = true
    return component
end

local function createSurface(parent, options)
    local surface = {}
    local frame = Sprites.HUD_WINDOW
    surface.root = Components.new(ui.Layer, parent)
    surface.interfaceID = surface.root.interfaceID
    surface.root:SetPos(options.x, options.y, options.xAnchor or 0, options.yAnchor or 0)
    surface.root:SetSize(options.width, options.height, options.widthAnchor or 0, options.heightAnchor or 0)
    surface.root.clickthrough = options.clickthrough == true

    surface.background = sprite(surface.root, frame.content)
    surface.background:SetPos(BORDER_SIZE, BORDER_SIZE)
    surface.background:SetSize(-BORDER_SIZE * 2, -BORDER_SIZE * 2, 1.0, 1.0)
    surface.background.isTiling = true
    surface.background.alpha = clampAlpha(options.backgroundAlpha)
    surface.background.clickthrough = options.clickthrough == true

    surface.top = sprite(surface.root, frame.top)
    surface.top:SetPos(BORDER_SIZE, 0)
    surface.top:SetSize(-BORDER_SIZE * 2, BORDER_SIZE, 1.0)
    surface.top.isTiling = true

    surface.bottom = sprite(surface.root, frame.bottom)
    surface.bottom:SetPos(BORDER_SIZE, -BORDER_SIZE, 0, 1.0)
    surface.bottom:SetSize(-BORDER_SIZE * 2, BORDER_SIZE, 1.0)
    surface.bottom.isTiling = true

    surface.right = sprite(surface.root, frame.side)
    surface.right:SetPos(-BORDER_SIZE, BORDER_SIZE, 1.0)
    surface.right:SetSize(BORDER_SIZE, -BORDER_SIZE * 2, 0, 1.0)
    surface.right.isTiling = true

    surface.left = sprite(surface.root, frame.side)
    surface.left:SetPos(0, BORDER_SIZE)
    surface.left:SetSize(BORDER_SIZE, -BORDER_SIZE * 2, 0, 1.0)
    surface.left.isTiling = true
    surface.right.isFlippedHorizontally = true

    surface.topRight = sprite(surface.root, frame.cornerTop)
    surface.topRight:SetPos(-BORDER_SIZE, 0, 1.0)
    surface.topRight:SetSize(BORDER_SIZE, BORDER_SIZE)
    surface.topRight.isFlippedHorizontally = true

    surface.topLeft = sprite(surface.root, frame.cornerTop)
    surface.topLeft:SetSize(BORDER_SIZE, BORDER_SIZE)

    surface.bottomRight = sprite(surface.root, frame.cornerBottom)
    surface.bottomRight:SetPos(-BORDER_SIZE, -BORDER_SIZE, 1.0, 1.0)
    surface.bottomRight:SetSize(BORDER_SIZE, BORDER_SIZE)
    surface.bottomRight.isFlippedHorizontally = true

    surface.bottomLeft = sprite(surface.root, frame.cornerBottom)
    surface.bottomLeft:SetPos(0, -BORDER_SIZE, 0, 1.0)
    surface.bottomLeft:SetSize(BORDER_SIZE, BORDER_SIZE)

    surface.container = Components.new(ui.Layer, surface.root)
    surface.container:SetPos(BORDER_SIZE, BORDER_SIZE)
    surface.container:SetSize(-BORDER_SIZE * 2, -BORDER_SIZE * 2, 1.0, 1.0)
    surface.container.clickthrough = options.clickthrough == true
    surface.container.enabled = options.clickthrough ~= true

    return surface
end

local function createToggle(surface, panel, popoutMode)
    local button = Components.new(ui.Sprite, surface.root)
    button:SetPos(-TOGGLE_SIZE - TOGGLE_INSET, TOGGLE_INSET, 1.0)
    button:SetSize(TOGGLE_SIZE, TOGGLE_SIZE)
    button.clickthrough = false
    local hovered = false
    local pressed = false

    local function update()
        local states = popoutMode and Sprites.PANEL_POPOUT_BUTTON or Sprites.PANEL_DOCK_BUTTON
        if pressed then
            button.spriteID = states.mousedown
        elseif hovered then
            button.spriteID = states.hovered
        else
            button.spriteID = states.neutral
        end
    end

    button:Subscribe(ui.Hook.ONMOUSEOVER, function()
        hovered = true
        update()
        return true
    end)
    button:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        hovered = false
        pressed = false
        update()
        return true
    end)
    button:Subscribe(ui.Hook.ONCLICK, function()
        pressed = true
        update()
        return false
    end)
    button:Subscribe(ui.Hook.ONRELEASE, function()
        local activate = pressed
        pressed = false
        update()
        if activate then panel:SetPoppedOut(popoutMode) end
        return false
    end)
    update()
    button:MoveToFront()
    return button
end

local function createDragLayer(parent, surface, panel)
    local layer = Components.new(ui.Layer, parent)
    layer:SetPos(surface.root.x, surface.root.y)
    layer:SetSize(surface.root.width, surface.root.height)
    layer.clickthrough = true
    layer.enabled = false
    layer.hidden = true

    layer:Subscribe(ui.Hook.ONCLICK, function(component, x, y)
        if not isAltDown() then return true end
        panel:_BeginDrag(surface, component, x, y)
        return false
    end)
    layer:Subscribe(ui.Hook.ONHOLD, function(component, x, y)
        return panel:_MoveDrag(component, x, y)
    end)
    layer:Subscribe(ui.Hook.ONDRAG, function(component, x, y)
        return panel:_MoveDrag(component, x, y)
    end)
    layer:Subscribe(ui.Hook.ONRELEASE, function()
        return panel:_StopDrag()
    end)
    layer:Subscribe(ui.Hook.ONDRAGCOMPLETE, function()
        return panel:_StopDrag()
    end)
    return layer
end

local addPairedKeybindField

local function pairObjects(panel, dock, overlay)
    local proxy = {}
    rawset(proxy, "dock", dock)
    rawset(proxy, "overlay", overlay)
    return setmetatable(proxy, {
        __index = function(_, key)
            if key == "dock" or key == "overlay" then return rawget(proxy, key) end
            local active = panel.poppedOut and overlay or dock
            local value = active[key]
            if type(value) ~= "function" then return value end
            if key == "AddKeybindField" then
                return function(_, options)
                    return addPairedKeybindField(panel, function(copied)
                        return pairObjects(panel, dock:AddKeybindField(copied), overlay:AddKeybindField(copied))
                    end, options)
                end
            end
            return function(_, ...)
                local dockResult = dock[key](dock, ...)
                local overlayResult = overlay[key](overlay, ...)
                local result = panel.poppedOut and overlayResult or dockResult
                if dockResult ~= nil and overlayResult ~= nil and
                    (type(dockResult) == "table" or type(dockResult) == "userdata") and
                    (type(overlayResult) == "table" or type(overlayResult) == "userdata") then
                    return pairObjects(panel, dockResult, overlayResult)
                end
                return result
            end
        end,
        __newindex = function(_, key, value)
            dock[key] = value
            overlay[key] = value
        end,
    })
end

-- Values are detached arrays, while listening belongs only to the visible field.
-- This also handles fields created through paired tab pages and collapse sections.
addPairedKeybindField = function(panel, create, options)
    local copied = copyOptions(options)
    local onChange = copied.onChange
    local proxy
    copied.onChange = function(field, value)
        local other = field == proxy.dock and proxy.overlay or proxy.dock
        other:SetValue(value, false)
        if onChange then onChange(proxy, value) end
    end
    proxy = create(copied)
    local function active()
        return panel.poppedOut and proxy.overlay or proxy.dock
    end
    rawset(proxy, "GetValue", function()
        return active():GetValue()
    end)
    rawset(proxy, "SetValue", function(_, value, notify)
        proxy.dock:SetValue(value, false)
        proxy.overlay:SetValue(value, false)
        if notify == true and onChange then onChange(proxy, active():GetValue()) end
    end)
    rawset(proxy, "StartListening", function()
        local other = panel.poppedOut and proxy.dock or proxy.overlay
        other:CancelListening()
        return active():StartListening()
    end)
    rawset(proxy, "IsListening", function()
        return active():IsListening()
    end)
    panel._keybindFields = panel._keybindFields or setmetatable({}, { __mode = "k" })
    panel._keybindFields[proxy] = true
    rawset(proxy, "Destroy", function()
        panel._keybindFields[proxy] = nil
        proxy.dock:Destroy()
        proxy.overlay:Destroy()
    end)
    return proxy
end

local function configureOwner(surface, options, context, overlayParent)
    local owner = setmetatable({}, PanelContent)
    local scroll = Scroll.attach(owner, surface.container, {
        width = 0,
        height = 0,
        widthAnchor = 1.0,
        heightAnchor = 1.0,
        contentHeight = options.contentHeight,
        scrollable = options.scrollable,
        scrollStep = options.scrollStep,
        _onScrollWheel = options._onScrollWheel,
        clickthrough = surface.root.clickthrough == true,
        parentContext = context,
        overlayParent = overlayParent,
        isVisible = function() return surface.root.hidden ~= true end,
        position = function(scrollRoot)
            local rootX = surface.root.x or 0
            local rootY = surface.root.y or 0
            if context then rootX, rootY = context.position(surface.root) end
            return rootX + (surface.container.x or 0) + (scrollRoot.x or 0),
                rootY + (surface.container.y or 0) + (scrollRoot.y or 0)
        end,
    })
    surface.scroll = scroll
    surface.viewport = scroll.viewport
    surface.content = scroll.content
    Layout.configure(owner, options.layout or options.textLayout)
    return owner
end

function PanelContent:_FitContent()
    local panel = self._rowBackgroundPanel
    panel:SetSize(panel.width, self.contentHeight + BORDER_SIZE * 2)
    panel:RefreshRowBackgrounds()
end

function Panel.getSize(options)
    options = options or {}
    return options.width or DEFAULT_WIDTH, options.height or DEFAULT_HEIGHT
end

local function buildPanel(parent, options, flowManaged, overlayParent)
    options = options or {}
    local width, height = Panel.getSize(options)

    local self = setmetatable({}, Panel)
    self.parent = parent
    self.overlayParent = overlayParent
    self._dockDraggable = flowManaged ~= true
    self._canPopout = options.popout == true
    self.minWidth = options.minWidth or BORDER_SIZE * 2 + 1
    self.minHeight = options.minHeight or BORDER_SIZE * 2 + 1
    self.maxWidth = options.maxWidth
    self.maxHeight = options.maxHeight
    self.popoutClickthrough = options.popoutClickthrough == true
    self.popoutBackgroundAlpha = clampAlpha(options.popoutBackgroundAlpha or options.backgroundAlpha)
    self.onPopoutChange = options.onPopoutChange
    self.rowBackgroundColours = options.rowBackgroundColours
        or options.rowBackgroundColors
        or {}
    self.rowBackgroundEdgeToEdge = options.rowBackgroundEdgeToEdge == true
    self.dockRowBackgrounds = {}
    self.overlayRowBackgrounds = {}
    self.poppedOut = self._canPopout and options.poppedOut == true

    self.dock = createSurface(parent, {
        x = options.x or 0,
        y = options.y or 0,
        xAnchor = options.xAnchor,
        yAnchor = options.yAnchor,
        widthAnchor = options.widthAnchor,
        heightAnchor = options.heightAnchor,
        width = width,
        height = height,
        backgroundAlpha = options.backgroundAlpha,
        clickthrough = false,
    })
    self.width = self.dock.root.width
    self.height = self.dock.root.height
    self.contentWidth = self.width - BORDER_SIZE * 2
    self.overlay = createSurface(overlayParent, {
        x = options.popoutX or DEFAULT_POPOUT_X,
        y = options.popoutY or DEFAULT_POPOUT_Y,
        xAnchor = options.popoutXAnchor,
        yAnchor = options.popoutYAnchor,
        width = options.popoutWidth or self.width,
        height = options.popoutHeight or self.height,
        backgroundAlpha = self.popoutBackgroundAlpha,
        clickthrough = self.popoutClickthrough,
    })
    local dockTooltipParent = parentContext and parentContext.parent or parent
    self.dockOwner = configureOwner(self.dock, options, parentContext, dockTooltipParent)
    self.overlayOwner = configureOwner(self.overlay, options, nil, overlayParent)
    self.dockOwner._rowBackgroundPanel = self
    self.dockOwner._rowBackgroundSurface = self.dock
    self.dockOwner._rowBackgroundKey = "dockRowBackgrounds"
    self.overlayOwner._rowBackgroundPanel = self
    self.overlayOwner._rowBackgroundSurface = self.overlay
    self.overlayOwner._rowBackgroundKey = "overlayRowBackgrounds"
    self.root = self.dock.root
    self.interfaceID = self.dock.interfaceID
    self.content = self.dock.content
    self.overlayContent = self.overlay.content
    self.scrollable = self.dock.scroll.scrollable
    Wheel.bind(self.dock.root, options)
    Wheel.bind(self.dock.background, options)

    self.dockTooltipContext = Tooltip.registerContext(self.dock.content, dockTooltipParent, function(target)
        local rootX, rootY = self.dock.scroll:_AbsolutePosition()
        return rootX + (target.x or 0),
            rootY + (target.y or 0) - self.dock.scroll.scrollY
    end, parentContext)
    self.overlayTooltipContext = Tooltip.registerContext(self.overlay.content, overlayParent, function(target)
        local rootX, rootY = self.overlay.scroll:_AbsolutePosition()
        return rootX + (target.x or 0),
            rootY + (target.y or 0) - self.overlay.scroll.scrollY
    end, nil)

    if self._canPopout then
        self.popoutButton = createToggle(self.dock, self, true)
        self.dockButton = createToggle(self.overlay, self, false)
        Wheel.bind(self.popoutButton, options)
    end
    if self._dockDraggable then
        self.dockDragLayer = createDragLayer(self.parent, self.dock, self)
    end
    if self._canPopout then
        self.overlayDragLayer = createDragLayer(self.overlayParent, self.overlay, self)
    end
    Tooltip.bind(self, self.dock.root, parent, options.tooltip, "dockTooltip")
    Tooltip.bind(self, self.overlay.root, overlayParent, options.tooltip, "overlayTooltip")
    self:SetPopoutClickthrough(self.popoutClickthrough)
    self:SetPoppedOut(self.poppedOut, false)
    self:_SetAltDragActive(isAltDown())
    registerAltDrag(self)
    local function watchBounds(parent, surface, layer)
        return DragBounds.new(parent, surface.root, function(dx, dy)
            local dragging = self.dragState and self.dragState.surface == surface
            if dragging then
                self.dragState.panelX = self.dragState.panelX + dx
                self.dragState.panelY = self.dragState.panelY + dy
            end
            if not dragging or not self.dragState.captureExpanded then
                layer:SetPos(surface.root.x, surface.root.y)
                layer:SetSize(surface.root.width, surface.root.height)
            end
            if dragging and self.dragFeedback then self.dragFeedback:Update() end
            surface.scroll:_LayoutThumbDrag()
            local resize = surface == self.dock and self.dockResize or self.overlayResize
            if resize then resize:Refresh() end
        end)
    end
    if self.dockDragLayer then
        self.dockBounds = watchBounds(self.parent, self.dock, self.dockDragLayer)
    end
    if self.overlayDragLayer then
        self.overlayBounds = watchBounds(self.overlayParent, self.overlay, self.overlayDragLayer)
    end
    if self.dockBounds then self.dockBounds:Clamp() end
    if self.overlayBounds then self.overlayBounds:Clamp() end
    if options.resizable == true then
        local function createResize(parent, surface)
            return Resize.new(parent, surface.root, {
                minWidth = self.minWidth,
                minHeight = self.minHeight,
                maxWidth = self.maxWidth,
                maxHeight = self.maxHeight,
                isVisible = function()
                    return surface.root.hidden ~= true and surface.root.visibleGlobal ~= false
                end,
                onBegin = function()
                    self:_StopDrag()
                    surface.root:MoveToFront()
                end,
                setRect = function(x, y, width, height)
                    if surface == self.dock and self.flowOwner then
                        Layout.resizeRect(self.flowOwner, self, x, y, width, height)
                    else
                        surface.root:SetPos(x, y)
                    end
                    self:SetSize(width, height)
                end,
            })
        end
        self.dockResize = createResize(self.parent, self.dock)
        if self._canPopout then
            self.overlayResize = createResize(self.overlayParent, self.overlay)
        end
        self:_UpdateResizeEnabled()
    end
    return self
end

function Panel.new(parent, options, flowManaged)
    options = options or {}
    local context = Tooltip.getContext(parent)
    local overlayParent = options.overlayParent or (context and context.parent) or parent
    return Components.withBatch(parent, function()
        return Components.withBatch(overlayParent, function()
            return buildPanel(parent, options, flowManaged, overlayParent)
        end)
    end)
end

function Panel:_UpdateResizeEnabled()
    local enabled = self.dragState == nil
    if self.dockResize then self.dockResize:SetEnabled(enabled) end
    if self.overlayResize then
        self.overlayResize:SetEnabled(enabled and (not self.popoutClickthrough or isAltDown()))
    end
end

function Panel:_SetAltDragActive(active)
    local activeSurface
    if active == true then
        if self.poppedOut and self._canPopout then
            activeSurface = self.overlay
        elseif self._dockDraggable then
            activeSurface = self.dock
        end
    end
    if self.altDragSurface == activeSurface then
        self:_UpdateResizeEnabled()
        return
    end
    if self.dragState and self.dragState.surface ~= activeSurface then self:_StopDrag() end
    self.altDragSurface = activeSurface

    local function updateLayer(layer, surface)
        if layer == nil or surface.root == nil or
            ui.Interfaces:GetInterface(surface.interfaceID) == nil then return end
        local enabled = activeSurface == surface
        layer.enabled = enabled
        layer.clickthrough = not enabled
        layer.hidden = not enabled
        Cursor.apply(layer, config.Cursor.TOPLEVEL_V2_MOVE, enabled)
        if enabled then
            layer:SetPos(surface.root.x, surface.root.y)
            layer:SetSize(surface.root.width, surface.root.height)
            layer:MoveToFront()
        end
    end
    updateLayer(self.dockDragLayer, self.dock)
    updateLayer(self.overlayDragLayer, self.overlay)

    if not activeSurface then
        self:_StopDrag()
        if self.popoutButton and ui.Interfaces:GetInterface(self.dock.interfaceID) ~= nil then
            self.popoutButton:MoveToFront()
        end
        if self.dockButton and ui.Interfaces:GetInterface(self.overlay.interfaceID) ~= nil then
            self.dockButton:MoveToFront()
        end
    end
    self:_UpdateResizeEnabled()
    if self.dockResize then self.dockResize:Refresh() end
    if self.overlayResize then self.overlayResize:Refresh() end
end

function Panel:_BeginDrag(surface, component, x, y)
    if surface ~= self.altDragSurface or not isAltDown() then return false end
    InterfaceMouse.BeginCapture(component)
    local mouse = InterfaceMouse.GetPosition(component, x, y)
    if not mouse then
        InterfaceMouse.EndCapture(component)
        return false
    end
    if self.dockResize then self.dockResize:SetEnabled(false) end
    if self.overlayResize then self.overlayResize:SetEnabled(false) end
    self.dragState = {
        surface = surface,
        mouseX = mouse.x,
        mouseY = mouse.y,
        panelX = surface.root.x,
        panelY = surface.root.y,
        captureExpanded = false,
    }
    surface.root:MoveToFront()
    return false
end

function Panel:_MoveDrag(component, x, y)
    if not self.dragState then return false end
    if not isAltDown() then return self:_StopDrag() end
    local mouse = InterfaceMouse.GetPosition(component, x, y)
    if mouse then
        local drag = self.dragState
        local parent = drag.surface == self.overlay and self.overlayParent or self.parent
        if not drag.captureExpanded then
            drag.captureExpanded = true
            drag.mouseX = mouse.x
            drag.mouseY = mouse.y
            drag.panelX = drag.surface.root.x
            drag.panelY = drag.surface.root.y
            self.dragFeedback = DragFeedback.new(parent, drag.surface.root)
            component:SetPos(0, 0)
            component:SetSize(0, 0, 1.0, 1.0)
            component:MoveToFront()
        end
        local nextX = clamp(drag.panelX + mouse.x - drag.mouseX,
            0, parent.width - drag.surface.root.width)
        local nextY = clamp(drag.panelY + mouse.y - drag.mouseY,
            0, parent.height - drag.surface.root.height)
        if drag.surface.root.x ~= nextX or drag.surface.root.y ~= nextY then
            drag.surface.root:SetPos(nextX, nextY)
            local bounds = drag.surface == self.overlay and self.overlayBounds or self.dockBounds
            bounds:RememberPosition()
        end
        self.dragFeedback:Update()
    end
    return false
end

function Panel:_StopDrag()
    if self.dragFeedback then
        self.dragFeedback:Destroy()
        self.dragFeedback = nil
    end
    local surface = self.dragState and self.dragState.surface or nil
    local dragLayer = surface == self.overlay and self.overlayDragLayer or self.dockDragLayer
    InterfaceMouse.EndCapture(dragLayer)
    self.dragState = nil
    if surface and surface.root and dragLayer and
        ui.Interfaces:GetInterface(surface.interfaceID) ~= nil then
        dragLayer:SetPos(surface.root.x, surface.root.y)
        dragLayer:SetSize(surface.root.width, surface.root.height)
    end
    self:_UpdateResizeEnabled()
    return false
end

function Panel:_UpdateFlowHeight()
    local height = self.poppedOut and 0 or self.height
    if self.flowOwner then
        Layout.resize(self.flowOwner, self, height)
    elseif not self.poppedOut then
        self.dock.root:SetHeight(height)
    end
end

function Panel:BindFlow(owner)
    self.flowOwner = owner
    self:_UpdateFlowHeight()
    return self
end

function Panel:SetPoppedOut(poppedOut, notify)
    local previous = self.poppedOut
    if previous ~= (self._canPopout and poppedOut == true) then
        if self.dockResize then self.dockResize:Cancel() end
        if self.overlayResize then self.overlayResize:Cancel() end
    end
    local listening
    for field in pairs(self._keybindFields or {}) do
        if field:IsListening() then listening = field; break end
    end
    self.poppedOut = self._canPopout and poppedOut == true
    self.dock.root.hidden = self.poppedOut
    self.overlay.root.hidden = not self.poppedOut
    if previous ~= self.poppedOut and listening then
        listening:CancelListening()
        listening:StartListening()
    end
    self:_UpdateFlowHeight()
    self.dock.scroll:Refresh()
    self.overlay.scroll:Refresh()
    local bounds = self.poppedOut and self.overlayBounds or self.dockBounds
    if bounds then bounds:Clamp() end
    if self.poppedOut then self.overlay.root:MoveToFront() end
    self:_SetAltDragActive(isAltDown())
    if self.dockResize then self.dockResize:Refresh() end
    if self.overlayResize then self.overlayResize:Refresh() end
    if notify ~= false and previous ~= self.poppedOut and self.onPopoutChange then
        self.onPopoutChange(self, self.poppedOut)
    end
end

function Panel:TogglePopout()
    self:SetPoppedOut(not self.poppedOut)
end

function Panel:SetPopoutClickthrough(clickthrough)
    self.popoutClickthrough = clickthrough == true
    self.overlay.root.clickthrough = self.popoutClickthrough
    self.overlay.background.clickthrough = self.popoutClickthrough
    self.overlay.container.clickthrough = self.popoutClickthrough
    self.overlay.container.enabled = not self.popoutClickthrough
    self.overlay.scroll:SetClickthrough(self.popoutClickthrough)
    self:_UpdateResizeEnabled()
end

function Panel:SetPopoutBackgroundAlpha(alpha)
    self.popoutBackgroundAlpha = clampAlpha(alpha)
    self.overlay.background.alpha = self.popoutBackgroundAlpha
end

function Panel:SetSize(width, height)
    self.width = clamp(math.floor(width), self.minWidth or BORDER_SIZE * 2 + 1, self.maxWidth)
    self.height = clamp(math.floor(height), self.minHeight or BORDER_SIZE * 2 + 1, self.maxHeight)
    self.contentWidth = self.width - BORDER_SIZE * 2
    self.dock.root:SetWidth(self.width)
    self.overlay.root:SetSize(self.width, self.height)
    self:_UpdateFlowHeight()
    if self.dockBounds then self.dockBounds:RememberPosition() end
    if self.overlayBounds then self.overlayBounds:RememberPosition() end
    self.dockOwner.contentWidth = self.contentWidth
    self.overlayOwner.contentWidth = self.contentWidth
    self.dock.scroll:Refresh()
    self.overlay.scroll:Refresh()
    if self.dockBounds then self.dockBounds:Clamp() end
    if self.overlayBounds then self.overlayBounds:Clamp() end
    if self.dragFeedback then self.dragFeedback:Update() end
    if self.dragState == nil then
        if self.dockDragLayer then
            self.dockDragLayer:SetPos(self.dock.root.x, self.dock.root.y)
            self.dockDragLayer:SetSize(self.dock.root.width, self.dock.root.height)
        end
        if self.overlayDragLayer then
            self.overlayDragLayer:SetPos(self.overlay.root.x, self.overlay.root.y)
            self.overlayDragLayer:SetSize(self.overlay.root.width, self.overlay.root.height)
        end
    end
    if self.dockResize then self.dockResize:Refresh() end
    if self.overlayResize then self.overlayResize:Refresh() end
end

function Panel:SetTooltip(value)
    local dockUpdated = Tooltip.set(self, value, "dockTooltip")
    local overlayUpdated = Tooltip.set(self, value, "overlayTooltip")
    return dockUpdated and overlayUpdated
end

function Panel:SetScrollable(scrollable)
    self.dock.scroll:SetScrollable(scrollable)
    self.overlay.scroll:SetScrollable(scrollable)
    self.dockOwner.scrollable = self.dock.scroll.scrollable
    self.overlayOwner.scrollable = self.overlay.scroll.scrollable
    self.scrollable = self.dock.scroll.scrollable
end

function Panel:RefreshRowBackgrounds()
    refreshPanelRows(self, self.dock, self.dockOwner, "dockRowBackgrounds")
    refreshPanelRows(self, self.overlay, self.overlayOwner, "overlayRowBackgrounds")
end

function Panel:ScrollToChild(child, topOffset)
    if child == nil then return end
    self.dock.scroll:ScrollToChild(child.dock, topOffset)
    self.overlay.scroll:ScrollToChild(child.overlay, topOffset)
end

-- Install the shared Add... API against both panel surfaces. The stateful methods
-- below overwrite their generated counterparts to keep dock and popout state in sync.
ContentMethods.installPaired(Panel, function(panel)
    return {
        { owner = panel.dockOwner, content = panel.dock.content },
        { owner = panel.overlayOwner, content = panel.overlay.content },
    }
end, pairObjects)

local addKeybindField = Panel.AddKeybindField

function Panel:AddKeybindField(options)
    return addPairedKeybindField(self, function(copied)
        return addKeybindField(self, copied)
    end, options)
end

local addPairedCollapseButton = Panel.AddCollapseButton

function Panel:AddCollapseButton(text, options)
    local copied = copyOptions(options)
    local onToggle = copied.onToggle
    local proxy
    local syncing = false
    copied.onToggle = function(section, expanded)
        if syncing then return end
        syncing = true
        local other = section == proxy.dock and proxy.overlay or proxy.dock
        other:SetExpanded(expanded)
        syncing = false
        if onToggle then onToggle(proxy, expanded) end
    end
    proxy = addPairedCollapseButton(self, text, copied)
    rawset(proxy, "Toggle", function()
        local active = self.poppedOut and proxy.overlay or proxy.dock
        active:Toggle()
    end)
    return proxy
end

local addPairedTimeGraph = Panel.AddTimeGraph

function Panel:AddTimeGraph(options)
    local shared = copyOptions(options)
    shared.bus = shared.bus or require("src/time_graph").CreateEventBus()
    local proxy
    local onZoom = shared.onZoom
    shared.onZoom = function(_, zoom)
        proxy.dock:SetZoom(zoom, false)
        proxy.overlay:SetZoom(zoom, false)
        if onZoom then onZoom(proxy, zoom) end
    end
    proxy = addPairedTimeGraph(self, shared)
    rawset(proxy, "SetZoom", function(_, zoom, notify)
        local dockChanged = proxy.dock:SetZoom(zoom, false)
        local overlayChanged = proxy.overlay:SetZoom(zoom, false)
        local changed = dockChanged or overlayChanged
        if changed and notify ~= false and onZoom then onZoom(proxy, proxy:GetZoom()) end
        return changed
    end)
    rawset(proxy, "ZoomIn", function() return proxy:SetZoom(proxy:GetZoom() * 2) end)
    rawset(proxy, "ZoomOut", function() return proxy:SetZoom(proxy:GetZoom() / 2) end)
    -- Both surfaces receive the same stream, including while one is hidden.
    -- A snapshot is detached data, not another paired component proxy.
    rawset(proxy, "GetSnapshot", function()
        local active = self.poppedOut and proxy.overlay or proxy.dock
        return active:GetSnapshot()
    end)
    return proxy
end

-- Caller-fed chart updates are mirrored by the normal paired methods. Snapshot
-- data must come from one surface rather than being wrapped as UI components.
for _, method in ipairs({ "AddBarChart", "AddHistogram" }) do
    local addChart = Panel[method]
    Panel[method] = function(self, options)
        local proxy = addChart(self, options)
        rawset(proxy, "GetSnapshot", function()
            local active = self.poppedOut and proxy.overlay or proxy.dock
            return active:GetSnapshot()
        end)
        return proxy
    end
end

function Panel:AddTabs(tabs, options)
    local width, height = Tabs.getSize(tabs, options)
    local proxy
    local syncing = false

    local function placedOptions(owner)
        local copied = Tabs.flowOptions(options)
        copied.onChange = function(_, index, value)
            if syncing then return end
            syncing = true
            proxy.dock:SetActive(index, false)
            proxy.overlay:SetActive(index, false)
            syncing = false
            if options and options.onChange then
                options.onChange(proxy, index, value, proxy:GetPage(index))
            end
        end
        return Layout.place(owner, copied, { width = width, height = height, fillWidth = true })
    end

    local dockOptions = placedOptions(self.dockOwner)
    local overlayOptions = placedOptions(self.overlayOwner)
    proxy = pairObjects(self,
        Layout.manage(self.dockOwner, Tabs.new(self.dock.content, tabs, dockOptions), dockOptions),
        Layout.manage(self.overlayOwner, Tabs.new(self.overlay.content, tabs, overlayOptions), overlayOptions))
    proxy.dock:BindFlow(self.dockOwner)
    proxy.overlay:BindFlow(self.overlayOwner)
    return proxy
end

function Panel:AddColourPicker(options)
    local proxy
    local syncing = false
    local function placedOptions(owner)
        local copied = copyOptions(options)
        copied.onChange = function(_, colour)
            if syncing then return end
            syncing = true
            proxy.dock:SetValue(colour, false)
            proxy.overlay:SetValue(colour, false)
            syncing = false
            if options and options.onChange then options.onChange(proxy, colour) end
        end
        local width, height = ColourPicker.getSize(copied)
        return Layout.place(owner, copied, { width = width, height = height })
    end
    local dockOptions = placedOptions(self.dockOwner)
    local overlayOptions = placedOptions(self.overlayOwner)
    proxy = pairObjects(self,
        Layout.manage(
            self.dockOwner,
            ColourPicker.new(self.dock.content, dockOptions),
            dockOptions
        ),
        Layout.manage(
            self.overlayOwner,
            ColourPicker.new(self.overlay.content, overlayOptions),
            overlayOptions
        ))
    rawset(proxy, "Open", function()
        local active = self.poppedOut and proxy.overlay or proxy.dock
        return active:Open()
    end)
    return proxy
end

function Panel:AddTextField(options)
    options = options or {}
    local proxy
    local syncing = false
    local width, height = TextField.getSize(options)
    local function placed(owner, other)
        local copied = copyOptions(options)
        copied.onChange = function(_, reason, content)
            if syncing then return end
            syncing = true
            if other() then other():SetText(content, false) end
            syncing = false
            if options.onChange then options.onChange(proxy, reason, content) end
            if options.onSubmit and reason == ui.InputFieldActionResult.SUBMIT then
                options.onSubmit(proxy, content)
            end
        end
        copied.onSubmit = nil
        return Layout.place(owner, copied, { width = width, height = height, fillWidth = true })
    end
    local dock, overlay
    local dockOptions = placed(self.dockOwner, function() return overlay end)
    local overlayOptions = placed(self.overlayOwner, function() return dock end)
    dock = Layout.manage(self.dockOwner, TextField.new(self.dock.content, dockOptions), dockOptions)
    overlay = Layout.manage(self.overlayOwner, TextField.new(self.overlay.content, overlayOptions), overlayOptions)
    proxy = pairObjects(self, dock, overlay)
    rawset(proxy, "SetText", function(_, value, notify)
        local content = tostring(value or "")
        syncing = true
        dock:SetText(content, false)
        overlay:SetText(content, false)
        syncing = false
        if notify == true and options.onChange then
            options.onChange(proxy, ui.InputFieldActionResult.CONTENT_CHANGE, content)
        end
    end)
    return proxy
end

function Panel:AddComboBox(options)
    options = options or {}
    local proxy
    local syncing = false
    local width, height = ComboBox.getSize(options)
    local function placed(owner, other)
        local copied = copyOptions(options)
        copied.onChange = function(_, entryID, label, eventType)
            if syncing then return end
            syncing = true
            if other() then other():Select(entryID, false) end
            syncing = false
            if options.onChange then options.onChange(proxy, entryID, label, eventType) end
        end
        return Layout.place(owner, copied, { width = width, height = height, fillWidth = true })
    end
    local dock, overlay
    local dockOptions = placed(self.dockOwner, function() return overlay end)
    local overlayOptions = placed(self.overlayOwner, function() return dock end)
    dock = Layout.manage(self.dockOwner, ComboBox.new(self.dock.content, dockOptions), dockOptions)
    overlay = Layout.manage(self.overlayOwner, ComboBox.new(self.overlay.content, overlayOptions), overlayOptions)
    proxy = pairObjects(self, dock, overlay)
    rawset(proxy, "Select", function(_, entryID, notify)
        syncing = true
        local dockResult = dock:Select(entryID, false)
        local overlayResult = overlay:Select(entryID, false)
        syncing = false
        if notify == true and options.onChange then
            local active = self.poppedOut and overlay or dock
            options.onChange(proxy, entryID, active:GetSelectedLabel(), ui.SelectionChangeEvent.SELECTED)
        end
        return self.poppedOut and overlayResult or dockResult
    end)
    return proxy
end

function Panel:AddList(options)
    options = options or {}
    local proxy
    local syncing = false
    local width, height = List.getSize(options)
    local function placed(owner, other)
        local copied = copyOptions(options)
        copied.onChange = function(_, entryID, selected, eventType)
            if syncing then return end
            syncing = true
            if other() then other():SetSelected(entryID, selected, false) end
            syncing = false
            if options.onChange then options.onChange(proxy, entryID, selected, eventType) end
        end
        return Layout.place(owner, copied, { width = width, height = height, fillWidth = true })
    end
    local dock, overlay
    local dockOptions = placed(self.dockOwner, function() return overlay end)
    local overlayOptions = placed(self.overlayOwner, function() return dock end)
    dock = Layout.manage(self.dockOwner, List.new(self.dock.content, dockOptions), dockOptions)
    overlay = Layout.manage(self.overlayOwner, List.new(self.overlay.content, overlayOptions), overlayOptions)
    proxy = pairObjects(self, dock, overlay)
    rawset(proxy, "SetSelected", function(_, entryID, selected, notify)
        syncing = true
        local dockResult = dock:SetSelected(entryID, selected, false)
        local overlayResult = overlay:SetSelected(entryID, selected, false)
        syncing = false
        if notify == true and options.onChange then
            options.onChange(
                proxy,
                entryID,
                selected == true,
                selected and ui.SelectionChangeEvent.SELECTED or ui.SelectionChangeEvent.DESELECTED
            )
        end
        return self.poppedOut and overlayResult or dockResult
    end)
    return proxy
end

function Panel:AddSlider(options)
    local proxy
    local syncing = false
    local function placedOptions(owner)
        local copied = copyOptions(options)
        copied.onChange = function(_, value)
            if syncing then return end
            syncing = true
            proxy.dock:SetValue(value, false)
            proxy.overlay:SetValue(value, false)
            syncing = false
            if options and options.onChange then options.onChange(proxy, value) end
        end
        local width, height = Slider.getSize(copied)
        return Layout.place(owner, copied, { width = width, height = height, fillWidth = true })
    end
    local dockOptions = placedOptions(self.dockOwner)
    local overlayOptions = placedOptions(self.overlayOwner)
    proxy = pairObjects(self,
        Layout.manage(self.dockOwner, Slider.new(self.dock.content, dockOptions), dockOptions),
        Layout.manage(self.overlayOwner, Slider.new(self.overlay.content, overlayOptions), overlayOptions))
    return proxy
end

function Panel:Destroy()
    if self.dockResize then self.dockResize:Destroy(); self.dockResize = nil end
    if self.overlayResize then self.overlayResize:Destroy(); self.overlayResize = nil end
    if self.dockBounds then self.dockBounds:Destroy(); self.dockBounds = nil end
    if self.overlayBounds then self.overlayBounds:Destroy(); self.overlayBounds = nil end
    unregisterAltDrag(self)
    self:_StopDrag()
    if self.dock and self.dock.content then Tooltip.unregisterContext(self.dock.content) end
    if self.overlay and self.overlay.content then Tooltip.unregisterContext(self.overlay.content) end
    Layout.destroyManaged(self.dockOwner)
    Layout.destroyManaged(self.overlayOwner)
    Tooltip.unbind(self, "dockTooltip")
    RowBackgrounds.clear(self.dockRowBackgrounds, self.dock.interfaceID)
    RowBackgrounds.clear(self.overlayRowBackgrounds, self.overlay.interfaceID)
    self.dockRowBackgrounds = {}
    self.overlayRowBackgrounds = {}
    Tooltip.unbind(self, "overlayTooltip")
    if self.dock and self.dock.scroll then
        self.dock.scroll:Destroy()
        self.dock.scroll = nil
    end
    if self.overlay and self.overlay.scroll then
        self.overlay.scroll:Destroy()
        self.overlay.scroll = nil
    end
    local dockLoaded = self.dock and ui.Interfaces:GetInterface(self.dock.interfaceID) ~= nil
    local overlayLoaded = self.overlay and ui.Interfaces:GetInterface(self.overlay.interfaceID) ~= nil
    if self.dockDragLayer then
        if dockLoaded then self.dockDragLayer:Destroy() end
        self.dockDragLayer = nil
    end
    if self.overlayDragLayer then
        if overlayLoaded then self.overlayDragLayer:Destroy() end
        self.overlayDragLayer = nil
    end
    if self.dock and self.dock.root then
        if dockLoaded then self.dock.root:Destroy() end
        self.dock.root = nil
    end
    if self.overlay and self.overlay.root then
        if overlayLoaded then self.overlay.root:Destroy() end
        self.overlay.root = nil
    end
    self.root = nil
    self.content = nil
    self.overlayContent = nil
    self.flowOwner = nil
end

return Panel
