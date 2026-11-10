local Snap = require("src/core/snap")
local NisLayout = require("src/core/nis_layout")
local DragFeedback = require("src/core/drag_feedback")
local InterfaceMouse = require("src/core/mouse")
local Cursor = require("src/core/cursor")
local NisGroup = require("src/core/nis_group")

local NisDrag = {}
local activePanel
local EVENT_ID = "prettyui_nis_panel_drag"

local function scaleSetting()
    local option = game and game.options and game.options.InterfaceScale
    return option and option.setting or 100
end

local function pointer(panel, component, x, y)
    local raw = InterfaceMouse.FromRawPosition(Mouse.GetPosition())
    if raw then
        local origin = panel.parent.xyGlobal
        return raw.x - origin.x, raw.y - origin.y
    end
    if component and type(x) == "number" and type(y) == "number" then
        local position = InterfaceMouse.GetPosition(component, x, y)
        if position then return position.x, position.y end
    end
end

local function tabPointer(panel, component, x, y)
    local px, py = pointer(panel, component == panel.dragLayer and component or nil, x, y)
    if px then return px, py end
    if component and type(x) == "number" and type(y) == "number" then
        local origin, parent = component.xyGlobal, panel.parent.xyGlobal
        return origin.x + x - parent.x, origin.y + y - parent.y
    end
end

local function rectLess(a, b)
    if a.x ~= b.x then return a.x < b.x end
    if a.y ~= b.y then return a.y < b.y end
    if a.width ~= b.width then return a.width < b.width end
    return a.height < b.height
end

local function sameRect(a, b)
    return a and b and a.x == b.x and a.y == b.y
        and a.width == b.width and a.height == b.height
end

-- Normalize before comparing: registry order, duplicate obstacles and fractional
-- changes within the same occupied units must not invalidate the free-space cache.
local function collectSpaces(panel, drag)
    local width, height = math.floor(panel.parent.width), math.floor(panel.parent.height)
    -- The native plugin-host layer spans the viewport but is not a NIS panel.
    -- Exclude its proven identity only; Window's default collection is unchanged.
    local ok = pcall(Snap.collect, panel, drag.rects, true,
        id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_BOTTOM)
    if not ok then
        drag.spaces = nil
        drag.snapshotValid = false
        return
    end
    local rects, count = drag.rects, 0
    for index = 1, #rects do
        local rect = rects[index]
        local left, top = math.max(0, math.floor(rect.x)), math.max(0, math.floor(rect.y))
        local right = math.min(width, math.ceil(rect.x + rect.width))
        local bottom = math.min(height, math.ceil(rect.y + rect.height))
        if rect.width > 0 and rect.height > 0 and right > left and bottom > top then
            count = count + 1
            rects[index], rects[count] = rects[count], rect
            rect.x, rect.y, rect.width, rect.height = left, top, right - left, bottom - top
        end
    end
    for index = #rects, count + 1, -1 do rects[index] = nil end
    table.sort(rects, rectLess)
    count = 0
    for index = 1, #rects do
        local rect = rects[index]
        if count == 0 or not sameRect(rects[count], rect) then
            count = count + 1
            rects[index], rects[count] = rects[count], rect
        end
    end
    for index = #rects, count + 1, -1 do rects[index] = nil end
    local snapshot = drag.snapshot
    local minWidth, minHeight = NisGroup.limits(panel)
    local changed = not drag.snapshotValid or #snapshot ~= count
        or drag.parentWidth ~= width or drag.parentHeight ~= height
        or drag.minWidth ~= minWidth or drag.minHeight ~= minHeight
    if not changed then
        for index, rect in ipairs(rects) do
            if not sameRect(snapshot[index], rect) then changed = true; break end
        end
    end
    if changed then
        for index, rect in ipairs(rects) do
            local saved = snapshot[index] or {}
            snapshot[index] = saved
            saved.x, saved.y, saved.width, saved.height = rect.x, rect.y, rect.width, rect.height
        end
        for index = #snapshot, count + 1, -1 do snapshot[index] = nil end
        drag.parentWidth, drag.parentHeight = width, height
        drag.minWidth, drag.minHeight = minWidth, minHeight
        drag.spaces = NisLayout.spaces(rects, width, height, minWidth, minHeight)
        drag.snapshotValid = true
    end
end

