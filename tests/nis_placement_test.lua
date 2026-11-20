local Fixture = require("tests/nis_fixture")
local nativeScene = require("tests/nis_native_fixture")
local run, rect = Fixture.run, Fixture.rect

run("header drag fits native gaps only on commit", function(f)
    local scene = nativeScene(f)
    local left = scene.node(1477, 100, scene.area, 0, 300, 400, 400)
    local right = scene.node(1477, 101, scene.area, 520, 300, 480, 400)
    function scene.area.IterateStaticComponents(_, callback)
        callback(left)
        callback(right)
    end
    local panel = f:panel()
    f:begin(panel)
    f:release(panel)
    rect(panel.root, 100, 100, 300, 200)
    f:begin(panel)
    f:move(panel, 460, 450)
    rect(panel.dragFeedback.active, 400, 300, 120, 400)
    rect(panel.root, 310, 444, 300, 200)
    f:release(panel)
    rect(panel.root, 400, 300, 120, 400)
    assert(panel.dragFeedback == nil and panel.dragState == nil)
end)

run("resize respects live obstacles and refuses unverified geometry", function(f)
    local scene = nativeScene(f)
    local obstacle = scene.node(1477, 100, scene.area, 450, 0, 100, 700)
    local fail = false
    function scene.area.IterateStaticComponents(_, callback)
        if fail then error("native enumeration unavailable") end
        callback(obstacle, obstacle.visibleGlobal)
    end
    local panel = f:panel()
    f:resize(panel, "e", 600, 0)
    rect(panel.root, 100, 100, 350, 200)
    obstacle.nativeShown = false
    f:resize(panel, "e", 50, 0)
    rect(panel.root, 100, 100, 400, 200)
    fail = true
    f:resize(panel, "e", 50, 0)
    rect(panel.root, 100, 100, 400, 200)
end)

run("raw pointer coordinates respect interface scale and parent origin", function(f)
    f.parent:SetPos(80, 40)
    game.options.InterfaceScale.setting = 150
    local pointer = { x = (80 + 250) * 1.5, y = (40 + 106) * 1.5 }
    Mouse.GetPosition = function() return pointer end
    local panel = f:panel()
    f:begin(panel)
    pointer.x, pointer.y = (80 + 450) * 1.5, (40 + 300) * 1.5
    f.fire(panel.dragLayer, ui.Hook.ONHOLD, 150, 6)
    pointer.x, pointer.y = (80 + 500) * 1.5, (40 + 350) * 1.5
    f:release(panel)
    rect(panel.root, 350, 344, 300, 200)
end)

