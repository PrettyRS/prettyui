---
title: "NisPanel"
weight: 6
---

{{% doc-section %}}

## NisPanel {#nis-panel-api}

A standalone panel matching the modern RuneScape interface. Always follows the
player's interface lock and background transparency settings; content stays opaque.
When unlocked, drag the header to move it or an edge or corner to resize it.
Placement fits around other interfaces; an invalid drop restores the previous bounds.

{{< signature compact="true" >}}
NisPanel.new(parent, options)
{{< /signature >}}

```lua
local gameArea = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
local panel = prettyui.NisPanel.new(gameArea, {
    categoryID = "auto",
    x = 80,
    y = 80,
    width = 300,
    height = 180,
    tabText = "Encounter",
})

panel:AddTitle("Encounter")
panel:AddText("Next attack: 00:12")

-- During plugin shutdown:
panel:Destroy()
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### Options

`categoryID`
: Optional **"auto"** allocation. See [Component IDs](#component-ids).

`x`, `y`, `xAnchor`, `yAnchor`
: Initial parent-relative position and optional proportional anchors. Position
  defaults to **0, 0** and stays within the parent when the panel fits.

`width`, `height`
: Initial dimensions in interface units. Defaults to **300 × 160**.

`minWidth`, `minHeight`, `maxWidth`, `maxHeight`
: Bounds for resizing and `SetSize`. Minimums default to **64 × 21**; maximums
  are optional.

`tabIcon`, `tabText`
: Sprite ID and hover text for the panel's tab when grouped. Defaults to a
  built-in icon and **"Panel"**.

`onBoundsChange(panel, x, y, width, height)`
: Receives changed, committed bounds after dragging, resizing, `SetSize`, or
  parent-driven repositioning. Coordinates are parent-relative interface units.
  Save all four values and restore them as constructor options without anchors.

`onClose(panel)`
: Called by `Close()` before hiding or destroying the panel.

`destroyOnClose`
: Destroy instead of hide when true. Defaults to false.

{{% /api-card %}}

{{% api-card %}}

### Content

`AddText`, `AddTitle`, `Add…`
: Use the shared [layout and flow helpers](#layout-and-scale).

`scrollable`, `scrollStep`, `contentHeight`
: Shared [scrolling options](#scrolling-api). Scrolling defaults to true with
  a step of **32**; managed content is measured automatically.

`SetScrollable(value)`, `SetScrollPosition(y)`, `ScrollBy(delta)`
`ScrollToChild(child, topOffset)`, `SetContentHeight(height)`
: Use the shared [scrolling methods](#scrolling-api).

`content`, `viewport`, `scrollbarVisible`, `scrollY`, `contentHeight`, `contentWidth`
: Raw content layer, clipped viewport, and current scroll state.

`layout`, `textLayout`
: Shared flow configuration; **textLayout** is an alias for **layout**.

`rowBackgroundColours`, `rowBackgroundColors`, `rowBackgroundEdgeToEdge`
: Shared [row background options](#row-backgrounds).

`RefreshRowBackgrounds()`
: Rebuilds row backgrounds after adding, removing, or repositioning content.

`tooltip`, `SetTooltip(value)`
: Set or replace the panel's [tooltip](#tooltip-api). Pass nil to remove it.

{{% /api-card %}}

{{% api-card %}}

### Docking and lifecycle

Drag onto another compatible `NisPanel` to form a tab group. Click tabs to switch,
drag within the tab strip to reorder, or drag a tab out to detach it. Grouped
panels share bounds and retain their own content and scroll state.

`DockTo(target)`
: Joins the target's group, adopts its bounds, and selects this panel. Returns
  false unless both panels are visible, unlocked, on the same parent, and the
  target's size satisfies every member's limits. Group minimum height is **49**.
  For existing groups, pass their active panels; docking merges both groups.

`Undock()`
: Detaches this panel without changing its bounds.

`SelectTab()`
: Selects this panel within its group.

`SetSize(width, height)`
: Resizes the panel, or its entire group, within the configured size limits.

`Show()`
: Shows and raises the panel, selecting its tab if grouped.

`Hide()`
: Hides and undocks the panel without calling **onClose**.

`Close()`
: Calls **onClose**, then hides or destroys the panel. Also used by the close
  button, which is visible only while the interface is unlocked.

`Destroy()`
: Removes the panel, managed content, and retained handlers. Call during plugin shutdown.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
