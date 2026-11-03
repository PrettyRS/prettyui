---
title: "Component IDs"
weight: 5
---

{{% doc-section %}}

## Component IDs {#component-ids}

Set `categoryID = "auto"` on a root window, view, panel, or component for higher-capacity allocation. Children and later Add calls inherit the choice.

```lua
local window = prettyui.Window.new(parent, {
    categoryID = "auto",
    title = "Example",
})
window:AddText("Inherits automatic allocation")

local layer = prettyui.NewComponent(ui.Layer, window.content)
prettyui.NewComponent(ui.Text, layer)
```

Owned tooltips, dropdowns, and other detached controls retain the owner's policy. Separately constructed roots need their own opt-in. Shared parents and sibling trees are not changed.

{{% api-grid compact="true" %}}

{{% api-card %}}

### Allocation rules

`categoryID = "auto"`
: Assigns free nonzero category/dynamic-ID pairs to managed controls and decorations of any native type. Numeric categories are not a PrettyUI option.

Omitted `categoryID`
: Keeps native parent-category inheritance. Existing calls continue to work, but emit one migration warning per loaded allocator module. Omitted selection will be deprecated in a future version.

Static parents
: Use native root ID assignment even in auto mode. Their PrettyUI descendants retain the auto policy.

Content hosts
: Stay in category **0** for raw-native children: Window and scrolling content, Tabs pages, both Panel surfaces, CollapseButton content, tooltips, and List rows. Managed children still use nonzero categories.

Mounting
: Auto content hosts require a static or category-zero parent. Dynamic nonzero parents are rejected before construction. Category-zero capacity remains finite.

{{% /api-card %}}

{{% api-card %}}

### Custom native components

`NewComponent(nativeType, parent, options)`
: Constructs a native component with the inherited policy and fresh ID checks. The optional **options** table accepts **categoryID = "auto"** for a standalone opt-in.

`BuildCategoryGroup(parent, count, builder)`
: Reserves **1..235** contiguous nonzero IDs. Calls **builder(new)**; create exactly **count** components with **new(nativeType, dynamicParent)**. Group-created components pass auto allocation to ordinary PrettyUI descendants.

`WithCategoryBatch(parent, callback)`
: Supplies **callback(build)** with **build(count, builder)** for repeated groups. Active reservations remain protected during builder callbacks.

`RefreshComponentIDs(parent)`
: Reconciles cached occupancy after raw construction or deletion. Fresh collision checks do not require a manual refresh.

```lua
local row = prettyui.BuildCategoryGroup(window.content, 2, function(new)
    local root = new(ui.Layer, window.content)
    new(ui.Text, root)
    return root
end)
```

{{% /api-card %}}

{{% /api-grid %}}

{{% note %}}

Raw `ui.*.new` calls bypass PrettyUI's ID guards. Raw overflow, invalid explicit IDs, or raw children beneath managed nonzero controls can still crash the client. Use `NewComponent` or reserved groups for guarded custom construction; `pcall` cannot catch a native crash.

{{% /note %}}

{{% /doc-section %}}
