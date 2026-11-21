local floor, ceil = math.floor, math.ceil

local NisResize = {}

local function constrainWidth(
    rects,
    x,
    y,
    sourceRight,
    sourceBottom,
    desiredX,
    desiredY,
    desiredRight,
    desiredBottom,
    edge
)
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
            local crossesBand = desiredY < bottom and desiredBottom > top
            if crossesBand and eastGrowth and right > sourceRight and left < desiredRight then
                desiredRight = math.max(sourceRight, math.min(desiredRight, left))
            elseif crossesBand and westGrowth and left < x and right > desiredX then
                desiredX = math.min(x, math.max(desiredX, right))
            end
        end
    end
    return desiredX, desiredRight, sourceOverlaps
end

local function constrainHeight(rects, y, sourceBottom, desiredX, desiredY, desiredRight, desiredBottom, edge)
    local northGrowth = edge.north and desiredY < y
    local southGrowth = edge.south and desiredBottom > sourceBottom
    for _, rect in ipairs(rects) do
        if rect.width > 0 and rect.height > 0 then
            local left, top = floor(rect.x), floor(rect.y)
            local right = ceil(rect.x + rect.width)
            local bottom = ceil(rect.y + rect.height)
            local crossesBand = desiredX < right and desiredRight > left
            if crossesBand and southGrowth and bottom > sourceBottom and top < desiredBottom then
                desiredBottom = math.max(sourceBottom, math.min(desiredBottom, top))
            elseif crossesBand and northGrowth and top < y and bottom > desiredY then
                desiredY = math.min(y, math.max(desiredY, bottom))
            end
        end
    end
    return desiredY, desiredBottom
end

-- A resize moves only the grabbed edges. Test the entire swept interval, not
-- just the destination, so a large mouse movement cannot cross a native panel.
-- Corner drags constrain X against the requested Y band, then Y against the
-- resulting X band; this can stop short of a more distant free destination.
function NisResize.constrain(rects, x, y, width, height, desiredX, desiredY, desiredWidth, desiredHeight, edge)
    if #rects == 0 then return desiredX, desiredY, desiredWidth, desiredHeight end

    local sourceRight, sourceBottom = x + width, y + height
    local desiredBottom = desiredY + desiredHeight
    local clampedX, desiredRight, sourceOverlaps = constrainWidth(
        rects,
        x,
        y,
        sourceRight,
        sourceBottom,
        desiredX,
        desiredY,
        desiredX + desiredWidth,
        desiredBottom,
        edge
    )

    -- An externally moved native panel may already intersect the source. In
    -- that case only an actually free requested destination is meaningful:
    -- clamping to the old edge could preserve the existing overlap forever.
    if sourceOverlaps then
        desiredRight = desiredX + desiredWidth
    else
        desiredX = clampedX
        desiredY, desiredBottom =
            constrainHeight(rects, y, sourceBottom, desiredX, desiredY, desiredRight, desiredBottom, edge)
    end

    -- Strict overlap makes edge contact legal. It also catches external
    -- changes or unusual resize requests without inventing a forced placement.
    for _, rect in ipairs(rects) do
        if rect.width > 0 and rect.height > 0 then
            if
                desiredX < ceil(rect.x + rect.width)
                and desiredRight > floor(rect.x)
                and desiredY < ceil(rect.y + rect.height)
                and desiredBottom > floor(rect.y)
            then
                return nil
            end
        end
    end
    return desiredX, desiredY, desiredRight - desiredX, desiredBottom - desiredY
end

return NisResize
