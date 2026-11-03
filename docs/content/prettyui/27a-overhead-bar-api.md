---
title: "Overhead bars"
weight: 27
---

{{% doc-section %}}

## Overhead bars {#overhead-bar-api}

{{% note %}}
**This API is Unreleased.** 

Overhead bars are available in the PrettyUI Git repository, but not yet in the public mod.io distribution.
{{% /note %}}

`prettyui.OverheadBar` attaches a health-bar-like overlay to NPCs, players, or Locs.

{{< signature >}}
OverheadBar.forNPC(npcEntity, options?)
OverheadBar.forPlayer(playerEntity, options?)
OverheadBar.forLoc(locEntity, options?)
{{< /signature >}}

Constructors need an entity and return `nil` if the target or overlay is unavailable.

{{< overhead-bar-preview >}}

{{% api-grid compact="true" %}}

{{% api-card %}}

### Styles and fill

`variant`
: Style name from `prettyui.OverheadBar.Variants` (default `"health.default"`).

`value`
: Fill fraction, default `1`. `SetValue(value)` clamps it to `0..1`.

`SetVariant(name)`
: Switches style without changing the fill; returns `false` for an unknown style or destroyed bar.

{{% /api-card %}}

{{% api-card %}}

### Placement options

`heightAboveGround`
: World-space height override. NPCs use their configured overlay height or current bounding-box top; players default to `1024`, Locs to `512`.

`offsetX`, `offsetY`
: Pixel offsets, default `0` and `8` respectively. Positive `offsetY` moves the bar up.

`parent`
: Optional overlay component.

`hidden`
: Start hidden when `true`.

{{% /api-card %}}

{{% api-card %}}

### Lifecycle

`Update()`
: Reprojects the bar; automatic each logic tick. Returns `false` when hidden or offscreen.

`Show()`, `Hide()`
: Control visibility. `Show()` also updates the position.

`Destroy()`
: Removes the bar. It also self-destructs when its entity or overlay disappears.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
