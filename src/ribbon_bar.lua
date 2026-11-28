local Components = require("src/core/components")
local RibbonButton = require("src/ribbon_button")
local SpriteButton = require("src/sprite_button")
local SimpleView = require("src/simple_view")
local InterfaceMouse = require("src/core/mouse")
local Sprites = require("src/core/sprites")
local Tooltip = require("src/tooltip")
local Window = require("src/window")
local WorldMap = require("src/core/world_map")
local NativeInterfaceSettings = require("src/core/native_interface_settings")
local ClassicLayout = require("src/nis/classic_layout")
local NisGroup = require("src/nis/group")
local NisPersistence = require("src/nis/persistence")
local NisNative = require("src/nis/native")
local Wheel = require("src/core/wheel")
local Settings = require("src/settings")

local RibbonBar = {}

local EVENT_ID = "prettyui_ribbon_bar"
local INDICATOR_SIZE = 12
local BORDER = 4
local PADDING = 6
local BUTTON_SIZE = 32
local SETTINGS_BUTTON_SIZE = 24
local SETTINGS_BUTTON_OFFSET = (BUTTON_SIZE - SETTINGS_BUTTON_SIZE) / 2
local BUTTON_GAP = 2
local AUTO_HIDE_SLIDE_STEP = 8
local SETTINGS_WIDTH = 480
local SETTINGS_HEIGHT = 410
local CLASSIC_CONTENT_WIDTH = 300
local MODE_LAYOUT_SETTLE_TICKS = 10 -- 200 ms at the client's fixed 50 Hz.
local RAIL_WIDTH = BUTTON_SIZE + PADDING * 2
local PITCH = BUTTON_SIZE + BUTTON_GAP
local SETTINGS_PITCH = SETTINGS_BUTTON_SIZE + BUTTON_GAP

local entries = {}
local byPanel = {}
local gameArea, root, interfaceID, frame, settingsButton, settingsWindow
local settingsView, settingsLayerView
local started, settingsOpen, hitboxHovered = false, false, false
local slideOffset = 0
local classic = false
local cropDelayTicks = 0
local classicSelectedPanel, classicBody
local iconList, previousIndicator, nextIndicator
local iconScroll = 0
local classicSelecting = false
local mountKey, mountGeneration
local layoutWidth, layoutHeight, layoutPosition, layoutSlideOffset, layoutScrollY, layoutCount
local ensureMounted, destroySurface, collapseClassic

local function identity(component)
    if component == nil then return nil end
    return component.interfaceID
        .. ":"
        .. component.staticID
        .. ":"
        .. component.categoryID
        .. ":"
        .. component.dynamicID
end

local function nativeComponent(name)
    local packed = id.Component[name]
    return packed and ui.Interfaces:GetComponent(packed) or nil
end

local function classicWidths(expanded)
    local width = gameArea and gameArea.width or 0
    local rail = math.min(RAIL_WIDTH, math.max(0, width - 1))
    if not expanded then return rail, 0 end
    local inventory = nativeComponent("TOPLEVEL_V2__INVENTORY_WINDOW")
    if not inventory or inventory.width <= 0 then return rail, 0 end
    local minimum = math.ceil(inventory.width)
    local available = width - 1 - rail
    if available < minimum then return rail, 0 end
    local body = math.min(math.max(CLASSIC_CONTENT_WIDTH, minimum), available)
    return rail, body
end

local function syncClassicButtons()
    for _, entry in ipairs(entries) do
        if entry.button then entry.button:SetActive(entry.panel == classicSelectedPanel) end
    end
end

local function reserveClassic(width)
    local ok, result = pcall(ClassicLayout.update, width, cropDelayTicks > 0)
    if (not ok or not result) and root and ui.Interfaces:GetInterface(interfaceID) ~= nil then
        Components.setHidden(root, true)
    end
    if not ok then error(result, 0) end
    return result
end

local function sprite(parent, spriteID)
    local component = Components.new(ui.Sprite, parent)
    component.spriteID = spriteID
    component.clickthrough = true
    return component
end

