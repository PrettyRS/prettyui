local InterfaceMouse = require("src/core/mouse")
local Sprites = require("src/core/sprites")
local clamp = require("src/core/math").clamp
local Components = require("src/core/components")

local PrettyMiniMenu = {}

local EVENT_ID = "prettyui_minimenu"
local HEADER_HEIGHT = 22
local ITEM_HEIGHT = 15
local BOTTOM_PADDING = 7
local TEXT_INSET = 3
local MENU_WIDTH_PADDING = 8
local BORDER_SIZE = 2
local TITLE_CORNER_WIDTH = 3
local SIDE_WIDTH = 3
local BOTTOM_HEIGHT = 3
local BOTTOM_CORNER_SIZE = 8
local TITLEBAR_HEIGHT = 20
local MINIMUM_WIDTH = 60
local NATIVE_HITBOX_PADDING = 10
local TITLE_COLOUR = 0xDBCBA6FF
local TEXT_COLOUR = 0xDBCBA6FF
local HOVER_TEXT_COLOUR = 0xEEE5C6FF
local BACKGROUND_COLOUR = 0x1D1D1DFF
local HOVER_COLOUR = 0x3D3D3DFF
local MENU_FONT = id.Font.NOTOSANS_BOLD_12
local NOOP = function() end

local started = false
local activeMenu = nil
local overlay = nil
local parentsByEntry = {}
local parentsByText = {}

local function sprite(parent, spriteID)
    local component = Components.new(ui.Sprite, parent)
    component.spriteID = spriteID
    component.clickthrough = true
    return component
end

local function plainTag(tag)
    if tag == "gt" then return ">" end
    if tag == "lt" then return "<" end
    return ""
end

local function plainText(value)
    return tostring(value or ""):gsub("<([^>]*)>", plainTag)
end

local function textKey(value)
    return plainText(value):gsub("%s+", " "):match("^%s*(.-)%s*$")
end

local function measureWithFont(value, font, fallbackCharacterWidth)
    local text = tostring(value or "")
    local succeeded, width = pcall(function() return font:GetStringWidth(text, false) end)
    if succeeded and type(width) == "number" then return width end
    return #plainText(text) * fallbackCharacterWidth
end

local function measureMenuText(value)
    return measureWithFont(value, config.Font.NOTOSANS_BOLD_12, 7)
end

local function measureNativeText(value)
    return measureWithFont(value, config.Font.MUSEO_SANS_15PT_REGULAR, 7)
end

local function entryText(entry)
    if entry.overrideText ~= nil and entry.overrideText ~= "" then return entry.overrideText end
    if entry.fullText ~= nil and entry.fullText ~= "" then return entry.fullText end
    return table.concat({ entry.verbText or "", entry.subjectText or "", entry.extraText or "" }, " ")
end

