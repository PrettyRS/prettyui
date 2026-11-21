local NisLayout = require("src/nis/layout")

local function expectRect(actual, x, y, width, height, message)
    assert(actual, message .. ": no placement")
    assert(
        actual.x == x and actual.y == y and actual.width == width and actual.height == height,
        message
            .. ": expected "
            .. x
            .. ","
            .. y
            .. " "
            .. width
            .. "x"
            .. height
            .. ", got "
            .. actual.x
            .. ","
            .. actual.y
            .. " "
            .. actual.width
            .. "x"
            .. actual.height
    )
end

local function checkFree(rect, obstacles, viewportWidth, viewportHeight, minWidth, minHeight)
    assert(rect, "expected a free placement")
    assert(rect.width >= minWidth and rect.height >= minHeight, "placement below minimum size")
    assert(
        rect.x >= 0 and rect.y >= 0 and rect.x + rect.width <= viewportWidth and rect.y + rect.height <= viewportHeight,
        "placement outside viewport"
    )
    for _, obstacle in ipairs(obstacles) do
        assert(
            rect.x + rect.width <= obstacle.x
                or obstacle.x + obstacle.width <= rect.x
                or rect.y + rect.height <= obstacle.y
                or obstacle.y + obstacle.height <= rect.y,
            "placement overlaps native UI"
        )
    end
end

local function fitsBetweenPanels()
    local obstacles = {
        { x = 0, y = 300, width = 400, height = 400 },
        { x = 520, y = 300, width = 480, height = 400 },
    }
    local spaces = NisLayout.spaces(obstacles, 1000, 700, 64, 17)
    for _, case in ipairs({
        { "bounded gap", 460, 450, 300, 200, 400, 300, 120, 400 },
        { "blocked pointer seeks free gap", 200, 450, 300, 200, 400, 300, 120, 400 },
        { "open area keeps panel size", 200, 100, 300, 200, 50, 94, 300, 200 },
        { "header outside neighbor band", 460, 100, 120, 400, 400, 94, 120, 400 },
    }) do
        local name, px, py, width, height, x, y, fittedWidth, fittedHeight = table.unpack(case)
        local target = NisLayout.fit(spaces, px, py, width, height, 0.5, 6)
        expectRect(target, x, y, fittedWidth, fittedHeight, name)
        checkFree(target, obstacles, 1000, 700, 64, 17)
    end
    local capped = NisLayout.fit(spaces, 460, 450, 300, 200, 0.5, 6, 100, 250)
    expectRect(capped, 410, 444, 100, 250, "maximum panel dimensions cap slot growth")
    checkFree(capped, obstacles, 1000, 700, 64, 17)
end

local function avoidsFalseSlotsAndObstacles()
    local wide = {
        { x = 0, y = 100, width = 200, height = 400 },
        { x = 600, y = 100, width = 400, height = 400 },
    }
    local spaces = NisLayout.spaces(wide, 1000, 700, 64, 17)
    for _, case in ipairs({
        { "distant panels do not stretch", 200, 300, 244, 200, 60 },
        { "nearby opposing edges snap", 380, 200, 100, 400, 400 },
        { "outside snap range keeps size", 375, 213, 244, 375, 60 },
    }) do
        local name, width, x, y, fittedWidth, fittedHeight = table.unpack(case)
        local target = NisLayout.fit(spaces, 400, 250, width, 60, 0.5, 6)
        expectRect(target, x, y, fittedWidth, fittedHeight, name)
        checkFree(target, wide, 1000, 700, 64, 17)
    end
    local staggeredNeighbors = {
        { x = 0, y = 200, width = 400, height = 400 },
        { x = 520, y = 300, width = 480, height = 380 },
    }
    local target = NisLayout.fit(NisLayout.spaces(staggeredNeighbors, 1000, 700, 64, 17), 460, 450, 300, 200, 0.5, 6)
    expectRect(target, 400, 300, 120, 300, "uneven panels fill only their shared band")
    checkFree(target, staggeredNeighbors, 1000, 700, 64, 17)

    local stacked = {
        { x = 100, y = 0, width = 500, height = 200 },
        { x = 100, y = 350, width = 500, height = 350 },
    }
    target = NisLayout.fit(NisLayout.spaces(stacked, 1000, 700, 64, 17), 350, 275, 200, 140, 0.5, 6)
    expectRect(target, 100, 200, 500, 150, "gap between stacked panels fills shared edges")
    checkFree(target, stacked, 1000, 700, 64, 17)

    local corridor = {
        { x = 0, y = 300, width = 400, height = 400 },
        { x = 520, y = 300, width = 480, height = 400 },
    }
    local intruder = { corridor[1], corridor[2], { x = 450, y = 400, width = 20, height = 100 } }
    target = NisLayout.fit(NisLayout.spaces(intruder, 1000, 700, 64, 17), 460, 450, 300, 200, 0.5, 6)
    expectRect(target, 400, 500, 120, 200, "intruding panel splits the corridor")
    checkFree(target, intruder, 1000, 700, 64, 17)
    local sealed = { corridor[1], corridor[2], { x = 400, y = 300, width = 120, height = 400 } }
    target = NisLayout.fit(NisLayout.spaces(sealed, 1000, 700, 64, 17), 460, 450, 300, 200, 0.5, 6)
    checkFree(target, sealed, 1000, 700, 64, 17)
    assert(target.y + target.height <= 300, "sealed corridor falls back above native UI")