local function createFrame(parent)
    local hud = Sprites.HUD_WINDOW
    local result = {}
    result.background = sprite(parent, hud.content)
    result.background.isTiling = true
    result.top = sprite(parent, hud.top)
    result.top.isTiling = true
    result.bottom = sprite(parent, hud.bottom)
    result.bottom.isTiling = true
    result.left = sprite(parent, hud.side)
    result.left.isTiling = true
    result.right = sprite(parent, hud.side)
    result.right.isTiling = true
    result.right.isFlippedHorizontally = true
    result.topLeft = sprite(parent, hud.cornerTop)
    result.topRight = sprite(parent, hud.cornerTop)
    result.topRight.isFlippedHorizontally = true
    result.bottomLeft = sprite(parent, hud.cornerBottom)
    result.bottomRight = sprite(parent, hud.cornerBottom)
    result.bottomRight.isFlippedHorizontally = true
    return result
end

local function layoutFrame()
    frame.background:SetPos(BORDER, BORDER)
    frame.background:SetSize(-BORDER * 2, -BORDER * 2, 1, 1)
    frame.top:SetPos(BORDER, 0)
    frame.top:SetSize(-BORDER * 2, BORDER, 1)
    frame.bottom:SetPos(BORDER, -BORDER, 0, 1)
    frame.bottom:SetSize(-BORDER * 2, BORDER, 1)
    frame.left:SetPos(0, BORDER)
    frame.left:SetSize(BORDER, -BORDER * 2, 0, 1)
    frame.right:SetPos(-BORDER, BORDER, 1)
    frame.right:SetSize(BORDER, -BORDER * 2, 0, 1)
    frame.topLeft:SetSize(BORDER, BORDER)
    frame.topRight:SetPos(-BORDER, 0, 1)
    frame.topRight:SetSize(BORDER, BORDER)
    frame.bottomLeft:SetPos(0, -BORDER, 0, 1)
    frame.bottomLeft:SetSize(BORDER, BORDER)
    frame.bottomRight:SetPos(-BORDER, -BORDER, 1, 1)
    frame.bottomRight:SetSize(BORDER, BORDER)
end

