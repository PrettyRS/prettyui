local Sprites = require("src/core/sprites")
local clamp = require("src/core/math").clamp
local Components = require("src/core/components")

local AnchoredTooltip = {}
AnchoredTooltip.__index = AnchoredTooltip

local CORNER_SIZE = 10
local EDGE_SIZE = 2
local PADDING_X = 12
local PADDING_Y = 10
local DEFAULT_MAX_WIDTH = 300
local DEFAULT_CONTENT_WIDTH = 240
local DEFAULT_CONTENT_HEIGHT = 48
local DEFAULT_NPC_HEIGHT = 1024
local DEFAULT_LOC_HEIGHT = 512
local DEFAULT_OFFSET_Y = 8
local FALLBACK_LINE_HEIGHT = 18
local TEXT_COLOUR = 0xE9E5DDFF
local BACKGROUND_COLOUR = 0x000000FF
local DEFAULT_BACKGROUND_ALPHA = 0.78
local BOTTOM_EDGE_TOP_COLOUR = 0xBFBFBFFF
local BOTTOM_EDGE_BOTTOM_COLOUR = 0x7A8A8AFF
local nextInstanceID = 0

local function copyOptions(value)
    local copy = {}
    if type(value) == "table" then
        for key, option in pairs(value) do copy[key] = option end
    end
    return copy
end

local function sprite(parent, spriteID)
    local component = Components.new(ui.Sprite, parent)
    component.spriteID = spriteID
    component.clickthrough = true
    return component
end