end

local function handlesStaggeredAndFractionalObstacles()
    local staggered = {
        { x = 0, y = 30, width = 40, height = 40 },
        { x = 40, y = 0, width = 40, height = 30 },
        { x = 80, y = 60, width = 40, height = 40 },
        { x = 40, y = 50, width = 40, height = 15 },
        { x = 40, y = 55, width = 40, height = 10 },
    }
    local spaces = NisLayout.spaces(staggered, 120, 100, 20, 17)
    local target = NisLayout.fit(spaces, 60, 41, 60, 40, 0.5, 6)
    expectRect(target, 40, 30, 40, 20, "staggered and overlapping panels leave a small safe gap")
    for _, space in ipairs(spaces) do
        checkFree(space, staggered, 120, 100, 20, 17)
    end
    local reordered = { staggered[5], staggered[3], staggered[2], staggered[4], staggered[1], staggered[4] }
    expectRect(
        NisLayout.fit(NisLayout.spaces(reordered, 120, 100, 20, 17), 60, 41, 60, 40, 0.5, 6),
        40,
        30,
        40,
        20,
        "duplicate/reordered panels still find the gap"
    )

    local fractional = {
        { x = 0, y = 10.1, width = 100.2, height = 89.3 },
        { x = 180.8, y = 10, width = 200, height = 90 },
    }
    target = NisLayout.fit(NisLayout.spaces(fractional, 400, 120, 10, 10), 140, 50, 70, 30, 0.5, 6)
    expectRect(target, 101, 10, 79, 90, "fractional native bounds round outward before fitting")
    checkFree(target, fractional, 400, 120, 10, 10)
end

local function respectsViewportAndMinimumSize()
    local narrow = {
        { x = 0, y = 80, width = 120, height = 120 },
        { x = 175, y = 80, width = 125, height = 120 },
    }
    local spaces = NisLayout.spaces(narrow, 300, 200, 64, 17)
    for _, space in ipairs(spaces) do
        assert(
            not (space.y >= 80 and space.x >= 120 and space.x + space.width <= 175),
            "a corridor narrower than the panel minimum is not available"
        )
    end
    checkFree(NisLayout.fit(spaces, 148, 130, 100, 80, 0.5, 6), narrow, 300, 200, 64, 17)
    assert(#NisLayout.spaces({}, 63, 700, 64, 17) == 0, "viewport below minimum width")
    assert(
        #NisLayout.spaces({ { x = 0, y = 0, width = 1000, height = 700 } }, 1000, 700, 64, 17) == 0,
        "covered viewport has no free space"
    )
    assert(NisLayout.fit({}, 460, 450, 300, 200, 0.5, 6) == nil, "no free space rejects placement")
end

fitsBetweenPanels()
avoidsFalseSlotsAndObstacles()
handlesStaggeredAndFractionalObstacles()
respectsViewportAndMinimumSize()
print("nis layout tests passed")
