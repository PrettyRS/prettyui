local Components = require("src/core/components")
local PanelSurface = require("src/core/panel_surface")
local Sprites = require("src/core/sprites")
local ContentMethods = require("src/core/content_methods")
local Scroll = require("src/core/scroll")
local Layout = require("src/core/layout")
local RowBackgrounds = require("src/core/row_backgrounds")
local Tooltip = require("src/tooltip")
local Wheel = require("src/core/wheel")
local Cursor = require("src/core/cursor")
local InterfaceMouse = require("src/core/mouse")
local DragBounds = require("src/core/drag_bounds")
local Resize = require("src/core/resize")
local NativeInterfaceSettings = require("src/core/native_interface_settings")
local Snap = require("src/core/snap")
local NisDrag = require("src/core/nis_drag")
local NisResize = require("src/core/nis_resize")
local NisGroup = require("src/core/nis_group")
local NisTabs = require("src/core/nis_tabs")
local NisPersistence = require("src/core/nis_persistence")
local NisNative = require("src/core/nis_native")
local clamp = require("src/core/math").clamp
local WorldMap = require("src/core/world_map")

local NisPanel = {}
NisPanel.__index = NisPanel

local BORDER = 4
local BOTTOM_CORNER_SIZE = 22
local HEADER_HEIGHT = 12
local HEADER_CORNER_WIDTH = 32
local CLOSE_SIZE = 12
local MIN_WIDTH = HEADER_CORNER_WIDTH * 2
local MIN_HEIGHT = HEADER_HEIGHT + BORDER * 2 + 1
local nextResizeID = 0
local FRAME_PARTS = { "top", "bottom", "left", "right", "topLeft", "topRight", "bottomLeft", "bottomRight" }
local HEADER_PARTS = { "headerLeft", "headerRight", "headerTop", "headerFill" }

local function sprite(parent, spriteID)
    local part = Components.new(ui.Sprite, parent)
    part.spriteID = spriteID
    part.clickthrough = true
    return part
end

local function dimension(value, fallback, minimum, maximum)
    return clamp(math.floor(tonumber(value) or fallback), minimum, maximum)
end

local function loaded(self)
    return self.root ~= nil and ui.Interfaces:GetInterface(self.interfaceID) ~= nil
end

function NisPanel:_SyncDragLayer()
    if not loaded(self) or self.dragLayer == nil then return end
    local capture = self.dragState and self.dragState.capture == self.dragLayer
        and self.dragState.captureExpanded
    local visible = capture or not self._nisNative and self.root.hidden ~= true and not self.locked
        and (not self._nisGroup or self._nisGroup.active == self)
    Components.setHidden(self.dragLayer, not visible)
    self.dragLayer.enabled = visible
    if visible and not capture then
        self.dragLayer:SetPos(self.root.x, self.root.y)
        self.dragLayer:SetSize(self.root.width - CLOSE_SIZE, HEADER_HEIGHT)
    end
    if visible then self.dragLayer:MoveToFront() end
end

function NisPanel:_SyncOverlays(hidden)
    if not loaded(self) then return end
    for component, overlay in pairs(self.overlays) do
        if ui.Interfaces:GetInterface(overlay.interfaceID) ~= nil then
            if not hidden and overlay.layout then overlay.layout() end
            Components.setHidden(component, hidden or
                (overlay.isVisible and not overlay.isVisible() or false))
            if not component.hidden then component:MoveToFront() end
        end
    end
    if self._nisTabs then self._nisTabs:Sync(hidden) end
    self:_SyncDragLayer()
    if self.resize then
        self.resize:SetEnabled(not self._nisNative and not self.locked and not hidden and self.dragState == nil
            and self._nisTabPress == nil and (not self._nisGroup or self._nisGroup.active == self))
        self.resize:Refresh()
    end
end

function NisPanel:_RegisterOverlay(component, isVisible, layout)
    self.overlays[component] = {
        interfaceID = component.interfaceID,
        isVisible = isVisible,
        layout = layout,
    }
end

function NisPanel:_UnregisterOverlay(component)
    self.overlays[component] = nil
end

