local Components = require("src/core/components")
local RibbonButton = require("src/ribbon_button")
local InterfaceMouse = require("src/core/mouse")
local Sprites = require("src/core/sprites")
local Tooltip = require("src/tooltip")
local Window = require("src/window")
local WorldMap = require("src/core/world_map")

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

local entries = {}
local byPanel = {}
local gameArea, root, interfaceID, frame, settingsButton, settingsWindow
local settingsPositionControl, settingsAutoHideControl
local started, settingsOpen, autoHide, hitboxHovered = false, false, false, false
local position, slideOffset = "left", 0

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
    local count = #entries + 1
    local run = PADDING * 2 + count * BUTTON_SIZE + (count - 1) * BUTTON_GAP
    if position == "top" then return run, BUTTON_SIZE + PADDING * 2 end
    return BUTTON_SIZE + PADDING * 2, run
end

local function ribbonOrigin(width, height)
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

local function closeSettings()
    settingsOpen = false
    if settingsButton then settingsButton:SetActive(false) end
end

local function showSettings()
    if settingsWindow then
        settingsOpen = true
        settingsPositionControl:SetSelectedValue(position, false)
        settingsAutoHideControl:SetSelected("autoHide", autoHide, false)
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
    settingsOpen = true
    settingsButton:SetActive(true)
end

local function toggleSettings()
    if settingsOpen and settingsWindow then settingsWindow:Close()
    else showSettings() end
end

local function destroySurface()
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
        if ui.Interfaces:GetInterface(interfaceID) ~= nil then root:Destroy() end
        root = nil
    end
    frame, gameArea, interfaceID = nil, nil, nil
end

local function clearEntries()
    for _, entry in ipairs(entries) do byPanel[entry.panel] = nil end
    entries = {}
end

local function panelLoaded(panel)
    return not panel._destroyed and not panel._destroying and panel.root ~= nil
        and ui.Interfaces:GetInterface(panel.interfaceID) ~= nil
end

local function removeEntry(index)
    local entry = table.remove(entries, index)
    byPanel[entry.panel] = nil
    if entry.button then entry.button:Destroy(); entry.button = nil end
end

local function createEntryButton(entry)
    local panel = entry.panel
    entry.button = RibbonButton.new(root, panel.tabIcon, function()
        if byPanel[panel] ~= entry or not panelLoaded(panel) then return end
        panel:SetActive(not panel:IsActive())
        RibbonBar.sync(panel)
    end, {
        _categoryPolicy = "auto",
        tooltip = panel.tabText or "Panel",
    })
    entry.button:SetActive(panel:IsActive())
    entry.icon, entry.text = panel.tabIcon, panel.tabText
end

local function ensureMounted()
    if not started then return end
    -- Do not retain native handles from a previous game-area generation.
    if gameArea and ui.Interfaces:GetInterface(interfaceID) == nil then
        destroySurface()
        clearEntries()
    end
    local current = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
    if gameArea and not Components.sameComponent(current, gameArea) then
        destroySurface()
        clearEntries()
    end
    if #entries == 0 then
        if root then destroySurface() end
        return
    end
    for index = #entries, 1, -1 do
        if not panelLoaded(entries[index].panel) then removeEntry(index) end
    end
    if #entries == 0 then
        if root then destroySurface() end
        return
    end
    if not current or ui.Interfaces:GetInterface(current.interfaceID) == nil then return end
    if root == nil then
        gameArea = current
        interfaceID = current.interfaceID
        root = Components.new(ui.Layer, gameArea, { categoryID = "auto" })
        root.clickthrough = false
        Tooltip.registerContext(root, gameArea, function(target)
            local width, height = barSize()
            local x, y = ribbonOrigin(width, height)
            return x + (target.x or 0), y + (target.y or 0)
        end)
        WorldMap.watch(root, function(suspended)
            if suspended then Tooltip.hideContextTooltips(root) end
        end)
        frame = createFrame(root)
        settingsButton = RibbonButton.new(root, Sprites.SPRITE_BUTTONS.SETTINGS.neutral,
            toggleSettings, { tooltip = "Ribbon settings", _categoryPolicy = "auto" })
        for _, entry in ipairs(entries) do createEntryButton(entry) end
    end
    local width, height = barSize()
    hitboxHovered = isHitboxHovered(width, height)
    local target = autoHide and not hitboxHovered and not settingsOpen
        and (position == "top" and height or width) or 0
    if slideOffset < target then
        slideOffset = math.min(target, slideOffset + AUTO_HIDE_SLIDE_STEP)
    elseif slideOffset > target then
        slideOffset = math.max(target, slideOffset - AUTO_HIDE_SLIDE_STEP)
    end
    layoutRoot()
    if not WorldMap.isSuspended() then
        root:MoveToFront()
        Tooltip.moveContextTooltipsToFront(root)
    end
end

function RibbonBar.register(panel)
    ensureMounted()
    if byPanel[panel] then return end
    local entry = { panel = panel }
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
    for index, candidate in ipairs(entries) do
        if candidate == entry then removeEntry(index); break end
    end
    if #entries == 0 then destroySurface()
    else layoutRoot() end
end

function RibbonBar.sync(panel)
    local entry = byPanel[panel]
    if not entry then return end
    if not panelLoaded(panel) then RibbonBar.unregister(panel); return end
    if not entry.button then ensureMounted(); return end
    entry.button:SetActive(panel:IsActive())
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
    ensureMounted()
end

function RibbonBar.Shutdown()
    if started then Event.Logic.Unsubscribe(EVENT_ID) end
    started = false
    destroySurface()
    clearEntries()
end

return RibbonBar
