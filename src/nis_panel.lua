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
local RibbonBar = require("src/ribbon_bar")
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

-- Only the shell and tab inputs survive deactivation. Consumer controls belong
-- to one buildContent invocation; its cleanup runs before their handles expire.
function NisPanel:_ReleaseContent()
    if self._scroll == nil or self._releasingContent then return end
    self._releasingContent = true
    local scroll, content = self._scroll, self.content
    local contentHost, contentHostInterfaceID = self._contentHost, self._contentHostInterfaceID
    local contentInterfaceID = self._contentInterfaceID
    local cleanup = self._contentCleanup
    self._contentCleanup = nil
    local problem
    local function release(callback, ...)
        local ok, failure = pcall(callback, ...)
        if not ok and problem == nil then problem = failure end
    end
    if cleanup then release(cleanup) end
    self.scrollY = scroll.scrollY
    self.scrollable = scroll.scrollable
    self.scrollStep = scroll.scrollStep
    if self.tooltip then release(self.tooltip.Hide, self.tooltip) end
    release(RowBackgrounds.clear, self.rowBackgrounds, contentInterfaceID)
    self.rowBackgrounds = {}
    release(Tooltip.unregisterContext, content)
    self.tooltipContext = nil
    release(Layout.destroyManaged, self)
    release(scroll.Destroy, scroll)
    self._scroll = nil
    self.viewport, self.content = nil, nil
    self._contentHost, self._contentHostInterfaceID, self._contentInterfaceID = nil, nil, nil
    self._onScrollWheel = self._contentWheelHandler
    self.scrollbarVisible = false
    self._flowLayout = nil
    self._releasingContent = nil
    if contentHost and ui.Interfaces:GetInterface(contentHostInterfaceID) ~= nil then
        release(Components.refresh, contentHost)
    end
    if problem ~= nil then error(problem, 0) end
end

function NisPanel:_SetClassicHost(host)
    if host == self._nisClassicHost and (host ~= nil or self._scroll == nil) then return end
    -- Finish the outgoing page before changing its host. Even a failing
    -- cleanup must clear ownership without mounting a replacement.
    local ok, problem = pcall(self._ReleaseContent, self)
    self._nisClassicHost, self._nisClassicHostInterfaceID = nil, nil
    if not ok then error(problem, 0) end
    if host == nil or not self._nisClassic or self._nisHidden or self._destroyed then return end
    local hostInterfaceID = host.interfaceID
    if ui.Interfaces:GetInterface(hostInterfaceID) == nil then return end
    self._nisClassicHost, self._nisClassicHostInterfaceID = host, hostInterfaceID
    ok, problem = pcall(self._SyncContent, self, true)
    if not ok then
        self._nisClassicHost, self._nisClassicHostInterfaceID = nil, nil
        error(problem, 0)
    end
end

local function classicState(self)
    local snapshot = NisNative.remember(self) or self._nisNativePending
    local native
    if snapshot then
        local free = snapshot.free
        native = {
            frame = snapshot.frame, frames = { table.unpack(snapshot.frames) },
            index = snapshot.index, beforeNative = snapshot.beforeNative,
            selected = snapshot.selected,
            free = { x = free.x, y = free.y, width = free.width, height = free.height },
        }
    end
    return { contentReady = self._contentReady, native = native }
end

function NisPanel:_SetClassicMode(enabled)
    if enabled ~= true then
        local ok, problem = pcall(self._SetClassicHost, self, nil)
        self._nisClassic = false
        self._nisClassicState = nil
        self:_CreateDragBounds()
        if not ok then error(problem, 0) end
        return
    end
    self._nisClassic = true
    local saved = self._nisClassicState
    if saved and saved.suspended then return end
    saved = saved or classicState(self)
    self._nisClassicState = saved
    saved.suspended = true
    self:_CancelDrag()
    if self.resize then self.resize:Cancel(); self.resize:SetEnabled(false) end
    if self.dragBounds then self.dragBounds:Destroy(); self.dragBounds = nil end
    local ok, problem = pcall(self._SetClassicHost, self, nil)
    NisGroup.clearPanel(self)
    NisNative.detach(self)
    self._nisNativePending = saved.native
    if loaded(self) then
        Components.setHidden(self.root, true)
        self:_SyncChrome()
        self:_SyncOverlays(true)
    end
    if not ok then error(problem, 0) end
