local Fixture = require("tests/nis_fixture")
local nativeScene = require("tests/nis_native_fixture")

local function sidebar(f, nativeDock)
    config.Cursor.CURSOR_OPEN = { id = 7 }
    local dock = nativeDock and nativeScene(f)
    local scene = dock or nativeScene(f)
    local top = scene.node(4088, 51, nil, 0, 0, 1200, 800)
    local viewportID = dock and 1477 or 4089
    local viewport = scene.node(viewportID, 52, nil, 0, 0, 1200, 800)
    local area = dock and dock.area or scene.node(4089, 53, viewport, 0, 0, 1200, 800)
    if dock then
        area.parent = viewport
        viewport.children[#viewport.children + 1] = area
        viewport.renderChildren[#viewport.renderChildren + 1] = area
    end
    area:SetSize(0, 0, 1, 1)
    area:SetPos(0, 0, 0.5, 0.5, 0.5, 0.5)
    local view = scene.node(4089, 54, viewport, 0, 0, 1200, 800)
    view:SetSize(0, 0, 1, 1)
    local content = scene.node(4089, 56, view, 0, 0, 1200, 800)
    content:SetSize(0, 0, 1, 1)
    local render = scene.node(4089, 57, content, 0, 0, 1200, 800)
    render:SetSize(0, 0, 1, 1)
    render.visibleGlobal = true
    scene.node(4089, 55, area, 988, 488, 212, 312)
    id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP = (4088 << 16) | 51
    id.Component.TOPLEVEL_V2__VIEWPORT = (viewportID << 16) | 52
    id.Component.TOPLEVEL_V2__GAME_AREA = (area.interfaceID << 16) | area.staticID
    id.Component.TOPLEVEL_V2__GAMEVIEW_WINDOW = (4089 << 16) | 54
    id.Component.TOPLEVEL_V2__GAMEVIEW_WINDOW_CONTENT = (4089 << 16) | 56
    id.Component.TOPLEVEL_V2__RENDER_LAYER = (4089 << 16) | 57
    id.Component.TOPLEVEL_V2__INVENTORY_WINDOW = (4089 << 16) | 55
    f.parent = area
    local function find(node, icon)
        if node.spriteID == icon then return node.parent end
        for _, child in ipairs(node.children) do
            local result = find(child, icon)
            if result then return result end
        end
    end
    local ribbon = require("src/ribbon_bar")
    ribbon.Start()
    return {
        native = dock,
        top = top,
        area = area,
        gameview = view,
        gamecontent = content,
        render = render,
        click = function(panel)
            f.fire(assert(find(top, panel.tabIcon), "missing ribbon button"), ui.Hook.ONCLICK)
        end,
    }
end
local function crop(f, scene, width, description)
    local visible = 1200 - width
    f.expect(scene.gameview.width, visible, description .. " gameview window clips at sidebar")
    f.expect(scene.gameview.size.widthParentPc, 0, description .. " clipped window uses absolute width")
    f.expect(scene.gameview.height, 800, description .. " gameview keeps full height")
    f.expect(scene.gamecontent.parent, scene.gameview, description .. " content belongs to gameview")
    f.expect(scene.gamecontent.width, visible, description .. " content fills window")
    f.expect(scene.gamecontent.size.widthParentPc, 1, description .. " content retains fill descriptor")
    f.expect(scene.render.parent, scene.gamecontent, description .. " render belongs to content")
    f.expect(scene.render.visibleGlobal, true, description .. " render remains visible")
    f.expect(scene.render.width, 1200, description .. " render keeps full viewport width")
    f.expect(scene.render.height, 800, description .. " render keeps full height")
    f.expect(scene.render.size.widthParentPc, 0, description .. " render width is absolute")
    f.expect(scene.render.x, -math.floor(width / 2), description .. " native viewport remains centered")
end

Fixture.run("Classic sidebar clicks mount one page, collapse without disabling, and release content", function(f)
    local scene = sidebar(f)
    f.classicMode.value = 1
    require("src/settings").set("allowClassicMovement", true)
    f:lock(true)
    local builds, cleanups = 0, 0
    local function content(owner)
        builds = builds + 1
        owner:AddText("Page")
        return function() cleanups = cleanups + 1 end
    end
    local a = f:panel({ tabIcon = 830001, contentHeight = 1200, buildContent = content })
    local b = f:panel({ tabIcon = 830002, buildContent = content })
    assert(a.content == nil and b.content == nil and builds == 0)
    f.expect(scene.area.width, 1156, "collapsed rail reserves native space")
    crop(f, scene, 44, "cold-start collapsed rail")
    scene.click(a)
    f.expect(scene.area.width, 856, "expanded page reserves native space")
    crop(f, scene, 344, "expanded page")
    assert(a.content.interfaceID == scene.top.interfaceID and a.root.hidden)
    a:SetScrollPosition(64)
    scene.click(b)
    assert(a.content == nil and b.content ~= nil and cleanups == 1)
    scene.click(a)
    f.expect(a.scrollY, 64, "sidebar selection restores scroll offset")
    scene.click(a)
    assert(a.content == nil and a:IsActive(), "collapse is not deactivation")
    f.expect(scene.area.width, 1156, "collapse restores rail-only reservation")
    crop(f, scene, 44, "collapsed page")
    a:Destroy()
    b:Destroy()
    f.expect(scene.area.width, 1200, "last panel releases native reservation")
    f.expect(scene.gameview.width, 1200, "last panel restores full native gameview")
    f.expect(scene.render.position.x, 0, "last panel restores render origin")
    f.expect(scene.render.size.widthParentPc, 1, "last panel restores native render descriptor")
    f.expect(builds, cleanups, "every mounted page is cleaned up")
end)

Fixture.run("live Modern to Classic transition delays only native crop for ten logic ticks", function(f)
    local scene = sidebar(f)
    local panel = f:panel({ tabIcon = 830004 })
    f.classicMode.value = 1
    f:emit("VarTransmit", { var = { id = id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP } })
    f.expect(scene.area.width, 1156, "Classic HUD rail reserves space immediately")
    f.expect(scene.gameview.width, 1200, "mode notification does not crop outgoing Modern gameview")
    for _ = 1, 9 do
        f:emit("VarTransmit", { var = { id = id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP } })
        f:emit("Logic")
    end
    f.expect(scene.area.width, 1156, "nine ticks retain immediate HUD reservation")
    f.expect(scene.gameview.width, 1200, "extra var events never count as logic ticks")
    f.expect(scene.render.size.widthParentPc, 1, "render stays native during transition")
    f:emit("Logic")
    crop(f, scene, 44, "live transition collapsed rail")
    scene.click(panel)
    f.expect(scene.area.width, 856, "expanded rail reserves full HUD width")
    crop(f, scene, 344, "live transition expanded page")
    f.classicMode.value = 0
    f:emit("VarTransmit", { var = { id = id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP } })
    f.expect(scene.gameview.width, 1200, "mode exit restores native window")
    f.expect(scene.render.position.x, 0, "mode exit restores render origin")
    f.expect(scene.render.size.widthParentPc, 1, "mode exit restores render width")
end)

Fixture.run("mode round trip preserves modern grouping, selection, bounds and ribbon preferences", function(f)
    local scene = sidebar(f)
    local settings = require("src/settings")
    settings.set("ribbonBarPosition", "top")
    settings.set("ribbonBarAutoHide", true)
    local a = f:panel({ id = "a", tabIcon = 830001 })
    local b = f:panel({ id = "b", x = 500, width = 300, height = 260, tabIcon = 830002 })
    assert(a:DockTo(b))
    b:SelectTab()
    local groupID = f:saved("a").group
    scene.gameview:SetSize(1000, 0, 0, 1)
    f.classicMode.value = 1
    f:emit("VarTransmit", { var = { id = id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP } })
    for _ = 1, 9 do
        f:emit("VarTransmit", { var = { id = id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP } })
        f:emit("Logic")
    end
    f.expect(scene.gameview.width, 1000, "repeated var events do not accelerate native crop")
    f:emit("Logic")
    assert(a.content == nil and b.content == nil, "mode entry starts collapsed")
    f.expect(scene.gameview.width, 1000, "collapsed rail leaves existing gameview inset alone")
    scene.click(a)
    assert(a.content ~= nil and a.root.hidden)
    crop(f, scene, 344, "overlapping fixed-width view")
    scene.click(a)
    f.expect(scene.gameview.width, 1000, "collapse restores exact native fixed width")
    f.expect(scene.gameview.size.width, 1000, "collapse restores fixed-width descriptor")
    f.expect(scene.gameview.size.widthParentPc, 0, "collapse restores native width anchor")
    f.expect(scene.render.position.x, 0, "collapse restores native render origin")
    f.expect(scene.render.size.widthParentPc, 1, "collapse restores native render sizing")
    scene.click(a)
    crop(f, scene, 344, "fixed-width page reopened")
    assert(f:saved("a").group == groupID, "Classic selection must not rewrite modern membership")
    f.classicMode.value = 0
    f:emit("VarTransmit", { var = { id = id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP } })
    f:emit("Logic")
    assert(a._nisGroup == b._nisGroup and a._nisGroup.active == b)
    assert(a.content == nil and b.content ~= nil)
    Fixture.rect(b.root, 500, 100, 300, 260)
    f.expect(scene.area.width, 1200, "mode exit returns native space")
    f.expect(scene.render.position.x, 0, "mode exit restores render origin")
    f.expect(scene.render.size.widthParentPc, 1, "mode exit restores native render sizing")
    f.expect(scene.gameview.width, 1000, "mode exit restores the native fixed-width view")
    f.expect(settings.get("ribbonBarPosition"), "top", "modern edge preference")
    f.expect(settings.get("ribbonBarAutoHide"), true, "modern auto-hide preference")
end)

Fixture.run("fixed-width gameview that fits beside the expanded sidebar is untouched", function(f)
    local scene = sidebar(f)
    scene.gameview:SetSize(800, 0, 0, 1)
    f.classicMode.value = 1
    local panel = f:panel({ tabIcon = 830003 })
    f.expect(scene.gameview.width, 800, "collapsed rail does not resize fitting gameview")
    scene.click(panel)
    f.expect(scene.gameview.width, 800, "expanded sidebar does not resize fitting gameview")
    f.expect(scene.gameview.size.width, 800, "fixed native window descriptor remains unchanged")
    f.expect(scene.render.size.widthParentPc, 1, "fitting view retains native render descriptor")
    f.expect(scene.render.position.x, 0, "fitting view retains native render origin")
end)

Fixture.run("panels without geometry choose modern placement after leaving Classic", function(f)
    local scene = sidebar(f)
    f.classicMode.value = 1
    local panel = f.NisPanel.new(f.parent, { id = "default", tabIcon = 830011 })
    f.panels[#f.panels + 1] = panel
    scene.click(panel)
    assert(panel.content ~= nil and panel.root.hidden)
    require("src/settings").set("ribbonBarPosition", "right")
    f.classicMode.value = 0
    f:emit("VarTransmit", { var = { id = id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP } })
    f:emit("Logic")
    Fixture.rect(panel.root, 850, 200, 300, 400)
    assert(panel.content ~= nil and not panel.root.hidden)
end)

Fixture.run(
    "native-docked panels round trip in order without rebuilding hidden pages or repeating group presentation",
    function(f)
        local scene = sidebar(f, true)
        local builds = { 0, 0, 0 }
        local function content(index)
            return function(owner)
                builds[index] = builds[index] + 1
                owner:AddText("Page")
            end
        end
        local a = f:panel({ id = "native-a", tabIcon = 830021, buildContent = content(1) })
        local b = f:panel({ id = "native-b", tabIcon = 830022, buildContent = content(2) })
        local c = f:panel({ id = "native-c", tabIcon = 830023, buildContent = content(3) })
        assert(a:DockTo(scene.native.notes.frame) and b:DockTo(a) and c:DockTo(b))
        b:SelectTab()
        local panels = { a, b, c }
        local group = b._nisNative.group
        assert(group.members[1] == a and group.members[2] == b and group.members[3] == c and group.active == b)

        f.classicMode.value = 1
        f:emit("VarTransmit", { var = { id = id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP } })
        for index, panel in ipairs(panels) do
            assert(panel._nisNative == nil and panel._nisClassicState.native, "Classic suspends native membership")
            f.expect(panel._nisClassicState.native.index, index, "Classic snapshots original native tab order")
            f.expect(panel._nisClassicState.native.selected, panel == b, "Classic snapshots middle selection")
        end
        local before = { table.unpack(builds) }
        f.classicMode.value = 0
        f:emit("VarTransmit", { var = { id = id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP } })
        for _ = 1, 9 do
            f:emit("Logic")
        end
        assert(a._nisNativePending and b._nisNativePending and c._nisNativePending)
        f.expect(builds[1], before[1], "unselected first page is not built as a transient standalone")
        f.expect(builds[3], before[3], "unselected last page is not built as a transient standalone")
        f.expect(builds[2], before[2], "selected page waits for the native host instead of building transiently")

        local raises = 0
        local moveToFront = b.root.MoveToFront
        b.root.MoveToFront = function(root)
            raises = raises + 1
            return moveToFront(root)
        end
        f:emit("Logic")
        group = b._nisNative and b._nisNative.group
        assert(group and a._nisNative.group == group and c._nisNative.group == group, "all pages rejoin the host")
        assert(group.members[1] == a and group.members[2] == b and group.members[3] == c, "native order survives")
        assert(
            group.active == b and b.content ~= nil and a.content == nil and c.content == nil,
            "middle page remains selected"
        )
        assert(raises <= 2, "restoration presents the selected native group once, not once per member")
        f.expect(builds[1], before[1], "hidden first page remains unbuilt after native restore")
        f.expect(builds[3], before[3], "hidden last page remains unbuilt after native restore")
        f.expect(builds[2], before[2] + 1, "selected page is built once on native restore")
        for _ = 1, 3 do
            f:emit("Logic")
        end
        f.expect(builds[1], before[1], "idle native ticks do not rebuild the first hidden page")
        f.expect(builds[3], before[3], "idle native ticks do not rebuild the last hidden page")
    end
)

Fixture.run("missing native host keeps a usable page at the due tick and redocks when it returns", function(f)
    local scene = sidebar(f, true)
    local panel = f:panel({ id = "late-native", tabIcon = 830024 })
    assert(panel:DockTo(scene.native.notes.frame))
    f.classicMode.value = 1
    f:emit("VarTransmit", { var = { id = id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP } })
    scene.native.notes.frame.nativeShown = false
    f.classicMode.value = 0
    f:emit("VarTransmit", { var = { id = id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP } })
    for _ = 1, 10 do
        f:emit("Logic")
    end
    assert(panel._nisNative == nil and panel._nisNativePending, "missing native host remains queued")
    assert(panel.content ~= nil and not panel.root.hidden, "failed redock retains usable standalone content")
    scene.native.notes.frame.nativeShown = true
    f:emit("Logic")
    assert(
        panel._nisNative and panel._nisNative.group.active == panel and panel.content ~= nil,
        "late native host restores membership and selected content"
    )
end)

Fixture.run("classic round trip restores directly into a smaller native host", function(f)
    local scene = sidebar(f, true)
    local panel = f:panel({ id = "resized-native", minHeight = 200, tabIcon = 830025 })
    assert(panel:DockTo(scene.native.notes.frame))
    f.classicMode.value = 1
    f:emit("VarTransmit", { var = { id = id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP } })
    scene.native.notes.body:SetSize(371, 100)
    f.classicMode.value = 0
    f:emit("VarTransmit", { var = { id = id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP } })
    for _ = 1, 10 do
        f:emit("Logic")
    end
    local binding = assert(panel._nisNative, "restore must not wait for the native host to grow")
    assert(binding.group.active == panel and panel.content and panel.root.height == 100)
    scene.native.notes.body:SetSize(371, 309)
    f:emit("Logic")
    assert(panel._nisNative == binding and panel.root.height == 309, "reflow resizes the same docked page")
end)
