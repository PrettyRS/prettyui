local NisLayout = require("src/core/nis_layout")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function expectRect(actual, x, y, width, height, message)
    assert(actual, message .. ": no rectangle")
    expect(actual.x, x, message .. " x")
    expect(actual.y, y, message .. " y")
    expect(actual.width, width, message .. " width")
    expect(actual.height, height, message .. " height")
end

local function containsRect(rects, x, y, width, height)
    for _, rect in ipairs(rects) do
        if rect.x == x and rect.y == y and rect.width == width and rect.height == height then
            return true
        end
    end
    return false
end

local function checkFree(rect, blockers, viewportWidth, viewportHeight, minWidth, minHeight)
    assert(rect, "expected a free rectangle")
    assert(rect.width >= minWidth and rect.height >= minHeight, "rectangle below minimum size")
    assert(rect.x >= 0 and rect.y >= 0, "rectangle outside viewport origin")
    assert(rect.x + rect.width <= viewportWidth and rect.y + rect.height <= viewportHeight,
        "rectangle outside viewport extent")
    for _, obstacle in ipairs(blockers) do
        assert(rect.x + rect.width <= obstacle.x or obstacle.x + obstacle.width <= rect.x
            or rect.y + rect.height <= obstacle.y or obstacle.y + obstacle.height <= rect.y,
            "rectangle intersects an obstacle")
    end
end

local blockers = {
    { x = 0, y = 300, width = 400, height = 400 },
    { x = 520, y = 300, width = 480, height = 400 },
}
local spaces = NisLayout.spaces(blockers, 1000, 700, 64, 17)
local function corridorFit(x, y)
    return NisLayout.fit(spaces, x, y, 300, 200, 0.5, 6)
end
expectRect(corridorFit(460, 450), 400, 300, 120, 400,
    "the panel fills both the width and height bounded by neighboring panels")
expectRect(corridorFit(200, 450), 400, 300, 120, 400,
    "a blocked pointer still fills the nearest bounded gap")
expectRect(corridorFit(200, 100), 50, 94, 300, 200,
    "open placement uses the supplied current dimensions")
for _, pointer in ipairs({ { 460, 450 }, { 200, 450 }, { 200, 100 } }) do
    checkFree(corridorFit(pointer[1], pointer[2]), blockers, 1000, 700, 64, 17)
end

local wideGap = {
    { x = 0, y = 100, width = 200, height = 400 },
    { x = 600, y = 100, width = 400, height = 400 },
}
local wideSpaces = NisLayout.spaces(wideGap, 1000, 700, 64, 17)
local wideTarget = NisLayout.fit(wideSpaces, 400, 250, 200, 60, 0.5, 6)
expectRect(wideTarget, 300, 244, 200, 60, "distant panel pairs do not stretch the panel")
checkFree(wideTarget, wideGap, 1000, 700, 64, 17)
expectRect(NisLayout.fit(wideSpaces, 400, 250, 380, 60, 0.5, 6),
    200, 100, 400, 400, "nearby snap edges still fill and align the panel")
expectRect(NisLayout.fit(wideSpaces, 400, 250, 376, 60, 0.5, 6),
    200, 100, 400, 400, "both edges exactly twelve units away may snap")
expectRect(NisLayout.fit(wideSpaces, 400, 250, 375, 60, 0.5, 6),
    213, 244, 375, 60, "a gap beyond the two-edge snap threshold does not activate")
expectRect(NisLayout.fit(spaces, 460, 100, 120, 400, 0.5, 6),
    400, 94, 120, 400, "a header above the neighbor band is not pulled back into its slot")
expectRect(NisLayout.fit(spaces, 200, 100, 120, 400, 0.5, 6),
    140, 0, 120, 300, "an occupied region may still require shrinking the current height")