local function frame(root, width, height)
    local sprites = Sprites.MINIMENU
    local background = Components.new(ui.Rectangle, root)
    background:SetPos(BORDER_SIZE, TITLEBAR_HEIGHT)
    background:SetSize(width - BORDER_SIZE * 2, height - TITLEBAR_HEIGHT - BORDER_SIZE)
    background.fill = true
    background.rgba = BACKGROUND_COLOUR
    background.clickthrough = true

    local title = sprite(root, sprites.title)
    title:SetPos(BORDER_SIZE, 0)
    title:SetSize(width - BORDER_SIZE * 2, TITLEBAR_HEIGHT)
    title.isTiling = true

    local titleLeft = sprite(root, sprites.titleCorner)
    titleLeft:SetSize(TITLE_CORNER_WIDTH, TITLEBAR_HEIGHT)

    local titleRight = sprite(root, sprites.titleCorner)
    titleRight:SetPos(width - TITLE_CORNER_WIDTH, 0)
    titleRight:SetSize(TITLE_CORNER_WIDTH, TITLEBAR_HEIGHT)
    titleRight.isFlippedHorizontally = true

    local sideHeight = height - TITLEBAR_HEIGHT - BOTTOM_CORNER_SIZE
    local left = sprite(root, sprites.side)
    left:SetPos(0, TITLEBAR_HEIGHT)
    left:SetSize(SIDE_WIDTH, sideHeight)
    left.isTiling = true

    local right = sprite(root, sprites.side)
    right:SetPos(width - SIDE_WIDTH, TITLEBAR_HEIGHT)
    right:SetSize(SIDE_WIDTH, sideHeight)
    right.isTiling = true
    right.isFlippedHorizontally = true

    local bottom = sprite(root, sprites.bottom)
    bottom:SetPos(BOTTOM_CORNER_SIZE, height - BOTTOM_HEIGHT)
    bottom:SetSize(width - BOTTOM_CORNER_SIZE * 2, BOTTOM_HEIGHT)
    bottom.isTiling = true

    local bottomLeft = sprite(root, sprites.bottomCorner)
    bottomLeft:SetPos(0, height - BOTTOM_CORNER_SIZE)
    bottomLeft:SetSize(BOTTOM_CORNER_SIZE, BOTTOM_CORNER_SIZE)

    local bottomRight = sprite(root, sprites.bottomCorner)
    bottomRight:SetPos(width - BOTTOM_CORNER_SIZE, height - BOTTOM_CORNER_SIZE)
    bottomRight:SetSize(BOTTOM_CORNER_SIZE, BOTTOM_CORNER_SIZE)
    bottomRight.isFlippedHorizontally = true

    return { left, right, bottom, bottomLeft, bottomRight }
end

local function nativeComponent(componentID)
    if componentID == nil then return nil end
    return ui.Interfaces:GetComponent(componentID)
end

local function nativeMouseLeaveLayer()
    local componentID = id.Component.MINIMENU__PC_MOUSE_LEAVE_LAYER
    local component = nativeComponent(componentID)
    if component ~= nil then return component, componentID end
    componentID = id.Component.MINIMENU__MENU_BLOCKING_LAYER
    return nativeComponent(componentID), componentID
end

local function restoreNativeMouseLeaveLayer(menuOverlay)
    local nativeHitbox = menuOverlay.nativeHitbox
    if nativeHitbox == nil then return end
    menuOverlay.nativeHitbox = nil
    if nativeComponent(nativeHitbox.componentID) ~= nativeHitbox.component then return end
    local position = nativeHitbox.position
    local size = nativeHitbox.size
    nativeHitbox.component:SetPos(
        position.x,
        position.y,
        position.xParentPc,
        position.yParentPc,
        position.xSelfPc,
        position.ySelfPc)
    nativeHitbox.component:SetSize(
        size.width,
        size.height,
        size.widthParentPc,
        size.heightParentPc)
end

local function extendNativeMouseLeaveLayer(menuOverlay, state)
    local component, componentID = nativeMouseLeaveLayer()
    if component == nil or component.width <= 0 or component.height <= 0 then return end

    local position = component.position
    local size = component.size
    local componentOrigin = component.xyGlobal
    local parentOrigin = component.parent and component.parent.xyGlobal or { x = 0, y = 0 }
    local viewportOrigin = state.parent.xyGlobal or { x = 0, y = 0 }
    local submenuX = viewportOrigin.x + menuOverlay.x
    local submenuY = viewportOrigin.y + menuOverlay.y
    -- The native menu otherwise closes when the pointer enters our submenu.
    -- Copy layout offsets and anchors before changing either native dimension.
    menuOverlay.nativeHitbox = {
        component = component,
        componentID = componentID,
        position = {
            x = position.x,
            y = position.y,
            xParentPc = position.xParentPc,
            yParentPc = position.yParentPc,
            xSelfPc = position.xSelfPc,
            ySelfPc = position.ySelfPc,
        },
        size = {
            width = size.width,
            height = size.height,
            widthParentPc = size.widthParentPc,
            heightParentPc = size.heightParentPc,
        },
    }
    local left = math.min(componentOrigin.x, submenuX - NATIVE_HITBOX_PADDING)
    local top = math.min(componentOrigin.y, submenuY - NATIVE_HITBOX_PADDING)
    local right = math.max(
        componentOrigin.x + component.width,
        submenuX + menuOverlay.width + NATIVE_HITBOX_PADDING)
    local bottom = math.max(
        componentOrigin.y + component.height,
        submenuY + menuOverlay.height + NATIVE_HITBOX_PADDING)
    component:SetPos(left - parentOrigin.x, top - parentOrigin.y)
    component:SetSize(right - left, bottom - top)
