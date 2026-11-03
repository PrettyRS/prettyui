---
title: "Tabbed content"
weight: 11
---

{{% doc-section %}}

## Tabbed content {#tabs-api}

Tabs combines divider-aligned navigation with one switchable content page per tab. Text and icon tabs may be used in the same group.

```lua
local tabs = window:AddTabs({
    { text = "Overview" },
    { text = "Items" },
    { kind = "icon", icon = id.Sprite.RS3_ICON_MENU_COMMUNITY, tooltip = "Actions" },
}, {
    height = 180,
    activeIndex = 1,
    onChange = function(group, index, value, page)
        log("Selected tab " .. tostring(index))
    end,
})

local overview = tabs:GetPage(1):AddPanel({ height = 96 })
overview:AddText("Overview content")
tabs:GetPage(2):AddItemGrid(items, { columns = 4, rows = 2 })
tabs:SetActive(2)
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### Configuration

{{< signature compact="true" >}}
Tabs.new(parent, tabs, options)
{{< /signature >}}

Text tabs
: Use **{ text = "Label" }**.

Icon tabs
: Use **{ kind = "icon", icon = spriteID, tooltip = value }**.

Disabled tabs
: Set **disabled = true** on a tab entry.

`activeIndex`
: Initial selected tab; defaults to 1.

`onChange(group, index, value, page)`
: Runs when the active tab changes.

`tabGap`, `tabInset`
: Adjust horizontal spacing and the first tab's inset.

`scrollable`, `scrollStep`, `contentHeight`
: Configure scrolling for every tab page. Pages scroll by default and hide their scrollbar until overflow.

`rowBackgroundColours`, `rowBackgroundColors`
: Alternates row background colours to match native settings panels. See
  [Row backgrounds](#row-backgrounds).

`rowBackgroundEdgeToEdge`
: Extends the backgrounds to the content edges. Defaults to false.

Per-page row backgrounds
: Set either row-background option on a tab entry to override it for that page.

Per-tab scrolling
: A tab entry may override **scrollable** or **contentHeight** for its own page.

{{% /api-card %}}

{{% api-card %}}

### Pages and control

`GetPage(index)`
: Returns a page with **content** and the standard **Add…** helpers, including
  **AddPanel** for flow-managed, non-popout panels and **AddTabs** for nested
  tab groups.

Tab page scroll methods
: Pages expose **SetScrollable**, **SetScrollPosition**, **ScrollBy**,
  **ScrollToChild**, and **SetContentHeight**.

`page:RefreshRowBackgrounds()`
: Rebuilds backgrounds after adding, removing, or moving rows.

`SetActive(index, notify)`
: Shows one enabled page and optionally invokes **onChange**.

`GetActiveIndex()`
: Returns the selected one-based index.

`SetScrollable(value)`
: Enables or disables scrolling across every page.

`GetTab(index)`
: Returns the normalized tab state.

`SetDisabled(index, disabled)`
: Changes availability and selects another enabled tab when necessary.

`SetTabTooltip(index, value)`
: Adds, replaces, or removes one tab's tooltip.

`Destroy()`
: Destroys the tab group and its pages.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
