---
title: "Layout and scale"
weight: 2
---

{{% doc-section %}}

## Layout and scale {#layout-and-scale}

Components added through `Add…` helpers participate in automatic flow. Text wraps to the available width, and following components move when content grows, collapses, or is removed.

{{% note %}}

**Flow placement.** Use `inline = true` to join the current row. Supplying `y` or `absolute = true` opts only that component out of flow. Interactive children continue forwarding wheel input to their owning scrollable content host.

{{% /note %}}

{{% note %}}

**Interface scale.** Dimensions use API interface units; the client applies the user's Interface Scale setting automatically.

{{% /note %}}

{{% /doc-section %}}
