local Fixture = require("tests/nis_fixture")
local nativeScene = require("tests/nis_native_fixture")

local function capture(callback)
    local lines = {}
    local original = log
    log = function(line)
        if line:find("[PrettyUI dock]", 1, true) then lines[#lines + 1] = line end
    end
    local ok, err = pcall(callback)
    log = original
    assert(ok, err)
    return table.concat(lines, "\n")
end

local function enableCapture()
    require("src/nis/dock_trace").capture = true
end

Fixture.run("native drop joins a grouped host despite an undersized hidden page", function(f)
    enableCapture()
    local scene = nativeScene(f)
    local panel = f:panel({ id = "tilemarkers:presets", minWidth = 420, minHeight = 160 })
    scene.ranged.body:SetSize(scene.ranged.body.width, 150)
    local text = capture(function()
        f:begin(panel)
        f:move(panel, 650, 130)
        assert(panel.root.hidden and panel.dragState.nativeTarget, "visible host accepts the preview")
        f:release(panel)
    end)
    assert(panel._nisNative and #panel._nisNative.group.hosts == 2, "both native pages remain in the nest")
    assert(text:find("native.dock.success", 1, true), text)
    scene.notes.frame.nativeShown = false
    scene.ranged.frame.nativeShown = true
    f:emit("Logic")
    panel:SelectTab()
    assert(
        panel._nisNative and not panel.root.hidden and panel.root.height == 150,
        "undersized hidden page remains selectable"
    )
end)

Fixture.run("incoming group drop reports the selected strip without logging idle ticks", function(f)
    enableCapture()
    local tile = f:panel({ id = "tilemarkers:presets", x = 500, tabIcon = Plugin.resources.image })
    local source = f:panel({ id = "other:panel" })
    local text = capture(function()
        f:begin(source)
        f:move(source, 650, 130)
        f:release(source)
    end)
    assert(source._nisGroup and source._nisGroup.active == source and tile._nisGroup == source._nisGroup)
    assert(text:find("tilemarkers:presets", 1, true) and text:find("other:panel", 1, true), text)
    assert(text:find("tabs=2", 1, true), text)
    local idle = capture(function()
        f:emit("Logic")
        f:emit("Draw")
    end)
    assert(idle == "", idle)
end)

Fixture.run("unrelated group drags do not emit Tile Markers diagnostics", function(f)
    enableCapture()
    local source = f:panel()
    f:panel({ x = 500 })
    local text = capture(function()
        f:begin(source)
        f:move(source, 650, 130)
        f:release(source)
    end)
    assert(source._nisGroup and text == "", text)
end)

Fixture.run("group preview reports a rejected tab icon without swallowing the client error", function(f)
    enableCapture()
    local source = f:panel({ id = "tilemarkers:presets" })
    local target = f:panel({ x = 500 })
    source.tabIcon = {}
    local text = capture(function()
        local ok, problem = pcall(target._nisTabs.Refresh, target._nisTabs, nil, nil, source)
        assert(not ok and tostring(problem):find("sprite accepts", 1, true), tostring(problem))
    end)
    assert(text:find("tab-icon-assignment-failed", 1, true) and text:find("tilemarkers:presets", 1, true), text)
end)

Fixture.run("Tile Markers drag diagnostics are off by default", function(f)
    local source = f:panel({ id = "tilemarkers:presets" })
    local target = f:panel({ x = 500 })
    local text = capture(function()
        f:begin(source)
        f:move(source, 650, 130)
        f:release(source)
    end)
    assert(source._nisGroup and source._nisGroup == target._nisGroup and text == "", text)
end)

Fixture.run("enabled dock traces have a hard per-load line and byte budget", function()
    enableCapture()
    local trace = require("src/nis/dock_trace")
    local problem = string.rep("line\n", 300)
    local text = capture(function()
        for _ = 1, 20 do
            trace.log("reject", "a", problem, "b", problem, "c", problem, "d", problem)
        end
    end)
    local count = 0
    for line in text:gmatch("[^\n]+") do
        assert(#line <= 512 and line:find("[PrettyUI dock] reject", 1, true) == 1)
        count = count + 1
    end
    assert(count == 8 and not trace.active())
end)
