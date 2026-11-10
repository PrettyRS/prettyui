local NisResize = require("src/core/nis_resize")

local edges = {
    e = { east = true }, w = { west = true },
    n = { north = true }, s = { south = true },
    ne = { north = true, east = true },
    nw = { north = true, west = true },
    se = { south = true, east = true },
    sw = { south = true, west = true },
}

local function expect(rects, source, requested, edge, result, message)
    local x, y, width, height = NisResize.constrain(rects,
        source[1], source[2], source[3], source[4],
        requested[1], requested[2], requested[3], requested[4], edges[edge])
    if result == nil then
        assert(x == nil, message .. ": unsafe request must be rejected")
        return
    end
    local actual = { x, y, width, height }
    for index, key in ipairs({ "x", "y", "width", "height" }) do
        assert(actual[index] == result[index],
            message .. " " .. key .. ": expected " .. result[index] .. ", got " .. tostring(actual[index]))
    end
    for _, rect in ipairs(rects) do
        local left, top = math.floor(rect.x), math.floor(rect.y)
        local right, bottom = math.ceil(rect.x + rect.width), math.ceil(rect.y + rect.height)
        assert(rect.width <= 0 or rect.height <= 0 or
            x >= right or x + width <= left or y >= bottom or y + height <= top,
            message .. ": result overlaps native panel")
    end
end

local source = { 100, 100, 100, 80 }
expect({}, source, { 100, 100, 260, 80 }, "e", { 100, 100, 260, 80 },
    "no native panels preserve the ordinary resize result")
expect({ { x = 230, y = 110, width = 20, height = 40 } },
    source, { 100, 100, 260, 80 }, "e", { 100, 100, 130, 80 }, "east edge")
expect({ { x = 60, y = 110, width = 20, height = 40 } },
    source, { 20, 100, 180, 80 }, "w", { 80, 100, 120, 80 }, "west edge")
expect({ { x = 110, y = 60, width = 40, height = 20 } },
    source, { 100, 20, 100, 160 }, "n", { 100, 80, 100, 100 }, "north edge")
expect({ { x = 110, y = 220, width = 40, height = 20 } },
    source, { 100, 100, 100, 220 }, "s", { 100, 100, 100, 120 }, "south edge")

-- A diagonal blocker lies outside both original edge bands, but inside the
-- expanded corner. The final rectangle can touch, never cover, that blocker.
expect({ { x = 220, y = 200, width = 20, height = 20 } },
    source, { 100, 100, 180, 150 }, "se", { 100, 100, 120, 150 }, "southeast diagonal")
expect({ { x = 70, y = 70, width = 20, height = 20 } },
    source, { 50, 50, 150, 130 }, "nw", { 90, 50, 110, 130 }, "northwest diagonal")
expect({ { x = 230, y = 70, width = 20, height = 20 } },
    source, { 100, 50, 180, 130 }, "ne", { 100, 50, 130, 130 }, "northeast diagonal")
expect({ { x = 70, y = 200, width = 20, height = 20 } },
    source, { 50, 100, 150, 150 }, "sw", { 90, 100, 110, 150 }, "southwest diagonal")

-- One corner axis can shrink while the other grows; use the requested band,
-- not the source band, when deciding whether a native panel is in the way.
expect({ { x = 215, y = 100, width = 20, height = 45 } },
    source, { 100, 150, 160, 30 }, "ne", { 100, 150, 160, 30 },
    "north shrink allows east expansion past a vacated blocker")
expect({ { x = 150, y = 220, width = 20, height = 20 } },
    source, { 100, 100, 60, 160 }, "se", { 100, 100, 60, 120 },
    "east shrink leaves south expansion limited by its new width")
expect({ { x = 230, y = 185, width = 20, height = 20 },
    { x = 130, y = 185, width = 20, height = 20 } },
    source, { 100, 100, 180, 150 }, "se", { 100, 100, 130, 85 },
    "corner constrains X and Y against separate blockers")

expect({ { x = 230, y = 100, width = 20, height = 80 } },
    source, { 100, 100, 130, 80 }, "e", { 100, 100, 130, 80 },
    "touching an obstacle edge is not overlap")
expect({ { x = 230.2, y = 110.3, width = 20.1, height = 30.2 } },
    source, { 100, 100, 160, 80 }, "e", { 100, 100, 130, 80 },
    "native left rounds outward")
expect({ { x = 230.2, y = 110.3, width = 20.1, height = 30.2 } },
    { 300, 100, 100, 80 }, { 180, 100, 220, 80 }, "w", { 251, 100, 149, 80 },
    "native right rounds outward")
expect({ { x = 110, y = 200.3, width = 40, height = 15 } },
    source, { 100, 100, 100, 160 }, "s", { 100, 100, 100, 100 },
    "native top rounds outward")
expect({ { x = 110.2, y = 60.3, width = 39.7, height = 20.2 } },
    source, { 100, 20, 100, 160 }, "n", { 100, 81, 100, 99 },
    "native bottom rounds outward")

local blockers = {
    { x = 300, y = 110, width = 20, height = 40 },
    { x = 230, y = 110, width = 20, height = 40 },
    { x = 260, y = 110, width = 15, height = 40 },
}
expect(blockers, source, { 100, 100, 350, 80 }, "e", { 100, 100, 130, 80 },
    "overshoot cannot tunnel through the nearest obstacle")
expect({ blockers[3], blockers[1], blockers[2], blockers[2] },
    source, { 100, 100, 350, 80 }, "e", { 100, 100, 130, 80 },
    "ordering and duplication do not alter the collision limit")

local overlapping = { { x = 150, y = 120, width = 30, height = 20 } }
expect(overlapping, source, { 100, 100, 250, 80 }, "e", nil,
    "a pre-overlapping source cannot grow further into native UI")
expect(overlapping, source, { 100, 100, 40, 80 }, "e", { 100, 100, 40, 80 },
    "a pre-overlapping source may shrink to a genuinely free result")
expect(overlapping, source, { 100, 140, 100, 40 }, "n", { 100, 140, 100, 40 },
    "a pre-overlapping source may clear native UI along the other axis")
expect(overlapping, source, { 160, 100, 40, 80 }, "w", nil,
    "pre-overlap does not permit teleporting across a blocker")

print("nis resize tests passed")
