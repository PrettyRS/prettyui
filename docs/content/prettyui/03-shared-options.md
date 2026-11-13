---
title: "Shared component options"
weight: 3
---

{{% doc-section %}}

## Shared component options {#shared-options}

Windows, panels, tab pages, and simple views place every content component through the same flow layout. This encapsulates every prettyUI component.

```lua
window:AddText({
    text = "Status",
    marginTop = 12,
})

window:AddSimpleButton("Refresh", refresh)
window:AddSpriteButton("SETTINGS", openSettings, {
    inline = true,
    columnGap = 8,
    tooltip = "Open settings",
})
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### Flow placement

`inline`
: Joins the current row instead of starting below it.

`offsetY`
: Offsets a component vertically when it joins an existing row with `inline = true`, without opting out of flow.

`marginTop`, `marginBottom`
: Overrides the component's normal vertical spacing.

`columnGap`
: Changes the space after this component before the next inline component.

`absolute` or `y`
: Opts the component out of automatic flow.

{{% /api-card %}}

{{% api-card %}}

### Common presentation

`x`, `y`
: Position offsets in interface units.

`xAnchor`, `yAnchor`
: Parent-relative position anchors.

`width`, `height`, `size`
: Component dimensions when supported.

`widthAnchor`, `heightAnchor`
: Parent-relative size anchors when supported.

`tooltip`
: A string or tooltip options table.

{{% /api-card %}}

{{% api-card %}}

### Allocation

`categoryID`
: Set **"auto"** on a root to allocate managed IDs for its component tree.
  Omitted selection keeps native inheritance. See [Component IDs](#component-ids).

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
