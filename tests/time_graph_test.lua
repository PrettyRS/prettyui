local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    assert(actual == expected, message .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end

local methods = {}
function methods:SetPos(x, y, xa, ya) self.x, self.y, self.xa, self.ya = x, y, xa or 0, ya or 0 end
function methods:SetSize(w, h, wa, ha) self.w, self.h, self.wa, self.ha = w, h, wa or 0, ha or 0 end
function methods:Subscribe(hook, name, callback)
    if callback == nil then callback, name = name, 'default' end
    self.hooks[hook] = self.hooks[hook] or {}
    self.hooks[hook][name] = callback
end
function methods:Unsubscribe(hook, name) self.hooks[hook][name] = nil end
function methods:Emit(hook, ...)
    for _, callback in pairs(self.hooks[hook] or {}) do
        if callback(self, ...) == false then return false end
    end
    return true
end
function methods:Destroy() self.destroyed = true end
function methods:MoveToFront() end
local function factory(kind)
    return {new = function(parent)
        local component = {parent = parent, kind = kind, children = {}, hooks = {}, x = 0, y = 0, w = 0, h = 0, wa = 0, ha = 0}
        if parent then table.insert(parent.children, component) end
        return Interfaces.component(setmetatable(component, {__index = function(self, key)
            if key == 'width' then return self.w + (self.parent and self.parent.width or 0) * self.wa end
            if key == 'height' then return self.h + (self.parent and self.parent.height or 0) * self.ha end
            return methods[key]
        end}), parent)
    end}
end
ui = {
    Hook = {ONMOUSEOVER = 1, ONMOUSEREPEAT = 2, ONMOUSELEAVE = 3, ONSCROLLWHEEL = 4},
    AlignMode = {TOPLEFT = 0, CENTRE = 1, BOTTOMRIGHT = 2},
}
for _, kind in ipairs({'Layer', 'Rectangle', 'Text', 'Sprite'}) do ui[kind] = factory(kind) end
id = {Font = {MUSEO_SANS_15PT_REGULAR = 1, CINZEL_13PT_BOLD = 2}}
config = {Font = {MUSEO_SANS_15PT_REGULAR = {
    baseline = 16,
    GetStringWidth = function(_, text) return #text * 7 end,
    GetStringHeightAndLineCount = function() return 96 end,
}}}
package.loaded['src/core/sprites'] = {CONTENT_FRAME = {}, HUD_WINDOW = {}}
local callbacks = {}
Event = {Logic = {
    Subscribe = function(key, callback) callbacks[key] = callback end,
    Unsubscribe = function(key) callbacks[key] = nil end,
    Emit = function(tick) for _, callback in pairs(callbacks) do callback({logicTick = tick}) end end,
}}
local TimeGraph = require('src/time_graph')
local root = ui.Layer.new(); root:SetSize(800, 700)
local forwarded, notices = 0, 0
local graph = TimeGraph.new(root, {
    metric = {id = 'gold', label = 'gp', spriteID = 197}, interval = 1, capacity = 8,
    x = 40, y = 30,
    onZoom = function() notices = notices + 1 end,
    _onScrollWheel = function() forwarded = forwarded + 1; return false end,
})
Event.Logic.Emit(100)
for index, value in ipairs({1000, 20, 30, 40, 5, 0, -10, 15}) do
    Event.Logic.Emit(100 + (index - 1) * 50)
    graph.bus.Update.Publish({metric = 'gold', value = value})
end
Event.Logic.Emit(451)
local completedAlpha, liveAlpha = graph.bars[1].alpha, graph.bars[8].alpha
Event.Logic.Emit(465)
assert(graph.bars[8].alpha ~= liveAlpha, 'live bar pulses without new samples or layout changes')
expect(graph.bars[1].alpha, completedAlpha, 'completed bars do not pulse')
assert(completedAlpha > 0 and completedAlpha < 1, 'completed bars remain translucent')
local before = graph:GetSnapshot()
expect(graph.readout.content, '137.5 gp/s', 'header averages signed deltas over the full visible span')
expect(graph.plot:Emit(ui.Hook.ONSCROLLWHEEL, -1), false, 'plot consumes zoom wheel')
expect(graph:GetZoom(), 2, 'wheel zooms into recent history')
expect(forwarded, 0, 'zoom does not also scroll the host')
expect(notices, 1, 'wheel notifies one zoom change')
expect(graph.yLabels[1].content, '15', 'zoom excludes old outlier from autoscaling')
expect(graph.readout.content, '2.5 gp/s', 'zoomed rate excludes outliers outside the view')
assert(graph.bars[3].y >= graph.baseline.y and graph.bars[4].y < graph.baseline.y,
    'zoom keeps signed bars on their side of zero')
local headerValue = graph.readout.content
graph.plot:Emit(ui.Hook.ONMOUSEOVER, graph.plotWidth * 1.5 / 4, 40)
assert(not graph.bucketTooltip.root.hidden, 'hover opens a bucket tooltip')
assert(not graph.bucketTooltip.label.content:find("[%z\1-\31]"), 'bucket tooltip has no unsupported control characters')
assert(graph.bucketTooltip.label.content:find('0:05 - 0:06', 1, true), 'zoom hover resolves retained bucket time')
assert(graph.bucketTooltip.label.content:find('0 gp', 1, true), 'zero-value zoomed bucket remains hoverable')
expect(graph.readout.content, headerValue, 'bucket hover does not replace the window rate')
local tooltipX = graph.bucketTooltip.root.x
graph.plot:Emit(ui.Hook.ONMOUSEREPEAT, graph.plotWidth * 1.5 / 4 + 4, 40)
assert(graph.bucketTooltip.root.x ~= tooltipX, 'tooltip follows pointer movement within a bucket')
graph:SetZoom(1000)
expect(graph.bucketTooltip.root.hidden, true, 'zoom hides stale bucket tooltip')
expect(graph:GetZoom(), 4, 'zoom stops at two buckets')
expect(graph:ZoomIn(), false, 'zoom limit is stable')
graph:SetZoom(0.1)
expect(graph:GetZoom(), 1, 'zoom out clamps to full retained history')
local after = graph:GetSnapshot()
expect(after.total, before.total, 'zoom leaves session total untouched')
expect(after.interval, before.interval, 'zoom does not change sampling interval')
for index, bucket in ipairs(before.buckets) do
    expect(after.buckets[index].value, bucket.value, 'zoom preserves collected samples')
    expect(after.buckets[index].startSeconds, bucket.startSeconds, 'zoom preserves timestamps')
end
for _, zoom in ipairs({0, -1, math.huge, 0 / 0, '2'}) do
    expect(pcall(graph.SetZoom, graph, zoom), false, 'invalid zoom rejected')
end
graph:SetZoom(2, false)
graph.bus.Update.Publish({metric = 'gold', value = 10})
Event.Logic.Emit(500)
expect(graph:GetSnapshot().total, before.total + 10, 'zoomed view continues collecting')
expect(graph.xLabels[2].content, '0:09', 'zoomed time window follows live bucket')
expect(graph.bars[3].alpha, completedAlpha, 'previous live bucket stops pulsing when completed')
graph.bus.Update.Publish({metric = 'gold', value = 12.5})
Event.Logic.Emit(501)
graph.plot:Emit(ui.Hook.ONMOUSEOVER, graph.plotWidth - 2, 40)
assert(graph.bucketTooltip.label.content:find('+12.5 gp', 1, true), 'positive bucket amount is explicitly signed')
graph.bus.Update.Publish({metric = 'gold', value = 2.25})
Event.Logic.Emit(502)
assert(graph.bucketTooltip.label.content:find('14.75 gp', 1, true), 'stationary hover receives live updates')
graph.plot:Emit(ui.Hook.ONMOUSELEAVE)
expect(graph.bucketTooltip.root.hidden, true, 'leaving plot hides bucket tooltip')
graph.header:Emit(ui.Hook.ONMOUSEOVER)
assert(not graph.tooltip.root.hidden, 'icon exposes its label and totals on hover')
assert(not graph.tooltip.label.content:find("[%z\1-\31]"), 'header tooltip has no unsupported control characters')
assert(graph.tooltip.root.x >= graph.root.x + graph.header.x, 'header tooltip includes graph position')
graph:SetVisible(false)
expect(graph.tooltip.root.hidden, true, 'hiding graph also hides its tooltip')
expect(graph.bucketTooltip.root.hidden, true, 'hiding graph also hides bucket tooltip')
graph:SetVisible(true)
graph.root:Emit(ui.Hook.ONSCROLLWHEEL, 1)
expect(forwarded, 1, 'header and margins retain host scrolling')
local unzoomable = TimeGraph.new(root, {metric = {id = 'xp'}, zoomable = false,
    _onScrollWheel = function() forwarded = forwarded + 1; return false end})
unzoomable.plot:Emit(ui.Hook.ONSCROLLWHEEL, -1)
expect(unzoomable:GetZoom(), 1, 'disabled wheel zoom retains history window')
expect(forwarded, 2, 'disabled zoom forwards plot wheel to host')

-- A panel renders two concrete graphs; wheel interaction must survive popout.
for _, name in ipairs({'colour_picker', 'combo_box', 'list', 'slider', 'text_field', 'tabs', 'core/cursor', 'core/mouse'}) do
    package.loaded['src/' .. name] = {}
end
package.loaded['src/core/scroll'] = {install = function() end}
local Panel = require('src/panel')
local panel = setmetatable({dock = {content = root}, overlay = {content = root},
    dockOwner = {content = root, contentHeight = 700, contentWidth = 800},
    overlayOwner = {content = root, contentHeight = 700, contentWidth = 800}}, Panel)
local panelNotices = 0
local paired = panel:AddTimeGraph({metric = {id = 'xp'}, capacity = 8, onZoom = function(handle)
    assert(handle.dock and handle.overlay, 'paired callback exposes panel proxy')
    panelNotices = panelNotices + 1
end})
paired.dock.plot:Emit(ui.Hook.ONSCROLLWHEEL, -1)
panel.poppedOut = true
expect(paired:GetZoom(), 2, 'popout keeps wheel-selected zoom')
expect(panelNotices, 1, 'paired wheel change emits once')
expect(paired:ZoomIn(), true, 'paired programmatic zoom reports a change')
expect(panelNotices, 2, 'paired programmatic zoom emits once')
expect(paired.dock:GetZoom(), paired.overlay:GetZoom(), 'both surfaces stay synchronized')

-- Time-unit boundaries, startup gaps, window eviction, and idle/reset rates.
local rateGraph = TimeGraph.new(root, {metric = {id = 'xp', label = 'XP'}, interval = 30, capacity = 120})
Event.Logic.Emit(10000)
for index, value in ipairs({120, 30, -60, 30}) do
    Event.Logic.Emit(10000 + (index - 1) * 1500)
    rateGraph.bus.Update.Publish({metric = 'xp', value = value})
end
Event.Logic.Emit(14501)
expect(rateGraph.readout.content, '120 XP/h', 'hour-wide view includes the empty startup span')
rateGraph:SetZoom(30)
expect(rateGraph.readout.content, '60 XP/min', 'two-minute view normalizes visible gains per minute')
rateGraph:SetZoom(60)
expect(rateGraph.readout.content, '-30 XP/min', 'one-minute view reports net loss after zoom excludes old gains')
rateGraph.plot:Emit(ui.Hook.ONMOUSEOVER, rateGraph.plotWidth / 4, 40)
assert(rateGraph.bucketTooltip.label.content:find('-60 XP', 1, true), 'negative bucket amount retains its loss sign')
expect(rateGraph:GetSnapshot().total, 120, 'window rate never changes the session total')
Event.Logic.Emit(16000)
expect(rateGraph.readout.content, '30 XP/min', 'rate drops the expired negative bucket')
Event.Logic.Emit(19000)
expect(rateGraph.readout.content, '0 XP/min', 'idle intervals replace all visible gains')
rateGraph.bus.Update.Publish({metric = 'xp', value = 60})
Event.Logic.Emit(19001)
expect(rateGraph.readout.content, '60 XP/min', 'fresh gain updates the live window rate')
rateGraph:Reset()
expect(rateGraph.readout.content, '0 XP/min', 'reset clears rate and preserves zoom time units')
local bucketSurface = graph.bucketTooltip.root
TimeGraph.Shutdown()
expect(bucketSurface.destroyed, true, 'shutdown removes bucket tooltip surface')
expect(next(callbacks), nil, 'shutdown removes all graph timers')
expect(graph:SetZoom(2), false, 'destroyed graph rejects zoom')
print('time_graph_test: zoom history, scaling, hover, wheel ownership, tooltip lifetime and panel continuity passed')
