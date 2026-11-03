---
title: "Divider"
weight: 10
---

{{% doc-section %}}

## Divider {#divider-api}

Divider adds a full-width visual separator between flow-managed components.

```lua
local divider = window:AddDivider()

local spacedDivider = view:AddDivider({
    marginTop = 12,
    marginBottom = 12,
})
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### Construction

{{< signature compact="true" >}}
Divider.new(parent, options)
{{< /signature >}}

`AddDivider(options)`
: Adds a flow-managed divider to a window, simple view, panel, or tab page.

Default layout
: Spans the available content width and occupies 60 interface units of flow height.

{{% /api-card %}}

{{% api-card %}}

### Options and lifecycle

`x`, `width`, `widthAnchor`
: Override the default full-width geometry.

`marginTop`, `marginBottom`
: Adjust vertical spacing.

`rowBackground`
: Defaults to false, so alternating row backgrounds do not paint divider rows.
  Set to true to include one.

`tooltip`
: Optional tooltip.

`Destroy()`
: Destroys the divider.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
