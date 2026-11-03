---
title: "Panel"
weight: 9
---

{{% doc-section %}}

## Panel {#panel-api}

Panels group content inside other content hosts or act as standalone overlays. Panel
content is scrollable by default on both its docked and pop-out surfaces. Set
`popout = true` to let users move a nested panel into a draggable overlay.

```lua
local panel = window:AddPanel({
    popout = true,
    resizable = true,
    minWidth = 240,
    minHeight = 120,
    height = 154,
    popoutX = 80,
    popoutY = 80,
    popoutBackgroundAlpha = 0.72,
    popoutClickthrough = false,
    rowBackgroundColours = {
        0x24211EFF,
        0x2E2825FF,
    },
})

panel:AddTitle("Details")
panel:AddText("Window-style automatic content flow")
panel:RefreshRowBackgrounds()
panel:SetPoppedOut(true)
```

### Standalone semi-transparent overlay

A panel does not need to belong to another PrettyUI content host. Construct it directly on the game area without enabling pop-out. Standalone panels can be repositioned by holding Alt and dragging from anywhere on the panel; their position stays within the parent when its dimensions permit.

```lua
local gameArea = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)

local overlayPanel = prettyui.Panel.new(gameArea, {
    categoryID = "auto",
    width = 300,
    height = 140,
    x = 80,
    y = 80,
    backgroundAlpha = 0.55,
})

overlayPanel:AddTitle("Encounter timer")
overlayPanel:AddText("Next attack: 00:12")
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### Construction and content

{{< signature compact="true" >}}
Panel.new(parent, options)
{{< /signature >}}

`Panel.new(parent, options)`
: Creates a standalone panel. Hold Alt and drag from anywhere on it to reposition it.

`AddPanel(options)`
: Adds a flow-managed panel to a window, simple view, tab page, or another
  supported content host.

`AddText`, `AddTitle`, `Add…`
: Add content using the same helpers and flow rules as a window.

`categoryID`
: Applies the allocation choice to both surfaces. Inherits from the parent
  unless set to **"auto"**. See [Component IDs](#component-ids).

`scrollable`, `scrollStep`, `contentHeight`
: Configure the shared scroll behavior. **scrollable** defaults to **true**.

`rowBackgroundColours`, `rowBackgroundColors`
: Alternates row background colours to match native settings panels. See
  [Row backgrounds](#row-backgrounds).

`rowBackgroundEdgeToEdge`
: Extends the backgrounds to the content edges. Defaults to false.

`SetScrollable(value)`
: Applies the setting to both docked and pop-out surfaces.

`ScrollToChild(child, topOffset)`
: Scrolls both surfaces to the paired direct child with an optional top offset.

`RefreshRowBackgrounds()`
: Rebuilds row backgrounds on both surfaces after content or layout changes.
  Call it after adding, removing, or repositioning managed children.

`content`
: Raw content layer for the normal panel surface.

`overlayContent`
: Raw content layer for custom pop-out content.

{{% /api-card %}}

{{% api-card %}}

### Pop-out overlay

`popout`
: Enables the pop-out and dock buttons. Defaults to false.

`poppedOut`
: Starts the panel popped out when true.

`SetPoppedOut(value)`
: Switches between the nested panel and overlay.

`TogglePopout()`
: Toggles the current mode.

`SetPopoutClickthrough(value)`
: Makes overlay content ignore input while leaving the dock button available.
  A resizable click-through pop-out exposes its resize edges only while Alt is
  held.

`SetPopoutBackgroundAlpha(alpha)`
: Sets overlay background opacity from 0 to 1.

`onPopoutChange`
: Receives the panel and its new popped-out state.

`popoutX`, `popoutY`
: Initial position of the pop-out in its overlay parent.

`popoutWidth`, `popoutHeight`
: Optional initial dimensions for the pop-out. Interactive and programmatic
  resizing subsequently synchronize both panel surfaces.

{{% /api-card %}}

{{% api-card %}}

### Sizing and movement

`resizable`
: Enables interactive resizing from all four edges and four corners. Defaults
  to false. Resizing is constrained to the parent where the configured minimum
  fits.

`minWidth`, `minHeight`
: Lower bounds used by interactive resizing and `SetSize`. Defaults to 9 × 9
  interface units.

`maxWidth`, `maxHeight`
: Optional upper bounds used by interactive resizing and `SetSize`.

`SetSize(width, height)`
: Changes both docked and pop-out dimensions, subject to the configured minimum
  and maximum dimensions.

`onPositionChange`
: Receives **(panel, x, y, poppedOut)** once after a completed drag changes
  position; releasing Alt also ends the drag. Coordinates are parent-relative
  interface units. Programmatic moves and cancelled drags do not notify.
  Restore saved positions with **x**, **y** for standalone panels or
  **popoutX**, **popoutY** for pop-outs, without position anchors.

{{% /api-card %}}

{{% api-card %}}

### Player interface settings

`useNativeTransparency`
: Makes the panel match the player's native interface transparency setting.
  Changes to the native interface transparency setting scale **backgroundAlpha**
  and **popoutBackgroundAlpha**, so both still apply. Defaults to false.

`respectInterfaceLock`
: Stops the panel from being moved or resized while the player's interface is
  locked. Defaults to true. 

`SetUseNativeTransparency(enabled)`
: Changes **useNativeTransparency**. Turning it off restores the panel's own
  alpha values.

`SetRespectInterfaceLock(enabled)`
: Changes **respectInterfaceLock**. Turning it off unlocks the panel.

{{% /api-card %}}


{{% /api-grid %}}

{{% note %}}

**Content synchronization.** Components added with panel `Add…` helpers stay synchronized between nested and popped-out views. Directly constructed standalone panels use their normal surface and show no toggle unless pop-out is enabled.

{{% /note %}}

{{% /doc-section %}}
