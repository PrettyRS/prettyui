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
  bounds, tab membership, order, and the active tab in its own persistent DB,
  including native NIS host membership. Omit for a transient panel. Duplicate
  live IDs are rejected.

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
native NIS tab band, or the visible header of a standalone native window.
Their existing content becomes an own page in that row; drag the own tab out
to restore an independent panel. Escape or focus loss
cancels the drag. Native tabs keep their original handlers and select native
pages normally. Native movement and resizing control the docked viewport.
Lock/unlock handling retains the existing controls and scroll state. Own tab
selection remains enabled; dragging, undocking by gesture, and resizing remain
disabled while locked.

PrettyUI-only groups and synthetic native-host rows use the native dark tab-strip
backdrop behind their tabs. Icons retain their original colours and input;
existing native tab rows keep their own backdrop without a second overlay.

Standalone synthetic rows follow the visible content slot, not the client-hidden
native strip. An existing binding retains its native icon if that strip is
temporarily rebuilt empty. Each embedded root may return to its recorded native
baseline once per lock transition, including delayed client reflow; its inset is
then restored without replacing controls or selection. Unrecognized or repeated
layout overwrites still detach safely rather than cause repeated native writes.

**Locking safety:** earlier live builds produced invisible nested pages and a
client crash on tab interaction. Artwork now uses GAME_AREA rather than
native-frame descendants. The latest Prayer report was a forced detach during
locking; its reflow correction is regression-tested, not client-verified.
Do not interact with obscured/invisible panels.

Identified panels save native host names, own-tab order and selection, and their
standalone bounds, never native component handles. On restart, they rejoin a
compatible saved host when it becomes available, even while the interface is
locked. Until then they remain standalone; matching screen position alone does
not establish native membership. Existing position-only saves require docking
once to record the native host. Explicit undocking, hiding, closing, or committing
a new standalone placement clears the saved membership.
Native-tab drag completion saves the settled host, own-tab order and selection
after clearing its transaction state; no later click or logic tick is needed
before restarting the consumer plugin. A save that already lost native membership
requires docking that panel again; matching bounds cannot recover the missing host.

Compatible native tab rebuilds, reorders, and group merges/splits retain the
existing PrettyUI page and its selected content.
Temporary loss of native frame selection suspends own content/input without
discarding membership; it resumes when native selection becomes visible again.
Closing every host or changing to an unsupported arrangement restores raised,
standalone PrettyUI panels and releases borrowed native state.

**Stacking limitation:** retained content and added tab artwork use the GAME_AREA
overlay fallback. They can draw above overlapping native windows; this is not
native-equivalent occlusion. Inactive pages hide their content, tooltips and
sibling input overlays; only the current native frame's own tab artwork is shown.

Grouped hosts are discovered from named native components and matching native
tab membership, not matching screen rectangles. Native scroll layers are optional
when the host does not define one, as with secondary chat windows.

Standalone whole-page handling covers Notes, Inventory, Prayer, Equipment, Chat,
Stats, captured ability/spellbooks, Emotes, RuneMetrics XP/loot/graph windows,
Friends/Friends Chat, Music, plugin content, achievement tracker/paths, Quest
List, standalone Clan Chat and Familiar.
Other standalone hosts require a native icon and an identifiable full-size,
anchored embedded wrapper. Notes also supports an empty hidden tab strip using
its known icon.

An existing native tab row can accept PrettyUI pages without a second matching
outer frame. Independently visible windows are not merged just because their row
artwork matches. With an existing Clan tab row, its main and tooltip roots are
concealed together by their native content slot without rewriting their layouts.

For standalone Clan, both full-size roots reserve the same tab band. Quest List
reserves that band across its list, controls and filter roots: the list shrinks
with the available height while fixed-height controls and filters retain their
sizes and relative offsets. Original layout scalars and plugin-hidden flags are
restored on undock, teardown, or a partially applied docking failure. Native
filter open/closed state is not overwritten.

Familiar supports both its centered embedded page and the native “Familiar
currently unavailable” state. The latter reserves the band across the native
edit block's background, message and icon children, without changing the edit
container. Availability changes retain the PrettyUI page and selection while
adopting newly loaded native roots. Each availability transition permits one
recorded-baseline reset per retained root, as with lock reflow. Original centered
anchors and placeholder layouts restore on undock; unknown layouts are rejected.
The client may retain the familiar interface with an unparented 0 × 0 root while
unavailable. Only a root actually parented to this host's content participates
in docking; a previously inset page releases its layout and hidden flag when
unparented so remounting it does not accumulate an inset.

Only embedded page roots are inset; native outer slots and descendants inside
those roots are not rewritten. Equipment's centered anchors restore exactly on
undock. Separate Prayer/plugin listeners and timers remain untouched. Native
outer scrollbar and edit layers are concealed only while an own page is selected.
Tabless HUD widgets and unrecognized split-root layouts remain excluded.
Incompatible bounds or insufficient native content/tab space are rejected
without native layout writes. Captured layouts are regression-verified;
client rendering and native script behavior still require verification.

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
  the last PrettyUI member leaves. Library shutdown restores native overrides
  without forgetting saved native membership.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
