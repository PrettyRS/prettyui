-- Own only horizontal displacement of direct native tab children. Store identities
-- and layouts, never retained child handles: native scripts can rebuild a row
-- with exactly the same component IDs.
local NativeTabLayout = {}
local positions = { "x", "y", "xParentPc", "yParentPc", "xSelfPc", "ySelfPc" }
local tracked = {}
local handles = setmetatable({}, { __mode = "k" })

local function identity(component)
    if not component then return nil end
    local ok, a, b, c, d = pcall(function()
        return component.interfaceID, component.staticID, component.categoryID, component.dynamicID
    end)
    if not ok or type(a) ~= "number" or type(b) ~= "number"
        or type(c) ~= "number" or type(d) ~= "number" then return nil end
    return a .. ":" .. b .. ":" .. c .. ":" .. d, a, b
end

local function position(component)
    local ok, result = pcall(function()
        local current = component.position
        local values = {}
        for index, field in ipairs(positions) do
            local value = current[field]
            if type(value) ~= "number" then return nil end
            values[index] = value
        end
        return values
    end)
    if ok then return result end
    return nil
end

local function matches(component, original, offset)
    local ok, same = pcall(function()
        local current = component.position
        if current.x ~= original[1] + offset then return false end
        for index = 2, 6 do
            if current[positions[index]] ~= original[index] then return false end
        end
        return true
    end)
    return ok and same
end

local function copy(values)
    return { values[1], values[2], values[3], values[4], values[5], values[6] }
end

function NativeTabLayout.capture(tabs, children)
    local tabKey = identity(tabs)
    if not tabKey or type(children) ~= "table" then return nil end
    local previous = tracked[tabKey]
    local records, seen = {}, {}
    for _, child in ipairs(children) do
        local key = identity(child)
        if not key or seen[key] then return nil end
        seen[key] = true
        local ok, parent, x, width, height = pcall(function()
            return child.parent, child.x, child.width, child.height
        end)
        if not ok or identity(parent) ~= tabKey or type(x) ~= "number"
            or type(width) ~= "number" or type(height) ~= "number" then return nil end
        local current = position(child)
        if not current then return nil end
        local saved = previous and previous.records[key]
        local offset, conflicted = 0, false
        if saved then
            if matches(child, saved.original, saved.offset) then
                current = copy(saved.original)
                offset = saved.offset
            elseif saved.offset ~= 0 then
                -- Native code took over this layout. Accept its new baseline,
                -- but do not repeatedly displace a row it keeps resetting.
                conflicted = true
            end
        end
        records[#records + 1] = {
            component = child, key = key, original = current,
            x = x - offset, width = width, height = height, offset = offset,
            _tabsKey = tabKey, _conflicted = conflicted,
        }
    end
    return records
end

-- allowReset is for a confirmed native rebuild/lock reset, not routine refresh.
function NativeTabLayout.track(tabs, records, allowReset)
    local key, interfaceID, staticID = identity(tabs)
    assert(key and type(records) == "table", "invalid native tab layout")
    local previous = tracked[key]
    local saved = { key = key, interfaceID = interfaceID, staticID = staticID,
        parentKey = identity(tabs.parent), records = {} }
    for _, record in ipairs(records) do
        assert(record._tabsKey == key and record.key and not saved.records[record.key]
            and record.original and type(record.offset) == "number", "invalid native tab record")
        local old = previous and previous.records[record.key]
        local entry = {
            original = copy(record.original), offset = record.offset,
            blocked = not allowReset and (record._conflicted or old and old.blocked) or false,
        }
        saved.records[record.key] = entry
        record._entry = entry
    end
    tracked[key] = saved
    handles[tabs] = saved
end

function NativeTabLayout.move(record, offset)
    assert(type(offset) == "number" and offset % 1 == 0, "native tab offset must be an integer")
    local owner = tracked[record._tabsKey]
    local entry = owner and owner.records[record.key]
    assert(entry and entry == record._entry, "native tab record is no longer tracked")
    assert(identity(record.component) == record.key
        and matches(record.component, entry.original, entry.offset),
        "native tab position changed since capture")
    if entry.blocked then return false end
    if offset == entry.offset then return true end
    -- SetPos can apply a layout and then throw. Record ownership first so the
    -- next capture or restore can recognize the actual post-error position.
    entry.offset, record.offset = offset, offset
    local original = entry.original
    record.component:SetPos(original[1] + offset, original[2], original[3],
        original[4], original[5], original[6])
    return true
end

-- A confirmed client-owned same-ID row rebuild has no safe old handle to
-- restore: the same key may now identify the dragged source. Drop only our
-- displacement bookkeeping and capture fresh baselines on the new row.
function NativeTabLayout.forget(tabs)
    local key = identity(tabs)
    if key then tracked[key] = nil end
end

function NativeTabLayout.restore(tabs)
    local remembered = handles[tabs]
    local key = remembered and remembered.key or identity(tabs)
    local saved = key and tracked[key]
    if not saved or remembered and remembered ~= saved then return end
    local interfaceID, staticID = saved.interfaceID, saved.staticID
    local ok, loaded = pcall(function() return ui.Interfaces:GetInterface(interfaceID) end)
    if not ok then error(loaded) end
    if not loaded then tracked[key] = nil; return end
    local fresh = ui.Interfaces:GetComponent((interfaceID << 16) | staticID)
    if not fresh or identity(fresh) ~= key then tracked[key] = nil; return end
    local parentOK, parent = pcall(function() return fresh.parent end)
    if not parentOK or not parent or saved.parentKey and identity(parent) ~= saved.parentKey then
        tracked[key] = nil
        return
    end

    local children, seen = {}, {}
    fresh:IterateDynamicComponents(function(child)
        local childKey = identity(child)
        if childKey and identity(child.parent) == key then
            -- An ambiguous duplicate identity cannot safely identify either child.
            if seen[childKey] then children[childKey] = nil
            else children[childKey], seen[childKey] = child, true end
        end
        return false
    end)
    local failed
    for childKey, entry in pairs(saved.records) do
        local child = children[childKey]
        if child and entry.offset ~= 0 and matches(child, entry.original, entry.offset) then
            local original = entry.original
            local success, err = pcall(function()
                child:SetPos(original[1], original[2], original[3],
                    original[4], original[5], original[6])
            end)
            if not success then failed = failed or err end
        end
    end
    if failed then error(failed) end
    tracked[key] = nil
end

return NativeTabLayout