local distantWithOffBandEdges = {
    { x = 0, y = 100, width = 100, height = 400 },
    { x = 1100, y = 100, width = 100, height = 400 },
    { x = 400, y = 700, width = 100, height = 100 },
}
expectRect(NisLayout.fit(NisLayout.spaces(distantWithOffBandEdges, 1200, 800, 64, 21),
    250, 250, 300, 80, 0.5, 6), 100, 244, 300, 80,
    "off-band obstacle boundaries do not turn distant panel pairs into nearby slots")

local unevenNeighbors = {
    { x = 0, y = 200, width = 400, height = 400 },
    { x = 520, y = 300, width = 480, height = 380 },
}
local unevenTarget = NisLayout.fit(NisLayout.spaces(unevenNeighbors, 1000, 700, 64, 17),
    460, 450, 300, 200, 0.5, 6)
expectRect(unevenTarget, 400, 300, 120, 300, "neighbors with different heights share only their common band")
checkFree(unevenTarget, unevenNeighbors, 1000, 700, 64, 17)

local stacked = {
    { x = 100, y = 0, width = 500, height = 200 },
    { x = 100, y = 350, width = 500, height = 350 },
}
local stackedTarget = NisLayout.fit(NisLayout.spaces(stacked, 1000, 700, 64, 17),
    350, 275, 200, 140, 0.5, 6)
expectRect(stackedTarget, 100, 200, 500, 150, "a vertical gap fills opposing horizontal panel edges")
checkFree(stackedTarget, stacked, 1000, 700, 64, 17)

local capped = NisLayout.fit(spaces, 460, 450, 300, 200, 0.5, 6, 100, 250)
expectRect(capped, 410, 444, 100, 250, "configured maxima limit automatic slot growth")
checkFree(capped, blockers, 1000, 700, 64, 17)
expectRect(NisLayout.fit(NisLayout.spaces({ blockers[1] }, 1000, 700, 64, 17),
    460, 450, 300, 200, 0.5, 6), 400, 444, 300, 200,
    "a single panel and viewport edge do not create an expanding slot")

local intruding = {
    blockers[1], blockers[2],
    { x = 450, y = 400, width = 20, height = 100 },
}
local intrudingSpaces = NisLayout.spaces(intruding, 1000, 700, 64, 17)
local intrudingTarget = NisLayout.fit(intrudingSpaces, 460, 450, 300, 200, 0.5, 6)
expectRect(intrudingTarget, 400, 500, 120, 200, "an intruder splits a slot without permitting overlap")
checkFree(intrudingTarget, intruding, 1000, 700, 64, 17)
local intrudingReordered = { intruding[3], intruding[2], intruding[1], intruding[3], intruding[2] }
expectRect(NisLayout.fit(NisLayout.spaces(intrudingReordered, 1000, 700, 64, 17),
    460, 450, 300, 200, 0.5, 6), intrudingTarget.x, intrudingTarget.y,
    intrudingTarget.width, intrudingTarget.height,
    "duplicated and reordered obstacles yield the same bounded destination")
local sealedGap = { blockers[1], blockers[2], { x = 400, y = 300, width = 120, height = 400 } }
local sealedTarget = NisLayout.fit(NisLayout.spaces(sealedGap, 1000, 700, 64, 17),
    460, 450, 300, 200, 0.5, 6)
checkFree(sealedTarget, sealedGap, 1000, 700, 64, 17)
assert(sealedTarget.y + sealedTarget.height <= 300,
    "a completely blocked gap falls back to a different free region")
expectRect(NisLayout.spaces({}, 1000.9, 700.9, 64, 17)[1], 0, 0, 1000, 700,
    "empty obstacles expose the whole floored viewport")
expectRect(NisLayout.fit(NisLayout.spaces({}, 1000, 700, 64, 17),
    460, 450, 300, 200, 0.5, 6), 310, 444, 300, 200,
    "open viewport does not grow a panel without opposing bounds")
