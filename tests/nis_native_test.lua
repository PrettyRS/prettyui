local Fixture = require("tests/nis_fixture")
local nativeScene = require("tests/nis_native_fixture")
local run, rect = Fixture.run, Fixture.rect

local function nativeClick(f, component)
    local delivered = false
    for _, callback in pairs(component.namedSubscriptions[ui.Hook.ONCLICK] or {}) do
        delivered = true
        assert(callback(component, 10, 10), "observer must preserve native click handling")
    end
    assert(delivered, "native tab must remain selectable")
    f:emit("Logic")
    f:emit("Draw")
end

local function tab(panel)
    return panel._nisNative.tabs[panel._nisNative.group.current]
end

local function reorder(f, panel, x, commit)
    local hit = tab(panel).hit
    local pointer = { x = hit.xyGlobal.x + 12, y = hit.xyGlobal.y + 12 }
    Mouse.GetPosition = function() return pointer end
    f.fire(hit, ui.Hook.ONCLICK, 12, 12)
    pointer.x = f.parent.xyGlobal.x + x
    f.fire(hit, ui.Hook.ONHOLD, 12, 12)
    if commit then
        f.fire(hit, ui.Hook.ONRELEASE)
    else
        f:emit("KeyDown", { gameKey = GameKey.ESCAPE })
    end
    Mouse.GetPosition = function() return nil end
end

run("idle nesting leaves unrelated rows alone and follows same-ID input replacements", function(f)
    local scene = nativeScene(f)
    local panel = f:panel()
    assert(panel:DockTo(scene.notes.frame))
    nativeClick(f, scene.notes.backgrounds[1])
    local scans = 0
    local iterate = scene.magic.tabs.IterateDynamicComponents
    scene.magic.tabs.IterateDynamicComponents = function(tabs, callback)
        scans = scans + 1
        return iterate(tabs, callback)
    end
    for _ = 1, 12 do
        f:emit("Logic")
        f:emit("Draw")
    end
    f.expect(scans, 0, "an unrelated window is not walked to maintain an unchanged nest")
    scene.notes:rebuild({ 9001, 9002 }, 1)
    f:emit("Logic")
    nativeClick(f, scene.notes.backgrounds[1])
    panel:SelectTab()
    assert(not panel.root.hidden and scene.notes.body.hidden, "both pages remain selectable after the idle rebuild")
end)

