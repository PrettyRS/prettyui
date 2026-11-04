local Dialog = require("src/dialog")

local Confirm = {}

local DEFAULT_TITLE = "CONFIRM"
local DEFAULT_CONFIRM_LABEL = "CONFIRM"
local DEFAULT_CANCEL_LABEL = "CANCEL"
local DEFAULT_CONFIRM_VARIANT = "positive"

local function resolve(options)
    options = options or {}
    return {
        title = options.title or DEFAULT_TITLE,
        body = options.body or "",
        cancelLabel = options.cancelLabel or DEFAULT_CANCEL_LABEL,
        confirmLabel = options.confirmLabel or DEFAULT_CONFIRM_LABEL,
        confirmVariant = options.confirmVariant or DEFAULT_CONFIRM_VARIANT,
        width = options.width,
        height = options.height,
        modal = options.modal ~= false,
        onConfirm = options.onConfirm,
        categoryID = options.categoryID,
        _categoryPolicy = options._categoryPolicy,
        onCancel = options.onCancel,
    }
end

function Confirm.new(parent, options)
    options = resolve(options)
    local body = options.body
    return Dialog.new(parent, {
        categoryID = options.categoryID,
        _categoryPolicy = options._categoryPolicy,
        title = options.title,
        width = options.width,
        height = options.height,
        modal = options.modal,
        onDismiss = function()
            if options.onCancel ~= nil then options.onCancel() end
        end,
        content = function(window)
            window:AddText(body)
        end,
        actions = {
            {
                label = options.cancelLabel,
                variant = "neutral",
                onClick = function()
                    if options.onCancel == nil then return true end
                    return options.onCancel() ~= false
                end,
            },
            {
                label = options.confirmLabel,
                variant = options.confirmVariant,
                onClick = function()
                    if options.onConfirm == nil then return true end
                    return options.onConfirm() ~= false
                end,
            },
        },
    })
end

return Confirm
