local Fixture = require("tests/nis_fixture")
local nativeScene = require("tests/nis_native_fixture")
local rect = Fixture.rect

-- One case per layout shape, not every native window using that shape.
local hosts = {
    { label = "single root", name = "ABILITY_WINDOW_MELEE", frame = 147, owner = 1460, static = 11,
        rootName = "TOPLEVEL_V2_WINDOW_ABILITY_BOOK_MELEE__MAIN_LAYER", width = 112, height = 292 },
    { label = "centered root", name = "LORE_WINDOW", frame = 125, owner = 662, static = 0,
        rootName = "LORE_STATS_SIDE__CONTENT_LAYER", width = 286, height = 292, centered = true, icon = 18787 },
    { label = "compact frame", name = "TELEMETRY_WINDOW", frame = 343, owner = 1588, static = 0,
        rootName = "TELEMETRY__TELEMETRY_WINDOW_CONTENT", width = 129, height = 276, top = 4 },
    { label = "existing tab row", name = "GROUP_LIST_WINDOW", frame = 523, owner = 1519, static = 11,
        rootName = "GROUP_CHILD__BASE", width = 238, height = 264, row = true },
    { label = "listener sibling", name = "PLUGIN_CONTENT_WINDOW", frame = 567, owner = 1604, static = 3,
        rootName = "TOPLEVEL_V2_PLUGIN_CONTENT__MAIN_LAYER", width = 371, height = 337, listener = true },
    { label = "multiple content roots", name = "QUESTLIST_WINDOW", frame = 376, owner = 190, static = 0,
        rootName = "QUESTLIST_V4__LIST_MAIN", width = 371, height = 337, quest = true, icon = 32077 },
}

for index, spec in ipairs(hosts) do
    Fixture.run("native host: " .. spec.label, function(f)
        local scene = nativeScene(f)
        scene.notes.frame.nativeShown = false
        local host = scene.host(spec.frame, spec.name, true, { spec.icon or 50000 + index })
        local tabTop = spec.top or 16
        local bodyTop = spec.row and tabTop + 28 or tabTop
        host.frame:SetSize(spec.width + 8, spec.height + bodyTop + 4)
        host.tabs:SetPos(4, tabTop); host.tabs:SetSize(spec.width, 28)
        host.tabs.visible = spec.row == true
        scene.nodes[(1477 << 16) | (spec.frame + 7)]:SetPos(0, tabTop)
        host.body:SetPos(4, bodyTop); host.body:SetSize(spec.width, spec.height)
        host.scroll:SetPos(4, bodyTop); host.scroll:SetSize(spec.width, spec.height)
        if spec.top then host.scroll:SetPos(0, 0); host.scroll:SetSize(host.frame.width, host.frame.height) end
        local edit = scene.nodes[(1477 << 16) | (spec.frame + 3)]
        edit:SetPos(4, bodyTop); edit:SetSize(spec.width, spec.height)
        local rootY = spec.quest and 30 or 0
        local root = scene.node(spec.owner, spec.static, host.body, 0, rootY, spec.width, spec.height - rootY)
        root:SetSize(0, -rootY, 1, 1)
        local anchor = spec.centered and 0.5 or 0
        root:SetPos(0, rootY, anchor, anchor, anchor, anchor)
        id.Component[spec.rootName] = (spec.owner << 16) | spec.static
        if spec.row then host:rebuild({ 50000 + index, 50100 + index }, 1) end
        local listener, controls, filters
        if spec.listener then
            listener = scene.node(1604, 0, host.body, 0, 0, 1, 1)
            id.Component.TOPLEVEL_V2_PLUGIN_CONTENT__LISTENERS_AND_TIMERS = 1604 << 16
        end
        if spec.quest then
            controls = scene.node(190, 15, host.body, 4, 2, spec.width - 8, 30)
            controls:SetSize(-8, 30, 1, 0)
            filters = scene.node(190, 14, host.body, 4, 32, spec.width - 30, 130)
            filters:SetSize(-30, 130, 1, 0)
            id.Component.QUESTLIST_V4__CONTROLS_LAYER = (190 << 16) | 15
            id.Component.QUESTLIST_V4__CONTROLS_FILTERS_LAYER = (190 << 16) | 14
        end
        local panel = f:panel({ x = 30, y = 450, width = 280, height = 180 })
        if controls then
            local setSize, fail = controls.SetSize, true
            controls.SetSize = function(self, ...)
                setSize(self, ...)
                if fail then fail = false; error("second-root setter failure") end
            end
            assert(not panel:DockTo(host.frame), "partial native writes must roll back")
            controls.SetSize = setSize
            rect(root, 0, 30, 371, 307)
            rect(controls, 4, 2, 363, 30)
        end
        assert(panel:DockTo(host.frame))
        local inset = spec.row and 0 or 28
        rect(root, 0, rootY + inset, spec.width, spec.height - rootY - inset)
        assert(not root.visibleGlobal, "selected own page conceals native content")
        if listener then
            assert(listener.visibleGlobal, "listener siblings must keep running")
            rect(listener, 0, 0, 1, 1)
        end
        if controls then
            rect(controls, 4, 30, 363, 30)
            rect(filters, 4, 60, 341, 130)
        end
        host.body:SetSize(spec.width, spec.height + 24)
        f:emit("Logic")
        rect(root, 0, rootY + inset, spec.width, spec.height + 24 - rootY - inset)
        host.body:SetSize(spec.width, spec.height)
        panel:Undock()
        rect(root, 0, rootY, spec.width, spec.height - rootY)
        assert(root.visibleGlobal and not host.scroll.hidden)
        f.expect(root.position.xParentPc, anchor, "restored parent anchor")
        f.expect(root.position.xSelfPc, anchor, "restored self anchor")
        if controls then
            rect(controls, 4, 2, 363, 30)
            rect(filters, 4, 32, 341, 130)
        end
    end)
end