function NisPanel:_SyncChrome()
    if not loaded(self) then return end
    local visible = not self._nisNative and not self.locked and self.root.hidden ~= true
    Components.setHidden(self.headerLeft, not visible)
    Components.setHidden(self.headerRight, not visible)
    Components.setHidden(self.headerTop, not visible or self.root.width == MIN_WIDTH)
    Components.setHidden(self.headerFill, not visible or self.root.width == MIN_WIDTH)
    Components.setHidden(self.closeButton, not visible)
    if visible then
        self.headerLeft:MoveToFront()
        self.headerRight:MoveToFront()
        self.headerTop:MoveToFront()
        self.headerFill:MoveToFront()
        self.closeButton:MoveToFront()
    end
    self.closeButton.enabled = visible
    self:_SyncDragLayer()
end

function NisPanel:_SetLocked(value)
    local locked = value ~= false
    if locked == self.locked then return end
    if locked and not WorldMap.isSuspended() then
        self:_CancelDrag()
        NisGroup.clearPanel(self)
    end
    self.locked = locked
    NisNative.lockChanged(self, locked)
    if WorldMap.isSuspended() or not loaded(self) then return end
    self:_LayoutBody()
    self:RefreshRowBackgrounds()
    self:_SyncChrome()
    self:_SyncOverlays(self.root.hidden == true)
    if self._nisTabs and self._nisGroup and self._nisGroup.active == self then
        self._nisTabs:Refresh(self._nisGroup.members, self)
    end
    self:_NotifyBoundsChange()
end

function NisPanel:_LayoutBody()
    if not loaded(self) then return end
    if self._nisNative then
        self.root.clickthrough = false
        for _, key in ipairs(FRAME_PARTS) do Components.setHidden(self.surface[key], true) end
        Components.setHidden(self.surface.background, true)
        Components.setHidden(self.tabBackground, true)
        Components.setHidden(self.bottomLeftHit, true)
        Components.setHidden(self.bottomRightHit, true)
        Components.setHidden(self.bottomHit, true)
        if self._tabGapHit then Components.setHidden(self._tabGapHit, true) end
        self.surface.container:SetPos(0, 0)
        self.surface.container:SetSize(0, 0, 1, 1)
        self._scroll:SetSize(0, 0, 1, 1)
        self._nisTabs:Refresh(nil)
        return
    end
    for _, key in ipairs(FRAME_PARTS) do Components.setHidden(self.surface[key], false) end
    Components.setHidden(self.surface.background, false)
    Components.setHidden(self.bottomLeftHit, false)
    Components.setHidden(self.bottomRightHit, false)
    Components.setHidden(self.bottomHit, false)
    -- Tab inputs are siblings: the group's backdrop must not mask their band.
    -- The content container remains input-blocking below the tabs.
    local grouped = self._nisGroup ~= nil
    self.root.clickthrough = grouped
    self.surface.background.clickthrough = grouped
    for _, key in ipairs(FRAME_PARTS) do self.surface[key].clickthrough = not grouped end
    -- Corner artwork extends into the content; only its four-unit edges block input.
    self.surface.bottomLeft.clickthrough = true
    self.surface.bottomRight.clickthrough = true
    local header = self.locked and 0 or HEADER_HEIGHT
    if grouped and self._tabGapHit == nil then
        self._tabGapHit = Components.new(ui.Layer, self.root)
        self._tabGapHit:SetSize(-BORDER * 2, BORDER, 1.0)
        self._tabGapHit.clickthrough = false
    end
    if self._tabGapHit then
        self._tabGapHit:SetPos(BORDER, header)
        Components.setHidden(self._tabGapHit, not grouped or self.locked)
    end
    local top = header + BORDER
    local contentTop = top + (self._nisGroup and NisTabs.HEIGHT or 0)
    local showTopBorder = self.locked or self._nisGroup == nil
    local bodyTop = showTopBorder and top or header
    Components.setHidden(self.surface.top, not showTopBorder)
    Components.setHidden(self.surface.topLeft, not showTopBorder)
    Components.setHidden(self.surface.topRight, not showTopBorder)
    self.surface.top:SetPos(BORDER, header)
    self.surface.topLeft:SetPos(0, header)
    self.surface.topRight:SetPos(-BORDER, header, 1.0)
    local cornerHeight = math.min(BOTTOM_CORNER_SIZE, self.root.height - contentTop)
    self.surface.left:SetPos(0, bodyTop)
    self.surface.left:SetSize(BORDER, -bodyTop - cornerHeight, 0, 1.0)
    self.surface.right:SetPos(-BORDER, bodyTop, 1.0)
    self.surface.right:SetSize(BORDER, -bodyTop - cornerHeight, 0, 1.0)
    self.surface.bottomLeft:SetPos(0, -cornerHeight, 0, 1.0)
    self.surface.bottomLeft:SetSize(BOTTOM_CORNER_SIZE, cornerHeight)
    self.surface.bottomRight:SetPos(-BOTTOM_CORNER_SIZE, -cornerHeight, 1.0, 1.0)
    self.surface.bottomRight:SetSize(BOTTOM_CORNER_SIZE, cornerHeight)
    self.bottomLeftHit:SetSize(BORDER, cornerHeight)
    self.bottomRightHit:SetSize(BORDER, cornerHeight)
    self.bottomLeftHit:SetPos(0, -cornerHeight, 0, 1.0)
    self.bottomRightHit:SetPos(-BORDER, -cornerHeight, 1.0, 1.0)
    -- Do not stack translucent body and tab fills: their bounds meet at contentTop.
    self.surface.background:SetPos(BORDER, contentTop)
    self.surface.background:SetSize(-BORDER * 2, -contentTop - BORDER, 1.0, 1.0)
    Components.setHidden(self.tabBackground, not grouped)
    self.tabBackground:SetPos(BORDER, bodyTop)
    self.tabBackground:SetSize(-BORDER * 2, contentTop - bodyTop, 1.0)
    self.surface.container:SetPos(BORDER, contentTop)
    self.surface.container:SetSize(-BORDER * 2, -contentTop - BORDER, 1.0, 1.0)
    self._scroll:SetSize(0, 0, 1.0, 1.0)
    self.surface.bottomLeft:MoveToFront()
    self.surface.bottomRight:MoveToFront()