end

local function releaseOverlay(menuOverlay)
    local root = menuOverlay.root
    menuOverlay.root = nil
    local destroyed, failure = true, nil
    if root ~= nil and ui.Interfaces:GetInterface(menuOverlay.interfaceID) ~= nil then
        destroyed, failure = pcall(root.Destroy, root)
    end
    -- Restore native bounds even if destroying a plugin component fails.
    restoreNativeMouseLeaveLayer(menuOverlay)
    if not destroyed then error(failure, 0) end
end

local function destroyOverlay()
    local previous = overlay
    overlay = nil
    if previous ~= nil then releaseOverlay(previous) end
end

local function reset()
    local state = activeMenu
    if state ~= nil and state.pointerLayer ~= nil
            and nativeComponent(state.pointerLayerID) == state.pointerLayer then
        state.pointerLayer:Unsubscribe(ui.Hook.ONMOUSEOVER, EVENT_ID)
        state.pointerLayer:Unsubscribe(ui.Hook.ONMOUSEREPEAT, EVENT_ID)
    end
    activeMenu = nil
    parentsByEntry = {}
    parentsByText = {}
    destroyOverlay()
end

local function setRowHovered(row, hovered)
    row.background.hidden = not hovered
    row.label.rgba = hovered and HOVER_TEXT_COLOUR or TEXT_COLOUR
end

local function refreshRows(menuOverlay)
    local children = menuOverlay.registration.children
    for rowIndex, row in ipairs(menuOverlay.rows) do
        local childIndex = menuOverlay.scrollOffset + rowIndex
        local child = children[childIndex]
        row.childIndex = childIndex
        row.root.hidden = child == nil
        row.label.content = child and tostring(child.label) or ""
        setRowHovered(row, false)
    end
end

