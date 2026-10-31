local Tooltip = require("src/tooltip")

local BuffBar = {}

local DEFAULT_ICON_SIZE = 28
local LABEL_HEIGHT = 12
local LABEL_Y_OFFSET = 12
local BACKGROUND_RGBA = 0x00000000
local BUFF_BORDER_RGBA = 0x5A9619FF
local DEBUFF_BORDER_RGBA = 0xCC0000FF
local DEFAULT_LABEL_RGBA = 0xFFFFFFFF
local ICON_GAP = 3
local BORDER_THICKNESS = 1
local EMPTY_ROW_X = BORDER_THICKNESS
-- Native occupancy is measured from the 29px slot edge, while its visible
-- icon is 28px wide. Discount that trailing pixel to preserve a 3px visual gap.
local NATIVE_SPACING = ICON_GAP - 1
local ENTRY_SPACING = ICON_GAP
local ROW_SPACING = 2
local RIGHT_MARGIN = 16
local TICKS_PER_SECOND = 50
local TOOLTIP_DELAY_TICKS = math.ceil(0.6 * TICKS_PER_SECOND)
local TICKS_PER_MINUTE = 60 * TICKS_PER_SECOND
local MAX_NATIVE_GRAPHIC_DEPTH = 8
local EVENT_ID = "prettyui_buff_bar"
local ENTRY_VISUAL_KEYS = { "background", "sprite", "border", "label" }

local function newBar(name, componentID, borderRGBA, allowBorderOverride)
    return {
        name = name,
        componentID = componentID,
        borderRGBA = borderRGBA,
        allowBorderOverride = allowBorderOverride,
        layer = nil,
        entries = {},
        entriesByID = {},
        -- The render layer is shared with the game and other plugins. Dynamic
        -- IDs let occupancy scans exclude only components created by this bar.
        ownDynamicIDs = {},
        lastIconSize = nil,
        lastRowsSignature = nil,
        lastUsableWidth = nil,
    }
end

local bars = {
    buff = newBar("buff", id.Component.BUFF_BAR__BUFF_RENDER_LAYER, BUFF_BORDER_RGBA, true),
    debuff = newBar("debuff", id.Component.DEBUFF_BAR__BUFF_RENDER_LAYER, DEBUFF_BORDER_RGBA, false),
}

local nextEntryID = 0
local started = false
local lastLogicTick = nil

local function resolveObjId(value)
    if value == nil then return nil end
    if type(value) == "number" then return value end
    return value.id
end

local function getLayer(bar)
    if bar.layer ~= nil then return bar.layer end
    bar.layer = ui.Interfaces:GetComponent(bar.componentID)
    return bar.layer
end

local function trackComponent(bar, component)
    bar.ownDynamicIDs[component.dynamicID] = true
    return component
end

local function forEachVisual(entry, callback)
    for _, key in ipairs(ENTRY_VISUAL_KEYS) do callback(entry[key]) end
end

local function cancelPendingTooltip(entry)
    entry.pendingTooltip = nil
    entry.pendingTooltipTicks = nil
end

local function setEntryHidden(entry, hidden)
    forEachVisual(entry, function(component) component.hidden = hidden end)
    if entry.tooltipTarget ~= nil then entry.tooltipTarget.hidden = hidden end
    if hidden then
        cancelPendingTooltip(entry)
        if entry.tooltip ~= nil then entry.tooltip:Hide() end
    end
end

local function isRendered(component, iteratorVisible)
    -- Native iterator visibility can disagree with what the client actually
    -- renders, while component.visible includes native/script visibility.
    local visible = component.visible
    if visible == nil then visible = iteratorVisible end
    return visible == true and (component.alpha == nil or component.alpha > 0)
end

local function hasSpriteSource(sprite)
    if sprite == nil then return false end
    if type(sprite) == "number" then return sprite >= 0 end
    if sprite.alpha ~= nil and sprite.alpha <= 0 then return false end
    if sprite.runtimeSprite ~= nil then return true end
    if sprite.associatedObjectID ~= nil and sprite.associatedObjectID >= 0 then return true end
    if sprite.spriteID ~= nil and sprite.spriteID >= 0 then return true end

    local value = sprite.sprite
    return value ~= nil and (type(value) ~= "number" or value >= 0)
end

local function isCollectionType(componentType)
    local types = ui.ComponentType
    return componentType == types.LAYER
        or componentType == types.PANEL
        or componentType == types.GRID
        or componentType == types.PAGED_LAYER
        or componentType == types.PAGED_CAROUSEL
        or componentType == types.GROUP_BOX
