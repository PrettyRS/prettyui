local Layout = require("src/nis/native_tab_layout")

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

local function movesTheWholeClickableRowAndRestoresAnchors()
    local tabs, backgrounds, icons, hits = row()
    local records = assert(Layout.capture(tabs, tabs.children))
    expect(#records, 6, "both native tabs include background, icon and hit region")
    local originals, visualX = {}, {}
    for index, record in ipairs(records) do
        originals[index], visualX[index] = record.original, record.x
    end
    Layout.track(tabs, records)
    for _, record in ipairs(records) do Layout.move(record, 26) end
    for index, record in ipairs(records) do
        local moved = { table.unpack(originals[index]) }
        moved[1] = moved[1] + 26
        assertAnchors(record.component, moved, visualX[index] + 26, "moved tab child")
    end
    expect(hits[1].x, backgrounds[1].x, "clickable area follows the tab background")
    expect(hits[2].x, backgrounds[2].x, "second clickable area follows its background")
    expect(icons[1].x - backgrounds[1].x, 8, "icon stays centered")
    expect(backgrounds[2].x - backgrounds[1].x, 40, "tabs keep their spacing")

    records = assert(Layout.capture(tabs, tabs.children))
    Layout.track(tabs, records)
    for _, record in ipairs(records) do Layout.move(record, 38) end
    expect(backgrounds[1].x, 38, "repositioning replaces rather than adds offsets")
    Layout.restore(tabs)
    for index, record in ipairs(records) do
        assertAnchors(record.component, originals[index], visualX[index], "restored tab child")
    end
end

local function protectsReplacedNativeHandles()
    local tabs, backgrounds = row()
    local records = assert(Layout.capture(tabs, tabs.children))
    Layout.track(tabs, records)
    for _, record in ipairs(records) do Layout.move(record, 15) end
    local old = backgrounds[1]
    local replacement = component(tabs, tabs.interfaceID, tabs.staticID, old.categoryID,
        old.dynamicID, { x = 73, y = 0, xParentPc = 0, yParentPc = 0, xSelfPc = 0, ySelfPc = 0 }, 40, 28)
    table.remove(tabs.children)
    tabs.children[1] = replacement
    old.retired = true
    Layout.restore(tabs)
    expect(replacement.position.x, 73, "independently laid out replacement remains native-owned")
    expect(replacement.writes, 0, "replacement is not overwritten")
    expect(backgrounds[2].x, 40, "live neighbor is still restored")

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
    expect(replacement.position.x, 0, "replacement carrying our applied offset restores safely")
end

local function honorsNativeLayoutChanges()
    local tabs, backgrounds = row()
    local records = assert(Layout.capture(tabs, tabs.children))
    Layout.track(tabs, records)
    Layout.move(records[1], 19)
    backgrounds[1].position.x = 0
    backgrounds[1].x = 0
    local captured = assert(Layout.capture(tabs, tabs.children))
    expect(captured[1].x, 0, "client reset establishes the new baseline")
    expect(captured[1].offset, 0, "client reset releases our old offset")
    Layout.track(tabs, captured)
    expect(Layout.move(captured[1], 19), false, "unexplained reset prevents fighting the client")
    Layout.track(tabs, captured, true)
    expect(Layout.move(captured[1], 19), true, "confirmed rebuild permits movement")
    Layout.restore(tabs)
    expect(backgrounds[1].x, 0, "rebuild restores the adopted baseline")

    tabs, backgrounds = row()
    records = assert(Layout.capture(tabs, tabs.children))
    Layout.track(tabs, records)
    Layout.move(records[1], 12)
    backgrounds[1].position.yParentPc = 0.25
    local writes = backgrounds[1].writes
    Layout.restore(tabs)
    expect(backgrounds[1].writes, writes, "unload does not undo a foreign anchor edit")
    expect(backgrounds[1].position.yParentPc, 0.25, "foreign native anchor survives")
end

local function recoversFromAnAppliedButFailingSetter()
    local tabs, backgrounds = row()
    local records = assert(Layout.capture(tabs, tabs.children))
    Layout.track(tabs, records)
    backgrounds[1].throwAfterSet = true
    expect(pcall(Layout.move, records[1], 22), false, "native setter failure propagates")
    expect(backgrounds[1].position.x, 22, "native setter applied the move before failing")
    Layout.restore(tabs)
    expect(backgrounds[1].position.x, 0, "unload recovers an applied move")
end

local function avoidsRetiredNativeInterfaces()
    local tabs, backgrounds = row()
    local records = assert(Layout.capture(tabs, tabs.children))
    Layout.track(tabs, records)
    Layout.move(records[1], 9)
    backgrounds[1].retired = true
    loaded[tabs.interfaceID] = nil
    Layout.restore(tabs)
    loaded[tabs.interfaceID] = {}
    expect(Layout.capture(tabs, tabs.children)[1].offset, 0, "unload releases old ownership")

    tabs, backgrounds = row()
    backgrounds[1].position.xSelfPc = nil
    expect(Layout.capture(tabs, tabs.children), nil, "unreadable native anchors reject capture")
end

local function followsNativeParentGeometry()
    local tabs, _, icons = row()
    local records = assert(Layout.capture(tabs, tabs.children))
    Layout.track(tabs, records)
    Layout.move(records[2], 8)
    local originalX = icons[1].x
    tabs.width = tabs.width + 20
    local pos = icons[1].position
    icons[1]:SetPos(pos.x, pos.y, pos.xParentPc, pos.yParentPc, pos.xSelfPc, pos.ySelfPc)
    local captured = assert(Layout.capture(tabs, tabs.children))
    expect(captured[2].x, originalX + 2 - 8, "parent resize updates native computed geometry")
    Layout.track(tabs, captured)
    Layout.restore(tabs)
    expect(icons[1].x, originalX + 2 - 8, "restore retains the native parent resize")
end

movesTheWholeClickableRowAndRestoresAnchors()
protectsReplacedNativeHandles()
honorsNativeLayoutChanges()
recoversFromAnAppliedButFailingSetter()
avoidsRetiredNativeInterfaces()
followsNativeParentGeometry()
print("nis native tab layout tests passed")