end

function NisPanel:_SyncContent(visible)
    local host = self._nisClassicHost
    if not self._nisClassic and self.surface then host = self.surface.container end
    if self._nisClassic then
        visible = host ~= nil and not self._nisHidden
            and ui.Interfaces:GetInterface(self._nisClassicHostInterfaceID) ~= nil
    end
    if not visible then self:_ReleaseContent(); return end
    if not self._contentReady or self._destroyed or self._scroll or self._buildingContent
        or self._releasingContent or not loaded(self) then return end
    self._buildingContent = true
    self._buildingOverlays = {}
    local scrollY = self.scrollY or 0
    local classic = self._nisClassic == true
    local parentContext = Tooltip.getContext(self._nisClassic and host or self.parent)
    local tooltipParent = parentContext and parentContext.parent or (self._nisClassic and host or self.parent)
    local ok, problem = pcall(function()
        self._contentHost, self._contentHostInterfaceID = host, host.interfaceID
        Scroll.attach(self, host, {
            width = 0, height = 0, widthAnchor = 1, heightAnchor = 1,
            contentHeight = self._minimumContentHeight,
            scrollable = self.scrollable,
            scrollStep = self.scrollStep,
            _onScrollWheel = self._contentWheelHandler,
            parentContext = parentContext,
            overlayParent = tooltipParent,
            ownerWindow = self,
            isVisible = function()
                if classic then
                    return self._nisClassicHost == host and not self._nisHidden
                        and not WorldMap.isSuspended()
                        and ui.Interfaces:GetInterface(self._nisClassicHostInterfaceID) ~= nil
                end
                return not self._nisClassic and self.root.hidden ~= true
            end,
            position = function(scrollRoot)
                if classic then
                    local hostX, hostY = parentContext.position(host)
                    return hostX + (scrollRoot.x or 0), hostY + (scrollRoot.y or 0)
                end
                local rootX, rootY = self.root.x or 0, self.root.y or 0
                if parentContext then rootX, rootY = parentContext.position(self.root) end
                return rootX + (self.surface.container.x or 0) + (scrollRoot.x or 0),
                    rootY + (self.surface.container.y or 0) + (scrollRoot.y or 0)
            end,
        })
        self._contentInterfaceID = self._scroll.interfaceID
        self.tooltipContext = Tooltip.registerContext(self.content, tooltipParent, function(target)
            local rootX, rootY = self._scroll:_AbsolutePosition()
            return rootX + (target.x or 0), rootY + (target.y or 0) - self._scroll.scrollY
        end, parentContext)
        self.tooltipContext.ownerWindow = self
        Layout.configure(self, self._contentLayout)
        self.interfaceID = self._shellInterfaceID
        if self.buildContent then
            local cleanup = self.buildContent(self)
            assert(cleanup == nil or type(cleanup) == "function",
                "PrettyUI: NisPanel buildContent must return a cleanup function or nil")
            self._contentCleanup = cleanup
        end
        self:SetScrollPosition(scrollY)
        self:RefreshRowBackgrounds()
    end)
    self._buildingContent = nil
    if not ok then
        self.interfaceID = self._shellInterfaceID
        pcall(self._ReleaseContent, self)
        for component in pairs(self._buildingOverlays) do
            local overlay = self.overlays[component]
            if overlay then
                self.overlays[component] = nil
                if ui.Interfaces:GetInterface(overlay.interfaceID) ~= nil then
                    pcall(component.Destroy, component)
                end
            end
        end
        self._buildingOverlays = nil
        self._contentHost, self._contentHostInterfaceID, self._contentInterfaceID = nil, nil, nil
        self.scrollY = scrollY
        error(problem, 0)
    end
    self._buildingOverlays = nil
end

