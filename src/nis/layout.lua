local NisLayout = {}
local SNAP_DISTANCE = 12

local function collectObstacles(rects, width, height)
    local boundaries = { 0, width }
    local obstacles = {}
    for _, rect in ipairs(rects) do
        if rect.width > 0 and rect.height > 0 then
            local left = math.max(0, math.floor(rect.x))
            local top = math.max(0, math.floor(rect.y))
            local right = math.min(width, math.ceil(rect.x + rect.width))
            local bottom = math.min(height, math.ceil(rect.y + rect.height))
            if right > left and bottom > top then
                obstacles[#obstacles + 1] = { left = left, top = top, right = right, bottom = bottom }
                boundaries[#boundaries + 1] = left
                boundaries[#boundaries + 1] = right
            end
        end
    end
    return obstacles, boundaries
end

local function addFreeSpan(result, count, obstacles, left, right, height, minHeight)
    local freeTop, span = 0, right - left
    for _, obstacle in ipairs(obstacles) do
        if obstacle.left < right and obstacle.right > left then
            if obstacle.top > freeTop and obstacle.top - freeTop >= minHeight then
                count = count + 1
                result[count] = { x = left, y = freeTop, width = span, height = obstacle.top - freeTop }
            end
            if obstacle.bottom > freeTop then freeTop = obstacle.bottom end
        end
    end
    if height - freeTop >= minHeight then
        count = count + 1
        result[count] = { x = left, y = freeTop, width = span, height = height - freeTop }
    end
    return count
end

local function addFacingSlots(addSlot, first, second)
    local top = math.max(first.top, second.top)
    local bottom = math.min(first.bottom, second.bottom)
    if top < bottom then
        if first.right < second.left then
            addSlot(first.right, top, second.left, bottom, "x")
        elseif second.right < first.left then
            addSlot(second.right, top, first.left, bottom, "x")
        end
    end
    local left = math.max(first.left, second.left)
    local right = math.min(first.right, second.right)
    if left < right then
        if first.bottom < second.top then
            addSlot(left, first.bottom, right, second.top, "y")
        elseif second.bottom < first.top then
            addSlot(left, second.bottom, right, first.top, "y")
        end
    end
end

-- Obstacles and output coordinates are in the moving panel's parent interface units.
function NisLayout.spaces(rects, parentWidth, parentHeight, minWidth, minHeight)
    local width = math.floor(parentWidth)
    local height = math.floor(parentHeight)
    local result = { slots = {} }
    if width < minWidth or height < minHeight then return result end

    local obstacles, boundaries = collectObstacles(rects, width, height)

    if #obstacles == 0 then
        result[1] = { x = 0, y = 0, width = width, height = height }
        return result
    end

    table.sort(boundaries)
    -- Adjacent panels share edges; enumerate each distinct horizontal span once.
    local uniqueCount = 0
    for index = 1, #boundaries do
        local edge = boundaries[index]
        if edge ~= boundaries[uniqueCount] then
            uniqueCount = uniqueCount + 1
            boundaries[uniqueCount] = edge
        end
    end
    for index = #boundaries, uniqueCount + 1, -1 do
        boundaries[index] = nil
    end
    table.sort(obstacles, function(a, b)
        if a.top ~= b.top then return a.top < b.top end
        return a.bottom < b.bottom
    end)

    -- Keep the exhaustive free rectangles for the nearest-position fallback.
    -- A slot additionally needs two facing panel edges, never just a viewport edge.
    local count = 0
    for index, left in ipairs(boundaries) do
        for nextIndex = index + 1, #boundaries do
            local right = boundaries[nextIndex]
            if right - left >= minWidth then
                count = addFreeSpan(result, count, obstacles, left, right, height, minHeight)
            end
        end
    end
    local slots = result.slots
    -- Deduplicate clipped slots before allocating and sorting them.
    local seenSlots = { x = {}, y = {} }
    local function addSlot(left, top, right, bottom, axis)
        if right - left < minWidth or bottom - top < minHeight then return end
        local span = axis == "x" and right - left or bottom - top
        -- Free rectangles were emitted in ascending left-edge order.
        for _, space in ipairs(result) do
            if space.x >= right then break end
            local x = math.max(left, space.x)
            local y = math.max(top, space.y)
            local xEnd = math.min(right, space.x + space.width)
            local yEnd = math.min(bottom, space.y + space.height)
            if xEnd - x >= minWidth and yEnd - y >= minHeight then
                local across = seenSlots[axis]
                local xKey = x * (width + 1) + xEnd - x
                local yKey = y * (height + 1) + yEnd - y
                local column = across[xKey]
                if not column then
                    column = {}
                    across[xKey] = column
                end
                local slot = column[yKey]
                if not slot then
                    slot = {
                        x = x,
                        y = y,
                        width = xEnd - x,
                        height = yEnd - y,
                        axis = axis,
                        span = span,
                    }
                    column[yKey] = slot
                    slots[#slots + 1] = slot
                elseif span < slot.span then
                    slot.span = span
                end
            end
        end
    end
    for index = 1, #obstacles do
        local first = obstacles[index]
        for nextIndex = index + 1, #obstacles do
            addFacingSlots(addSlot, first, obstacles[nextIndex])
        end
    end
    table.sort(slots, function(a, b)
        if a.axis ~= b.axis then return a.axis < b.axis end
        if a.x ~= b.x then return a.x < b.x end
        if a.y ~= b.y then return a.y < b.y end
        if a.width ~= b.width then return a.width < b.width end
        if a.height ~= b.height then return a.height < b.height end
        return a.span < b.span
    end)
    return result
end

local function preferPlacement(area, y, x, width, height, bestArea, bestY, bestX, bestWidth, bestHeight)
    if area ~= bestArea then return area > bestArea end
    if y ~= bestY then return y < bestY end
    if x ~= bestX then return x < bestX end
    if width ~= bestWidth then return width > bestWidth end
    return height > bestHeight
end

local function nearestPlacement(spaces, pointerX, pointerY, fittingWidth, fittingHeight, gripFractionX, gripY)
    local bestX, bestY, bestWidth, bestHeight, bestDistance, bestArea
    for _, space in ipairs(spaces) do
        local width = math.min(fittingWidth, space.width)
        local height = math.min(fittingHeight, space.height)
        if width > 0 and height > 0 then
            local x = math.max(
                space.x,
                math.min(space.x + space.width - width, math.floor(pointerX - gripFractionX * width + 0.5))
            )
            local y = math.max(space.y, math.min(space.y + space.height - height, math.floor(pointerY - gripY + 0.5)))
            local dx = x + gripFractionX * width - pointerX
            local dy = y + gripY - pointerY
            local distance = dx * dx + dy * dy
            local area = width * height
            local better = bestDistance == nil or distance < bestDistance
            if not better and distance == bestDistance then
                better = preferPlacement(area, y, x, width, height, bestArea, bestY, bestX, bestWidth, bestHeight)
            end
            if better then
                bestX, bestY, bestWidth, bestHeight = x, y, width, height
                bestDistance, bestArea = distance, area
            end
        end
    end
    return bestX, bestY, bestWidth, bestHeight
end

local function preferSlot(slot, selected, area, selectedArea)
    if area ~= selectedArea then return area > selectedArea end
    if slot.y ~= selected.y then return slot.y < selected.y end
    if slot.x ~= selected.x then return slot.x < selected.x end
    if slot.width ~= selected.width then return slot.width > selected.width end
    if slot.height ~= selected.height then return slot.height > selected.height end
    return slot.axis < selected.axis
end

local function slotOverlap(slot, pointerX, pointerY, fittingWidth, fittingHeight, x, y, width, height)
    local right, bottom = slot.x + slot.width, slot.y + slot.height
    if
        slot.axis == "x"
        and x >= slot.x
        and x + width <= right
        and pointerY >= slot.y - SNAP_DISTANCE
        and pointerY <= bottom + SNAP_DISTANCE
        and slot.span <= fittingWidth + SNAP_DISTANCE * 2
        and (slot.width <= fittingWidth or (x - slot.x <= SNAP_DISTANCE and right - x - width <= SNAP_DISTANCE))
    then
        local overlap = math.min(y + height, bottom) - math.max(y, slot.y)
        if overlap > 0 then return overlap * width end
    elseif
        slot.axis == "y"
        and y >= slot.y
        and y + height <= bottom
        and pointerX >= slot.x - SNAP_DISTANCE
        and pointerX <= right + SNAP_DISTANCE
        and slot.span <= fittingHeight + SNAP_DISTANCE * 2
        and (slot.height <= fittingHeight or (y - slot.y <= SNAP_DISTANCE and bottom - y - height <= SNAP_DISTANCE))
    then
        local overlap = math.min(x + width, right) - math.max(x, slot.x)
        if overlap > 0 then return overlap * height end
    end
end

local function chooseSlot(slots, pointerX, pointerY, fittingWidth, fittingHeight, x, y, width, height)
    local selected, selectedOverlap, selectedArea
    if not slots then return nil end
    for _, slot in ipairs(slots) do
        local overlap = slotOverlap(slot, pointerX, pointerY, fittingWidth, fittingHeight, x, y, width, height)
        if overlap and overlap > 0 then
            local area = slot.width * slot.height
            local better = not selected or overlap > selectedOverlap
            if selected and overlap == selectedOverlap then
                better = preferSlot(slot, selected, area, selectedArea)
            end
            if better then
                selected, selectedOverlap, selectedArea = slot, overlap, area
            end
        end
    end
    return selected
end

function NisLayout.fit(
    spaces,
    pointerX,
    pointerY,
    currentWidth,
    currentHeight,
    gripFractionX,
    gripY,
    maxWidth,
    maxHeight,
    result
)
    local fittingWidth = math.min(currentWidth, maxWidth or currentWidth)
    local fittingHeight = math.min(currentHeight, maxHeight or currentHeight)
    local bestX, bestY, bestWidth, bestHeight =
        nearestPlacement(spaces, pointerX, pointerY, fittingWidth, fittingHeight, gripFractionX, gripY)
    if bestX == nil then return nil end

    -- A bounded slot can modify the nearest placement, not pull it into a more distant gap.
    local selected =
        chooseSlot(spaces.slots, pointerX, pointerY, fittingWidth, fittingHeight, bestX, bestY, bestWidth, bestHeight)
    if selected then
        local width = math.min(selected.width, maxWidth or selected.width)
        local height = math.min(selected.height, maxHeight or selected.height)
        bestX = math.max(selected.x, math.min(bestX, selected.x + selected.width - width))
        bestY = math.max(selected.y, math.min(bestY, selected.y + selected.height - height))
        bestWidth, bestHeight = width, height
    end
    result = result or {}
    result.x, result.y, result.width, result.height = bestX, bestY, bestWidth, bestHeight
    return result
end

return NisLayout
