local Fixture = require("tests/nis_fixture")
local run, rect = Fixture.run, Fixture.rect

local function pair(f, extra)
    return f:panel(extra), f:panel({ x = 500, width = 300, height = 260 })
end

local function dragTab(f, tab, x, y)
    local pointer = { x = tab.xyGlobal.x + 12, y = tab.xyGlobal.y + 12 }
    Mouse.GetPosition = function() return pointer end
    f.fire(tab, ui.Hook.ONCLICK, 12, 12)
    pointer.x, pointer.y = x, y
    f.fire(tab, ui.Hook.ONHOLD, 12, 12)
end

run("docking targets the tab band, not the body", function(f)
    local source, target = pair(f)
    f:begin(source); f:move(source, 650, 130)
    assert(source.root.hidden and not target._nisTabs.root.hidden)
    f:move(source, 650, 250)
    assert(not source.root.hidden and target._nisTabs.root.hidden)
    f:release(source)
    assert(source._nisGroup == nil, "leaving the band cancels the pending target")

    f:begin(source); f:move(source, 650, 130); f:release(source)
    assert(source._nisGroup == target._nisGroup and target.root.hidden)
    rect(source.root, 500, 100, 300, 260)
    source:Undock()
    assert(source._nisGroup == nil and target._nisGroup == nil)
    assert(not source.root.hidden and not target.root.hidden)
    rect(source.root, 500, 100, 300, 260)
end)

run("tab selection rebuilds only the selected page and retains pressed input", function(f)
    local builds, row = 0, nil
    local source, target = pair(f, { contentHeight = 500, tabIcon = Plugin.resources.image,
        buildContent = function(owner)
            builds = builds + 1
            row = owner:AddText("Page")
        end })
    assert(source:DockTo(target))
    source:SetScrollPosition(64)
    local oldRow = row
    local view = source._nisTabs
    f.expect(view.tabs[2].iconSprite.runtimeSprite.resource, Plugin.resources.image, "custom tab image")
    local pressed = f.hitAt(f.parent, 514, 126)
    f.expect(pressed, view.tabs[1].hit, "tab input follows artwork")
    f.fire(pressed, ui.Hook.ONCLICK, 10, 10)
    assert(source.content == nil and oldRow.destroyed and not target.root.hidden)
    assert(not pressed.destroyed, "selection must not destroy the in-flight native click")
    f.fire(pressed, ui.Hook.ONRELEASE, 10, 10)
    source:SelectTab(); source:SelectTab()
    assert(row ~= oldRow and builds == 2 and source.scrollY == 64)
    f:lock(true)
    target:SelectTab()
    assert(not target.root.hidden and not target.dragLayer.enabled, "locked tabs still select, not drag")
end)

run("group size limits apply to every member and disappear on undock", function(f)
    local source = f:panel({ maxWidth = 340 })
    local target = f:panel({ x = 500, width = 300, height = 260, minWidth = 280 })
    assert(source:DockTo(target))
    target:SetSize(700, 280)
    f.expect(source.root.width, 340, "inactive member maximum constrains group")
    f:resize(source, "w", 200, 0)
    f.expect(target.root.width, 280, "inactive member minimum constrains resize")
    rect(source.root, target.root.x, target.root.y, target.root.width, target.root.height)
    source:Undock()
    source:SetSize(200, 200); target:SetSize(400, 200)
    assert(source.root.width == 200 and target.root.width == 400)
end)

run("invalid docking leaves both panels usable", function(f)
    local source, target = pair(f, { maxWidth = 299 })
    assert(not source:DockTo(target), "target exceeds source limits")
    rect(target.root, 500, 100, 300, 260)
    assert(not source.root.hidden)
    source:Destroy()
    source = f:panel()
    f:lock(true)
    assert(not source:DockTo(target), "locked panels cannot explicitly dock")
    f:lock(false)
    target:Hide()
    assert(not source:DockTo(target), "hidden targets cannot accept docking")
end)

for _, finish in ipairs({ "release", "escape", "focus", "lock" }) do
    run("tab tear-out: " .. finish, function(f)
        local source, target = pair(f, { id = "source" })
        assert(source:DockTo(target))
        local tab = source._nisTabs.tabs[2].hit
        dragTab(f, tab, 200, 500)
        assert(not source.root.hidden and not target.root.hidden)
        if finish == "release" then f.fire(tab, ui.Hook.ONRELEASE)
        elseif finish == "escape" then f:emit("KeyDown", { gameKey = GameKey.ESCAPE })
        elseif finish == "focus" then f:emit("WindowFocusChanged", { hasFocus = false })
        else f:lock(true) end
        if finish == "release" then
            assert(source._nisGroup == nil and target._nisGroup == nil)
            assert(source.root.y >= target.root.y + target.root.height
                or source.root.x + source.root.width <= target.root.x, "tear-out must not overlap survivor")
        else
            assert(source._nisGroup == target._nisGroup and target.root.hidden)
            rect(source.root, 500, 100, 300, 260)
        end
        assert(source.dragState == nil and source.dragFeedback == nil, "gesture releases capture and outlines")
    end)
end

run("reordering commits on release and rolls back on Escape", function(f)
    local source, target = pair(f)
    assert(source:DockTo(target))
    local third = f:panel()
    assert(third:DockTo(source))
    local tab = third._nisTabs.tabs[3].hit
    dragTab(f, tab, 514, 128)
    f:emit("KeyDown", { gameKey = GameKey.ESCAPE })
    assert(source._nisGroup.members[3] == third, "cancel restores original order")
    tab = third._nisTabs.tabs[3].hit
    dragTab(f, tab, 514, 128)
    f.fire(tab, ui.Hook.ONRELEASE)
    assert(third._nisGroup.members[1] == third, "release commits first slot")
    rect(third.root, 500, 100, 300, 260)
    local hit = f.hitAt(f.parent, 514, 126)
    f.fire(hit, ui.Hook.ONCLICK, 10, 10)
    f.fire(hit, ui.Hook.ONRELEASE, 10, 10)
    assert(not third.root.hidden, "reordered tab remains clickable")
end)

