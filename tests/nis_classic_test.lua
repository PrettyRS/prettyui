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
    id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP = (4088 << 16) | 51
    id.Component.TOPLEVEL_V2__VIEWPORT = (4089 << 16) | 52
    id.Component.TOPLEVEL_V2__GAME_AREA = (4089 << 16) | 53
    id.Component.TOPLEVEL_V2__GAMEVIEW_WINDOW = (4089 << 16) | 54
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
        top = top, area = area, ribbon = ribbon,
        click = function(panel)
            f.fire(assert(find(top, panel.tabIcon), "missing ribbon button"), ui.Hook.ONCLICK)
        end,
    }
end

Fixture.run("Classic sidebar clicks mount one page, collapse without disabling, and release content", function(f)
    local scene = sidebar(f)
    f.classicMode.value = 1
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
    scene.click(a)
    f.expect(scene.area.width, 796, "expanded page reserves native space")
    assert(a.content.interfaceID == scene.top.interfaceID and a.root.hidden)
    a:SetScrollPosition(64)
    scene.click(b)
    assert(a.content == nil and b.content ~= nil and cleanups == 1)
    scene.click(a)
    f.expect(a.scrollY, 64, "sidebar selection restores scroll offset")
    scene.click(a)
    assert(a.content == nil and a:IsActive(), "collapse is not deactivation")
    f.expect(scene.area.width, 1156, "collapse restores rail-only reservation")
    a:Destroy(); b:Destroy()
    f.expect(scene.area.width, 1200, "last panel releases native reservation")
    f.expect(builds, cleanups, "every mounted page is cleaned up")
end)

Fixture.run("mode round trip preserves modern grouping, selection, bounds and ribbon preferences", function(f)
    local scene = sidebar(f)
    scene.ribbon.SetPosition("top")
    scene.ribbon.SetAutoHide(true)
    local a = f:panel({ id = "a", tabIcon = 830001 })
    local b = f:panel({ id = "b", x = 500, width = 300, height = 260, tabIcon = 830002 })
    assert(a:DockTo(b))
    b:SelectTab()
    local groupID = f:saved("a").group
    f.classicMode.value = 1
    f:emit("VarTransmit", { var = { id = id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP } })
    f:emit("Logic")
    assert(a.content == nil and b.content == nil, "mode entry starts collapsed")
    scene.click(a)
    assert(a.content ~= nil and a.root.hidden)
    assert(f:saved("a").group == groupID, "Classic selection must not rewrite modern membership")
    f.classicMode.value = 0
    f:emit("VarTransmit", { var = { id = id.VarPlayer.TOPLEVEL_V2_GENERAL_VARP } })
    f:emit("Logic")
    assert(a._nisGroup == b._nisGroup and a._nisGroup.active == b)
    assert(a.content == nil and b.content ~= nil)
    Fixture.rect(b.root, 500, 100, 300, 260)
    f.expect(scene.area.width, 1200, "mode exit returns native space")
    f.expect(scene.ribbon.GetPosition(), "top", "modern edge preference")
    f.expect(scene.ribbon.GetAutoHide(), true, "modern auto-hide preference")
end)
