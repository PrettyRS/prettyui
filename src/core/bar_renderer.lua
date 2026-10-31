local Components = require("src/core/components")
local Data = require("src/core/chart_data")
local Tooltip = require("src/tooltip")
local Wheel = require("src/core/wheel")
local clamp = require("src/core/math").clamp

local Renderer = {}
local DEFAULT_WIDTH, DEFAULT_HEIGHT = 480, 260
local TEXT_RGBA, GOLD_RGBA = 0xE7D7B0FF, 0xF2C66DFF
local BAR_RGBA = 0xC49946FF
local instances = {}
local nextID = 0
local HOVER_HOOK = "prettyui_chart_hover"

local function dimension(value, fallback)
    if value == nil then return fallback end
    assert(Data.finite(value), "chart dimensions must be finite numbers")
    return math.floor(value)
end

local function rectangle(parent, rgba)
    local component = Components.new(ui.Rectangle, parent)
    component.fill = true
    component.rgba = rgba
    component.clickthrough = true
    return component
end

local function label(parent, alignment)
    local component = Components.new(ui.Text, parent)
    component.font = id.Font.MUSEO_SANS_15PT_REGULAR
    component.rgba = TEXT_RGBA
    component.isShadowed = true
    component.alignHorizontal = alignment or ui.AlignMode.TOPLEFT
    component.alignVertical = ui.AlignMode.CENTRE
    component.maxLines = 1
    component.clickthrough = true
    return component
end

local function place(component, x, y, width, height)
    component:SetPos(math.floor(x), math.floor(y))
    component:SetSize(math.max(0, math.floor(width)), math.max(0, math.floor(height)))
end

local function setText(component, text)
    if component.content ~= text then component.content = text end
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

local function nativeText(text)
    return (text:gsub("\r\n", "<br>"):gsub("[\r\n]", "<br>"))
end

-- Subtract normally for narrow, large-magnitude ranges; normalize first only
-- when opposite finite endpoints overflow their difference.
local function fraction(value, lower, upper)
    local span = upper - lower
    if span < math.huge then return (value - lower) / span end
    local scale = math.max(math.abs(lower), math.abs(upper))
    return (value / scale - lower / scale) / (upper / scale - lower / scale)
end

function Renderer.getSize(options)
    options = options or {}
    return dimension(options.width, DEFAULT_WIDTH), dimension(options.height, DEFAULT_HEIGHT)
end

