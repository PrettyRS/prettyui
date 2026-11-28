-- Developer opt-in; the budget is shared by all drags until PrettyUI reloads.
local Trace = { capture = false }
local remaining = 8
local MAX_LINE_BYTES = 512
local PANEL_ID = "tilemarkers:presets"

local function includesTileMarkers(panel)
    if not panel then return false end
    if panel._nisPersistenceID == PANEL_ID then return true end
    local group = panel._nisGroup or (panel._nisNative and panel._nisNative.group)
    if group then
        for _, member in ipairs(group.members) do
            if member._nisPersistenceID == PANEL_ID then return true end
        end
    end
    return false
end

function Trace.active()
    return Trace.capture and remaining > 0 and type(log) == "function"
end

function Trace.enabled(panel, other)
    return Trace.active() and (includesTileMarkers(panel) or includesTileMarkers(other))
end

function Trace.panel(panel)
    if not panel then return "none" end
    return tostring(panel._nisPersistenceID or panel.tabText or "panel") .. "@" .. tostring(panel._nisOrder)
end

function Trace.target(drag)
    if drag.nisTarget then return "panel:" .. Trace.panel(drag.nisTarget) end
    if drag.nativeTarget then return "native:" .. tostring(drag.nativeTarget.spec.frame) end
    local r = drag.target
    if not r then return "none" end
    return ("free:%s,%s/%sx%s"):format(r.x, r.y, r.width, r.height)
end

function Trace.strip(panel)
    -- Use Lua-owned state only: never dereference native component or sprite handles for a snapshot.
    local view = panel and panel._nisTabs
    if not view then return "none" end
    return ("tabs=%d,visible=%s,parts=%s"):format(#view.tabs, tostring(view.visible), tostring(view.parts ~= nil))
end

local function fieldText(value)
    local kind = type(value)
    if kind == "string" then return (value:sub(1, 128):gsub("%c", " ")) end
    if kind == "number" or kind == "boolean" or kind == "nil" then return tostring(value) end
    return kind
end

function Trace.log(phase, ...)
    if not Trace.active() then return end
    remaining = remaining - 1
    local line = "[PrettyUI dock] " .. phase
    for index = 1, select("#", ...), 2 do
        line = line .. " " .. select(index, ...) .. "=" .. fieldText(select(index + 1, ...))
        if #line >= MAX_LINE_BYTES then break end
    end
    pcall(log, line:sub(1, MAX_LINE_BYTES))
end

return Trace