function NisPanel:_SyncDragLayer()
    if not loaded(self) or self.dragLayer == nil then return end
    local capture = self.dragState and self.dragState.capture == self.dragLayer
        and self.dragState.captureExpanded
    local visible = not self._nisClassic and (capture or not self._nisNative
        and self.root.hidden ~= true and not self.locked
        and (not self._nisGroup or self._nisGroup.active == self))
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
    local shellHidden = hidden
    if self._nisClassic then
        hidden = self._nisClassicHost == nil or self._nisHidden or WorldMap.isSuspended()
            or ui.Interfaces:GetInterface(self._nisClassicHostInterfaceID) == nil
        shellHidden = true
    end
    for component, overlay in pairs(self.overlays) do
        if ui.Interfaces:GetInterface(overlay.interfaceID) ~= nil then
            if not hidden and overlay.layout then overlay.layout() end
            Components.setHidden(component, hidden or
                (overlay.isVisible and not overlay.isVisible() or false))
            if not component.hidden then component:MoveToFront() end
        end
    end
    if self._nisTabs then self._nisTabs:Sync(shellHidden) end
    self:_SyncDragLayer()
    if self.resize then
        self.resize:SetEnabled(not self._nisClassic and not self._nisNative and not self.locked
            and not shellHidden and self.dragState == nil and self._nisTabPress == nil
            and (not self._nisGroup or self._nisGroup.active == self))
        self.resize:Refresh()
    end
end

function NisPanel:_RegisterOverlay(component, isVisible, layout)
    self.overlays[component] = {
        interfaceID = component.interfaceID,
        isVisible = isVisible,
        layout = layout,
    }
    if self._buildingOverlays then self._buildingOverlays[component] = true end
end

function NisPanel:_UnregisterOverlay(component)
    self.overlays[component] = nil
end

function NisPanel:_SyncChrome()
    if not loaded(self) then return end
    local visible = not self._nisClassic and not self._nisNative and not self.locked
        and self.root.hidden ~= true
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
    if self._nisClassic then
        self:_SyncChrome()
        self:_SyncOverlays(false)
        return
    end
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
    if self._nisClassic or not loaded(self) then return end
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
        if self._scroll then self._scroll:SetSize(0, 0, 1, 1) end
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
    if self._scroll then self._scroll:SetSize(0, 0, 1.0, 1.0) end
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

function NisPanel:_NotifyBoundsChange(preserveNative)
    if self._nisClassic or WorldMap.isSuspended() or not loaded(self) or self._updatingBounds
        or self.dragState or (self.resize and self.resize.dragState)
        or self._lastBounds == nil then return end
    local root, previous = self.root, self._lastBounds
    local x, y, width, height = root.x, root.y, root.width, root.height
    if previous[1] == x and previous[2] == y and previous[3] == width and previous[4] == height then return end
    previous[1], previous[2], previous[3], previous[4] = x, y, width, height
    if not preserveNative or self._nisNativePending == nil then NisPersistence.bounds(self) end
    if self.onBoundsChange then self.onBoundsChange(self, x, y, width, height) end
end

function NisPanel:SetSize(width, height)
    if self._nisClassic then return end
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
    local contentInterfaceID = self._contentInterfaceID or self.interfaceID
    RowBackgrounds.clear(self.rowBackgrounds, contentInterfaceID)
    if self.content == nil or ui.Interfaces:GetInterface(contentInterfaceID) == nil then
        self.rowBackgrounds = {}
        return
    end
    local host = self._contentHost or self.surface.container
    self.rowBackgrounds = RowBackgrounds.apply(self.content, host.height, self,
        self.rowBackgroundColours, self.rowBackgroundEdgeToEdge)
end

function NisPanel:SetTooltip(value)
    return Tooltip.set(self, value)
end

function NisPanel:IsActive()
    return not self._destroyed and not self._nisHidden
end

