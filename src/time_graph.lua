local Components = require("src/core/components")
local Stream = require("src/core/time_graph_stream")
local Wheel = require("src/core/wheel")
local Tooltip = require("src/tooltip")
local clamp = require("src/core/math").clamp

local TimeGraph = {}
TimeGraph.__index = TimeGraph
TimeGraph.CreateEventBus = Stream.CreateEventBus

local DEFAULT_WIDTH = 480
local DEFAULT_HEIGHT = 260
local TEXT_RGBA = 0xE7D7B0FF
local GOLD_RGBA = 0xF2C66DFF
local GRID_RGBA = 0x74634455
local BAR_RGBA = 0xC49946FF
local NEGATIVE_RGBA = 0xBC7770FF
-- Match the alternating row backgrounds used by the PrettyUI gallery.
local BACKGROUND_RGBA = 0x2E2825FF
local PLOT_RGBA = 0x24211EFF
local BAR_ALPHA = 0.65
local BAR_GAP = 2
local PULSE_TICKS = 60 -- 1.2 seconds at the client's fixed 50 Hz.
local instances = {}
local nextID = 0

local function dimension(value, fallback)
    if value == nil then return fallback end
    assert(type(value) == "number" and value == value and math.abs(value) < math.huge,
        "graph dimensions must be finite numbers")
    return math.floor(value)
end

local function compact(value)
    local magnitude = math.abs(value)
    if magnitude >= 1e12 then return string.format("%.3g", value) end
    if magnitude >= 1e9 then return string.format("%.1fB", value / 1e9) end
    if magnitude >= 1e6 then return string.format("%.1fM", value / 1e6) end
    if magnitude >= 1e3 then return string.format("%.1fK", value / 1e3) end
    if value == 0 then return "0" end
    return string.format("%.4g", value)
end

local function timestamp(seconds)
    if seconds < 0 then return "" end
    local minutes = math.floor(seconds / 60)
    local remaining = seconds - minutes * 60
    if seconds % 1 ~= 0 then
        return string.format("%d:%05.2f", minutes, remaining)
    end
    return string.format("%d:%02d", minutes, remaining)
end

local function rectangle(parent, rgba)
    local component = Components.new(ui.Rectangle, parent)
    component.fill = true
    component.rgba = rgba
    component.clickthrough = true
    return component
end

local function label(parent, rgba, alignment)
    local component = Components.new(ui.Text, parent)
    component.font = id.Font.MUSEO_SANS_15PT_REGULAR
    component.rgba = rgba or TEXT_RGBA
    component.isShadowed = true
    component.alignHorizontal = alignment or ui.AlignMode.TOPLEFT
    component.alignVertical = ui.AlignMode.CENTRE
    component.maxLines = 1
    component.clickthrough = true
    return component
end

local function place(component, x, y, width, height)
    component:SetPos(x, y)
    component:SetSize(math.max(0, width), math.max(0, height))
end

local function setText(component, content)
    if component.content ~= content then component.content = content end
end

local function visibleBuckets(capacity, zoom)
    assert(type(zoom) == "number" and zoom == zoom and zoom > 0 and zoom < math.huge,
        "graph zoom must be a positive finite number")
    return clamp(math.floor(capacity / zoom + 0.5), 2, capacity)
end

function TimeGraph.getSize(options)
    options = options or {}
    return dimension(options.width, DEFAULT_WIDTH), dimension(options.height, DEFAULT_HEIGHT)
end