local function barSize()
    if classic then
        local rail, body = classicWidths(classicSelectedPanel ~= nil or settingsOpen)
        return rail + body, gameArea.height
    end
    local position = Settings.get("ribbonBarPosition")
    local span = position == "top" and gameArea.width or gameArea.height
    local available = math.max(0, span - PADDING * 2 - SETTINGS_PITCH)
    local count = math.min(#entries, Settings.get("ribbonBarButtonCap"))
    local run = math.max(0, count * PITCH - BUTTON_GAP)
    if #entries > count or run > available then
        count = math.min(count, math.max(0, math.floor((available - INDICATOR_SIZE * 2 + BUTTON_GAP) / PITCH)))
        run = math.max(0, count * PITCH - BUTTON_GAP) + INDICATOR_SIZE * 2
    end
    run = math.min(span, PADDING * 2 + SETTINGS_PITCH + run)
    if position == "top" then return run, RAIL_WIDTH end
    return RAIL_WIDTH, run
end

local function ribbonOrigin(width, height)
    if classic then return gameArea.width - width, 0 end
    local position = Settings.get("ribbonBarPosition")
    if position == "top" then
        return math.floor(((gameArea.width or 0) - width) / 2), -slideOffset
    end
    local y = math.floor(((gameArea.height or 0) - height) / 2)
    if position == "right" then
        return (gameArea.width or 0) - width + slideOffset, y
    end
    return -slideOffset, y
end

local function isHitboxHovered(width, height)
    local mouse = InterfaceMouse.GetPosition()
    if mouse == nil then return false end
    local x, y = ribbonOrigin(width, height)
    local position = Settings.get("ribbonBarPosition")
    -- The unslid edge stays reachable while the bar is auto-hidden.
    if position == "top" then
        y = 0
    elseif position == "right" then
        x = (gameArea.width or 0) - width
    else
        x = 0
    end
    x, y = x + (gameArea.x or 0), y + (gameArea.y or 0)
    return mouse.x >= x and mouse.x < x + width and mouse.y >= y and mouse.y < y + height
end

local function layoutClassicBody(width, height, rearrange)
    local _, body = classicWidths(classicSelectedPanel ~= nil or settingsOpen)
    if rearrange then root:SetPos(-width, 0, 1, 0) end
    local resized = classicBody.width ~= body or classicBody.height ~= height
    if resized then
        classicBody:SetSize(body, height)
        frame.contentBackground:SetSize(math.max(0, body - BORDER * 2), math.max(0, height - BORDER * 2))
        if settingsView then
            settingsView:SetSize(math.max(0, body - BORDER * 2), math.max(0, height - BORDER * 2))
        end
    end
    Components.setHidden(classicBody, classicSelectedPanel == nil and not settingsOpen)
    if resized and classicSelectedPanel and classicSelectedPanel._scroll then
        classicSelectedPanel._scroll:Refresh()
        classicSelectedPanel:RefreshRowBackgrounds()
    end
    return body
end

local function arrangeIconList(width, height, body, horizontal, gutter, extent, total)
    root:SetSize(width, height)
    settingsButton.root:SetPos(
        body + PADDING + (horizontal and 0 or SETTINGS_BUTTON_OFFSET),
        PADDING + (horizontal and SETTINGS_BUTTON_OFFSET or 0)
    )
    if horizontal then
        iconList:SetPos(PADDING + SETTINGS_PITCH + gutter, PADDING)
        iconList:SetSize(extent, BUTTON_SIZE)
        iconList:SetScrollSize(math.max(extent, total), BUTTON_SIZE)
        previousIndicator:SetPos(PADDING + SETTINGS_PITCH, PADDING + (BUTTON_SIZE - INDICATOR_SIZE) / 2)
        nextIndicator:SetPos(width - PADDING - INDICATOR_SIZE, PADDING + (BUTTON_SIZE - INDICATOR_SIZE) / 2)
    else
        iconList:SetPos(body + PADDING, PADDING + SETTINGS_PITCH + gutter)
        iconList:SetSize(BUTTON_SIZE, extent)
        iconList:SetScrollSize(BUTTON_SIZE, math.max(extent, total))
        previousIndicator:SetPos(body + PADDING + (BUTTON_SIZE - INDICATOR_SIZE) / 2, PADDING + SETTINGS_PITCH)
        nextIndicator:SetPos(body + PADDING + (BUTTON_SIZE - INDICATOR_SIZE) / 2, height - PADDING - INDICATOR_SIZE)
    end
    previousIndicator.rotationDegrees = horizontal and -90 or 0
    nextIndicator.rotationDegrees = horizontal and -90 or 0
end

local function layoutIcons(width, height, body, horizontal, rearrange)
    local available = math.max(0, (horizontal and width or height) - PADDING * 2 - SETTINGS_PITCH)
    local total = math.max(0, #entries * PITCH - BUTTON_GAP)
    local gutter = total > available and INDICATOR_SIZE or 0
    local extent = math.max(0, available - gutter * 2)
    if rearrange then arrangeIconList(width, height, body, horizontal, gutter, extent, total) end
    iconScroll = math.max(0, math.min(iconScroll, total - extent))
    iconList:SetScrollPos(horizontal and iconScroll or 0, horizontal and 0 or iconScroll)
    Components.setHidden(previousIndicator, gutter == 0 or iconScroll == 0)
    Components.setHidden(nextIndicator, gutter == 0 or iconScroll >= total - extent)
    for index, entry in ipairs(entries) do
        if entry.button then
            local offset = (index - 1) * PITCH
            if rearrange then entry.button.root:SetPos(horizontal and offset or 0, horizontal and 0 or offset) end
            entry.visible = extent > 0 and offset + BUTTON_SIZE > iconScroll and offset < iconScroll + extent
            entry.button.root.enabled = entry.visible
            Components.setHidden(entry.button.root, not entry.visible)
        end
    end
end

local function layoutRoot()
    if root == nil or ui.Interfaces:GetInterface(interfaceID) == nil then return end
    local position = Settings.get("ribbonBarPosition")
    local width, height = barSize()
    local rearrange = width ~= layoutWidth
        or height ~= layoutHeight
        or position ~= layoutPosition
        or #entries ~= layoutCount
    if not rearrange and slideOffset == layoutSlideOffset and iconScroll == layoutScrollY then return end
    local horizontal = not classic and position == "top"
    local body = 0
    if classic then
        body = layoutClassicBody(width, height, rearrange)
    elseif horizontal then
        root:SetPos(-math.floor(width / 2), -slideOffset, 0.5, 0)
    elseif position == "right" then
        root:SetPos(-width + slideOffset, -math.floor(height / 2), 1, 0.5)
    else
        root:SetPos(-slideOffset, -math.floor(height / 2), 0, 0.5)
    end
    layoutIcons(width, height, body, horizontal, rearrange)
    layoutWidth, layoutHeight, layoutPosition = width, height, position
    layoutSlideOffset, layoutScrollY, layoutCount = slideOffset, iconScroll, #entries
end

local function scrollIcons(_, delta)
    if WorldMap.isSuspended() then return true end
    local previous = iconScroll
    iconScroll = iconScroll + delta * PITCH
    layoutRoot()
    return previous == iconScroll
end

local function closeSettings()
    settingsOpen = false
end

local function mountSettingsLayer(event)
    Settings.destroy(settingsLayerView)
    settingsLayerView = SimpleView.new(event.component, {
        categoryID = "auto",
        width = 0,
        height = 0,
        widthAnchor = 1,
        heightAnchor = 1,
    })
    local view = settingsLayerView
    view.root:Subscribe(ui.Hook.ONRESIZE, EVENT_ID, function() view:Refresh() end)
    Settings.build(view, true)
end

local function showSettings()
    if classic then
        local rail, body = classicWidths(true)
        if body == 0 then return end
        collapseClassic(false)
        if not reserveClassic(rail + body) then return end
        settingsOpen = true
        layoutRoot()
        settingsView = SimpleView.new(classicBody, {
            categoryID = "auto",
            x = BORDER,
            y = BORDER,
            width = math.max(0, body - BORDER * 2),
            height = math.max(0, gameArea.height - BORDER * 2),
        })
        Settings.build(settingsView, true)
        return
    end
    if settingsWindow then
        settingsOpen = true
        settingsWindow:Show()
        return
    end
    settingsWindow = Window.new(gameArea, {
        categoryID = "auto",
        title = "PrettyUI settings",
        x = -math.floor(SETTINGS_WIDTH / 2),
        y = -math.floor(SETTINGS_HEIGHT / 2),
        xAnchor = 0.5,
        yAnchor = 0.5,
        width = SETTINGS_WIDTH,
        height = SETTINGS_HEIGHT,
        minWidth = SETTINGS_WIDTH,
        minHeight = SETTINGS_HEIGHT,
        maxWidth = SETTINGS_WIDTH,
        maxHeight = SETTINGS_HEIGHT,
        onClose = closeSettings,
    })
    Settings.build(settingsWindow)
    settingsOpen = true
end

local function toggleSettings()
    if settingsOpen then
        if classic then
            collapseClassic()
        else
            settingsWindow:Close()
        end
    else
        showSettings()
    end
end

destroySurface = function(keepLayout)
    local selected = classicSelectedPanel
    classicSelectedPanel = nil
    local ok, problem = true, nil
    if selected then
        ok, problem = pcall(selected._SetClassicHost, selected, nil)
    end
    if not keepLayout then ClassicLayout.restore() end
    Settings.destroy(settingsWindow)
    Settings.destroy(settingsView)
    settingsWindow, settingsView = nil, nil
    settingsOpen, hitboxHovered, slideOffset = false, false, 0
    if settingsButton then
        settingsButton:Destroy()
        settingsButton = nil
    end
    for _, entry in ipairs(entries) do
        if entry.button then
            entry.button:Destroy()
            entry.button = nil
        end
    end
    if root then
        WorldMap.unwatch(root)
        Tooltip.unregisterContext(root)
        if classicBody then Tooltip.unregisterContext(classicBody) end
        if iconList then Tooltip.unregisterContext(iconList) end
        if ui.Interfaces:GetInterface(interfaceID) ~= nil then root:Destroy() end
        root = nil
    end
    frame, gameArea, interfaceID = nil, nil, nil
    classicBody, iconList, iconScroll = nil, nil, 0
    previousIndicator, nextIndicator = nil, nil
    mountKey, mountGeneration = nil, nil
    layoutWidth = nil
    if not ok then error(problem, 0) end
end

local function clearEntries()
    for _, entry in ipairs(entries) do
        byPanel[entry.panel] = nil
    end
    entries = {}
end

local function panelLoaded(panel)
    if
        panel._destroyed
        or panel._destroying
        or panel.root == nil
        or ui.Interfaces:GetInterface(panel.interfaceID) == nil
    then
        return false
    end
    local entry = byPanel[panel]
    if entry then
        local shell = entry.shell
        local fresh = ui.Interfaces:GetComponent(table.unpack(shell))
        return fresh ~= nil
            and fresh.interfaceID == shell[1]
            and fresh.staticID == shell[2]
            and fresh.categoryID == shell[3]
            and fresh.dynamicID == shell[4]
    end
    return true
end

local function removeEntry(index)
    local entry = entries[index]
    local ok, problem = true, nil
    if classicSelectedPanel == entry.panel then
        ok, problem = pcall(collapseClassic, #entries > 1)
    end
    table.remove(entries, index)
    byPanel[entry.panel] = nil
    if entry.button then
        entry.button:Destroy()
        entry.button = nil
    end
    if not ok then error(problem, 0) end
end

local function createEntryButton(entry)
    local panel = entry.panel
    layoutWidth = nil
    entry.button = RibbonButton.new(iconList, panel.tabIcon, function()
        if byPanel[panel] ~= entry or not panelLoaded(panel) or not entry.visible then return end
        if classic then
            if not panel:IsActive() then
                panel:SetActive(true)
            else
                RibbonBar.selectClassic(panel, true)
            end
        else
            panel:SetActive(not panel:IsActive())
        end
        RibbonBar.sync(panel)
    end, {
        _categoryPolicy = "auto",
        tooltip = panel.tabText or "Panel",
        _onScrollWheel = scrollIcons,
    })
    entry.button:SetActive(classic and classicSelectedPanel == panel or not classic and panel:IsActive())
    entry.icon, entry.text = panel.tabIcon, panel.tabText
end

local function snapshot(panel)
    local native = NisNative.remember(panel) or panel._nisNativePending
    if native then
        local free = native.free
        native = {
            frame = native.frame,
            frames = { table.unpack(native.frames) },
            index = native.index,
            beforeNative = native.beforeNative,
            selected = native.selected,
            free = { x = free.x, y = free.y, width = free.width, height = free.height },
        }
    end
    return { contentReady = panel._contentReady, native = native }
end

local function suspendPanels()
    -- Premark and snapshot the entire batch: detaching one native member can
    -- otherwise change the next member's tab index and selection.
    for _, entry in ipairs(entries) do
        entry.panel._nisClassic = true
    end
    for _, entry in ipairs(entries) do
        local panel = entry.panel
        if not panel._nisClassicState then panel._nisClassicState = snapshot(panel) end
    end
    local problem
    for _, entry in ipairs(entries) do
        local ok, failure = pcall(entry.panel._SetClassicMode, entry.panel, true)
        if not ok and problem == nil then problem = failure end
    end
    if problem ~= nil then error(problem, 0) end
end

local function restoreModernPanel(panel, saved, attempt)
    if not panel:IsActive() then
        panel._nisInactiveNative = panel._nisInactiveNative or saved.native
        return
    end
    local restored = NisPersistence.setActive(panel, true, NisGroup)
    if not restored and panel._nisInactiveGroup then
        attempt(NisGroup.resume, panel, panel._nisInactiveGroup)
    end
    panel._nisNativePending = saved.native or panel._nisNativePending or panel._nisInactiveNative
    -- Let native mode-change scripts finish before redocking.
    -- Queue only native redocking; normal modern panels resume now.
    if panel._nisNativePending then
        attempt(NisNative.register, panel, false, MODE_LAYOUT_SETTLE_TICKS)
    end
    panel._nisInactiveGroup, panel._nisInactiveNative = nil, nil
end

local function changeMode(enabled)
    local problem
    local function attempt(callback, ...)
        local ok, failure = pcall(callback, ...)
        if not ok and problem == nil then problem = failure end
    end
    if enabled then
        -- The mode var can change before the client finishes resetting the gameview.
        -- Reserve the HUD immediately; only delay crop capture on a live transition.
        cropDelayTicks = gameArea and MODE_LAYOUT_SETTLE_TICKS or 0
        classic = true
        attempt(suspendPanels)
        attempt(destroySurface)
    else
        cropDelayTicks = 0
        -- Shared content and native reservation go away before shell geometry
        -- or consumer content can resume.
        attempt(destroySurface)
        local saved = {}
        for _, entry in ipairs(entries) do
            local panel = entry.panel
            saved[panel] = panel._nisClassicState or snapshot(panel)
            panel._contentReady = false
        end
        classic = false
        for _, entry in ipairs(entries) do
            attempt(entry.panel._SetClassicMode, entry.panel, false)
        end
        for _, entry in ipairs(entries) do
            local panel = entry.panel
            restoreModernPanel(panel, saved[panel], attempt)
        end
        for _, entry in ipairs(entries) do
            local panel = entry.panel
            if not panel._nisNative then
                Components.setHidden(
                    panel.root,
                    panel._nisHidden == true or panel._nisGroup ~= nil and panel._nisGroup.active ~= panel
                )
            end
            panel._contentReady = saved[panel].contentReady
            panel:_LayoutBody()
            panel:_SyncChrome()
            panel:_SyncOverlays(panel.root.hidden == true)
        end
        for _, entry in ipairs(entries) do
            local panel = entry.panel
            attempt(panel._SyncContent, panel, panel.root.hidden ~= true)
        end
    end
    if problem ~= nil then error(problem, 0) end
end

collapseClassic = function(reserve)
    local panel = classicSelectedPanel
    classicSelectedPanel = nil
    if classic then settingsOpen = false end
    if settingsView then
        Settings.destroy(settingsView)
        settingsView = nil
    end
    local ok, problem = true, nil
    if panel then
        ok, problem = pcall(panel._SetClassicHost, panel, nil)
    end
    local reserved = true
    if reserve ~= false and classic and started and #entries > 0 and gameArea and not WorldMap.isSuspended() then
        local rail = classicWidths(false)
        local applied, result = pcall(reserveClassic, rail)
        reserved = applied and result
        if not applied and ok then
            ok, problem = false, result
        end
    end
    layoutRoot()
    syncClassicButtons()
    if not ok then error(problem, 0) end
    return reserved
end

local function mountSurface()
    root = Components.new(ui.Layer, gameArea, { categoryID = "auto" })
    root.clickthrough = false
    local rootContext = Tooltip.registerContext(root, gameArea, function(target)
        local width, height = barSize()
        local x, y = ribbonOrigin(width, height)
        return x + (target.x or 0), y + (target.y or 0)
    end)
    frame = createFrame(root)
    layoutFrame()
    if classic then
        classicBody = Components.newContent(root)
        classicBody:SetPos(0, 0, 0, 0, 0, 0)
        classicBody.clickthrough = false
        frame.contentBackground = sprite(classicBody, Sprites.NIS_PANEL.content)
        frame.contentBackground.isTiling = true
        frame.contentBackground:SetPos(BORDER, BORDER)
        frame.contentBackground:MoveToBack()
        -- Content inherits category zero; categorized artwork can otherwise
        -- paint over it regardless of construction order.
        frame.background:MoveToBack()
        Tooltip.registerContext(
            classicBody,
            gameArea,
            function(target)
                return gameArea.width - root.width + (target.x or 0), (target.y or 0)
            end,
            rootContext
        )
    end
    iconList = Components.new(ui.Layer, root)
    iconList.clickthrough = false
    Wheel.bind(iconList, { _onScrollWheel = scrollIcons })
    Wheel.bind(root, { _onScrollWheel = scrollIcons })
    Tooltip.registerContext(iconList, gameArea, function(target)
        local width, height = barSize()
        local x, y = ribbonOrigin(width, height)
        local horizontal = not classic and Settings.get("ribbonBarPosition") == "top"
        return x + iconList.x + (target.x or 0) - (horizontal and iconScroll or 0),
            y + iconList.y + (target.y or 0) - (horizontal and 0 or iconScroll)
    end, rootContext)
    previousIndicator = sprite(root, id.Sprite.RS3_ICON_ACCORDION_5)
    nextIndicator = sprite(root, id.Sprite.RS3_ICON_ACCORDION_2)
    previousIndicator:SetSize(INDICATOR_SIZE, INDICATOR_SIZE)
    nextIndicator:SetSize(INDICATOR_SIZE, INDICATOR_SIZE)
    for _, indicator in ipairs({ previousIndicator, nextIndicator }) do
        indicator.clickthrough = false
        local delta = indicator == previousIndicator and -1 or 1
        indicator:Subscribe(ui.Hook.ONCLICK, function()
            if not indicator.hidden then scrollIcons(indicator, delta) end
            return false
        end)
        Wheel.bind(indicator, { _onScrollWheel = scrollIcons })
    end
    WorldMap.watch(root, function(suspended)
        if suspended then Tooltip.hideContextTooltips(root) end
        if classicSelectedPanel then
            local panel = classicSelectedPanel
            if not suspended and panel._scroll then
                panel._scroll:Refresh()
                panel:RefreshRowBackgrounds()
            end
            panel:_SyncOverlays(suspended)
        end
    end)
    settingsButton = SpriteButton.new(root, "SETTINGS", toggleSettings, {
        tooltip = "PrettyUI settings",
        _categoryPolicy = "auto",
        size = SETTINGS_BUTTON_SIZE,
    })
    for _, entry in ipairs(entries) do
        createEntryButton(entry)
    end
end

local function updateAutoHide()
    local width, height = barSize()
    hitboxHovered = isHitboxHovered(width, height)
    local target = Settings.get("ribbonBarAutoHide")
            and not hitboxHovered
            and not settingsOpen
            and (Settings.get("ribbonBarPosition") == "top" and height or width)
        or 0
    if slideOffset < target then
        slideOffset = math.min(target, slideOffset + AUTO_HIDE_SLIDE_STEP)
    elseif slideOffset > target then
        slideOffset = math.max(target, slideOffset - AUTO_HIDE_SLIDE_STEP)
    end
end

local function reserveClassicSpace()
    local rail, body = classicWidths(classicSelectedPanel ~= nil or settingsOpen)
    if body == 0 and (classicSelectedPanel ~= nil or settingsOpen) then
        collapseClassic(false)
    end
    local ok, reserved = pcall(reserveClassic, rail + body)
    if not ok or not reserved then
        pcall(destroySurface, true)
        if not ok then error(reserved, 0) end
        return false
    end
    return true
end

ensureMounted = function()
    if not started or #entries == 0 then return end
    for index = #entries, 1, -1 do
        if not panelLoaded(entries[index].panel) then removeEntry(index) end
    end
    if #entries == 0 then
        destroySurface()
        return
    end
    if WorldMap.isSuspended() then return end
    local enabled = NativeInterfaceSettings.isClassicUI()
    if enabled ~= classic then changeMode(enabled) end
    if classic then suspendPanels() end
    local current = ui.Interfaces:GetComponent(
        classic and id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP or id.Component.TOPLEVEL_V2__GAME_AREA
    )
    local currentKey = identity(current)
    local generation = current and ui.Interfaces:GetInterface(current.interfaceID)
    if
        gameArea
        and (ui.Interfaces:GetInterface(interfaceID) == nil or mountKey ~= currentKey or mountGeneration ~= generation)
    then
        destroySurface()
        if not classic then
            clearEntries()
            return
        end
    end
    if current == nil or generation == nil then
        if classic then ClassicLayout.update(0, cropDelayTicks > 0) end
        return
    end
    gameArea, interfaceID = current, current.interfaceID
    mountKey, mountGeneration = currentKey, generation
    if classic and not reserveClassicSpace() then return end
    if root == nil then mountSurface() end
    if not classic then updateAutoHide() end
    layoutRoot()
    root:MoveToFront()
    Tooltip.moveContextTooltipsToFront(root)
end

function RibbonBar.isClassicSelected(panel)
    return panel ~= nil and classicSelectedPanel == panel
end

function RibbonBar.selectClassic(panel, toggle)
    -- Teardown is independent of eligibility: Hide/Destroy can already have
    -- disabled or retired the selected owner's shell.
    if panel ~= nil and panel == classicSelectedPanel and toggle == true then
        return collapseClassic()
    end
    if classicSelecting then return false end
    ensureMounted()
    if
        not classic
        or not root
        or not byPanel[panel]
        or not panelLoaded(panel)
        or not panel:IsActive()
        or WorldMap.isSuspended()
    then
        return false
    end
    local rail, body = classicWidths(true)
    if body == 0 then return false end
    if panel == classicSelectedPanel then return true end
    classicSelecting = true
    local ok, result = pcall(function()
        collapseClassic(false)
        if not byPanel[panel] or not panelLoaded(panel) or not panel:IsActive() then return false end
        if not reserveClassic(rail + body) then return false end
        classicSelectedPanel = panel
        layoutRoot()
        panel:_SetClassicHost(classicBody)
        syncClassicButtons()
        return classicSelectedPanel == panel
    end)
    if not ok or not result then pcall(collapseClassic) end
    classicSelecting = false
    if not ok then error(result, 0) end
    return result
end

function RibbonBar.register(panel)
    ensureMounted()
    if byPanel[panel] then return end
    if not panelLoaded(panel) then return end
    local shell = panel.root
    local entry = { panel = panel, shell = { panel.interfaceID, shell.staticID, shell.categoryID, shell.dynamicID } }
    entries[#entries + 1] = entry
    byPanel[panel] = entry
    ensureMounted()
    if root and byPanel[panel] == entry then
        if entry.button == nil then createEntryButton(entry) end
        layoutRoot()
    end
end

function RibbonBar.unregister(panel)
    local entry = byPanel[panel]
    if not entry then return end
    local ok, problem = true, nil
    for index, candidate in ipairs(entries) do
        if candidate == entry then
            ok, problem = pcall(removeEntry, index)
            break
        end
    end
    if #entries == 0 then
        local removed, failure = pcall(destroySurface)
        if not removed and ok then
            ok, problem = false, failure
        end
    else
        layoutRoot()
    end
    if not ok then error(problem, 0) end
end

function RibbonBar.sync(panel)
    local entry = byPanel[panel]
    if not entry then return end
    if not panelLoaded(panel) then
        RibbonBar.unregister(panel)
        return
    end
    if not entry.button then
        ensureMounted()
        return
    end
    entry.button:SetActive(classic and classicSelectedPanel == panel or not classic and panel:IsActive())
    if entry.icon ~= panel.tabIcon then
        entry.button:SetIcon(panel.tabIcon)
        entry.icon = panel.tabIcon
    end
    if entry.text ~= panel.tabText then
        entry.button:SetTooltip(panel.tabText or "Panel")
        entry.text = panel.tabText
    end
end

-- Use the expanded ribbon edge so auto-hide never puts a panel off-screen.
function RibbonBar.panelPosition(parent, width, height)
    local position = Settings.get("ribbonBarPosition")
    local area = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA) or parent
    local origin, parentOrigin = area.xyGlobal, parent.xyGlobal
    local x = math.floor((area.width - width) / 2)
    local y = math.floor((area.height - height) / 2)
    if position == "top" then
        y = RAIL_WIDTH + PADDING
    elseif position == "right" then
        x = area.width - RAIL_WIDTH - PADDING - width
    else
        x = RAIL_WIDTH + PADDING
    end
    x, y = x + origin.x - parentOrigin.x, y + origin.y - parentOrigin.y
    return math.max(0, math.min(x, parent.width - width)), math.max(0, math.min(y, parent.height - height))
end

function RibbonBar.Start()
    if started then return end
    started = true
    Settings.load()
    Settings.watch(RibbonBar, function(key)
        if key == "ribbonBarPosition" or key == "ribbonBarButtonCap" then layoutRoot() end
    end)
    Event.SettingsLayerReady.Subscribe(EVENT_ID, mountSettingsLayer)
    Event.Logic.Subscribe(EVENT_ID, function()
        if cropDelayTicks > 0 then cropDelayTicks = cropDelayTicks - 1 end
        ensureMounted()
    end)
    Event.VarTransmit.Subscribe(EVENT_ID, function(event)
        if #entries > 0 and event.var.id == id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP then ensureMounted() end
    end)
    ensureMounted()
end

function RibbonBar.Shutdown()
    if started then
        Settings.unwatch(RibbonBar)
        Event.Logic.Unsubscribe(EVENT_ID)
        Event.VarTransmit.Unsubscribe(EVENT_ID)
        Event.SettingsLayerReady.Unsubscribe(EVENT_ID)
    end
    started = false
    cropDelayTicks = 0
    Settings.destroy(settingsLayerView)
    settingsLayerView = nil
    local ok, problem = pcall(destroySurface)
    clearEntries()
    if not ok then error(problem, 0) end
end

return RibbonBar