function Renderer.init(self, parent, options)
    local width, height = Renderer.getSize(options)
    assert(options.label == nil or type(options.label) == "string", "chart label must be a string")
    Data.colour(options.rgba)
    for _, key in ipairs({ "x", "y", "xAnchor", "yAnchor", "widthAnchor", "heightAnchor" }) do
        assert(options[key] == nil or Data.finite(options[key]), "chart positions and anchors must be finite numbers")
    end
    assert(options._onScrollWheel == nil or type(options._onScrollWheel) == "function",
        "chart scroll handler must be a function")
    self.label = options.label or ""
    self.barRGBA = options.rgba
    self.widthAnchor, self.heightAnchor = options.widthAnchor or 0, options.heightAnchor or 0
    self.bars, self.edges = {}, {}
    self.dirty = true
    self.root = Components.new(ui.Layer, parent)
    self.interfaceID = self.root.interfaceID
    self.root:SetPos(options.x or 0, options.y or 0, options.xAnchor or 0, options.yAnchor or 0)
    self.root:SetSize(width, height, self.widthAnchor, self.heightAnchor)
    self.root.hidden = options.visible == false
    self.root.clickthrough = false
    Wheel.bind(self.root, options)
    self.background = rectangle(self.root, 0x2E2825FF)
    self.border = rectangle(self.root, 0x766341FF)
    self.border.fill = false
    self.border.outlineThickness = 1
    self.title = label(self.root)
    self.title.font = id.Font.CINZEL_13PT_BOLD
    self.title.rgba = GOLD_RGBA
    self.title.content = nativeText(self.label)
    self.body = Components.new(ui.Layer, self.root)
    self.body.clickthrough = false
    Wheel.bind(self.body, options)
    self.plot = Components.new(ui.Layer, self.body)
    self.plot.clickthrough = false
    Wheel.bind(self.plot, options)
    self.plotBackground = rectangle(self.plot, 0x24211EFF)
    self.grid = { rectangle(self.plot, 0x74634455), rectangle(self.plot, 0x74634455) }
    self.baseline = rectangle(self.plot, 0xBBA06DFF)
    -- A sibling overlay stays above dynamically created bars in the plot layer.
    self.highlight = rectangle(self.body, 0xF2C66D33)
    self.highlight.hidden = true
    self.axisLabels = { label(self.body),
        label(self.body, self.orientation == "horizontal" and ui.AlignMode.BOTTOMRIGHT or ui.AlignMode.TOPLEFT) }
    if self.kind == "histogram" then
        self.rangeLabels = { label(self.body), label(self.body, ui.AlignMode.BOTTOMRIGHT) }
    end
    self.empty = label(self.plot, ui.AlignMode.CENTRE)
    self.empty.content = self.kind == "histogram" and "No samples" or "No data"
    local parentContext = Tooltip.getContext(parent)
    self.tooltipContext = Tooltip.registerContext(self.root, parentContext and parentContext.parent or parent, function(target)
        local x, y
        if parentContext then x, y = parentContext.position(self.root)
        else x, y = self.root.x, self.root.y end
        return x + target.x, y + target.y
    end, parentContext)
    local function hover(_, x, y)
        if self.root == nil then return true end
        self.hoverX, self.hoverY = x, y
        self:_RenderHover()
        return true
    end
    self.plot:Subscribe(ui.Hook.ONMOUSEOVER, HOVER_HOOK, hover)
    self.plot:Subscribe(ui.Hook.ONMOUSEREPEAT, HOVER_HOOK, hover)
    self.plot:Subscribe(ui.Hook.ONMOUSELEAVE, HOVER_HOOK, function()
        self:_ClearHover()
        return true
    end)
    nextID = nextID + 1
    self.eventID = "prettyui_bar_renderer_" .. nextID
    instances[self] = true
    -- Observe native anchor/flow resizes and ancestor visibility only. No time
    -- source, aggregation, or data mutation occurs in the logic subscription.
    Event.Logic.Subscribe(self.eventID, function()
        if self.root ~= nil then self:_Render() end
    end)
    self:_Render()
    return self
end

function Renderer:_ClearHover()
    self.hoverX, self.hoverY = nil, nil
    if self.highlight and ui.Interfaces:GetInterface(self.interfaceID) ~= nil then
        self.highlight.hidden = true
    end
    if self.tooltip then self.tooltip:Hide() end
end

function Renderer:_Layout(width, height)
    self.width, self.height = width, height
    self:_ClearHover()
    local left = math.min(1, width)
    local top = math.min(38, height)
    local bodyHeight = math.max(0, height - top)
    local horizontal = self.orientation == "horizontal"
    self.plotX, self.plotY = left, 0
    self.plotWidth = math.max(0, width - left * 2)
    self.plotHeight = math.max(0, bodyHeight - 1)
    local pw, ph = self.plotWidth, self.plotHeight
    place(self.background, 0, 0, width, height)
    place(self.border, 0, 0, width, height)
    local titleInset = math.min(12, math.floor(width / 8))
    place(self.title, titleInset, 0, width - titleInset * 2, top)
    place(self.body, 0, top, width, bodyHeight)
    place(self.plot, left, 0, pw, ph)
    place(self.plotBackground, 0, 0, pw, ph)
    place(self.empty, 0, 0, pw, ph)
    local inset = math.min(4, math.floor(pw / 4), math.floor(ph / 4))
    local textHeight = clamp(ph - inset * 2, 0, 18)
    local half = math.floor(math.max(0, pw - inset * 2) / 2)
    local bottom = math.max(inset, ph - textHeight - inset)
    if horizontal then
        place(self.axisLabels[1], left + inset, bottom, half, textHeight)
        place(self.axisLabels[2], left + inset + half, bottom, half, textHeight)
    else
        local labelWidth = clamp(pw - inset * 2, 0, 80)
        local lowY = self.rangeLabels and math.max(inset, bottom - textHeight) or bottom
        place(self.axisLabels[1], left + inset, inset, labelWidth, textHeight)
        place(self.axisLabels[2], left + inset, lowY, labelWidth, textHeight)
    end
    if self.rangeLabels then
        place(self.rangeLabels[1], left + inset, bottom, half, textHeight)
        place(self.rangeLabels[2], left + inset + half, bottom, half, textHeight)
    end
