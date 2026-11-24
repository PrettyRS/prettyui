local Fixture = require("tests/nis_fixture")
local run, rect = Fixture.run, Fixture.rect

run("lock, transparency and resizing preserve mounted content", function(f)
    local builds = 0
    f:lock(true)
    local panel = f:panel({ buildContent = function(owner)
        builds = builds + 1
        for index = 1, 16 do owner:AddText("Row " .. index) end
    end })
    local content = panel.content
    assert(panel.scrollbarVisible)
    assert(not panel.dragLayer.enabled and not panel.resize.handles.e.enabled)

    f:lock(false)
    assert(panel.dragLayer.enabled and panel.resize.handles.e.enabled)
    rect(panel.root, 100, 100, 300, 200)
    assert(f.hitAt(f.parent, 250, 106) == panel.dragLayer, "header must receive input above the body")
    f:resize(panel, "e", 40, 0)
    rect(panel.root, 100, 100, 340, 200)
    panel:SetSize(32, 8)
    rect(panel.root, 100, 100, 64, 21)
    assert(panel.viewport.height > 0, "minimum size must leave usable content")
    f:transparency(128)
    f.expect(panel.surface.background.alpha, 1 - 128 / 255, "native background opacity")
    f.expect(panel.root.alpha or 1, 1, "consumer content stays opaque")
    f:lock(true)
    assert(not panel.dragLayer.enabled)
    f.expect(panel.content, content, "settings and resize retain controls")
    f.expect(builds, 1, "settings and resize do not rebuild content")
end)

run("hide unmounts scoped resources; show rebuilds and restores scrolling", function(f)
    local signal, order = f.event("Content"), {}
    local rowA, rowB
    local a = f:panel({ contentHeight = 500, buildContent = function(owner)
        rowA = owner:AddText("A")
        owner:OnCleanup(function()
            assert(not rowA.destroyed, "cleanup must run before controls are destroyed")
            order[#order + 1] = "first"
        end)
        owner:Subscribe(signal, function(value) rowA.content = value end)
        owner:OnCleanup(function() order[#order + 1] = "last" end)
        return function() order[#order + 1] = "returned" end
    end })
    local b = f:panel({ buildContent = function(owner)
        rowB = owner:AddText("B")
        owner:Subscribe(signal, function(value) rowB.content = value end)
    end })
    a:SetScrollPosition(64)
    local oldRow, oldThumb = rowA, a._scroll.thumbDrag
    a:Hide()
    f.expect(table.concat(order, ","), "returned,last,first", "cleanup order")
    assert(oldRow.destroyed and oldThumb.destroyed and a.content == nil)
    f:emit("Content", "still subscribed")
    f.expect(rowB.content, "still subscribed", "another panel keeps its subscription")
    assert(not pcall(a.Subscribe, a, signal, function() end), "unmounted subscriptions are rejected")
    a:Show()
    assert(rowA ~= oldRow and not rowA.destroyed)
    f.expect(a.scrollY, 64, "remount restores scroll position")
    a:Destroy(); b:Destroy()
    assert(next(f.events.Content) == nil, "destroy must release every scoped subscription")
end)

run("builder and cleanup failures still release controls and subscriptions", function(f)
    local signal, partial = f.event("Failure"), nil
    local ok, problem = pcall(function()
        f:panel({ buildContent = function(owner)
            partial = owner:AddText("Partial")
            owner:Subscribe(signal, function() error("leaked subscription") end)
            owner:OnCleanup(function() error("secondary cleanup failure") end)
            error("builder failure")
        end })
    end)
    assert(not ok and problem:find("builder failure", 1, true), "rollback must preserve the original error")
    assert(partial.destroyed and next(f.events.Failure) == nil)

    local cleaned = false
    local panel = f:panel({ buildContent = function(owner)
        partial = owner:AddText("Mounted")
        owner:Subscribe(signal, function() end)
        owner:OnCleanup(function() cleaned = true end)
        owner:OnCleanup(function() error("cleanup failure") end)
    end })
    ok, problem = pcall(panel.Hide, panel)
    assert(not ok and problem:find("cleanup failure", 1, true))
    assert(cleaned and partial.destroyed and next(f.events.Failure) == nil,
        "one failed cleanup must not prevent the remaining cleanup")
end)

run("inactive construction, close and destroy have distinct lifecycles", function(f)
    local builds, closes = 0, 0
    local panel = f:panel({ active = false,
        buildContent = function() builds = builds + 1 end,
        onClose = function() closes = closes + 1 end })
    assert(panel.content == nil and builds == 0)
    panel:Show()
    assert(panel:IsActive() and builds == 1)
    panel:Hide()
    f.expect(closes, 0, "Hide is not Close")
    panel:Show(); panel:Close()
    assert(not panel:IsActive() and panel.root ~= nil and closes == 1)
    local disposable = f:panel({ destroyOnClose = true })
    disposable:Close()
    assert(disposable.root == nil, "destroyOnClose releases the shell")
end)

run("default mount supports large content without mutating caller options", function(f)
    id.Component.TOPLEVEL_V2__GAME_AREA = (f.parent.interfaceID << 16) | f.parent.staticID
    local first, last
    local options = { buildContent = function(owner)
        first = owner:AddText("First")
        for index = 1, 260 do last = owner:AddText("Row " .. index) end
    end }
    local panel = f.NisPanel.new(options)
    assert(panel.parent == f.parent and first.categoryID ~= last.categoryID)
    assert(options.categoryID == nil)
    panel:Destroy()
    id.Component.TOPLEVEL_V2__GAME_AREA = -1
    assert(not pcall(f.NisPanel.new, {}), "missing default mount must fail before building")
end)

run("interface unload releases an active gesture without touching dead handles", function(f)
    local panel = f:panel()
    f:begin(panel); f:move(panel, 460, 450)
    f.Interfaces.unload(panel.interfaceID)
    f:emit("Logic")
    assert(panel.root == nil and panel.dragState == nil and panel.dragFeedback == nil)
    panel:Destroy()
end)

run("wrapping reflows following rows and scrolling without rebuilding", function(f)
    f.font.maxAscent, f.font.maxDescent = 14, 4
    f.font.GetStringLineCount = function(_, text, width)
        local count, used = 1, 0
        for word in text:gsub("<[^>]+>", ""):gmatch("%S+") do
            local length = #word * 7
            if used > 0 and used + 7 + length > width then
                count, used = count + 1, length
            else
                used = used == 0 and length or used + 7 + length
            end
        end
        return count
    end
    local title, body, tail
    local panel = f:panel({ width = 300, height = 160, buildContent = function(owner)
        title = owner:AddTitle("word word word word word word")
        body = owner:AddText("<col=ff0000>word word word word word word</col>")
        tail = owner:AddText("End")
    end })
    local content = panel.content
    panel:SetSize(110, 160)
    f.expect(title.height, 114, "title wraps to available width")
    f.expect(body.y, title.y + title.height + 8, "body clears wrapped title")
    f.expect(tail.y, body.y + body.height + 2, "tail clears wrapped body")
    assert(panel.scrollbarVisible)
    panel:SetScrollPosition(10000)
    f.expect(panel.scrollY, panel.contentHeight - panel._scroll.height, "last row remains reachable")
    panel:SetSize(300, 160)
    assert(not panel.scrollbarVisible and panel.scrollY == 0)
    f.expect(title.height, 28, "widening unwraps title")
    f.expect(panel.content, content, "reflow retains mounted controls")
end)
