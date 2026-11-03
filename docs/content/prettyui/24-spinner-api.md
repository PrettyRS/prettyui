---
title: "Loading spinner"
weight: 24
---

{{% doc-section %}}

## Loading spinner {#spinner-api}

Animated loading indicator with controllable speed and playback.

```lua
local spinner = window:AddSpinner({
    degreesPerLogicUpdate = -6,
})

spinner:SetDegreesPerLogicUpdate(-4)
spinner:SetRotation(180)
spinner:Stop()
spinner:Start()
spinner:Reset()
spinner:Destroy()
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### Spinner

{{< signature compact="true" >}}
Spinner.new(parent, options)
{{< /signature >}}

`size`
: Defaults to 72.

`rotation`
: Initial foreground angle in degrees.

`degreesPerLogicUpdate`
: Foreground rotation added per logic update; defaults to -6. Positive values reverse the default direction.

`BigSpinner`, `AddBigSpinner(options)`
: Aliases for `Spinner` and `AddSpinner(options)`.

`SetRotation(degrees)`
: Sets and normalizes the foreground angle.

`SetDegreesPerLogicUpdate(degrees)`
: Changes rotation speed and direction. The former `logicUpdatesPerFrame`
  option and `SetFrame()` and `SetLogicUpdatesPerFrame()` methods are
  unavailable.

{{% /api-card %}}

{{% api-card %}}

### Lifecycle

`autoPlay`
: Set false to construct the spinner paused.

`Start()`
: Starts or resumes playback.

`Stop()`
: Pauses playback.

`Reset()`
: Restores the angle to zero.

`Destroy()`
: Unsubscribes and destroys the component.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
