local Components = require("src/core/components")
local Cursor = require("src/core/cursor")
local InterfaceMouse = require("src/core/mouse")
local Palette = require("src/core/control_palette")
local Sprites = require("src/core/sprites")
local Tooltip = require("src/tooltip")
local clamp = require("src/core/math").clamp

local List = {}
List.__index = List

local DEFAULT_WIDTH = 240
local DEFAULT_HEIGHT = 120
local DEFAULT_ENTRY_HEIGHT = 24
local DEFAULT_TEXT_COLOUR = Palette.TEXT
local DISABLED_TEXT_COLOUR = Palette.DISABLED_TEXT
local BACKGROUND_COLOUR = 0x171512E8
local BORDER_COLOUR = 0x716B61FF
local HOVER_COLOUR = Palette.HOVER
local SELECTED_COLOUR = Palette.SELECTED
local BAR_WIDTH = 16
local ARROW_SIZE = 16
local END_SIZE = 5
local MIN_THUMB_HEIGHT = 24

local function entryParts(entry, fallbackID)
    if type(entry) == "table" then
        return tostring(entry.label or entry.text or ""), entry.id or entry.value or fallbackID
    end
    return tostring(entry), fallbackID
end

local function rowBackgroundColour(list, entry, hovered)
    if entry.selected then
        return entry.selectedColour or list.selectedColour
    end
    if hovered then
        return entry.hoverColour or list.hoverColour
    end
    return entry.backgroundColour or 0x00000000
end

local function rowTextColour(list, entry)
    if list.disabled or not entry.enabled then
        return entry.disabledTextColour or list.disabledTextColour
    end
    return entry.textColour or list.textColour
end

local function rectangle(parent, colour, fill)
    local component = Components.new(ui.Rectangle, parent)
    component:SetSize(0, 0, 1.0, 1.0)
    component.fill = fill ~= false
    component.rgba = colour
    component.clickthrough = true
    return component
end

local function frameEdge(parent, x, y, width, height, xAnchor, yAnchor, widthAnchor, heightAnchor)
    local component = Components.new(ui.Rectangle, parent)
    component:SetPos(x, y, xAnchor or 0, yAnchor or 0)
    component:SetSize(width, height, widthAnchor or 0, heightAnchor or 0)
    component.fill = true
    component.rgba = BORDER_COLOUR
    component.clickthrough = true
    return component
end

local function sprite(parent, spriteID)
    local component = Components.new(ui.Sprite, parent)
    component.spriteID = spriteID
    component.clickthrough = false
    return component
end

function List.getSize(options)
    options = options or {}
    return options.width or DEFAULT_WIDTH, options.height or DEFAULT_HEIGHT
end

