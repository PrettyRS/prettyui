local Snap = {}
local windows = setmetatable({}, { __mode = "k" })

local function add(list, at, from, to)
    list[#list + 1] = { at = at, from = from, to = to }
end

-- inset lines up the drawn frames, which sit inside each box
function Snap.positions(rects, width, height, parentWidth, parentHeight, inset)
    local across, down = {}, {}
    add(across, 0, -math.huge, math.huge)
    add(across, parentWidth - width, -math.huge, math.huge)
    add(down, 0, -math.huge, math.huge)
    add(down, parentHeight - height, -math.huge, math.huge)
    for _, rect in ipairs(rects) do
        local left, top = rect.x, rect.y
        local right, bottom = rect.x + rect.width, rect.y + rect.height
        add(across, left - width + inset, top, bottom)
        add(across, right - inset, top, bottom)
        add(across, left - inset, top, bottom)
        add(across, right - width + inset, top, bottom)
        add(down, top - height + inset, left, right)
        add(down, bottom - inset, left, right)
        add(down, top - inset, left, right)
        add(down, bottom - height + inset, left, right)
    end
    return { across = across, down = down }
end

local function closest(list, value, start, size, distance)
    local snapped, snappedGap = value, math.huge
    for _, position in ipairs(list) do
        if start < position.to + distance and start + size > position.from - distance then
            local gap = math.abs(value - position.at)
            if gap <= distance and gap < snappedGap then
                snapped, snappedGap = position.at, gap
            end
        end
    end
    return snapped
end

function Snap.apply(positions, x, y, width, height, distance)
    local snappedX = closest(positions.across, x, y, height, distance)
    local snappedY = closest(positions.down, y, x, width, distance)
    return snappedX, snappedY
end

return Snap