end

function Renderer:_RenderHover()
    if self.root == nil then return end
    local x, y = self.hoverX, self.hoverY
    local pw, ph = self.plotWidth or 0, self.plotHeight or 0
    if self.root.hidden or self.root.visibleGlobal == false or x == nil or pw <= 0 or ph <= 0 then
        self:_ClearHover()
        return
    end
    local horizontal = self.orientation == "horizontal"
    local position = horizontal and y or x
    local slot
    if x >= 0 and x < pw and y >= 0 and y < ph then
        -- Pixel edges are shared with rendering, so variable-width histogram
        -- boundaries (including exact edges and zero bins) select the right bin.
        local first, last = 1, #self.rows
        while first <= last do
            local index = math.floor((first + last) / 2)
            if position < self.edges[index] then
                last = index - 1
            elseif position >= self.edges[index + 1] then
                first = index + 1
            else
                slot = index
                break
            end
        end
    end
    local row = slot and self.rows[slot]
    self.highlight.hidden = row == nil
    if row == nil then
        if self.tooltip then self.tooltip:Hide() end
        return
    end
    local start, finish = self.edges[slot], self.edges[slot + 1]
    if horizontal then place(self.highlight, self.plotX, self.plotY + start, pw, finish - start)
    else place(self.highlight, self.plotX + start, self.plotY, finish - start, ph) end
    if not self.tooltip then
        self.tooltip = Tooltip.attach(self.plot, self.root, "", {
            onMouseOver = function() self:_RenderHover() end,
            onMouseLeave = function() self:_ClearHover() end,
        })
    end
    local text
    if self.kind == "histogram" then
        text = "[" .. string.format("%.14g", row.lower) .. ", " .. string.format("%.14g", row.upper)
            .. ")<br>Count: " .. string.format("%.0f", row.count)
    else
        text = nativeText(row.label) .. "<br>" .. string.format("%.14g", row.value)
    end
    if self.tooltipText ~= text then
        self.tooltipText = text
        self.tooltip:SetText(text)
    end
    local bodyX, bodyY = self.tooltipContext.position(self.body)
    self.tooltip.options.x = bodyX + self.plotX + x + 12
    self.tooltip.options.y = bodyY + self.plotY + y + 12
    self.tooltip:Show()
end