function List.new(parent, options)
    options = options or {}
    local self = setmetatable({}, List)
    self.onChange = options.onChange
    self.disabled = options.disabled == true
    self.maxSelected = math.max(1, math.floor(options.maxSelected or 1))
    self.entryHeight = math.max(16, math.floor(options.entryHeight or DEFAULT_ENTRY_HEIGHT))
    self.entryIconScale = options.entryIconScale or 100
    self.font = options.font or id.Font.MUSEO_SANS_15PT_REGULAR
    self.textColour = options.colour or options.color or DEFAULT_TEXT_COLOUR
    self.disabledTextColour = options.disabledColour or options.disabledColor or DISABLED_TEXT_COLOUR
    self.backgroundColour = options.backgroundColour or options.backgroundColor or BACKGROUND_COLOUR
    self.borderColour = options.borderColour or options.borderColor or BORDER_COLOUR
    self.hoverColour = options.hoverColour or options.hoverColor or HOVER_COLOUR
    self.selectedColour = options.selectedColour or options.selectedColor or SELECTED_COLOUR
    self.shadowed = options.shadowed ~= false
    self._onScrollWheel = options._onScrollWheel
    self._onEntryClick = options._onEntryClick
    self.entries = {}
    self.entriesByID = {}
    self.rows = {}
    self.scrollY = 0
    self.parent = parent
    self.widthValue = options.width or DEFAULT_WIDTH
    self.widthAnchor = options.widthAnchor or 0
    self.heightValue = options.height or DEFAULT_HEIGHT
    self.heightAnchor = options.heightAnchor or 0

    self.interfaceID = parent.interfaceID
    self.root = Components.new(ui.Layer, parent)
    self.root:SetPos(options.x or 0, options.y or 0, options.xAnchor or 0, options.yAnchor or 0)
    self.root:SetSize(
        options.width or DEFAULT_WIDTH,
        options.height or DEFAULT_HEIGHT,
        options.widthAnchor or 0,
        options.heightAnchor or 0
    )
    self.root.clickthrough = false
    self.background = rectangle(self.root, self.backgroundColour)
    self.viewport = Components.new(ui.Layer, self.root)
    self.viewport:SetPos(1, 1)
    self.viewport:SetSize(-2, -2, 1.0, 1.0)
    self.viewport.clickthrough = false
    self.frame = {
        frameEdge(self.root, 0, 0, 0, 1, 0, 0, 1.0, 0),
        frameEdge(self.root, 0, self.root.height - 1, 0, 1, 0, 0, 1.0, 0),
        frameEdge(self.root, 0, 0, 1, self.root.height),
        frameEdge(self.root, -1, 0, 1, self.root.height, 1.0, 0),
    }
    for _, edge in ipairs(self.frame) do edge.rgba = self.borderColour end

    -- Keep scrollbar visuals as narrow direct children of the list root. They
    -- never become parents or siblings of the working row viewport.
    self.upArrow = sprite(self.root, Sprites.SCROLL_ARROW_UP)
    self.upArrow:SetPos(-BAR_WIDTH - 1, 1, 1.0, 0)
    self.upArrow:SetSize(BAR_WIDTH, ARROW_SIZE)
    self.downArrow = sprite(self.root, Sprites.SCROLL_ARROW_DOWN)
    self.downArrow:SetPos(-BAR_WIDTH - 1, -ARROW_SIZE - 1, 1.0, 1.0)
    self.downArrow:SetSize(BAR_WIDTH, ARROW_SIZE)

    local trackHeight = math.max(1, self:_ResolvedHeight() - ARROW_SIZE * 2 - 2)
    self.track = Components.new(ui.Layer, self.root)
    self.track:SetPos(-BAR_WIDTH - 1, ARROW_SIZE + 1, 1.0, 0)
    self.track:SetSize(BAR_WIDTH, trackHeight)
    self.track.clickthrough = false
    self.trackTop = sprite(self.track, Sprites.SCROLL_TRACK_TOP)
    self.trackTop:SetSize(BAR_WIDTH, END_SIZE)
    self.trackCentre = sprite(self.track, Sprites.SCROLL_TRACK_CENTRE)
    self.trackCentre:SetPos(0, END_SIZE)
    self.trackCentre:SetSize(BAR_WIDTH, math.max(1, trackHeight - END_SIZE * 2))
    self.trackCentre.isTiling = true
    self.trackBottom = sprite(self.track, Sprites.SCROLL_TRACK_BOTTOM)
    self.trackBottom:SetPos(0, math.max(0, trackHeight - END_SIZE))
    self.trackBottom:SetSize(BAR_WIDTH, END_SIZE)

    self.thumb = Components.new(ui.Layer, self.track)
    self.thumb.clickthrough = false
    self.thumbTop = sprite(self.thumb, Sprites.SCROLL_THUMB_TOP)
    self.thumbTop:SetSize(BAR_WIDTH, END_SIZE)
    self.thumbCentre = sprite(self.thumb, Sprites.SCROLL_THUMB_CENTRE)
    self.thumbCentre:SetPos(0, END_SIZE)
    self.thumbCentre.isTiling = true
    self.thumbBottom = sprite(self.thumb, Sprites.SCROLL_THUMB_BOTTOM)
    self:_SetScrollbarHidden(true)

    self.upArrow:Subscribe(ui.Hook.ONCLICK, function()
        self:SetScrollPosition(self.scrollY - self.entryHeight)
        return false
    end)
    self.downArrow:Subscribe(ui.Hook.ONCLICK, function()
        self:SetScrollPosition(self.scrollY + self.entryHeight)
        return false
    end)
    self.track:Subscribe(ui.Hook.ONCLICK, function(_, _, clickY)
        local maxScroll = math.max(0, self.contentHeight - self:_ViewportHeight())
        local travel = self.track.height - self.thumbHeight
        if maxScroll > 0 and travel > 0 then
            self:SetScrollPosition((clickY - self.thumbHeight / 2) * maxScroll / travel)
        end
        return false
    end)

    local dragStart = nil
    self.thumb:Subscribe(ui.Hook.ONCLICK, function(component, x, y)
        local mouse = InterfaceMouse.GetPosition(component, x, y)
        if mouse then dragStart = { mouseY = mouse.y, scrollY = self.scrollY } end
        return false
    end)
    self.thumb:Subscribe(ui.Hook.ONHOLD, function(component, x, y)
        local mouse = InterfaceMouse.GetPosition(component, x, y)
        local maxScroll = math.max(0, self.contentHeight - self:_ViewportHeight())
        local travel = self.track.height - self.thumbHeight
        if dragStart and mouse and maxScroll > 0 and travel > 0 then
            self:SetScrollPosition(dragStart.scrollY + (mouse.y - dragStart.mouseY) * maxScroll / travel)
        end
        return false
    end)
    self.thumb:Subscribe(ui.Hook.ONRELEASE, function()
        dragStart = nil
        return false
    end)

    local function onListWheel(component, delta)
        return self:_OnScrollWheel(component, delta)
    end
    self.upArrow:Subscribe(ui.Hook.ONSCROLLWHEEL, onListWheel)
    self.downArrow:Subscribe(ui.Hook.ONSCROLLWHEEL, onListWheel)
    self.track:Subscribe(ui.Hook.ONSCROLLWHEEL, onListWheel)
    self.thumb:Subscribe(ui.Hook.ONSCROLLWHEEL, onListWheel)
    self.viewport:Subscribe(ui.Hook.ONSCROLLWHEEL, onListWheel)

    self.root:Subscribe(ui.Hook.ONSCROLLWHEEL, function(component, delta)
        return self:_OnScrollWheel(component, delta)
    end)

    local ok, err = pcall(self.SetEntries, self, options.entries or options.choices or {})
    if not ok then
        self.root:Destroy()
        error(err, 0)
    end
    Tooltip.bind(self, self.root, parent, options.tooltip)
    return self