local function preview(panel, drag)
    local candidate
    if drag.snapshotValid ~= false or drag.spaces ~= nil then
        candidate = NisGroup.candidate(panel, drag.pointerX, drag.pointerY)
    end
    NisGroup.preview(panel, candidate)
    drag.nisTarget = candidate
    local target
    if candidate then
        local root = candidate.root
        target = { x = root.x, y = root.y, width = root.width, height = root.height }
    else
        local minWidth, minHeight, maxWidth, maxHeight = NisGroup.limits(panel)
        local width = math.max(minWidth, math.min(maxWidth or math.huge, drag.width))
        local height = math.max(minHeight, math.min(maxHeight or math.huge, drag.height))
        target = drag.spaces and NisLayout.fit(drag.spaces, drag.pointerX, drag.pointerY,
            width, height, drag.gripFractionX, drag.gripY,
            maxWidth, maxHeight)
    end
    drag.target = target
    local feedback = panel.dragFeedback
    local hidden = target == nil
    if feedback.active.hidden ~= hidden then feedback.active.hidden = hidden end
    if target then feedback:SetTargetRect(target.x, target.y, target.width, target.height) end
    -- Only orange fits/snaps. The original-size body follows its pointer grip.
    local x = math.floor(drag.pointerX - drag.gripFractionX * drag.width + 0.5)
    local y = math.floor(drag.pointerY - drag.gripY + 0.5)
    if panel.root.x ~= x or panel.root.y ~= y then
        panel.root:SetPos(x, y)
        panel:_SyncOverlays(panel.root.hidden == true)
        drag.capture:MoveToFront()
    end
    if drag.raisedTarget ~= candidate then
        drag.raisedTarget = candidate
        if candidate then candidate.root:MoveToFront() else panel.root:MoveToFront() end
        if candidate then candidate._nisTabs:Sync(false) else panel._nisTabs:Sync(false) end
        feedback.origin:MoveToFront()
        feedback.active:MoveToFront()
        drag.capture:MoveToFront()
    end
end

local function unsubscribe(panel)
    if activePanel ~= panel then return end
    activePanel = nil
    Event.Logic.Unsubscribe(EVENT_ID)
    Event.KeyDown.Unsubscribe(EVENT_ID)
    Event.WindowFocusChanged.Unsubscribe(EVENT_ID)
end

