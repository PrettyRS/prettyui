---
title: "Dynamic data"
weight: 4
---

{{% doc-section %}}

## Dynamic data {#dynamic-data}

PrettyUI components are live objects rather than one-time templates. Keep the values returned by constructors and `Add…` helpers, then update them when your plugin state changes. Native properties update directly, while stateful PrettyUI components expose methods that also refresh their visuals and internal state.

### Update several component types

```lua
local status = window:AddText({
    text = "Waiting...",
    height = 24,
    maxLines = 1,
})

local progress = window:AddSlider({
    min = 0,
    max = 100,
    value = 0,
})

local action = window:AddFancyButton("Start", startTask)
local reward = window:AddItemSlot(config.Obj.STEEL_BAR, {
    quantity = 1,
})

local function render(state)
    status.content = state.message
    progress:SetValue(state.percent, false)
    action:SetText(state.running and "Cancel" or "Start")
    action:SetDisabled(state.locked)
    reward:SetQuantity(state.rewardQuantity)
end

render({
    message = "Processing rewards...",
    percent = 65,
    running = true,
    locked = false,
    rewardQuantity = 12,
})
```

### Continuously updated values

Call the same setters from the event that owns the data. This example updates a label and progress control from the client logic tick:

```lua
Event.Logic.Subscribe("my_plugin_live_status", function(event)
    local percent = event.logicTick % 101
    status.content = "Client tick: " .. tostring(event.logicTick)
    progress:SetValue(percent, false)
end)

function PluginShutdown()
    Event.Logic.Unsubscribe("my_plugin_live_status")
end
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### Common update patterns

Native component properties
: Assign values such as **text.content** directly.

PrettyUI setters
: Use methods such as **SetText**, **SetValue**, **SetDisabled**, **SetObject**,
  and **SetQuantity**.

Callbacks and events
: Refresh from control callbacks, RuneScape events, HTTP responses, or your own state transitions.

{{% /api-card %}}

{{% api-card %}}

### Keep updates predictable

Suppress callbacks when rendering
: Where supported, pass **false** to a setter such as
  **SetValue(value, false)** to avoid feeding a programmatic update back into
  **onChange**.

Clean up subscriptions
: Unsubscribe plugin-owned events during **PluginShutdown**.

Account for layout
: Changing a value redraws its component, but does not automatically resize every flow row. Use stable dimensions or explicitly resize dynamic multiline content.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
