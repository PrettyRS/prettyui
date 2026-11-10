local NisLayout = {}
local SNAP_DISTANCE = 12

-- Obstacles and output coordinates are in the moving panel's parent interface units.
function NisLayout.spaces(rects, parentWidth, parentHeight, minWidth, minHeight)
    local width = math.floor(parentWidth)
    local height = math.floor(parentHeight)
    local result = { slots = {} }
    if width < minWidth or height < minHeight then return result end

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

    table.sort(boundaries)
    table.sort(obstacles, function(a, b)
        if a.top ~= b.top then return a.top < b.top end
        return a.bottom < b.bottom
    end)

    -- Keep the exhaustive free rectangles for the nearest-position fallback.
    -- A slot additionally needs two facing panel edges, never just a viewport edge.
    local count = 0
    for index, left in ipairs(boundaries) do
        if index == 1 or left ~= boundaries[index - 1] then
            for nextIndex = index + 1, #boundaries do
                local right = boundaries[nextIndex]
                if right - left >= minWidth and right ~= boundaries[nextIndex - 1] then
                    local freeTop = 0
                    for _, obstacle in ipairs(obstacles) do
                        if obstacle.left < right and obstacle.right > left then
                            if obstacle.top > freeTop and obstacle.top - freeTop >= minHeight then
                                count = count + 1
                                result[count] = { x = left, y = freeTop, width = right - left, height = obstacle.top - freeTop }
                            end
                            if obstacle.bottom > freeTop then freeTop = obstacle.bottom end
                        end
                    end
                    if height - freeTop >= minHeight then
                        count = count + 1
                        result[count] = { x = left, y = freeTop, width = right - left, height = height - freeTop }
                    end
                end
            end
        end
    end
    local slots = result.slots
    local function addSlot(left, top, right, bottom, axis)
        if right - left < minWidth or bottom - top < minHeight then return end
        for _, space in ipairs(result) do
            local x = math.max(left, space.x)
            local y = math.max(top, space.y)
            local xEnd = math.min(right, space.x + space.width)
            local yEnd = math.min(bottom, space.y + space.height)
            if xEnd - x >= minWidth and yEnd - y >= minHeight then
                slots[#slots + 1] = {
                    x = x, y = y, width = xEnd - x, height = yEnd - y, axis = axis,
                    span = axis == "x" and right - left or bottom - top,
                }
            end
        end
    end
    for index = 1, #obstacles do
        local first = obstacles[index]
        for nextIndex = index + 1, #obstacles do
            local second = obstacles[nextIndex]
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
    end
    table.sort(slots, function(a, b)
        if a.axis ~= b.axis then return a.axis < b.axis end
        if a.x ~= b.x then return a.x < b.x end
        if a.y ~= b.y then return a.y < b.y end
        if a.width ~= b.width then return a.width < b.width end
        if a.height ~= b.height then return a.height < b.height end
        return a.span < b.span
    end)
    local unique = 0
    for _, slot in ipairs(slots) do
        local previous = slots[unique]
        if not previous or previous.axis ~= slot.axis or previous.x ~= slot.x
            or previous.y ~= slot.y or previous.width ~= slot.width or previous.height ~= slot.height then
            unique = unique + 1
            slots[unique] = slot
        end
    end
    for index = #slots, unique + 1, -1 do slots[index] = nil end
    return result
end

function NisLayout.fit(spaces, pointerX, pointerY, currentWidth, currentHeight, gripFractionX, gripY,
    maxWidth, maxHeight)
    local bestX, bestY, bestWidth, bestHeight, bestDistance, bestArea
    local fittingWidth = math.min(currentWidth, maxWidth or currentWidth)
    local fittingHeight = math.min(currentHeight, maxHeight or currentHeight)
    for _, space in ipairs(spaces) do
        local width = math.min(fittingWidth, space.width)
        local height = math.min(fittingHeight, space.height)
        if width > 0 and height > 0 then
            local x = math.max(space.x, math.min(space.x + space.width - width,
                math.floor(pointerX - gripFractionX * width + 0.5)))
            local y = math.max(space.y, math.min(space.y + space.height - height,
                math.floor(pointerY - gripY + 0.5)))
            local dx = x + gripFractionX * width - pointerX
            local dy = y + gripY - pointerY
            local distance = dx * dx + dy * dy
            local area = width * height
            local better = bestDistance == nil or distance < bestDistance
            if not better and distance == bestDistance then
                if area ~= bestArea then
                    better = area > bestArea
                elseif y ~= bestY then
                    better = y < bestY
                elseif x ~= bestX then
                    better = x < bestX
                elseif width ~= bestWidth then
                    better = width > bestWidth
                else
                    better = height > bestHeight
                end
            end
            if better then
                bestX, bestY, bestWidth, bestHeight = x, y, width, height
                bestDistance, bestArea = distance, area
            end
        end
    end
    if bestDistance == nil then return nil end
    -- First choose the nearest ordinary placement. A bounded slot only modifies
    -- that destination; it cannot pull the panel into a more distant gap.
    local selected, selectedOverlap, selectedArea
    for _, slot in ipairs(spaces.slots or {}) do
        local right, bottom = slot.x + slot.width, slot.y + slot.height
        local overlap
        if slot.axis == "x" and bestX >= slot.x and bestX + bestWidth <= right
            and pointerY >= slot.y - SNAP_DISTANCE and pointerY <= bottom + SNAP_DISTANCE
            and slot.span <= fittingWidth + SNAP_DISTANCE * 2
            and (slot.width <= fittingWidth or
                (bestX - slot.x <= SNAP_DISTANCE and right - bestX - bestWidth <= SNAP_DISTANCE)) then
            overlap = math.min(bestY + bestHeight, bottom) - math.max(bestY, slot.y)
            if overlap > 0 then overlap = overlap * bestWidth end
        elseif slot.axis == "y" and bestY >= slot.y and bestY + bestHeight <= bottom
            and pointerX >= slot.x - SNAP_DISTANCE and pointerX <= right + SNAP_DISTANCE
            and slot.span <= fittingHeight + SNAP_DISTANCE * 2
            and (slot.height <= fittingHeight or
                (bestY - slot.y <= SNAP_DISTANCE and bottom - bestY - bestHeight <= SNAP_DISTANCE)) then
            overlap = math.min(bestX + bestWidth, right) - math.max(bestX, slot.x)
            if overlap > 0 then overlap = overlap * bestHeight end
        end
        if overlap and overlap > 0 then
            local area = slot.width * slot.height
            local better = not selected or overlap > selectedOverlap
            if selected and overlap == selectedOverlap then
                if area ~= selectedArea then
                    better = area > selectedArea
                elseif slot.y ~= selected.y then
                    better = slot.y < selected.y
                elseif slot.x ~= selected.x then
                    better = slot.x < selected.x
                elseif slot.width ~= selected.width then
                    better = slot.width > selected.width
                elseif slot.height ~= selected.height then
                    better = slot.height > selected.height
                else
                    better = slot.axis < selected.axis
                end
            end
            if better then selected, selectedOverlap, selectedArea = slot, overlap, area end
        end
    end
    if selected then
        local width = math.min(selected.width, maxWidth or selected.width)
        local height = math.min(selected.height, maxHeight or selected.height)
        bestX = math.max(selected.x, math.min(bestX, selected.x + selected.width - width))
        bestY = math.max(selected.y, math.min(bestY, selected.y + selected.height - height))
        bestWidth, bestHeight = width, height
    end
    return { x = bestX, y = bestY, width = bestWidth, height = bestHeight }
end

return NisLayout
