-- A native nest has one frame per page. Capture can change hands during a drag;
-- the frame delivering the press is not necessarily the page being removed.
local TabLayout = require("src/nis/native_tab_layout")

local Split = {}

local function refreshFrame(Host, group, host)
    local frame = Host.component(host.spec.frame)
    if frame and Host.identity(frame) == host.key and Host.same(frame.parent, group.area) then
        host.frame = frame
        return frame
    end
end

function Split.visibleCopies(Host, group)
    local count, first, separate, standalone, sameSize = 0, nil, false, false, true
    for _, host in ipairs(group.hosts) do
        local frame = refreshFrame(Host, group, host)
        if frame and frame.visibleGlobal then
            count = count + 1
            if first and (frame.x ~= first.x or frame.y ~= first.y) then separate = true end
            if first and (frame.width ~= first.width or frame.height ~= first.height) then sameSize = false end
            local tabs = Host.component(host.spec.TABS)
            if host.grouped and tabs and not tabs.visible then standalone = true end
            first = first or frame
        end
    end
    return count, separate or count > 1 and standalone, sameSize
end

function Split.release(group, stopInputs, suspend)
    local sort = group.nativeSort
    local press = sort and sort.press or group.nativePress
    if not press then return end
    stopInputs(group)
    group.nativeSort, group.nativePress = nil, nil
    group.split, group.paintPending = press, true
    press.before = sort and sort.before
    press.away = {}
    for _, host in ipairs(group.hosts) do
        local frame = host.frame
        if frame.visibleGlobal and (frame.x ~= press.frameX or frame.y ~= press.frameY) then
            press.away[host.key] = true
        end
        if host.grouped then TabLayout.restore(host.tabs) end
    end
    suspend(group)
end

local function residualRow(host, press)
    local count = host.grouped and #host.backgrounds or 1
    if count ~= #press.backgrounds - 1 then return false end
    for index = 1, count do
        local previous = index < press.index and index or index + 1
        local icon = host.grouped and host.backgrounds[index].icon or host.nativeIcon
        if icon ~= press.backgrounds[previous].icon then return false end
    end
    return true
end

-- If the client cancels the tear-out before the reduced row is published,
-- resume the original nest only after all its frame copies agree again.
local function rejoined(group, found, press)
    local current, count = nil, 0
    for _, host in ipairs(found) do
        if group.frames[host.key] then
            if host.signature ~= press.signature or current and host.frame.visibleGlobal then return nil end
            count = count + 1
            if host.frame.visibleGlobal then current = host end
        end
    end
    if count == #group.hosts then return current end
end

-- Only a previously bound, visible frame can inherit the nest. Match the row
-- with the pressed page removed; use the press position to disambiguate twins.
function Split.anchor(group, found)
    local press = group.split
    local candidate, matches = nil, 0
    for _, host in ipairs(found) do
        if group.frames[host.key] and host.frame.visibleGlobal and residualRow(host, press) then
            if host.frame.x == press.frameX and host.frame.y == press.frameY then return host, true end
            candidate, matches = host, matches + 1
        end
    end
    if matches == 1 then return candidate, true end
    return rejoined(group, found, press), false
end

function Split.settle(group, anchor, removed)
    local press = group.split
    for _, panel in ipairs(group.members) do
        local binding = group.bindings[panel]
        local before = binding.beforeNative
        if press.before then before = press.before[panel] end
        if removed and before and before >= press.index then before = before - 1 end
        binding.beforeNative = before
    end
    -- Hidden copies can rebuild later than the visible survivor. Keep their
    -- identities, but never keep the independently visible departing frame.
    for _, host in ipairs(group.hosts) do
        local pending = removed and anchor.grouped and not (host.frame.visibleGlobal or press.away[host.key])
        group.frames[host.key].sortPending = pending or nil
    end
    group.split = nil
end

return Split