for _, grouped in ipairs({ true, false }) do
    for _, ownPage in ipairs({ true, false }) do
        local kind = grouped and "grouped" or "standalone"
        local page = ownPage and "PrettyUI" or "native"
        run("settled " .. kind .. " " .. page .. " page avoids full native alignment each Logic", function(f)
            local scene = nativeScene(f)
            if not grouped then
                scene.notes.tabs.visible = false
            end
            local panel = f:panel()
            assert(panel:DockTo(scene.notes.frame))
            local group = panel._nisNative.group
            if not ownPage then
                if grouped then
                    nativeClick(f, scene.notes.backgrounds[1])
                else
                    f.fire(group.hosts[group.current].nativeTab.hit, ui.Hook.ONCLICK, 10, 10)
                end
            end
            f:emit("Logic")
            f:emit("Draw")
            local alignments = 0
            for _, host in ipairs(group.hosts) do
                local layout = host.overflow.Layout
                host.overflow.Layout = function(view, ...)
                    alignments = alignments + 1
                    return layout(view, ...)
                end
            end
            for _ = 1, 8 do
                f:emit("Logic")
            end
            assert(alignments <= #group.hosts * 2, "idle Logic must not fully align the native group every tick")
            assert(panel._nisNative.group == group and panel.root.hidden == not ownPage)
            scene.notes.frame:SetPos(520, 120)
            f:emit("Logic")
            f.expect(group.hosts[group.current].chrome.x, 520, "frame motion wakes native alignment on first Logic")
            scene.notes.body:SetSize(400, scene.notes.body.height)
            f:emit("Logic")
            f.expect(panel.root.width, 400, "content resize wakes native alignment on first Logic")
        end)
    end
end

run("same-ID native input replacement rebinds on first Logic and repaint on Draw", function(f)
    local scene = nativeScene(f)
    local panel = f:panel()
    assert(panel:DockTo(scene.notes.frame))
    local binding = panel._nisNative
    f:emit("Logic")
    f:emit("Draw")
    local retired = scene.notes.backgrounds[1]
    scene.notes:rebuild({ 9001, 9002 }, 1)
    f:emit("Logic")
    local replacement = scene.notes.backgrounds[1]
    assert(retired.destroyed and replacement ~= retired)
    f.expect(
        binding.group.hosts[binding.group.current].children[1],
        replacement,
        "the first Logic adopts the new native input handle"
    )
    assert(
        replacement.namedSubscriptions[ui.Hook.ONCLICK]
            and replacement.namedSubscriptions[ui.Hook.ONCLICK][binding.group.hookID],
        "replacement receives the native click observer before another Draw"
    )
    nativeClick(f, replacement)
    panel:SelectTab()
    scene.notes:rebuild({ 9001, 9002 }, 1)
    replacement = scene.notes.backgrounds[1]
    f:emit("Draw")
    f.expect(
        binding.group.hosts[binding.group.current].children[1],
        replacement,
        "a native repaint after Logic adopts replacement inputs before paint"
    )
    nativeClick(f, replacement)
    panel:SelectTab()
    assert(panel._nisNative == binding and not panel.root.hidden)
end)

run("native preview cancels cleanly; docking retains content and undocking restores bounds", function(f)
    local scene = nativeScene(f)
    local panel = f:panel({
        x = 50,
        y = 450,
        width = 280,
        height = 180,
        tabIcon = Plugin.resources.image,
        buildContent = function(owner) owner:AddTitle("Page") end,
    })
    local content = panel.content
    f:begin(panel)
    f:move(panel, 650, 130)
    f:emit("Draw")
    assert(
        panel.root.hidden and not scene.notes.body.hidden and panel._nisNative == nil,
        "native dock preview persists when Draw precedes the next Logic"
    )
    f:emit("KeyDown", { gameKey = GameKey.ESCAPE })
    assert(not panel.root.hidden and panel.content == content)
    f:begin(panel)
    f:move(panel, 650, 130)
    f:release(panel)
    assert(panel._nisNative and panel.content == content and scene.notes.body.hidden)
    f.expect(tab(panel).artwork.children[2].runtimeSprite.resource, Plugin.resources.image, "custom native icon")
    scene.notes.frame:SetPos(520, 120)
    f:emit("Logic")
    rect(panel.root, 524, 164, 371, 309)
    nativeClick(f, scene.notes.tabs)
    assert(panel.content == nil and not scene.notes.body.hidden)
    panel:SelectTab()
    assert(panel.content ~= content and panel.content ~= nil and scene.notes.body.hidden)
    panel:Undock()
    rect(panel.root, 50, 450, 280, 180)
    assert(not scene.notes.body.hidden, "undock returns native content")
end)

run("failed native hook registration rolls back and allows a later dock", function(f)
    local scene = nativeScene(f)
    local panel = f:panel()
    local subscribe = scene.notes.tabs.Subscribe
    function scene.notes.tabs:Subscribe(hook, name, callback)
        if hook == ui.Hook.ONDRAG then error("registration failure") end
        return subscribe(self, hook, name, callback)
    end
    assert(not panel:DockTo(scene.notes.frame))
    assert(panel._nisNative == nil and not scene.notes.body.hidden)
    rect(panel.root, 100, 100, 300, 200)
    scene.notes.tabs.Subscribe = subscribe
    assert(panel:DockTo(scene.notes.frame), "rollback must release ownership for a later attempt")
end)

run("mixed tab reorder preserves native hit targets and restores borrowed positions", function(f)
    local scene = nativeScene(f)
    local nativeHit = f.component(scene.notes.tabs, "native input", 0, 20)
    nativeHit:SetPos(0, 0)
    nativeHit:SetSize(44, 28)
    nativeHit.clickthrough = false
    local clicks = 0
    nativeHit:Subscribe(ui.Hook.ONCLICK, function(self)
        clicks = clicks + 1
        nativeClick(f, self)
    end)
    local panel = f:panel({ id = "mixed" })
    assert(panel:DockTo(scene.notes.frame))
    reorder(f, panel, 516, false)
    f.expect(scene.notes.backgrounds[1].x, 0, "cancel restores native row")
    reorder(f, panel, 516, true)
    f.expect(scene.notes.backgrounds[1].x, 40, "own tab precedes first native tab")
    f.expect(nativeHit.x, 40, "native input moves with its artwork")
    f.expect(f:saved("mixed").native.beforeNative, 0, "committed insertion is saved")
    local hit = f.hitAt(scene.area, 556, 128)
    f.expect(hit, nativeHit, "shifted native hit remains reachable")
    f.fire(hit, ui.Hook.ONCLICK, 12, 12)
    assert(clicks == 1 and panel.root.hidden)
    panel:SelectTab()
    panel:Undock()
    f.expect(nativeHit.x, 0, "undock restores native input")
    f.expect(scene.notes.backgrounds[2].x, 44, "undock restores original native spacing")
end)

run("native rebuilds and lock changes retain membership, selection and tab painting", function(f)
    local scene = nativeScene(f)
    local panel = f:panel({ tabIcon = Plugin.resources.image })
    assert(panel:DockTo(scene.notes.frame))
    local binding, content = panel._nisNative, panel.content
    require("src/settings").set("respectInterfaceLock", false)
    f:lock(true)
    scene.notes:rebuild({ 9001, 9002 }, 1)
    scene.ranged:rebuild({ 9001, 9002 }, 2)
    f:emit("Logic")
    f:emit("Draw")
    assert(panel._nisNative == binding and panel.content == content)
    local ownTab = tab(panel)
    local point = ownTab.visual.xyGlobal
    f.expect(
        scene.paintedAt(scene.area, point.x + 2, point.y + 12),
        ownTab.background,
        "tab background must paint above the strip fill"
    )
    f.expect(
        f.hitAt(scene.area, ownTab.hit.x + 2, ownTab.hit.y + 12),
        ownTab.hit,
        "painted tab and hit target remain aligned"
    )
    nativeClick(f, scene.notes.backgrounds[1])
    assert(panel.root.hidden)
    panel:SelectTab()
    assert(not panel.root.hidden)
    ownTab = tab(panel)
    f.fire(ownTab.hit, ui.Hook.ONCLICK, 10, 10)
    f.fire(ownTab.hit, ui.Hook.ONHOLD, 200 - ownTab.hit.x, 450 - ownTab.hit.y)
    f.fire(ownTab.hit, ui.Hook.ONRELEASE)
    assert(panel._nisNative == binding and panel.dragState == nil, "locked tab must not tear out")
    f:lock(false)
    f.expect(
        tab(panel).artwork.children[2].runtimeSprite.resource,
        Plugin.resources.image,
        "custom icon survives replacement native children"
    )
end)

run("overflow scrolls the mixed row without changing selection and restores native scroll state", function(f)
    local scene = nativeScene(f)
    for _, host in ipairs({ scene.notes, scene.ranged }) do
        host.frame:SetSize(88, host.frame.height)
        host.body:SetSize(80, host.body.height)
        host.scroll:SetSize(80, host.scroll.height)
        host.tabs:SetPos(15, host.tabs.y)
        host.tabs:SetSize(58, 28)
        host.tabs:SetScrollSize(88, 28)
        host.tabs:SetScrollPos(30, 0)
        host.tabControls:SetSize(80, 28)
    end
    local panel = f:panel()
    assert(panel:DockTo(scene.notes.frame))
    local group = panel._nisNative.group
    local host = group.hosts[group.current]
    local overflow = host.overflow
    assert(not tab(panel).hit.hidden, "joining reveals the selected overflowing tab")
    f.expect(host.tabs.scrollWidth, 128, "scroll extent includes the own tab")
    for _ = 1, 6 do
        f.fire(overflow.leftHit, ui.Hook.ONCLICK)
    end
    assert(group.tabScroll == 0 and group.active == panel)
    assert(tab(panel).hit.hidden, "offscreen tab must not intercept native clicks")
    f:lock(true)
    for _ = 1, 6 do
        f.fire(overflow.rightHit, ui.Hook.ONCLICK)
    end
    assert(not overflow.rightHit.enabled and not tab(panel).hit.hidden)
    panel:Undock()
    for _, restored in ipairs({ scene.notes, scene.ranged }) do
        f.expect(restored.tabs.x, 15, "original native viewport origin")
        f.expect(restored.tabs.width, 58, "original native viewport width")
        f.expect(restored.tabs.scrollWidth, 88, "original native scroll extent")
        f.expect(restored.tabs.scrollX, 30, "original native scroll position")
        assert(not restored.tabControls.hidden)
    end
end)

run("native membership waits for a late host and restores reverse-loaded selection", function(f)
    local scene = nativeScene(f)
    local a = f:panel({ id = "a" })
    local b = f:panel({ id = "b" })
    assert(a:DockTo(scene.notes.frame) and b:DockTo(a))
    a:SelectTab()
    b:Destroy()
    a:Destroy()
    f:restart()
    f:lock(true)
    scene.notes.frame.visible = false
    b = f:panel({ id = "b" })
    assert(b._nisNative == nil and not b.root.hidden, "missing native host leaves usable standalone content")
    scene.notes.frame.visible = true
    f:emit("Logic")
    assert(b._nisNative and b._nisNative.group.active == nil, "missing selected plugin does not steal native focus")
    a = f:panel({ id = "a" })
    local group = a._nisNative.group
    assert(group.members[1] == a and group.members[2] == b and group.active == a)
    b:Hide()
    a:Undock()
    a:Destroy()
    b:Destroy()
    f:restart()
    a = f:panel({ id = "a" })
    b = f:panel({ id = "b" })
    assert(a._nisNative == nil and not b:IsActive())
    b:Show()
    assert(b._nisNative and b._nisNative.group.active == b, "reopening restores remembered native host")
end)

run("HUD suppression and transmog hide input without losing placement or native membership", function(f)
    local scene = nativeScene(f)
    local hud = scene.node(1477, 199, scene.area, 0, 0, 1000, 700)
    id.Component.TOPLEVEL_V2__GAMEPLAY_HUDS = (1477 << 16) | 199
    local unmorph = scene.node(1633, 0, nil, 0, 0, 100, 30)
    id.Component.TRH61_UNMORPH__BUTTON_LAYER = 1633 << 16
    unmorph.nativeShown = false
    local standalone = f:panel({ x = 140, y = 440, width = 220, height = 140, contentHeight = 400 })
    local docked = f:panel()
    assert(docked:DockTo(scene.notes.frame))
    local binding, content = docked._nisNative, standalone.content
    standalone:SetScrollPosition(64)
    hud.nativeShown = false
    f:emit("Logic")
    assert(standalone.root.hidden and docked.root.hidden)
    hud.nativeShown = true
    f:emit("Logic")
    f:emit("Logic")
    assert(not standalone.root.hidden and docked._nisNative == binding)
    unmorph.nativeShown = true
    scene.notes.frame.nativeShown = false
    f:emit("Logic")
    f:emit("Logic")
    standalone:Show()
    assert(standalone.root.hidden and standalone.dragLayer.hidden and standalone._scroll.thumbDrag.hidden)
    assert(docked.root.hidden and docked._nisNative == binding)
    local late = f:panel()
    assert(late.root.hidden and late.content == nil)
    unmorph.nativeShown = false
    scene.notes.frame.nativeShown = true
    f:emit("Logic")
    f:emit("Logic")
    assert(not standalone.root.hidden and not docked.root.hidden and late.content ~= nil)
    assert(standalone.content == content and standalone.scrollY == 64)
    rect(standalone.root, 140, 440, 220, 140)
    local header = f.hitAt(scene.area, 250, 446)
    f.expect(header, standalone.dragLayer, "restored header stays above body input")
    f.fire(header, ui.Hook.ONCLICK, 110, 6)
    f.fire(header, ui.Hook.ONHOLD, 140, 26)
    f.fire(header, ui.Hook.ONRELEASE)
    rect(standalone.root, 170, 460, 220, 140)
end)

run("unloading a native host does not touch stale components during cleanup", function(f)
    local scene = nativeScene(f)
    local panel = f:panel()
    assert(panel:DockTo(scene.notes.frame))
    f.Interfaces.unload(1477)
    f:emit("Logic")
    panel:Destroy()
    assert(panel.root == nil)
end)

run("native sorting can rebuild the row mid-drag without ejecting the own page", function(f)
    local scene = nativeScene(f)
    local panel = f:panel()
    assert(panel:DockTo(scene.notes.frame))
    reorder(f, panel, 560, true)
    local binding = panel._nisNative
    local source = scene.notes.backgrounds[2]
    local function hook(kind, ...)
        for _, callback in pairs(source.namedSubscriptions[kind] or {}) do
            assert(callback(source, ...), "native sort observer preserves client handling")
        end
    end
    nativeClick(f, source)
    hook(ui.Hook.ONDRAG, 12, 12)
    source:SetPos(-12, 0)
    f:emit("Draw")
    assert(
        panel._nisNative == binding and source.x == -12 and not tab(panel).hit.enabled,
        "Draw updates native drag preview without moving the client's captured source"
    )
    f:emit("Logic")
    assert(panel._nisNative == binding and source.x == -12, "mixed layout must not fight the native drag")
    assert(not tab(panel).hit.enabled, "own tab cannot steal native drag capture")
    scene.notes:rebuild({ 9002, 9001 }, 2)
    f:emit("Draw")
    assert(
        panel._nisNative == binding and not tab(panel).hit.enabled,
        "same-ID native sort repaint keeps client capture through Draw"
    )
    f:emit("Logic")
    hook(ui.Hook.ONRELEASE, 12, 12)
    scene.ranged:rebuild({ 9002, 9001 }, 1)
    for _ = 1, 3 do
        f:emit("Logic")
    end
    assert(panel._nisNative == binding, "replacement row retains native membership")
    panel:SelectTab()
    assert(not panel.root.hidden, "own page remains selectable after native sorting")
end)

run("world-map suspension keeps native membership and restores the selected page", function(f)
    local scene = nativeScene(f)
    local focus = { configName = "WORLDMAP_FOCUS", value = -1 }
    var.VarClient = { WORLDMAP_FOCUS = focus }
    local panel = f:panel()
    assert(panel:DockTo(scene.notes.frame))
    local binding = panel._nisNative
    focus.value = 0
    f:emit("VarTransmit", { var = focus, newValue = 0 })
    f:emit("Logic")
    assert(panel.root.hidden and panel._nisNative == binding)
    focus.value = -1
    f:emit("VarTransmit", { var = focus, newValue = -1 })
    f:emit("Logic")
    f:emit("Logic")
    assert(not panel.root.hidden and panel._nisNative == binding)
end)
