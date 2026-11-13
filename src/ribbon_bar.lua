local Components = require("src/core/components")
local RibbonButton = require("src/ribbon_button")
local InterfaceMouse = require("src/core/mouse")
local Sprites = require("src/core/sprites")
local Tooltip = require("src/tooltip")
local Window = require("src/window")
local WorldMap = require("src/core/world_map")
local NativeInterfaceSettings = require("src/core/native_interface_settings")
local ClassicLayout = require("src/core/classic_layout")
local NisGroup = require("src/core/nis_group")
local NisPersistence = require("src/core/nis_persistence")
local NisNative = require("src/core/nis_native")
local Wheel = require("src/core/wheel")

local RibbonBar = {}

local EVENT_ID = "prettyui_ribbon_bar"
local POSITION_STORAGE_KEY = "ribbonBarPosition"
local AUTO_HIDE_STORAGE_KEY = "ribbonBarAutoHide"
local BORDER = 4
local PADDING = 6
local BUTTON_SIZE = 32
local BUTTON_GAP = 2
local AUTO_HIDE_SLIDE_STEP = 8
local SETTINGS_WIDTH = 340
local SETTINGS_HEIGHT = 250
local CLASSIC_CONTENT_WIDTH = 360
local MODERN_NATIVE_RESTORE_TICKS = 10 -- 200 ms at the client's fixed 50 Hz.
local RAIL_WIDTH = BUTTON_SIZE + PADDING * 2
local PITCH = BUTTON_SIZE + BUTTON_GAP

local entries = {}
local byPanel = {}
local gameArea, root, interfaceID, frame, settingsButton, settingsWindow
local settingsPositionControl, settingsAutoHideControl
local started, settingsOpen, autoHide, hitboxHovered = false, false, false, false
local position, slideOffset = "left", 0
local classic = false
local classicSelectedPanel, classicBody, classicIconList
local classicIconScrollY = 0
local classicSelecting = false
local mountKey, mountGeneration
local ensureMounted, destroySurface, collapseClassic

local function identity(component)
    if component == nil then return nil end
    return table.concat({ component.interfaceID, component.staticID,
        component.categoryID, component.dynamicID }, ":")
end

local function classicWidths(expanded)
    local width = gameArea and gameArea.width or 0
    local rail = math.min(RAIL_WIDTH, math.max(0, width - 1))
    local body = expanded and math.min(CLASSIC_CONTENT_WIDTH, math.max(0, width - 1 - rail)) or 0
    return rail, body
end

local function syncClassicButtons()
    for _, entry in ipairs(entries) do
        if entry.button then entry.button:SetActive(entry.panel == classicSelectedPanel) end
    end
end

local function reserveClassic(width)
    local ok, result = pcall(ClassicLayout.update, width)
    if (not ok or not result) and root and ui.Interfaces:GetInterface(interfaceID) ~= nil then
        Components.setHidden(root, true)
    end
    if not ok then error(result, 0) end
    return result
end

local function normalizePosition(value)
    value = string.lower(tostring(value or ""))
    if value == "right" or value == "top" then return value end
    return "left"
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
        local rail, body = classicWidths(classicSelectedPanel ~= nil)
        return rail + body, gameArea.height
    end
    local count = #entries + 1
    local run = PADDING * 2 + count * BUTTON_SIZE + (count - 1) * BUTTON_GAP
    if position == "top" then return run, BUTTON_SIZE + PADDING * 2 end
    return BUTTON_SIZE + PADDING * 2, run
end

local function ribbonOrigin(width, height)
    if classic then return gameArea.width - width, 0 end
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
    -- The unslid edge stays reachable while the bar is auto-hidden.
    if position == "top" then y = 0
    elseif position == "right" then x = (gameArea.width or 0) - width
    else x = 0 end
    x, y = x + (gameArea.x or 0), y + (gameArea.y or 0)
    return mouse.x >= x and mouse.x < x + width and mouse.y >= y and mouse.y < y + height
