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

In Classic Interface, panels use one full-height right sidebar instead of their
modern windows. It starts collapsed on each mode entry, even when panels are
enabled. Modern placement, tab groups, native membership, and ribbon preferences
are retained for returning to Modern Interface.

{{< signature compact="true" >}}
NisPanel.new(parent, options)
{{< /signature >}}

```lua
local state = { lastTick = 0 } -- Plugin state survives content rebuilds.
local gameArea = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
local panel = prettyui.NisPanel.new(gameArea, {
    id = "my-plugin:encounter",
    categoryID = "auto",
    x = 80,
    y = 80,
    width = 300,
    height = 180,
    tabText = "Encounter",
    buildContent = function(owner)
        owner:AddTitle("Encounter")
        local tickText = owner:AddText("Client tick: " .. state.lastTick)
        Event.Logic.Subscribe("my-plugin:encounter-tick", function(event)
            state.lastTick = event.logicTick
            tickText.content = "Client tick: " .. state.lastTick
        end)
        return function()
            Event.Logic.Unsubscribe("my-plugin:encounter-tick")
        end
    end,
})

-- During plugin shutdown:
panel:Destroy()
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### Options

`id`
: Stable, globally unique ID, such as **"my-plugin:encounter"**. PrettyUI saves
  enabled state, bounds, tab membership, order, and the selected tab in its own
  persistent DB, including native NIS host membership. Omit for a transient
  panel whose enabled state and remembered membership last only this session.
  Duplicate live IDs are rejected.

`dockTo`
: Another panel's **id**, used as a first-declaration docking default. The target
  may be created later, including by another plugin. Requires **id**.

Saved layouts override constructor position, size, anchors, and **dockTo**.

`active`
: Whether the panel starts enabled. Defaults to true; set false to defer its
  first opening to the ribbon. Saved enabled state overrides this default.

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
: Sprite ID and hover text shared by the panel's tab and its automatic ribbon
  button. Defaults to a built-in icon and **"Panel"**.

`buildContent(panel)`
: Optional for a panel with no content; required to create content. Called whenever
  the panel's page becomes active. Add controls using **panel:Add…** or build
  directly under **panel.content**. Return an optional cleanup function for
  plugin-owned subscriptions and other content-specific resources.

`onBoundsChange(panel, x, y, width, height)`
: Receives changed, committed bounds after dragging, resizing, `SetSize`, or
  parent-driven repositioning. Coordinates are parent-relative interface units.
  Identified panels are saved automatically; no persistence callback is needed.

`onClose(panel)`
: Called by `Close()` after deactivating the panel, before optional destruction.

`destroyOnClose`
: Destroy instead of hide when true. Defaults to false.

{{% /api-card %}}

{{% api-card %}}

### Content lifecycle

Build all content inside **buildContent(panel)**, not after construction. An
unselected grouped tab or native page releases managed controls, tooltip contexts,
row backgrounds, the scroll tree, and its overlays while remaining enabled.
Disabling a panel with **SetActive(false)** or **Hide()** also removes its tab
from the visible UI. The shell and remembered placement remain for reactivation.
Selection, **Show()**, or undocking remounts selected content by calling
**buildContent** again and restores **scrollY**. Resizing, toggling interface
lock, temporarily hiding a drag preview, and world-map hiding do not rebuild
content or change enabled state.
Classic sidebar switching and collapse also release outgoing content without
disabling the page or calling **onClose**. Only the selected enabled page builds.
Its content and tooltip/input overlays can live on a different interface from
the retained modern shell; use **panel.content** as the content parent.

If **buildContent** returns a function, PrettyUI calls it before destroying
controls on deactivation or **Destroy()**. Use it to unsubscribe content-owned
events while controls are still accessible. Keep persistent values in plugin Lua
state, not in control handles: handles from a previous build are invalid after
cleanup. **panel.content** and **panel.viewport** are nil while unmounted.
**Add…** helpers remain available on the panel, but create controls only during
an active content build. A panel without **buildContent** may remain empty.

`AddText`, `AddTitle`, `Add…`
: Use the shared [layout and flow helpers](#layout-and-scale) inside
  **buildContent**.

`scrollable`, `scrollStep`, `contentHeight`
: Shared [scrolling options](#scrolling-api). Scrolling defaults to true with
  a step of **32**; managed content is measured automatically.

`SetScrollable(value)`, `SetScrollPosition(y)`, `ScrollBy(delta)`
`ScrollToChild(child, topOffset)`, `SetContentHeight(height)`
: Use the shared [scrolling methods](#scrolling-api).

`content`, `viewport`, `scrollbarVisible`, `scrollY`, `contentHeight`, `contentWidth`
: Raw content layer and clipped viewport while mounted; **content** and
  **viewport** are nil when unmounted. **scrollY** is preserved across rebuilds.

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
panels share bounds; only the active page mounts content. Each panel preserves
its own scroll position across switches.

Panels mounted directly on `TOPLEVEL_V2__GAME_AREA` can also be dropped onto a
native NIS tab band, or the visible header of a standalone native window.
Their own tab becomes a page in that row; drag it out to restore an independent
panel. Escape or focus loss cancels the drag. Native tabs keep their original
handlers and select native pages normally. Native movement and resizing control
the docked viewport. Lock/unlock handling does not rebuild active content.
Own tab selection remains enabled; dragging, undocking by gesture, and resizing
remain disabled while locked.

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
once to record the native host. Explicit undocking or committing a new standalone
placement clears the saved membership; deactivation and closing remember it.
Native-tab drag completion saves the settled host, own-tab order and selection
after clearing its transaction state; no later click or logic tick is needed
before restarting the consumer plugin. A save that already lost native membership
requires docking that panel again; matching bounds cannot recover the missing host.

Compatible native tab rebuilds, reorders, and group merges/splits preserve
PrettyUI shell, membership, and selection; switching away destroys page content
and selecting it again rebuilds it. Temporary loss of native frame selection
releases own content/input without discarding membership; active content returns
when native selection becomes visible again. Closing every host or changing to
an unsupported arrangement restores raised, standalone PrettyUI panels and
releases borrowed native state.

**Stacking limitation:** active content and added tab artwork use the GAME_AREA
overlay fallback. They can draw above overlapping native windows; this is not
native-equivalent occlusion. Inactive pages release content, tooltips, and
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
container. Availability changes preserve the PrettyUI shell and selection while
adopting newly loaded native roots; an active page's content is not rebuilt by
native reflow alone. Each availability transition permits one
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
  Returns false in Classic Interface; remembered modern docking is unchanged.

`Undock()`
: Detaches this panel and saves it as standalone, remounting its content if
  active. Native docking restores the retained standalone rectangle;
  PrettyUI-only groups keep their current bounds.
  In Classic Interface this is a no-op.

`SelectTab()`
: Selects this panel within its group, or enables/selects its Classic sidebar page.

`SetSize(width, height)`
: Resizes the panel, or its entire PrettyUI group, within the configured size
  limits. Native docking and the Classic sidebar own sizing; this is a no-op there.

`SetActive(active)`, `IsActive()`
: Enables or disables the panel independently of tab selection. Disabling removes
  its body, tab, and input overlays, releases content, and remembers placement.
  Enabling restores its previous group/tab slot or standalone bounds and selects
  it, including while locked. First activation uses constructor placement and
  **dockTo** defaults. An unavailable native host restores when it becomes
  available; until then an enabled panel is standalone.

`Show()`
: Enables, shows, and raises the panel, restoring remembered placement if disabled
  and selecting its tab if grouped.

`Hide()`
: Equivalent to **SetActive(false)**. Does not call **onClose** or forget placement.

`Close()`
: Deactivates the panel, calls **onClose**, then optionally destroys it. Also used
  by the close button, which is visible only while the interface is unlocked.

`Destroy()`
: Calls the content cleanup before destroying controls, then removes the panel,
  ribbon button, shell, and retained handlers without forgetting enabled state or
  saved membership. Call during plugin shutdown. **Hide()** and **Close()**
  instead retain a ribbon button for reopening unless **destroyOnClose** is true.
  Destroying a native member also removes its tab and restores native state when
  the last PrettyUI member leaves. Library shutdown restores native overrides
  without forgetting saved native membership.

{{% /api-card %}}

{{% /api-grid %}}

### Panel ribbon {#ribbon-bar-api}

Every live `NisPanel` automatically adds a ribbon button using its **tabIcon**
and **tabText**. No registration API is needed. Destroying a panel removes its
button; the ribbon disappears when no panels remain.

In Modern Interface, a highlighted button means the panel is enabled, even when
another tab is selected. Click to disable or restore it. Disabled panels have no
body or tab but keep their ribbon buttons. The cog opens left/right/top placement
and auto-hide settings, saved independently of panel layout.

In Classic Interface, the fixed right rail is **44 interface units** wide.
Selecting a button opens **360 additional content units** to its left (**404**
total); selecting the same button again collapses it. Another button replaces
the current page. Only the selected page is highlighted; other pages stay enabled.
**Show()**, **SelectTab()**, and **SetActive(true)** select a page even if it was
already enabled. **Hide()**, **SetActive(false)**, **Close()**, and destruction
release the selected body without automatically selecting a replacement.

The entire visible sidebar width is reserved in the native containing layout:
right-anchored minimap, ribbon, and content wrappers shift together. The gameview
also shrinks when its native layout permits it; a gameview limitation does not
disable native UI reservation. Incompatible mandatory native layouts suspend
the sidebar rather than drawing it over native controls. On undersized screens,
the rail/content widths clamp to leave at least one native-area unit.

The settings icon stays at the top; wheel-scroll the clipped panel-icon list if
it exceeds the available height. Classic settings explain that position and
auto-hide apply only to Modern Interface; saved preferences are not overwritten.
World-map focus temporarily occludes the sidebar and pauses native writes while
retaining the selected content tree and scroll position. Mode exit, last-panel
removal, and shutdown restore owned native geometry.

Classic geometry and lifecycle are fixture-verified. Actual client rendering,
native-script compliance, and world-click alignment still require client proof.

`prettyui.RibbonBar.SetPosition("left" | "right" | "top")`, `GetPosition()`
: Changes or reads the saved modern ribbon edge.

`prettyui.RibbonBar.SetAutoHide(boolean)`, `GetAutoHide()`
: Changes or reads saved modern sliding auto-hide.

This restores the ribbon for panel control, not the removed plugin-registration
API. Native plugin content/settings layers remain separate entry points.

{{% /doc-section %}}