end

local nativeSlotHasGraphic
nativeSlotHasGraphic = function(component, iteratorVisible, depth)
    -- BUFF_N components are permanent layer shells. Expired buffs can leave
    -- those shells visible, so occupancy must be determined from a visible
    -- sprite/button descendant that still has a drawable source.
    if not isRendered(component, iteratorVisible) then return false end

    local types = ui.ComponentType
    local componentType = component.type
    if componentType == types.SPRITE then
        return hasSpriteSource(component)
    end
    if componentType == types.BUTTON then
        if component.associatedObjectID ~= nil and component.associatedObjectID >= 0 then return true end
        return hasSpriteSource(component.sprite)
    end

    if depth >= MAX_NATIVE_GRAPHIC_DEPTH or not isCollectionType(componentType) then
        return false
    end

    local found = false
    component:IterateStaticComponents(function(child, visible)
        found = nativeSlotHasGraphic(child, visible, depth + 1)
        return found
    end)
    if found then return true end

    component:IterateDynamicComponents(function(child, visible)
        found = nativeSlotHasGraphic(child, visible, depth + 1)
        return found
    end)
    return found
end

local function ensureRow(rows, rowsByY, y)
    local row = rowsByY[y]
    if row ~= nil then return row end
    row = { y = y, occupiedRight = 0 }
    rowsByY[y] = row
    table.insert(rows, row)
    return row
end

local function nearestRow(rows, iconSize, component)
    -- Other plugins add components directly to the shared render layer.
    -- Associate those components with the closest native row so they only
    -- reserve horizontal space on the row they visually occupy.
    local componentCentre = component.y + component.height / 2
    local nearest = rows[1]
    local nearestDistance = math.abs(componentCentre - (nearest.y + iconSize / 2))
    for index = 2, #rows do
        local row = rows[index]
        local distance = math.abs(componentCentre - (row.y + iconSize / 2))
        if distance < nearestDistance then
            nearest = row
            nearestDistance = distance
        end
    end
    return nearest
end

local function scanRows(bar, layer)
    local defaultY = 0
    local iconSize = DEFAULT_ICON_SIZE
    local geometrySet = false
    local rows = {}
    local rowsByY = {}

    -- Empty native slot shells still provide useful row geometry. They define
    -- where PrettyUI should wrap, but occupiedRight remains zero until a slot
    -- contains an actual graphic.
    layer:IterateStaticComponents(function(component, visible)
        if not geometrySet then
            defaultY = component.y
            iconSize = math.max(1, component.width - 2)
            geometrySet = true
        end

        local row = ensureRow(rows, rowsByY, component.y)
        if nativeSlotHasGraphic(component, visible, 0) then
            row.occupiedRight = math.max(row.occupiedRight, component.x + component.width)
        end
        return false
    end)

    if #rows == 0 then ensureRow(rows, rowsByY, defaultY) end
    table.sort(rows, function(left, right) return left.y < right.y end)

    layer:IterateDynamicComponents(function(component, visible)
        if not bar.ownDynamicIDs[component.dynamicID] and isRendered(component, visible) then
            local row = nearestRow(rows, iconSize, component)
            row.occupiedRight = math.max(row.occupiedRight, component.x + component.width)
        end
        return false
    end)

    local signatureParts = {}
    for _, row in ipairs(rows) do
        table.insert(signatureParts, tostring(row.y) .. ":" .. tostring(row.occupiedRight))
    end
    return rows, iconSize, table.concat(signatureParts, "|")
end

