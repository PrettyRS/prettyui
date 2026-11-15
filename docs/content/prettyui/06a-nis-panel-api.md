---
title: "NisPanel"
weight: 6
---

{{% doc-section %}}

## NisPanel {#nis-panel-api}

A draggable, resizable panel that follows the player's interface lock and
background transparency settings. Panels can share tabs with other `NisPanel`s
or compatible native windows. In Classic Interface, they use a shared right sidebar.

```lua
local panel = prettyui.NisPanel.new({
    id = "my-plugin:encounter",
    x = 80,
    y = 80,
    width = 300,
    height = 180,
    tabIcon = id.Sprite.CHILD_TAB_ICON_NOTES,
    tabText = "Encounter",
    buildContent = function(view)
        view:AddTitle("Encounter")
        view:AddText("No active encounter.")
    end,
})

-- During plugin shutdown:
panel:Destroy()
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### Construction

{{< signature compact="true" >}}
NisPanel.new(options?)
NisPanel.new(parent, options?)
{{< /signature >}}

The default parent is `TOPLEVEL_V2__GAME_AREA`, which must be available before
construction. Pass an explicit parent for a custom mount.

`id`
: Stable, globally unique ID, such as **"my-plugin:encounter"**. Saves enabled
  state, bounds, tab membership, order, and selection across sessions. Omit for
  a transient panel. Duplicate live IDs are rejected.

`dockTo`
: Another panel's **id** as the initial docking target; it may be created later.
  Requires **id**. Saved layouts override initial position, size, anchors, and
  **dockTo**.

`active`
: Starts enabled by default. Set false to defer opening to the ribbon.
  Saved enabled state overrides this default.

`categoryID`
: Defaults to **"auto"**. See [Component IDs](#component-ids).

`x`, `y`, `xAnchor`, `yAnchor`
: Initial parent-relative position and optional proportional anchors.
  Position defaults to **0, 0**.

`width`, `height`
: Initial dimensions in interface units. Defaults to **300 × 160**.

`minWidth`, `minHeight`, `maxWidth`, `maxHeight`
: Limits for resizing and **SetSize**. Minimums default to **64 × 21**;
  maximums are optional.

`tabIcon`
: A loaded **Plugin.resources** image or a built-in
  **id.Sprite** ID such as **id.Sprite.CHILD_TAB_ICON_NOTES**. This sets the icon for the tab and ribbon button.
`tabText`
: Hover text for the tab and automatic ribbon button. Defaults to **"Panel"**.

`buildContent(panel)`
: Builds content when the page becomes selected. Use **panel:Add…** helpers or
  **panel.content**. May return a cleanup function; see Content lifecycle below.

`onBoundsChange(panel, x, y, width, height)`
: Called after committed bounds changes, in parent-relative interface units.
  Identified panels save placement automatically.

`onClose(panel)`
: Called by **Close()** after deactivation, before optional destruction.

`destroyOnClose`
: Destroy instead of hide when true. Defaults to false.

{{% /api-card %}}

{{% api-card %}}

### Content lifecycle

Create controls inside **buildContent**, not after construction. Switching tabs,
disabling the panel, or collapsing the Classic sidebar releases its content.
Selecting it again calls **buildContent** and restores its scroll position.
Resizing and interface locking do not rebuild content.

Keep persistent values in plugin state: control handles are invalid after
cleanup. The returned cleanup function runs first, then **OnCleanup** callbacks
and managed unsubscriptions in reverse registration order, before controls are
destroyed. Cleanup also runs on **Destroy()** or a failed build.

`Subscribe(event, callback)`
: Subscribes to a native event, such as **Event.Logic**, while content is mounted.
  Automatically unsubscribes on cleanup; no key is needed. Use plugin-owned
  subscriptions for updates that must continue while the panel is closed.

`OnCleanup(callback)`
: Registers mount-scoped cleanup. Call this and **Subscribe** only inside
  **buildContent** or while content is mounted.

`AddText`, `AddTitle`, `Add…`
: Shared [layout and flow helpers](#layout-and-scale).

`content`, `viewport`
: Content parent and clipped viewport; nil while unmounted. Use **content** as
  the parent for custom controls, including in Classic Interface.

`scrollable`, `scrollStep`, `contentHeight`
: Shared [scrolling options](#scrolling-api). Scrolling defaults to true with
  a step of **32**; managed content is measured automatically.

`SetScrollable(value)`, `SetScrollPosition(y)`, `ScrollBy(delta)`,
`ScrollToChild(child, topOffset)`, `SetContentHeight(height)`
: Shared [scrolling methods](#scrolling-api).

`scrollbarVisible`, `scrollY`, `contentHeight`, `contentWidth`
: Scrollbar visibility, current scroll position, and measured content dimensions.

`layout`, `textLayout`
: Shared flow configuration; **textLayout** is an alias for **layout**.

`rowBackgroundColours`, `rowBackgroundColors`, `rowBackgroundEdgeToEdge`
: Shared [row background options](#row-backgrounds).

`RefreshRowBackgrounds()`
: Rebuilds row backgrounds after content or layout changes.

`tooltip`, `SetTooltip(value)`
: Set or replace the panel's [tooltip](#tooltip-api). Pass nil to remove it.

{{% /api-card %}}

{{% api-card %}}

### Docking and visibility

While unlocked, drag panels together to group them, drag tabs to reorder, or
drag a tab out to detach it. Native docking requires a direct mount on
`TOPLEVEL_V2__GAME_AREA` and a compatible native tab band or window header.
Only the selected page builds content.

Saved native membership restores when its host becomes available; until then,
the panel remains standalone. Docked content can draw above overlapping native
windows rather than following native window occlusion.

`DockTo(target)`
: Joins and selects a panel group. Both panels must be visible, unlocked, on the
  same parent, with target dimensions satisfying every member's size limits.
  Group minimum height is **49**.
  For existing groups, pass their active panels to merge them. Also accepts a
  compatible native frame component or packed frame component ID. Returns false
  when docking is unavailable, including in Classic Interface. Use **dockTo**
  for startup defaults.

`Undock()`
: Detaches and saves the panel as standalone. Native docking restores its
  previous standalone bounds; PrettyUI groups retain their current bounds.
  No-op in Classic Interface.

`SelectTab()`
: Selects this panel's tab, or enables and selects its Classic sidebar page.

`SetSize(width, height)`
: Resizes the panel or its PrettyUI group within configured limits.
  No-op when native-docked or in Classic Interface, where the host owns sizing.

`SetActive(active)`, `IsActive()`
: Sets or reads enabled state, independently of tab selection. Disabling
  releases content and removes the tab but remembers placement. Enabling
  restores placement and selects the panel, including while locked.

`Show()`
: Enables, selects, and raises the panel.

`Hide()`
: Equivalent to **SetActive(false)**; does not call **onClose**.

`Close()`
: Deactivates, calls **onClose**, then optionally destroys the panel.
  Also used by the close button, visible only while unlocked.

`Destroy()`
: Cleans up content and removes the panel and ribbon button without forgetting
  saved state. Call during plugin shutdown. **Hide()** and **Close()** retain
  the ribbon button for reopening unless **destroyOnClose** is true.

{{% /api-card %}}

{{% /api-grid %}}

### Panel ribbon {#ribbon-bar-api}

Each panel automatically adds a ribbon button using **tabIcon** and **tabText**.
In Modern Interface, click to toggle enabled state; highlighting means enabled,
not necessarily selected. The cog controls ribbon placement and auto-hide.

In Classic Interface, click to select a sidebar page; clicking it again collapses
the sidebar without disabling the panel. The sidebar starts collapsed on mode
entry. Modern placement, tab groups, and ribbon preferences are preserved.

`prettyui.RibbonBar.SetPosition("left" | "right" | "top")`, `GetPosition()`
: Changes or reads the saved modern ribbon edge.

`prettyui.RibbonBar.SetAutoHide(boolean)`, `GetAutoHide()`
: Changes or reads saved modern sliding auto-hide.

{{% /doc-section %}}
