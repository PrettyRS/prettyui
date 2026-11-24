local floor, ceil = math.floor, math.ceil

local NisResize = {}

-- A resize moves only the grabbed edges. Test the entire swept interval, not
-- just the destination, so a large mouse movement cannot cross a native panel.
-- Corner drags constrain X against the requested Y band, then Y against the
-- resulting X band; this can stop short of a more distant free destination.
function NisResize.constrain(rects, x, y, width, height,
    desiredX, desiredY, desiredWidth, desiredHeight, edge)
    if #rects == 0 then return desiredX, desiredY, desiredWidth, desiredHeight end

    local sourceRight, sourceBottom = x + width, y + height
    local requestedX = desiredX
    local desiredRight = desiredX + desiredWidth
    local desiredBottom = desiredY + desiredHeight
    local sourceOverlaps = false
    local eastGrowth = edge.east and desiredRight > sourceRight
    local westGrowth = edge.west and desiredX < x

    for _, rect in ipairs(rects) do
        if rect.width > 0 and rect.height > 0 then
            local left, top = floor(rect.x), floor(rect.y)
            local right = ceil(rect.x + rect.width)
            local bottom = ceil(rect.y + rect.height)
            if x < right and sourceRight > left and y < bottom and sourceBottom > top then
                sourceOverlaps = true
            end
            if desiredY < bottom and desiredBottom > top then
                if eastGrowth and right > sourceRight and left < desiredRight then
                    desiredRight = math.max(sourceRight, math.min(desiredRight, left))
                elseif westGrowth and left < x and right > desiredX then
                    desiredX = math.min(x, math.max(desiredX, right))
                end
            end
        end
    end

    -- An externally moved native panel may already intersect the source. In
    -- that case only an actually free requested destination is meaningful:
    -- clamping to the old edge could preserve the existing overlap forever.
    if sourceOverlaps then
        desiredX, desiredRight = requestedX, requestedX + desiredWidth
    end

    local northGrowth = edge.north and desiredY < y
    local southGrowth = edge.south and desiredBottom > sourceBottom
    if not sourceOverlaps then
        for _, rect in ipairs(rects) do
            if rect.width > 0 and rect.height > 0 then
                local left, top = floor(rect.x), floor(rect.y)
                local right = ceil(rect.x + rect.width)
                local bottom = ceil(rect.y + rect.height)
                if desiredX < right and desiredRight > left then
                    if southGrowth and bottom > sourceBottom and top < desiredBottom then
                        desiredBottom = math.max(sourceBottom, math.min(desiredBottom, top))
                    elseif northGrowth and top < y and bottom > desiredY then
                        desiredY = math.min(y, math.max(desiredY, bottom))
                    end
                end
            end
        end
    end

    -- Strict overlap makes edge contact legal. It also catches external
    -- changes or unusual resize requests without inventing a forced placement.
    for _, rect in ipairs(rects) do
        if rect.width > 0 and rect.height > 0 then
            if desiredX < ceil(rect.x + rect.width) and desiredRight > floor(rect.x) and
                desiredY < ceil(rect.y + rect.height) and desiredBottom > floor(rect.y) then
                return nil
            end
        end
    end
    return desiredX, desiredY, desiredRight - desiredX, desiredBottom - desiredY
end

return NisResize
