local Snap = {}

-- derived from in-game testing, 2px snaps windows flush with one another
local VISIBLE_EDGE_OFFSET = 2
-- theory: the games own windows only snap to the layout windows, which all sit in this container
local LAYOUT_CONTAINER = id.Component.TOPLEVEL_V2__GAME_AREA
local windows = setmetatable({}, { __mode = "k" })

function Snap.register(window)
    windows[window] = true
end

function Snap.unregister(window)
    windows[window] = nil
end

local function add(list, at, from, to)
    list[#list + 1] = { at = at, from = from, to = to }
end

function Snap.positions(rects, width, height, parentWidth, parentHeight, edgeOffset)
    local across, down = {}, {}
    add(across, 0, -math.huge, math.huge)
    add(across, parentWidth - width, -math.huge, math.huge)
    add(down, 0, -math.huge, math.huge)
    add(down, parentHeight - height, -math.huge, math.huge)
    for _, rect in ipairs(rects) do
        local left, top = rect.x, rect.y
        local right, bottom = rect.x + rect.width, rect.y + rect.height
        add(across, left - width + edgeOffset, top, bottom)
        add(across, right - edgeOffset, top, bottom)
        add(across, left - edgeOffset, top, bottom)
        add(across, right - width + edgeOffset, top, bottom)
        add(down, top - height + edgeOffset, left, right)
        add(down, bottom - edgeOffset, left, right)
        add(down, top - edgeOffset, left, right)
        add(down, bottom - height + edgeOffset, left, right)
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

local function snappable(other, movingWindow)
    return other ~= movingWindow
        and other.root ~= nil
        and not other.root.hidden
        and ui.Interfaces:GetInterface(other.interfaceID) ~= nil
end

local function windowRects(movingWindow, rects)
    local origin = movingWindow.parent.xyGlobal
    for other in pairs(windows) do
        if snappable(other, movingWindow) then
            local root = other.root
            local at = root.xyGlobal
            rects[#rects + 1] = {
                x = at.x - origin.x + VISIBLE_EDGE_OFFSET,
                y = at.y - origin.y + VISIBLE_EDGE_OFFSET,
                width = root.width - 2 * VISIBLE_EDGE_OFFSET,
                height = root.height - 2 * VISIBLE_EDGE_OFFSET,
            }
        end
    end
end

-- the game area also holds a full screen layer, which isnt a window
local function shownWindow(frame, gameArea)
    return frame.visibleGlobal
        and not (frame.width >= gameArea.width and frame.height >= gameArea.height)
end

local function gameRects(movingWindow, rects)
    local gameArea = ui.Interfaces:GetComponent(LAYOUT_CONTAINER)
    if gameArea == nil then return end
    local origin = movingWindow.parent.xyGlobal
    gameArea:IterateStaticComponents(function(frame)
        if shownWindow(frame, gameArea) then
            local at = frame.xyGlobal
            rects[#rects + 1] = { x = at.x - origin.x, y = at.y - origin.y, width = frame.width, height = frame.height }
        end
    end)
end

function Snap.start(movingWindow)
    local root, parent = movingWindow.root, movingWindow.parent
    local rects = {}
    windowRects(movingWindow, rects)
    gameRects(movingWindow, rects)
    return Snap.positions(rects, root.width, root.height, parent.width, parent.height, VISIBLE_EDGE_OFFSET)
end

return Snap
