---
title: "Scrolling and SimpleView"
weight: 7
---

{{% doc-section %}}

## Scrolling and SimpleView {#scrolling-api}

Windows, panels, tab pages, and `SimpleView` use the same vertical scroll core.
Scrolling defaults to enabled, but no gutter or scrollbar is shown until content
actually overflows. Wheel input, arrow buttons, track clicks, and thumb dragging
stay synchronized; nested scroll areas pass wheel input to their parent when they
reach an edge.

Use `SimpleView` to benefit from the prettyUI layout manager without window or panel styling:

```lua
local view = prettyui.SimpleView.new(parent, {
    categoryID = "auto",
    x = 12,
    y = 12,
    width = 440,
    height = 260,
    scrollStep = 32,
})

view:AddTitle("Rows")
for index = 1, 12 do
    view:AddTextField({
        placeholder = "Row " .. tostring(index),
    })
end
```

### Scroll to a child

```lua
local window = prettyui.Window.new(parent, {
    title = "QuestHelper",
    width = 400,
    height = 300,
})

local questStep = window:AddTitle("Quest Step")

window:ScrollToChild(questStep)
```

`ScrollToChild` accepts a direct child returned by an **Add…** method. It places
the child's top 12 interface units below the viewport top by default and clamps
the scroll position at the start or end of the content. Pass a second argument
to use a different offset: `window:ScrollToChild(questStep, 30)`.

{{% api-grid compact="true" %}}

{{% api-card %}}

### Construction and configuration

{{< signature compact="true" >}}
SimpleView.new(parent, options)
{{< /signature >}}

`categoryID`
: Optional **"auto"** allocation for the view's component tree. See
  [Component IDs](#component-ids).

`scrollable`
: Enables vertical scrolling. Defaults to true.

`contentHeight`
: Optional initial height for raw content. Flow-managed children grow it automatically.

`scrollStep`
: Interface units per wheel delta. Defaults to 32.

`x`, `y`, `width`, `height`
: Viewport position and dimensions.

{{% /api-card %}}

{{% api-card %}}

### Methods

`content`, `viewport`
: The consumer content layer and its clipped viewport.

`scrollbarVisible`, `scrollY`, `contentHeight`, `contentWidth`
: Current overflow state, scroll position, and content dimensions.

`SetScrollPosition(y)`
: Clamped absolute position.

`ScrollBy(delta)`
: Relative movement.

`ScrollToChild(child, topOffset)`
: Scrolls to a direct content child. **topOffset** defaults to 12.

`SetContentHeight(height)`
: Updates overflow detection, content width, scrollbar visibility, and thumb ratios.

`SetScrollable(value)`
: Enables or disables scrolling and resets to the top when disabled.

`SetSize(width, height)`
: Relayouts viewport and track.

`Destroy()`
: Destroys managed children, tooltips, and the complete view tree.

{{% /api-card %}}

{{% /api-grid %}}

{{% note %}}

**Deprecated:** `prettyui.Scrollbar.new(parent, options)` now acts as an
alias for `SimpleView` and will
be removed in v1.0.0.

{{% /note %}}

{{% /doc-section %}}
