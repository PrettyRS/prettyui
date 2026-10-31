local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local SPRITE_TYPE = 1
local LAYER_TYPE = 3
local BUFF_LAYER_ID = 1
local DEBUFF_LAYER_ID = 2
local DEFAULT_FONT_ID = 10

local function iteratorVisibility(component)
    if component.iteratorVisible ~= nil then return component.iteratorVisible end
    return component.visible
end

local function nativeSlot(x, spriteID, y)
    local graphic = {
        visible = true,
        alpha = 1,
        type = SPRITE_TYPE,
        spriteID = spriteID,
    }
    local slot = {
        x = x,
        y = y or 0,
        width = 30,
        height = 30,
        visible = true,
        alpha = 1,
        type = LAYER_TYPE,
        graphic = graphic,
        dynamicComponents = { graphic },
    }
    function slot:IterateStaticComponents() end
    function slot:IterateDynamicComponents(callback)
        for _, item in ipairs(self.dynamicComponents) do
            if callback(item, iteratorVisibility(item)) then return end
        end
    end
    return slot
end

local nextDynamicID = 0
local function newLayer(nativeY, height)
    local leadingSlot = nativeSlot(0, 100, nativeY)
    local trailingSlot = nativeSlot(38, -1, nativeY)
    local secondRowSlot = nativeSlot(0, -1, (nativeY or 0) + 38)
    local layer = {
        width = 200,
        height = height or 30,
        staticComponents = {
            leadingSlot,
            trailingSlot,
            secondRowSlot,
        },
        slots = {
            leading = leadingSlot,
            trailing = trailingSlot,
            secondRow = secondRowSlot,
        },
        dynamicComponents = {},
    }
    function layer:IterateStaticComponents(callback)
        for _, item in ipairs(self.staticComponents) do
            if callback(item, iteratorVisibility(item)) then return end
        end
    end
    function layer:IterateDynamicComponents(callback)
        for _, item in ipairs(self.dynamicComponents) do
            if not item.destroyed and callback(item, not item.hidden) then return end
        end
    end
    return layer
end

local buffLayer = newLayer()
local debuffLayer = newLayer(100, 200)

local function component(parent, kind)
    nextDynamicID = nextDynamicID + 1
    local result = {
        dynamicID = nextDynamicID,
        kind = kind,
        hidden = false,
        visible = true,
        x = 0,
        y = 0,
        width = 0,
        height = 0,
        dynamicComponents = {},
        subscriptions = {},
    }
    function result:SetSize(width, height)
        self.width = width
        self.height = height
    end
    function result:SetPos(x, y)
        self.x = x
        self.y = y
        self.positionUpdates = (self.positionUpdates or 0) + 1
    end
    function result:SetAssociatedObject(objectID)
        self.objectID = objectID
        self.associatedObjectID = objectID
    end
    function result:Destroy()
        self.destroyed = true
    end
    function result:Subscribe(hook, id, callback)
        self.subscriptions[tostring(hook) .. ":" .. tostring(id)] = callback
    end
    function result:Unsubscribe(hook, id)
        self.subscriptions[tostring(hook) .. ":" .. tostring(id)] = nil
    end
    function result:MoveToFront()
        self.movedToFront = true
    end
    table.insert(parent.dynamicComponents, result)
    return Interfaces.component(result, parent)
end

local function componentFactory(kind)
    return {
        new = function(parent) return component(parent, kind) end,
    }
end