function NisDrag.install(NisPanel)
    function NisPanel:_CheckDragEnvironment()
        local drag = self.dragState or self._nisTabPress
        if not drag then return false end
        if ui.Interfaces:GetInterface(self.interfaceID) == nil then
            self:Destroy()
            return true
        end
        local origin = self.parent.xyGlobal
        if self.parent.width ~= drag.viewportWidth or self.parent.height ~= drag.viewportHeight
            or origin.x ~= drag.parentX or origin.y ~= drag.parentY or scaleSetting() ~= drag.scale then
            self:_CancelDrag()
            self.dragBounds:Clamp()
            return true
        end
        return false
    end

    function NisPanel:_BeginDrag(component, x, y, gripX, gripY, retainExpanded)
        if self.locked or self.root == nil or ui.Interfaces:GetInterface(self.interfaceID) == nil
            or self.root.hidden or self.root.visibleGlobal == false then return true end
        if not retainExpanded then InterfaceMouse.CalibrateFromHook(component, x, y) end
        local px, py = pointer(self, component, x, y)
        if px == nil then return false end
        local root = self.root
        if component == self.dragLayer and not retainExpanded and
            (px < root.x or px >= root.x + root.width - 12
                or py < root.y or py >= root.y + 12) then
            return false
        end
        if activePanel then activePanel:_CancelDrag() end
        if self.resize then self.resize:Cancel() end
        InterfaceMouse.BeginCapture(component)
        local origin = self.parent.xyGlobal
        self.dragState = {
            x = root.x, y = root.y, width = root.width, height = root.height,
            capture = component,
            gripFractionX = (gripX or x) / root.width, gripY = gripY or y,
            pressX = px, pressY = py, pointerX = px, pointerY = py,
            viewportWidth = self.parent.width, viewportHeight = self.parent.height,
            parentX = origin.x, parentY = origin.y, scale = scaleSetting(),
            captureExpanded = retainExpanded == true,
            rects = {}, snapshot = {},
        }
        root:MoveToFront()
        component:MoveToFront()
        self:_SyncOverlays(false)
        activePanel = self
        Event.Logic.Subscribe(EVENT_ID, function()
            if self:_CheckDragEnvironment() then return end
            local drag = self.dragState
            if not drag then return end
            local pxNow, pyNow = pointer(self)
            if pxNow then drag.pointerX, drag.pointerY = pxNow, pyNow end
            if not drag.moved then
                self:_MoveDrag()
            else
                collectSpaces(self, drag)
                preview(self, drag)
            end
        end)
        Event.KeyDown.Subscribe(EVENT_ID, function(event)
            if event.gameKey == GameKey.ESCAPE then self:_CancelDrag() end
        end)
        Event.WindowFocusChanged.Subscribe(EVENT_ID, function(event)
            if event.hasFocus == false then self:_CancelDrag() end
        end)
        return false
    end

    function NisPanel:_MoveDrag(component, x, y)
        if not self.dragState or self:_CheckDragEnvironment() then return false end
        local drag = self.dragState
        local px, py = pointer(self, component, x, y)
        if px then drag.pointerX, drag.pointerY = px, py end
        if not drag.moved then
            if drag.pointerX == drag.pressX and drag.pointerY == drag.pressY then return false end
            -- Capture the white source before moving the original-size ghost.
            self.dragFeedback = self.dragFeedback or DragFeedback.new(self.parent, self.root)
            drag.moved = true
            drag.captureExpanded = true
            local capture = drag.capture
            InterfaceMouse.EndCapture(capture)
            capture:SetPos(0, 0)
            capture:SetSize(0, 0, 1, 1)
            InterfaceMouse.BeginCapture(capture)
            self.dragFeedback.origin:MoveToFront()
            self.dragFeedback.active:MoveToFront()
            capture:MoveToFront()
            collectSpaces(self, drag)
        end
        preview(self, drag)
        return false
    end

    function NisPanel:_StopDrag(commit, component, x, y)
        local drag = self.dragState
        if not drag then return false end
        if commit and self:_CheckDragEnvironment() then return false end
        local loaded = ui.Interfaces:GetInterface(self.interfaceID) ~= nil
        if loaded and commit and drag.moved then
            local px, py = pointer(self, component, x, y)
            if px then drag.pointerX, drag.pointerY = px, py end
            collectSpaces(self, drag)
            preview(self, drag)
        end
        self.dragState = nil
        unsubscribe(self)
        InterfaceMouse.EndCapture(drag.capture)
        if drag.tab then drag.tab:Release() end
        local target = loaded and commit and drag.moved and drag.target
        local nisTarget = target and drag.nisTarget
        NisGroup.clearPreview(self)
        if loaded then
            if nisTarget and NisGroup.dock(self, nisTarget, false) then
                if drag.tab then NisGroup.reorder(self, drag.pointerX) end
                self._nisTabTransaction = nil
            elseif target and not nisTarget then
                NisGroup.apply(self, target.x, target.y, target.width, target.height)
                if self._nisTabTransaction then
                    self._nisTabTransaction = nil
                end
            else
                NisGroup.apply(self, drag.x, drag.y, drag.width, drag.height)
                if self._nisTabTransaction then
                    NisGroup.restore(self._nisTabTransaction)
                    self._nisTabTransaction = nil
                end
            end
        else
            self._nisTabTransaction = nil
        end
        if self.dragFeedback then
            self.dragFeedback:Destroy()
            self.dragFeedback = nil
        end
        if self.root and ui.Interfaces:GetInterface(self.interfaceID) ~= nil then
            self.root:MoveToFront()
            self._nisTabs:Sync(self.root.hidden == true)
        end
        if self._nisGroup then NisGroup.notify(self) else self:_NotifyBoundsChange() end
        self:_SyncDragLayer()
        return false
    end

    function NisPanel:_CancelDrag()
        if self._nisTabPress then return self:_StopNisTabDrag(nil, nil, nil, false) end
        return self:_StopDrag(false)
    end

    function NisPanel:_SelectNisTab(member)
        if member and member._nisGroup == self._nisGroup then NisGroup.select(member) end
    end

    function NisPanel:_BeginNisTabDrag(member, component, x, y, tab)
        if not member or not member._nisGroup or member._nisGroup ~= self._nisGroup
            or member.locked or self.locked or ui.Interfaces:GetInterface(member.interfaceID) == nil then
            return false
        end
        if activePanel then activePanel:_CancelDrag() end
        InterfaceMouse.CalibrateFromHook(component, x, y)
        local px, py = tabPointer(self, component, x, y)
        if not px then return false end
        local origin = member.parent.xyGlobal
        local press = {
            owner = self, member = member, component = component,
            snapshot = NisGroup.snapshot(member),
            pressX = px, pressY = py,
            viewportWidth = member.parent.width, viewportHeight = member.parent.height,
            parentX = origin.x, parentY = origin.y, scale = scaleSetting(),
            tab = tab,
        }
        member._nisTabPress = press
        self._nisTabPress = press
        if tab then tab.dragOwner = member end
        activePanel = member
        Event.Logic.Subscribe(EVENT_ID, function()
            if member._nisTabPress ~= press then return end
            if member:_CheckDragEnvironment() then return end
            -- Poll only an established drag, never a click awaiting release.
            if press.dragging then member:_MoveNisTabDrag() end
        end)
        Event.KeyDown.Subscribe(EVENT_ID, function(event)
            if event.gameKey == GameKey.ESCAPE then member:_CancelDrag() end
        end)
        Event.WindowFocusChanged.Subscribe(EVENT_ID, function(event)
            if event.hasFocus == false then member:_CancelDrag() end
        end)
        return false
    end

    function NisPanel:_MoveNisTabDrag(component, x, y)
        local press = self._nisTabPress
        if not press then
            if self.dragState and self.dragState.capture == component then
                return self:_MoveDrag(component, x, y)
            end
            return false
        end
        local member = press.member
        if member:_CheckDragEnvironment() then return false end
        if not member._nisGroup or member.locked then
            member:_CancelDrag()
            return false
        end
        local px, py = tabPointer(member, component, x, y)
        if not px then return false end
        local capture = press.component
        if not press.dragging then
            if math.max(math.abs(px - press.pressX), math.abs(py - press.pressY)) < 4 then return false end
            press.dragging = true
            if press.tab then press.tab.retained = true end
            member.dragFeedback = DragFeedback.new(member.parent, member.root)
            capture:SetPos(0, 0)
            capture:SetSize(0, 0, 1, 1)
            InterfaceMouse.BeginCapture(capture)
        end
        if member._nisTabs:Contains(px, py) then
            NisGroup.reorder(member, px)
            local feedback = member.dragFeedback
            feedback:SetTargetRect(math.floor(px - member.root.width / 2 + 0.5),
                math.floor(py - 6 + 0.5), member.root.width, member.root.height)
            feedback.origin:MoveToFront()
            feedback.active:MoveToFront()
            capture:MoveToFront()
            return false
        end
        member._nisTabPress, press.owner._nisTabPress = nil, nil
        unsubscribe(member)
        NisGroup.undock(member)
        member._nisTabTransaction = press.snapshot
        Cursor.apply(capture, config.Cursor.TOPLEVEL_V2_MOVE, true)
        member:_BeginDrag(capture, press.pressX, press.pressY,
            member.root.width / 2, 6, true)
        if member.dragState then
            member.dragState.tab = press.tab
            member.dragState.pressX, member.dragState.pressY = press.pressX, press.pressY
            member.dragState.pointerX, member.dragState.pointerY = px, py
            member:_MoveDrag()
        else
            NisGroup.restore(member._nisTabTransaction)
            member._nisTabTransaction = nil
            if member.dragFeedback then member.dragFeedback:Destroy(); member.dragFeedback = nil end
            if press.tab then press.tab:Release() end
        end
        return false
    end

    function NisPanel:_StopNisTabDrag(component, x, y, commit)
        local press = self._nisTabPress
        if not press then
            if self.dragState and self.dragState.capture == component then
                return self:_StopDrag(commit ~= false, component, x, y)
            end
            return false
        end
        local member = press.member
        if press.dragging and commit ~= false and component then
            member:_MoveNisTabDrag(component, x, y)
            if member.dragState then return member:_StopDrag(true, component, x, y) end
            if member._nisTabPress ~= press then return false end
        end
        member._nisTabPress, press.owner._nisTabPress = nil, nil
        unsubscribe(member)
        InterfaceMouse.EndCapture(press.component)
        if press.dragging then
            if press.tab then press.tab:Release() end
        elseif press.tab then
            press.tab.dragOwner = nil
        end
        if member.dragFeedback then
            member.dragFeedback:Destroy()
            member.dragFeedback = nil
        end
        if commit == false and press.snapshot then
            if press.dragging then NisGroup.restore(press.snapshot)
            else NisGroup.select(press.snapshot.active) end
        end
        local group = member._nisGroup
        if group then group.active._nisTabs:Refresh(group.members, group.active) end
        if member.root and ui.Interfaces:GetInterface(member.interfaceID) ~= nil then
            member:_SyncOverlays(member.root.hidden == true)
        end
        return false
    end
end

return NisDrag