end

function List:_SetScrollbarHidden(hidden)
    self.upArrow.hidden = hidden
    self.downArrow.hidden = hidden
    self.track.hidden = hidden
end

function List:_ResolvedWidth()
    if self.root.width > 0 then return self.root.width end
    return math.max(1, self.widthValue + (self.parent.width or 0) * self.widthAnchor)
end

function List:_ResolvedHeight()
    if self.root.height > 0 then return self.root.height end
    return math.max(1, self.heightValue + (self.parent.height or 0) * self.heightAnchor)
end

function List:_ViewportHeight()
    return math.max(1, self:_ResolvedHeight() - 2)
end

function List:SetSize(width, height, widthAnchor, heightAnchor)
    self.widthValue = width or self.widthValue
    self.heightValue = height or self.heightValue
    self.widthAnchor = widthAnchor or 0
    self.heightAnchor = heightAnchor or 0
    self.root:SetSize(
        self.widthValue,
        self.heightValue,
        self.widthAnchor,
        self.heightAnchor
    )

    local resolvedHeight = self:_ResolvedHeight()
    self.frame[2]:SetPos(0, resolvedHeight - 1)
    self.frame[3]:SetSize(1, resolvedHeight)
    self.frame[4]:SetSize(1, resolvedHeight)

    local trackHeight = math.max(1, resolvedHeight - ARROW_SIZE * 2 - 2)
    self.track:SetSize(BAR_WIDTH, trackHeight)
    self.trackCentre:SetSize(BAR_WIDTH, math.max(1, trackHeight - END_SIZE * 2))
    self.trackBottom:SetPos(0, math.max(0, trackHeight - END_SIZE))
    self:SetScrollPosition(self.scrollY)