ui = {
    Interfaces = {
        GetComponent = function(_, componentID)
            if componentID == BUFF_LAYER_ID then return buffLayer end
            if componentID == DEBUFF_LAYER_ID then return debuffLayer end
            return nil
        end,
    },
    Rectangle = componentFactory("rectangle"),
    Sprite = componentFactory("sprite"),
    Text = componentFactory("text"),
    Layer = componentFactory("layer"),
    Hook = { ONMOUSEOVER = 1, ONMOUSELEAVE = 2 },
    AlignMode = { CENTRE = 0 },
    ComponentType = {
        SPRITE = SPRITE_TYPE,
        BUTTON = 2,
        LAYER = LAYER_TYPE,
        PANEL = 4,
        GRID = 5,
        PAGED_LAYER = 6,
        PAGED_CAROUSEL = 7,
        GROUP_BOX = 8,
    },
}
id = {
    Component = {
        BUFF_BAR__BUFF_RENDER_LAYER = BUFF_LAYER_ID,
        DEBUFF_BAR__BUFF_RENDER_LAYER = DEBUFF_LAYER_ID,
    },
    Font = {
        NOTOSANS_BOLD_12 = DEFAULT_FONT_ID,
        MUSEO_SANS_15PT_REGULAR = 11,
    },
    Sprite = setmetatable({}, { __index = function() return 1 end }),
}
config = {
    Font = {
        MUSEO_SANS_15PT_REGULAR = {
            baseline = 12,
            GetStringWidth = function(_, text) return #text * 7 end,
            GetStringHeightAndLineCount = function() return 18 end,
        },
    },
}

local logicHandler
Event = {
    Logic = {
        Subscribe = function(_, handler) logicHandler = handler end,
        Unsubscribe = function() logicHandler = nil end,
    },
}
log = function() end

local BuffBar = require("src/buff_bar")

