---
title: "Confirm"
weight: 32
---

{{% doc-section %}}

## Confirm {#confirm-api}

A [Dialog](#dialog-api) with body text and cancel/confirm buttons. Returns a Dialog controller with the same fields and methods.

{{< signature >}}
Confirm.new(parent, options)
{{< /signature >}}

{{% api-grid compact="true" %}}

{{% api-card %}}

### Options

`title`
: Defaults to **CONFIRM**.

`body`
: Body text. Defaults to an empty string.

`width`, `height`, `modal`
: Same as Dialog, including defaults and automatic footer sizing.

`cancelLabel`, `confirmLabel`
: Defaults to **CANCEL** and **CONFIRM**.

`confirmVariant`
: **positive** (default), **neutral**, or **negative**. The cancel button uses **neutral**.

{{% /api-card %}}

{{% api-card %}}

### Callbacks

`onConfirm()`
: Called by the confirm button. Return **false** to keep the dialog open; any other return closes it. Without a callback, the button closes it.

`onCancel()`
: Called by the cancel button with the same return rules as `onConfirm`. Also called by the window close button, which closes regardless of the return value.

`Destroy()` and `Dialog.dismissAll(parent)` do not invoke either callback.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