end

function NisPanel:_SetBackgroundTransparency(transparency)
    self.transparencyScale = 1 - transparency
    if loaded(self) then
        self.surface.background.alpha = self.transparencyScale
        self.tabBackground.alpha = self.transparencyScale
        for _, key in ipairs(FRAME_PARTS) do self.surface[key].alpha = self.transparencyScale end
        for _, key in ipairs(HEADER_PARTS) do self[key].alpha = self.transparencyScale end
        self.closeBacking.alpha = self.transparencyScale
        if self._nisTabs then self._nisTabs:SetAlpha(self.transparencyScale) end
    end
end


-- Keep each member's own native surface; grouped geometry is synchronized in Lua.
function NisPanel:_ApplyRectSingle(x, y, width, height)
    if not loaded(self) then return end
    self.root:SetPos(x, y)
    self.root:SetSize(width, height)
    self.width, self.height = self.root.width, self.root.height
    self:_LayoutBody()
    self.contentWidth = self._scroll.contentWidth
    self:RefreshRowBackgrounds()
    self:_SyncChrome()
    self:_SyncOverlays(self.root.hidden == true)
    if self.dragBounds then self.dragBounds:RememberPosition() end
end

function NisPanel:_ApplyRect(x, y, width, height)
    NisGroup.apply(self, x, y, width, height)
end

function NisPanel:_ConstrainResize(x, y, width, height, edge)
    if not loaded(self) then return nil end
    local rects = self._resizeRects or {}
    self._resizeRects = rects
    local ok = pcall(Snap.collect, self, rects, true,
        id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_BOTTOM)
    if not ok then return nil end
    local root = self.root
    return NisResize.constrain(rects, root.x, root.y, root.width, root.height,
        x, y, width, height, edge)
end

function NisPanel:_NotifyBoundsChange()
    if WorldMap.isSuspended() or not loaded(self) or self._updatingBounds or self.dragState
        or (self.resize and self.resize.dragState) or self._lastBounds == nil then return end
    local root, previous = self.root, self._lastBounds
    local x, y, width, height = root.x, root.y, root.width, root.height
    if previous[1] == x and previous[2] == y and previous[3] == width and previous[4] == height then return end
    previous[1], previous[2], previous[3], previous[4] = x, y, width, height
    NisPersistence.bounds(self)
    if self.onBoundsChange then self.onBoundsChange(self, x, y, width, height) end
end