expect(#NisLayout.spaces({}, 63, 700, 64, 17), 0, "viewport below minimum width")
expect(#NisLayout.spaces({}, 1000, 16, 64, 17), 0, "viewport below minimum height")
expect(#NisLayout.spaces({ { x = 0, y = 0, width = 1000, height = 700 } }, 1000, 700, 64, 17),
    0, "viewport-sized obstacle must not be treated as a wrapper")
expect(NisLayout.fit({}, 460, 450, 300, 200, 0.5, 6), nil,
    "no valid free space returns nil")
local reusedTarget = {}
expect(NisLayout.fit(spaces, 460, 450, 300, 200, 0.5, 6, nil, nil, reusedTarget),
    reusedTarget, "free placement reuses the caller's destination rectangle")
expectRect(reusedTarget, 400, 300, 120, 400, "reused destination includes bounded slot dimensions")
expect(NisLayout.fit(spaces, 200, 100, 300, 200, 0.5, 6, nil, nil, reusedTarget),
    reusedTarget, "a subsequent placement keeps reusing the same rectangle")
expectRect(reusedTarget, 50, 94, 300, 200, "reused destination overwrites stale slot bounds")
expect(NisLayout.fit({}, 460, 450, 300, 200, 0.5, 6, nil, nil, reusedTarget),
    nil, "no free placement does not return the previous destination")

local narrowBlockers = {
    { x = 0, y = 80, width = 120, height = 120 },
    { x = 175, y = 80, width = 125, height = 120 },
}
local narrowSpaces = NisLayout.spaces(narrowBlockers, 300, 200, 64, 17)
for _, space in ipairs(narrowSpaces) do
    assert(not (space.y >= 80 and space.x >= 120 and space.x + space.width <= 175),
        "a 55-unit corridor cannot meet the 64-unit minimum")
end
checkFree(NisLayout.fit(narrowSpaces, 148, 130, 100, 80, 0.5, 6),
    narrowBlockers, 300, 200, 64, 17)

-- The central gap is bounded above and below by different, staggered blockers;
-- overlapping/duplicate blockers must not invent a false gap in their y union.
local staggered = {
    { x = 0, y = 30, width = 40, height = 40 },
    { x = 40, y = 0, width = 40, height = 30 },
    { x = 80, y = 60, width = 40, height = 40 },
    { x = 40, y = 50, width = 40, height = 15 },
    { x = 40, y = 55, width = 40, height = 10 },
}
local staggeredSpaces = NisLayout.spaces(staggered, 120, 100, 20, 17)
assert(containsRect(staggeredSpaces, 40, 30, 40, 20),
    "enumerating all x spans discovers the central staggered gap")
assert(containsRect(staggeredSpaces, 40, 65, 40, 35),
    "overlapping y intervals merge before emitting their complement")
local staggeredTarget = NisLayout.fit(staggeredSpaces, 60, 41, 60, 40, 0.5, 6)
expectRect(staggeredTarget, 40, 30, 40, 20, "nearest staggered gap")
for _, rect in ipairs(staggeredSpaces) do checkFree(rect, staggered, 120, 100, 20, 17) end
checkFree(staggeredTarget, staggered, 120, 100, 20, 17)

local reordered = { staggered[5], staggered[3], staggered[2], staggered[4], staggered[1], staggered[4] }
local reorderedSpaces = NisLayout.spaces(reordered, 120, 100, 20, 17)
expect(#reorderedSpaces, #staggeredSpaces, "duplicates do not change the free-space enumeration")
for index, rect in ipairs(staggeredSpaces) do
    expectRect(reorderedSpaces[index], rect.x, rect.y, rect.width, rect.height,
        "obstacle order and duplication do not affect free spaces " .. index)
end
expectRect(NisLayout.fit(reorderedSpaces, 60, 41, 60, 40, 0.5, 6),
    40, 30, 40, 20, "obstacle order and duplication do not affect the target")

local touching = {
    { x = 0, y = 0, width = 100, height = 100 },
    { x = 150, y = 0, width = 150, height = 100 },
}
local touchingSpaces = NisLayout.spaces(touching, 300, 100, 50, 17)
expectRect(NisLayout.fit(touchingSpaces, 125, 50, 100, 40, 0.5, 6),
    100, 0, 50, 100, "the gap can touch both obstacle edges and fills their shared band")
checkFree(touchingSpaces[1], touching, 300, 100, 50, 17)
expect(#NisLayout.spaces({ touching[1], touching[2],
    { x = 100, y = 0, width = 50, height = 30 },
    { x = 100, y = 30, width = 50, height = 70 },
}, 300, 100, 50, 17), 0, "edge-touching intervals jointly cover a vertical span")

local fractional = { { x = 2.2, y = 3.1, width = 2.1, height = 2.3 } }
local fractionalSpaces = NisLayout.spaces(fractional, 10.9, 10.8, 1, 1)
assert(containsRect(fractionalSpaces, 2, 0, 3, 3),
    "fractional obstacle bounds expand outward before forming x and y gaps")
for _, rect in ipairs(fractionalSpaces) do
    checkFree(rect, { { x = 2, y = 3, width = 3, height = 3 } }, 10, 10, 1, 1)
end
expectRect(NisLayout.fit(fractionalSpaces, 3, 3, 3, 3, 0, 0), 5, 3, 3, 3,
    "fitting respects the expanded bounds, not the unrounded sprite bounds")
local fractionalGap = {
    { x = 0, y = 10.1, width = 100.2, height = 89.3 },
    { x = 180.8, y = 10, width = 200, height = 90 },
}
local fractionalGapTarget = NisLayout.fit(NisLayout.spaces(fractionalGap, 400, 120, 10, 10),
    140, 50, 70, 30, 0.5, 6)
expectRect(fractionalGapTarget, 101, 10, 79, 90,
    "slot edges use outward-rounded neighboring panel bounds")
checkFree(fractionalGapTarget, fractionalGap, 400, 120, 10, 10)
local clipped = NisLayout.spaces({
    { x = -3.2, y = -4, width = 5, height = 8.2 },
    { x = 50, y = 50, width = 10, height = 10 },
    { x = 4, y = 4, width = 0, height = 8 },
}, 10, 10, 1, 1)
for _, rect in ipairs(clipped) do
    checkFree(rect, { { x = 0, y = 0, width = 2, height = 5 } }, 10, 10, 1, 1)
end

expectRect(NisLayout.fit({ { x = 3, y = 4, width = 20, height = 20 } },
    15, 10, 10, 10, 0.25, 2.5), 13, 8, 10, 10,
    "desired grip position rounds with floor(value + 0.5)")
expectRect(NisLayout.fit({ { x = 3, y = 4, width = 20, height = 20 } },
    100, 100, 10, 10, 0.25, 2.5), 13, 14, 10, 10,
    "rounded origin clamps within a free rectangle")
expectRect(NisLayout.fit({
    { x = 40, y = 40, width = 20, height = 20 },
    { x = 0, y = 0, width = 100, height = 25 },
}, 50, 50, 100, 25, 0.5, 6), 40, 40, 20, 20,
    "grip distance wins before destination area")
expectRect(NisLayout.fit({
    { x = 0, y = 0, width = 20, height = 20 },
    { x = 0, y = 0, width = 40, height = 20 },
}, 0, 0, 40, 20, 0, 0), 0, 0, 40, 20,
    "area wins when grip distance ties")
expectRect(NisLayout.fit({
    { x = 0, y = 20, width = 10, height = 10 },
    { x = 0, y = 0, width = 10, height = 10 },
}, 0, 10, 10, 10, 0, 0), 0, 0, 10, 10,
    "y wins on equal distance and area")
expectRect(NisLayout.fit({
    { x = 20, y = 0, width = 10, height = 10 },
    { x = 0, y = 0, width = 10, height = 10 },
}, 10, 0, 10, 10, 0, 0), 0, 0, 10, 10,
    "x wins on equal distance, area and y")
expectRect(NisLayout.fit({
    { x = 0, y = 0, width = 20, height = 20 },
    { x = 0, y = 0, width = 40, height = 10 },
}, 0, 0, 40, 20, 0, 0), 0, 0, 40, 10,
    "width wins on equal distance, area, x and y")

print("nis layout tests passed")