local function scrollRows(menuOverlay, delta)
    if delta == 0 then return false end
    local maximum = math.max(0, #menuOverlay.registration.children - menuOverlay.visibleRows)
    local direction = delta > 0 and 1 or -1
    local nextOffset = clamp(menuOverlay.scrollOffset + direction, 0, maximum)
    if nextOffset ~= menuOverlay.scrollOffset then
        menuOverlay.scrollOffset = nextOffset
        refreshRows(menuOverlay)
    end
    return false
end

local function selectChild(menuOverlay, row)
    local child = menuOverlay.registration.children[row.childIndex]
    if child == nil then return false end
    local action = child.action
    local arguments = child.arguments or child.args
    reset()
    if arguments ~= nil then
        action(table.unpack(arguments))
    else
        action()
    end
    return false
end

local function submenuWidth(registration)
    local width = measureMenuText(registration.title or "Choose Option")
    for _, child in ipairs(registration.children) do
        width = math.max(width, measureMenuText(child.label))
    end
    return math.max(MINIMUM_WIDTH, math.ceil(width) + MENU_WIDTH_PADDING)
end

local function mountOverlay(menuOverlay, state)
    local registration = menuOverlay.registration
    local x, y = menuOverlay.x, menuOverlay.y
    local width, height = menuOverlay.width, menuOverlay.height
    extendNativeMouseLeaveLayer(menuOverlay, state)

    local rootParent = state.parent
    local rootX, rootY = x, y
    if menuOverlay.nativeHitbox ~= nil
            and menuOverlay.nativeHitbox.componentID == id.Component.MINIMENU__MENU_BLOCKING_LAYER then
        -- A top-level sibling would render and receive input below this blocker.
        -- Hosting inside it also requires converting viewport to blocker-local coordinates.
        rootParent = menuOverlay.nativeHitbox.component
        local hostOrigin = rootParent.xyGlobal or { x = 0, y = 0 }
        local viewportOrigin = state.parent.xyGlobal or { x = 0, y = 0 }
        rootX = viewportOrigin.x + x - hostOrigin.x
        rootY = viewportOrigin.y + y - hostOrigin.y
    end

    menuOverlay.interfaceID = rootParent.interfaceID
    local root = Components.new(ui.Layer, rootParent)
    menuOverlay.root = root
    root:SetPos(rootX, rootY)
    root:SetSize(width, height)
    root.clickthrough = true
    local frameEdges = frame(root, width, height)

    local title = Components.new(ui.Text, root)
    title:SetPos(TEXT_INSET, 0)
    title:SetSize(width - TEXT_INSET * 2, TITLEBAR_HEIGHT)
    title.content = tostring(registration.title or "Choose Option")
    title.font = MENU_FONT
    title.rgba = TITLE_COLOUR
    title.alignHorizontal = ui.AlignMode.TOPLEFT
    title.alignVertical = ui.AlignMode.CENTRE
    title.maxLines = 1
    title.isShadowed = false
    title.clickthrough = true

    for rowIndex = 1, menuOverlay.visibleRows do
        local rowRoot = Components.new(ui.Layer, root)
        rowRoot:SetPos(0, HEADER_HEIGHT + (rowIndex - 1) * ITEM_HEIGHT)
        rowRoot:SetSize(width, ITEM_HEIGHT)
        rowRoot.clickthrough = false

        local background = Components.new(ui.Rectangle, rowRoot)
        background:SetSize(0, 0, 1.0, 1.0)
        background.fill = true
        background.rgba = HOVER_COLOUR
        background.hidden = true
        background.clickthrough = true

        local label = Components.new(ui.Text, rowRoot)
        label:SetPos(TEXT_INSET, 0)
        label:SetSize(-TEXT_INSET * 2, ITEM_HEIGHT, 1.0)
        label.font = MENU_FONT
        label.rgba = TEXT_COLOUR
        label.alignHorizontal = ui.AlignMode.TOPLEFT
        label.alignVertical = ui.AlignMode.CENTRE
        label.maxLines = 1
        label.isShadowed = true
        label.clickthrough = true

        local row = { root = rowRoot, background = background, label = label }
        menuOverlay.rows[rowIndex] = row
        rowRoot:Subscribe(ui.Hook.ONMOUSEOVER, function()
            setRowHovered(row, true)
            return false
        end)
        rowRoot:Subscribe(ui.Hook.ONMOUSEREPEAT, function()
            setRowHovered(row, true)
            return false
        end)
        rowRoot:Subscribe(ui.Hook.ONMOUSELEAVE, function()
            setRowHovered(row, false)
            return false
        end)
        rowRoot:Subscribe(ui.Hook.ONCLICK, function()
            return selectChild(menuOverlay, row)
        end)
        rowRoot:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, delta)
            return scrollRows(menuOverlay, delta)
        end)
    end

    for _, edge in ipairs(frameEdges) do edge:MoveToFront() end

    root:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, delta)
        return scrollRows(menuOverlay, delta)
    end)
    refreshRows(menuOverlay)
    root:MoveToFront()
end

