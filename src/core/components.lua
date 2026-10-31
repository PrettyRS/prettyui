local Components = {}

local IDS_PER_CATEGORY = 235
local LAST_CATEGORY = 234
local CAPACITY = LAST_CATEGORY * IDS_PER_CATEGORY
local EXHAUSTED = "PrettyUI: no dynamic component IDs available on this static parent; page or reuse components"
local states = setmetatable({}, { __mode = "k" })

local function staticParentOf(parent)
    return parent.parentStatic or parent
end

local function pairAt(index)
    return 1 + math.floor(index / IDS_PER_CATEGORY), index % IDS_PER_CATEGORY
end

local function slotOf(categoryID, dynamicID)
    if categoryID and categoryID >= 1 and categoryID <= LAST_CATEGORY and
        dynamicID and dynamicID >= 0 and dynamicID < IDS_PER_CATEGORY then
        return (categoryID - 1) * IDS_PER_CATEGORY + dynamicID
    end
    return nil
end

-- Some clients only return direct children from GetChild. Include nested and
-- hidden descendants before choosing an ID in the shared static namespace.
local function occupiedIDs(staticParent)
    local occupied, visited = {}, {}
    local function visit(collection)
        if visited[collection] or collection.IterateDynamicComponents == nil then return end
        visited[collection] = true
        collection:IterateDynamicComponents(function(child)
            if child.parentStatic == staticParent then
                local slot = slotOf(child.categoryID, child.dynamicID)
                if slot then occupied[slot] = true end
                visit(child)
            end
            return false
        end)
    end
    visit(staticParent)
    return occupied
end

local function stateFor(staticParent)
    local state = states[staticParent]
    if not state then
        -- Native roots and unmanaged children retain category zero. Only the
        -- nonzero grouped range has survived large live-client construction.
        state = { cursor = 0, owned = {}, occupied = nil }
        states[staticParent] = state
    end
    return state
end

-- Mixed native constructors outside PrettyUI must refresh the snapshot before
-- the next allocation if they insert IDs beneath an already mounted root.
function Components.refresh(parent)
    local staticParent = staticParentOf(parent)
    local state = stateFor(staticParent)
    if state.batch then
        local occupied = occupiedIDs(staticParent)
        state.batch.occupied = occupied
        state.occupied = occupied
    else
        state.occupied = nil
    end
end

-- A raw category batch already walked this host; share its updated snapshot.
function Components.useSnapshot(parent, occupied)
    local state = stateFor(staticParentOf(parent))
    state.occupied = occupied
    if state.batch then state.batch.occupied = occupied end
end

-- Cache the shared occupancy snapshot across widget batches. Rescanning the
-- entire interface for every AddText/AddList becomes quadratic on reopen.
-- Native constructors cannot be interleaved with another Lua plugin callback.
function Components.withBatch(parent, callback)
    local staticParent = staticParentOf(parent)
    local state = stateFor(staticParent)
    if state.batch then return callback() end
    local occupied = state.occupied
    if occupied == nil and staticParent.GetChild and staticParent.IterateDynamicComponents then
        occupied = occupiedIDs(staticParent)
        state.occupied = occupied
    end
    state.batch = { occupied = occupied, created = {} }
    local batch = state.batch
    local ok, result = pcall(callback)
    state.batch = nil
    if not ok then state.occupied = nil end
    if not ok then
        for index = #batch.created, 1, -1 do
            local component = batch.created[index]
            if component.Destroy then pcall(component.Destroy, component) end
        end
        error(result, 0)
    end
    return result
end

function Components.new(nativeType, parent)
    local staticParent = staticParentOf(parent)
    local state = stateFor(staticParent)
    -- Explicit IDs on a static host have aborted the BETA client. Let the
    -- native constructor assign the root ID; descendants can use the shared
    -- allocator once they have a dynamic parent.
    if parent == staticParent or parent.categoryID == -1 then
        local component = nativeType.new(parent)
        if state.batch then
            local batch = state.batch
            batch.created[#batch.created + 1] = component
            local slot = slotOf(component.categoryID, component.dynamicID)
            if batch.occupied and slot then batch.occupied[slot] = true end
        end
        return component
    end

    local lookup = staticParent.GetChild
    local occupied = state.batch and state.batch.occupied or state.occupied
    local cached = occupied ~= nil
    if occupied == nil and lookup and staticParent.IterateDynamicComponents then
        occupied = occupiedIDs(staticParent)
        state.occupied = occupied
    end
    for attempt = 1, cached and 2 or 1 do
        for offset = 0, CAPACITY - 1 do
            local slot = (state.cursor + offset) % CAPACITY
            local categoryID, dynamicID = pairAt(slot)
            local owned = state.owned[slot]
            if owned ~= nil and owned.destroyed then
                state.owned[slot] = nil
                owned = nil
            end
            if not (occupied and occupied[slot]) and
                not (lookup and staticParent:GetChild(categoryID, dynamicID)) and
                owned == nil then
                local component = nativeType.new(parent, categoryID, dynamicID)
                -- ID-ignorant test doubles cannot be queried via GetChild; their
                -- destroyed flag is the only available release signal.
                if not lookup or not occupied then state.owned[slot] = component end
                if occupied then occupied[slot] = true end
                if state.batch then
                    local created = state.batch.created
                    created[#created + 1] = component
                end
                state.cursor = (slot + 1) % CAPACITY
                if state.cursor == 0 then
                    state.occupied = nil
                    if state.batch then state.batch.occupied = nil end
                end
                return component
            end
        end
        -- Previously mounted widgets may have been destroyed since the last
        -- snapshot. Reconcile once before declaring the namespace exhausted.
        if attempt == 1 and cached and lookup and staticParent.IterateDynamicComponents then
            occupied = occupiedIDs(staticParent)
            state.occupied = occupied
            if state.batch then state.batch.occupied = occupied end
        end
    end
    error(EXHAUSTED, 2)
end

return Components
