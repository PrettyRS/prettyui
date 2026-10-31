local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function key(categoryID, dynamicID)
    return categoryID .. ":" .. dynamicID
end

local constructorCalls = 0
local function host(interfaceID)
    local static = {
        interfaceID = interfaceID, categoryID = -1, dynamicID = -1,
        children = {}, registry = {}, virtual = {},
    }
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
        categoryID = category, dynamicID = dynamic, kind = kind,
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
local managedAfterGroup = prettyui.NewComponent(ui.Text, content)
expect(primary.scans, 1, "managed component reuses the grouped occupancy walk")
managedAfterGroup:Destroy()
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

print("category_groups_test: ok")
