local NisResize = require("src/nis/resize")

local edges = {
    e = { east = true },
    w = { west = true },
    n = { north = true },
    s = { south = true },
    ne = { north = true, east = true },
    nw = { north = true, west = true },
    se = { south = true, east = true },
    sw = { south = true, west = true },
}

local function expect(rects, source, requested, edge, result, message)
    local x, y, width, height = NisResize.constrain(
        rects,
        source[1],
        source[2],
        source[3],
        source[4],
        requested[1],
        requested[2],
        requested[3],
        requested[4],
        edges[edge]
    )
    if result == nil then
        assert(x == nil, message .. ": unsafe request must be rejected")
        return
    end
    local actual = { x, y, width, height }
    for index, key in ipairs({ "x", "y", "width", "height" }) do
        assert(
            actual[index] == result[index],
            message .. " " .. key .. ": expected " .. result[index] .. ", got " .. tostring(actual[index])
        )
    end
    for _, rect in ipairs(rects) do
        local left, top = math.floor(rect.x), math.floor(rect.y)
        local right, bottom = math.ceil(rect.x + rect.width), math.ceil(rect.y + rect.height)
        assert(
            rect.width <= 0 or rect.height <= 0 or x >= right or x + width <= left or y >= bottom or y + height <= top,
            message .. ": result overlaps native panel"
        )
    end
end

local function constrainedEdges()
    local source = { 100, 100, 100, 80 }
    for _, case in ipairs({
        {
            "east",
            "e",
            { x = 230, y = 110, width = 20, height = 40 },
            { 100, 100, 260, 80 },
            { 100, 100, 130, 80 },
        },
        {
            "west",
            "w",
            { x = 60, y = 110, width = 20, height = 40 },
            { 20, 100, 180, 80 },
            { 80, 100, 120, 80 },
        },
        {
            "north",
            "n",
            { x = 110, y = 60, width = 40, height = 20 },
            { 100, 20, 100, 160 },
            { 100, 80, 100, 100 },
        },
        {
            "south",
            "s",
            { x = 110, y = 220, width = 40, height = 20 },
            { 100, 100, 100, 220 },
            { 100, 100, 100, 120 },
        },
        {
            "southeast corner",
            "se",
            { x = 220, y = 200, width = 20, height = 20 },
            { 100, 100, 180, 150 },
            { 100, 100, 120, 150 },
        },
        {
            "northwest corner",
            "nw",
            { x = 70, y = 70, width = 20, height = 20 },
            { 50, 50, 150, 130 },
            { 90, 50, 110, 130 },
        },
    }) do
        expect({ case[3] }, source, case[4], case[2], case[5], case[1])
    end
end

local function shrinkingOneAxisCanFreeTheOther()
    local source = { 100, 100, 100, 80 }
    expect(
        { { x = 215, y = 100, width = 20, height = 45 } },
        source,
        { 100, 150, 160, 30 },
        "ne",
        { 100, 150, 160, 30 },
        "north shrink vacates blocker before east expansion"
    )
    expect(
        { { x = 150, y = 220, width = 20, height = 20 } },
        source,
        { 100, 100, 60, 160 },
        "se",
        { 100, 100, 60, 120 },
        "east shrink constrains south expansion using the narrower width"
    )
    expect({
        { x = 230, y = 185, width = 20, height = 20 },
        { x = 130, y = 185, width = 20, height = 20 },
    }, source, { 100, 100, 180, 150 }, "se", { 100, 100, 130, 85 }, "corner stops at separate blockers on both axes")
end

local function cannotJumpThroughOrIntoNativePanels()
    local source = { 100, 100, 100, 80 }
    expect({
        { x = 300, y = 110, width = 20, height = 40 },
        { x = 230, y = 110, width = 20, height = 40 },
        { x = 260, y = 110, width = 15, height = 40 },
    }, source, { 100, 100, 350, 80 }, "e", { 100, 100, 130, 80 }, "overshoot stops at the nearest panel, not behind it")
    local overlapping = { { x = 150, y = 120, width = 30, height = 20 } }
    expect(overlapping, source, { 100, 100, 250, 80 }, "e", nil, "pre-overlap cannot grow into a native panel")
    expect(
        overlapping,
        source,
        { 100, 100, 40, 80 },
        "e",
        { 100, 100, 40, 80 },
        "pre-overlap can shrink to a free rectangle"
    )
    expect(overlapping, source, { 160, 100, 40, 80 }, "w", nil, "pre-overlap cannot teleport across a native panel")
end

local function fractionalNativeBoundsRemainSafe()
    local source = { 100, 100, 100, 80 }
    expect(
        { { x = 230.2, y = 110.3, width = 20.1, height = 30.2 } },
        source,
        { 100, 100, 160, 80 },
        "e",
        { 100, 100, 130, 80 },
        "east edge stops before a fractional native boundary"
    )
    expect(
        { { x = 110.2, y = 60.3, width = 39.7, height = 20.2 } },
        source,
        { 100, 20, 100, 160 },
        "n",
        { 100, 81, 100, 99 },
        "north edge stops beyond a fractional native boundary"
    )
end

constrainedEdges()
shrinkingOneAxisCanFreeTheOther()
cannotJumpThroughOrIntoNativePanels()
fractionalNativeBoundsRemainSafe()
print("nis resize tests passed")
