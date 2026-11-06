local Snap = {}

-- a prettyui windows visible edge sits 2px inside its box and game windows dont have this
local VISIBLE_EDGE_OFFSET = 2
-- theory: game windows only snap to the layout windows, which all sit on this layer
local LAYOUT_LAYER = id.Component.TOPLEVEL_V2__GAME_AREA
local windows = setmetatable({}, { __mode = "k" })

function Snap.register(window)
    windows[window] = true
end

function Snap.unregister(window)
    windows[window] = nil
end

local function addPosition(list, at, from, to)
    list[#list + 1] = { at = at, from = from, to = to }
end

function Snap.positions(rects, width, height, parentWidth, parentHeight, edgeOffset)
    local across, down = {}, {}
    addPosition(across, 0, -math.huge, math.huge)
    addPosition(across, parentWidth - width, -math.huge, math.huge)
    addPosition(down, 0, -math.huge, math.huge)
    addPosition(down, parentHeight - height, -math.huge, math.huge)
    for _, rect in ipairs(rects) do
        local left, top = rect.x, rect.y
        local right, bottom = rect.x + rect.width, rect.y + rect.height
        addPosition(across, left - width + edgeOffset, top, bottom)
        addPosition(across, right - edgeOffset, top, bottom)
        addPosition(across, left - edgeOffset, top, bottom)
        addPosition(across, right - width + edgeOffset, top, bottom)
        addPosition(down, top - height + edgeOffset, left, right)
        addPosition(down, bottom - edgeOffset, left, right)
        addPosition(down, top - edgeOffset, left, right)
        addPosition(down, bottom - height + edgeOffset, left, right)
    end
    return { across = across, down = down }
end

local function isOverlappingOtherAxis(position, otherStart, otherSize, distance)
    return otherStart < position.to + distance and otherStart + otherSize > position.from - distance
end

local function snapAxis(list, rawValue, otherStart, otherSize, distance)
    local snapped, snappedGap = rawValue, math.huge
    for _, position in ipairs(list) do
        if isOverlappingOtherAxis(position, otherStart, otherSize, distance) then
            local gap = math.abs(rawValue - position.at)
            if gap <= distance and gap < snappedGap then
                snapped, snappedGap = position.at, gap
            end
        end
    end
    return snapped
end

function Snap.apply(positions, x, y, width, height, distance)
    local snappedX = snapAxis(positions.across, x, y, height, distance)
    local snappedY = snapAxis(positions.down, y, x, width, distance)
    return snappedX, snappedY
end

local function isSnapTarget(other, movingWindow)
    return other ~= movingWindow
        and other.root ~= nil
        and not other.root.hidden
        and ui.Interfaces:GetInterface(other.interfaceID) ~= nil
end

-- prettyui windows (registered automatically via Snap.register) from version 1.4.0+
local function addRegisteredWindows(rects, movingWindow)
    local parentOrigin = movingWindow.parent.xyGlobal
    for other in pairs(windows) do
        if isSnapTarget(other, movingWindow) then
            local root = other.root
            local rootOrigin = root.xyGlobal
            rects[#rects + 1] = {
                x = rootOrigin.x - parentOrigin.x + VISIBLE_EDGE_OFFSET,
                y = rootOrigin.y - parentOrigin.y + VISIBLE_EDGE_OFFSET,
                width = root.width - 2 * VISIBLE_EDGE_OFFSET,
                height = root.height - 2 * VISIBLE_EDGE_OFFSET,
            }
        end
    end
end

-- the layout layer also holds a full screen layer, which isnt a window
local function isShownWindow(child, layoutLayer)
    return child.visibleGlobal
        and not (child.width >= layoutLayer.width and child.height >= layoutLayer.height)
end

local function addLayoutWindows(rects, movingWindow)
    local layoutLayer = ui.Interfaces:GetComponent(LAYOUT_LAYER)
    if layoutLayer == nil then return end
    local parentOrigin = movingWindow.parent.xyGlobal
    layoutLayer:IterateStaticComponents(function(child)
        if isShownWindow(child, layoutLayer) then
            local childOrigin = child.xyGlobal
            rects[#rects + 1] = {
                x = childOrigin.x - parentOrigin.x,
                y = childOrigin.y - parentOrigin.y,
                width = child.width,
                height = child.height,
            }
        end
    end)
end

function Snap.start(movingWindow)
    local root, parent = movingWindow.root, movingWindow.parent
    local rects = {}
    addRegisteredWindows(rects, movingWindow)
    addLayoutWindows(rects, movingWindow)
    return Snap.positions(rects, root.width, root.height, parent.width, parent.height, VISIBLE_EDGE_OFFSET)
end

return Snap
