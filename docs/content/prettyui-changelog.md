---
title: PrettyUI Changelog
description: PrettyUI release history and upcoming changes.
navigation: changelog
brandTitle: PrettyUI
brandSubtitle: By J3
brandHref: index.html
docsHref: index.html
changelogHref: prettyui-changelog.html
bodyClass: changelog
contentLayout: changelog
aliases:
  - /changelog.html
hero:
  eyebrow: Release history
  title: Changelog
  lede: Notable changes to PrettyUI.
  actionHref: index.html
  actionText: Back to documentation
  compact: true
---

## Unreleased {#unreleased}

### Added

- Added `Hide()` to [windows](index.html#window-api), which hides the window without invoking `onClose`.
- Added `Hide()`, `Show()` and `Close()` methods and `onClose` and `destroyOnClose` options to [panels](index.html#panel-api).
- Added snapping to [windows](index.html#window-api), on by default. While being dragged, windows snap to other PrettyUI windows, the game's own interfaces that use snapping, and the screen edges. Set `snapToEdges = false` to opt out.
- Added `Refresh()` to [sliders](index.html#slider-api), which can update the marker's position again after the slider's width changes.


### Fixed
- Improved hover feedback on keybind fields and restored the missing clear sprite for resetting keybinds.
- [Windows](index.html#window-api) can now be positioned visually flush against the edges of their parents.
- [Slider](index.html#slider-api) markers now move with the track when the window or panel holding them is resized.
- Nested panels' content now resizes when the parent being resized causes the panel to be resized.
- Nested Panels are linked to their parent again, which 1.3.0 had broken.

## 1.3.0 (published, awaiting approval) {#v1-3-0}

### Added

- Added [overhead bars](index.html#overhead-bar-api) API that can be used to attach health-bar-like overlays to NPCs, players, or Locs.
- Added optional `onPositionChange(window, x, y)` and `onPositionChange(panel, x, y, poppedOut)` callbacks to be used for persisting component positions. These callbacks fire once the user stops their drag action on the targeted component.
- Added [automatic component IDs](index.html#component-ids) with the root option `categoryID = "auto"`.
- Added `NewComponent`, `RefreshComponentIDs`, `BuildCategoryGroup`, and `WithCategoryBatch` for custom native construction.
- Added `hideCloseButton` as a option to windows and dialogs. 
- Added a `useNativeTransparency` option to [windows](index.html#window-api) and [panels](index.html#panel-api), with a matching `SetUseNativeTransparency(enabled)` method, which when enabled makes them follow the player's native interface transparency setting.
- Added an editable hex colour code caption beneath the [colour picker](index.html#colour-picker-api) preview.

### Changed
- Dialog Component: Dialog footer actions can now be set to `Disabled`
- [Windows](index.html#window-api) and [panels](index.html#panel-api) can no longer be moved or resized while the player's interface is locked. To keep a component movable, set `respectInterfaceLock = false` or call `SetRespectInterfaceLock(false)`.
- Tooltip UI objects (`root`, `label`, frame sprites) are now built on first `Show()` or first access, not in `Tooltip.attach`.
- `Tooltip:Hide()` releases those objects, and the next `Show()` rebuilds them. Tooltips with a custom `onMouseLeave` handler stay built.
- `Tooltip.__index` is now a function, not the `Tooltip` table.
- Hovering over edges of resizable surfaces now shows a feedback cursor when a resize action can be performed.
-  The drag area for corners on rsizable surfaces has been widened to make it easier to grab onto them.


### Fixed
* Minimenu API: Optimized to reduce the amount of reads of `miniMenu.entries` and fixed misalignment issues when multiple plugins are using the API simultaneously.
* `Tabs:SetActive` now hides tooltips on pages it deactivates, so they no longer stay visible after a tab switch.
* Fixed an alignment issue on the close button for the window component.

- Corrected the default rotation direction of the `Spinner` component.

### Deprecated
- Omitting `categoryID` will emit a warning. In PrettyUI version 2 `categoryID = auto` behavior will become the default and this may break existing library consumers so it is important to migrate and test auto-allocated categoryIDs before the switch.


### Removed
- Removed previously deprecated  `RibbonBar` API
- Removed previously deprecated `ScrollBar` API

### Other
- We now ship a LuaLS addon along with our GitHub releases that can be used for language server integration for PrettyUI in your IDE of choice

### Credits
This version of PrettyUI contains changes from multiple community developers, a big thank you to:
- [Adam Keenan](https://github.com/adamk33n3r)
- [ash (sereselene)](https://github.com/CodeNameAshley)
- [CJ Fritz](https://github.com/cjfritz9)
- [Psymansayz](https://github.com/Psymansayz)
- [Keensta](https://github.com/keensta)

## 1.2.0 - 2026-10-12 {#v1-2-0}

### Added

- Added [MiniMenu submenus](index.html#minimenu-submenu-api) this mimicks the OSRS submenu behavior with fold-out submenus that appear when hovering a parent entry.

## 1.1.0 - 2026-10-12 {#v1-1-0}

### Added

- Added [KeybindField](index.html#keybind-field-api) for one-key and two-key bindings, with capture, clearing, reset values, and paired panel support.
- Added opt-in edge and corner resizing for [windows](index.html#window-api) and [panels](index.html#panel-api), including minimum and maximum dimensions.

### Changed

- `Spinner` now defaults to the 72 × 72 rotating indicator. It accepts `rotation` and `degreesPerLogicUpdate`; `SetFrame()`, `SetLogicUpdatesPerFrame()`, and `logicUpdatesPerFrame` are removed. `BigSpinner` and `AddBigSpinner()` remain aliases for the rotating spinner.
- `TextField` now defaults `maxLength` to 9999.
- [Colour picker](index.html#colour-picker-api) popups now open beside their swatch, flip above it when needed, and default to 312 pixels high (348 with `alphaSlider`).
- Dividers are excluded from alternating row backgrounds unless `rowBackground = true`.
- Kept tooltip, inline placement, and join-previous-row controls visible in the visual editor inspector, and made the palette and inspector scroll independently within the viewport-height workspace.
- Holding Alt over a standalone panel now shows the move cursor on its draggable area, matching window title bars.
- Exposed window resize and close callback, plus nested and standalone panel resize, pop-out, and pop-out callback options without opening the inspector's Layout & appearance section.

### Fixed

- Kept draggable windows and panels within their parent when their dimensions permit, including after parent resizing.
- Refreshed alternating row backgrounds when adding a slider.
- Kept overlapping editor windows and standalone surfaces in their canvas stacking order, so a lower window's header cannot cover a surface above it.


## 1.0.0 - 2026-09-29 {#v1-0-0}

### Added

- Added [Dialog](index.html#dialog-api) with custom content, configurable footer actions, per-parent modal stacking, and automatic width expansion to fit its actions.
- Added [Confirm](index.html#confirm-api) with body text, configurable buttons, and confirm/cancel callbacks that can keep the dialog open.
- Added opt-in `resizeParent` support to [collapse sections](index.html#collapse-button-api) to automatically fit the parent container's height when a section expands or collapses.

### Deprecated

- Deprecated `RibbonBar` in favour of the native plugin UI. Use `"hasRibbonIcon": true` in your manifest and mount controls in [ContentLayer](index.html#content-layer), or use [SettingsLayer](index.html#settings-layer) for settings. Remove `RibbonBar.Register` calls and their handle updates and teardown; registrations now emit a deprecation warning.

### Fixed

- Fixed stale content height and scrollbar overflow after collapsing the last flow row, and preserved taller inline neighbours during reflow.
- Fixed collapse sections becoming out of sync between a panel's docked and pop-out views.
- Fixed text and title tooltips not appearing on hover; their tooltips now follow the cursor.
- Fixed the shared ribbon bar leaving an empty surface after its last entry is removed.

## 0.7.1 - 2026-08-18 {#v0-7-1}

### Fixed

- Added parent interface teardown guards on logout to prevent client crashes

## 0.7.0 - 2026-08-08 {#v0-7-0}

### Added

- Added various graph components: `TimeGraph`, `BarChart`, and `Histogram`. See the [Graphs API](index.html#graphs) for details.
- Added [`Sprite`](index.html#sprite-api) API to easily insert flow-managed images/sprites into windows, panels, and tab pages.

### Fixed

- Fixed various small layout flow issues

## 0.6.0 - 2026-07-29 {#v0-6-0}


### Added

- Added optional alternating row backgrounds to windows, panels, and tab pages with `rowBackgroundColours`/`rowBackgroundColors`, `rowBackgroundEdgeToEdge`, and `RefreshRowBackgrounds()`.
- Added `rowBackgroundGroup` to merge consecutive managed rows into one background region.
- Added per-entry `List` colour overrides for the row background.
- Tab pages now support flow-managed panels and nested tab groups through `AddPanel` and `AddTabs`.
- Radio and checkbox groups now lay out their choices side by side when `inline = true`.
- Added `rowBackground = false` for controls that should leave their flow row outside the host's alternating backgrounds.
- Added a `disabled` state to itemslots

### Changed

- Buff and debuff tooltips now show after a brief delay to match the native buff behavior.
- Changed scrollbar sprites to use the more general variant that is more commonly seen in native UIs

### Fixed

- Fixed ComboBox entry IDs and programmatic selections being mismatched when restoring a requested entry on plugin reload.
- Fixed closing a reusable window leaving tooltips from its content or nested panels visible.
- Fixed an issue where the scrollbar thumb would rubber band when initiating a drag action.

### Removed

- Removed the `Draw` API because world-drawing helpers are outside PrettyUI's UI scope.

## 0.5.0 - 2026-07-28 {#v0-5-0}

### Added

- Added a new `Draw` API namespace intended for shape api helpers. Currently this exposes a new `Draw.Tile(options)` for generic tile markers that can be attached to terrain tiles, NPCS, object-stacks or players.

## 0.4.1 - 2026-07-27 {#v0-4-1}

### Added

- Added universal `SetTooltip(value)` lifecycle methods to tooltip-enabled PrettyUI components and handles, plus `SetText(text)` on mouseover and text-based anchored tooltip attachments.
- Added `SetObject(objId)` and `SetSprite(spriteID)` to BuffBar handles for changing or clearing sprites or Obj references without recreating the entry.

### Fixed

- `TextField` caret and text are now better aligned to the background sprites.
- Reduced drag-related client overhead to reduce resource usage.
- Fixed parent-anchored tab pages applying an incorrect minimum height.

## 0.4.0 - 2026-07-26 {#v0-4-0}

### Added

- Added an optional alpha slider to `ColourPicker`, enabled with `alphaSlider = true`.
- Added `SimpleView`, an unstyled standalone content host using the shared scroll and flow behavior.
- Added shared `SetScrollable`, `SetScrollPosition`, `ScrollBy`, and `SetContentHeight` methods to scrollable content hosts.

### Changed

- Lowered the default title font size from `CINZEL_18PT_BOLD` to `CINZEL_13PT_BOLD` to better align with what native UI does.
- Windows, panels, and tab pages are now vertically scrollable by default. Their scrollbar remains hidden until managed content overflows.
- `Scrollbar` has been deprecated and renamed to `SimpleView`, the  `Scrollbar` alias will be removed in v1.0.0. For most implementations 
the use of `SimpleView` is no longer necessary, as windows, panels, and tab pages now scroll by default. Use `SimpleView` when content needs an unstyled host without a window or panel frame.

### Fixed

- Mouse dragging targets now correctly remain aligned with the pointer when OS display scaling is enabled.
- Text tabs have now got their minimum width capped to the width of the sprites to prevent clipping when the tab text is too short.

## 0.3.0 - 2026-07-25 {#v0-3-0}

### Added

- Added `BuffBar` API, this should make it easy to add custom buffs to the buff and debuff bars leaving positioning management to the prettyUI library.

### Changed

- Moved Add... method definitions into a shared method vendor to avoid repetition between components.

### Fixed

- Removed unintentional hover interaction from selection preview in `ColourPicker` component.
- Fixed an oversight in the layout manager not reclaiming empty rows when components are destroyed.
- Drag handlers now correctly account for interface scaling when determining the mouse position.

## 0.2.0 - 2026-07-24 {#v0-2-0}

### Added

- Added `ColourPicker` component.

### Changed

- Changed the default font size of window titles from 18pt to 13pt.

### Fixed

- Fixed the scrollbar thumb dragging losing connection when the pointer leaves the scrollbar parent.

## 0.1.1 - 2026-07-24 {#v0-1-1}

### Fixed

- Fixed dragging for windows, slider thumbs, and scrollbar handles when the pointer leaves the original drag target.
- Fixed Alt-dragging for panels.

## 0.1.0 - 2026-07-23 {#v0-1-0}

### Added

- Initial release.