function NisPanel:SetSize(width, height)
    self:_CancelDrag()
    if self.resize then self.resize:Cancel() end
    if self._nisNative then return end -- The native frame owns docked dimensions.
    local minWidth, minHeight, maxWidth, maxHeight = NisGroup.limits(self)
    local targetWidth = dimension(width, self.width, minWidth, maxWidth)
    local targetHeight = dimension(height, self.height, minHeight, maxHeight)
    self._updatingBounds = true
    if loaded(self) then
        NisGroup.apply(self, self.root.x, self.root.y, targetWidth, targetHeight)
        if self.dragBounds then self.dragBounds:Clamp() end
    end
    self._updatingBounds = nil
    if self._nisGroup then
        NisGroup.notify(self)
    else
        self:_NotifyBoundsChange()
    end
end

function NisPanel:_FitContent()
    self:SetSize(self.width, self.contentHeight +
        (self.locked and 0 or HEADER_HEIGHT) + BORDER * 2
        + (self._nisGroup and NisTabs.HEIGHT or 0))
    self:RefreshRowBackgrounds()
end

function NisPanel:RefreshRowBackgrounds()
    RowBackgrounds.clear(self.rowBackgrounds, self.interfaceID)
    if not loaded(self) then
        self.rowBackgrounds = {}
        return
    end
    self.rowBackgrounds = RowBackgrounds.apply(self.content,
        self.surface.container.height, self,
        self.rowBackgroundColours, self.rowBackgroundEdgeToEdge)
end

function NisPanel:SetTooltip(value)
    return Tooltip.set(self, value)
end

function NisPanel:Show()
    if not loaded(self) then return end
    self._nisHidden = false
    if self._nisNative then
        NisNative.select(self)
        return
    end
    if self._nisGroup then
        NisGroup.select(self)
        if loaded(self) and not self.root.hidden then
            self.root:MoveToFront()
            self:_SyncOverlays(false)
        end
        return
    end
    Components.setHidden(self.root, false)
    self.root:MoveToFront()
    self:_SyncChrome()
    if not self.dragLayer.hidden then self.dragLayer:MoveToFront() end
    self:_SyncOverlays(false)
end

function NisPanel:Hide()
    self:_CancelDrag()
    NisNative.detach(self)
    NisGroup.clearPanel(self)
    NisGroup.undock(self)
    NisPersistence.detach(self)
    self._nisHidden = true
    if self.content then Tooltip.hideContextTooltips(self.content) end
    if not loaded(self) then return end
    Components.setHidden(self.root, true)
    self:_SyncChrome()
    self:_SyncOverlays(true)
    self:_NotifyBoundsChange()
end

function NisPanel:Close()
    self:_CancelDrag()
    if self.resize then self.resize:Cancel() end
    NisPersistence.detach(self)
    if self.onClose then self.onClose(self) end
    if self._destroyed then return end
    if self.destroyOnClose then self:Destroy() else self:Hide() end
end

function NisPanel:Destroy()
    if self._destroyed then return end
    WorldMap.unwatch(self)
    self:_CancelDrag()
    NisNative.detach(self)
    NisPersistence.unregister(self)
    self._destroyed = true
    NisGroup.unregister(self)
    NativeInterfaceSettings.unwatchLock(self)
    NativeInterfaceSettings.unwatchTransparency(self)
    Snap.unregister(self)
    if self.resize then self.resize:Destroy(); self.resize = nil end
    self._resizeRects = nil
    if self.dragBounds then self.dragBounds:Destroy(); self.dragBounds = nil end
    if self._resizeHookID and ui.Interfaces:GetInterface(self.interfaceID) ~= nil then
        self.parent:Unsubscribe(ui.Hook.ONRESIZE, self._resizeHookID)
    end
    self._resizeHookID = nil
    self:_SyncOverlays(true)
    RowBackgrounds.clear(self.rowBackgrounds, self.interfaceID)
    self.rowBackgrounds = {}
    if self.content then Tooltip.unregisterContext(self.content) end
    self.tooltipContext = nil
    Layout.destroyManaged(self)
    Tooltip.unbind(self)
    if self._scroll then self._scroll:Destroy(); self._scroll = nil end
    self.viewport, self.content = nil, nil
    if self._nisTabs then self._nisTabs:Destroy(); self._nisTabs = nil end
    if self.dragLayer then
        InterfaceMouse.EndCapture(self.dragLayer)
        if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.dragLayer:Destroy() end
        self.dragLayer = nil
    end
    if self.root then
        if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.root:Destroy() end
        self.root = nil
    end
    self.surface = nil
    self.overlays = {}
