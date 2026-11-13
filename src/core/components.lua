local WorldMap = require("src/core/world_map")
local Components = {}

-- Different Lua handles can refer to the same native component.
function Components.sameComponent(first, second)
    if first == second then return true end
    return first ~= nil and second ~= nil
        and type(first.interfaceID) == "number" and type(first.staticID) == "number"
        and first.interfaceID == second.interfaceID and first.staticID == second.staticID
        and first.categoryID == second.categoryID and first.dynamicID == second.dynamicID
end

local sameComponent = Components.sameComponent

local IDS_PER_CATEGORY = 235
local LAST_CATEGORY = 234
local CAPACITY = LAST_CATEGORY * IDS_PER_CATEGORY
local EXHAUSTED = "PrettyUI: this UI has reached its control limit. Show fewer controls at once, split long lists into pages, or reuse existing controls."
local INHERITED_EXHAUSTED = 'PrettyUI: this container has reached its control limit. Set categoryID = "auto" on your root UI, or show fewer controls at once.'
local RESERVED_INHERITED = 'PrettyUI: a control group is still being built. Create additional controls with PrettyUI.NewComponent(..., { categoryID = "auto" }) to avoid conflicts.'
local CONTENT_PARENT_ERROR = "PrettyUI: this parent cannot host a content container. Use window.content, view.content, or a UI layer supplied by the client as its parent."
local UNLOADED = "PrettyUI: the parent UI is no longer available. Recreate your controls when it is available again."
local UNVERIFIABLE = "PrettyUI: cannot check for existing controls in this parent. Use window.content, view.content, or a UI layer supplied by the client."
local LEGACY_NOTICE = 'PrettyUI: legacy category allocation will be deprecated in v2. Add { categoryID = "auto" } to your root UI options to enable automatic category management'
local states = setmetatable({}, { __mode = "k" })
local policies = setmetatable({}, { __mode = "k" })
local knownHosts = setmetatable({}, { __mode = "k" })
local owned = setmetatable({}, { __mode = "k" })
local warned = false

local function visitKey(component)
    local categoryID, dynamicID = component.categoryID, component.dynamicID
    if type(categoryID) == "number" and type(dynamicID) == "number" then
        return categoryID * 4096 + dynamicID
    end
    return component
end

local function staticParentOf(parent)
    local host = knownHosts[parent]
    if host then return host end
    host = parent.categoryID == -1 and parent or parent.parentStatic or parent
    knownHosts[parent] = host
    return host
end

local function ancestryPolicy(component)
    while component do
        local policy = policies[component]
        if policy then return policy end
        component = component.parent
    end
    return nil
end

function Components.policyOf(parent, options, fallbackParent)
    if options and options.categoryID == "auto" then return "auto" end
    if options and (options._categoryPolicy == "auto" or options._categoryPolicy == "legacy") then
        return options._categoryPolicy
    end
    return ancestryPolicy(parent) or ancestryPolicy(fallbackParent) or "legacy"
end

function Components.setPolicy(component, policy)
    assert(policy == "auto" or policy == "legacy", "invalid component allocation policy")
    policies[component] = policy
    knownHosts[component] = staticParentOf(component)
    return component
end

-- Visibility writes preserve the caller's intent while the world map occludes
-- top-level PrettyUI roots. Nested/native components are written normally.
function Components.setHidden(component, hidden)
    WorldMap.setHidden(component, hidden)
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