-- options.metric = { id, label?, spriteID?, rgba? } is reusable metadata.
-- Each graph captures that metadata and consumes signed deltas for metric.id.
-- Sharing a descriptor or bus does not share/reset another graph's history.
-- Position/size anchors follow other components. Hiding keeps time.
function TimeGraph.new(parent, options)
    options = options or {}
    local metric = options.metric
    assert(type(metric) == "table", "TimeGraph requires a metric descriptor")
    local model = Stream.new({ metric = metric.id, interval = options.interval, capacity = options.capacity })
    local visibleCount = visibleBuckets(model.capacity, options.zoom or 1)
    assert(metric.spriteID == nil or (type(metric.spriteID) == "number"
        and metric.spriteID >= 0 and metric.spriteID < math.huge
        and metric.spriteID == math.floor(metric.spriteID)), "metric spriteID must be a nonnegative integer")
    local width, height = TimeGraph.getSize(options)
    local bus = options.bus or TimeGraph.CreateEventBus()
    assert(type(bus) == "table" and type(bus.Update) == "table"
        and type(bus.Update.Subscribe) == "function"
        and type(bus.Update.Unsubscribe) == "function",
        "graph bus must expose Update.Subscribe and Update.Unsubscribe")

    local self = setmetatable({}, TimeGraph)
    self.model = model
    self.bus = bus
    self.label = tostring(metric.label or model.metric)
    self.amountSuffix = self.label ~= "" and (" " .. self.label) or ""
    self.visibleCount = visibleCount
    self.zoomable = options.zoomable ~= false
    self.onZoom = options.onZoom
    self.barRGBA = metric.rgba or BAR_RGBA
    self.widthAnchor = options.widthAnchor or 0
    self.heightAnchor = options.heightAnchor or 0
    self.bars = {}
    self.grid = {}
    self.yLabels = {}
    self.xLabels = {}
    self.dirty = true

    self.interfaceID = parent.interfaceID
    self.root = Components.new(ui.Layer, parent)
    self.root:SetPos(options.x or 0, options.y or 0, options.xAnchor or 0, options.yAnchor or 0)
    self.root:SetSize(width, height, self.widthAnchor, self.heightAnchor)
    self.root.hidden = options.visible == false
    self.root.clickthrough = false
    Wheel.bind(self.root, options)

    self.background = rectangle(self.root, BACKGROUND_RGBA)
    self.border = rectangle(self.root, 0x766341FF)
    self.border.fill = false
    self.border.outlineThickness = 1
    self.header = Components.new(ui.Layer, self.root)
    Wheel.bind(self.header, options)
    if metric.spriteID ~= nil then
        self.icon = Components.new(ui.Sprite, self.header)
        self.icon.spriteID = metric.spriteID
        self.icon.clickthrough = true
    else
        self.title = label(self.header, GOLD_RGBA)
        self.title.font = id.Font.CINZEL_13PT_BOLD
        self.title.content = self.label
    end
    local parentContext = Tooltip.getContext(parent)
    self.tooltipContext = Tooltip.registerContext(self.root, parentContext and parentContext.parent or parent, function(target)
        local x, y
        if parentContext then x, y = parentContext.position(self.root)
        else x, y = self.root.x, self.root.y end
        return x + target.x, y + target.y
    end, parentContext)
    Tooltip.bind(self, self.header, self.root, nil)

    self.plot = Components.new(ui.Layer, self.root)
    self.plot.clickthrough = false
    if self.zoomable then
        self.plot:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, delta)
            if delta < 0 then self:ZoomIn()
            elseif delta > 0 then self:ZoomOut() end
            return false
        end)
    else
        Wheel.bind(self.plot, options)
    end
    self.plotBackground = rectangle(self.plot, PLOT_RGBA)
    for index = 1, 2 do
        self.grid[index] = rectangle(self.plot, GRID_RGBA)
        self.yLabels[index] = label(self.root, TEXT_RGBA)
    end
    for index = 1, 2 do
        self.xLabels[index] = label(self.root, TEXT_RGBA,
            index == 1 and ui.AlignMode.TOPLEFT or ui.AlignMode.BOTTOMRIGHT)
    end
    -- Allocate once: even idle buckets and hoverable zero values need no new UI.
    for index = 1, model.capacity do
        self.bars[index] = rectangle(self.plot, self.barRGBA)
        self.bars[index].hidden = true
    end
    self.baseline = rectangle(self.plot, 0xBBA06DFF)
    self.highlight = rectangle(self.plot, 0xF2C66D33)
    self.highlight.hidden = true
    self.readout = label(self.root, TEXT_RGBA, ui.AlignMode.BOTTOMRIGHT)

    local function hover(_, x, y)
        if self.root == nil or self.plotWidth == nil or self.plotWidth <= 0 then return true end
        local slot = clamp(math.floor(x * self.visibleCount / self.plotWidth) + 1, 1, self.visibleCount)
        if self.hoverSlot ~= slot or self.hoverX ~= x or self.hoverY ~= y then
            self.hoverSlot, self.hoverX, self.hoverY = slot, x, y
            self:_RenderHover()
        end
        return true
    end
    self.plot:Subscribe(ui.Hook.ONMOUSEOVER, hover)
    self.plot:Subscribe(ui.Hook.ONMOUSEREPEAT, hover)
    self.plot:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        if self.root ~= nil then
            self.hoverSlot = nil
            self:_RenderHover()
        end
        return true
    end)

    self.listener = function(event)
        if self.root ~= nil and event.metric == model.metric then
            model:Push(event.value)
        end
    end
    bus.Update.Subscribe(self.listener)
    nextID = nextID + 1
    self.eventID = "prettyui_time_graph_" .. nextID
    instances[self] = true
    Event.Logic.Subscribe(self.eventID, function(event)
        if self.root == nil then return end
        model:Advance(event.logicTick)
        self:_Render()
    end)
    self:_Render()
    return self
