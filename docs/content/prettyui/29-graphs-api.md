---
title: "Graphs"
weight: 29
---

{{% doc-section %}}

## Graphs {#graphs}

Graphs display data supplied by your plugin. They can be hosted in a windows, simple views, tab pages, or panels.

### Time graph {#time-graph-api}

Rolling interval totals mimicking the runemetrics graphs.

```lua
local bus = prettyui.TimeGraph.CreateEventBus()
local graph = window:AddTimeGraph({
    metric = { id = "xp", label = "XP", rgba = 0x69B7FFFF },
    interval = 5,
    capacity = 60,
    bus = bus,
})

bus.Update.Publish({ metric = "xp", value = 125 })
bus.Update.Publish({ metric = "xp", value = 75 })
```

{{% api-grid compact="true" %}}
{{% api-card %}}

#### Options

`metric`
: Descriptor with a nonempty string **id**, optional **label** (defaults to id),
  **spriteID** (icon instead of title), and **rgba** (positive bar colour).

`interval`, `capacity`
: Seconds per bucket (5) and retained bucket count (60), including the live bucket.

`zoom`, `zoomable`, `onZoom`
: Initial magnification (1), wheel zoom (true), and **function(graph, zoom)**.

`bus`
: Shared update bus. Defaults to a new bus available as **graph.bus**.

{{% /api-card %}}
{{% api-card %}}

#### Updates and controls

`bus.Update.Publish({ metric, value })`
: Adds a signed delta to the current bucket. Returns **true** or **false, error**.
  **Subscribe(callback)** and **Unsubscribe(callback)** also use dot syntax.

`SetZoom(zoom, notify?)`, `GetZoom()`, `ZoomIn()`, `ZoomOut()`
: Changes magnification. Pass **false** to **SetZoom** to suppress **onZoom**.

`GetSnapshot()`
: Returns **{ metric, interval, capacity, total, elapsedSeconds, buckets }**.
  Metric is the ID; chronological buckets contain
  **{ value, startSeconds, endSeconds, complete }**. The last bucket is live.

{{% /api-card %}}
{{% /api-grid %}}

### Bar chart {#bar-chart-api}

Compare categories in caller order.

```lua
local chart = window:AddBarChart({
    label = "XP by skill",
    data = {
        { id = "attack", label = "Attack", value = 250 },
        { id = "construction", label = "Construction", value = 175 },
    },
})

chart:SetData({
    { id = "attack", label = "Attack", value = 375 },
    { id = "construction", label = "Construction", value = 250 },
})
```

{{% api-grid compact="true" %}}
{{% api-card %}}

#### Options

`label`, `data`
: Heading and **{ id, label, value, rgba? }** rows.
  Row colour overrides chart colour.

`orientation`, `rgba`
: **"horizontal"** (default) or **"vertical"**. Chart colour overrides source colours.

{{% /api-card %}}
{{% api-card %}}

#### Methods

`SetData(rows)`
: Replaces category data.

`GetSnapshot()`
: Returns **{ label, data }**, including resolved row colours.

{{% /api-card %}}
{{% /api-grid %}}

### Histogram {#histogram-api}

Group numeric samples into contiguous bins.

```lua
local histogram = window:AddHistogram({
    label = "Duration (seconds)",
    binWidth = 5,
    samples = { 73.2, 74.4, 75.6, 81 },
})

histogram:SetSamples({ 73.2, 74.4, 75.6, 78.6, 81 })

-- Or send pre-binned counts.
histogram:SetBins({
    { lower = 70, upper = 75, count = 2 },
    { lower = 75, upper = 80, count = 2 },
    { lower = 80, upper = 85, count = 1 },
})
```

{{% api-grid compact="true" %}}
{{% api-card %}}

#### Options

`label`, `rgba`
: Heading and bar colour.

`samples`, `binWidth`, `origin`
: Sample values, bin width (5), and alignment origin (0). Bins use **[lower, upper)**.

{{% /api-card %}}
{{% api-card %}}

#### Methods

`SetSamples(samples)`
: Replaces samples and rebuilds bins.

`SetBins(bins)`
: Replaces the distribution with contiguous **{ lower, upper, count }** bins.

`GetSnapshot()`
: Returns **{ label, binWidth, origin, sampleCount, bins }**.

{{% /api-card %}}
{{% /api-grid %}}

### Shared API

Standalone constructors use **prettyui.TimeGraph.new(parent, options)**,
**prettyui.BarChart.new(parent, options)**, or **prettyui.Histogram.new(parent, options)**.
Default size is 480 × 260; managed helpers fill the host width. Standard anchors and flow options apply.

`Reset()`
: Clears data and totals while retaining configuration and zoom.

`SetSize(width, height)`, `SetVisible(visible)`
: Resize or hide the graph. Size anchors are retained; hidden time graphs continue collecting.

`Destroy()`
: Removes UI and subscriptions. Managed hosts clean up automatically; standalone owners must call it.

Snapshots are detached copies. Panel dock/popout views stay synchronized.

{{% /doc-section %}}
