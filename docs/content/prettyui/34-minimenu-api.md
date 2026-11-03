---
title: "MiniMenu submenus"
weight: 34
---

{{% doc-section %}}

## MiniMenu submenus {#minimenu-submenu-api}

Add a custom MiniMenu parent whose child actions open in a sprite-backed submenu on hover. PrettyUI places the submenu on the right when it fits, otherwise on the left, and keeps it within the viewport.

{{< signature >}}
MiniMenu.AddSubmenu(miniMenu, label, children, options?) -> MiniMenuEntry
{{< /signature >}}

```lua
Event.MiniMenuReady.Subscribe("my_plugin_menu", function(event)
    prettyui.MiniMenu.AddSubmenu(event.miniMenu, "Marker options", {
        {
            label = "Add marker",
            action = addMarker,
            arguments = { "red" },
        },
        {
            label = "Remove marker",
            action = removeMarker,
        },
    }, {
        title = "Marker options",
        position = "top",
    })
end)
```

Call `AddSubmenu` only with the writable `miniMenu` supplied by **Event.MiniMenuReady**. It adds the parent entry immediately and returns that `MiniMenuEntry`; later `MiniMenu:Swap` calls during the same Ready event can reorder it without breaking the submenu association.

{{% api-grid compact="true" %}}

{{% api-card %}}

### Child entries

`label`
: Required nonempty text displayed in the submenu.

`action`
: Required function called when the child is selected.

`arguments`, `args`
: Optional array passed to `action` with `table.unpack`. `arguments` takes precedence when both names are present.

Supply an array of child entries. Children display in array order. When they exceed the available viewport height, use the mouse wheel over the submenu to reach the remaining entries.

{{% /api-card %}}

{{% api-card %}}

### Options

`title`
: Submenu header text. Defaults to **Choose Option**.

`parentAction`
: Function called if the native parent entry itself is selected. Defaults to a no-op; child actions remain independent.

`arrow`
: Appends the native white **>** direction marker to the parent label unless set to **false**.

`position`
: Parent entry placement. **"top"** places the parent directly below the highest-priority native entry so it never becomes the default left-click action. **"bottom"** places it directly above **Cancel** and is the default. An integer of 2 or greater selects that 1-based visible row from the top; positions that would reach or pass **Cancel** clamp to the row directly above it. Visible row 1 and the final Cancel row are reserved for native entries.

{{% /api-card %}}

{{% /api-grid %}}


{{% /doc-section %}}
