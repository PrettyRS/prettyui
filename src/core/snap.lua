local Snap = {}

-- a prettyui windows visible edge sits 2 units inside its box and game windows dont have this
local VISIBLE_EDGE_OFFSET = 2
-- the games own windows snap from about this far away too
local SNAP_DISTANCE = 12
local windows = setmetatable({}, { __mode = "k" })

function Snap.register(window, edgeOffset)
    windows[window] = edgeOffset or VISIBLE_EDGE_OFFSET
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

local function isSnapTarget(other, movingWindow, visibleOnly)
    -- Check the cached interface ID before touching a potentially unloaded root.
    return other ~= movingWindow
        and not (movingWindow._nisGroup ~= nil and other._nisGroup == movingWindow._nisGroup)
        and ui.Interfaces:GetInterface(other.interfaceID) ~= nil
        and not other.root.hidden
        and (visibleOnly ~= true or other.root.visibleGlobal ~= false)
end

function Snap.collect(movingWindow, rects, visibleOnly, excludedNativeID)
    rects = rects or {}
    local count = 0
    local parentOrigin = movingWindow.parent.xyGlobal
    local function add(x, y, width, height)
        count = count + 1
        local rect = rects[count]
        if rect == nil then
            rect = {}
            rects[count] = rect
        end
        rect.x, rect.y, rect.width, rect.height = x, y, width, height
    end
    for other, inset in pairs(windows) do
        if isSnapTarget(other, movingWindow, visibleOnly) then
            local root = other.root
            local origin = root.xyGlobal
            add(origin.x - parentOrigin.x + inset, origin.y - parentOrigin.y + inset,
                root.width - 2 * inset, root.height - 2 * inset)
        end
    end
    -- Theory: game windows only snap to the layout windows on this layer.
    -- Enumeration failures propagate so placement cannot approve unknown geometry.
    local layoutLayer = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
    local excludedInterface = excludedNativeID and (excludedNativeID >> 16)
    local excludedStatic = excludedNativeID and (excludedNativeID & 0xFFFF)
    if layoutLayer ~= nil then
        layoutLayer:IterateStaticComponents(function(child)
            if child.visibleGlobal and (excludedNativeID == nil or
                child.interfaceID ~= excludedInterface or child.staticID ~= excludedStatic) then
                local origin = child.xyGlobal
                add(origin.x - parentOrigin.x, origin.y - parentOrigin.y, child.width, child.height)
            end
            return false
        end)
    end
    for index = #rects, count + 1, -1 do rects[index] = nil end
    return rects
end

function Snap.start(movingWindow)
    local root, parent = movingWindow.root, movingWindow.parent
    return Snap.positions(Snap.collect(movingWindow), root.width, root.height,
        parent.width, parent.height, windows[movingWindow] or VISIBLE_EDGE_OFFSET)
end

return Snap