local function createOverlay(registration, parentRow)
    destroyOverlay()

    local state = activeMenu
    local width = math.min(submenuWidth(registration), state.viewportWidth)
    local maximumRows = math.max(1,
        math.floor((state.viewportHeight - HEADER_HEIGHT - BOTTOM_PADDING) / ITEM_HEIGHT))
    local visibleRows = math.min(#registration.children, maximumRows)
    local height = math.max(46, HEADER_HEIGHT + visibleRows * ITEM_HEIGHT + BOTTOM_PADDING)

    local rightX = state.rootX + state.rootWidth
    local leftX = state.rootX - width
    local rightSpace = state.viewportWidth - rightX
    local leftSpace = state.rootX
    local x
    if rightSpace >= width then
        x = rightX
    elseif leftSpace >= width then
        x = leftX
    elseif rightSpace >= leftSpace then
        x = clamp(rightX, 0, state.viewportWidth - width)
    else
        x = clamp(leftX, 0, state.viewportWidth - width)
    end

    local parentRowTop = state.rootY + HEADER_HEIGHT + parentRow * ITEM_HEIGHT
    local y = clamp(parentRowTop - HEADER_HEIGHT, 0, state.viewportHeight - height)
    local menuOverlay = {
        registration = registration,
        x = x,
        y = y,
        width = width,
        height = height,
        visibleRows = visibleRows,
        scrollOffset = 0,
        rows = {},
    }
    local mounted, failure = pcall(mountOverlay, menuOverlay, state)
    if not mounted then
        activeMenu = nil
        local released, releaseFailure = pcall(releaseOverlay, menuOverlay)
        if not released then
            error(tostring(failure) .. "; submenu cleanup failed: " .. tostring(releaseFailure), 0)
        end
        error(failure, 0)
    end
    overlay = menuOverlay
end

-- MiniMenuOpened exposes entries, not a stable native menu rectangle. Match the
-- native font, chrome metrics and mouse-centred placement; the custom rows use
-- their own font. Native entry order is reversed when mapping displayed rows.
local function menuDimensions(entries, viewportHeight)
    local width = measureNativeText("Choose Option")
    for _, entry in ipairs(entries) do
        width = math.max(width, measureNativeText(entryText(entry)))
    end
    width = math.max(MINIMUM_WIDTH, math.ceil(width) + MENU_WIDTH_PADDING)
    local maximumRows = math.max(1,
        math.floor((viewportHeight - HEADER_HEIGHT - BOTTOM_PADDING) / ITEM_HEIGHT))
    local visibleRows = math.min(#entries, maximumRows)
    local height = math.max(46, HEADER_HEIGHT + visibleRows * ITEM_HEIGHT + BOTTOM_PADDING)
    return width, height, visibleRows
end

local function placeNativeMenu(state, mouse)
    local origin = state.parent.xyGlobal or { x = 0, y = 0 }
    local mouseX = mouse.x - origin.x
    local mouseY = mouse.y - origin.y
    state.rootX = clamp(math.floor(mouseX - state.rootWidth / 2),
        0, state.viewportWidth - state.rootWidth)
    state.rootY = clamp(math.floor(mouseY), 0, state.viewportHeight - state.rootHeight)
end

-- Keep the raw opening point until the native hook calibrates the shared
-- pointer conversion; the cursor may have moved by the time the hook runs.
local function calibratePointer(state, component, x, y)
    if activeMenu ~= state or state.pointerLayer == nil then return true end
    if not InterfaceMouse.CalibrateFromHook(component, x, y) then return true end
    if overlay ~= nil then destroyOverlay() end
    placeNativeMenu(state, InterfaceMouse.FromRawPosition(state.openPointer))
    state.openPointer = nil
    state.pointerLayer:Unsubscribe(ui.Hook.ONMOUSEOVER, EVENT_ID)
    state.pointerLayer:Unsubscribe(ui.Hook.ONMOUSEREPEAT, EVENT_ID)
    state.pointerLayer = nil
    return true
end

local function onOpened(event)
    local byEntry, byText = parentsByEntry, parentsByText
    reset()
    local entries = event.miniMenu.entries
    local registrations = {}
    local fallbackIndices = {}
    for index, entry in ipairs(entries) do
        registrations[index] = byEntry[entry]
        local key = textKey(entryText(entry))
        if byText[key] ~= nil then
            fallbackIndices[key] = fallbackIndices[key] == nil and index or false
        end
    end
    -- Open-time wrappers may be new. Only use text when exactly one entry matches.
    for key, index in pairs(fallbackIndices) do
        if index then registrations[index] = registrations[index] or byText[key] end
    end
    if next(registrations) == nil then return end

    local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__ROOT)
        or ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
    local raw = Mouse.GetPosition()
    if parent == nil or raw == nil or parent.width <= 0 or parent.height <= 0 then
        return
    end

    local width, height, visibleRows = menuDimensions(entries, parent.height)
    width = math.min(width, parent.width)
    local pointerLayer, pointerLayerID = nativeMouseLeaveLayer()
    local state = {
        parent = parent,
        interfaceID = parent.interfaceID,
        entryCount = #entries,
        registrations = registrations,
        viewportWidth = parent.width,
        viewportHeight = parent.height,
        rootWidth = width,
        rootHeight = height,
        rootVisibleRows = visibleRows,
        pointerLayer = pointerLayer,
        pointerLayerID = pointerLayerID,
        openPointer = pointerLayer and raw or nil,
    }
    activeMenu = state
    if pointerLayer ~= nil then
        local function onPointer(component, x, y)
            return calibratePointer(state, component, x, y)
        end
        pointerLayer:Subscribe(ui.Hook.ONMOUSEOVER, EVENT_ID, onPointer)
        pointerLayer:Subscribe(ui.Hook.ONMOUSEREPEAT, EVENT_ID, onPointer)
    else
        placeNativeMenu(state, InterfaceMouse.FromRawPosition(raw))
    end
end

local function inside(x, y, left, top, width, height)
    return x >= left and x < left + width and y >= top and y < top + height
end

local function onLogic()
    local state = activeMenu
    if state == nil then return end
    if ui.Interfaces:GetInterface(state.interfaceID) == nil or not MiniMenu.IsOpen() then
        reset()
        return
    end

    local mouse = InterfaceMouse.GetPosition()
    if mouse == nil then return end
    if state.rootX == nil then
        -- Some client builds may not dispatch mouse hooks on this native layer.
        -- Keep the previous positioning behavior until calibration arrives.
        placeNativeMenu(state, mouse)
    end
    local origin = state.parent.xyGlobal or { x = 0, y = 0 }
    local x = mouse.x - origin.x
    local y = mouse.y - origin.y
    local insideNative = inside(
        x, y, state.rootX, state.rootY, state.rootWidth, state.rootHeight)
    local insideSubmenu = overlay ~= nil and inside(
        x, y, overlay.x, overlay.y, overlay.width, overlay.height)
    if overlay ~= nil and not insideNative and not insideSubmenu then
        destroyOverlay()
        return
    end

    if insideSubmenu or not insideNative then return end

    local contentY = y - state.rootY - HEADER_HEIGHT
    local row = math.floor(contentY / ITEM_HEIGHT)
    if row < 0 or row >= state.rootVisibleRows then
        destroyOverlay()
        return
    end

    local entryIndex = state.entryCount - row
    local registration = state.registrations[entryIndex]
    if registration == nil then
        destroyOverlay()
    elseif overlay == nil or overlay.registration ~= registration then
        createOverlay(registration, row)
    end
end

local function validatePosition(position)
    if position == nil or position == "top" or position == "bottom" then return end
    assert(type(position) == "number"
            and position >= 2
            and position == math.floor(position),
        "MiniMenu submenu position must be \"top\", \"bottom\", or an integer of 2 or greater")
end

local function targetEntryIndex(position, entryCount)
    local lastSafeRow = math.max(1, entryCount - 1)
    local displayedRow
    if position == nil or position == "bottom" then
        displayedRow = lastSafeRow
    else
        displayedRow = position == "top" and 2 or position
        displayedRow = math.min(displayedRow, lastSafeRow)
    end
    return entryCount - displayedRow + 1
end

local function moveEntry(miniMenu, currentIndex, targetIndex)
    while currentIndex < targetIndex do
        miniMenu:Swap(currentIndex, currentIndex + 1)
        currentIndex = currentIndex + 1
    end
    while currentIndex > targetIndex do
        miniMenu:Swap(currentIndex, currentIndex - 1)
        currentIndex = currentIndex - 1
    end
end

local function findEntry(entries, key)
    local count = #entries
    if textKey(entryText(entries[1])) == key then return entries[1], 1 end
    if textKey(entryText(entries[count])) == key then return entries[count], count end
    for index = 2, count - 1 do
        if textKey(entryText(entries[index])) == key then return entries[index], index end
    end
end

-- Read once before and after Add, and find the parent by text
local function addParentEntry(miniMenu, label, action)
    local key = textKey(label)
    assert(parentsByText[key] == nil,
        "MiniMenu submenu labels must be unique within the current menu")
    local entries = miniMenu.entries
    for _, entry in ipairs(entries) do
        assert(textKey(entryText(entry)) ~= key,
            "MiniMenu submenu label conflicts with an existing menu entry")
    end
    local entryCount = #entries + 1
    miniMenu:Add(label, action)
    entries = miniMenu.entries
    assert(#entries == entryCount, "MiniMenu:Add did not add the submenu parent entry")
    local entry, index = findEntry(entries, key)
    if entry == nil then error("MiniMenu:Add did not expose the submenu parent entry") end
    return entry, index, entryCount
end

function PrettyMiniMenu.AddSubmenu(miniMenu, label, children, options)
    assert(miniMenu ~= nil and type(miniMenu.Add) == "function",
        "MiniMenu.AddSubmenu requires a writable MiniMenu from Event.MiniMenuReady")
    assert(type(label) == "string" and label ~= "", "MiniMenu submenu label must be a non-empty string")
    assert(type(children) == "table" and #children > 0, "MiniMenu submenu requires child entries")
    for index, child in ipairs(children) do
        assert(type(child) == "table", "MiniMenu child " .. index .. " must be a table")
        assert(type(child.label) == "string" and child.label ~= "",
            "MiniMenu child " .. index .. " requires a non-empty label")
        assert(type(child.action) == "function", "MiniMenu child " .. index .. " requires an action")
        local arguments = child.arguments or child.args
        assert(arguments == nil or type(arguments) == "table",
            "MiniMenu child " .. index .. " arguments must be a table")
    end

    options = options or {}
    assert(type(options) == "table", "MiniMenu submenu options must be a table")
    assert(options.parentAction == nil or type(options.parentAction) == "function",
        "MiniMenu submenu parentAction must be a function")
    validatePosition(options.position)
    local parentLabel = label
    if options.arrow ~= false then parentLabel = parentLabel .. " <col=ffffff><gt></col>" end
    local entry, entryIndex, entryCount = addParentEntry(
        miniMenu,
        parentLabel,
        options.parentAction or NOOP)
    moveEntry(
        miniMenu,
        entryIndex,
        targetEntryIndex(options.position, entryCount))
    local registration = {
        children = children,
        title = options.title,
    }
    parentsByEntry[entry] = registration
    parentsByText[textKey(parentLabel)] = registration
    return entry
end

function PrettyMiniMenu.Start()
    if started then return end
    started = true
    -- Dependencies start before consumers subscribe, so each Ready event clears
    -- the previous build before their AddSubmenu calls populate the next one.
    Event.MiniMenuReady.Subscribe(EVENT_ID, reset)
    Event.MiniMenuOpened.Subscribe(EVENT_ID, onOpened)
    Event.MiniMenuClosed.Subscribe(EVENT_ID, reset)
    Event.MiniMenuEntrySelected.Subscribe(EVENT_ID, reset)
    Event.Logic.Subscribe(EVENT_ID, onLogic)
end

function PrettyMiniMenu.Shutdown()
    if started then
        started = false
        Event.MiniMenuReady.Unsubscribe(EVENT_ID)
        Event.MiniMenuOpened.Unsubscribe(EVENT_ID)
        Event.MiniMenuClosed.Unsubscribe(EVENT_ID)
        Event.MiniMenuEntrySelected.Unsubscribe(EVENT_ID)
        Event.Logic.Unsubscribe(EVENT_ID)
    end
    reset()
end

return PrettyMiniMenu
