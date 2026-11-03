---
title: "Dialog"
weight: 31
---

{{% doc-section %}}

## Dialog {#dialog-api}

A centred window with custom content and footer actions. Dialogs stack separately for each parent component.

{{< signature >}}
Dialog.new(parent, options)
{{< /signature >}}

{{% api-grid compact="true" %}}

{{% api-card %}}

### Options

`title`
: Window title. Defaults to an empty string.

`width`, `height`
: Defaults to **328 × 150**. Width grows when needed to fit the footer actions.

`modal`
: Defaults to **true**. Dims the parent and blocks interaction behind the dialog.

`content(window)`
: Called once to populate the underlying [Window](#window-api) using its `Add…` methods.

`actions`
: Array of footer actions, ordered left to right. Defaults to no actions.

`onDismiss()`
: Called by the window close button, not by footer actions or `Destroy()`. Its return value does not prevent closing.

{{% /api-card %}}

{{% api-card %}}

### Actions

`label`
: Button text.

`variant`
: **neutral** (default), **positive**, or **negative**.

`disabled`, `tooltip`
: Initial disabled state and [tooltip](#tooltip-api).

`onClick()`
: Return **true** to close the dialog; any other return keeps it open. Omitting the callback closes it immediately when clicked.

{{% /api-card %}}

{{% api-card %}}

### Methods and fields

`window`
: Underlying Window controller.

`Destroy()`
: Removes the dialog from its stack and destroys its window without invoking callbacks.

`Dialog.depth(parent)`
: Returns the number of open dialogs for the parent.

`Dialog.dismissAll(parent)`
: Destroys all dialogs for the parent without invoking callbacks.

`Dialog.Shutdown()`
: Destroys all dialogs. Called automatically when PrettyUI shuts down.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
