id = { Component = { TOPLEVEL_V2__GAME_AREA = (1477 << 16) | 61 } }

local Snap = require("src/core/snap")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function expectPosition(position, at, from, to, message)
    expect(position.at, at, message .. " position")
    expect(position.from, from, message .. " span start")
    expect(position.to, to, message .. " span end")
end

local PARENT_WIDTH, PARENT_HEIGHT = 1920, 1080
local WIDTH, HEIGHT, EDGE_OFFSET = 100, 80, 2
local target = { x = 500, y = 300, width = 200, height = 150 }

local function positionsFor(rects, edgeOffset)
    return Snap.positions(rects, WIDTH, HEIGHT, PARENT_WIDTH, PARENT_HEIGHT, edgeOffset or EDGE_OFFSET)
end

local empty = positionsFor({})
expect(#empty.across, 2, "with no targets there are only the parent's left and right edges")
expect(#empty.down, 2, "with no targets there are only the parent's top and bottom edges")
expectPosition(empty.across[1], 0, -math.huge, math.huge, "parent left edge")
expectPosition(empty.across[2], PARENT_WIDTH - WIDTH, -math.huge, math.huge, "parent right edge")
expectPosition(empty.down[1], 0, -math.huge, math.huge, "parent top edge")
expectPosition(empty.down[2], PARENT_HEIGHT - HEIGHT, -math.huge, math.huge, "parent bottom edge")

local one = positionsFor({ target })
expect(#one.across, 6, "one target adds four across entries")
expect(#one.down, 6, "one target adds four down entries")
expectPosition(one.across[3], 402, 300, 450, "left of the target")
expectPosition(one.across[4], 698, 300, 450, "right of the target")
expectPosition(one.across[5], 498, 300, 450, "flush with the target's left side")
expectPosition(one.across[6], 602, 300, 450, "flush with the target's right side")
expectPosition(one.down[3], 222, 500, 700, "above the target")
expectPosition(one.down[4], 448, 500, 700, "below the target")
expectPosition(one.down[5], 298, 500, 700, "flush with the target's top")
expectPosition(one.down[6], 372, 500, 700, "flush with the target's bottom")

local noOffset = positionsFor({ target }, 0)
expect(noOffset.across[3].at, 400, "without an edge offset the window's right side meets the target's left side")
expect(noOffset.across[4].at, 700, "without an edge offset the window starts at the target's right side")
expect(noOffset.down[4].at, 450, "without an edge offset the window starts at the target's bottom")

local second = { x = 1200, y = 600, width = 300, height = 200 }
local two = positionsFor({ target, second })
expect(#two.across, 10, "each target adds four across entries")
expect(#two.down, 10, "each target adds four down entries")
expectPosition(two.across[7], 1102, 600, 800, "the second target's entries follow the first's")
expectPosition(two.down[10], 722, 1200, 1500, "the second target's last down entry is flush with its bottom")

local DISTANCE = 12

local function expectLanding(positions, x, y, expectedX, expectedY, message)
    local snappedX, snappedY = Snap.apply(positions, x, y, WIDTH, HEIGHT, DISTANCE)
    expect(snappedX, expectedX, message .. " x")
    expect(snappedY, expectedY, message .. " y")
end

expectLanding(one, 407, 320, 402, 320, "a window just left of the target snaps beside it")
expectLanding(one, 495, 455, 498, 448, "a window just below the target snaps below it, flush with its left side")
expectLanding(one, 405, 302, 402, 298, "both axes snap at once into the target's corner")
expectLanding(one, 414, 320, 402, 320, "a window exactly the snap distance away still snaps")
expectLanding(one, 415, 320, 415, 320, "a window one pixel past the snap distance stays where the mouse put it")
expectLanding(one, 405, 900, 405, 900, "a window far below the target isn't level with it, so it doesn't snap beside it")
expectLanding(one, 405, 462, 402, 462, "a window exactly the snap distance below the target's bottom still snaps beside it")
expectLanding(one, 405, 463, 405, 463, "a window one pixel further below doesn't snap beside it")
expectLanding(one, 6, 600, 0, 600, "a window near the parent's left edge snaps to it")
expectLanding(one, 600, 995, 600, 1000, "a window near the parent's bottom edge snaps to it")
expectLanding(one, 405, 215, 402, 222, "a window just off the target's corner snaps corner to corner")

local TALL_HEIGHT = 400
local tall = Snap.positions({ target }, WIDTH, TALL_HEIGHT, PARENT_WIDTH, PARENT_HEIGHT, EDGE_OFFSET)
local tallX = Snap.apply(tall, 407, 200, WIDTH, TALL_HEIGHT, DISTANCE)
expect(tallX, 402, "a window taller than the target still snaps beside it")

local nearer = { x = 507, y = 200, width = 50, height = 300 }
expectLanding(positionsFor({ target, nearer }), 407, 320, 409, 320, "of two entries in range, the nearer one wins")

local tied = { x = 118, y = 300, width = 200, height = 150 }
expectLanding(positionsFor({ tied }), 10, 320, 0, 320, "on a tie, the parent's edge wins because it comes first")

local function gameWindow(x, y, width, height, shown)
    return { xyGlobal = { x = x, y = y }, width = width, height = height, visibleGlobal = shown }
end

local wideBar = gameWindow(0, 400, 1920, 40, false)
local layoutLayer = {
    interfaceID = 1477, width = 1920, height = 1009, xyGlobal = { x = 0, y = 0 },
    children = {
        gameWindow(0, 0, 1920, 1009, true),
        gameWindow(1533, 48, 387, 334, true),
        gameWindow(1533, 671, 191, 338, false),
        wideBar,
    },
}
function layoutLayer:IterateStaticComponents(callback)
    for _, child in ipairs(self.children) do
        callback(child)
    end
end
local loadedLayoutLayer = layoutLayer
local buildLayer = { interfaceID = 1477, width = 1920, height = 1009, xyGlobal = { x = 10, y = 20 } }

ui = {
    Interfaces = {
        GetInterface = function(_, interfaceID)
            if interfaceID == buildLayer.interfaceID then return {} end
            return nil
        end,
        GetComponent = function(_, packed)
            if packed == id.Component.TOPLEVEL_V2__GAME_AREA then return loadedLayoutLayer end
            return nil
        end,
    },
}
local function prettyWindow(x, y, parent)
    parent = parent or buildLayer
    return {
        parent = parent, interfaceID = parent.interfaceID,
        root = {
            x = x, y = y, width = 300, height = 200,
            xyGlobal = { x = parent.xyGlobal.x + x, y = parent.xyGlobal.y + y },
        },
    }
end

local moving = prettyWindow(100, 100)
local other = prettyWindow(500, 100)
Snap.register(moving)
Snap.register(other)

local started = Snap.start(moving)
expect(#started.across, 10, "the other window and the minimap each add four across entries")
expectPosition(started.across[4], 796, 102, 298, "right of the other window's visible edge")
expectPosition(started.across[7], 1225, 28, 362, "left of the minimap, converted into the build layer's coordinates")
expect(#started.down, 10, "the full screen layer and the closed slot add nothing")

wideBar.visibleGlobal = true
expect(#Snap.start(moving).across, 14, "a shown bar as wide as the screen is still a window")
wideBar.visibleGlobal = false

Snap.unregister(other)
expect(#Snap.start(moving).across, 6, "an unregistered window is no longer a target")
other.root.hidden = true
Snap.register(other)
expect(#Snap.start(moving).across, 6, "a hidden window isn't a target")

local crossParentWindow = prettyWindow(1000, 600, layoutLayer)
Snap.register(crossParentWindow)
local crossParent = Snap.start(moving)
expect(#crossParent.across, 10, "a window in another parent is still a target")
expectPosition(crossParent.across[4], 1286, 582, 778, "right of a window in the layout layer, converted into the build layer's coordinates")

local unloadedLayer = { interfaceID = 1500, xyGlobal = { x = 0, y = 0 } }
local unloadedWindow = prettyWindow(200, 600, unloadedLayer)
Snap.register(unloadedWindow)
expect(#Snap.start(moving).across, 10, "a window whose interface isn't loaded isn't a target")

loadedLayoutLayer = nil
expect(#Snap.start(moving).across, 6, "without the layout layer, only prettyui windows are targets")
loadedLayoutLayer = layoutLayer

local destroyedWindow = prettyWindow(300, 300)
destroyedWindow.root = nil
Snap.register(destroyedWindow)
expect(#Snap.start(moving).across, 10, "a registered window without a root is skipped, not a crash")

local forgottenWindow = prettyWindow(300, 300)
Snap.register(forgottenWindow)
expect(#Snap.start(moving).across, 14, "a registered window is a target while something still holds it")
forgottenWindow = nil
collectgarbage()
expect(#Snap.start(moving).across, 10, "a window nothing else holds drops out of the registry")

print("snap_test: ok")