end

function TimeGraph:_Layout(width, height)
    self.width, self.height = width, height
    local left = math.min(1, width)
    local top = math.min(38, height)
    self.plotWidth = math.max(0, width - left * 2)
    self.plotHeight = math.max(0, height - top - 1)
    local plotWidth, plotHeight = self.plotWidth, self.plotHeight
    place(self.background, 0, 0, width, height)
    place(self.border, 0, 0, width, height)
    local headerWidth = self.icon and 28 or math.floor(math.max(0, width - 24) * 0.35)
    place(self.header, 12, 5, headerWidth, 28)
    if self.icon then place(self.icon, 2, 2, 24, 24)
    else place(self.title, 0, 0, headerWidth, 28) end
    place(self.readout, 20 + headerWidth, 5, width - headerWidth - 32, 28)
    place(self.plot, left, top, plotWidth, plotHeight)
    place(self.plotBackground, 0, 0, plotWidth, plotHeight)
    local inset = math.min(4, math.floor(plotWidth / 4), math.floor(plotHeight / 4))
    local labelHeight = clamp(plotHeight - inset * 2, 0, 18)
    for index = 1, 2 do
        local y = (index - 1) * math.max(0, plotHeight - 1)
        place(self.grid[index], 0, y, plotWidth, math.min(1, plotHeight))
        local labelY = index == 1 and inset or math.max(inset, plotHeight - labelHeight * 2 - inset)
        place(self.yLabels[index], left + inset, top + labelY,
            math.min(80, plotWidth - inset * 2), labelHeight)
    end
    local labelWidth = math.floor(math.max(0, plotWidth - inset * 2) / 2)
    for index = 1, 2 do
        place(self.xLabels[index], left + inset + (index - 1) * labelWidth,
            top + plotHeight - labelHeight - inset, labelWidth, labelHeight)
    end
end