function Renderer:_Render()
    if self.root.hidden or self.root.visibleGlobal == false then
        self:_ClearHover()
        return
    end
    local width, height = math.max(0, self.root.width), math.max(0, self.root.height)
    if self.width ~= width or self.height ~= height then self:_Layout(width, height)
    elseif not self.dirty then return end
    self.dirty = false
    local rows, count = self.rows, #self.rows
    local histogram = self.kind == "histogram"
    local horizontal = self.orientation == "horizontal"
    local minimum, maximum = 0, 0
    for _, row in ipairs(rows) do
        local value = histogram and row.count or row.value
        minimum, maximum = math.min(minimum, value), math.max(maximum, value)
    end
    local scale = math.max(-minimum, maximum)
    if scale == 0 then scale = 1 end
    local low, high = minimum / scale, maximum / scale
    if low == high then high = 1 end
    local span = high - low
    local pw, ph = self.plotWidth, self.plotHeight
    local valueExtent = math.max(0, (horizontal and pw or ph) - 1)
    local function coordinate(value)
        local unit = (value / scale - low) / span
        return math.floor((horizontal and unit or 1 - unit) * valueExtent + 0.5)
    end
    local zero = coordinate(0)
    if horizontal then place(self.baseline, zero, 0, math.min(1, pw), ph)
    else place(self.baseline, 0, zero, pw, math.min(1, ph)) end
    for index = 1, 2 do
        local edge = (index - 1) * valueExtent
        if horizontal then place(self.grid[index], edge, 0, math.min(1, pw), ph)
        else place(self.grid[index], 0, edge, pw, math.min(1, ph)) end
        local value = ((horizontal and index == 1) or (not horizontal and index == 2)) and minimum or maximum
        setText(self.axisLabels[index], compact(value))
        self.axisLabels[index].hidden = count == 0
        if self.rangeLabels then self.rangeLabels[index].hidden = count == 0 end
    end
    if histogram and count > 0 then
        setText(self.rangeLabels[1], compact(rows[1].lower))
        setText(self.rangeLabels[2], compact(rows[count].upper))
    end
    self.empty.hidden = count > 0 and (not histogram or self.sampleCount > 0)
    local categoryExtent = horizontal and ph or pw
    for index = 1, count + 1 do
        local unit
        if histogram and count > 0 then
            local boundary = index <= count and rows[index].lower or rows[count].upper
            unit = fraction(boundary, rows[1].lower, rows[count].upper)
        else
            unit = count > 0 and (index - 1) / count or 0
        end
        self.edges[index] = math.floor(unit * categoryExtent + 0.5)
    end
    for index, row in ipairs(rows) do
        local bar = self.bars[index]
        if not bar then
            bar = rectangle(self.plot, BAR_RGBA)
            self.bars[index] = bar
        end
        local start, finish = self.edges[index], self.edges[index + 1]
        local value = histogram and row.count or row.value
        local endpoint = coordinate(value)
        local gap = histogram and 0 or clamp(finish - start - 1, 0, 4)
        bar.hidden = value == 0 or finish <= start or endpoint == zero or pw == 0 or ph == 0
        if not bar.hidden then
            if horizontal then
                place(bar, math.min(zero, endpoint), start + math.floor(gap / 2), math.abs(endpoint - zero), finish - start - gap)
            else
                place(bar, start + math.floor(gap / 2), math.min(zero, endpoint), finish - start - gap, math.abs(endpoint - zero))
            end
            bar.rgba = row.rgba or self.barRGBA or BAR_RGBA
        end
    end
    for index = count + 1, #self.bars do
        self.bars[index].hidden = true
    end
    self.baseline:MoveToFront()
    self.empty:MoveToFront()
    self:_RenderHover()
end

function Renderer:_DataChanged()
    self:_ClearHover()
    self.dirty = true
    self:_Render()
end

function Renderer:SetVisible(visible)
    if self.root == nil then return false end
    self.root.hidden = visible ~= true
    self:_ClearHover()
    self.dirty = true
    self:_Render()
    return true
end

-- Dimensions remain offsets against the constructor's size anchors.
function Renderer:SetSize(width, height)
    if self.root == nil then return false end
    width, height = Renderer.getSize({ width = width, height = height })
    self.root:SetSize(width, height, self.widthAnchor, self.heightAnchor)
    self:_ClearHover()
    self.dirty = true
    self:_Render()
    return true
end

function Renderer:Destroy()
    if self.root == nil then return end
    Event.Logic.Unsubscribe(self.eventID)
    self:_ClearHover()
    Tooltip.unregisterContext(self.root)
    local loaded = ui.Interfaces:GetInterface(self.interfaceID) ~= nil
    if self.plot and loaded then
        self.plot:Unsubscribe(ui.Hook.ONMOUSEOVER, HOVER_HOOK)
        self.plot:Unsubscribe(ui.Hook.ONMOUSEREPEAT, HOVER_HOOK)
        self.plot:Unsubscribe(ui.Hook.ONMOUSELEAVE, HOVER_HOOK)
    end
    instances[self] = nil
    if loaded then self.root:Destroy() end
    self.root, self.body, self.plot = nil, nil, nil
    self.background, self.border, self.title, self.plotBackground = nil, nil, nil, nil
    self.grid, self.baseline, self.highlight, self.empty = nil, nil, nil, nil
    self.bars, self.edges, self.axisLabels, self.rangeLabels = nil, nil, nil, nil
    self.tooltip, self.tooltipContext = nil, nil
end

function Renderer.shutdown(kind)
    -- Destroy may be decorated by Layout.manage; always call the instance method.
    for instance in pairs(instances) do
        if instance.kind == kind then instance:Destroy() end
    end
end

return Renderer
