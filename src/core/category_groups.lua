local Components = require("src/core/components")
local CategoryGroups = {}

local IDS_PER_CATEGORY = 235
local LAST_CATEGORY = 234
local CAPACITY = LAST_CATEGORY * IDS_PER_CATEGORY
local EXHAUSTED = "PrettyUI: no free category ID block on this static parent; page or reuse components"
local cursors = setmetatable({}, { __mode = "k" })

local function staticParentOf(component)
    return component.parentStatic or component
end

-- GetChild alone does not establish that a nested ID is free on every client.
-- Walk dynamic descendants, including hidden pages and other plugins' children.
local function occupiedIDs(staticParent)
    local occupied = {}
    local visited = {}
    local function visit(collection)
        if visited[collection] or collection.IterateDynamicComponents == nil then return end
        visited[collection] = true
        collection:IterateDynamicComponents(function(child)
            if child.parentStatic == staticParent then
                local categoryID, dynamicID = child.categoryID, child.dynamicID
                if categoryID and categoryID >= 1 and categoryID <= LAST_CATEGORY and
                    dynamicID and dynamicID >= 0 and dynamicID < IDS_PER_CATEGORY then
                    occupied[(categoryID - 1) * IDS_PER_CATEGORY + dynamicID] = true
                end
                visit(child)
            end
            return false
        end)
    end
    visit(staticParent)
    return occupied
end

local function findBlock(staticParent, occupied, cursor, count)
    for offset = 0, CAPACITY - 1 do
        local start = (cursor + offset) % CAPACITY
        local firstID = start % IDS_PER_CATEGORY
        if firstID + count <= IDS_PER_CATEGORY then
            local categoryID = 1 + math.floor(start / IDS_PER_CATEGORY)
            local free = true
            for step = 0, count - 1 do
                if occupied[start + step] or
                    Components.isOccupied(staticParent, categoryID, firstID + step) then
                    free = false
                    break
                end
            end
            if free then
                local token = Components.reserve(staticParent, categoryID, firstID, count)
                if token then return start, categoryID, firstID, token end
            end
        end
    end
    return nil
end

-- Synchronous groups share one occupancy walk. The builder itself can create
-- raw/managed components, so reservations and fresh checks protect its slots.
function CategoryGroups.withBatch(parent, callback)
    local staticParent = staticParentOf(parent)
    if staticParent.IterateDynamicComponents == nil then
        error("PrettyUI: category group requires static-parent child lookup and iteration", 2)
    end
    local state = cursors[staticParent]
    if state == nil then
        state = { cursor = 0, busy = false }
        cursors[staticParent] = state
    end
    if state.busy then error("PrettyUI: nested category group on one static parent", 2) end
    state.busy = true
    local occupied
    local ok, result = pcall(function()
        occupied = occupiedIDs(staticParent)
        Components.useSnapshot(staticParent, occupied)
        local function build(count, builder)
            assert(type(count) == "number" and count % 1 == 0 and count >= 1 and
                count <= IDS_PER_CATEGORY, "PrettyUI: category group size must be 1..235")
            if occupied == nil then
                occupied = occupiedIDs(staticParent)
                Components.useSnapshot(staticParent, occupied)
            end
            local start, categoryID, firstID, token = findBlock(staticParent, occupied,
                state.cursor, count)
            if start == nil then error(EXHAUSTED, 2) end

            local created = {}
            local function new(nativeType, actualParent)
                if #created >= count then error("PrettyUI: category group exceeded reserved size", 2) end
                if staticParentOf(actualParent) ~= staticParent then
                    error("PrettyUI: category group parent belongs to another static component", 2)
                end
                if actualParent == staticParent or actualParent.categoryID == -1 then
                    error("PrettyUI: category groups require a dynamic parent; create a native root first", 2)
                end
                local dynamicID = firstID + #created
                if Components.isOccupied(actualParent, categoryID, dynamicID, token) then
                    error("PrettyUI: reserved category ID became occupied", 2)
                end
                local component = nativeType.new(actualParent, categoryID, dynamicID)
                Components.setPolicy(component, "auto")
                created[#created + 1] = component
                return component
            end
            local built, value = pcall(builder, new)
            Components.release(token)
            if not built or #created ~= count then
                for index = #created, 1, -1 do
                    if created[index].Destroy then
                        pcall(created[index].Destroy, created[index])
                    end
                end
                -- The caller may catch this builder error and continue the
                -- batch. Discard reservations observed by managed allocation
                -- as occupied, without discarding other live reservations.
                occupied = nil
                Components.useSnapshot(staticParent, nil)
                if not built then error(value, 0) end
                error("PrettyUI: category group created fewer components than reserved", 2)
            end
            for step = 0, count - 1 do occupied[start + step] = true end
            state.cursor = (start + count) % CAPACITY
            return value
        end
        return callback(build)
    end)
    state.busy = false
    if occupied then Components.useSnapshot(staticParent, ok and occupied or nil) end
    if not ok then error(result, 0) end
    return result
end

-- Raw groups reserve contiguous nonzero IDs; ordinary PrettyUI descendants
-- use Components.new in the same nonzero category range.
function CategoryGroups.build(parent, count, builder)
    return CategoryGroups.withBatch(parent, function(build)
        return build(count, builder)
    end)
end
return CategoryGroups
