local Sprites = require("src/core/sprites")
local clamp = require("src/core/math").clamp

local Tooltip = {}

local BORDER_SIZE = 10
local PADDING_X = 8
local PADDING_Y = 5
local OFFSET = 6
local CURSOR_OFFSET = 12
local DEFAULT_MAX_WIDTH = 240
local FALLBACK_LINE_HEIGHT = 18
local TEXT_COLOUR = 0xFFFFFFFF
local HOOK_ID = "prettyui_tooltip"
local contexts = setmetatable({}, { __mode = "k" })

local function sprite(parent, spriteID)
    local component = ui.Sprite.new(parent)
    component.spriteID = spriteID
    component.clickthrough = true
    return component
end

local function normalize(value)
    if type(value) == "table" then return value end
    return { text = tostring(value or "") }
end

local function measure(text, options)
    local font = config.Font.MUSEO_SANS_15PT_REGULAR
    local maxWidth = options.maxWidth or DEFAULT_MAX_WIDTH
    local width = options.width
    if width == nil then
        local succeeded, textWidth = pcall(function() return font:GetStringWidth(text, false) end)
        width = math.min(maxWidth, (succeeded and textWidth or #text * 7) + PADDING_X * 2)
    end
    width = math.max(BORDER_SIZE * 2 + 1, width)

    local contentWidth = math.max(1, width - PADDING_X * 2)
    local height = options.height
    if height == nil then
        local succeeded, textHeight = pcall(function()
            return font:GetStringHeightAndLineCount(text, contentWidth, font.baseline, false, false, false)
        end)
        if succeeded then
            height = textHeight + PADDING_Y * 2
        else
            local lines = math.max(1, math.ceil((#text * 7) / contentWidth))
            height = lines * FALLBACK_LINE_HEIGHT + PADDING_Y * 2
        end
    end
    return width, math.max(BORDER_SIZE * 2 + 1, height)
end

local function placementOrder(preferred)
    if preferred == "left" then return { "left", "right", "below", "above" } end
    if preferred == "below" then return { "below", "above", "right", "left" } end
    if preferred == "above" then return { "above", "below", "right", "left" } end
    return { "right", "left", "below", "above" }
end

local function placedPosition(placement, targetX, targetY, targetWidth, targetHeight, width, height, offset)
    if placement == "left" then return targetX - width - offset, targetY end
    if placement == "below" then return targetX, targetY + targetHeight + offset end
    if placement == "above" then return targetX, targetY - height - offset end
    return targetX + targetWidth + offset, targetY
end

local function fitsParent(x, y, width, height, parentWidth, parentHeight, margin)
    return x >= margin and y >= margin and
        x + width <= parentWidth - margin and y + height <= parentHeight - margin
end

function Tooltip.getContext(collection)
    return contexts[collection]
end

function Tooltip.registerContext(collection, parent, position, parentContext)
    local context = {
        collection = collection,
        parent = parent,
        position = position,
        parentContext = parentContext,
        children = {},
        tooltips = {},
        active = true,
    }
    contexts[collection] = context
    if parentContext then table.insert(parentContext.children, context) end
    return context
end

local function destroyContext(context)
    if context == nil or not context.active then return end
    context.active = false
    contexts[context.collection] = nil
    for index = #context.children, 1, -1 do
        destroyContext(context.children[index])
    end
    for index = #context.tooltips, 1, -1 do
        context.tooltips[index]:Destroy()
    end
    context.children = {}
    context.tooltips = {}
    context.ownerWindow = nil
end

function Tooltip.unregisterContext(collection)
    destroyContext(contexts[collection])
end

local function moveContextTooltipsToFront(context)
    if context == nil or not context.active then return end
    for _, tooltip in ipairs(context.tooltips) do
        local parts = tooltip._parts
        if parts ~= nil and ui.Interfaces:GetInterface(tooltip.interfaceID) ~= nil
            and parts.root.hidden ~= true then
            parts.root:MoveToFront()
        end
    end
    for _, child in ipairs(context.children) do
        moveContextTooltipsToFront(child)
    end
end

function Tooltip.moveContextTooltipsToFront(collection)
    moveContextTooltipsToFront(contexts[collection])
end

local function hideContextTooltips(context)
    if context == nil or not context.active then return end
    for _, tooltip in ipairs(context.tooltips) do tooltip:Hide() end
    for _, child in ipairs(context.children) do hideContextTooltips(child) end
end

function Tooltip.hideContextTooltips(collection)
    hideContextTooltips(contexts[collection])
end

function Tooltip.bind(owner, target, parent, value, field)
    field = field or "tooltip"
    owner._tooltipBindings = owner._tooltipBindings or {}
    local binding = {
        target = target,
        parent = parent,
        targetInterfaceID = target.interfaceID,
        parentInterfaceID = parent.interfaceID,
        active = true,
    }
    owner._tooltipBindings[field] = binding
    owner[field] = Tooltip.attach(target, parent, value)
    return owner[field]
end

function Tooltip.set(owner, value, field)
    field = field or "tooltip"
    local bindings = owner and owner._tooltipBindings
    local binding = bindings and bindings[field]
    if binding == nil or not binding.active then return false end
    if ui.Interfaces:GetInterface(binding.targetInterfaceID) == nil
        or ui.Interfaces:GetInterface(binding.parentInterfaceID) == nil then return false end

    local attachment = owner[field]
    if attachment ~= nil and value ~= nil and type(value) ~= "table" then
        return attachment:SetText(value)
    end
    if attachment ~= nil then attachment:Destroy() end
    owner[field] = Tooltip.attach(binding.target, binding.parent, value)
    return true
end

function Tooltip.unbind(owner, field)
    field = field or "tooltip"
    local bindings = owner and owner._tooltipBindings
    local binding = bindings and bindings[field]
    if binding == nil or not binding.active then return false end

    binding.active = false
    local attachment = owner[field]
    if attachment ~= nil then attachment:Destroy() end
    owner[field] = nil
    bindings[field] = nil
    if next(bindings) == nil then owner._tooltipBindings = nil end
    return true
end

local function build(self)
    local parts = {}
    self._parts = parts
    parts.root = ui.Layer.new(self.parent)
    parts.root:SetSize(self.width, self.height)
    parts.root.hidden = true
    parts.root.clickthrough = true

    local frame = Sprites.CONTENT_FRAME

    parts.centre = sprite(parts.root, frame.centre)
    parts.centre:SetPos(BORDER_SIZE, BORDER_SIZE)
    parts.centre:SetSize(-BORDER_SIZE * 2, -BORDER_SIZE * 2, 1.0, 1.0)
    parts.centre.isTiling = true

    parts.top = sprite(parts.root, frame.top)
    parts.top:SetPos(BORDER_SIZE, 0)
    parts.top:SetSize(-BORDER_SIZE * 2, BORDER_SIZE, 1.0)
    parts.top.isTiling = true

    parts.bottom = sprite(parts.root, frame.bottom)
    parts.bottom:SetPos(BORDER_SIZE, -BORDER_SIZE, 0, 1.0)
    parts.bottom:SetSize(-BORDER_SIZE * 2, BORDER_SIZE, 1.0)
    parts.bottom.isTiling = true

    parts.right = sprite(parts.root, frame.right)
    parts.right:SetPos(-BORDER_SIZE, BORDER_SIZE, 1.0)
    parts.right:SetSize(BORDER_SIZE, -BORDER_SIZE * 2, 0, 1.0)
    parts.right.isTiling = true

    parts.left = sprite(parts.root, frame.left)
    parts.left:SetPos(0, BORDER_SIZE)
    parts.left:SetSize(BORDER_SIZE, -BORDER_SIZE * 2, 0, 1.0)
    parts.left.isTiling = true

    parts.topRight = sprite(parts.root, frame.topRight)
    parts.topRight:SetPos(-BORDER_SIZE, 0, 1.0)
    parts.topRight:SetSize(BORDER_SIZE, BORDER_SIZE)

    parts.topLeft = sprite(parts.root, frame.topLeft)
    parts.topLeft:SetSize(BORDER_SIZE, BORDER_SIZE)

    parts.bottomRight = sprite(parts.root, frame.bottomRight)
    parts.bottomRight:SetPos(-BORDER_SIZE, -BORDER_SIZE, 1.0, 1.0)
    parts.bottomRight:SetSize(BORDER_SIZE, BORDER_SIZE)

    parts.bottomLeft = sprite(parts.root, frame.bottomLeft)
    parts.bottomLeft:SetPos(0, -BORDER_SIZE, 0, 1.0)
    parts.bottomLeft:SetSize(BORDER_SIZE, BORDER_SIZE)

    parts.label = ui.Text.new(parts.root)
    parts.label:SetPos(PADDING_X, PADDING_Y)
    parts.label:SetSize(-PADDING_X * 2, -PADDING_Y * 2, 1.0, 1.0)
    parts.label.content = tostring(self.options.text or "")
    parts.label.font = id.Font.MUSEO_SANS_15PT_REGULAR
    parts.label.rgba = TEXT_COLOUR
    parts.label.maxLines = 0
    parts.label.clickthrough = true
end

local function release(self)
    if self._parts == nil then return end
    if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self._parts.root:Destroy() end
    self._parts = nil
end

local PARTS = {
    root = true, label = true, centre = true, top = true, bottom = true, left = true, right = true,
    topLeft = true, topRight = true, bottomLeft = true, bottomRight = true,
}

function Tooltip:__index(key)
    if not PARTS[key] then return Tooltip[key] end
    if self._parts == nil and self.target ~= nil and ui.Interfaces:GetInterface(self.interfaceID) ~= nil then
        build(self)
    end
    if self._parts == nil then return nil end
    self.keepBuilt = true
    return self._parts[key]
end

function Tooltip.attach(target, parent, value, hoverHandlers)
    if value == nil then return nil end
    local options = normalize(value)
    local width, height = measure(tostring(options.text or ""), options)

    local self = setmetatable({}, Tooltip)
    self.target = target
    self.targetInterfaceID = target.interfaceID
    self.targetClickthrough = target.clickthrough
    self.options = options
    self.followCursor = hoverHandlers and hoverHandlers.followCursor == true
    self.width = width
    self.height = height
    self.context = options.parent == nil and contexts[parent] or nil
    self.parent = options.parent or (self.context and self.context.parent) or parent
    self.interfaceID = self.parent.interfaceID

    -- callers with their own leave handling reuse one tooltip across hovers so only the rest release on hide
    self.keepBuilt = hoverHandlers ~= nil and hoverHandlers.onMouseLeave ~= nil

    target.clickthrough = false

    target:Subscribe(ui.Hook.ONMOUSEOVER, HOOK_ID, function(_, x, y)
        if self.followCursor then self.cursorX, self.cursorY = x, y end
        if hoverHandlers and hoverHandlers.onMouseOver then
            hoverHandlers.onMouseOver(self)
        else
            self:Show()
        end
        return true
    end)
    target:Subscribe(ui.Hook.ONMOUSELEAVE, HOOK_ID, function()
        if hoverHandlers and hoverHandlers.onMouseLeave then
            hoverHandlers.onMouseLeave(self)
        else
            self:Hide()
        end
        return true
    end)

    if self.followCursor then
        target:Subscribe(ui.Hook.ONMOUSEREPEAT, HOOK_ID, function(_, x, y)
            if self._parts ~= nil and ui.Interfaces:GetInterface(self.interfaceID) ~= nil
                and self._parts.root.hidden ~= true then
                self.cursorX, self.cursorY = x, y
                self:Show()
            end
            return true
        end)
    end

    if self.context then table.insert(self.context.tooltips, self) end

    return self
end

function Tooltip:Show()
    if self.target == nil
        or ui.Interfaces:GetInterface(self.interfaceID) == nil
        or ui.Interfaces:GetInterface(self.targetInterfaceID) == nil then return end
    if self._parts == nil then build(self) end
    local targetX = self.target.x or 0
    local targetY = self.target.y or 0
    if self.context and self.context.active then
        targetX, targetY = self.context.position(self.target)
    end
    local targetWidth = self.target.width or 0
    local targetHeight = self.target.height or 0
    local offset = OFFSET
    if self.followCursor and self.cursorX ~= nil and self.cursorY ~= nil then
        -- Hover coordinates are local interface units; reuse the overlay context origin.
        targetX, targetY = targetX + self.cursorX, targetY + self.cursorY
        targetWidth, targetHeight = 0, 0
        offset = CURSOR_OFFSET
    end
    local parentWidth = self.parent and (self.parent.width or 0) or 0
    local parentHeight = self.parent and (self.parent.height or 0) or 0
    local margin = self.options.boundsMargin or OFFSET
    local x, y
    for _, placement in ipairs(placementOrder(self.options.placement)) do
        local candidateX, candidateY = placedPosition(
            placement, targetX, targetY, targetWidth, targetHeight, self.width, self.height, offset
        )
        x, y = candidateX, candidateY
        if parentWidth <= 0 or parentHeight <= 0 or
            fitsParent(x, y, self.width, self.height, parentWidth, parentHeight, margin) then
            break
        end
    end
    x = self.options.x or x
    y = self.options.y or y
    if self.options.constrainToParent ~= false and parentWidth > 0 and parentHeight > 0 then
        local maxX = math.max(margin, parentWidth - self.width - margin)
        local maxY = math.max(margin, parentHeight - self.height - margin)
        x = clamp(x, margin, maxX)
        y = clamp(y, margin, maxY)
    end
    self._parts.root:SetPos(x, y)
    self._parts.root.hidden = false
    self._parts.root:MoveToFront()
end

function Tooltip:SetText(text)
    if self.target == nil
        or ui.Interfaces:GetInterface(self.interfaceID) == nil then return false end

    text = tostring(text or "")
    self.options.text = text
    self.width, self.height = measure(text, self.options)
    if self._parts == nil then return true end
    self._parts.root:SetSize(self.width, self.height)
    self._parts.label.content = text

    if self._parts.root.hidden ~= true then self:Show() end
    return true
end

function Tooltip:Hide()
    self.cursorX, self.cursorY = nil, nil
    if not self.keepBuilt then
        release(self)
    elseif self._parts ~= nil and ui.Interfaces:GetInterface(self.interfaceID) ~= nil then
        self._parts.root.hidden = true
    end
end

function Tooltip:Destroy()
    if self.target ~= nil and ui.Interfaces:GetInterface(self.targetInterfaceID) ~= nil then
        self.target:Unsubscribe(ui.Hook.ONMOUSEOVER, HOOK_ID)
        self.target:Unsubscribe(ui.Hook.ONMOUSELEAVE, HOOK_ID)
        if self.followCursor then self.target:Unsubscribe(ui.Hook.ONMOUSEREPEAT, HOOK_ID) end
        self.target.clickthrough = self.targetClickthrough
    end
    self.target = nil
    release(self)
    self.parent = nil
    if self.context then
        local attachments = self.context.tooltips
        for index = #attachments, 1, -1 do
            if attachments[index] == self then
                table.remove(attachments, index)
                break
            end
        end
        self.context = nil
    end
end

return Tooltip
