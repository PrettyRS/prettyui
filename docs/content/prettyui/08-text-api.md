---
title: "Text"
weight: 8
---

{{% doc-section %}}

## Text {#text-api}

Body text uses Museo Sans and titles use Cinzel by default. Pass an `id.Font` value to override the font.

```lua
local heading = window:AddTitle("A Cinzel heading")
local description = window:AddText("Readable body copy")

window:AddText({
    text = "A customized row",
    colour = 0xAFA27FFF,
    marginTop = 12,
})
```

{{% api-grid compact="true" %}}

{{% api-card %}}

### Constructors

`Text.new(parent, options)`
: Creates body text at an explicit layout, using Museo Sans by default.

`Text.title(parent, options)`
: Creates a title at an explicit layout, using Cinzel by default.

`AddText(value)`
: Appends body text to any flow container. Pass a string or an options table.

`AddTitle(value)`
: Appends a title with automatic section spacing.

{{% /api-card %}}

{{% api-card %}}

### Options

`text`
: Displayed string. The entire value may be a string for defaults.

`marginTop`, `marginBottom`
: Overrides automatic flow spacing.

`colour`
: RGBA colour value.

`font`
: An **id.Font** value overriding the default body or title font.

`shadowed`
: Set false to disable the default shadow.

`x`, `y`, `width`, `height`
: Optional layout overrides.

{{% /api-card %}}

{{% /api-grid %}}

{{% /doc-section %}}