function NisPanel:SetActive(active)
    if not loaded(self) or self._destroyed then return end
    active = active == true
    if self._nisClassic then
        if active then
            if self._nisHidden then
                self._nisHidden = false
                NisPersistence.setActive(self, true, NisGroup)
                self._nisNativePending = self._nisNativePending or self._nisInactiveNative
            end
            RibbonBar.sync(self)
            return RibbonBar.selectClassic(self, false)
        end
        if self._nisHidden then
            if RibbonBar.isClassicSelected(self) then
                return RibbonBar.selectClassic(self, true)
            end
            return
        end
        NisPersistence.capture(self)
        self._nisInactiveGroup = NisGroup.snapshot(self) or self._nisInactiveGroup
        self._nisInactiveNative = NisNative.remember(self)
            or self._nisNativePending or self._nisInactiveNative
        self._nisHidden = true
        NisPersistence.setActive(self, false, NisGroup)
        local ok, problem = pcall(self._ReleaseContent, self)
        if RibbonBar.isClassicSelected(self) then
            local collapsed, failure = pcall(RibbonBar.selectClassic, self, true)
            if not collapsed and ok then ok, problem = false, failure end
        end
        if self._nisClassicHost ~= nil then
            local released, failure = pcall(self._SetClassicHost, self, nil)
            if not released and ok then ok, problem = false, failure end
        end
        NisNative.detach(self)
        NisGroup.clearPanel(self)
        NisGroup.undock(self)
        if loaded(self) then
            Components.setHidden(self.root, true)
            self:_SyncChrome()
            self:_SyncOverlays(true)
        end
        RibbonBar.sync(self)
        if not ok then error(problem, 0) end
        return
    end
    if active == self:IsActive() then return end
    self:_CancelDrag()
    if self.resize then self.resize:Cancel() end
    if active then
        self._nisHidden = false
        local restored = NisPersistence.setActive(self, true, NisGroup)
        if not restored and self._nisInactiveGroup then
            NisGroup.resume(self, self._nisInactiveGroup)
        end
        self._nisNativePending = self._nisNativePending or self._nisInactiveNative
        if self._nisNativePending then
            NisNative.register(self, true)
        end
        self._nisInactiveGroup, self._nisInactiveNative = nil, nil
        RibbonBar.sync(self)
        self:Show()
        NisPersistence.capture(self)
        return
    end
    NisPersistence.capture(self)
    self._nisInactiveGroup = NisGroup.snapshot(self)
    self._nisInactiveNative = NisNative.remember(self) or self._nisNativePending
    self._nisHidden = true
    NisPersistence.setActive(self, false, NisGroup)
    local ok, problem = pcall(self._ReleaseContent, self)
    NisNative.detach(self)
    NisGroup.clearPanel(self)
    NisGroup.undock(self)
    if loaded(self) then
        Components.setHidden(self.root, true)
        self:_SyncChrome()
        self:_SyncOverlays(true)
        self:_NotifyBoundsChange()
    end
    RibbonBar.sync(self)
    if not ok then error(problem, 0) end
end

function NisPanel:Show()
    if not loaded(self) then return end
    if self._nisHidden then return self:SetActive(true) end
    if self._nisClassic then return RibbonBar.selectClassic(self, false) end
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
    self:_SyncContent(true)
    self.root:MoveToFront()
    self:_SyncChrome()
    if not self.dragLayer.hidden then self.dragLayer:MoveToFront() end
    self:_SyncOverlays(false)
end

function NisPanel:Hide()
    self:SetActive(false)
end

function NisPanel:Close()
    self:_CancelDrag()
    if self.resize then self.resize:Cancel() end
    self:SetActive(false)
    if self.onClose then self.onClose(self) end
    if self._destroyed then return end
    if self.destroyOnClose then self:Destroy() else self:Hide() end
end

function NisPanel:Destroy()
    if self._destroyed or self._destroying then return end
    self._destroying = true
    self._contentReady = false
    local ok, problem = pcall(RibbonBar.unregister, self)
    self._nisClassicHost, self._nisClassicHostInterfaceID = nil, nil
    local released, releaseProblem = pcall(self._ReleaseContent, self)
    if not released and ok then ok, problem = false, releaseProblem end
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
    Tooltip.unbind(self)
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
    self._nisInactiveGroup, self._nisInactiveNative = nil, nil
    self._nisClassicState = nil
    if not ok then error(problem, 0) end
end

ContentMethods.installSingle(NisPanel)
-- Inactive pages retain scroll preferences without allocating a viewport.
function NisPanel:SetScrollable(value)
    self.scrollable = value ~= false
    if not self.scrollable then self.scrollY = 0 end
    if self._scroll then self._scroll:SetScrollable(value) end
end

function NisPanel:SetScrollPosition(y)
    if self._scroll then return self._scroll:SetScrollPosition(y) end
    self.scrollY = self.scrollable and math.max(0, math.floor(y or 0)) or 0
end

function NisPanel:ScrollBy(delta)
    self:SetScrollPosition(self.scrollY + delta)
end

function NisPanel:ScrollToChild(child, topOffset)
    assert(self._scroll, "PrettyUI: select the NisPanel tab before scrolling to a child")
    return self._scroll:ScrollToChild(child, topOffset)
end

function NisPanel:SetContentHeight(height)
    if self._scroll then return self._scroll:SetContentHeight(height) end
    self._minimumContentHeight = math.max(0, math.floor(height or 0))
    self.contentHeight = self._minimumContentHeight