local function positionEntries(bar, rows, iconSize, usableWidth)
    local function getRow(index)
        if rows[index] ~= nil then return rows[index] end
        -- PrettyUI may need more rows than the native bar currently exposes.
        -- Continue using PrettyUI's compact row spacing after the last one.
        local previous = rows[index - 1]
        local row = {
            y = previous.y + iconSize + ROW_SPACING,
            occupiedRight = 0,
        }
        rows[index] = row
        return row
    end

    local rowIndex = 1
    local currentRow = getRow(rowIndex)
    local nextX = currentRow.occupiedRight > 0
        and (currentRow.occupiedRight + NATIVE_SPACING)
        or EMPTY_ROW_X
    local rowHasPrettyUIEntry = false

    for _, entry in ipairs(bar.entries) do
        if entry.visible then
            while (currentRow.occupiedRight > 0 or rowHasPrettyUIEntry)
                and nextX + iconSize > usableWidth
            do
                rowIndex = rowIndex + 1
                currentRow = getRow(rowIndex)
                nextX = currentRow.occupiedRight > 0
                    and (currentRow.occupiedRight + NATIVE_SPACING)
                    or EMPTY_ROW_X
                rowHasPrettyUIEntry = false
            end
            local currentY = currentRow.y + 1
            local backgroundInset = iconSize >= (BORDER_THICKNESS * 2 + 1)
                and BORDER_THICKNESS
                or 0

            entry.background:SetSize(
                iconSize - backgroundInset * 2,
                iconSize - backgroundInset * 2
            )
            entry.background:SetPos(nextX + backgroundInset, currentY + backgroundInset)
            entry.sprite:SetSize(iconSize, iconSize)
            entry.sprite:SetPos(nextX, currentY)
            entry.border:SetSize(iconSize, iconSize)
            entry.border:SetPos(nextX, currentY)
            entry.label:SetSize(iconSize, LABEL_HEIGHT)
            entry.label:SetPos(nextX, currentY + LABEL_Y_OFFSET)
            if entry.tooltipTarget ~= nil then
                entry.tooltipTarget:SetSize(iconSize, iconSize)
                entry.tooltipTarget:SetPos(nextX, currentY)
            end

            nextX = nextX + iconSize + ENTRY_SPACING
            rowHasPrettyUIEntry = true
        end
    end
end

local function layout(bar, force)
    local layer = getLayer(bar)
    if layer == nil then return end

    local rows, iconSize, rowsSignature = scanRows(bar, layer)
    local usableWidth = math.max(0, (layer.width or 512) - RIGHT_MARGIN)
    -- Native state is inspected every logic tick for responsive movement.
    -- Avoid component writes unless row occupancy or geometry actually changed.
    if not force
        and iconSize == bar.lastIconSize
        and rowsSignature == bar.lastRowsSignature
        and usableWidth == bar.lastUsableWidth
    then
        return
    end

    bar.lastIconSize = iconSize
    bar.lastRowsSignature = rowsSignature
    bar.lastUsableWidth = usableWidth
    positionEntries(bar, rows, iconSize, usableWidth)
end

local function hasEntries()
    return #bars.buff.entries > 0 or #bars.debuff.entries > 0
end

local function stopIfEmpty()
    if not started or hasEntries() then return end
    Event.Logic.Unsubscribe(EVENT_ID)
    started = false
    lastLogicTick = nil
end

local function destroyEntry(bar, entry)
    if bar.entriesByID[entry.id] == nil then return false end

    for index, candidate in ipairs(bar.entries) do
        if candidate == entry then
            table.remove(bar.entries, index)
            break
        end
    end

    cancelPendingTooltip(entry)
    forEachVisual(entry, function(component)
        bar.ownDynamicIDs[component.dynamicID] = nil
        component:Destroy()
    end)
    if entry.tooltip ~= nil then
        bar.ownDynamicIDs[entry.tooltip.root.dynamicID] = nil
        entry.tooltip:Destroy()
    end
    if entry.tooltipTarget ~= nil then
        bar.ownDynamicIDs[entry.tooltipTarget.dynamicID] = nil
        entry.tooltipTarget:Destroy()
    end
    bar.entriesByID[entry.id] = nil

    return true
end

local function formatDuration(remainingTicks)
    -- Match native-style coarse minutes, then round seconds up so an active
    -- entry never displays 0s immediately before it is removed.
    if remainingTicks >= TICKS_PER_MINUTE then
        return tostring(math.floor(remainingTicks / TICKS_PER_MINUTE)) .. "m"
    end
    return tostring(math.ceil(remainingTicks / TICKS_PER_SECOND)) .. "s"
end

local function updateTimers(elapsedTicks)
    for _, bar in pairs(bars) do
        local removed = false
        for index = #bar.entries, 1, -1 do
            local entry = bar.entries[index]
            if entry.remainingTicks ~= nil then
                entry.remainingTicks = entry.remainingTicks - elapsedTicks
                if entry.remainingTicks <= 0 then
                    destroyEntry(bar, entry)
                    removed = true
                else
                    local label = formatDuration(entry.remainingTicks)
                    if entry.label.content ~= label then entry.label.content = label end
                end
            end
        end
        if removed and #bar.entries > 0 then layout(bar, true) end
    end
    stopIfEmpty()
end

local function showPendingTooltips(elapsedTicks)
    for _, bar in pairs(bars) do
        for _, entry in ipairs(bar.entries) do
            local tooltip = entry.pendingTooltip
            if tooltip ~= nil then
                entry.pendingTooltipTicks = entry.pendingTooltipTicks - elapsedTicks
                if entry.pendingTooltipTicks <= 0 then
                    cancelPendingTooltip(entry)
                    if entry.visible and entry.tooltip == tooltip then tooltip:Show() end
                end
            end
        end
    end
