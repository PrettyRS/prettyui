local Snap = {}

-- a prettyui window's visible edge sits inside its box by window.edgeOffsets on each side, and
-- game windows dont have this

-- the games own windows snap from about this far away too
local SNAP_DISTANCE = 12
local NO_EDGE_OFFSETS = { left = 0, top = 0, right = 0, bottom = 0 }
local windows = setmetatable({}, { __mode = "k" })

function Snap.register(window)
    windows[window] = window.edgeOffsets or NO_EDGE_OFFSETS
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

local function isSnapTarget(other, movingWindow, visibleOnly)
    -- Check the cached interface ID before touching a potentially unloaded root.
    return other ~= movingWindow
        and not (movingWindow._nisGroup ~= nil and other._nisGroup == movingWindow._nisGroup)
        and ui.Interfaces:GetInterface(other.interfaceID) ~= nil
        and not other.root.hidden
        and (visibleOnly ~= true or other.root.visibleGlobal ~= false)
end

function Snap.collect(movingWindow, rects, visibleOnly, excludedNativeID, nativeCache)
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
    for other, offsets in pairs(windows) do
        if isSnapTarget(other, movingWindow, visibleOnly) then
            local root = other.root
            local origin = root.xyGlobal
            add(origin.x - parentOrigin.x + offsets.left, origin.y - parentOrigin.y + offsets.top,
                root.width - offsets.left - offsets.right, root.height - offsets.top - offsets.bottom)
        end
    end
    -- Theory: game windows only snap to the layout windows on this layer.
    -- Enumeration failures propagate so placement cannot approve unknown geometry.
    local layoutLayer = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
    local excludedInterface = excludedNativeID and (excludedNativeID >> 16)
    local excludedStatic = excludedNativeID and (excludedNativeID & 0xFFFF)
    local function addNative(child)
        if child and child.visibleGlobal and (excludedNativeID == nil or
            child.interfaceID ~= excludedInterface or child.staticID ~= excludedStatic) then
            local origin = child.xyGlobal
            add(origin.x - parentOrigin.x, origin.y - parentOrigin.y, child.width, child.height)
        end
    end
    if layoutLayer ~= nil then
        if nativeCache and nativeCache.ids then
            -- Keep identities, not native handles: rebuilds may replace a
            -- component without changing its ID. Bounds/visibility stay live.
            for _, packed in ipairs(nativeCache.ids) do
                addNative(ui.Interfaces:GetComponent(packed))
            end
        else
            local ids = nativeCache and {}
            layoutLayer:IterateStaticComponents(function(child)
                if ids then ids[#ids + 1] = (child.interfaceID << 16) | child.staticID end
                addNative(child)
                return false
            end)
            -- Publish only a complete enumeration, including hidden children.
            if nativeCache then nativeCache.ids = ids end
        end
    elseif nativeCache then
        nativeCache.ids = nil
    end
    for index = #rects, count + 1, -1 do rects[index] = nil end
    return rects
end

function Snap.start(movingWindow)
    local root, parent = movingWindow.root, movingWindow.parent
    return Snap.positions(Snap.collect(movingWindow), root.width, root.height,
        parent.width, parent.height, windows[movingWindow] or movingWindow.edgeOffsets or NO_EDGE_OFFSETS)
end

return Snap