end

function List:_OnScrollWheel(component, delta)
    local maxScroll = math.max(0, self.contentHeight - self:_ViewportHeight())
    if maxScroll > 0 then
        local previous = self.scrollY
        self:SetScrollPosition(self.scrollY + delta * self.entryHeight)
        if self.scrollY ~= previous then return false end
    end
    if self._onScrollWheel then return self._onScrollWheel(component, delta) end
    return false
end

function List:SetScrollPosition(value)
    local viewportHeight = self:_ViewportHeight()
    local maxScroll = math.max(0, (self.contentHeight or 0) - viewportHeight)
    self.scrollY = clamp(math.floor(value or 0), 0, maxScroll)
    self.viewport:SetScrollPos(0, self.scrollY)
    local rowWidth = math.max(1, self:_ResolvedWidth() - 2 - (maxScroll > 0 and BAR_WIDTH or 0))
    for _, row in ipairs(self.rows) do row.root:SetSize(rowWidth, self.entryHeight) end

    if maxScroll <= 0 then
        self:_SetScrollbarHidden(true)
        return
    end

    self:_SetScrollbarHidden(false)
    local trackHeight = math.max(1, self.track.height)
    local thumbHeight = clamp(
        math.floor(trackHeight * viewportHeight / self.contentHeight),
        math.min(MIN_THUMB_HEIGHT, trackHeight),
        trackHeight
    )
    local travel = trackHeight - thumbHeight
    local thumbY = travel > 0 and math.floor(self.scrollY / maxScroll * travel) or 0
    self.thumbHeight = thumbHeight
    self.thumb:SetPos(0, thumbY)
    self.thumb:SetSize(BAR_WIDTH, thumbHeight)
    self.thumbCentre:SetSize(BAR_WIDTH, math.max(1, thumbHeight - END_SIZE * 2))
    self.thumbBottom:SetPos(0, math.max(0, thumbHeight - END_SIZE))
    self.thumbBottom:SetSize(BAR_WIDTH, END_SIZE)
end

function List:_Notify(entry, eventType)
    if self._suppressCallbacks or not self.onChange then return end
    self.onChange(self, entry.id, eventType == ui.SelectionChangeEvent.SELECTED, eventType)
end

function List:_SelectedCount()
    local count = 0
    for _, entry in ipairs(self.entries) do
        if entry.selected then count = count + 1 end
    end
    return count
end

function List:_Select(entry, selected, notify)
    if not entry or not entry.enabled or not entry.visible then return false end
    selected = selected == true
    if entry.selected == selected then return true end

    if selected and self.maxSelected == 1 then
        for _, other in ipairs(self.entries) do
            if other ~= entry and other.selected then
                other.selected = false
                if notify then self:_Notify(other, ui.SelectionChangeEvent.DESELECTED) end
            end
        end
    elseif selected and self:_SelectedCount() >= self.maxSelected then
        if notify then self:_Notify(entry, ui.SelectionChangeEvent.ERROR_MAX_SELECTED) end
        return false
    end

    entry.selected = selected
    self:_RefreshRows()
    if notify then
        self:_Notify(entry, selected and ui.SelectionChangeEvent.SELECTED or ui.SelectionChangeEvent.DESELECTED)
    end
    return true