end

local function ensureStarted()
    if started then return end
    started = true
    Event.Logic.Subscribe(EVENT_ID, function(event)
        -- Normally this delta is one. Using the event counter also keeps timers
        -- correct if callbacks are delayed or client logic ticks are skipped.
        local elapsedTicks = 1
        if lastLogicTick ~= nil and event.logicTick > lastLogicTick then
            elapsedTicks = event.logicTick - lastLogicTick
        end
        lastLogicTick = event.logicTick

        updateTimers(elapsedTicks)
        if #bars.buff.entries > 0 then layout(bars.buff, false) end
        if #bars.debuff.entries > 0 then layout(bars.debuff, false) end
        showPendingTooltips(elapsedTicks)
    end)
end

local function setTooltip(bar, entry, value, deferLayout)
    if entry.tooltip ~= nil and value ~= nil and type(value) ~= "table" then
        return entry.tooltip:SetText(value)
    end
    cancelPendingTooltip(entry)
    if entry.tooltip ~= nil then
        if entry.tooltip.root ~= nil then
            bar.ownDynamicIDs[entry.tooltip.root.dynamicID] = nil
        end
        entry.tooltip:Destroy()
        entry.tooltip = nil
    end
    if value == nil then
        if entry.tooltipTarget ~= nil then
            bar.ownDynamicIDs[entry.tooltipTarget.dynamicID] = nil
            entry.tooltipTarget:Destroy()
            entry.tooltipTarget = nil
        end
        return true
    end

    if entry.tooltipTarget == nil then
        entry.tooltipTarget = trackComponent(bar, ui.Layer.new(entry.layer))
    end
    entry.tooltip = Tooltip.attach(entry.tooltipTarget, entry.layer, value, {
        onMouseOver = function(tooltip)
            if entry.visible then
                entry.pendingTooltip = tooltip
                entry.pendingTooltipTicks = TOOLTIP_DELAY_TICKS
            end
        end,
        onMouseLeave = function(tooltip)
            if entry.pendingTooltip == tooltip then cancelPendingTooltip(entry) end
            tooltip:Hide()
        end,
    })
    trackComponent(bar, entry.tooltip.root)
    entry.tooltipTarget.hidden = not entry.visible
    if deferLayout ~= true then layout(bar, true) end
    return true
end

local Handle = {}
Handle.__index = Handle

function Handle:SetLabel(text, rgba)
    local entry = self._bar.entriesByID[self._id]
    if entry == nil or entry.remainingTicks ~= nil then return false end
    entry.label.content = tostring(text or "")
    if rgba ~= nil then entry.label.rgba = rgba end
    return true
end

function Handle:SetObject(value)
    local entry = self._bar.entriesByID[self._id]
    if entry == nil then return false end
    local objectID = resolveObjId(value)
    if value ~= nil then
        objectID = math.tointeger(objectID)
        if objectID == nil then return false end
    end
    entry.sprite.spriteID = -1
    entry.sprite:SetAssociatedObject(objectID or -1)
    return true
end

function Handle:SetSprite(spriteID)
    local entry = self._bar.entriesByID[self._id]
    if entry == nil then return false end
    if spriteID ~= nil then
        spriteID = math.tointeger(spriteID)
        if spriteID == nil then return false end
    end
    entry.sprite:SetAssociatedObject(-1)
    entry.sprite.spriteID = spriteID or -1
    return true
end

function Handle:SetTooltip(value)
    local entry = self._bar.entriesByID[self._id]
    if entry == nil then return false end
    return setTooltip(self._bar, entry, value)
end

function Handle:SetVisible(visible)
    local entry = self._bar.entriesByID[self._id]
    if entry == nil then return false end

    local nextVisible = visible == true
    if entry.visible == nextVisible then return true end
    entry.visible = nextVisible
    setEntryHidden(entry, not nextVisible)
    layout(self._bar, true)
    return true
end

