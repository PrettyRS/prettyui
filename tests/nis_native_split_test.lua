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

Fixture.run("a two-page nest retains its last native page and restores its standalone content", function(f)
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
    local binding = assert(panel._nisNative)
    local tab = binding.tabs[binding.group.current]
    f.expect(tab.hit.x, scene.notes.frame.x + 4 + 40, "own tab follows the single remaining native tab")
    assert(tab.hit.enabled and not tab.hit.hidden and not scene.ranged.body.hidden)
    f.expect(scene.wrapper.y, 28, "only the surviving standalone page reserves a tab band")
    panel:Undock()
    f.expect(scene.wrapper.y, 0, "undocking returns standalone native content to its original bounds")
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
