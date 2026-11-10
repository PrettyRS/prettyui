local Components = require("src/core/components")
local Sprites = require("src/core/sprites")
local clamp = require("src/core/math").clamp

local PanelSurface = {}
local BORDER_SIZE = 4

local function clampAlpha(value)
    return clamp(tonumber(value) or 1, 0, 1)
end

local function sprite(parent, spriteID)
    local component = Components.new(ui.Sprite, parent)
    component.spriteID = spriteID
    component.clickthrough = true
    return component
end

function PanelSurface.new(parent, options)
    local surface = {}
    local frame = Sprites.HUD_WINDOW
    surface.root = Components.newContent(parent, options)
    surface.interfaceID = surface.root.interfaceID
    surface.root:SetPos(options.x, options.y, options.xAnchor or 0, options.yAnchor or 0)
    surface.root:SetSize(options.width, options.height, options.widthAnchor or 0, options.heightAnchor or 0)
    surface.root.clickthrough = options.clickthrough == true

    surface.background = sprite(surface.root, frame.content)
    surface.background:SetPos(BORDER_SIZE, BORDER_SIZE)
    surface.background:SetSize(-BORDER_SIZE * 2, -BORDER_SIZE * 2, 1.0, 1.0)
    surface.background.isTiling = true
    surface.background.alpha = clampAlpha(options.backgroundAlpha)
    surface.background.clickthrough = options.clickthrough == true

    surface.top = sprite(surface.root, frame.top)
    surface.top:SetPos(BORDER_SIZE, 0)
    surface.top:SetSize(-BORDER_SIZE * 2, BORDER_SIZE, 1.0)
    surface.top.isTiling = true

    surface.bottom = sprite(surface.root, frame.bottom)
    surface.bottom:SetPos(BORDER_SIZE, -BORDER_SIZE, 0, 1.0)
    surface.bottom:SetSize(-BORDER_SIZE * 2, BORDER_SIZE, 1.0)
    surface.bottom.isTiling = true

    surface.right = sprite(surface.root, frame.side)
    surface.right:SetPos(-BORDER_SIZE, BORDER_SIZE, 1.0)
    surface.right:SetSize(BORDER_SIZE, -BORDER_SIZE * 2, 0, 1.0)
    surface.right.isTiling = true

    surface.left = sprite(surface.root, frame.side)
    surface.left:SetPos(0, BORDER_SIZE)
    surface.left:SetSize(BORDER_SIZE, -BORDER_SIZE * 2, 0, 1.0)
    surface.left.isTiling = true
    surface.right.isFlippedHorizontally = true

    surface.topRight = sprite(surface.root, frame.cornerTop)
    surface.topRight:SetPos(-BORDER_SIZE, 0, 1.0)
    surface.topRight:SetSize(BORDER_SIZE, BORDER_SIZE)
    surface.topRight.isFlippedHorizontally = true

    surface.topLeft = sprite(surface.root, frame.cornerTop)
    surface.topLeft:SetSize(BORDER_SIZE, BORDER_SIZE)

    surface.bottomRight = sprite(surface.root, frame.cornerBottom)
    surface.bottomRight:SetPos(-BORDER_SIZE, -BORDER_SIZE, 1.0, 1.0)
    surface.bottomRight:SetSize(BORDER_SIZE, BORDER_SIZE)
    surface.bottomRight.isFlippedHorizontally = true

    surface.bottomLeft = sprite(surface.root, frame.cornerBottom)
    surface.bottomLeft:SetPos(0, -BORDER_SIZE, 0, 1.0)
    surface.bottomLeft:SetSize(BORDER_SIZE, BORDER_SIZE)

    surface.container = Components.newContent(surface.root)
    surface.container:SetPos(BORDER_SIZE, BORDER_SIZE)
    surface.container:SetSize(-BORDER_SIZE * 2, -BORDER_SIZE * 2, 1.0, 1.0)
    surface.container.clickthrough = options.clickthrough == true
    surface.container.enabled = options.clickthrough ~= true

    -- Category-zero content must stay above managed, nonzero-category artwork.
    surface.background:MoveToBack()

    return surface
end

return PanelSurface