local function add(bar, options)
    options = options or {}
    if options.duration ~= nil
        and (
            type(options.duration) ~= "number"
            or options.duration <= 0
            or options.duration ~= options.duration
            or options.duration == math.huge
        )
    then
        log("[PrettyUI BuffBar] duration must be a positive number of seconds")
        return nil
    end

    local layer = getLayer(bar)
    if layer == nil then
        log("[PrettyUI BuffBar] " .. bar.name .. " render layer not found; entry not added")
        return nil
    end

    nextEntryID = nextEntryID + 1

    local background = trackComponent(bar, ui.Rectangle.new(layer))
    background.fill = true
    background.rgba = options.backgroundRgba or BACKGROUND_RGBA
    background.clickthrough = true

    local sprite = trackComponent(bar, ui.Sprite.new(layer))
    sprite.outlineWidth = 1
    sprite.clickthrough = true
    if options.objId ~= nil then
        local objId = resolveObjId(options.objId)
        if objId ~= nil then sprite:SetAssociatedObject(objId) end
    elseif options.spriteID ~= nil then
        sprite.spriteID = options.spriteID
    end

    local border = trackComponent(bar, ui.Rectangle.new(layer))
    border.fill = false
    border.outlineThickness = BORDER_THICKNESS
    border.rgba = bar.allowBorderOverride and (options.borderRgba or bar.borderRGBA)
        or bar.borderRGBA
    border.clickthrough = true

    local remainingTicks = options.duration ~= nil
        and math.ceil(options.duration * TICKS_PER_SECOND)
        or nil
    local label = trackComponent(bar, ui.Text.new(layer))
    label.font = options.font or id.Font.NOTOSANS_BOLD_12
    label.isShadowed = true
    label.alignHorizontal = ui.AlignMode.CENTRE
    label.content = remainingTicks ~= nil
        and formatDuration(remainingTicks)
        or tostring(options.label or "")
    label.rgba = options.labelRgba or DEFAULT_LABEL_RGBA
    label.clickthrough = true

    local visible = options.visible ~= false

    local entry = {
        id = nextEntryID,
        background = background,
        sprite = sprite,
        border = border,
        label = label,
        layer = layer,
        visible = visible,
        remainingTicks = remainingTicks,
    }
    table.insert(bar.entries, entry)
    bar.entriesByID[entry.id] = entry
    if options.tooltip ~= nil then setTooltip(bar, entry, options.tooltip, true) end
    setEntryHidden(entry, not visible)

    ensureStarted()
    layout(bar, true)
    return setmetatable({ _id = entry.id, _bar = bar }, Handle)
end

local function remove(bar, handle)
    if type(handle) ~= "table" or handle._bar ~= bar then return false end
    local entry = bar.entriesByID[handle._id]
    if entry == nil or not destroyEntry(bar, entry) then return false end

    if #bar.entries > 0 then layout(bar, true) end
    stopIfEmpty()
    return true
end

-- options:
--   spriteID        integer      Static sprite ID to display.
--   objId           integer      Object ID used with SetAssociatedObject. Takes
--                                precedence over spriteID.
--   label           string       Label for an untimed entry (default "").
--   labelRgba       integer      Packed 0xRRGGBBAA label colour (default white).
--   backgroundRgba  integer      Optional packed 0xRRGGBBAA background colour.
--   borderRgba      integer      Buff-only packed 0xRRGGBBAA border colour.
--                                Debuffs always use their fixed red border.
--   font            integer      Label font ID (default NOTOSANS_BOLD_12).
--   tooltip         string|table Tooltip text or standard Tooltip options.
--   visible         boolean      Initial visibility (default true).
--   duration        number       Optional lifetime in seconds. Timed entries
--                                display whole minutes at 60 seconds or more,
--                                then seconds, and remove themselves at zero.
--
-- Returned handles support SetVisible(visible), SetLabel(text, rgba),
-- SetObject(objId), SetSprite(spriteID), and SetTooltip(value). They return
-- false after removal. SetObject and SetSprite switch the icon source and
-- accept nil to clear it. Passing nil to SetTooltip removes the tooltip; a
-- later non-nil value adds it again. Timed entries own their label, so SetLabel
-- returns false for them; hiding an entry does not pause its duration.
function BuffBar.addBuff(options)
    return add(bars.buff, options)
end

function BuffBar.removeBuff(handle)
    return remove(bars.buff, handle)
end

function BuffBar.addDebuff(options)
    return add(bars.debuff, options)
end

function BuffBar.removeDebuff(handle)
    return remove(bars.debuff, handle)
end

function BuffBar.Shutdown()
    if started then
        Event.Logic.Unsubscribe(EVENT_ID)
        started = false
    end

    for _, bar in pairs(bars) do
        for index = #bar.entries, 1, -1 do
            destroyEntry(bar, bar.entries[index])
        end
        bar.layer = nil
        bar.lastIconSize = nil
        bar.lastRowsSignature = nil
        bar.lastUsableWidth = nil
    end
    lastLogicTick = nil
end

return BuffBar
