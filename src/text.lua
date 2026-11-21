local Components = require("src/core/components")
local Tooltip = require("src/tooltip")
local Layout = require("src/core/layout")
local Wheel = require("src/core/wheel")

local Text = {}

local DEFAULT_TEXT_COLOUR = 0xE7D7B0FF
local DEFAULT_TITLE_COLOUR = 0xF2C66DFF
local BODY_FONT = id.Font.MUSEO_SANS_15PT_REGULAR
local TITLE_FONT = id.Font.CINZEL_13PT_BOLD
local BODY_GAP = 2
local TITLE_GAP = 8
local TITLE_MARGIN_TOP = 16
local BODY_LINE_HEIGHT = 18
local TOOLTIP_HOVER = { followCursor = true }

local function fontConfig(fontID, isTitle)
    if fontID ~= nil and config.Font.FromID ~= nil then
        local succeeded, font = pcall(function() return config.Font.FromID(fontID) end)
        if succeeded and font ~= nil then return font end
    end
    return isTitle and config.Font.CINZEL_13PT_BOLD or config.Font.MUSEO_SANS_15PT_REGULAR
end

local function lineHeight(font, options)
    if options.lineSpacing ~= nil and options.lineSpacing > 0 then return options.lineSpacing end
    local succeeded, baseline = pcall(function() return font.baseline end)
    if succeeded and baseline ~= nil then return baseline end
    return BODY_LINE_HEIGHT
end

local function create(parent, options, isTitle)
    options = options or {}
    local width = options.width or 0
    local widthAnchor = options.widthAnchor
    if widthAnchor == nil then widthAnchor = width <= 0 and 1.0 or 0 end

    local label = Components.new(ui.Text, parent, options)
    label:SetPos(
        options.x or 0,
        options.y or 0,
        options.xAnchor or 0,
        options.yAnchor or 0
    )
    label:SetSize(
        width,
        options.height or (isTitle and 28 or 24),
        widthAnchor,
        options.heightAnchor or 0
    )
    label.content = options.text or ""
    label.font = options.font or (isTitle and TITLE_FONT or BODY_FONT)
    label.rgba = options.colour or (isTitle and DEFAULT_TITLE_COLOUR or DEFAULT_TEXT_COLOUR)
    label.isShadowed = options.shadowed ~= false
    label.alignHorizontal = options.alignHorizontal or ui.AlignMode.TOPLEFT
    label.alignVertical = options.alignVertical or ui.AlignMode.CENTRE
    label.maxLines = options.maxLines or 0
    if options.lineSpacing ~= nil then label.lineSpacing = options.lineSpacing end
    if options.tooltip ~= nil then label.enabled = true end
    Wheel.bind(label, options)
    Tooltip.attach(label, parent, options.tooltip, TOOLTIP_HOVER)

    return label
end

local function textOptions(value)
    if type(value) ~= "table" then return { text = tostring(value or "") } end

    local copy = {}
    for key, option in pairs(value) do copy[key] = option end
    return copy
end

function Text._bindWrapping(label, options, isTitle, paused, onHeight)
    local measuredWidth, measuredText
    local function refresh()
        if paused() then return true end
        local width = math.max(1, label.width)
        local text = label.content
        if width == measuredWidth and text == measuredText then return true end
        local font = fontConfig(label.font, isTitle)
        local succeeded, count = pcall(function()
            return font:GetStringLineCount(text, width, false, false, false)
        end)
        if not succeeded then return true end
        measuredWidth, measuredText = width, text
        if label.maxLines > 0 then count = math.min(count, label.maxLines) end
        local spacing = lineHeight(font, options)
        local glyphHeight = (font.maxAscent or spacing) + (font.maxDescent or 0)
        local height = math.max(isTitle and 28 or 24, (count - 1) * spacing + glyphHeight + 6)
        -- Cache before resizing: height and scrollbar changes can trigger ONRESIZE again.
        onHeight(height)
        return true
    end
    label:Subscribe(ui.Hook.ONRESIZE, "prettyui_text_wrap", refresh)
    refresh()
    return refresh
end

function Text.append(owner, value, isTitle)
    local options = textOptions(value)
    options.text = tostring(options.text or "")
    local autoHeight = options.height == nil and (options.heightAnchor or 0) == 0
    -- Block titles own their row; inline controls belong to the content below.
    options._flowBreakAfter = isTitle and options.inline ~= true
    if options.width == nil and (not isTitle or options.inline == true) then
        local font = fontConfig(options.font, isTitle)
        local succeeded, width = pcall(function() return font:GetStringWidth(options.text, false) end)
        width = (succeeded and width or #options.text * 7) + 4
        if options.inline == true then
            options.width = width
        else
            -- Keep the wrapping box full-width, but advance inline controls past
            -- the text rather than treating its anchored width as zero.
            options._flowWidth = width
        end
    end
    options = Layout.place(owner, options, {
        height = isTitle and 28 or 24,
        fillWidth = true,
        gap = isTitle and TITLE_GAP or BODY_GAP,
        marginTop = isTitle and TITLE_MARGIN_TOP or 0,
    })
    local label = Layout.manage(owner, create(owner.content, options, isTitle), options)
    if autoHeight then
        options._remeasure = Text._bindWrapping(
            label,
            options,
            isTitle,
            function() return owner._destroyingManagedFlow end,
            function(height) Layout.resize(owner, label, height) end
        )
    end
    return label
end

function Text.new(parent, options)
    return create(parent, options, false)
end

function Text.title(parent, options)
    return create(parent, options, true)
end

return Text