end

ContentMethods.installSingle(NisPanel)
Scroll.install(NisPanel)
NisDrag.install(NisPanel)

function NisPanel:DockTo(target)
    self:_CancelDrag()
    if type(target) == "table" and target.root then
        if target._nisNative then return NisNative.dock(self, target._nisNative) end
        return NisGroup.dock(self, target)
    end
    return NisNative.dock(self, target)
end

function NisPanel:Undock()
    self:_CancelDrag()
    NisNative.detach(self)
    NisGroup.undock(self)
    NisPersistence.detach(self)
end

function NisPanel:SelectTab()
    if self._nisNative then return NisNative.select(self) end
    NisGroup.select(self)
end

local function buildPanel(parent, options, policy)
    local self = setmetatable({}, NisPanel)
    self.parent = parent
    self.minWidth = dimension(options.minWidth, MIN_WIDTH, MIN_WIDTH)
    self.minHeight = dimension(options.minHeight, MIN_HEIGHT, MIN_HEIGHT)
    self.maxWidth = options.maxWidth and dimension(options.maxWidth, self.minWidth, self.minWidth)
    self.maxHeight = options.maxHeight and dimension(options.maxHeight, self.minHeight, self.minHeight)
    self.width = dimension(options.width, 300, self.minWidth, self.maxWidth)
    self.height = dimension(options.height, 160, self.minHeight, self.maxHeight)
    self.tabIcon = options.tabIcon or Sprites.NIS_PANEL.defaultIcon
    self.tabText = options.tabText
    self.transparencyScale = 1
    self.locked = true
    self.onClose = options.onClose
    self.onBoundsChange = options.onBoundsChange
    self.destroyOnClose = options.destroyOnClose == true
    self.rowBackgroundColours = options.rowBackgroundColours or options.rowBackgroundColors or {}
    self.rowBackgroundEdgeToEdge = options.rowBackgroundEdgeToEdge == true
    self.rowBackgrounds = {}
    self.overlays = {}

    local surface = PanelSurface.new(parent, {
        _categoryPolicy = policy,
        x = options.x or 0,
        y = options.y or 0,
        xAnchor = options.xAnchor,
        yAnchor = options.yAnchor,
        width = self.width,
        height = self.height,
        clickthrough = false,
    })
    self.surface = surface
    self.root = surface.root
    self.interfaceID = surface.interfaceID
    self.width, self.height = self.root.width, self.root.height
    surface.background.spriteID = Sprites.NIS_PANEL.content
    surface.top.spriteID = Sprites.NIS_PANEL.contentTop
    surface.topLeft.spriteID = Sprites.NIS_PANEL.contentCorner
    surface.topRight.spriteID = Sprites.NIS_PANEL.contentCorner
    surface.left.spriteID = Sprites.NIS_PANEL.frameSide
    surface.right.spriteID = Sprites.NIS_PANEL.frameSide
    surface.bottom.spriteID = Sprites.NIS_PANEL.frameBottomTile
    surface.bottomLeft.spriteID = Sprites.NIS_PANEL.frameBottomCorner
    surface.bottomRight.spriteID = Sprites.NIS_PANEL.frameBottomCorner
    surface.bottom:SetPos(BOTTOM_CORNER_SIZE, -BORDER, 0, 1.0)
    surface.bottom:SetSize(-BOTTOM_CORNER_SIZE * 2, BORDER, 1.0)
    self.tabBackground = sprite(self.root, Sprites.HUD_WINDOW.content)
    self.tabBackground.isTiling = true
    Components.setHidden(self.tabBackground, true)

    self.bottomLeftHit = Components.new(ui.Layer, self.root)
    self.bottomLeftHit.clickthrough = false
    self.bottomRightHit = Components.new(ui.Layer, self.root)
    self.bottomRightHit.clickthrough = false
    self.bottomHit = Components.new(ui.Layer, self.root)
    self.bottomHit:SetPos(0, -BORDER, 0, 1.0)
    self.bottomHit:SetSize(0, BORDER, 1.0)
    self.bottomHit.clickthrough = false

    local art = Sprites.NIS_PANEL
    self.headerLeft = sprite(self.root, art.headerLeft)
    self.headerLeft:SetSize(HEADER_CORNER_WIDTH, HEADER_HEIGHT)
    self.headerRight = sprite(self.root, art.headerRight)
    self.headerRight:SetPos(-HEADER_CORNER_WIDTH, 0, 1.0)
    self.headerRight:SetSize(HEADER_CORNER_WIDTH, HEADER_HEIGHT)
    self.headerTop = sprite(self.root, art.headerTop)
    self.headerTop:SetPos(HEADER_CORNER_WIDTH, 0)
    self.headerTop:SetSize(-MIN_WIDTH, BORDER, 1.0)
    self.headerTop.isTiling = true
    self.headerFill = sprite(self.root, art.headerFill)
    self.headerFill:SetPos(HEADER_CORNER_WIDTH, BORDER)
    self.headerFill:SetSize(-MIN_WIDTH, HEADER_HEIGHT - BORDER, 1.0)
    self.headerFill.isTiling = true

    self.closeButton = Components.new(ui.Layer, self.root)
    self.closeButton:SetPos(-CLOSE_SIZE, 0, 1.0)
    self.closeButton:SetSize(CLOSE_SIZE, CLOSE_SIZE)
    self.closeButton.clickthrough = false
    self.closeBacking = sprite(self.closeButton, art.closeBacking)
    self.closeBacking:SetSize(CLOSE_SIZE, CLOSE_SIZE)
    self.closeSprite = sprite(self.closeButton, art.close)
    self.closeSprite:SetSize(CLOSE_SIZE, CLOSE_SIZE)
    self.closeButton:Subscribe(ui.Hook.ONMOUSEOVER, function()
        self.closeSprite.spriteID = art.closeOver
    end)
    self.closeButton:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        self.closeSprite.spriteID = art.close
    end)
    self.closeButton:Subscribe(ui.Hook.ONCLICK, function()
        self:Close()
        return false
    end)
    self.closeButton:MoveToFront()

    local parentContext = Tooltip.getContext(parent)
    local tooltipParent = parentContext and parentContext.parent or parent
    Scroll.attach(self, surface.container, {
        width = 0, height = 0, widthAnchor = 1.0, heightAnchor = 1.0,
        contentHeight = options.contentHeight,
        scrollable = options.scrollable,
        scrollStep = options.scrollStep,
        _onScrollWheel = options._onScrollWheel,
        parentContext = parentContext,
        overlayParent = tooltipParent,
        ownerWindow = self,
        isVisible = function() return self.root.hidden ~= true end,
        position = function(scrollRoot)
            local rootX, rootY = self.root.x or 0, self.root.y or 0
            if parentContext then rootX, rootY = parentContext.position(self.root) end
            return rootX + (surface.container.x or 0) + (scrollRoot.x or 0),
                rootY + (surface.container.y or 0) + (scrollRoot.y or 0)
        end,
    })
    self.tooltipContext = Tooltip.registerContext(self.content, tooltipParent, function(target)
        local rootX, rootY = self._scroll:_AbsolutePosition()
        return rootX + (target.x or 0), rootY + (target.y or 0) - self._scroll.scrollY
    end, parentContext)
    self.tooltipContext.ownerWindow = self
    Layout.configure(self, options.layout or options.textLayout)
    Wheel.bind(self.root, options)
    Wheel.bind(surface.background, options)
    Tooltip.bind(self, self.root, parent, options.tooltip)
    self._nisTabs = NisTabs.new(self)
    self._nisTabs:SetAlpha(self.transparencyScale)

    self.dragLayer = Components.new(ui.Layer, parent, {
        _categoryPolicy = Components.policyOf(self.root),
    })
    self.dragLayer.clickthrough = false
    Cursor.apply(self.dragLayer, config.Cursor.TOPLEVEL_V2_MOVE, true)
    self.dragLayer:Subscribe(ui.Hook.ONCLICK, function(component, x, y)
        if not self.locked and not self.dragState and not self._nisTabPress
            and type(x) == "number" and type(y) == "number"
            and x >= 0 and x < self.root.width - CLOSE_SIZE and y >= 0 and y < HEADER_HEIGHT then
            self:_BeginDrag(component, x, y)
        end
        return false
    end)
    local function move(component, x, y)
        if self._nisTabPress then
            self:_MoveNisTabDrag(component, x, y)
        else
            self:_MoveDrag(component, x, y)
        end
        return false
    end
    self.dragLayer:Subscribe(ui.Hook.ONHOLD, move)
    self.dragLayer:Subscribe(ui.Hook.ONDRAG, move)
    local function release(component, x, y)
        if self._nisTabPress then
            self:_StopNisTabDrag(component, x, y)
        else
            self:_StopDrag(true, component, x, y)
        end
        return false
    end
    self.dragLayer:Subscribe(ui.Hook.ONRELEASE, release)
    self.dragLayer:Subscribe(ui.Hook.ONDRAGCOMPLETE, function(component, _, x, y)
        return release(component, x, y)
    end)
    self:_SyncChrome()

    -- DragBounds updates the root before its callback, so this hook must be first.
    nextResizeID = nextResizeID + 1
    self._resizeHookID = "prettyui_nis_panel_parent_" .. nextResizeID
    parent:Subscribe(ui.Hook.ONRESIZE, self._resizeHookID, function()
        if WorldMap.isSuspended() then return true end
        self:_CheckDragEnvironment()
        if self.resize then self.resize:Cancel() end
        return true
    end)
    self.dragBounds = DragBounds.new(parent, self.root, function()
        if not loaded(self) then return end
        if WorldMap.isSuspended() or NisGroup.boundsChanged(self) then return end
        self:_SyncDragLayer()
        self._scroll:_LayoutThumbDrag()
        self:_SyncOverlays(self.root.hidden == true)
        self:_NotifyBoundsChange()
    end)
    self.dragBounds:Clamp()
    self:_SyncDragLayer()
    self.resize = Resize.new(parent, self.root, {
        minWidth = self.minWidth, minHeight = self.minHeight,
        maxWidth = self.maxWidth, maxHeight = self.maxHeight,
        isVisible = function()
            return not self._nisNative and not self.locked and self.root.hidden ~= true
                and self.dragState == nil and self._nisTabPress == nil
                and (not self._nisGroup or self._nisGroup.active == self)
        end,
        onBegin = function()
            self:_CancelDrag()
            self:Show()
        end,
        constrainRect = function(x, y, width, height, edge)
            return self:_ConstrainResize(x, y, width, height, edge)
        end,
        setRect = function(x, y, width, height)
            self:_ApplyRect(x, y, width, height)
        end,
        onFinish = function()
            if self._nisGroup then NisGroup.notify(self) else self:_NotifyBoundsChange() end
        end,
    })
    self:_LayoutBody()
    self:_SyncOverlays(false)
    NativeInterfaceSettings.watchTransparency(self, function(transparency)
        self:_SetBackgroundTransparency(transparency)
    end)
    Snap.register(self)
    NisGroup.register(self)
    NativeInterfaceSettings.watchLock(self, function(locked) self:_SetLocked(locked) end)
    self._lastBounds = { self.root.x, self.root.y, self.root.width, self.root.height }
    WorldMap.watch(self, function(suspended)
        if suspended then
            -- Keep rollback state until native hosts return. Releases over the
            -- map must not commit placement or discard a detached tab's origin.
            local capture = self.dragState and self.dragState.capture
                or self._nisTabPress and self._nisTabPress.component
            if capture then InterfaceMouse.EndCapture(capture) end
            if self.resize then self.resize:Cancel() end
            if self.content then Tooltip.hideContextTooltips(self.content) end
        elseif loaded(self) then
            self:_CancelDrag()
            if not self._nisNative then self.dragBounds:Refresh() end
            self:_LayoutBody()
            self:_SyncChrome()
            self:_SyncOverlays(self.root.hidden == true)
        end
    end)
    NisPersistence.register(self, options, NisGroup)
    NisNative.register(self)
    return self
end

function NisPanel.new(parent, options)
    options = NisPersistence.prepare(options or {})
    local policy = Components.checkContentParent(parent, options)
    return Components.withBatch(parent, function()
        return buildPanel(parent, options, policy)
    end)
end

return NisPanel