run("narrow groups navigate hidden tabs and recover direct input when widened", function(f)
    local source, target = pair(f)
    assert(source:DockTo(target))
    source:SetSize(64, 260)
    f.fire(f.hitAt(f.parent, 548, 130), ui.Hook.ONCLICK, 4, 10)
    assert(not target.root.hidden, "previous arrow selects hidden tab")
    f.fire(f.hitAt(f.parent, 556, 130), ui.Hook.ONCLICK, 4, 10)
    assert(not source.root.hidden, "next arrow returns to source")
    source:SetSize(460, 260)
    local hit = f.hitAt(f.parent, 514, 126)
    f.fire(hit, ui.Hook.ONCLICK, 10, 10)
    f.fire(hit, ui.Hook.ONRELEASE, 10, 10)
    assert(not target.root.hidden, "widening restores direct tab access")
end)

for _, case in ipairs({
    { name = "majority", x = 249, y = 100, docked = true },
    { name = "exactly half", x = 250, y = 100, docked = false },
    { name = "minority area despite majority width", x = 200, y = 180, docked = false },
    { name = "edge contact", x = 400, y = 100, docked = false },
}) do
    run("activation overlap: " .. case.name, function(f)
        local target = f:panel({ x = case.x, y = case.y })
        local source = f:panel({ active = false })
        source:SetActive(true)
        assert(source:IsActive() and source.content ~= nil and not source.root.hidden)
        assert((source._nisGroup ~= nil) == case.docked, "overlap uses the newly active panel's area")
        if case.docked then
            assert(source._nisGroup == target._nisGroup and source._nisGroup.active == source)
            assert(target.content == nil and target.root.hidden, "only the newly selected page stays mounted")
            rect(source.root, case.x, case.y, 300, 200)
        else
            assert(target.content ~= nil and not target.root.hidden)
            rect(source.root, 100, 100, 300, 200)
        end
    end)
end

run("only reactivation groups overlapping standalone panels", function(f)
    local source = f:panel()
    local target = f:panel({ x = 180, width = 400, height = 240 })
    source:SetActive(true)
    assert(source._nisGroup == nil and target._nisGroup == nil, "already active panels do not regroup")
    source:Hide()
    source:Show()
    assert(source._nisGroup == target._nisGroup and source._nisGroup.active == source)
    rect(source.root, 180, 100, 400, 240)
end)

run("locked activation appends to the existing group and persists its selection", function(f)
    local target = f:panel({ id = "target", x = 180, width = 400, height = 240 })
    local peer = f:panel({ id = "peer" })
    assert(peer:DockTo(target))
    local group = peer._nisGroup
    local source = f:panel({ id = "source", active = false })
    f:lock(true)
    source:SetActive(true)
    assert(source._nisGroup == group and group.active == source, "activation keeps the existing group")
    assert(group.members[1] == target and group.members[2] == peer and group.members[3] == source)
    assert(target.content == nil and peer.content == nil and source.content ~= nil)
    assert(not source.dragLayer.enabled, "automatic docking must not unlock the panel")
    rect(source.root, 180, 100, 400, 240)
    source:Destroy(); peer:Destroy(); target:Destroy(); f:restart()
    source = f:panel({ id = "source" })
    peer = f:panel({ id = "peer" })
    target = f:panel({ id = "target" })
    group = source._nisGroup
    assert(group == target._nisGroup and group == peer._nisGroup and group.active == source)
    assert(group.members[1] == target and group.members[2] == peer and group.members[3] == source)
end)

run("activation chooses greatest eligible overlap with deterministic ties", function(f)
    local smaller = f:panel({ x = 200 })
    local larger = f:panel({ x = 160 })
    local tied = f:panel({ x = 160 })
    local incompatible = f:panel({ width = 400 })
    local source = f:panel({ active = false, maxWidth = 300 })
    source:Show()
    assert(source._nisGroup == tied._nisGroup, "equal areas prefer the latest registered panel")
    assert(smaller._nisGroup == nil and larger._nisGroup == nil and incompatible._nisGroup == nil)
    rect(source.root, 160, 100, 300, 200)
end)

run("activation ignores hidden, differently mounted and size-incompatible targets", function(f)
    local hidden = f:panel({ active = false })
    local incompatible = f:panel({ width = 400 })
    local parent = f.parent
    f.parent = f.component(nil, "other-parent")
    f.parent:SetSize(1000, 700)
    local other = f:panel()
    f.parent = parent
    local source = f:panel({ active = false, maxWidth = 300 })
    source:Show()
    assert(source._nisGroup == nil and source.content ~= nil and not source.root.hidden)
    assert(hidden._nisGroup == nil and incompatible._nisGroup == nil and other._nisGroup == nil)
    rect(source.root, 100, 100, 300, 200)
end)

run("restored membership takes precedence over a newly overlapping standalone panel", function(f)
    local target = f:panel({ id = "target" })
    local source = f:panel({ id = "source" })
    assert(source:DockTo(target))
    source:Hide()
    local other = f:panel()
    source:Show()
    assert(source._nisGroup == target._nisGroup and other._nisGroup == nil)
    assert(source._nisGroup.active == source)
end)