function TimeGraph:_RenderHover()
    local model = self.model
    local index = self.hoverSlot and self.hoverSlot + model.count - self.visibleCount
    local value, startSeconds, endSeconds
    if index and index >= 1 and index <= model.count then
        value, startSeconds, endSeconds = model:GetBucket(index)
    end
    self.highlight.hidden = value == nil or self.plotWidth <= 0 or self.plotHeight <= 0
    if not self.highlight.hidden then
        local left = math.floor((self.hoverSlot - 1) * self.plotWidth / self.visibleCount)
        local right = math.floor(self.hoverSlot * self.plotWidth / self.visibleCount)
        place(self.highlight, left, 0, right - left, self.plotHeight)
        if not self.bucketTooltip then
            self.bucketTooltip = Tooltip.attach(self.plot, self.root, "", {
                onMouseOver = function(tooltip)
                    if self.hoverSlot == nil then tooltip:Hide() end
                end,
                onMouseLeave = function(tooltip) tooltip:Hide() end,
            })
        end
        local tooltip = self.bucketTooltip
        local plotX, plotY = self.tooltipContext.position(self.plot)
        tooltip.options.x = plotX + (self.hoverX or left) + 12
        tooltip.options.y = plotY + (self.hoverY or 0) + 12
        local text = timestamp(startSeconds) .. " - " .. timestamp(endSeconds)
            .. "<br>" .. (value > 0 and "+" or "") .. string.format("%.14g", value) .. self.amountSuffix
        if self.bucketTooltipText ~= text then
            self.bucketTooltipText = text
            tooltip:SetText(text)
        end
        tooltip:Show()
    elseif self.bucketTooltip then
        self.bucketTooltip:Hide()
    end
end

function TimeGraph:_PulseLiveBar()
    local bar = self.bars[self.visibleCount]
    if bar.hidden then return end
    local phase = (self.model.elapsedTicks % PULSE_TICKS) / PULSE_TICKS
    bar.alpha = self.liveOpacity * (0.55 + 0.20 * math.cos(phase * math.pi * 2))
end

function TimeGraph:_Render()
    if self.root.hidden or self.root.visibleGlobal == false then return end
    local width, height = math.max(0, self.root.width), math.max(0, self.root.height)
    local geometryChanged = width ~= self.width or height ~= self.height
    if not geometryChanged and not self.dirty and self.renderedRevision == self.model.revision then
        self:_PulseLiveBar()
        return
    end
    if geometryChanged then self:_Layout(width, height) end
    self.dirty = false
    local model = self.model
    self.renderedRevision = model.revision

    local minimum, maximum, mean = 0, 0, 0
    for index = math.max(1, model.count - self.visibleCount + 1), model.count do
        local value = model:GetBucket(index)
        minimum = math.min(minimum, value)
        maximum = math.max(maximum, value)
        -- Average first so a finite window average cannot overflow its sum.
        mean = mean + value / self.visibleCount
    end
    -- Normalize before subtracting: opposite large finite values must not
    -- overflow the range and turn rectangle coordinates into NaN/infinity.
    local scale = math.max(-minimum, maximum)
    if scale == 0 then scale = 1 end
    local low = -math.ceil((-minimum / scale) * 4) / 4
    local high = math.ceil((maximum / scale) * 4) / 4
    if low == high then high = 1 end
    local span = high - low
    local plotHeight, plotWidth = self.plotHeight, self.plotWidth
    local drawableHeight = math.max(0, plotHeight - 1)
    local zeroY = math.floor(high / span * drawableHeight + 0.5)
    place(self.baseline, 0, zeroY, plotWidth, math.min(1, plotHeight))
    for index = 1, 2 do
        local normalized = index == 1 and high or low
        setText(self.yLabels[index], compact(normalized * scale))
    end

    local empty = self.visibleCount - model.count
    for slot = 1, self.visibleCount do
        local bar = self.bars[slot]
        local index = slot - empty
        local value = index >= 1 and model:GetBucket(index) or 0
        local left = math.floor((slot - 1) * plotWidth / self.visibleCount)
        local right = math.floor(slot * plotWidth / self.visibleCount)
        local valueY = math.floor((high - value / scale) / span * drawableHeight + 0.5)
        local barHeight = math.abs(zeroY - valueY)
        bar.hidden = index < 1 or value == 0 or right <= left or barHeight == 0
        if not bar.hidden then
            local gap = clamp(right - left - 1, 0, BAR_GAP)
            place(bar, left + math.floor(gap / 2), math.min(zeroY, valueY), right - left - gap, barHeight)
            local rgba = value < 0 and NEGATIVE_RGBA or self.barRGBA
            bar.rgba = rgba
            local opacity = (rgba % 256) / 255
            bar.alpha = opacity * BAR_ALPHA
            if slot == self.visibleCount then self.liveOpacity = opacity end
        end
    end
    for slot = self.visibleCount + 1, model.capacity do self.bars[slot].hidden = true end
    local _, _, currentEnd = model:GetBucket(model.count)
    -- Labels describe session time at plot boundaries; before-origin positions
    -- stay blank while the initial history grows from the right-hand edge.
    for index = 1, 2 do
        local seconds = currentEnd - (2 - index) * self.visibleCount * model.interval
        setText(self.xLabels[index], timestamp(seconds))
    end
    local windowSeconds = self.visibleCount * model.interval
    local rateSeconds, rateUnit = 1, "/s"
    if windowSeconds >= 3600 then rateSeconds, rateUnit = 3600, "/h"
    elseif windowSeconds >= 60 then rateSeconds, rateUnit = 60, "/min" end
    setText(self.readout, compact(mean / model.interval * rateSeconds) .. self.amountSuffix .. rateUnit)
    self:_PulseLiveBar()
    self:_UpdateTooltip()
    self:_RenderHover()
