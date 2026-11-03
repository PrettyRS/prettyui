---
title: "Collapse button"
weight: 12
---

{{% doc-section %}}

## Collapse button {#collapse-button-api}

An expandable header with an indented content region that reflows following components.

{{< signature >}}
CollapseButton.new(parent, text, options)
{{< /signature >}}

```lua
local section = window:AddCollapseButton("Actions", {
    expanded = false,
    resizeParent = true,
    onToggle = function(self, expanded)
        log(expanded and "Opened" or "Closed")
    end,
})

section:AddText("Choose an action below.")
section:AddSimpleButton("Short", firstAction)
section:AddSimpleButton("A much longer action", secondAction)
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### Options

`expanded`
: Sets the initial open state.

`resizeParent`
: Fits the immediate PrettyUI content host vertically as the section is populated,
  opened, or closed. Defaults to **false**, preserving the host's fixed size and
  scrolling. Width is unchanged.

`disabled`
: Blocks interaction when true.

`indent`
: Controls the content inset.

`onToggle(section, expanded)`
: Runs after the open state changes and any parent resizing completes.

`colour`, `disabledColour`, `hoverCursor`, `shadowed`, `tooltip`
: Customize presentation and interaction.

{{% /api-card %}}

{{% api-card %}}

### Content and control

`AddText`, `AddSimpleButton`, `AddFancyButton`
: Add flow-managed content to the expanded region.

`AddTextField`, `AddComboBox`, `AddList`
: Add full-width field controls.

Button widths
: Textual buttons in one section equalize to the widest button.

`SetExpanded(expanded)`
: Opens or closes the content, reflows following items, and fits the parent when
  **resizeParent** is enabled.

`Toggle()`
: Switches the open state.

`SetDisabled`, `SetHoverCursor`, `SetText`
: Update the header at runtime.

{{% /api-card %}}

{{% /api-grid %}}

### Parent resizing

With `resizeParent = true`, fitting includes all measured content in the immediate
host, layout padding, and its borders/title bar. It removes unused vertical space
rather than preserving the original height. Initially expanded sections also fit
as their content is added.

- **Windows** respect `minHeight` (140 by default) and `maxHeight`. Content exceeding
  the maximum remains scrollable when scrolling is enabled.
- **Panels** resize both docked and pop-out surfaces, keeping the section's open
  state synchronized.
- **Simple views** resize their viewport.
- **Tab pages** resize their tab container and reflow its following siblings,
  without resizing ancestor windows or panels.

{{% note %}}

Use the host's **AddCollapseButton** helper so the section is bound to its content
layout. A directly constructed **CollapseButton.new** without a flow owner does
not resize its raw native parent.

{{% /note %}}

{{% /doc-section %}}
