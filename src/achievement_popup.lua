local ItemSlot = require("src/item_slot")
local Sprites = require("src/core/sprites")
local clamp = require("src/core/math").clamp
local Components = require("src/core/components")

local AchievementPopup = {}
AchievementPopup.__index = AchievementPopup

local BORDER_SIZE = 4
local CORNER_SIZE = 4
local SLOT_SIZE = 40
local DEFAULT_WIDTH = 300
local DEFAULT_HEIGHT = 92
local DEFAULT_Y = 20
local TITLE_TOP = 6
local TITLE_HEIGHT = 24
local TICKS_PER_SECOND = 50
local FADE_IN_TICKS = 15
local FADE_OUT_TICKS = 25
local HOLD_TICKS = TICKS_PER_SECOND * 4 - FADE_IN_TICKS - FADE_OUT_TICKS
local TOTAL_TICKS = FADE_IN_TICKS + HOLD_TICKS + FADE_OUT_TICKS
local TITLE_COLOUR = 0xF1C384FF
local TEXT_COLOUR = 0xFFFFFFFF
local nextInstanceID = 0

local function sprite(parent, spriteID)
    local component = Components.new(ui.Sprite, parent)
    component.spriteID = spriteID
    component.clickthrough = true
    return component
end

local function createFrame(self)
    local frame = Sprites.HUD_WINDOW

    self.top = sprite(self.root, frame.top)
    self.top:SetPos(CORNER_SIZE, 0)
    self.top:SetSize(-CORNER_SIZE * 2, BORDER_SIZE, 1.0)
    self.top.isTiling = true

    self.bottom = sprite(self.root, frame.bottom)
    self.bottom:SetPos(CORNER_SIZE, -BORDER_SIZE, 0, 1.0)
    self.bottom:SetSize(-CORNER_SIZE * 2, BORDER_SIZE, 1.0)
    self.bottom.isTiling = true

    self.left = sprite(self.root, frame.side)
    self.left:SetPos(0, CORNER_SIZE)
    self.left:SetSize(BORDER_SIZE, -CORNER_SIZE * 2, 0, 1.0)
    self.left.isTiling = true

    self.right = sprite(self.root, frame.side)
    self.right:SetPos(-BORDER_SIZE, CORNER_SIZE, 1.0)
    self.right:SetSize(BORDER_SIZE, -CORNER_SIZE * 2, 0, 1.0)
    self.right.isTiling = true
    self.right.isFlippedHorizontally = true

    self.topLeft = sprite(self.root, frame.cornerTop)
    self.topLeft:SetSize(CORNER_SIZE, CORNER_SIZE)

    self.topRight = sprite(self.root, frame.cornerTop)
    self.topRight:SetPos(-CORNER_SIZE, 0, 1.0)
    self.topRight:SetSize(CORNER_SIZE, CORNER_SIZE)
    self.topRight.isFlippedHorizontally = true

    self.bottomLeft = sprite(self.root, frame.cornerBottom)
    self.bottomLeft:SetPos(0, -CORNER_SIZE, 0, 1.0)
    self.bottomLeft:SetSize(CORNER_SIZE, CORNER_SIZE)

    self.bottomRight = sprite(self.root, frame.cornerBottom)
    self.bottomRight:SetPos(-CORNER_SIZE, -CORNER_SIZE, 1.0, 1.0)
    self.bottomRight:SetSize(CORNER_SIZE, CORNER_SIZE)
    self.bottomRight.isFlippedHorizontally = true
end

local function playCompletionSound(options)
    if options.sound == false then return nil end
    local soundID = options.soundID
    if soundID == nil and id.Sound ~= nil then soundID = id.Sound.ARCH_INFO_POPUP end
    if soundID == nil then return nil end
    local succeeded, sound = pcall(function() return audio.Play(soundID) end)
    return succeeded and sound or nil
end

function AchievementPopup:_SetVisualAlpha(alpha)
    alpha = clamp(alpha, 0, 1)
    for _, visual in ipairs(self.fadeVisuals) do
        if visual.component then visual.component.alpha = visual.alpha * alpha end
    end
end

