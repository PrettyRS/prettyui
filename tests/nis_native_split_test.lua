local Fixture = require("tests/nis_fixture")
local nativeScene = require("tests/nis_native_fixture")

local function nativeHook(component, kind)
    local _, callback = next(component.namedSubscriptions[kind] or {})
    assert(callback and callback(component, 10, 10), "observer must leave native input enabled")
end

local function cycle(f)
    f:emit("Logic")
    f:emit("Draw")
end

local function assertMixedRow(f, scene, panel, remaining)
    local binding = assert(panel._nisNative, "panel detached from its nest")
    local tab = binding.tabs[binding.group.current]
    local left = remaining.frame.x + remaining.tabs.x
    local top = remaining.frame.y + remaining.tabs.y
    f.expect(remaining.backgrounds[1].x, 0, "first native tab starts the row")
    f.expect(tab.hit.x, left + 44, "own tab follows the first native tab")
    f.expect(remaining.backgrounds[2].x, 84, "second native tab follows the own tab")
    f.expect(f.hitAt(scene.area, left + 45, top + 10), tab.hit, "own tab receives input in the surviving nest")
end

Fixture.run("native tear-out leaves the mixed row in the original nest without a release hook", function(f)
    local scene = nativeScene(f)
    local emotes, first, last = scene.notes, scene.ranged, scene.magic
    local inventory = scene.host(3000, "INVENTORY_WINDOW", true, { 8000 })
    inventory.frame:SetPos(10, 100)
    inventory.tabs.visible = false
    last.frame:SetPos(500, 100)
    for index, host in ipairs({ first, emotes, last }) do
        host:rebuild({ 9001, 9002, 9003 }, index)
    end
    first.frame.nativeShown, emotes.frame.nativeShown = true, false

    local panel = f:panel({ id = "nested", x = 300, y = 480 })
    f:begin(panel)
    f:move(panel, 560, 128)
    f:release(panel)
    assert(panel._nisNative and not panel.root.hidden)
    nativeHook(first.backgrounds[2], ui.Hook.ONCLICK)
    first.frame.nativeShown, emotes.frame.nativeShown = false, true
    cycle(f)
    assert(panel.root.hidden and not emotes.body.hidden, "native page selected before tear-out")

    local source = emotes.backgrounds[2]
    nativeHook(source, ui.Hook.ONCLICK)
    nativeHook(source, ui.Hook.ONRELEASE)
    last.frame.nativeShown = true -- the client hands capture between coincident frame copies
    f:emit("Draw")
    emotes.frame:SetPos(200, 20)
    emotes:rebuild({ 9002 }, 1)
    emotes.tabs.visible = false
    last:rebuild({ 9001, 9003 }, 2)
    -- The hidden copy still has three tabs. Do not wait for hover, release or another Logic tick.
    f:emit("Draw")
    assertMixedRow(f, scene, panel, last)
    f.expect(emotes.backgrounds[1].x, 0, "departing page has no borrowed offset")
    first:rebuild({ 9001, 9003 }, 1)
    cycle(f)

    -- The client repaints the remaining row on mouseover using the same handles.
    last.backgrounds[2]:SetPos(44, 0)
    last.tabs.children[4]:SetPos(54, 2)
    f:emit("Draw")
    assertMixedRow(f, scene, panel, last)

    emotes.frame:SetPos(inventory.frame.x, inventory.frame.y)
    inventory.tabs.visible, emotes.tabs.visible = true, true
    inventory.frame.nativeShown = false
    emotes:rebuild({ 8000, 9002 }, 2)
    inventory:rebuild({ 8000, 9002 }, 1)
    cycle(f)
    assertMixedRow(f, scene, panel, last)
    f.expect(emotes.backgrounds[2].x, 44, "destination nest has only native tabs")
    emotes.frame.nativeShown, inventory.frame.nativeShown = false, true
    cycle(f)
    assertMixedRow(f, scene, panel, last)
    assert(panel:SelectTab() and not panel.root.hidden and not inventory.body.hidden)
    f.expect(panel.root.x, last.frame.x + last.body.x, "own content opens in the source nest")
    f.expect(#f:saved("nested").native.frames, 2, "only remaining native frames are persisted")
end)

local function splitToStandalone(f)
    local scene = nativeScene(f)
    local panel = f:panel()
    assert(panel:DockTo(scene.notes.frame))
    local source = scene.notes.backgrounds[2] -- the hook belongs to Notes, the dragged page is Ranged
    nativeHook(source, ui.Hook.ONCLICK)
    nativeHook(source, ui.Hook.ONDRAG)
    scene.ranged.frame.nativeShown = true
    scene.ranged.frame:SetPos(30, 300)
    for index, host in ipairs({ scene.notes, scene.ranged }) do
        host:rebuild({ 9000 + index }, 1)
        host.tabs.visible = false
        host.body:SetPos(4, 16)
    end
    -- Release can precede Logic/Draw and must not paint the old row one last time.
    nativeHook(source, ui.Hook.ONDRAGCOMPLETE)
    f:emit("Draw")
    return scene, panel
end

Fixture.run("a two-page nest retains its last native page and restores its standalone content", function(f)
    local scene, panel = splitToStandalone(f)
    local binding = assert(panel._nisNative)
    local tab = binding.tabs[binding.group.current]
    f.expect(tab.hit.x, scene.notes.frame.x + 4 + 40, "own tab follows the single remaining native tab")
    assert(tab.hit.enabled and not tab.hit.hidden and not scene.ranged.body.hidden)
    f.expect(scene.wrapper.y, 28, "only the surviving standalone page reserves a tab band")
    panel:Undock()
    f.expect(scene.wrapper.y, 0, "undocking returns standalone native content to its original bounds")
end)

Fixture.run("redocking to the last native page replaces the standalone tab and inset", function(f)
    local scene, panel = splitToStandalone(f)
    local notes = scene.notes
    local binding = panel._nisNative
    local synthetic = binding.group.hosts[binding.group.current].nativeTab.hit
    scene.ranged.frame:SetPos(notes.frame.x, notes.frame.y)
    scene.ranged.frame.nativeShown = false
    notes.tabs.visible = true
    notes.body:SetPos(4, 44)
    notes:rebuild({ 9001, 9002 }, 1)
    f:emit("Draw")
    assert(synthetic.destroyed, "the standalone tab must not cover the real native tab")
    f.expect(scene.wrapper.y, 0, "native content no longer needs an extra tab inset")
    local tab = binding.tabs[binding.group.current]
    assert(tab.hit.enabled and not tab.hit.hidden and notes.body.visibleGlobal)
    local ownX = tab.hit.x - notes.frame.x - notes.tabs.x
    local second = notes.backgrounds[2]
    assert(ownX + tab.hit.width == second.x or second.x + second.width == ownX, "disjoint adjacent tabs on return")
end)

Fixture.run("a cancelled tear-out restores the original mixed nest", function(f)
    local scene = nativeScene(f)
    local panel = f:panel()
    assert(panel:DockTo(scene.notes.frame))
    local source = scene.notes.backgrounds[1]
    nativeHook(source, ui.Hook.ONCLICK)
    nativeHook(source, ui.Hook.ONDRAG)
    scene.ranged.frame.nativeShown = true
    scene.notes.frame:SetPos(240, 125)
    cycle(f)
    scene.notes.frame:SetPos(500, 100)
    scene.ranged.frame.nativeShown = false
    cycle(f)
    local binding = assert(panel._nisNative)
    local tab = binding.tabs[binding.group.current]
    f.expect(tab.hit.x, scene.notes.frame.x + 4 + 88, "cancelled split restores the original trailing tab")
    assert(tab.hit.enabled and not tab.hit.hidden)
end)

local function checkOwnTab(f, scene, host, panel, slot)
    local binding = assert(panel._nisNative)
    local tab = binding.tabs[binding.group.current]
    local left, top = host.frame.x + host.tabs.x + slot, host.frame.y + host.tabs.y
    f.expect(tab.hit.x, left, "own input follows its mixed slot")
    f.expect(f.hitAt(scene.area, left + 2, top + 12), tab.hit, "own slot remains clickable")
    local origin = scene.area.xyGlobal
    local painted = scene.paintedAt(scene.area, origin.x + left + 2, origin.y + top + 12)
    f.expect(painted, tab.background, "own tab is painted above the native strip")
end

local function checkFivePaintedTabs(f, scene, host)
    local origin = host.tabs.xyGlobal
    local iconWidths, tabWidths = {}, {}
    for x = 0, host.tabs.width - 1 do
        local icon = scene.paintedAt(scene.area, origin.x + x, origin.y + 12)
        if icon then iconWidths[icon.spriteID] = (iconWidths[icon.spriteID] or 0) + 1 end
        local bg = scene.paintedAt(scene.area, origin.x + x, origin.y + 1)
        if bg then tabWidths[bg] = (tabWidths[bg] or 0) + 1 end
    end
    for _, icon in ipairs({ 9001, 9004, 9005, 9003, 9002 }) do
        f.expect(iconWidths[icon], 24, "hover must paint the entire icon " .. icon)
    end
    local complete = 0
    for bg, width in pairs(tabWidths) do
        if bg.spriteID == id.Sprite.RS3_CHILD_TAB_SELECTED or bg.spriteID == id.Sprite.RS3_CHILD_TAB_UNSELECTED then
            f.expect(width, bg.width, "hover must not cover even the edge of a tab")
            complete = complete + 1
        end
    end
    f.expect(complete, 5, "all five backgrounds paint during the held drag")
end

local function paintHeld(f, scene, host, slot, x, iconX)
    host.backgrounds[slot]:SetPos(x, 0)
    local icon = host.tabs.children[2 * slot]
    icon:SetPos(iconX or x + 10, 2)
    host.frame:MoveToFront()
    f:emit("Draw")
    checkFivePaintedTabs(f, scene, host)
    f.expect(host.backgrounds[slot].x, x, "preview must not move the captured tab away from the pointer")
    f.expect(icon.x, iconX or x + 10, "preview must not move the native drag icon")
end

local function hoverOver(f, scene, returning, staying, keepHeld)
    local x, y = returning.frame.x, returning.frame.y
    returning.frame:SetPos(staying.frame.x, staying.frame.y)
    returning.tabs.visible = true
    returning:rebuild({ 9001, 9003, 9002 }, 3)
    local backdrop = returning.backdrop
    local buffer = f.component(backdrop, "sprite")
    buffer.spriteID = id.Sprite.RS3_CHILD_TAB_BUFFER_TILE
    buffer:SetSize(backdrop.width, 24)
    -- The native preview is now in front, but the resident frame and its row
    -- still exist behind it. The selected tab follows the pointer, not a slot.
    for _, ghostX in ipairs({ 151, 58, 151, 151 }) do
        paintHeld(f, scene, returning, 3, ghostX)
    end
    returning.backgrounds[2]:SetPos(0, 0) -- peer is repainted beneath the first tab
    paintHeld(f, scene, returning, 3, 151, 107) -- icon still at last frame's position
    returning:rebuild({ 9002, 9001, 9003 }, 1)
    paintHeld(f, scene, returning, 1, 151)
    f.expect(returning.backgrounds[2].x, 0, "resident tabs keep their order as the provisional insertion changes")
    f.expect(#f:saved("redock").native.frames, 2, "hover does not save a provisional native frame")
    if keepHeld then return end
    returning.frame:SetPos(x, y)
    returning.tabs.visible = false
    returning:rebuild({ 9002 }, 1)
    cycle(f)
    f.expect(returning.backgrounds[1].x, 0, "leaving the preview returns the floating strip to native layout")
    f.expect(#f:saved("redock").native.frames, 2, "a cancelled hover does not join the floating frame")
end

local function dividerAtDrop(f, host, selected)
    local backdrop = host.backdrop
    local function tile(index, x, width, anchor)
        local item = f.component(backdrop, "sprite", 0, index)
        item.type, item.visible, item.spriteID = 3, true, id.Sprite.RS3_CHILD_TAB_BAR_TILE
        item:SetSize(width, 4)
        item:SetPos(x, 0, anchor, 1, anchor, 1)
        return item
    end
    local left = tile(5, 4, (selected - 1) * 44, 0)
    tile(6, -4, backdrop.width - 8 - selected * 44, 1)
    return left
end

local function redock(f, returningSelected, dropHeld)
    local scene = nativeScene(f)
    local staying, returning, hidden = scene.notes, scene.ranged, scene.magic
    hidden.frame:SetPos(staying.frame.x, staying.frame.y)
    for index, host in ipairs({ staying, returning, hidden }) do
        host:rebuild({ 9001, 9002, 9003 }, index)
    end
    local panel = f:panel({ id = "redock", tabIcon = 9004, x = 40, y = 480 })
    f:begin(panel)
    f:move(panel, 560, 128)
    f:release(panel)
    local second = f:panel({ id = "redock-second", tabIcon = 9005, x = 340, y = 480 })
    f:begin(second)
    f:move(second, 640, 128)
    f:release(second)
    checkOwnTab(f, scene, staying, panel, 44)
    checkOwnTab(f, scene, staying, second, 128)
    f.expect(staying.backgrounds[3].x, 168, "native / own / native / own / native before tear-out")
    nativeHook(staying.backgrounds[2], ui.Hook.ONCLICK)
    staying.frame.nativeShown, returning.frame.nativeShown = false, true
    cycle(f)
    nativeHook(returning.backgrounds[2], ui.Hook.ONCLICK)
    nativeHook(returning.backgrounds[2], ui.Hook.ONDRAG)
    returning.frame:SetPos(200, 20)
    returning:rebuild({ 9002 }, 1)
    returning.tabs.visible = false
    staying.frame.nativeShown = true
    staying:rebuild({ 9001, 9003 }, 1)
    hidden:rebuild({ 9001, 9003 }, 2)
    cycle(f)
    checkOwnTab(f, scene, staying, panel, 44)
    checkOwnTab(f, scene, staying, second, 84)
    f.expect(staying.backgrounds[2].x, 124, "trailing native page stays after both own tabs")

    -- The held drag can repaint the background independently of its icon
    -- and badges, several times between Logic ticks.
    for _, nativeX in ipairs({ 44, 0, 0, 44 }) do
        staying.backgrounds[2]:SetPos(nativeX, 0)
        f:emit("Draw")
        f.expect(staying.backgrounds[2].x, 124, "native drag repaint cannot cover either own tab")
        checkOwnTab(f, scene, staying, panel, 44)
        checkOwnTab(f, scene, staying, second, 84)
    end
    hoverOver(f, scene, returning, staying, dropHeld)
    if not dropHeld then
        checkOwnTab(f, scene, staying, panel, 44)
        checkOwnTab(f, scene, staying, second, 84)
        -- A new insertion can preview at the end but commit in the middle.
        staying:rebuild({ 9001, 9003, 9002 }, 1)
        hidden:rebuild({ 9001, 9003, 9002 }, 2)
        cycle(f)
        f.expect(staying.backgrounds[3].x, 168, "preview includes the incoming page")
    end

    returning.frame:SetPos(staying.frame.x, staying.frame.y)
    returning.tabs.visible = true
    returning.frame.nativeShown, staying.frame.nativeShown = returningSelected, not returningSelected
    local target = returningSelected and returning or staying
    -- Only the visible copy rebuilds at drop time. The others still have their old strips.
    local finalOrder = dropHeld and { 9001, 9003, 9002 } or { 9001, 9002, 9003 }
    local selected = dropHeld and 3 or returningSelected and 2 or 1
    target:rebuild(finalOrder, selected)
    local leftEdge = dividerAtDrop(f, target, selected)
    if returningSelected then
        staying.frame.visible, hidden.frame.visible = false, false
    end
    target.tabs.clickthrough = false
    f:emit("Logic")
    target.frame:MoveToFront() -- native drop scripts finish between Logic and Draw
    f:emit("Draw")
    checkOwnTab(f, scene, target, panel, 44)
    checkOwnTab(f, scene, target, second, 84)
    checkFivePaintedTabs(f, scene, target)
    f.expect(target.backgrounds[2].x, 124, "second native tab follows both own tabs")
    f.expect(target.backgrounds[3].x, 168, "last native tab keeps its own slot at release")
    assert(panel.root.hidden and second.root.hidden and target.body.visibleGlobal, "native page remains selected")
    if dropHeld then
        local origin = target.tabs.xyGlobal
        local line = scene.paintedAt(scene.area, origin.x + 127, origin.y + 26, id.Sprite.RS3_CHILD_TAB_UNSELECTED)
        f.expect(line, leftEdge, "the old native opening must not leave a slit under the inactive tab")
        local opening = scene.paintedAt(target.backdrop, origin.x + 190, origin.y + 26)
        f.expect(opening, nil, "only the selected native tab has an opening in the divider")
    end

    for index, host in ipairs({ staying, returning, hidden }) do
        if host ~= target then host:rebuild(finalOrder, index) end
    end
    cycle(f)
    checkOwnTab(f, scene, target, panel, 44)
    checkOwnTab(f, scene, target, second, 84)
    f.expect(#f:saved("redock").native.frames, 3, "all pages rejoin when their copies catch up")
    panel:Undock()
    second:Undock()
    f.expect(target.backgrounds[2].x, 44, "undock releases the second tab's displacement")
    f.expect(target.backgrounds[3].x, 88, "undock releases the returning tab's displacement")
end

Fixture.run("redock keeps the resident native page selected", function(f) redock(f, false) end)
Fixture.run("redock selects the returning page before the resident strips rebuild", function(f) redock(f, true) end)
Fixture.run("dropping the held native preview at the end keeps all five tabs", function(f) redock(f, true, true) end)
