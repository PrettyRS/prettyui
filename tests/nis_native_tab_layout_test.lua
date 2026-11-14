local Layout = require("src/core/nis_native_tab_layout")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local loaded, static = {}, {}
ui = { Interfaces = {} }
function ui.Interfaces:GetInterface(interfaceID)
    return loaded[interfaceID]
end
function ui.Interfaces:GetComponent(packed)
    return static[packed]
end

local positions = { "x", "y", "xParentPc", "yParentPc", "xSelfPc", "ySelfPc" }
local function component(parent, interfaceID, staticID, categoryID, dynamicID, position, width, height)
    local item = {
        parent = parent, interfaceID = interfaceID, staticID = staticID,
        categoryID = categoryID, dynamicID = dynamicID, position = position,
        width = width, height = height, children = {}, writes = 0,
    }
    local function layout()
        item.x = item.position.x + (parent and parent.width or 0) * item.position.xParentPc
            + item.width * item.position.xSelfPc
        item.y = item.position.y + (parent and parent.height or 0) * item.position.yParentPc
            + item.height * item.position.ySelfPc
    end
    function item:SetPos(x, y, xParentPc, yParentPc, xSelfPc, ySelfPc)
        assert(not self.retired, "attempted to write a retired native child")
        self.writes = self.writes + 1
        self.position = { x = x, y = y, xParentPc = xParentPc, yParentPc = yParentPc,
            xSelfPc = xSelfPc, ySelfPc = ySelfPc }
        layout()
        if self.throwAfterSet then self.throwAfterSet = false; error("native setter failed after applying") end
    end
    function item:IterateDynamicComponents(callback)
        for _, child in ipairs(self.children) do
            if callback(child, true) then break end
        end
    end
    layout()
    if parent then parent.children[#parent.children + 1] = item end
    return item
end

local nextInterfaceID = 100
local function row()
    nextInterfaceID = nextInterfaceID + 1
    local interfaceID, staticID = nextInterfaceID, 9
    loaded[interfaceID] = {}
    local frame = component(nil, interfaceID, 1, -1, -1,
        { x = 0, y = 0, xParentPc = 0, yParentPc = 0, xSelfPc = 0, ySelfPc = 0 }, 300, 300)
    local tabs = component(frame, interfaceID, staticID, -1, -1,
        { x = 0, y = 0, xParentPc = 0, yParentPc = 0, xSelfPc = 0, ySelfPc = 0 }, 280, 28)
    static[(interfaceID << 16) | staticID] = tabs
    -- One background, icon and input component per native tab. The icon's
    -- nonzero anchor coefficients expose accidental SetPos(x, y) writes.
    local backgrounds, icons, hits = {}, {}, {}
    for index = 1, 2 do
        local x = (index - 1) * 40
        backgrounds[index] = component(tabs, interfaceID, staticID, 0, index * 3,
            { x = x, y = 0, xParentPc = 0, yParentPc = 0, xSelfPc = 0, ySelfPc = 0 }, 40, 28)
        icons[index] = component(tabs, interfaceID, staticID, 0, index * 3 + 1,
            { x = x - 8, y = 2, xParentPc = 0.1, yParentPc = 0,
                xSelfPc = -0.5, ySelfPc = 0 }, 24, 24)
        hits[index] = component(tabs, interfaceID, staticID, 0, index * 3 + 2,
            { x = x, y = 0, xParentPc = 0, yParentPc = 0,
                xSelfPc = 0, ySelfPc = 0 }, 40, 28)
    end
    return tabs, backgrounds, icons, hits
end

local function assertAnchors(component, original, x, message)
    expect(component.x, x, message .. " visual x")
    for index, key in ipairs(positions) do
        expect(component.position[key], original[index], message .. " " .. key)
    end
end

-- A whole native tab, not just its artwork, must move as a single clickable row.
local tabs, backgrounds, icons, hits = row()
local records = assert(Layout.capture(tabs, tabs.children))
expect(#records, 6, "all direct native tab children captured")
local originals, baselineX = {}, {}
for index, record in ipairs(records) do
    originals[index], baselineX[index] = record.original, record.x
    expect(record.offset, 0, "new native tab starts unowned")
end
Layout.track(tabs, records)
for _, record in ipairs(records) do
    expect(Layout.move(record, 26), true, "native tab child displacement accepted")
end
for index, record in ipairs(records) do
    local original = { table.unpack(originals[index]) }
    original[1] = original[1] + 26
    assertAnchors(record.component, original, baselineX[index] + 26,
        "tab background/icon/hit displaced together")
end
expect(backgrounds[2].x - backgrounds[1].x, 40, "background tab spacing")
expect(icons[2].x - icons[1].x, 40, "icon tab spacing")
expect(hits[2].x - hits[1].x, 40, "input tab spacing")
expect(icons[1].x - backgrounds[1].x, 8, "icon remains centered on native background")
expect(hits[1].x, backgrounds[1].x, "native hit region follows its background")

local captured = assert(Layout.capture(tabs, tabs.children))
for index, record in ipairs(captured) do
    expect(record.x, baselineX[index], "discovery normalizes owned displacement")
    expect(record.offset, 26, "discovery retains current owned offset")
    expect(record.original[1], originals[index][1], "discovery retains native scalar baseline")
end
Layout.track(tabs, captured)
for _, record in ipairs(captured) do
    local writes = record.component.writes
    Layout.move(record, 26)
    expect(record.component.writes, writes, "unchanged offset does not write")
    Layout.move(record, 38)
end
expect(backgrounds[1].x, 38, "later displacement replaces rather than accumulates offset")
Layout.restore(tabs)
for index, record in ipairs(records) do
    assertAnchors(record.component, originals[index], baselineX[index], "teardown restores native row")
end

-- An old handle is never used for cleanup. Replacement children with identical
-- IDs but independent positions are not overwritten, while still-owned live
-- neighbors can be restored from fresh enumeration.
tabs, backgrounds = row()
records = assert(Layout.capture(tabs, tabs.children))
Layout.track(tabs, records)
for _, record in ipairs(records) do Layout.move(record, 15) end
local old = backgrounds[1]
local replacement = component(tabs, tabs.interfaceID, tabs.staticID, old.categoryID,
    old.dynamicID, { x = 73, y = 0, xParentPc = 0, yParentPc = 0, xSelfPc = 0, ySelfPc = 0 }, 40, 28)
table.remove(tabs.children)
tabs.children[1] = replacement
old.retired = true
Layout.restore(tabs)
expect(replacement.position.x, 73, "same-ID replacement preserves its independent native layout")
expect(replacement.writes, 0, "same-ID replacement receives no write")
expect(backgrounds[2].x, 40, "still-owned neighbor restores from fresh enumeration")

-- A full-ID replacement carrying our exact applied position is safe to restore,
-- but the stale original component must remain untouched.
tabs, backgrounds = row()
records = assert(Layout.capture(tabs, tabs.children))
Layout.track(tabs, records)
Layout.move(records[1], 17)
old = backgrounds[1]
replacement = component(tabs, tabs.interfaceID, tabs.staticID, old.categoryID,
    old.dynamicID, { x = 17, y = 0, xParentPc = 0, yParentPc = 0, xSelfPc = 0, ySelfPc = 0 }, 40, 28)
table.remove(tabs.children)
tabs.children[1] = replacement
old.retired = true
Layout.restore(tabs)
expect(replacement.position.x, 0, "fresh child carrying owned layout restores")
expect(replacement.writes, 1, "fresh child gets precisely one restore write")

-- A same-ID client reset is adopted as a new baseline, not subtracted as our
-- old offset. A recurring reset blocks writes until a known rebuild is allowed.
tabs, backgrounds = row()
records = assert(Layout.capture(tabs, tabs.children))
Layout.track(tabs, records)
Layout.move(records[1], 19)
backgrounds[1].position.x = 0
backgrounds[1].x = 0
captured = assert(Layout.capture(tabs, tabs.children))
expect(captured[1].x, 0, "native reset adopts true baseline")
expect(captured[1].offset, 0, "native reset discards stale owned offset")
Layout.track(tabs, captured)
local writes = backgrounds[1].writes
expect(Layout.move(captured[1], 19), false, "unexplained client reset blocks displacement")
expect(backgrounds[1].writes, writes, "blocked displacement never fights native script")
captured = assert(Layout.capture(tabs, tabs.children))
Layout.track(tabs, captured)
expect(Layout.move(captured[1], 19), false, "blocked reset stays blocked across refreshes")
Layout.track(tabs, captured, true)
expect(Layout.move(captured[1], 19), true, "confirmed rebuild permits a fresh displacement")
Layout.restore(tabs)
expect(backgrounds[1].x, 0, "confirmed rebuild still restores to adopted native baseline")

-- Never overwrite an unexpected native edit that happened after discovery.
tabs, backgrounds = row()
records = assert(Layout.capture(tabs, tabs.children))
Layout.track(tabs, records)
backgrounds[1].position.yParentPc = 0.5
writes = backgrounds[1].writes
expect(pcall(Layout.move, records[1], 12), false, "late native write invalidates stale capture")
expect(backgrounds[1].writes, writes, "stale capture cannot overwrite client layout")
Layout.restore(tabs)
expect(backgrounds[1].position.yParentPc, 0.5, "teardown preserves foreign anchor changes")

-- Foreign edits to already-displaced children must not be undone at teardown.
tabs, backgrounds = row()
records = assert(Layout.capture(tabs, tabs.children))
Layout.track(tabs, records)
Layout.move(records[1], 12)
backgrounds[1].position.yParentPc = 0.25
writes = backgrounds[1].writes
captured = assert(Layout.capture(tabs, tabs.children))
expect(captured[1].offset, 0, "foreign edit of displaced child adopts its new baseline")
expect(captured[1].x, 12, "foreign edit is not double-normalized")
Layout.restore(tabs)
expect(backgrounds[1].writes, writes, "teardown does not overwrite foreign displacement")
expect(backgrounds[1].position.yParentPc, 0.25, "teardown retains foreign anchors")

-- A setter that applies SetPos then throws still leaves recoverable ownership.
tabs, backgrounds = row()
records = assert(Layout.capture(tabs, tabs.children))
Layout.track(tabs, records)
backgrounds[1].throwAfterSet = true
expect(pcall(Layout.move, records[1], 22), false, "setter failure propagates")
expect(backgrounds[1].position.x, 22, "setter applied displacement before throwing")
captured = assert(Layout.capture(tabs, tabs.children))
expect(captured[1].offset, 22, "post-error discovery recognizes applied displacement")
Layout.restore(tabs)
expect(backgrounds[1].position.x, 0, "post-error teardown recovers baseline")

-- A restore setter may also apply then throw; ownership persists for retry.
tabs, backgrounds = row()
records = assert(Layout.capture(tabs, tabs.children))
Layout.track(tabs, records)
Layout.move(records[1], 31)
backgrounds[1].throwAfterSet = true
expect(pcall(Layout.restore, tabs), false, "restore failure propagates for retry")
expect(backgrounds[1].position.x, 0, "failed restore may have applied baseline")
Layout.restore(tabs)
expect(backgrounds[1].position.x, 0, "retry leaves already-restored baseline intact")
expect(Layout.capture(tabs, tabs.children)[1].offset, 0, "retry drops completed ownership")

-- Missing anchors reject the entire native strip rather than guessing zeros.
tabs, backgrounds = row()
backgrounds[1].position.xSelfPc = nil
expect(Layout.capture(tabs, tabs.children), nil, "unreadable native anchor rejects capture")
backgrounds[1].position = nil
expect(Layout.capture(tabs, tabs.children), nil, "missing position rejects capture")

-- An unloaded interface must not be probed via its now-retired tab handles.
tabs, backgrounds = row()
records = assert(Layout.capture(tabs, tabs.children))
Layout.track(tabs, records)
Layout.move(records[1], 9)
loaded[tabs.interfaceID] = nil
Layout.restore(tabs)
loaded[tabs.interfaceID] = {}
expect(Layout.capture(tabs, tabs.children)[1].offset, 0,
    "unload releases ownership without accessing retired native children")

-- A retired native tab collection cannot be used to restore its children.
tabs, backgrounds = row()
records = assert(Layout.capture(tabs, tabs.children))
Layout.track(tabs, records)
Layout.move(records[1], 9)
writes = backgrounds[1].writes
tabs.parent = nil
Layout.restore(tabs)
expect(backgrounds[1].writes, writes, "unparented native collection receives no restore writes")
expect(Layout.capture(tabs, tabs.children)[1].offset, 0,
    "unparented native collection releases ownership")

-- Rows with no PrettyUI displacement have nothing to restore: teardown must
-- not enumerate native children or look up an interface that may have remounted.
tabs, backgrounds, icons = row()
records = assert(Layout.capture(tabs, tabs.children))
Layout.track(tabs, records)
local oldInterface, oldComponent = ui.Interfaces.GetInterface, ui.Interfaces.GetComponent
local oldIterate = tabs.IterateDynamicComponents
local interfaceReads, componentReads, enumerations = 0, 0, 0
function ui.Interfaces:GetInterface(...)
    interfaceReads = interfaceReads + 1
    return oldInterface(self, ...)
end
function ui.Interfaces:GetComponent(...)
    componentReads = componentReads + 1
    return oldComponent(self, ...)
end
function tabs:IterateDynamicComponents(...)
    enumerations = enumerations + 1
    return oldIterate(self, ...)
end
Layout.restore(tabs)
expect(interfaceReads, 0, "zero-offset cleanup never probes an interface")
expect(componentReads, 0, "zero-offset cleanup never looks up a native row")
expect(enumerations, 0, "zero-offset cleanup never enumerates native children")
expect(Layout.capture(tabs, tabs.children)[1].offset, 0,
    "zero-offset cleanup discards ownership for a later capture")
records = assert(Layout.capture(tabs, tabs.children))
Layout.track(tabs, records)
Layout.move(records[1], 11)
Layout.restore(tabs)
expect(interfaceReads > 0 and componentReads > 0 and enumerations > 0, true,
    "displaced cleanup still enumerates live native children")
expect(backgrounds[1].x, 0, "displaced cleanup restores native position")
tabs.IterateDynamicComponents = oldIterate
ui.Interfaces.GetInterface, ui.Interfaces.GetComponent = oldInterface, oldComponent

-- Parent geometry can change without a child anchor change. Discovery must
-- always sample computed x even when it reuses an immutable owned baseline.
tabs, backgrounds, icons = row()
records = assert(Layout.capture(tabs, tabs.children))
Layout.track(tabs, records)
Layout.move(records[2], 8)
local originalIconX = icons[1].x
tabs.width = tabs.width + 20
icons[1]:SetPos(table.unpack({ icons[1].position.x, icons[1].position.y,
    icons[1].position.xParentPc, icons[1].position.yParentPc,
    icons[1].position.xSelfPc, icons[1].position.ySelfPc }))
captured = assert(Layout.capture(tabs, tabs.children))
expect(captured[2].x, originalIconX + 2 - 8,
    "computed tab position follows native parent resize without stale geometry")
expect(captured[2].offset, 8, "parent resize keeps the owned horizontal offset")
Layout.track(tabs, captured)
Layout.restore(tabs)
expect(icons[1].x, originalIconX + 2 - 8,
    "native geometry remains authoritative after restoring horizontal displacement")

print("nis native tab layout tests passed")
