---
title: "Window"
weight: 6
---

{{% doc-section %}}

## Window {#window-api}

```lua
local gameArea = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)

local settingsWindow = prettyui.Window.new(gameArea, {
    categoryID = "auto",
    title = "Plugin settings",
    x = -210,
    y = -150,
    xAnchor = 0.5,
    yAnchor = 0.5,
    width = 420,
    height = 300,
    resizable = true,
    minWidth = 320,
    minHeight = 220,
    maxWidth = 900,
    maxHeight = 700,
    scrollable = true,
    rowBackgroundColours = {
        0x24211EFF,
        0x2E2825FF,
    },
    onClose = function(window)
        saveSettings()
    end,
})

settingsWindow:AddTitle("Display")
settingsWindow:AddText("Configure the interface below.")
settingsWindow:RefreshRowBackgrounds()

settingsWindow:SetTitle("Updated settings")
settingsWindow:SetSize(460, 320)
settingsWindow:Show()

-- Hide the window and invoke onClose.
settingsWindow:Close()

-- Destroy it during plugin shutdown.
settingsWindow:Destroy()
```

{{% api-grid %}}

{{% api-card %}}

### Construction

{{< signature compact="true" >}}
Window.new(parent, options)
{{< /signature >}}

Creates an independent window state object.

Window content is vertically scrollable by default. Its scrollbar remains hidden
and leaves the full content width available until managed content exceeds the
viewport height.

Titled windows can be moved by dragging their title bar. Their position stays
within the parent when their dimensions permit and is retained proportionally
when the parent is resized.
Interactive resizing is opt-in with `resizable = true`.

`categoryID`
: Optional **"auto"** allocation for the window's component tree. See
  [Component IDs](#component-ids).

`title`
: Optional string. Omitting it switches to the plain top border.

`x`, `y`
: Initial position in interface units.

`xAnchor`, `yAnchor`
: Optional offsets based on the parent's dimensions. To centre a fixed-size
  window, use **0.5** for both anchors and negative half-width/half-height for
  **x** and **y**.

`width`, `height`
: Initial dimensions.

`resizable`
: Enables interactive resizing from all four edges and four corners. Defaults
  to false.

`minWidth`, `minHeight`
: Lower bounds used by interactive resizing and `SetSize`. Defaults to 220 ×
  140 interface units.

`maxWidth`, `maxHeight`
: Optional upper bounds used by interactive resizing and `SetSize`.

`onClose`
: Callback receiving the window object.

`onPositionChange`
: Receives **(window, x, y)** once after a completed drag changes position.
  Coordinates are parent-relative interface units. Programmatic moves and
  cancelled drags do not notify. To persist, save **x** and **y** and restore
  them as constructor options without **xAnchor** or **yAnchor**.

`destroyOnClose`
: Destroy instead of hide when true.

`useNativeTransparency`
: Makes the window match the player's native interface transparency setting.
  Defaults to false.

`respectInterfaceLock`
: Stops the window from being moved or resized while the player's interface is
  locked. Defaults to true.

`scrollable`
: Enables automatic vertical scrolling. Defaults to true.

`scrollStep`
: Interface units moved per wheel delta. Defaults to 32.

`contentHeight`
: Optional initial content height for raw or manually positioned children.
  Content added with **Add…** helpers is measured automatically.

`rowBackgroundColours`, `rowBackgroundColors`
: Alternates row background colours to match native settings panels. See
  [Row backgrounds](#row-backgrounds).

`rowBackgroundEdgeToEdge`
: Extends the backgrounds to the content edges. Defaults to false.

{{% /api-card %}}

{{% api-card %}}

### Methods and fields

`content`
: Layer used as the parent for consumer UI.

`viewport`
: Clipped layer that owns **content**.

`scrollbarVisible`
: True while content exceeds the viewport and **scrollable** is enabled.

`scrollY`, `contentHeight`, `contentWidth`
: Current scroll position and measured content dimensions.

`SetScrollable(value)`
: Enables or disables scrolling. Disabling resets the viewport to the top and restores the full content width.

`SetScrollPosition(y)`, `ScrollBy(delta)`
: Moves the viewport to an absolute or relative vertical position.

`ScrollToChild(child, topOffset)`
: Scrolls to a direct content child with an optional top offset.

`SetContentHeight(height)`
: Updates overflow detection for raw content not managed through **Add…**
  helpers.

`RefreshRowBackgrounds()`
: Rebuilds row backgrounds after content or layout changes. Call it after
  adding, removing, or repositioning managed children.

`SetSize(width, height)`
: Changes dimensions programmatically, subject to the configured minimum and
  maximum dimensions.

`SetTitle(title)`
: Updates an existing title label.

`SetUseNativeTransparency(enabled)`
: Changes **useNativeTransparency**. Turning it off makes the background opaque.

`SetRespectInterfaceLock(enabled)`
: Changes **respectInterfaceLock**. Turning it off unlocks the window.

`Show()`
: Shows and raises the window.

`Close()`
: Hides tooltips belonging to the window and its nested panels, invokes
  **onClose**, then hides or destroys the window.

`Destroy()`
: Destroys the complete component tree.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
