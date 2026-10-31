local Components = require("src/core/components")
local RibbonButton = require("src/ribbon_button")
local InterfaceMouse = require("src/core/mouse")
local Sprites = require("src/core/sprites")
local Tooltip = require("src/tooltip")
local Window = require("src/window")

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
local entriesByID = {}
local gameArea = nil
local root = nil
local interfaceID = nil
local frame = nil
local settingsButton = nil
local settingsWindow = nil
local settingsPositionControl = nil
local settingsAutoHideControl = nil
local settingsOpen = false
local started = false
local position = "left"
local autoHide = false
local hitboxHovered = false
local slideOffset = 0

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

local function layoutFrame(width, height)
    frame.background:SetPos(BORDER, BORDER)
    frame.background:SetSize(-BORDER * 2, -BORDER * 2, 1.0, 1.0)
    frame.top:SetPos(BORDER, 0)
    frame.top:SetSize(-BORDER * 2, BORDER, 1.0)
    frame.bottom:SetPos(BORDER, -BORDER, 0, 1.0)
    frame.bottom:SetSize(-BORDER * 2, BORDER, 1.0)
    frame.left:SetPos(0, BORDER)
    frame.left:SetSize(BORDER, -BORDER * 2, 0, 1.0)
    frame.right:SetPos(-BORDER, BORDER, 1.0)
    frame.right:SetSize(BORDER, -BORDER * 2, 0, 1.0)
    frame.topLeft:SetSize(BORDER, BORDER)
    frame.topRight:SetPos(-BORDER, 0, 1.0)
    frame.topRight:SetSize(BORDER, BORDER)
    frame.bottomLeft:SetPos(0, -BORDER, 0, 1.0)
    frame.bottomLeft:SetSize(BORDER, BORDER)
    frame.bottomRight:SetPos(-BORDER, -BORDER, 1.0, 1.0)
    frame.bottomRight:SetSize(BORDER, BORDER)
end

local function buttonCount()
    return #entries + 1
end

local function barSize()
    local count = buttonCount()
    local run = PADDING * 2 + count * BUTTON_SIZE + math.max(0, count - 1) * BUTTON_GAP
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

local function hiddenOffset(width, height)
    return position == "top" and height or width
end

local function isHitboxHovered(width, height)
    local mouse = InterfaceMouse.GetPosition()
    if mouse == nil or gameArea == nil then return false end

    local gameX = gameArea.x or 0
    local gameY = gameArea.y or 0
    local x = gameX
    local y = gameY + math.floor(((gameArea.height or 0) - height) / 2)
    if position == "top" then
        x = gameX + math.floor(((gameArea.width or 0) - width) / 2)
        y = gameY
    elseif position == "right" then
        x = gameX + (gameArea.width or 0) - width
    end

    return mouse.x >= x and mouse.x < x + width and mouse.y >= y and mouse.y < y + height
end

local function updateSlide(width, height)
    local target = 0
    if autoHide and not hitboxHovered and not settingsOpen then
        target = hiddenOffset(width, height)
    end
    if slideOffset < target then
        slideOffset = math.min(target, slideOffset + AUTO_HIDE_SLIDE_STEP)
    elseif slideOffset > target then
        slideOffset = math.max(target, slideOffset - AUTO_HIDE_SLIDE_STEP)
    end
end

local function layoutRoot()
    if root == nil or ui.Interfaces:GetInterface(interfaceID) == nil then return end
    local width, height = barSize()
    if position == "top" then
        root:SetPos(-math.floor(width / 2), -slideOffset, 0.5, 0)
    elseif position == "right" then
        root:SetPos(-width + slideOffset, -math.floor(height / 2), 1.0, 0.5)
    else
        root:SetPos(-slideOffset, -math.floor(height / 2), 0, 0.5)
    end
    root:SetSize(width, height)
    layoutFrame(width, height)

    local buttons = { settingsButton }
    for _, entry in ipairs(entries) do table.insert(buttons, entry.button) end
    for index, button in ipairs(buttons) do
        if button ~= nil and button.root ~= nil then
            local offset = PADDING + (index - 1) * (BUTTON_SIZE + BUTTON_GAP)
            if position == "top" then
                button.root:SetPos(offset, PADDING)
            else
                button.root:SetPos(PADDING, offset)
            end
        end
    end
end

local function closeSettings()
    settingsOpen = false
    if settingsButton ~= nil then settingsButton:SetActive(false) end
end