-- Cached occupancy speeds up batches; a fresh authoritative lookup is still
-- required immediately before every explicit native construction.
function Components.occupiedIDs(staticParent)
    local occupied, visited = {}, {}
    local function visit(collection)
        local key = visitKey(collection)
        if visited[key] or collection.IterateDynamicComponents == nil then return end
        visited[key] = true
        collection:IterateDynamicComponents(function(child)
            if sameComponent(child.parentStatic, staticParent) then
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
        -- Cache numeric IDs while the host is loaded; never query an unloaded
        -- component handle merely to discover its interface namespace.
        state = {
            cursor = 0, owned = {}, occupied = nil, reserved = {},
            interfaceID = staticParent.interfaceID, staticID = staticParent.staticID,
        }
        states[staticParent] = state
        knownHosts[staticParent] = staticParent
    end
    return state
end

local function loadedInterface(state)
    local interfaces = ui and ui.Interfaces
    if state.interfaceID ~= nil and interfaces and interfaces.GetInterface and
        interfaces:GetInterface(state.interfaceID) == nil then
        error(UNLOADED, 3)
    end
    return interfaces
end

-- A full-ID lookup is usable only when it can also resolve a known dynamic
-- parent. Otherwise a nil candidate could conceal nested native components.
local function nativeOccupant(staticParent, state, parent, categoryID, dynamicID)
    local interfaces = loadedInterface(state)
    if state.fullLookup ~= false and interfaces and interfaces.GetComponent and
        interfaces.GetInterface and type(state.interfaceID) == "number" and
        type(state.staticID) == "number" then
        if parent ~= staticParent and sameComponent(parent.parentStatic, staticParent) and
            type(parent.categoryID) == "number" and parent.categoryID >= 0 and
            type(parent.dynamicID) == "number" and parent.dynamicID >= 0 then
            local resolved = interfaces:GetComponent(state.interfaceID, state.staticID,
                parent.categoryID, parent.dynamicID)
            if not sameComponent(resolved, parent) then state.fullLookup = false end
        end
        if state.fullLookup ~= false then
            return interfaces:GetComponent(state.interfaceID, state.staticID,
                categoryID, dynamicID) ~= nil
        end
    end
    if staticParent.IterateDynamicComponents == nil then error(UNVERIFIABLE, 3) end
    local visited, found = {}, false
    local function visit(collection)
        local key = visitKey(collection)
        if found or visited[key] then return end
        if collection.IterateDynamicComponents == nil then error(UNVERIFIABLE, 3) end
        visited[key] = true
        collection:IterateDynamicComponents(function(child)
            if sameComponent(child.parentStatic, staticParent) then
                if child.categoryID == categoryID and child.dynamicID == dynamicID then
                    found = true
                    return true
                end
                visit(child)
            end
            return false
        end)
    end
    visit(staticParent)
    return found
end

local function reservedAt(state, categoryID, dynamicID)
    local slot = slotOf(categoryID, dynamicID)
    return slot and state.reserved[slot] or nil
end

function Components.isOccupied(parent, categoryID, dynamicID, reservation)
    local staticParent = staticParentOf(parent)
    local state = stateFor(staticParent)
    local token = reservedAt(state, categoryID, dynamicID)
    if token and token ~= reservation then return true end
    return nativeOccupant(staticParent, state, parent, categoryID, dynamicID)
end

function Components.reserve(parent, categoryID, firstID, count)
    local staticParent = staticParentOf(parent)
    local state = stateFor(staticParent)
    for dynamicID = firstID, firstID + count - 1 do
        local slot = slotOf(categoryID, dynamicID)
        if not slot or (state.occupied and state.occupied[slot]) or
            Components.isOccupied(parent, categoryID, dynamicID) then return nil end
    end
    local reservation = { state = state, slots = {} }
    for dynamicID = firstID, firstID + count - 1 do
        local slot = slotOf(categoryID, dynamicID)
        state.reserved[slot] = reservation
        reservation.slots[#reservation.slots + 1] = slot
    end
    return reservation
end

function Components.release(reservation)
    if not reservation then return end
    for _, slot in ipairs(reservation.slots) do
        if reservation.state.reserved[slot] == reservation then
            reservation.state.reserved[slot] = nil
        end
    end
end

local function inheritedPreflight(parent, staticParent, state)
    local categoryID, start
    if parent == staticParent or parent.categoryID == -1 then
        categoryID, start = 0, 0
    else
        categoryID = parent.categoryID
        local dynamicID = parent.dynamicID
        if type(categoryID) ~= "number" or categoryID % 1 ~= 0 or categoryID < 0 or
            categoryID > LAST_CATEGORY or type(dynamicID) ~= "number" or
            dynamicID % 1 ~= 0 or dynamicID < 0 or
            dynamicID > (categoryID == 0 and 4095 or 234) then
            error(INHERITED_EXHAUSTED, 3)
        end
        start = dynamicID + 1
    end
    local limit = categoryID == 0 and 4095 or 234
    if start > limit then error(INHERITED_EXHAUSTED, 3) end
    for dynamicID = start, limit do
        if not nativeOccupant(staticParent, state, parent, categoryID, dynamicID) then
            if reservedAt(state, categoryID, dynamicID) then
                error(RESERVED_INHERITED, 3)
            end
            return
        end
    end
    error(INHERITED_EXHAUSTED, 3)
end

local function register(component, staticParent, state, policy)
    Components.setPolicy(component, policy)
    knownHosts[component] = staticParent
    local slot = slotOf(component.categoryID, component.dynamicID)
    if slot and state.occupied then state.occupied[slot] = true end
    if state.batch then
        local created = state.batch
        created[#created + 1] = component
    end
    if policy == "legacy" and not warned and type(log) == "function" then
        warned = true
        -- Native log resolves plugin ownership from its Lua caller's _ENV.
        -- Passing it directly to C pcall leaves no caller environment.
        pcall(function() log(LEGACY_NOTICE) end)
    end
    local ancestor, nested = component.parent, false
    while ancestor do
        if owned[ancestor] then nested = true; break end
        ancestor = ancestor.parent
    end
    owned[component] = true
    if not nested then WorldMap.track(component) end
    return component
end

-- Explicit refresh reconciles deletion/raw changes in the cached occupancy
-- view. Fresh per-candidate lookups protect construction even without refresh.
function Components.refresh(parent)
    local staticParent = staticParentOf(parent)
    local state = stateFor(staticParent)
    state.occupied = state.batch and Components.occupiedIDs(staticParent) or nil
end

-- A raw category batch already walked this host; share its updated snapshot.
function Components.useSnapshot(parent, occupied)
    local state = stateFor(staticParentOf(parent))
    state.occupied = occupied
end

-- Cache shared occupancy across widget batches; callback-created raw components
-- are still checked against the live namespace before construction.
function Components.withBatch(parent, callback)
    local staticParent = staticParentOf(parent)
    local state = stateFor(staticParent)
    if state.batch then return callback() end
    if state.occupied == nil and staticParent.GetChild and staticParent.IterateDynamicComponents then
        state.occupied = Components.occupiedIDs(staticParent)
    end
    local created = {}
    state.batch = created
    local ok, result = pcall(callback)
    state.batch = nil
    if not ok then
        state.occupied = nil
        for index = #created, 1, -1 do
            local component = created[index]
            if component.Destroy then pcall(component.Destroy, component) end
        end
        error(result, 0)
    end
    return result
end

function Components.checkContentParent(parent, options)
    local staticParent = staticParentOf(parent)
    loadedInterface(stateFor(staticParent))
    local policy = Components.policyOf(parent, options)
    if policy == "auto" and parent ~= staticParent and
        parent.categoryID ~= -1 and parent.categoryID ~= 0 then
        error(CONTENT_PARENT_ERROR, 2)
    end
    return policy
end

function Components.newContent(parent, options)
    local policy = Components.checkContentParent(parent, options)
    if policy == "legacy" then return Components.new(ui.Layer, parent, options) end
    local staticParent = staticParentOf(parent)
    local state = stateFor(staticParent)
    inheritedPreflight(parent, staticParent, state)
    return register(ui.Layer.new(parent), staticParent, state, policy)
end

function Components.new(nativeType, parent, options)
    local staticParent = staticParentOf(parent)
    local state = stateFor(staticParent)
    loadedInterface(state)
    local policy = Components.policyOf(parent, options)
    -- Native static roots must never receive explicit IDs, including for an
    -- opted-in auto root. Save its policy for managed descendants.
    if parent == staticParent or parent.categoryID == -1 or policy == "legacy" then
        inheritedPreflight(parent, staticParent, state)
        return register(nativeType.new(parent), staticParent, state, policy)
    end

    local occupied = state.occupied
    local cached = occupied ~= nil
    if occupied == nil and staticParent.IterateDynamicComponents then
        occupied = Components.occupiedIDs(staticParent)
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
            if not (occupied and occupied[slot]) and owned == nil then
                if Components.isOccupied(parent, categoryID, dynamicID) then
                    if occupied then occupied[slot] = true end
                else
                    local component = nativeType.new(parent, categoryID, dynamicID)
                    if not occupied then state.owned[slot] = component end
                    register(component, staticParent, state, policy)
                    state.cursor = (slot + 1) % CAPACITY
                    if state.cursor == 0 then
                        state.occupied = nil
                    end
                    return component
                end
            end
        end
        -- Reclaim slots freed since the last snapshot, without discarding live
        -- category-group reservations.
        if attempt == 1 and cached and staticParent.IterateDynamicComponents then
            occupied = Components.occupiedIDs(staticParent)
            state.occupied = occupied
        end
    end
    error(EXHAUSTED, 2)
end

return Components
