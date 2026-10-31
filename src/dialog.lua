local Window = require("src/window")
local FancyButton = require("src/fancy_button")
local Components = require("src/core/components")

local Dialog = {}
Dialog.__index = Dialog

local DEFAULT_WIDTH = 328
local DEFAULT_HEIGHT = 150
local ACTION_GAP = 10
local ACTION_PAD = 10
local ACTION_Y = -35
local DIM_ALPHA = 0.4
local WINDOW_BORDER = 8

local stacks = {}
local chrome = {}

local function resolve(options)
    options = options or {}
    return {
        title = options.title or "",
        width = options.width or DEFAULT_WIDTH,
        height = options.height or DEFAULT_HEIGHT,
        modal = options.modal ~= false,
        content = options.content,
        actions = options.actions or {},
        onDismiss = options.onDismiss,
    }
end

local function stackOf(parent)
    local stack = stacks[parent]
    if stack == nil then
        stack = {}
        stacks[parent] = stack
    end
    return stack
end

function Dialog.depth(parent)
    local stack = stacks[parent]
    if stack == nil then return 0 end
    return #stack
end

local function destroyLayer(layer)
    if layer == nil then return end
    layer:Destroy()
end

local function destroyChrome(parent)
    local existing = chrome[parent]
    if existing == nil then return end
    chrome[parent] = nil
    destroyLayer(existing.blocker)
    destroyLayer(existing.dim)
end

local function ensureChrome(parent)
    local existing = chrome[parent]
    if existing ~= nil then return existing.dim, existing.blocker end

    local dim = Components.new(ui.Layer, parent)
    dim:SetPos(0, 0)
    dim:SetSize(0, 0, 1.0, 1.0)
    dim.clickthrough = false

    local rect = Components.new(ui.Rectangle, dim)
    rect.fill = true
    rect.clickthrough = false
    rect:SetPos(0, 0)
    rect:SetSize(0, 0, 1.0, 1.0)
    rect.colour = Vector4.new(0, 0, 0, DIM_ALPHA)

    local blocker = Components.new(ui.Layer, parent)
    blocker:SetPos(0, 0)
    blocker:SetSize(0, 0, 1.0, 1.0)
    blocker.clickthrough = false

    local hit = Components.new(ui.Rectangle, blocker)
    hit.fill = true
    hit.clickthrough = false
    hit:SetPos(0, 0)
    hit:SetSize(0, 0, 1.0, 1.0)
    hit.colour = Vector4.new(0, 0, 0, 0)

    chrome[parent] = { dim = dim, blocker = blocker }
    return dim, blocker
end

local function raise(component)
    if component == nil then return end
    if component.Show ~= nil then
        component:Show()
        return
    end
    component:MoveToFront()
end

local function syncChrome(parent)
    local stack = stacks[parent]
    if stack == nil or #stack == 0 then
        stacks[parent] = nil
        destroyChrome(parent)
        return
    end

    local anyModal = false
    for _, frame in ipairs(stack) do
        if frame.options.modal then
            anyModal = true
            break
        end
    end

    local top = stack[#stack]
    local dim, blocker
    if anyModal then
        dim, blocker = ensureChrome(parent)
    else
        destroyChrome(parent)
    end

    raise(dim)
    for index = 1, #stack - 1 do
        raise(stack[index].window)
    end
    if top.options.modal then raise(blocker) end
    raise(top.window)
end

local function pop(frame, skipDestroy)
    if frame.closed then return end
    frame.closed = true

    local parent = frame.parent
    local stack = stacks[parent]
    if stack ~= nil then
        for index = #stack, 1, -1 do
            if stack[index] == frame then
                table.remove(stack, index)
                break
            end
        end
    end

    if not skipDestroy and frame.window ~= nil then
        frame.window.onClose = nil
        frame.window:Destroy()
    end
    syncChrome(parent)
end

function Dialog.dismissAll(parent)
    if parent == nil then return end
    local stack = stacks[parent]
    if stack == nil then return end
    while #stack > 0 do
        pop(stack[#stack], false)
    end
end

function Dialog.Shutdown()
    local parents = {}
    for parent in pairs(stacks) do
        parents[#parents + 1] = parent
    end
    for _, parent in ipairs(parents) do
        Dialog.dismissAll(parent)
    end
end

local function footerWidth(actions)
    if actions == nil or #actions == 0 then return 0 end
    local total = ACTION_PAD * 2
    for index, action in ipairs(actions) do
        if index > 1 then total = total + ACTION_GAP end
        total = total + FancyButton.getSize(action.label or "")
    end
    return total
end

local function resolveWindowWidth(options)
    local footer = footerWidth(options.actions) + WINDOW_BORDER * 2
    return math.max(options.width, footer)
end

local function bindAction(frame, slot)
    return function()
        if frame.closed or slot.disabled then return end
        if slot.action.onClick == nil or slot.action.onClick() == true then
            pop(frame, false)
        end
    end
end

local function mountActions(window, frame, actions)
    local slots = {}
    frame.actionSlots = slots
    local x = -ACTION_PAD
    for index = #actions, 1, -1 do
        local action = actions[index]
        local label = action.label or ""
        local width = FancyButton.getSize(label)
        x = x - width
        local slot = {
            action = action,
            disabled = action.disabled == true,
        }
        slots[action] = slot
        slot.button = window:AddFancyButton(label, bindAction(frame, slot), {
            variant = action.variant or "neutral",
            disabled = slot.disabled,
            tooltip = action.tooltip,
            xAnchor = 1,
            yAnchor = 1,
            x = x,
            y = ACTION_Y,
        })
        x = x - ACTION_GAP
    end
end

function Dialog.new(parent, options)
    if parent == nil then error("Dialog requires a parent component") end
    options = resolve(options)

    local self = setmetatable({
        parent = parent,
        window = nil,
        options = options,
        closed = false,
    }, Dialog)

    local width, height = resolveWindowWidth(options), options.height
    local window = Window.new(parent, {
        title = options.title,
        x = -math.floor(width / 2),
        y = -math.floor(height / 2),
        xAnchor = 0.5,
        yAnchor = 0.5,
        width = width,
        height = height,
        minWidth = width,
        minHeight = height,
        maxWidth = width,
        maxHeight = height,
        destroyOnClose = true,
        onClose = function()
            if self.closed then return end
            if options.onDismiss ~= nil then options.onDismiss() end
            pop(self, true)
        end,
    })

    self.window = window
    local dialog = self
    local innerDestroy = window.Destroy
    function window:Destroy()
        pop(dialog, true)
        innerDestroy(self)
    end

    local stack = stackOf(parent)
    stack[#stack + 1] = self
    if options.content ~= nil then
        options.content(window)
    end
    mountActions(window, self, options.actions)
    syncChrome(parent)
    return self
end

function Dialog:SetActionDisabled(action, disabled)
    local slot = self.actionSlots[action]
    if slot == nil then error("Dialog:SetActionDisabled: unknown action") end
    slot.disabled = disabled == true
    local button = slot.button
    if button ~= nil and button.SetDisabled ~= nil then
        button:SetDisabled(slot.disabled)
    end
end

function Dialog:Destroy()
    pop(self, false)
end

return Dialog
