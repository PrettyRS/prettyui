-- Recorded 1477 TAB_BACKGROUND: two native bar tiles border a 44-wide opening.
id = { Sprite = { RS3_CHILD_TAB_BAR_TILE = 18038 } }
local Divider = require("src/nis/native_divider")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local static, loaded = {}, {}
ui = { Interfaces = {} }
function ui.Interfaces.GetInterface(_, interfaceID)
    return loaded[interfaceID]
end
function ui.Interfaces.GetComponent(_, packed)
    return static[packed]
end

local function component(parent, staticID, dynamicID, x, y, width, height, sprite)
    local item = {
        interfaceID = 1477,
        staticID = staticID,
        categoryID = dynamicID and 0 or -1,
        dynamicID = dynamicID or -1,
        parent = parent,
        children = {},
        type = sprite and 3 or 20,
        spriteID = sprite,
        visible = true,
        hidden = false,
        position = { x = x, y = y, xParentPc = 0, yParentPc = 0, xSelfPc = 0, ySelfPc = 0 },
        size = { width = width, height = height, widthParentPc = 0, heightParentPc = 0 },
        writes = 0,
    }
    function item:Relayout()
        local pos, size = self.position, self.size
        self.width = size.width + self.parent.width * size.widthParentPc
        self.height = size.height + self.parent.height * size.heightParentPc
        self.x = pos.x + self.parent.width * pos.xParentPc - self.width * pos.xSelfPc
        self.y = pos.y + self.parent.height * pos.yParentPc - self.height * pos.ySelfPc
    end
    function item:SetPos(px, py, xp, yp, xs, ys)
        self.writes = self.writes + 1
        self.position = { x = px, y = py, xParentPc = xp, yParentPc = yp, xSelfPc = xs, ySelfPc = ys }
        self:Relayout()
        if self.failAfterSet then
            self.failAfterSet = false
            error("native position setter failed")
        end
    end
    function item:SetSize(w, h, wp, hp)
        self.writes = self.writes + 1
        self.size = { width = w, height = h, widthParentPc = wp, heightParentPc = hp }
        self:Relayout()
        if self.failAfterSet then
            self.failAfterSet = false
            error("native size setter failed")
        end
    end
    function item:IterateDynamicComponents(callback)
        for _, child in ipairs(self.children) do
            if callback(child, child.visible) then return end
        end
    end
    if parent then
        parent.children[#parent.children + 1] = item
        item:Relayout()
    else
        item.x, item.y, item.width, item.height = x, y, width, height
    end
    return item
end

local function row(width, leftWidth, rightWidth)
    width, leftWidth, rightWidth = width or 220, leftWidth or 84, rightWidth or 84
    loaded[1477] = true
    local frame = component(nil, 409, nil, 0, 0, width, 100)
    local backdrop = component(frame, 416, nil, 0, 4, width, 28)
    static[(1477 << 16) | 416] = backdrop
    -- Dynamic 0..4 are the two side sprites and corners in the supplied export.
    for index = 0, 4 do
        component(backdrop, 416, index, 0, index, 4, 4, 700 + index)
    end
    local left = component(backdrop, 416, 5, 4, 24, leftWidth, 4, 18038)
    local right = component(backdrop, 416, 6, -4, 0, rightWidth, 4, 18038)
    right.position.yParentPc, right.position.ySelfPc = 1, 1
    right.position.xParentPc, right.position.xSelfPc = 1, 1
    right:Relayout()
    expect(right.x, width - 4 - rightWidth, "native right tile follows its parent anchor")
    local spec = { TAB_BACKGROUND = (1477 << 16) | 416 }
    return { owner = 1477, key = "1477:409:-1:-1", spec = spec, backdrop = backdrop }, left, right
end

local function painted(left, right, x)
    return x >= left.x and x < left.x + left.width or x >= right.x and x < right.x + right.width
end

local function recordedEmotesDivider()
    local host, left, right = row(129, 22, 55)
    expect(left.x + left.width, 26, "recorded left tile ends at 26")
    expect(right.x, 70, "recorded right tile begins at 70")
    expect(right.x + right.width, 125, "recorded right tile ends at 125")
    Divider.align(host, 76, 40)
    expect(painted(left, right, 30), true, "native opening closes beneath an inactive tab")
    expect(painted(left, right, 80), false, "own selected opening replaces native opening")
    Divider.restore(host)
    expect(left.width, 22, "recorded left width restores")
    expect(right.position.x, -4, "recorded right anchor restores")
end

local function selectedOpeningAndInactiveNativeTab()
    local host, left, right = row()
    expect(painted(left, right, 127), false, "native initial opening covers the probe")
    expect(Divider.align(host, 170, 40), true, "own selection moves native divider edges")
    expect(painted(left, right, 127), true, "no stray slit at the inactive native tab")
    expect(painted(left, right, 169), true, "bar meets selected tab's left edge")
    expect(painted(left, right, 170), false, "own selected tab keeps its opening")
    expect(painted(left, right, 207), false, "own selected tab opening reaches its right edge")
    expect(painted(left, right, 210), true, "bar resumes after own selected tab")
    local writes = left.writes + right.writes
    Divider.align(host, 170, 40)
    expect(left.writes + right.writes, writes, "stable selection does not rewrite native edges")
    -- A returning native selected tab was displaced 40 px in the mixed row.
    Divider.align(host, 128, 44)
    expect(painted(left, right, 127), true, "displaced native gap does not open at its old slot")
    expect(painted(left, right, 128), false, "returning native selection opens at its new position")
    expect(painted(left, right, 171), false, "returning native opening keeps native width")
    expect(painted(left, right, 172), true, "returning native selection ends at its new position")
    Divider.restore(host)
    expect(left.x + left.width, 88, "native left tile restored")
    expect(right.x, 132, "native right tile and self anchor restored")
    expect(right.position.x, -4, "original right-tile anchor retained")
    expect(right.size.width, 84, "original right-tile width restored")
end

local function clipsAndAdoptsNativeChanges()
    local host, left, right = row()
    Divider.align(host, 200, 9) -- viewport clips a tab at x=209.
    expect(painted(left, right, 199), true, "clipped opening begins at visible position")
    expect(painted(left, right, 208), false, "clipped selected tab remains open")
    expect(painted(left, right, 209), true, "bar resumes after viewport edge")
    expect(Divider.changed(host), false, "our own edge writes are not native changes")
    right:SetPos(-12, 0, 1, 1, 1, 1) -- client owns the new right-tile anchor
    expect(Divider.changed(host), true, "native repaint is observable without writing")
    local nativePosition = right.position.x
    Divider.restore(host)
    expect(left.x + left.width, 88, "untouched left edge restores independently")
    expect(right.position.x, nativePosition, "cleanup preserves native-owned right anchor")
end

local function survivesPartialWritesAndRebuilds()
    local host, left, right = row()
    left.failAfterSet = true
    expect(pcall(Divider.align, host, 170, 40), false, "setter failure propagates")
    expect(left.width, 166, "setter applied its partial width")
    Divider.restore(host)
    expect(left.width, 84, "partially applied width is recoverable")
    Divider.align(host, 170, 40)
    local former = right
    local replacement = component(host.backdrop, 416, 6, -7, 0, 90, 4, 18038)
    replacement.position.xParentPc, replacement.position.xSelfPc = 1, 1
    replacement.position.yParentPc, replacement.position.ySelfPc = 1, 1
    replacement:Relayout()
    host.backdrop.children[#host.backdrop.children] = nil
    host.backdrop.children[7] = replacement
    former.retired = true
    expect(Divider.changed(host), true, "same-ID native child rebuild is observed")
    Divider.restore(host)
    expect(replacement.writes, 0, "retired edge's write is not imposed on a rebuilt child")
    expect(replacement.position.x, -7, "rebuilt native anchor remains owned by client")
    expect(left.width, 84, "live edge still restores after neighbor rebuild")
    Divider.align(host, 170, 40)
    local writes = replacement.writes
    loaded[1477] = nil
    Divider.restore(host)
    expect(replacement.writes, writes, "unloaded interface is not written")
    expect(host.nativeDivider, nil, "retired native divider state is released")
end

local function restoresDuringPartialNativeRepaint()
    local host, left, right = row()
    Divider.align(host, 170, 40)
    host.backdrop.children[7] = nil -- one tile is absent for this Draw
    Divider.restore(host)
    expect(left.width, 84, "available native tile restores during partial repaint")
    expect(host.nativeDivider ~= nil, true, "missing native tile retains its restoration state")
    host.backdrop.children[7] = right
    Divider.restore(host)
    expect(right.x, 132, "returning tile restores its native gap")
    expect(host.nativeDivider, nil, "complete native pair releases its saved state")
end

recordedEmotesDivider()
selectedOpeningAndInactiveNativeTab()
clipsAndAdoptsNativeChanges()
survivesPartialWritesAndRebuilds()
restoresDuringPartialNativeRepaint()
print("nis native divider tests passed")