function AchievementPopup.new(parent, options)
    if parent == nil then error("AchievementPopup requires a parent component collection") end
    options = options or {}

    nextInstanceID = nextInstanceID + 1

    local self = setmetatable({}, AchievementPopup)
    self.eventID = "prettyui_achievement_popup_" .. tostring(nextInstanceID)
    self.elapsedTicks = 0
    self.onComplete = options.onComplete

    local width = math.max(BORDER_SIZE * 2 + 1, options.width or DEFAULT_WIDTH)
    local height = math.max(BORDER_SIZE * 2 + 1, options.height or DEFAULT_HEIGHT)

    self.interfaceID = parent.interfaceID
    self.root = Components.new(ui.Layer, parent)
    self.root:SetPos(
        options.x or -math.floor(width / 2),
        options.y or DEFAULT_Y,
        options.xAnchor == nil and 0.5 or options.xAnchor,
        options.yAnchor or 0
    )
    self.root:SetSize(width, height)
    self.root.alpha = 1
    self.root.clickthrough = true
    self.root:MoveToFront()

    self.backgroundTexture = sprite(self.root, Sprites.HUD_WINDOW.content)
    self.backgroundTexture:SetPos(BORDER_SIZE, BORDER_SIZE)
    self.backgroundTexture:SetSize(-BORDER_SIZE * 2, -BORDER_SIZE * 2, 1.0, 1.0)
    self.backgroundTexture.isTiling = true
    self.backgroundTexture.alpha = 1

    createFrame(self)

    self.title = Components.new(ui.Text, self.root)
    self.title:SetPos(BORDER_SIZE + 4, TITLE_TOP)
    self.title:SetSize(-(BORDER_SIZE * 2 + 8), TITLE_HEIGHT, 1.0)
    self.title.content = tostring(options.title or "ACHIEVEMENT COMPLETE")
    self.title.font = id.Font.CINZEL_13PT_BOLD
    self.title.rgba = options.titleColour or TITLE_COLOUR
    self.title.alignHorizontal = ui.AlignMode.CENTRE
    self.title.alignVertical = ui.AlignMode.CENTRE
    self.title.maxLines = 1
    self.title.isShadowed = options.shadowed ~= false
    self.title.clickthrough = true

    local textLeft = BORDER_SIZE + 6
    if options.item ~= nil then
        local slotY = math.floor((height + TITLE_HEIGHT - SLOT_SIZE) / 2)
        self.itemSlot = ItemSlot.new(self.root, options.item, {
            x = BORDER_SIZE + 5,
            y = slotY,
            quantity = options.quantity,
            quantityMode = options.quantityMode,
            itemInset = options.itemInset,
            outlineWidth = options.outlineWidth,
            shadowRGBA = options.shadowRGBA,
            clickthrough = true,
        })
        textLeft = BORDER_SIZE + SLOT_SIZE + 12
    end

    self.text = Components.new(ui.Text, self.root)
    self.text:SetPos(textLeft, TITLE_HEIGHT)
    self.text:SetSize(-(textLeft + BORDER_SIZE + 6), -(TITLE_HEIGHT + BORDER_SIZE), 1.0, 1.0)
    self.text.content = tostring(options.text or "")
    self.text.font = id.Font.MUSEO_SANS_11PT_REGULAR
    self.text.rgba = options.textColour or TEXT_COLOUR
    self.text.alignHorizontal = ui.AlignMode.CENTRE
    self.text.alignVertical = ui.AlignMode.CENTRE
    self.text.maxLines = 0
    self.text.isShadowed = options.shadowed ~= false
    self.text.clickthrough = true

    self.fadeVisuals = {
        { component = self.backgroundTexture, alpha = 1 },
        { component = self.top, alpha = 1 },
        { component = self.bottom, alpha = 1 },
        { component = self.left, alpha = 1 },
        { component = self.right, alpha = 1 },
        { component = self.topLeft, alpha = 1 },
        { component = self.topRight, alpha = 1 },
        { component = self.bottomLeft, alpha = 1 },
        { component = self.bottomRight, alpha = 1 },
        { component = self.title, alpha = 1 },
        { component = self.text, alpha = 1 },
    }
    if self.itemSlot then
        table.insert(self.fadeVisuals, { component = self.itemSlot.background, alpha = 1 })
        if self.itemSlot.item then
            table.insert(self.fadeVisuals, { component = self.itemSlot.item, alpha = 1 })
        end
    end

    self.flash = Components.new(ui.Rectangle, self.root)
    self.flash:SetSize(0, 0, 1.0, 1.0)
    self.flash.fill = true
    self.flash.rgba = 0xFFFFFFFF
    self.flash.alpha = 1
    self.flash.clickthrough = true
    self.flash:MoveToFront()

    self.sound = playCompletionSound(options)

    Event.Logic.Subscribe(self.eventID, function()
        if self.root == nil then
            Event.Logic.Unsubscribe(self.eventID)
            return
        end

        self.elapsedTicks = self.elapsedTicks + 1
        if self.elapsedTicks <= FADE_IN_TICKS then
            self.flash.alpha = 1 - self.elapsedTicks / FADE_IN_TICKS
        elseif self.elapsedTicks <= FADE_IN_TICKS + HOLD_TICKS then
            self.flash.hidden = true
        elseif self.elapsedTicks <= TOTAL_TICKS then
            self:_SetVisualAlpha(1 -
                (self.elapsedTicks - FADE_IN_TICKS - HOLD_TICKS) / FADE_OUT_TICKS)
        else
            local onComplete = self.onComplete
            self:Destroy()
            if onComplete then onComplete(self) end
        end
    end)

    return self
end

function AchievementPopup.show(options)
    options = options or {}
    local parent = options.parent or
        ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
    if parent == nil then return nil end
    return AchievementPopup.new(parent, options)
end

function AchievementPopup:Destroy()
    Event.Logic.Unsubscribe(self.eventID)
    if self.itemSlot then
        self.itemSlot:Destroy()
        self.itemSlot = nil
    end
    if self.root then
        if ui.Interfaces:GetInterface(self.interfaceID) ~= nil then self.root:Destroy() end
        self.root = nil
    end
    self.sound = nil
    self.fadeVisuals = nil
    self.onComplete = nil
end

return AchievementPopup