end

local function layoutRoot()
    if root == nil or ui.Interfaces:GetInterface(interfaceID) == nil then return end
    if classic then
        local rail, body = classicWidths(classicSelectedPanel ~= nil)
        local width, height = rail + body, gameArea.height
        root:SetPos(-width, 0, 1, 0)
        if root.width ~= width or root.height ~= height then root:SetSize(width, height) end
        layoutFrame()
        settingsButton.root:SetPos(body + PADDING, PADDING)
        local resized = classicBody.width ~= body or classicBody.height ~= height
        if resized then
            classicBody:SetSize(body, height)
            frame.contentBackground:SetSize(math.max(0, body - BORDER * 2), math.max(0, height - BORDER * 2))
        end
        Components.setHidden(classicBody, classicSelectedPanel == nil)
        local listHeight = math.max(0, height - PADDING * 2 - PITCH)
        local scrollHeight = math.max(0, #entries * PITCH - BUTTON_GAP)
        classicIconList:SetPos(body, PADDING + PITCH)
        classicIconList:SetSize(rail, listHeight)
        classicIconList:SetScrollSize(rail, math.max(listHeight, scrollHeight))
        classicIconScrollY = math.max(0, math.min(classicIconScrollY, scrollHeight - listHeight))
        classicIconList:SetScrollPos(0, classicIconScrollY)
        for index, entry in ipairs(entries) do
            if entry.button then
                local y = (index - 1) * PITCH
                entry.button.root:SetPos(PADDING, y)
                entry.classicVisible = y + BUTTON_SIZE > classicIconScrollY
                    and y < classicIconScrollY + listHeight
                entry.button.root.enabled = entry.classicVisible
                Components.setHidden(entry.button.root, not entry.classicVisible)
            end
        end
        if resized and classicSelectedPanel and classicSelectedPanel._scroll then
            classicSelectedPanel._scroll:Refresh()
            classicSelectedPanel:RefreshRowBackgrounds()
        end
        return
    end
    local width, height = barSize()
    if position == "top" then
        root:SetPos(-math.floor(width / 2), -slideOffset, 0.5, 0)
    elseif position == "right" then
        root:SetPos(-width + slideOffset, -math.floor(height / 2), 1, 0.5)
    else
        root:SetPos(-slideOffset, -math.floor(height / 2), 0, 0.5)
    end
    root:SetSize(width, height)
    layoutFrame()
    if settingsButton then settingsButton.root:SetPos(PADDING, PADDING) end
    for index, entry in ipairs(entries) do
        if entry.button then
            local offset = PADDING + index * (BUTTON_SIZE + BUTTON_GAP)
            if position == "top" then entry.button.root:SetPos(offset, PADDING)
            else entry.button.root:SetPos(PADDING, offset) end
        end
    end
end

local function scrollClassicIcons(_, delta)
    if not classic or WorldMap.isSuspended() then return true end
    local previous = classicIconScrollY
    classicIconScrollY = classicIconScrollY + delta * PITCH
    layoutRoot()
    return previous == classicIconScrollY
end

local function closeSettings()
    settingsOpen = false
    if settingsButton then settingsButton:SetActive(false) end
end

local function showSettings()
    if settingsWindow then
        settingsOpen = true
        if settingsPositionControl then settingsPositionControl:SetSelectedValue(position, false) end
        if settingsAutoHideControl then settingsAutoHideControl:SetSelected("autoHide", autoHide, false) end
        settingsWindow:Show()
        settingsButton:SetActive(true)
        return
    end
    settingsWindow = Window.new(gameArea, {
        categoryID = "auto",
        title = "Ribbon settings",
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
    settingsWindow:AddTitle("PLUGIN RIBBON")
    if classic then
        settingsWindow:AddText("Classic Interface uses a fixed right sidebar; position and auto-hide apply in Modern Interface.")
    else
        settingsWindow:AddText("Choose which game-window edge holds the panel ribbon.")
        settingsPositionControl = settingsWindow:AddRadioButton({
            { text = "Left", value = "left" },
            { text = "Right", value = "right" },
            { text = "Top", value = "top" },
        }, {
            selectedValue = position,
            onChange = function(_, value) RibbonBar.SetPosition(value) end,
        })
        settingsAutoHideControl = settingsWindow:AddCheckboxButton({
            { text = "Auto-hide ribbon", value = "autoHide", selected = autoHide },
        }, {
            onChange = function(_, _, _, selected) RibbonBar.SetAutoHide(selected) end,
        })
    end
    settingsOpen = true
    settingsButton:SetActive(true)
end

local function toggleSettings()
    if settingsOpen and settingsWindow then settingsWindow:Close()
    else showSettings() end
end

destroySurface = function(keepLayout)
    local selected = classicSelectedPanel
    classicSelectedPanel = nil
    local ok, problem = true, nil
    if selected then ok, problem = pcall(selected._SetClassicHost, selected, nil) end
    if not keepLayout then ClassicLayout.restore() end
    if settingsWindow then settingsWindow:Destroy(); settingsWindow = nil end
    settingsPositionControl, settingsAutoHideControl = nil, nil
    settingsOpen, hitboxHovered, slideOffset = false, false, 0
    if settingsButton then settingsButton:Destroy(); settingsButton = nil end
    for _, entry in ipairs(entries) do
        if entry.button then entry.button:Destroy(); entry.button = nil end
    end
    if root then
        WorldMap.unwatch(root)
        Tooltip.unregisterContext(root)
        if classicBody then Tooltip.unregisterContext(classicBody) end
        if classicIconList then Tooltip.unregisterContext(classicIconList) end
        if ui.Interfaces:GetInterface(interfaceID) ~= nil then root:Destroy() end
        root = nil
    end
    frame, gameArea, interfaceID = nil, nil, nil
    classicBody, classicIconList, classicIconScrollY = nil, nil, 0
    mountKey, mountGeneration = nil, nil
    if not ok then error(problem, 0) end
end

local function clearEntries()
    for _, entry in ipairs(entries) do byPanel[entry.panel] = nil end
    entries = {}
end

local function panelLoaded(panel)
    if panel._destroyed or panel._destroying or panel.root == nil
        or ui.Interfaces:GetInterface(panel.interfaceID) == nil then return false end
    local entry = byPanel[panel]
    if entry then
        local shell = entry.shell
        return identity(ui.Interfaces:GetComponent(table.unpack(shell))) == entry.shellKey
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
    if entry.button then entry.button:Destroy(); entry.button = nil end
    if not ok then error(problem, 0) end
end

local function createEntryButton(entry)
    local panel = entry.panel
    entry.button = RibbonButton.new(classic and classicIconList or root, panel.tabIcon, function()
        if byPanel[panel] ~= entry or not panelLoaded(panel) then return end
        if classic then
            if not entry.classicVisible then return end
            if not panel:IsActive() then panel:SetActive(true)
            else RibbonBar.selectClassic(panel, true) end
        else
            panel:SetActive(not panel:IsActive())
        end
        RibbonBar.sync(panel)
    end, {
        _categoryPolicy = "auto",
        tooltip = panel.tabText or "Panel",
        _onScrollWheel = classic and scrollClassicIcons or nil,
    })
    entry.button:SetActive(classic and classicSelectedPanel == panel or not classic and panel:IsActive())
    entry.icon, entry.text = panel.tabIcon, panel.tabText
end

local function snapshot(panel)
    local native = NisNative.remember(panel) or panel._nisNativePending
    if native then
        local free = native.free
        native = {
            frame = native.frame, frames = { table.unpack(native.frames) },
            index = native.index, beforeNative = native.beforeNative, selected = native.selected,
            free = { x = free.x, y = free.y, width = free.width, height = free.height },
        }
    end
    return { contentReady = panel._contentReady, native = native }
end

local function suspendPanels()
    -- Premark and snapshot the entire batch: detaching one native member can
    -- otherwise change the next member's tab index and selection.
    for _, entry in ipairs(entries) do entry.panel._nisClassic = true end
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

local function changeMode(enabled)
    local problem
    local function attempt(callback, ...)
        local ok, failure = pcall(callback, ...)
        if not ok and problem == nil then problem = failure end
    end
    if enabled then
        classic = true
        attempt(suspendPanels)
        attempt(destroySurface)
    else
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
            if panel:IsActive() then
                local restored = NisPersistence.setActive(panel, true, NisGroup)
                if not restored and panel._nisInactiveGroup then
                    attempt(NisGroup.resume, panel, panel._nisInactiveGroup)
                end
                panel._nisNativePending = saved[panel].native or panel._nisNativePending
                    or panel._nisInactiveNative
                -- Let native mode-change scripts finish before redocking.
                -- Queue only native redocking; normal modern panels resume now.
                if panel._nisNativePending then
                    attempt(NisNative.register, panel, false, MODERN_NATIVE_RESTORE_TICKS)
                end
                panel._nisInactiveGroup, panel._nisInactiveNative = nil, nil
            else
                panel._nisInactiveNative = panel._nisInactiveNative or saved[panel].native
            end
        end
        for _, entry in ipairs(entries) do
            local panel = entry.panel
            if not panel._nisNative then
                Components.setHidden(panel.root, panel._nisHidden == true
                    or panel._nisGroup ~= nil and panel._nisGroup.active ~= panel)
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
    local ok, problem = true, nil
    if panel then ok, problem = pcall(panel._SetClassicHost, panel, nil) end
    local reserved = true
    if reserve ~= false and classic and started and #entries > 0 and gameArea
        and not WorldMap.isSuspended() then
        local rail = classicWidths(false)
        local applied, result = pcall(reserveClassic, rail)
        reserved = applied and result
        if not applied and ok then ok, problem = false, result end
    end
    layoutRoot()
    syncClassicButtons()
    if not ok then error(problem, 0) end
    return reserved
end

ensureMounted = function()
    if not started or #entries == 0 then return end
    for index = #entries, 1, -1 do
        if not panelLoaded(entries[index].panel) then removeEntry(index) end
    end
    if #entries == 0 then destroySurface(); return end
    if WorldMap.isSuspended() then return end
    local enabled = NativeInterfaceSettings.isClassicUI()
    if enabled ~= classic then changeMode(enabled) end
    if classic then suspendPanels() end
    local current = ui.Interfaces:GetComponent(classic
        and id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP or id.Component.TOPLEVEL_V2__GAME_AREA)
    local currentKey = identity(current)
    local generation = current and ui.Interfaces:GetInterface(current.interfaceID)
    if gameArea and (ui.Interfaces:GetInterface(interfaceID) == nil
        or mountKey ~= currentKey or mountGeneration ~= generation) then
        destroySurface()
        if not classic then clearEntries(); return end
    end
    if current == nil or generation == nil then
        if classic then ClassicLayout.update(0) end
        return
    end
    gameArea, interfaceID = current, current.interfaceID
    mountKey, mountGeneration = currentKey, generation
    if classic then
        local rail, body = classicWidths(classicSelectedPanel ~= nil)
        local ok, reserved = pcall(reserveClassic, rail + body)
        if not ok or not reserved then
            pcall(destroySurface, true)
            if not ok then error(reserved, 0) end
            return
        end
    end
    if root == nil then
        root = Components.new(ui.Layer, gameArea, { categoryID = "auto" })
        root.clickthrough = false
        local rootContext = Tooltip.registerContext(root, gameArea, function(target)
            local width, height = barSize()
            local x, y = ribbonOrigin(width, height)
            return x + (target.x or 0), y + (target.y or 0)
        end)
        frame = createFrame(root)
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
            Tooltip.registerContext(classicBody, gameArea, function(target)
                return gameArea.width - root.width + (target.x or 0), (target.y or 0)
            end, rootContext)
            classicIconList = Components.new(ui.Layer, root)
            classicIconList.clickthrough = false
            Wheel.bind(classicIconList, { _onScrollWheel = scrollClassicIcons })
            Tooltip.registerContext(classicIconList, gameArea, function(target)
                return gameArea.width - root.width + classicIconList.x + (target.x or 0),
                    classicIconList.y + (target.y or 0) - classicIconScrollY
            end, rootContext)
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
        settingsButton = RibbonButton.new(root, Sprites.SPRITE_BUTTONS.SETTINGS.neutral,
            toggleSettings, { tooltip = "Ribbon settings", _categoryPolicy = "auto" })
        for _, entry in ipairs(entries) do createEntryButton(entry) end
    end
    if not classic then
        local width, height = barSize()
        hitboxHovered = isHitboxHovered(width, height)
        local target = autoHide and not hitboxHovered and not settingsOpen
            and (position == "top" and height or width) or 0
        if slideOffset < target then
            slideOffset = math.min(target, slideOffset + AUTO_HIDE_SLIDE_STEP)
        elseif slideOffset > target then
            slideOffset = math.max(target, slideOffset - AUTO_HIDE_SLIDE_STEP)
        end
    end
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
    if not classic or not root or not byPanel[panel] or not panelLoaded(panel)
        or not panel:IsActive() or WorldMap.isSuspended() then return false end
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
    local entry = { panel = panel,
        shell = { panel.interfaceID, shell.staticID, shell.categoryID, shell.dynamicID },
        shellKey = identity(shell) }
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
        if candidate == entry then ok, problem = pcall(removeEntry, index); break end
    end
    if #entries == 0 then
        local removed, failure = pcall(destroySurface)
        if not removed and ok then ok, problem = false, failure end
    else
        layoutRoot()
    end
    if not ok then error(problem, 0) end
end

function RibbonBar.sync(panel)
    local entry = byPanel[panel]
    if not entry then return end
    if not panelLoaded(panel) then RibbonBar.unregister(panel); return end
    if not entry.button then ensureMounted(); return end
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

function RibbonBar.SetPosition(value)
    position = normalizePosition(value)
    PersistentDB:SetString(POSITION_STORAGE_KEY, position)
    if settingsPositionControl and ui.Interfaces:GetInterface(interfaceID) ~= nil then
        settingsPositionControl:SetSelectedValue(position, false)
    end
    layoutRoot()
end

function RibbonBar.GetPosition()
    return position
end

function RibbonBar.SetAutoHide(value)
    autoHide = value == true
    PersistentDB:SetBool(AUTO_HIDE_STORAGE_KEY, autoHide)
    if settingsAutoHideControl and ui.Interfaces:GetInterface(interfaceID) ~= nil then
        settingsAutoHideControl:SetSelected("autoHide", autoHide, false)
    end
end

function RibbonBar.GetAutoHide()
    return autoHide
end

function RibbonBar.Start()
    if started then return end
    started = true
    position = normalizePosition(PersistentDB:GetString(POSITION_STORAGE_KEY))
    autoHide = PersistentDB:GetBool(AUTO_HIDE_STORAGE_KEY) == true
    Event.Logic.Subscribe(EVENT_ID, ensureMounted)
    Event.VarTransmit.Subscribe(EVENT_ID, function(event)
        if #entries > 0 and event.var.id == id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP then ensureMounted() end
    end)
    ensureMounted()
end

function RibbonBar.Shutdown()
    if started then
        Event.Logic.Unsubscribe(EVENT_ID)
        Event.VarTransmit.Unsubscribe(EVENT_ID)
    end
    started = false
    local ok, problem = pcall(destroySurface)
    clearEntries()
    if not ok then error(problem, 0) end
end

return RibbonBar