local function measure(text, options, customContent, paddingX, paddingY)
    local font = config.Font.MUSEO_SANS_15PT_REGULAR
    local maxWidth = options.maxWidth or DEFAULT_MAX_WIDTH
    local width = options.width
    if width == nil and customContent then
        width = (options.contentWidth or DEFAULT_CONTENT_WIDTH) + paddingX * 2
    end
    if width == nil then
        local succeeded, textWidth = pcall(function() return font:GetStringWidth(text, false) end)
        width = math.min(maxWidth, (succeeded and textWidth or #text * 7) + paddingX * 2)
    end
    width = math.max(CORNER_SIZE * 2 + 1, width)

    local contentWidth = math.max(1, width - paddingX * 2)
    local height = options.height
    if height == nil and customContent then
        height = (options.contentHeight or DEFAULT_CONTENT_HEIGHT) + paddingY * 2
    end
    if height == nil then
        local succeeded, textHeight = pcall(function()
            return font:GetStringHeightAndLineCount(text, contentWidth, font.baseline, false, false, false)
        end)
        if succeeded then
            height = textHeight + paddingY * 2
        else
            local lines = math.max(1, math.ceil((#text * 7) / contentWidth))
            height = lines * FALLBACK_LINE_HEIGHT + paddingY * 2
        end
    end
    return width, math.max(CORNER_SIZE * 2 + 1, height)
end

local function createBorder(self)
    local border = Sprites.ANCHORED_TOOLTIP.border

    self.topLeft = sprite(self.root, border.topLeft)
    self.topLeft:SetSize(CORNER_SIZE, CORNER_SIZE)
    self.top = sprite(self.root, border.top)
    self.top:SetPos(CORNER_SIZE, 0)
    self.top:SetSize(self.width - CORNER_SIZE * 2, EDGE_SIZE)
    self.top.isTiling = true
    self.topRight = sprite(self.root, border.topLeft)
    self.topRight:SetPos(self.width - CORNER_SIZE, 0)
    self.topRight:SetSize(CORNER_SIZE, CORNER_SIZE)
    self.topRight.isFlippedHorizontally = true

    self.left = sprite(self.root, border.side)
    self.left:SetPos(0, CORNER_SIZE)
    self.left:SetSize(EDGE_SIZE, self.height - CORNER_SIZE * 2)
    self.left.isTiling = true
    self.right = sprite(self.root, border.side)
    self.right:SetPos(self.width - EDGE_SIZE + 1, CORNER_SIZE)
    self.right:SetSize(EDGE_SIZE, self.height - CORNER_SIZE * 2)
    self.right.isTiling = true

    self.bottomLeft = sprite(self.root, border.bottomLeft)
    self.bottomLeft:SetPos(0, self.height - CORNER_SIZE)
    self.bottomLeft:SetSize(CORNER_SIZE, CORNER_SIZE)
    self.bottom = {}
    local bottomWidth = self.width - CORNER_SIZE * 2
    local bottomTop = Components.new(ui.Rectangle, self.root)
    bottomTop:SetPos(CORNER_SIZE, self.height - EDGE_SIZE)
    bottomTop:SetSize(bottomWidth, 1)
    bottomTop.fill = true
    bottomTop.rgba = BOTTOM_EDGE_TOP_COLOUR
    bottomTop.clickthrough = true
    self.bottom[#self.bottom + 1] = bottomTop

    local bottomBottom = Components.new(ui.Rectangle, self.root)
    bottomBottom:SetPos(CORNER_SIZE, self.height - 1)
    bottomBottom:SetSize(bottomWidth, 1)
    bottomBottom.fill = true
    bottomBottom.rgba = BOTTOM_EDGE_BOTTOM_COLOUR
    bottomBottom.clickthrough = true
    self.bottom[#self.bottom + 1] = bottomBottom
    self.bottomRight = sprite(self.root, border.bottomLeft)
    self.bottomRight:SetPos(self.width - CORNER_SIZE, self.height - CORNER_SIZE)
    self.bottomRight:SetSize(CORNER_SIZE, CORNER_SIZE)
    self.bottomRight.isFlippedHorizontally = true
end

local function resize(self, width, height)
    self.width = width
    self.height = height
    self.contentWidth = width - self.paddingX * 2
    self.contentHeight = height - self.paddingY * 2

    self.root:SetSize(width, height)
    self.background:SetSize(width - EDGE_SIZE * 2, height - EDGE_SIZE * 2)
    self.top:SetSize(width - CORNER_SIZE * 2, EDGE_SIZE)
    self.topRight:SetPos(width - CORNER_SIZE, 0)
    self.left:SetSize(EDGE_SIZE, height - CORNER_SIZE * 2)
    self.right:SetPos(width - EDGE_SIZE + 1, CORNER_SIZE)
    self.right:SetSize(EDGE_SIZE, height - CORNER_SIZE * 2)
    self.bottomLeft:SetPos(0, height - CORNER_SIZE)
    local bottomWidth = width - CORNER_SIZE * 2
    self.bottom[1]:SetPos(CORNER_SIZE, height - EDGE_SIZE)
    self.bottom[1]:SetSize(bottomWidth, 1)
    self.bottom[2]:SetPos(CORNER_SIZE, height - 1)
    self.bottom[2]:SetSize(bottomWidth, 1)
    self.bottomRight:SetPos(width - CORNER_SIZE, height - CORNER_SIZE)
end

function AnchoredTooltip.new(parent, options)
    if parent == nil then error("AnchoredTooltip requires a parent component collection") end
    options = options or {}
    if options.npc == nil and options.loc == nil and options.position == nil and
        options.anchor == nil then
        error("AnchoredTooltip requires npc, loc, position, or anchor")
    end

    nextInstanceID = nextInstanceID + 1
    local self = setmetatable({}, AnchoredTooltip)
    self.eventID = "prettyui_anchored_tooltip_" .. tostring(nextInstanceID)
    self.parent = parent
    self.options = options
    self.npc = options.npc
    self.loc = options.loc
    self.position = options.position
    self.anchor = options.anchor
    self.visible = options.hidden ~= true
    self.heightAboveGround = options.heightAboveGround
    self.offsetX = options.offsetX or 0
    self.offsetY = options.offsetY == nil and DEFAULT_OFFSET_Y or options.offsetY
    self.paddingX = options.paddingX or options.padding or PADDING_X
    self.paddingY = options.paddingY or options.padding or PADDING_Y
    self.buildContent = options.buildContent
    if self.buildContent == nil and type(options.content) == "function" then
        self.buildContent = options.content
    end
    self.hasText = options.text ~= nil
    self.text = tostring(options.text or "")
    local customContent = self.buildContent ~= nil or not self.hasText
    self.width, self.height = measure(
        self.text,
        options,
        customContent,
        self.paddingX,
        self.paddingY
    )

    self.interfaceID = parent.interfaceID
    self.root = Components.new(ui.Layer, parent)
    self.root:SetSize(self.width, self.height)
    self.root.clickthrough = options.clickthrough ~= false
    self.root.hidden = true

    self.background = Components.new(ui.Rectangle, self.root)
    self.background:SetPos(EDGE_SIZE, EDGE_SIZE)
    self.background:SetSize(
        self.width - EDGE_SIZE * 2,
        self.height - EDGE_SIZE * 2
    )
    self.background.fill = true
    self.background.rgba = options.backgroundColour or BACKGROUND_COLOUR
    self.background.alpha = options.backgroundAlpha or DEFAULT_BACKGROUND_ALPHA
    self.background.clickthrough = true

    createBorder(self)

    self.content = Components.new(ui.Layer, self.root)
    self.content:SetPos(self.paddingX, self.paddingY)
    self.content:SetSize(-self.paddingX * 2, -self.paddingY * 2, 1.0, 1.0)
    self.content.clickthrough = options.clickthrough ~= false
    self.content.enabled = options.clickthrough == false
    self.contentWidth = self.width - self.paddingX * 2
    self.contentHeight = self.height - self.paddingY * 2

    if self.buildContent then
        local succeeded, result = pcall(self.buildContent, self, self.content)
        if not succeeded then
            self.root:Destroy()
            self.root = nil
            error(result, 0)
        end
        self.contentResult = result
    elseif self.hasText then
        self.label = Components.new(ui.Text, self.content)
        self.label:SetSize(0, 0, 1.0, 1.0)
        self.label.content = self.text
        self.label.font = options.font or id.Font.MUSEO_SANS_13PT_BOLD
        self.label.rgba = options.colour or TEXT_COLOUR
        self.label.maxLines = 0
        self.label.alignHorizontal = options.alignHorizontal or ui.AlignMode.CENTRE
        self.label.alignVertical = options.alignVertical or ui.AlignMode.CENTRE
        self.label.isShadowed = options.shadowed ~= false
        self.label.clickthrough = true
    end

    self:Update()
    Event.Logic.Subscribe(self.eventID, function()
        if self.root == nil then
            Event.Logic.Unsubscribe(self.eventID)
            return
        end
        if self.npc ~= nil and not self.npc.isValid then
            self:Destroy()
            return
        end
        self:Update()
    end)
    return self
end

function AnchoredTooltip.show(options)
    options = options or {}
    local parent = options.parent
    if parent == nil then
        parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__ROOT)
            or ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
    end
    if parent == nil then return nil end
    return AnchoredTooltip.new(parent, options)
end

function AnchoredTooltip.forNPC(npc, options)
    options = copyOptions(options)
    options.npc = npc
    return AnchoredTooltip.show(options)
end

function AnchoredTooltip.forLoc(loc, options)
    options = copyOptions(options)
    options.loc = loc
    return AnchoredTooltip.show(options)
end

function AnchoredTooltip:_ResolveScreenPosition()
    if self.anchor then return self.anchor(self) end
    if self.npc then
        local height = self.heightAboveGround or DEFAULT_NPC_HEIGHT
        return ScreenConvert.Vector3ToScreen(self.npc.position + Vector3.new(0, height, 0))
    end
    if self.position then return ScreenConvert.Vector3ToScreen(self.position) end
    if self.loc then
        local height = self.heightAboveGround or DEFAULT_LOC_HEIGHT
        local succeeded, screenPosition = pcall(function()
            return ScreenConvert.CoordGridToScreen(self.loc, height)
        end)
        if succeeded and screenPosition ~= nil then return screenPosition end
        succeeded, screenPosition = pcall(function()
            return ScreenConvert.CoordFineToScreen(self.loc, height)
        end)
        if succeeded then return screenPosition end
    end
    return nil
end

function AnchoredTooltip:Update()
    if self.root == nil then return false end
    if not self.visible then
        self.root.hidden = true
        return false
    end
    local succeeded, screenPosition = pcall(function() return self:_ResolveScreenPosition() end)
    if not succeeded or screenPosition == nil then
        self.root.hidden = true
        return false
    end

    local parentWidth = self.parent.width or 0
    local parentHeight = self.parent.height or 0
    if screenPosition.x < 0 or screenPosition.y < 0 or
        screenPosition.x > parentWidth or screenPosition.y > parentHeight then
        self.root.hidden = true
        return false
    end

    local x = math.floor(screenPosition.x - self.width / 2 + self.offsetX + 0.5)
    local y = math.floor(screenPosition.y - self.height - self.offsetY + 0.5)
    x = clamp(x, 0, math.max(0, parentWidth - self.width))
    y = clamp(y, 0, math.max(0, parentHeight - self.height))
    self.root:SetPos(x, y)
    self.root.hidden = false
    self.root:MoveToBack()
    return true
end

function AnchoredTooltip:SetText(text)
    if self.root == nil or self.label == nil then return false end

    self.text = tostring(text or "")
    self.options.text = self.text
    self.label.content = self.text
    local width, height = measure(
        self.text,
        self.options,
        false,
        self.paddingX,
        self.paddingY
    )
    resize(self, width, height)
    self:Update()
    return true
end

function AnchoredTooltip:Show()
    self.visible = true
    return self:Update()
end

function AnchoredTooltip:Hide()
    self.visible = false
    if self.root then self.root.hidden = true end
end

function AnchoredTooltip:Destroy()
    Event.Logic.Unsubscribe(self.eventID)
    if self.root then
        if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.root:Destroy() end
        self.root = nil
    end
    self.parent = nil
    self.npc = nil
    self.loc = nil
    self.position = nil
    self.anchor = nil
    self.content = nil
    self.contentResult = nil
    self.buildContent = nil
    self.hasText = nil
    self.label = nil
    self.options = nil
end

return AnchoredTooltip