local function showSettings()
    if settingsWindow ~= nil then
        settingsOpen = true
        settingsPositionControl:SetSelectedValue(position, false)
        settingsAutoHideControl:SetSelected("autoHide", autoHide, false)
        settingsWindow:Show()
        if settingsButton ~= nil then settingsButton:SetActive(true) end
        return
    end

    settingsWindow = Window.new(gameArea, {
        title = "PrettyUI Settings",
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
    settingsWindow:AddText("Choose which game-window edge holds the shared plugin ribbon.")
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
    if settingsButton ~= nil then settingsButton:SetActive(true) end
end

local function toggleSettings()
    if settingsOpen and settingsWindow ~= nil then
        settingsWindow:Close()
    else
        showSettings()
    end
end

local function destroyButtons()
    if settingsButton ~= nil then settingsButton:Destroy() settingsButton = nil end
    for _, entry in ipairs(entries) do
        if entry.button ~= nil then entry.button:Destroy() entry.button = nil end
    end
end

local function createEntryButton(entry)
    local options = entry.options
    local icon = options.icon or Sprites.ITEM_SLOT_BACKGROUND
    entry.button = RibbonButton.new(root, icon, function(button)
        entry.active = button.active
        if options.onClick then options.onClick(entry.handle, button.active) end
    end, {
        tooltip = entry.tooltipValue,
        disabled = options.disabled == true,
    })
    if options.object ~= nil then
        entry.button.icon:SetAssociatedObject(options.object.id)
        entry.button.icon.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
    end
    entry.button:SetActive(entry.active)
end

local function rebuildButtons()
    if root == nil or ui.Interfaces:GetInterface(interfaceID) == nil then return end
    destroyButtons()
    settingsButton = RibbonButton.new(
        root,
        Sprites.SPRITE_BUTTONS.SETTINGS.neutral,
        toggleSettings,
        { tooltip = "PrettyUI plugin ribbon settings" })
    settingsButton:SetActive(settingsOpen)
    for _, entry in ipairs(entries) do createEntryButton(entry) end
    layoutRoot()
end

local function destroySurface()
    if settingsWindow ~= nil then settingsWindow:Destroy() settingsWindow = nil end
    settingsPositionControl = nil
    settingsAutoHideControl = nil
    settingsOpen = false
    hitboxHovered = false
    slideOffset = 0
    destroyButtons()
    if root ~= nil then
        Tooltip.unregisterContext(root)
        if ui.Interfaces:GetInterface(interfaceID) ~= nil then root:Destroy() end
        root = nil
    end
    frame = nil
    gameArea = nil
    interfaceID = nil
end

local function ensureMounted()
    if #entries == 0 then
        if root ~= nil then destroySurface() end
        return false
    end
    local currentGameArea = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
    if currentGameArea == nil then
        if gameArea ~= nil then destroySurface() end
        return false
    end
    if currentGameArea ~= gameArea then
        destroySurface()
        gameArea = currentGameArea
    end
    if root == nil then
        interfaceID = gameArea.interfaceID
        root = Components.new(ui.Layer, gameArea)
        root.clickthrough = false
        Tooltip.registerContext(root, gameArea, function(target)
            local width, height = barSize()
            local x, y = ribbonOrigin(width, height)
            return x + (target.x or 0), y + (target.y or 0)
        end)
        frame = createFrame(root)
        rebuildButtons()
    end
    local width, height = barSize()
    hitboxHovered = isHitboxHovered(width, height)
    updateSlide(width, height)
    layoutRoot()
    root:MoveToFront()
    Tooltip.moveContextTooltipsToFront(root)
    return true
end

local Handle = {}
Handle.__index = Handle

function Handle:SetActive(active)
    local entry = entriesByID[self.id]
    if entry == nil then return false end
    entry.active = active == true
    if entry.button ~= nil then entry.button:SetActive(entry.active) end
    return true
end

function Handle:SetIcon(icon)
    local entry = entriesByID[self.id]
    if entry == nil then return false end
    entry.options.icon = icon
    entry.options.object = nil
    if entry.button ~= nil then entry.button:SetIcon(icon) end
    return true
end

function Handle:SetTooltip(value)
    local entry = entriesByID[self.id]
    if entry == nil then return false end
    entry.tooltipValue = value
    if entry.button ~= nil then return entry.button:SetTooltip(value) end
    return true
end

function Handle:Destroy()
    return RibbonBar.Unregister(self.id)
end

function RibbonBar.Register(options)
    options = options or {}
    local identifier = tostring(options.id or options.identifier or "")
    if identifier == "" then error("RibbonBar.Register requires a stable id") end

    local existing = entriesByID[identifier]
    if existing ~= nil then
        existing.options = options
        existing.tooltipValue = options.tooltip ~= nil and options.tooltip or options.label
        if root ~= nil then rebuildButtons() end
        return existing.handle
    end

    print("[PrettyUI] RibbonBar is deprecated; ribbon registration '" .. identifier ..
        "' should be migrated to using the new native hasRibbonIcon and ContentLayer system.")

    local entry = {
        id = identifier,
        options = options,
        active = options.active == true,
        tooltipValue = options.tooltip ~= nil and options.tooltip or options.label,
    }
    entry.handle = setmetatable({ id = identifier }, Handle)
    entriesByID[identifier] = entry
    table.insert(entries, entry)
    ensureMounted()
    if root ~= nil then rebuildButtons() end
    return entry.handle
end

function RibbonBar.Unregister(identifier)
    identifier = tostring(identifier or "")
    local entry = entriesByID[identifier]
    if entry == nil then return false end
    if entry.button ~= nil then entry.button:Destroy() entry.button = nil end
    entriesByID[identifier] = nil
    for index, candidate in ipairs(entries) do
        if candidate == entry then table.remove(entries, index) break end
    end
    if #entries == 0 then
        destroySurface()
    elseif root ~= nil then
        rebuildButtons()
    end
    return true
end

function RibbonBar.SetPosition(value)
    position = normalizePosition(value)
    PersistentDB:SetString(POSITION_STORAGE_KEY, position)
    if settingsPositionControl ~= nil and ui.Interfaces:GetInterface(interfaceID) ~= nil then
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
    if settingsAutoHideControl ~= nil and ui.Interfaces:GetInterface(interfaceID) ~= nil then
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
    entries = {}
    entriesByID = {}
end

return RibbonBar
