local Fixture = require("tests/nis_fixture")
local nativeScene = require("tests/nis_native_fixture")

local function sidebar(f)
    config.Cursor.CURSOR_OPEN = { id = 7 }
    local scene = nativeScene(f)
    local top = scene.node(4088, 51, nil, 0, 0, 1200, 800)
    local viewport = scene.node(4089, 52, nil, 0, 0, 1200, 800)
    local area = scene.node(4089, 53, viewport, 0, 0, 1200, 800)
    area:SetSize(0, 0, 1, 1); area:SetPos(0, 0, .5, .5, .5, .5)
    local view = scene.node(4089, 54, viewport, 0, 0, 1200, 800)
    view:SetSize(0, 0, 1, 1)
    local content = scene.node(4089, 56, view, 0, 0, 1200, 800)
    content:SetSize(0, 0, 1, 1)
    local render = scene.node(4089, 57, content, 0, 0, 1200, 800)
    render:SetSize(0, 0, 1, 1)
    render.visibleGlobal = true
    scene.node(4089, 55, area, 988, 488, 212, 312)
    id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP = (4088 << 16) | 51
    id.Component.TOPLEVEL_V2__VIEWPORT = (4089 << 16) | 52
    id.Component.TOPLEVEL_V2__GAME_AREA = (4089 << 16) | 53
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
        top = top, area = area, gameview = view, gamecontent = content, render = render,
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
    crop(f, scene, 44, "collapsed rail")
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
    a:Destroy(); b:Destroy()
    f.expect(scene.area.width, 1200, "last panel releases native reservation")
    f.expect(scene.gameview.width, 1200, "last panel restores full native gameview")
    f.expect(scene.render.position.x, 0, "last panel restores render origin")
    f.expect(scene.render.size.widthParentPc, 1, "last panel restores native render descriptor")
    f.expect(builds, cleanups, "every mounted page is cleaned up")
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
    for _ = 1, 10 do f:emit("Logic") end
    assert(a.content == nil and b.content == nil, "mode entry starts collapsed")
    f.expect(scene.gameview.width, 1000, "collapsed rail leaves existing gameview inset alone")
    scene.click(a)
    assert(a.content ~= nil and a.root.hidden)
    crop(f, scene, 344, "overlapping fixed-width view")
    scene.click(a)
    f.expect(scene.gameview.width, 1000, "collapse restores the exact fixed-width gameview")
    f.expect(scene.gameview.size.width, 1000, "collapse restores fixed-width native descriptor")
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
    f.expect(scene.gameview.width, 1000, "mode exit leaves the native fixed-width view alone")
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
