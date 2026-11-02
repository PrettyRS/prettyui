local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function key(categoryID, dynamicID)
    return categoryID .. ":" .. dynamicID
end

local constructorCalls = 0
local hosts = {}
local virtualComponent = {}
local function host(interfaceID)
    local static = {
        interfaceID = interfaceID, staticID = 1, categoryID = -1, dynamicID = -1,
        children = {}, registry = {}, virtual = {},
    }
    hosts[interfaceID] = static
    -- Deliberately direct-only: a nested foreign child is invisible here.
    function static:GetChild(categoryID, dynamicID)
        local pair = key(categoryID, dynamicID)
        if self.virtual[pair] then return self.virtual[pair] end
        for _, child in ipairs(self.children) do
            if not child.destroyed and key(child.categoryID, child.dynamicID) == pair then
                return child
            end
        end
        return nil
    end
    function static:IterateDynamicComponents(callback)
        self.scans = (self.scans or 0) + 1
        for _, child in ipairs(self.children) do
            if not child.destroyed and callback(child, not child.hidden) then return end
        end
    end
    return static
end

local function component(parent, categoryID, dynamicID, kind)
    constructorCalls = constructorCalls + 1
    local static = parent.parentStatic or parent
    assert(categoryID == nil or parent ~= static and parent.categoryID ~= -1,
        "native explicit IDs on a static host")
    local category = categoryID or (parent.categoryID == -1 and 0 or parent.categoryID)
    local dynamic = dynamicID
    local ids = static.registry[category]
    if not ids then ids = {}; static.registry[category] = ids end
    if dynamic == nil then
        dynamic = parent.dynamicID + 1
        while ids[dynamic] do dynamic = dynamic + 1 end
    end
    assert(category >= 0 and category <= 234 and dynamic >= 0 and
        dynamic <= (category == 0 and 4095 or 234), "native ID out of range")
    assert(not ids[dynamic] and not static.virtual[key(category, dynamic)],
        "native ID collision " .. key(category, dynamic))
    local result = {
        parent = parent, parentStatic = static, interfaceID = static.interfaceID,
        staticID = static.staticID, categoryID = category, dynamicID = dynamic, kind = kind,
        children = {}, hooks = {},
    }
    ids[dynamic] = result
    parent.children[#parent.children + 1] = result
    function result:IterateDynamicComponents(callback)
        for _, child in ipairs(self.children) do
            if not child.destroyed and callback(child, not child.hidden) then return end
        end
    end
    function result:Subscribe(hook, callback) self.hooks[hook] = callback end
    function result:Destroy()
        if self.destroyed then return end
        for _, child in ipairs(self.children) do child:Destroy() end
        self.destroyed = true
        if ids[dynamic] == self then ids[dynamic] = nil end
    end
    return result
end

ui = {
    Layer = { new = function(parent, category, dynamic)
        return component(parent, category, dynamic, "layer")
    end },
    Text = { new = function(parent, category, dynamic)
        return component(parent, category, dynamic, "text")
    end },
    Button = { new = function(parent, category, dynamic)
        return component(parent, category, dynamic, "button")
    end },
    Hook = { ONCLICK = 1 },
    Interfaces = {
        GetInterface = function(_, interfaceID) return hosts[interfaceID] end,
        GetComponent = function(_, interfaceID, staticID, categoryID, dynamicID)
            local static = hosts[interfaceID]
            if not static or static.staticID ~= staticID then return nil end
            if categoryID == nil then return static end
            if static.virtual[key(categoryID, dynamicID)] then return virtualComponent end
            local ids = static.registry[categoryID]
            return ids and ids[dynamicID] or nil
        end,
    },
}
Plugin = { resources = {} }
local function namespace()
    return setmetatable({}, { __index = function(table_, field)
        local value = setmetatable({}, { __index = function() return 1 end })
        rawset(table_, field, value)
        return value
    end })
end
id = namespace()
config = namespace()
package.loaded["src/ribbon_bar"] = { Start = function() end }
package.loaded["src/minimenu"] = { Start = function() end }
local prettyui = require("main")
local build = prettyui.BuildCategoryGroup

local primary = host(1)
local content = ui.Layer.new(primary)
local rows = {}
local clicks = {}
prettyui.WithCategoryBatch(content, function(buildGroup)
    for index = 1, 720 do
        rows[index] = buildGroup(6, function(new)
            local row = new(ui.Layer, content)
            for _ = 1, 4 do new(ui.Text, row) end
            local button = new(ui.Button, row)
            button:Subscribe(ui.Hook.ONCLICK, function() clicks[#clicks + 1] = index end)
            return row
        end)
    end
end)
expect(primary.scans, 1, "720 groups take one occupancy walk, not 720")
local managedAfterGroup = prettyui.NewComponent(ui.Text, content, { categoryID = "auto" })
expect(primary.scans, 1, "managed component reuses the grouped occupancy walk")
managedAfterGroup:Destroy()
local inheritedFromGroup = prettyui.NewComponent(ui.Text, rows[1])
assert(inheritedFromGroup.categoryID ~= rows[1].categoryID,
    "a reserved root opts ordinary descendants into auto instead of native inheritance")
inheritedFromGroup:Destroy()
expect(rows[1].categoryID, 1, "first group begins outside category zero")
expect(rows[39].dynamicID, 228, "39 six-component rows fit one category")
expect(rows[40].categoryID, 2, "next row uses the next category")
expect(rows[250].categoryID, 7, "250 rows require seven packed categories")
expect(rows[600].categoryID, 16, "600 rows fit in sixteen categories")
expect(rows[720].categoryID, 19, "720 rows exceed category zero in nineteen categories")
expect(#rows * 6, 4320, "720 actual six-component groups exceed 4096")
for index, row in ipairs(rows) do
    for child = 1, 5 do
        local component = row.children[child]
        expect(component.categoryID, row.categoryID, "row child shares its category")
        expect(component.dynamicID, row.dynamicID + child, "row IDs are consecutive")
    end
    assert(row.categoryID <= 234 and row.dynamicID <= 234, "no unsafe category boundary")
end
rows[1].children[5].hooks[ui.Hook.ONCLICK]()
rows[720].children[5].hooks[ui.Hook.ONCLICK]()
expect(clicks[1], 1, "first row clickable")
expect(clicks[2], 720, "last row clickable")

local neighbor = ui.Layer.new(primary)
local oldID = rows[1].dynamicID
for _, row in ipairs(rows) do row:Destroy() end
expect(neighbor.destroyed, nil, "destroying rows preserves neighboring components")
-- The cursor can wrap to released IDs without reserving categories forever.
local remounted = host(2)
local remountContent = ui.Layer.new(remounted)
local fresh = build(remountContent, 6, function(new)
    local row = new(ui.Layer, remountContent)
    for _ = 1, 5 do new(ui.Text, row) end
    return row
end)
expect(fresh.categoryID, 1, "a second static namespace starts independently")
expect(fresh.dynamicID, oldID, "a remount can reuse its first category slot")

local mixed = host(3)
local mixedContent = ui.Layer.new(mixed)
local foreign = ui.Layer.new(mixedContent, 1, 6)
local first = build(mixedContent, 6, function(new)
    local row = new(ui.Layer, mixedContent)
    for _ = 1, 5 do new(ui.Text, row) end
    return row
end)
local second = build(mixedContent, 6, function(new)
    local row = new(ui.Layer, mixedContent)
    for _ = 1, 5 do new(ui.Text, row) end
    return row
end)
expect(first.dynamicID, 0, "first block takes category-one IDs zero through five")
expect(second.dynamicID, 7, "recursive scan skips a nested foreign occupant")
expect(mixed:GetChild(1, 6), nil, "direct-only lookup misses that nested occupant")
expect(foreign.destroyed, nil, "allocator never destroys another owner's component")

local rollbackHost = host(4)
local rollbackContent = ui.Layer.new(rollbackHost)
local before = constructorCalls
local failure = "injected native error"
local broken = { new = function() error(failure, 0) end }
local ok, reason = pcall(build, rollbackContent, 6, function(new)
    local row = new(ui.Layer, rollbackContent)
    new(broken, row)
end)
expect(ok, false, "native constructor failure propagates")
expect(reason, failure, "native error text is unchanged")
expect(constructorCalls, before + 1, "one partial row was attempted")
local retry = build(rollbackContent, 6, function(new)
    local row = new(ui.Layer, rollbackContent)
    for _ = 1, 5 do new(ui.Text, row) end
    return row
end)
expect(retry.dynamicID, 0, "failed group releases its IDs and cursor")
local nested, nestedError = pcall(prettyui.WithCategoryBatch, rollbackContent, function()
    prettyui.WithCategoryBatch(rollbackContent, function() end)
end)
expect(nested, false, "same-namespace nested batch is rejected")
assert(nestedError:find("nested category group", 1, true), "nested batch diagnostic")
prettyui.WithCategoryBatch(rollbackContent, function(buildGroup)
    local row = buildGroup(1, function(new) return new(ui.Layer, rollbackContent) end)
    expect(row.dynamicID, 6, "failed batch releases its busy lock")
end)

local saturated = host(5)
local survivor = ui.Layer.new(saturated)
for categoryID = 1, 234 do
    for dynamicID = 0, 234 do
        saturated.virtual[key(categoryID, dynamicID)] = true
    end
end
local callsBefore = constructorCalls
local full, diagnostic = pcall(build, survivor, 6, function(new)
    new(ui.Text, survivor)
end)
expect(full, false, "a full namespace rejects before construction")
local exhausted = "PrettyUI: no free category ID block on this static parent; page or reuse components"
expect(diagnostic:sub(-#exhausted), exhausted, "exhaustion has a precise diagnostic")
expect(constructorCalls, callsBefore, "capacity failure never invokes a constructor")
expect(survivor.destroyed, nil, "capacity failure preserves existing UI")
for dynamicID = 229, 234 do saturated.virtual[key(234, dynamicID)] = nil end
local rescued = build(survivor, 6, function(new)
    local row = new(ui.Layer, survivor)
    for _ = 1, 5 do new(ui.Text, row) end
    return row
end)
expect(rescued.categoryID, 234, "freed category can be allocated")
expect(rescued.dynamicID, 229, "freed contiguous block is reused")
rescued:Destroy()
for dynamicID = 0, 5 do saturated.virtual[key(1, dynamicID)] = nil end
local wrapped = build(survivor, 6, function(new)
    local row = new(ui.Layer, survivor)
    for _ = 1, 5 do new(ui.Text, row) end
    return row
end)
expect(wrapped.categoryID, 1, "cursor wraps from the final category")
expect(wrapped.dynamicID, 0, "released IDs are reused on wrap")
expect(survivor.destroyed, nil, "reuse does not disturb the static parent's other child")

local guarded = host(6)
local guardedContent = ui.Layer.new(guarded)
local beforeStatic = constructorCalls
local staticOK, staticError = pcall(build, guardedContent, 1, function(new)
    new(ui.Text, guarded)
end)
expect(staticOK, false, "reserved constructors reject static parents")
assert(staticError:find("require a dynamic parent", 1, true), "static rejection is actionable")
expect(constructorCalls, beforeStatic, "static rejection precedes native construction")

local guardedRow, guardedManaged = build(guardedContent, 3, function(new)
    local ordinary = prettyui.NewComponent(ui.Text, guardedContent, { categoryID = "auto" })
    prettyui.RefreshComponentIDs(guardedContent)
    local row = new(ui.Layer, guardedContent)
    new(ui.Text, row)
    new(ui.Text, row)
    return { row, ordinary }
end)
guardedRow, guardedManaged = guardedRow[1], guardedRow[2]
expect(guardedRow.dynamicID, 0, "reserved block remains intact after managed allocation and refresh")
expect(guardedManaged.dynamicID, 3, "ordinary allocation skips all unbuilt reserved slots")
local inherited = prettyui.NewComponent(ui.Text, guardedRow)
expect(inherited.categoryID, 1, "an ordinary child of a reserved root inherits auto")
expect(inherited.dynamicID, 4, "reserved-root descendant uses managed allocator")

local legacyHost = host(7)
local legacyContent = ui.Layer.new(legacyHost)
local legacyParent = ui.Layer.new(legacyContent, 1, 0)
local legacyRow = build(legacyContent, 2, function(new)
    local beforeLegacy = constructorCalls
    local legacyOK, legacyError = pcall(prettyui.NewComponent, ui.Text, legacyParent)
    expect(legacyOK, false, "legacy native inheritance cannot steal an unbuilt reserved slot")
    assert(legacyError:find("overlaps an active category-group reservation", 1, true),
        "legacy reservation diagnostic")
    expect(constructorCalls, beforeLegacy, "legacy reserved-hole rejection precedes native call")
    local row = new(ui.Layer, legacyContent)
    new(ui.Text, row)
    return row
end)
expect(legacyRow.dynamicID, 1, "reservation begins after the existing native component")

local interrupted = host(8)
local interruptedContent = ui.Layer.new(interrupted)
local raw
local beforeCollision = constructorCalls
local collisionOK, collisionError = pcall(build, interruptedContent, 3, function(new)
    new(ui.Layer, interruptedContent)
    raw = ui.Text.new(interruptedContent, 1, 2)
    new(ui.Text, interruptedContent)
    new(ui.Text, interruptedContent)
end)
expect(collisionOK, false, "a raw occupant in a reserved future slot rejects the group")
assert(collisionError:find("reserved category ID became occupied", 1, true),
    "reservation collision retains the original diagnostic")
expect(constructorCalls, beforeCollision + 3,
    "reserved collision rejects before constructing the second reserved component")
expect(raw.destroyed, nil, "group rollback leaves the unrelated raw occupant alive")
expect(interrupted.registry[1][0], nil, "partial group component is rolled back")
local recovered = build(interruptedContent, 2, function(new)
    local row = new(ui.Layer, interruptedContent)
    new(ui.Text, row)
    return row
end)
expect(recovered.dynamicID, 0, "failed group releases reservations and retains its cursor")
expect(raw.destroyed, nil, "retry preserves unrelated raw components")
do
    local caughtHost = host(9)
    local caughtContent = ui.Layer.new(caughtHost)
    local ordinary, failedID
    prettyui.WithCategoryBatch(caughtContent, function(reserve)
        local success, message = pcall(reserve, 2, function(new)
            failedID = new(ui.Layer, caughtContent).dynamicID
            ordinary = prettyui.NewComponent(ui.Text, caughtContent, { categoryID = "auto" })
            error("caught builder failure", 0)
        end)
        expect(success, false, "a builder failure can be caught inside the batch")
        expect(message, "caught builder failure", "caught builder failure is unchanged")
        local retried = reserve(2, function(new)
            local row = new(ui.Layer, caughtContent)
            new(ui.Text, row)
            return row
        end)
        expect(retried.dynamicID, failedID, "caught builder failure clears stale reserved occupancy")
        expect(ordinary.destroyed, nil, "caught group rollback preserves unrelated managed components")
    end)
end
local SharedInterfaces = require("tests/interface_fixture")
local sharedRoot = SharedInterfaces.component({ interfaceID = 90, children = {} })
local sharedParent = SharedInterfaces.component({ children = {} }, sharedRoot)
local sharedCalls = 0
local sharedNative = { new = function(parent)
    sharedCalls = sharedCalls + 1
    return SharedInterfaces.component({ children = {} }, parent)
end }
local Components = require("src/core/components")
local knownChild = Components.new(sharedNative, sharedParent)
expect(sharedCalls, 1, "shared fixture registers a known dynamic parent")
SharedInterfaces.unload(90)
local unloadedOK, unloadedError = pcall(Components.new, sharedNative, knownChild)
expect(unloadedOK, false, "cached numeric interface detects unload before reading a stale handle")
assert(unloadedError:find("component interface is not loaded; remount the UI", 1, true),
    "unloaded handle reports remount guidance instead of property-read errors")
expect(sharedCalls, 1, "unloaded interface rejects before native construction")
local rawParentOK, rawParentError = pcall(Components.new, sharedNative, sharedParent)
expect(rawParentOK, false, "previously used foreign parents retain a cached namespace across unload")
assert(rawParentError:find("component interface is not loaded; remount the UI", 1, true),
    "foreign parents fail with remount guidance without dereferencing unloaded handles")
expect(sharedCalls, 1, "an unloaded foreign parent cannot enter a native constructor")
print("category_groups_test: ok")