local function captureEntry(layer, addEntry, hasTooltip)
    local firstIndex = #layer.dynamicComponents + 1
    local handle = addEntry()
    local components = {}
    for index = firstIndex, #layer.dynamicComponents do
        table.insert(components, layer.dynamicComponents[index])
    end

    expect(#components, hasTooltip and 6 or 4, "an entry creates the expected component count")
    expect(components[1].kind, "rectangle", "the first entry component is its background")
    expect(components[2].kind, "sprite", "the second entry component is its sprite")
    expect(components[3].kind, "rectangle", "the third entry component is its border")
    expect(components[4].kind, "text", "the fourth entry component is its label")

    return handle, {
        background = components[1],
        sprite = components[2],
        border = components[3],
        label = components[4],
        tooltipTarget = components[5],
        tooltipRoot = components[6],
        tooltipLabel = components[6] and components[6].dynamicComponents[10],
    }
end

local firstHandle, first = captureEntry(buffLayer, function()
    return BuffBar.addBuff({
        objId = 42,
        label = "100%",
        borderRgba = 0x123456FF,
        backgroundRgba = 0x654321AA,
    })
end)
expect(first.sprite.x, 32, "buff layout follows the visible native buff with a three-pixel gap")
expect(first.sprite.y, 1, "buff layout preserves the vertical offset")
expect(first.border.rgba, 0x123456FF, "buffs can override their border colour")
expect(first.background.rgba, 0x654321AA, "buffs can override their background colour")
expect(first.background.x, first.border.x + 1, "the background starts inside the border")
expect(first.background.y, first.border.y + 1, "the background starts below the border")
expect(first.background.width, first.border.width - 2, "the background ends inside the border")
expect(first.background.height, first.border.height - 2, "the background stays vertically inside the border")
expect(firstHandle:SetLabel("99%", 0xABCDEF12), true, "untimed labels can be updated")
expect(first.label.content, "99%", "SetLabel updates label content")
expect(first.label.rgba, 0xABCDEF12, "SetLabel can update label colour")
expect(firstHandle:SetSprite(123), true, "buff handles can switch to a raw sprite")
expect(first.sprite.associatedObjectID, -1, "SetSprite clears associated object artwork")
expect(first.sprite.spriteID, 123, "SetSprite updates the raw sprite ID")
expect(firstHandle:SetObject(84), true, "buff handles can switch to object artwork")
expect(first.sprite.spriteID, -1, "SetObject clears the raw sprite ID")
expect(first.sprite.associatedObjectID, 84, "SetObject updates the associated object")
expect(firstHandle:SetObject({ id = 85 }), true, "SetObject accepts an Obj config")
expect(first.sprite.associatedObjectID, 85, "SetObject resolves an Obj config ID")
expect(firstHandle:SetSprite("invalid"), false, "SetSprite rejects non-integer IDs")
expect(first.sprite.associatedObjectID, 85, "an invalid sprite leaves the icon unchanged")

local initialPositionUpdates = first.sprite.positionUpdates
logicHandler({ logicTick = 1 })
expect(first.sprite.positionUpdates, initialPositionUpdates, "an unchanged tick skips component writes")

buffLayer.slots.trailing.graphic.spriteID = 101
buffLayer.slots.trailing.iteratorVisible = false
logicHandler({ logicTick = 2 })
expect(first.sprite.x, 70, "rendered native buffs override a stale iterator visibility")

buffLayer.slots.trailing.graphic.spriteID = -1
buffLayer.slots.trailing.iteratorVisible = nil
logicHandler({ logicTick = 3 })
expect(first.sprite.x, 32, "an expired native buff releases space on the next tick")

local foreignComponent = component(buffLayer, "sprite")
foreignComponent.categoryID = 1
foreignComponent.dynamicID = first.sprite.dynamicID
first.sprite.categoryID = 0
foreignComponent:SetSize(28, 28)
foreignComponent:SetPos(70, 0)
foreignComponent.hidden = true
foreignComponent.visible = false
logicHandler({ logicTick = 4 })
expect(first.sprite.x, 32, "hidden foreign components do not reserve space")

foreignComponent.hidden = false
foreignComponent.visible = true
logicHandler({ logicTick = 5 })
expect(first.sprite.x, 100, "visible foreign components reserve space")

foreignComponent.hidden = true
foreignComponent.visible = false
logicHandler({ logicTick = 6 })
expect(first.sprite.x, 32, "hidden foreign components release their space")
foreignComponent:Destroy()

local secondHandle, second = captureEntry(buffLayer, function()
    return BuffBar.addBuff({ spriteID = 7 })
end)
expect(second.sprite.x, 63, "custom buffs retain three pixels of spacing")
expect(second.background.rgba, 0x00000000, "buff backgrounds remain transparent by default")
expect(second.border.rgba, 0x5A9619FF, "buffs retain the default border without an override")

expect(firstHandle:SetVisible(false), true, "buffs can be hidden")
expect(second.sprite.x, 32, "hidden custom buffs do not leave gaps")
local hiddenPositionUpdates = second.sprite.positionUpdates
expect(firstHandle:SetVisible(false), true, "repeating visibility is still successful")
expect(second.sprite.positionUpdates, hiddenPositionUpdates, "unchanged visibility skips layout writes")
expect(firstHandle:SetVisible(true), true, "buffs can be shown again")

local debuffHandle, debuff = captureEntry(debuffLayer, function()
    return BuffBar.addDebuff({
        spriteID = 8,
        label = "!",
        tooltip = "Test debuff",
        borderRgba = 0x123456FF,
        backgroundRgba = 0x112233CC,
    })
end, true)
expect(debuff.border.rgba, 0xCC0000FF, "debuffs ignore border overrides and remain red")
expect(debuff.background.rgba, 0x112233CC, "debuffs can override their background colour")
expect(debuff.label.rgba, 0xFFFFFFFF, "labels default to white")
expect(debuff.label.font, DEFAULT_FONT_ID, "labels default to Noto Sans Bold")
expect(debuff.tooltipTarget.clickthrough, false, "tooltip target receives pointer events")
expect(debuff.tooltipRoot.hidden, true, "tooltip starts hidden")
expect(debuff.sprite.x, 32, "debuffs avoid native debuffs independently")
expect(debuff.sprite.y, 101, "debuff layout follows the native row")
expect(debuffHandle:SetTooltip("Updated debuff"), true, "buff handles update their tooltip")
expect(debuff.tooltipLabel.content, "Updated debuff", "SetTooltip updates tooltip content")
expect(secondHandle:SetTooltip("Added later"), true, "entries can add tooltips dynamically")
expect(secondHandle:SetTooltip(nil), true, "entries can remove tooltips dynamically")

debuff.tooltipTarget.subscriptions["1:prettyui_tooltip"]()
expect(debuff.tooltipRoot.hidden, true, "hover starts the tooltip delay")
debuff.tooltipTarget.subscriptions["2:prettyui_tooltip"]()
logicHandler({ logicTick = 7 })
expect(debuff.tooltipRoot.hidden, true, "leaving during the delay cancels the tooltip")

debuff.tooltipTarget.subscriptions["1:prettyui_tooltip"]()
logicHandler({ logicTick = 8 })
expect(debuff.tooltipRoot.hidden, true, "one logic tick is shorter than the tooltip delay")
logicHandler({ logicTick = 36 })
expect(debuff.tooltipRoot.hidden, true, "tooltip remains hidden before thirty logic ticks")
logicHandler({ logicTick = 37 })
expect(debuff.tooltipRoot.hidden, false, "thirty logic ticks show the hovered entry tooltip")
expect(debuff.tooltipRoot.x, 66, "tooltip uses the standard right-side placement")
expect(debuff.tooltipRoot.y, 101, "tooltip uses the standard target alignment")
debuff.tooltipTarget.subscriptions["2:prettyui_tooltip"]()
expect(debuff.tooltipRoot.hidden, true, "leaving an entry hides its tooltip")

expect(BuffBar.removeDebuff(firstHandle), false, "removeDebuff rejects a buff handle")
expect(BuffBar.removeDebuff(debuffHandle), true, "removeDebuff removes a debuff")
expect(debuff.border.destroyed, true, "removing a debuff destroys its components")
expect(debuff.tooltipTarget.destroyed, true, "removing a debuff destroys its tooltip target")
expect(debuff.tooltipRoot.destroyed, true, "removing a debuff destroys its tooltip")
expect(debuffHandle:SetVisible(true), false, "removed handles reject visibility changes")
expect(debuffHandle:SetLabel("removed"), false, "removed handles reject label changes")
expect(debuffHandle:SetTooltip("removed"), false, "removed handles reject tooltip changes")

local timedHandle, timed = captureEntry(buffLayer, function()
    return BuffBar.addBuff({ spriteID = 9, duration = 301 })
end)
expect(timed.label.content, "5m", "timers at or above one minute use minute units")
expect(timedHandle:SetLabel("manual"), false, "timed entries reject manual label changes")
expect(timed.label.content, "5m", "rejecting SetLabel preserves the timer label")

logicHandler({ logicTick = 100 })
logicHandler({ logicTick = 14437 })
expect(timed.label.content, "13s", "timers below one minute count down in seconds")

logicHandler({ logicTick = 15087 })
expect(timed.background.destroyed, true, "timed buffs remove themselves at zero")
expect(timedHandle:SetVisible(true), false, "expired handles reject visibility changes")

buffLayer.width = 100
buffLayer.slots.trailing.graphic.spriteID = 101
buffLayer.slots.secondRow.graphic.spriteID = 102
logicHandler({ logicTick = 15088 })
expect(first.sprite.x, 32, "wrapped custom buffs avoid native occupancy on the second row")
expect(first.sprite.y, 39, "wrapped custom buffs use the native second-row position")

buffLayer.slots.secondRow.graphic.spriteID = -1
logicHandler({ logicTick = 15089 })
expect(first.sprite.x, 1, "custom buffs stay inside the left edge of an empty second row")
expect(first.sprite.y, 39, "reclaiming space keeps the custom buff on the second row")

expect(BuffBar.removeBuff(secondHandle), true, "removeBuff removes a buff")
expect(BuffBar.removeBuff(firstHandle), true, "removeBuff removes the final buff")
expect(firstHandle:SetLabel("removed"), false, "removed buff handles reject label changes")
expect(firstHandle:SetObject(42), false, "removed buff handles reject object changes")
expect(firstHandle:SetSprite(42), false, "removed buff handles reject sprite changes")
expect(logicHandler, nil, "removing the final entry stops the logic subscription")

local invalid = BuffBar.addDebuff({ spriteID = 10, duration = 0 })
expect(invalid, nil, "non-positive durations are rejected")

BuffBar.Shutdown()
expect(logicHandler, nil, "shutdown leaves the logic subscription stopped")

print("buff_bar_test: ok")
