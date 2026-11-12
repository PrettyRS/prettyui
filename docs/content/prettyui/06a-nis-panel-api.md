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
    id = "my-plugin:encounter",
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

`id`
: Stable, globally unique ID, such as **"my-plugin:encounter"**. PrettyUI saves
  bounds, tab membership, order, and the active tab in its own persistent DB.
  Omit for a transient panel. Duplicate live IDs are rejected.

`dockTo`
: Another panel's **id**, used as a first-declaration docking default. The target
  may be created later, including by another plugin. Requires **id**.

Saved layouts override constructor position, size, anchors, and **dockTo**.

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
  Identified panels are saved automatically; no persistence callback is needed.

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

Panels mounted directly on `TOPLEVEL_V2__GAME_AREA` can also be dropped onto a
native NIS tab band. Their existing content becomes an own page in that row;
drag the own tab out to restore an independent panel. Escape or focus loss
cancels the drag. Native tabs keep their original handlers and select native
pages normally. Native movement and resizing control the docked viewport.
Lock/unlock handling retains the existing controls and scroll state. Own tab
selection remains enabled; dragging, undocking by gesture, and resizing remain
disabled while locked.

**Locking safety:** the latest live result still showed invisible nested pages
and a client crash on tab interaction, including after the owned-layer workaround.
Artwork now uses GAME_AREA rather than native-frame descendants, but this
replacement is not yet client-verified. Do not interact with obscured/invisible
panels.

Native bindings are session-only: saved panel layouts retain standalone bounds,
not native component handles. Compatible native tab rebuilds, reorders, and
group merges/splits retain the existing PrettyUI page and its selected content.
Temporary loss of native frame selection suspends own content/input without
discarding membership; it resumes when native selection becomes visible again.
Closing every host or changing to an unsupported arrangement restores raised,
standalone PrettyUI panels and releases borrowed native state.

**Stacking limitation:** retained content and added tab artwork use the GAME_AREA
overlay fallback. They can draw above overlapping native windows; this is not
native-equivalent occlusion. Inactive pages hide their content, tooltips and
sibling input overlays; only the current native frame's own tab artwork is shown.

Grouped hosts are discovered from named native components and matching native
tab membership, not matching screen rectangles. Standalone Notes supports a
synthetic native/PrettyUI row by insetting its embedded whole wrapper. Other
standalone hosts are not supported. Incompatible bounds or insufficient tab
space are rejected without changing native layout.

`DockTo(target)`
: Joins the target's group, adopts its bounds, and selects this panel. Returns
  false unless both panels are visible, unlocked, on the same parent, and the
  target's size satisfies every member's limits. Group minimum height is **49**.
  For existing groups, pass their active panels; docking merges both groups.
  This is an explicit layout change; use the **dockTo** option for startup defaults.
  A native frame component or packed frame component ID is also accepted, such as
  `ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__NOTES_WINDOW)`.
  Native targets require a direct GAME_AREA mount and a compatible native host.

`Undock()`
: Detaches this panel and saves it as standalone. Native docking restores the
  retained standalone rectangle; PrettyUI-only groups keep their current bounds.

`SelectTab()`
: Selects this panel within its group.

`SetSize(width, height)`
: Resizes the panel, or its entire PrettyUI group, within the configured size
  limits. While docked natively, the native frame owns sizing; this is a no-op.

`Show()`
: Shows and raises the panel, selecting its tab if grouped.

`Hide()`
: Hides and undocks the panel without calling **onClose**.

`Close()`
: Calls **onClose**, then hides or destroys the panel. Also used by the close
  button, which is visible only while the interface is unlocked.

`Destroy()`
: Removes the panel, managed content, and retained handlers without forgetting its
  saved group. Call during plugin shutdown; `Hide()` and `Close()` instead save
  the panel's removal from its group.
  Destroying a native member also removes its tab and restores native state when
  the last PrettyUI member leaves. Library shutdown restores native overrides.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
