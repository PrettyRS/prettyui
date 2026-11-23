-- Move the client's two real divider tiles with the selected mixed-row tab.
-- Retain native anchors and restore only values still written by docking.
local Sprites = require("src/core/sprites")

local Divider = {}
local TILE, SEAM = Sprites.NIS_PANEL.tabBarTile, 4

local positions = { "x", "y", "xParentPc", "yParentPc", "xSelfPc", "ySelfPc" }
local sizes = { "width", "height", "widthParentPc", "heightParentPc" }

local function identity(component)
    if not component then return nil end
    local a, b, c, d = component.interfaceID, component.staticID, component.categoryID, component.dynamicID
    return a .. ":" .. b .. ":" .. c .. ":" .. d
end

local function capture(object, fields)
    local values = {}
    for index, field in ipairs(fields) do
        local value = object[field]
        if type(value) ~= "number" then return nil end
        values[index] = value
    end
    return values
end

local function matches(object, fields, values)
    if not values then return false end
    for index, field in ipairs(fields) do
        if object[field] ~= values[index] then return false end
    end
    return true
end

local function freshBackdrop(host)
    -- Never touch retained native handles after interface unload.
    if not ui.Interfaces:GetInterface(host.owner) then return nil end
    local fresh = ui.Interfaces:GetComponent(host.spec.TAB_BACKGROUND)
    if fresh and identity(fresh.parent) == host.key then
        return fresh
    end
    return nil
end

local function edges(host)
    local backdrop = freshBackdrop(host)
    if not backdrop then return nil end
    local key, left, right, extra = identity(backdrop), nil, nil, false
    backdrop:IterateDynamicComponents(function(child)
        if child.type ~= 3 or child.spriteID ~= TILE or child.height ~= SEAM then return false end
        if child.visible and not child.hidden and identity(child.parent) == key then
            if right then
                extra = true
                return true
            end
            if left then
                right = child
            else
                left = child
            end
        end
        return false
    end)
    if not right or extra then return nil end
    if left.x > right.x then
        left, right = right, left
    end
    local y = backdrop.height - SEAM
    if left.y ~= y or right.y ~= y or left.x < 0 or right.x + right.width > backdrop.width then return nil end
    if identity(left) == identity(right) then return nil end
    return backdrop, left, right
end

local function observe(saved, child)
    local pos, size = child.position, child.size
    if not matches(pos, positions, saved.writtenPosition or saved.position) then
        saved.position, saved.writtenPosition = capture(pos, positions), nil
    end
    if not matches(size, sizes, saved.writtenSize or saved.size) then
        saved.size, saved.writtenSize = capture(size, sizes), nil
    end
    return saved.position ~= nil and saved.size ~= nil
end

local function record(child)
    return {
        key = identity(child),
        position = capture(child.position, positions),
        size = capture(child.size, sizes),
    }
end

local function edgeChanged(saved, child)
    return not matches(child.position, positions, saved.writtenPosition or saved.position)
        or not matches(child.size, sizes, saved.writtenSize or saved.size)
end

function Divider.changed(host)
    local saved = host.nativeDivider
    if not saved then return false end
    local backdrop, left, right = edges(host)
    if not backdrop or identity(backdrop) ~= saved.backdropKey then return true end
    if identity(left) ~= saved.left.key or identity(right) ~= saved.right.key then return true end
    return edgeChanged(saved.left, left) or edgeChanged(saved.right, right) or false
end

local function restoreEdge(saved, child)
    if saved.key ~= identity(child) then return end
    local ownPos = matches(child.position, positions, saved.writtenPosition)
    local ownSize = matches(child.size, sizes, saved.writtenSize)
    if ownSize then child:SetSize(table.unpack(saved.size, 1, 4)) end
    if ownPos then child:SetPos(table.unpack(saved.position, 1, 6)) end
end

function Divider.restore(host)
    local saved = host.nativeDivider
    if not saved then return end
    local backdrop = freshBackdrop(host)
    if not backdrop or identity(backdrop) ~= saved.backdropKey then
        host.nativeDivider = nil
        return
    end
    local left, right, seenLeft, seenRight
    backdrop:IterateDynamicComponents(function(child)
        if child.type ~= 3 or child.spriteID ~= TILE then return false end
        if identity(child.parent) ~= saved.backdropKey then return false end
        local key = identity(child)
        if key == saved.left.key then
            left = not seenLeft and child or nil
            seenLeft = true
        elseif key == saved.right.key then
            right = not seenRight and child or nil
            seenRight = true
        end
        return false
    end)
    if left then restoreEdge(saved.left, left) end
    if right then restoreEdge(saved.right, right) end
    if left and right or edges(host) then host.nativeDivider = nil end
end

local function setEdge(saved, child, x, width)
    if child.width ~= width then
        local size = saved.size
        local desiredSize = { width - child.parent.width * size[3], size[2], size[3], size[4] }
        saved.writtenSize = desiredSize -- A setter can apply before throwing.
        child:SetSize(table.unpack(desiredSize, 1, 4))
    end
    -- SetSize may move a self-anchored right tile; resolve its new x afterward.
    if child.x ~= x then
        local pos = saved.position
        local desiredPos = { child.position.x + x - child.x, pos[2], pos[3], pos[4], pos[5], pos[6] }
        saved.writtenPosition = desiredPos
        child:SetPos(table.unpack(desiredPos, 1, 6))
    end
end

function Divider.align(host, x, width)
    local backdrop, left, right = edges(host)
    if not backdrop then return false end
    local saved = host.nativeDivider
    local backdropKey = identity(backdrop)
    if
        saved
        and (saved.backdropKey ~= backdropKey or saved.left.key ~= identity(left) or saved.right.key ~= identity(right))
    then
        Divider.restore(host)
        saved = nil
    end
    if not saved then
        if left.x + left.width > right.x then return false end
        saved = { backdropKey = backdropKey, left = record(left), right = record(right) }
        if not saved.left.position or not saved.left.size or not saved.right.position or not saved.right.size then
            return false
        end
        host.nativeDivider = saved
    end
    if not observe(saved.left, left) or not observe(saved.right, right) then return false end
    local start = left.x
    local finish = right.x + right.width
    local gapLeft = math.max(start, math.min(finish, x))
    local gapRight = math.max(gapLeft, math.min(finish, x + width))
    setEdge(saved.left, left, start, gapLeft - start)
    setEdge(saved.right, right, gapRight, finish - gapRight)
    return true
end

return Divider
