id = {
    Component = { TOPLEVEL_V2__GAME_AREA = (1477 << 16) | 61 },
    Interface = {
        TOPLEVEL_V2_MINIMAP = 1465, TOPLEVEL_V2_COMPASS = 1504, TOPLEVEL_V2_INVENTORY = 1473, XP_POPUP = 1213,
        CLOSED_INTERFACE = 999,
    },
}

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
local WIDTH, HEIGHT, INSET = 100, 80, 2
local target = { x = 500, y = 300, width = 200, height = 150 }

local function positionsFor(rects, inset)
    return Snap.positions(rects, WIDTH, HEIGHT, PARENT_WIDTH, PARENT_HEIGHT, inset or INSET)
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

local noInset = positionsFor({ target }, 0)
expect(noInset.across[3].at, 400, "without an inset the window's right side meets the target's left side")
expect(noInset.across[4].at, 700, "without an inset the window starts at the target's right side")
expect(noInset.down[4].at, 450, "without an inset the window starts at the target's bottom")
expect(noInset.across[1].at, 0, "the parent's edges never take the inset")

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
expectLanding(one, 6, 600, 0, 600, "a window near the parent's left edge snaps to it")
expectLanding(one, 600, 995, 600, 1000, "a window near the parent's bottom edge snaps to it")

expectLanding(one, 407, 320, 402, 320, "a window snaps while it's close")
expectLanding(one, 420, 320, 420, 320, "moving it past the snap distance takes it off the snap")

local nearer = { x = 507, y = 200, width = 50, height = 300 }
expectLanding(positionsFor({ target, nearer }), 407, 320, 409, 320, "of two entries in range, the nearer one wins")

local tied = { x = 118, y = 300, width = 200, height = 150 }
expectLanding(positionsFor({ tied }), 10, 320, 0, 320, "on a tie, the parent's edge wins because it comes first")

local screen = { interfaceID = 1477, staticID = 28, width = 1920, height = 1009 }
local layout = { interfaceID = 1477, staticID = 61, parent = screen, width = 1920, height = 1009 }
local overlays = { interfaceID = 1477, staticID = 578, parent = screen, width = 1920, height = 1009 }
local minimapFrame = {
    interfaceID = 1477, staticID = 94, parent = layout, width = 387, height = 334, xyGlobal = { x = 1533, y = 48 },
}
local hiddenFrame = {
    interfaceID = 1477, staticID = 103, parent = layout, width = 191, height = 338, xyGlobal = { x = 1533, y = 671 },
    visibleGlobal = false,
}
local popupFrame = {
    interfaceID = 1477, staticID = 671, parent = overlays, width = 400, height = 60, xyGlobal = { x = 747, y = 0 },
}
local roots = {
    [1465] = { interfaceID = 1465, staticID = 0, parent = minimapFrame },
    [1504] = { interfaceID = 1504, staticID = 0, parent = minimapFrame },
    [1473] = { interfaceID = 1473, staticID = 0, parent = hiddenFrame },
    [1213] = { interfaceID = 1213, staticID = 0, parent = popupFrame },
}
local buildLayer = { interfaceID = 1477, width = 1920, height = 1009, xyGlobal = { x = 10, y = 20 } }

ui = {
    Interfaces = {
        GetInterface = function(_, interfaceID)
            if interfaceID == buildLayer.interfaceID or roots[interfaceID] then return {} end
            return nil
        end,
        GetComponent = function(_, packed) return roots[packed >> 16] end,
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
expectPosition(started.across[4], 796, 102, 298, "right of the other window's visible frame")
expectPosition(started.across[7], 1225, 28, 362, "left of the minimap, converted into the build layer's coordinates")
expect(#started.down, 10, "the compass shares the minimap's frame, so it adds nothing more")

Snap.unregister(other)
expect(#Snap.start(moving).across, 6, "an unregistered window is no longer a target")
other.root.hidden = true
Snap.register(other)
expect(#Snap.start(moving).across, 6, "a hidden window isn't a target")

local gameArea = { interfaceID = 1477, width = 1920, height = 1009, xyGlobal = { x = 0, y = 0 } }
Snap.register(prettyWindow(1000, 600, gameArea))
local crossParent = Snap.start(moving)
expect(#crossParent.across, 10, "a window in another parent is still a target")
expectPosition(crossParent.across[4], 1286, 582, 778, "right of a game area window, converted into the build layer's coordinates")

print("snap_test: ok")