local function unpositioned(f, options)
    local panel = f.NisPanel.new(f.parent, options or {})
    f.panels[#f.panels + 1] = panel
    return panel
end

local function ribbonScene(f)
    config.Cursor.CURSOR_OPEN = { id = 7 }
    local scene = nativeScene(f)
    local ribbon = require("src/ribbon_bar")
    ribbon.Start()
    return scene, ribbon
end

for _, case in ipairs({
    { edge = "left", x = 50, y = 150 },
    { edge = "right", x = 650, y = 150 },
    { edge = "top", x = 350, y = 50 },
}) do
    run("omitted geometry opens beside the " .. case.edge .. " ribbon", function(f)
        local _, ribbon = ribbonScene(f)
        ribbon.SetPosition(case.edge)
        local panel = unpositioned(f, {
            buildContent = function(owner)
                rect(owner.root, case.x, case.y, 300, 400)
                owner:AddText("Default geometry")
            end,
        })
        rect(panel.root, case.x, case.y, 300, 400)
        assert(panel.content ~= nil and not panel.root.hidden)
    end)
end

run("first ribbon enable uses the current edge even after an unopened panel restarts", function(f)
    local scene, ribbon = ribbonScene(f)
    ribbon.SetPosition("left")
    local panel = unpositioned(f, { id = "deferred", active = false, tabIcon = 830011 })
    assert(panel.content == nil)
    panel:Destroy()
    ribbon.Shutdown()
    f:restart()
    ribbon = require("src/ribbon_bar")
    ribbon.Start()
    panel = unpositioned(f, { id = "deferred", tabIcon = 830011 })
    assert(not panel:IsActive(), "restart must preserve the unopened state")
    ribbon.SetPosition("right")
    ribbon.SetAutoHide(true)
    for _ = 1, 8 do
        f:emit("Logic")
    end
    local function findButton(node)
        if node.spriteID == panel.tabIcon then return node.parent end
        for _, child in ipairs(node.children) do
            local found = findButton(child)
            if found then return found end
        end
    end
    f.fire(assert(findButton(scene.area), "missing ribbon button"), ui.Hook.ONCLICK)
    rect(panel.root, 650, 150, 300, 400)
    assert(panel.content ~= nil and panel:IsActive())
    panel:SetSize(340, 180)
    panel:Hide()
    ribbon.SetPosition("top")
    panel:Show()
    rect(panel.root, 650, 150, 340, 180)
    panel:Destroy()
    ribbon.Shutdown()
    f:restart()
    ribbon = require("src/ribbon_bar")
    ribbon.Start()
    panel = unpositioned(f, { id = "deferred", x = 5, y = 10, width = 100, height = 80 })
    rect(panel.root, 650, 150, 340, 180)
end)

for _, case in ipairs({
    { name = "explicit x", options = { x = 25 }, x = 25, y = 150 },
    { name = "explicit y", options = { y = 37 }, x = 650, y = 37 },
    { name = "x anchor", options = { xAnchor = 0.5 }, x = 500, y = 150 },
    { name = "y anchor", options = { yAnchor = 0.5, height = 200 }, x = 650, y = 350 },
    { name = "explicit origin", options = { x = 0, y = 0 }, x = 0, y = 0 },
}) do
    run("ribbon placement preserves " .. case.name, function(f)
        local _, ribbon = ribbonScene(f)
        ribbon.SetPosition("left")
        local options = f.copy(case.options)
        options.active = false
        local panel = unpositioned(f, options)
        ribbon.SetPosition("right")
        panel:Show()
        rect(panel.root, case.x, case.y, 300, case.options.height or 400)
        if options.xAnchor then
            f.expect(panel.root.position.xParentPc, options.xAnchor, "explicit x anchor")
        end
        if options.yAnchor then
            f.expect(panel.root.position.yParentPc, options.yAnchor, "explicit y anchor")
        end
    end)
end

run("ribbon placement converts parent origins and clamps to small mounts", function(f)
    local _, ribbon = ribbonScene(f)
    local parent = f.parent
    f.parent = f.component(nil, "custom-parent")
    f.parent:SetPos(180, 140)
    f.parent:SetSize(900, 600)
    ribbon.SetPosition("right")
    local panel = unpositioned(f)
    rect(panel.root, 550, 50, 300, 400)
    panel:Destroy()
    f.parent = parent
    parent:SetSize(220, 140)
    ribbon.SetPosition("left")
    panel = unpositioned(f, { width = 200, height = 120 })
    rect(panel.root, 20, 10, 200, 120)
end)

run("first placement waits for world-map suspension to end", function(f)
    local _, ribbon = ribbonScene(f)
    local focus = { configName = "WORLDMAP_FOCUS", value = -1 }
    var.VarClient = { WORLDMAP_FOCUS = focus }
    local panel = unpositioned(f, { id = "suspended", active = false })
    focus.value = 0
    f:emit("VarTransmit", { var = focus, newValue = 0 })
    panel:Show()
    assert(panel.root.hidden)
    ribbon.SetPosition("right")
    focus.value = -1
    f:emit("VarTransmit", { var = focus, newValue = -1 })
    f:emit("Logic")
    rect(panel.root, 650, 150, 300, 400)
    assert(panel.content ~= nil and not panel.root.hidden)
end)
