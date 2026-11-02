---
title: "Sprite"
weight: 30
---

{{% doc-section %}}

## Sprite {#sprite-api}

Add an image from a built-in sprite ID or a loaded `Plugin.resources` image.

{{< signature >}}
prettyui.Sprite.new(parent, sprite, options)
host:AddSprite(sprite, options)
{{< /signature >}}

### Managed images

`AddSprite` is available on [Window](#window-api), [SimpleView](#scrolling-api), [TabPage](#tabs-api), and [Panel](#panel-api). Panels return a paired handle that updates both their docked and popped-out sprites.

```lua
local icon = window:AddSprite(id.Sprite.RS3_BTN_MENU_7_2, {
    size = 24,
    tooltip = "Decorative menu icon",
})
window:AddText({ text = "Menu", inline = true })

-- Put myimage.png in this plugin's resources/ directory.
local portrait = window:AddSprite(Plugin.resources.myimage, {
    size = 64,
    marginTop = 12,
    tooltip = "Image description",
})
window:AddText({ text = "Image", inline = true, offsetY = 20 })
```

The 128×128 `myimage.png` resource is displayed at 64×64 here. Pass the loaded image value, not `"myimage"`, `"myimage.png"`, or a filesystem path. Sprite does not load files, infer intrinsic dimensions, or provide aspect-fit sizing; choose dimensions with the desired aspect ratio.

Managed sprites reserve their configured width and height without filling the row. `inline = true` joins the current row, allowing sprites and text to sit beside one another. See [shared component options](#shared-options) and [layout and scale](#layout-and-scale) for margins, spacing, anchors, and absolute placement.

### Standalone image

```lua
-- parent is an existing native UI component.
local image = prettyui.Sprite.new(parent, Plugin.resources.myimage, {
    x = 16,
    y = 16,
    width = 128,
    height = 128,
})

-- When this standalone image is no longer needed:
image:Destroy()
```

The constructor positions the image directly under `parent`; it does not register a managed flow row. Use `AddSprite` when the host should manage placement and cleanup.

{{% api-grid compact="true" %}}

{{% api-card %}}

### Size and presentation

`size`
: Sets both dimensions; defaults to 24 interface units.

`width`, `height`
: Override `size` independently. For example, `{ size = 64, width = 96 }` produces a 96×64 image.

`prettyui.Sprite.getSize(options)`
: Returns `width, height` using those same defaults and overrides, without creating an image or inspecting its resource.

`x`, `y`, `xAnchor`, `yAnchor`
: Position offsets and parent-relative anchors. Standalone defaults are zero; managed hosts supply flow positions. Explicit `y` or `absolute = true` opts a managed sprite out of flow.

`widthAnchor`, `heightAnchor`
: Parent-relative size anchors, both defaulting to zero.

`colour` or `color`
: RGBA tint, defaulting to `0xFFFFFFFF` (white). `colour` takes precedence if both are supplied.

`alpha`
: Optional native sprite opacity override.

`tooltip`
: A string or [tooltip options table](#tooltip-api). Without a tooltip, the sprite is clickthrough. Attaching a tooltip uses the existing hover handling; removing it restores clickthrough. No click action is added.

{{% /api-card %}}

{{% api-card %}}

### Methods and lifecycle

`SetSprite(sprite)`
: Replaces the built-in sprite ID or loaded image without changing dimensions or flow placement.

`SetTooltip(value)`
: Adds or updates a tooltip; pass `nil` to remove it.

`Destroy()`
: Removes the tooltip and destroys the native sprite. For a managed sprite, also removes its layout entry and reflows following content.

Host cleanup
: Destroying a managed host destroys its sprites and their tooltips. Panel handle methods apply to both paired images. For standalone images, call `Destroy()` when finished to release tooltip hooks as well as the image.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