end

function List:_RefreshRows()
    for _, row in ipairs(self.rows) do
        row.background.rgba = rowBackgroundColour(self, row.entry, false)
        row.label.rgba = rowTextColour(self, row.entry)
    end
end

function List:_BuildRow(entry, baseY)
    local row = Components.new(ui.Layer, self.viewport)
    local record = { root = row, entry = entry, baseY = baseY }
    self.rows[#self.rows + 1] = record
    row:SetPos(0, baseY)
    row:SetSize(0, self.entryHeight, 1.0, 0)
    row.clickthrough = self.disabled or not entry.enabled

    local rowBackground = rectangle(row, rowBackgroundColour(self, entry, false))
    rowBackground:Subscribe(ui.Hook.ONSCROLLWHEEL, function(component, delta)
        return self:_OnScrollWheel(component, delta)
    end)
    local left = 8
    if entry.icon ~= nil then
        local iconSize = math.max(1, math.floor(16 * self.entryIconScale / 100))
        local icon = Components.new(ui.Sprite, row)
        icon:SetPos(7, math.floor((self.entryHeight - iconSize) / 2))
        icon:SetSize(iconSize, iconSize)
        icon.spriteID = entry.icon
        icon.clickthrough = true
        icon:Subscribe(ui.Hook.ONSCROLLWHEEL, function(component, delta)
            return self:_OnScrollWheel(component, delta)
        end)
        left = 7 + iconSize + 6
    end

    local label = Components.new(ui.Text, row)
    label:SetPos(left, 0)
    label:SetSize(-left - 6, self.entryHeight, 1.0, 0)
    label.content = entry.text
    label.font = self.font
    label.rgba = rowTextColour(self, entry)
    label.isShadowed = self.shadowed
    label.maxLines = 1
    label.alignVertical = ui.AlignMode.CENTRE
    label.clickthrough = true
    label:Subscribe(ui.Hook.ONSCROLLWHEEL, function(component, delta)
        return self:_OnScrollWheel(component, delta)
    end)
    row:Subscribe(ui.Hook.ONSCROLLWHEEL, function(component, delta)
        return self:_OnScrollWheel(component, delta)
    end)

    if not self.disabled and entry.enabled then
        row:Subscribe(ui.Hook.ONMOUSEOVER, function()
            rowBackground.rgba = rowBackgroundColour(self, entry, true)
            return true
        end)
        row:Subscribe(ui.Hook.ONMOUSELEAVE, function()
            rowBackground.rgba = rowBackgroundColour(self, entry, false)
            return true
        end)
        row:Subscribe(ui.Hook.ONCLICK, function()
            local selected = self.maxSelected > 1 and not entry.selected or true
            local succeeded = self:_Select(entry, selected, true)
            if succeeded and self._onEntryClick then
                self._onEntryClick(self, entry.id, entry.selected)
            end
            return false
        end)
        Cursor.apply(row, config.Cursor.CURSOR_TICK, true)
    end
    record.background = rowBackground
    record.label = label
end

function List:_RebuildRows()
    for _, row in ipairs(self.rows) do row.root:Destroy() end
    self.rows = {}

    local ok, result = pcall(Components.withBatch, self.viewport, function()
        local visibleIndex = 0
        for _, entry in ipairs(self.entries) do
            if entry.visible then
                self:_BuildRow(entry, visibleIndex * self.entryHeight)
                visibleIndex = visibleIndex + 1
            end
        end
        return visibleIndex
    end)
    if not ok then
        for _, row in ipairs(self.rows) do row.root:Destroy() end
        self.rows = {}
        error(result, 0)
    end
    local visibleIndex = result
    self.contentHeight = math.max(1, visibleIndex * self.entryHeight)
    self.viewport:SetScrollSize(
        math.max(1, self:_ResolvedWidth() - 2),
        math.max(self:_ViewportHeight(), self.contentHeight)
    )
    self:SetScrollPosition(self.scrollY)
    for _, edge in ipairs(self.frame) do edge:MoveToFront() end
    self.upArrow:MoveToFront()
    self.downArrow:MoveToFront()
    self.track:MoveToFront()
end

function List:Add(label, entryID)
    if entryID == nil or self.entriesByID[entryID] ~= nil then return false end
    local entry = {
        id = entryID,
        text = tostring(label),
        enabled = true,
        visible = true,
        selected = false,
    }
    table.insert(self.entries, entry)
    self.entriesByID[entryID] = entry
    self:_RebuildRows()
    return true
end

function List:Clear()
    self.entries = {}
    self.entriesByID = {}
    self:_RebuildRows()
end

function List:SetEntries(entries)
    self.entries = {}
    self.entriesByID = {}
    for index, value in ipairs(entries or {}) do
        local label, entryID = entryParts(value, index)
        if self.entriesByID[entryID] == nil then
            local entry = {
                id = entryID,
                text = label,
                enabled = type(value) ~= "table" or (value.enabled ~= false and value.disabled ~= true),
                visible = type(value) ~= "table" or value.visible ~= false,
                selected = type(value) == "table" and value.selected == true,
                icon = type(value) == "table" and value.icon or nil,
                backgroundColour = type(value) == "table"
                    and (value.backgroundColour or value.backgroundColor)
                    or nil,
                hoverColour = type(value) == "table"
                    and (value.hoverColour or value.hoverColor)
                    or nil,
                selectedColour = type(value) == "table"
                    and (value.selectedColour or value.selectedColor)
                    or nil,
                textColour = type(value) == "table"
                    and (value.textColour or value.textColor or value.colour or value.color)
                    or nil,
                disabledTextColour = type(value) == "table"
                    and (value.disabledTextColour or value.disabledTextColor)
                    or nil,
            }
            table.insert(self.entries, entry)
            self.entriesByID[entryID] = entry
        end
    end

    local selected = 0
    for _, entry in ipairs(self.entries) do
        if entry.selected then
            selected = selected + 1
            if selected > self.maxSelected then entry.selected = false end
        end
    end
    self:_RebuildRows()
end

function List:SetSelected(entryID, selected, triggerEvents)
    return self:_Select(self.entriesByID[entryID], selected, triggerEvents == true)
end

function List:UnselectAll()
    for _, entry in ipairs(self.entries) do entry.selected = false end
    self:_RefreshRows()
end

function List:SetEntryEnabled(entryID, enabled)
    local entry = self.entriesByID[entryID]
    if not entry then return false end
    entry.enabled = enabled == true
    if not entry.enabled then entry.selected = false end
    self:_RebuildRows()
    return true
end

function List:SetEntryVisible(entryID, visible)
    local entry = self.entriesByID[entryID]
    if not entry then return false end
    entry.visible = visible == true
    if not entry.visible then entry.selected = false end
    self:_RebuildRows()
    return true
end

function List:SetEntryIcon(entryID, spriteID)
    local entry = self.entriesByID[entryID]
    if not entry then return false end
    entry.icon = spriteID
    self:_RebuildRows()
    return true
end

function List:GetSelectedEntries()
    local selected = {}
    for _, entry in ipairs(self.entries) do
        if entry.selected then table.insert(selected, entry) end
    end
    return selected
end

function List:SetDisabled(disabled)
    self.disabled = disabled == true
    self.root.enabled = not self.disabled
    self.root.clickthrough = self.disabled
    self:_RebuildRows()
end

function List:SetTooltip(value)
    return Tooltip.set(self, value)
end

function List:Destroy()
    Tooltip.unbind(self)
    if self.root then
        if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.root:Destroy() end
        self.root = nil
    end
    self.rows = {}
    self.entries = {}
    self.entriesByID = {}
end

return List
