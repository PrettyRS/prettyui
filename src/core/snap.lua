local Snap = {}

-- a prettyui window's visible edge sits inside its box by window.edgeOffsets on each side, and
-- game windows dont have this

-- the games own windows snap from about this far away too
local SNAP_DISTANCE = 12
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

-- Offests compensate for the difference between a window's box and its visible edge
function Snap.positions(rects, width, height, parentWidth, parentHeight, offsets)
    local across, down = {}, {}
    addPosition(across, -offsets.left, -math.huge, math.huge)
    addPosition(across, parentWidth - width + offsets.right, -math.huge, math.huge)
    addPosition(down, -offsets.top, -math.huge, math.huge)
    addPosition(down, parentHeight - height + offsets.bottom, -math.huge, math.huge)
    for _, rect in ipairs(rects) do
        local left, top = rect.x, rect.y
        local right, bottom = rect.x + rect.width, rect.y + rect.height
        addPosition(across, left - width + offsets.right, top, bottom)
        addPosition(across, right - offsets.left, top, bottom)
        addPosition(across, left - offsets.left, top, bottom)
        addPosition(across, right - width + offsets.right, top, bottom)
        addPosition(down, top - height + offsets.bottom, left, right)
        addPosition(down, bottom - offsets.top, left, right)
        addPosition(down, top - offsets.top, left, right)
        addPosition(down, bottom - height + offsets.bottom, left, right)
    end
    return { across = across, down = down }
end

local function isOverlappingOtherAxis(position, otherStart, otherSize, distance)
    return otherStart <= position.to + distance and otherStart + otherSize >= position.from - distance
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

function Snap.apply(positions, x, y, width, height)
    local snappedX = snapAxis(positions.across, x, y, height, SNAP_DISTANCE)
    local snappedY = snapAxis(positions.down, y, x, width, SNAP_DISTANCE)
    return snappedX, snappedY
end

local function isSnapTarget(other, movingWindow)
    return other ~= movingWindow
        and not other.root.hidden
        and ui.Interfaces:GetInterface(other.interfaceID) ~= nil
end

local function addRegisteredWindows(rects, movingWindow)
    local parentOrigin = movingWindow.parent.xyGlobal
    for other in pairs(windows) do
        if isSnapTarget(other, movingWindow) then
            local root, offsets = other.root, other.edgeOffsets
            local rootOrigin = root.xyGlobal
            rects[#rects + 1] = {
                x = rootOrigin.x - parentOrigin.x + offsets.left,
                y = rootOrigin.y - parentOrigin.y + offsets.top,
                width = root.width - offsets.left - offsets.right,
                height = root.height - offsets.top - offsets.bottom,
            }
        end
    end
end

local function addLayoutWindows(rects, movingWindow)
    -- theory: game windows only snap to the layout windows, which all sit on this layer
    local layoutLayer = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
    if layoutLayer == nil then return end
    local parentOrigin = movingWindow.parent.xyGlobal
    layoutLayer:IterateStaticComponents(function(child)
        if child.visibleGlobal then
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
    return Snap.positions(rects, root.width, root.height, parent.width, parent.height, movingWindow.edgeOffsets)
end

return Snap