end
NisDrag.install(NisPanel)

function NisPanel:DockTo(target)
    if self._nisClassic then return false end
    self:_CancelDrag()
    if type(target) == "table" and target.root then
        if target._nisNative then return NisNative.dock(self, target._nisNative) end
        return NisGroup.dock(self, target)
    end
    return NisNative.dock(self, target)
end

function NisPanel:Undock()
    if self._nisClassic then return end
    self:_CancelDrag()
    NisNative.detach(self)
    self._nisInactiveGroup, self._nisInactiveNative = nil, nil
    NisGroup.undock(self)
    NisPersistence.detach(self)
end

function NisPanel:SelectTab()
    if self._nisClassic then return self:Show() end
    if self._nisNative then return NisNative.select(self) end
    NisGroup.select(self)
end

function NisPanel:_CreateDragBounds()
    if self.dragBounds or self._nisClassic or not loaded(self) then return end
    self.dragBounds = DragBounds.new(self.parent, self.root, function()
        if self._nisClassic or not loaded(self) then return end
        if WorldMap.isSuspended() or NisGroup.boundsChanged(self) then return end
        self:_SyncDragLayer()
        if self._scroll then self._scroll:_LayoutThumbDrag() end
        self:_SyncOverlays(self.root.hidden == true)
        -- Native hosts can return after the parent finishes its mode-change
        -- reflow. Automatic fallback placement must not discard that target.
        self:_NotifyBoundsChange(true)
    end)
    self.dragBounds:Clamp()
    self:_SyncDragLayer()
end

local function buildPanel(parent, options, policy)
    local self = setmetatable({}, NisPanel)
    self.parent = parent
    self._nisClassic = NativeInterfaceSettings.isClassicUI()
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
    self._nisHidden = options.active == false
    self.onClose = options.onClose
    self.onBoundsChange = options.onBoundsChange
    self.destroyOnClose = options.destroyOnClose == true
    self.rowBackgroundColours = options.rowBackgroundColours or options.rowBackgroundColors or {}
    self.rowBackgroundEdgeToEdge = options.rowBackgroundEdgeToEdge == true
    self.rowBackgrounds = {}
    self.overlays = {}
    assert(options.buildContent == nil or type(options.buildContent) == "function",
        "PrettyUI: NisPanel buildContent must be a function")
    self.buildContent = options.buildContent
    self._contentLayout = options.layout or options.textLayout
    self._minimumContentHeight = options.contentHeight or 0
    self._contentWheelHandler = options._onScrollWheel
    self.scrollable = options.scrollable ~= false
    self.scrollStep = options.scrollStep or 32
    self.scrollY = 0
    self.contentHeight = self._minimumContentHeight
    self.contentWidth = 0
    self.scrollbarVisible = false

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
    Components.setHidden(self.root, self._nisHidden or self._nisClassic)
    self.interfaceID = surface.interfaceID
    self._shellInterfaceID = self.interfaceID
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
        if WorldMap.isSuspended() or self._nisClassic then return true end
        self:_CheckDragEnvironment()
        if self.resize then self.resize:Cancel() end
        return true
    end)
    self:_CreateDragBounds()
    self.resize = Resize.new(parent, self.root, {
        minWidth = self.minWidth, minHeight = self.minHeight,
        maxWidth = self.maxWidth, maxHeight = self.maxHeight,
        isVisible = function()
            return not self._nisClassic and not self._nisNative and not self.locked
                and self.root.hidden ~= true and self.dragState == nil
                and self._nisTabPress == nil
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
            if self._nisClassic then
                self:_SyncOverlays(false)
                return
            end
            if not self._nisNative and self.dragBounds then self.dragBounds:Refresh() end
            self:_LayoutBody()
            if self.root.hidden ~= true then self:_SyncContent(true) end
            self:_SyncChrome()
            self:_SyncOverlays(self.root.hidden == true)
        end
    end)
    NisPersistence.register(self, options, NisGroup)
    if not self._nisHidden and not self._nisClassic then NisNative.register(self) end
    self._contentReady = true
    local ok, problem = pcall(function() self:_SyncContent(self.root.hidden ~= true) end)
    if not ok then
        pcall(self.Destroy, self)
        error(problem, 0)
    end
    if not self._destroyed then RibbonBar.register(self) end
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