end

function TimeGraph:_UpdateTooltip()
    local text = self.label .. "<br>Total: " .. compact(self.model.total)
        .. self.amountSuffix
    if self.tooltipText ~= text then
        self.tooltipText = text
        Tooltip.set(self, text)
    end
end

-- Zoom selects the newest buckets, without changing interval, history or total.
function TimeGraph:SetZoom(zoom, notify)
    if self.root == nil then return false end
    local count = visibleBuckets(self.model.capacity, zoom)
    if count == self.visibleCount then return false end
    self.visibleCount = count
    self.hoverSlot = nil
    self.dirty = true
    self:_Render()
    if notify ~= false and self.onZoom then self.onZoom(self, self:GetZoom()) end
    return true
end

function TimeGraph:GetZoom()
    return self.model.capacity / self.visibleCount
end

function TimeGraph:ZoomIn()
    return self:SetZoom(self:GetZoom() * 2)
end

function TimeGraph:ZoomOut()
    return self:SetZoom(self:GetZoom() / 2)
end

-- Snapshots are detached from the live history, including after destruction.
function TimeGraph:GetSnapshot()
    return self.model:GetSnapshot()
end

function TimeGraph:Reset()
    if self.root == nil then return false end
    self.model:Reset()
    self.hoverSlot = nil
    self.dirty = true
    self:_Render()
    return true
end

function TimeGraph:SetVisible(visible)
    if self.root == nil then return false end
    self.root.hidden = visible ~= true
    if self.root.hidden then Tooltip.hideContextTooltips(self.root) end
    self.hoverSlot = nil
    self.dirty = true
    self:_Render()
    return true
end

-- Width/height remain offsets against the constructor's size anchors.
function TimeGraph:SetSize(width, height)
    if self.root == nil then return false end
    width, height = dimension(width, DEFAULT_WIDTH), dimension(height, DEFAULT_HEIGHT)
    self.root:SetSize(width, height, self.widthAnchor, self.heightAnchor)
    self.dirty = true
    self:_Render()
    return true
end

function TimeGraph:Destroy()
    if self.root == nil then return end
    Event.Logic.Unsubscribe(self.eventID)
    self.bus.Update.Unsubscribe(self.listener)
    Tooltip.unbind(self)
    Tooltip.unregisterContext(self.root)
    instances[self] = nil
    if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.root:Destroy() end
    self.root = nil
    self.listener = nil
    self.hoverSlot = nil
    self.bars, self.grid, self.yLabels, self.xLabels = nil, nil, nil, nil
    self.background, self.border, self.header, self.title, self.icon = nil, nil, nil, nil, nil
    self.plot, self.plotBackground, self.baseline, self.highlight, self.readout = nil, nil, nil, nil, nil
    self.bucketTooltip, self.tooltipContext = nil, nil
end

function TimeGraph.Shutdown()
    while next(instances) ~= nil do
        local graph = next(instances)
        graph:Destroy()
    end
end

return TimeGraph
