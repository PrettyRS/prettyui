local Fixture = require("tests/nis_fixture")
local nativeScene = require("tests/nis_native_fixture")
local run, rect = Fixture.run, Fixture.rect

run("header drag fits native gaps only on commit", function(f)
    local scene = nativeScene(f)
    local left = scene.node(1477, 100, scene.area, 0, 300, 400, 400)
    local right = scene.node(1477, 101, scene.area, 520, 300, 480, 400)
    function scene.area:IterateStaticComponents(callback)
        callback(left); callback(right)
    end
    local panel = f:panel()
    f:begin(panel); f:release(panel)
    rect(panel.root, 100, 100, 300, 200)
    f:begin(panel); f:move(panel, 460, 450)
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
    function scene.area:IterateStaticComponents(callback)
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
