-- Native NIS windows keep their own scripts, tab input and layout. All retained
-- PrettyUI content, artwork and input live on GAME_AREA: native lock/rebuild
-- processing can retire dynamic render entries even below an owned frame child.
local Components = require("src/core/components")
local Sprites = require("src/core/sprites")
local Tooltip = require("src/tooltip")
local Cursor = require("src/core/cursor")
local InterfaceMouse = require("src/core/mouse")
local Persistence = require("src/core/nis_persistence")
local NisGroup = require("src/core/nis_group")

local Native = {}
local groups, byFrame = {}, {}
local subscribed = false
local pending = {}
local restoring = false
local restorePending
local EVENT_ID = "prettyui_nis_native"
local nextHook = 0
local HEIGHT, WIDTH, SEAM, MAX_TABS = 28, 40, 4, 128
local art = Sprites.NIS_PANEL
local positions = { "x", "y", "xParentPc", "yParentPc", "xSelfPc", "ySelfPc" }
local sizes = { "width", "height", "widthParentPc", "heightParentPc" }

local function identity(component)
    if not component then return nil end
    local a, b, c, d = component.interfaceID, component.staticID, component.categoryID, component.dynamicID
    if type(a) ~= "number" or type(b) ~= "number" or type(c) ~= "number" or type(d) ~= "number" then return nil end
    return a .. ":" .. b .. ":" .. c .. ":" .. d
end

local function warn(message)
    if type(log) == "function" then pcall(function() log("PrettyUI native docking: " .. tostring(message)) end) end
end

-- Index component names, not static numbers or similarly positioned windows.
-- ABILITY_WINDOW_CONTENT_RANGED and ABILITY_WINDOW_TABS_RANGED both belong to
-- ABILITY_WINDOW_RANGED; NOTES_WINDOW_CONTENT belongs to NOTES_WINDOW.
local specs, specByID = {}, {}
local indexed = false
local function indexSpecs()
    if indexed then return end
    indexed = true
    for packed, name in pairs(id.Component) do
        if type(name) == "string" and type(packed) == "number" then
            for _, kind in ipairs({ "CONTENT", "EDIT_BLOCK", "SCROLL", "TAB_BACKGROUND", "TABS" }) do
                local base, suffix = name:match("^(.+_WINDOW)_" .. kind .. "(.*)$")
                if base and (suffix == "" or suffix:sub(1, 1) == "_") then
                    local frameName = base .. suffix
                    local spec = specs[frameName]
                    if not spec then spec = { name = frameName }; specs[frameName] = spec end
                    if kind ~= "TABS" or not suffix:match("^_SCROLL") then spec[kind] = packed end
                    break
                end
            end
        end
    end
    for name, spec in pairs(specs) do
        spec.frame = id.Component[name]
        if type(spec.frame) == "number" and spec.frame >= 0
            and spec.CONTENT and spec.TABS and spec.TAB_BACKGROUND then
            specByID[spec.frame] = spec
        else
            specs[name] = nil
        end
    end
end

local function component(packed)
    return packed and ui.Interfaces:GetComponent(packed) or nil
end

local function same(componentA, componentB)
    return Components.sameComponent(componentA, componentB)
end

local function live(group)
    return ui.Interfaces:GetInterface(group.owner) ~= nil
        and same(group.area, component(id.Component.TOPLEVEL_V2__GAME_AREA))
end

local function layout(component)
    local result, pos, size = {}, component.position, component.size
    for index, field in ipairs(positions) do
        local value = pos[field]
        if type(value) ~= "number" then return nil end
        result[index] = value
    end
    for index, field in ipairs(sizes) do
        local value = size[field]
        if type(value) ~= "number" then return nil end
        result[index + 6] = value
    end
    return result
end

local function applyLayout(component, saved)
    component:SetPos(table.unpack(saved, 1, 6))
    component:SetSize(table.unpack(saved, 7, 10))
end

local function spriteID(component)
    local ok, value = pcall(function() return component.spriteID end)
    if ok and type(value) == "number" then return value, "spriteID" end
    ok, value = pcall(function() return component.spriteId end)
    if ok and type(value) == "number" then return value, "spriteId" end
    return nil
end

local function strip(tabs)
    local backgrounds, children, seen, overflow, count = {}, {}, {}, false, 0
    tabs:IterateDynamicComponents(function(child)
        count = count + 1
        if count > MAX_TABS then overflow = true; return true end
        local key = identity(child)
        if not key then overflow = true; return true end
        if not seen[key] and same(child.parent, tabs) then
            seen[key] = true
            children[#children + 1] = child
            local value, field = spriteID(child)
            if child.visible and child.hidden ~= true
                and (value == art.tabSelected or value == art.tabUnselected) then
                backgrounds[#backgrounds + 1] = { component = child, key = key, field = field }
            end
        end
        return false
    end)
    if overflow or #backgrounds == 0 then return nil end
    table.sort(backgrounds, function(a, b) return a.component.x < b.component.x end)
    local signature, right = {}, 0
    for _, entry in ipairs(backgrounds) do
        local bg = entry.component
        if bg.width < WIDTH or bg.height ~= HEIGHT or bg.x < 0 then return nil end
        local icon
        for _, child in ipairs(children) do
            if child.visible and child.hidden ~= true and child.width == 24 and child.height == 24
                and child.y == 2 and child.x == bg.x + math.floor((bg.width - 24) / 2) then
                local value = spriteID(child)
                if value then icon = value; break end
            end
        end
        if not icon then return nil end
        signature[#signature + 1] = tostring(bg.x) .. ":" .. tostring(bg.width) .. ":" .. tostring(icon)
        entry.icon = icon
        right = math.max(right, bg.x + bg.width)
    end
    return backgrounds, children, table.concat(signature, "/"), right
end

-- Client-hidden native strips need not reflow when the standalone content does.
local function tabBand(host)
    return host.grouped and host.tabs or host.content
end

local function capture(spec, area, allowHidden)
    local frame = component(spec.frame)
    if not frame or not same(frame.parent, area) or frame.hidden then return nil end
    local content, scroll, tabs, backdrop = component(spec.CONTENT), component(spec.SCROLL),
        component(spec.TABS), component(spec.TAB_BACKGROUND)
    if not content or not tabs or not backdrop or spec.SCROLL and not scroll
        or not same(content.parent, frame) or scroll and not same(scroll.parent, frame)
        or not same(tabs.parent, frame) or not same(backdrop.parent, frame)
        or content.width <= 0 or content.height <= HEIGHT
        or not allowHidden and (content.hidden or scroll and scroll.hidden) then return nil end
    local grouped = tabs.visible == true
    local frameKey = identity(frame)
    local backgrounds, children, signature, used, nativeIcon
    if grouped then
        if tabs.height ~= HEIGHT or tabs.width < WIDTH * 2
            or content.x ~= tabs.x or backdrop.y ~= tabs.y then return nil end
        backgrounds, children, signature, used = strip(tabs)
        if not backgrounds or used + WIDTH > tabs.width or content.y < tabs.y + HEIGHT then return nil end
    else
        if not frame.visibleGlobal or content.width < WIDTH * 2 then return nil end
        -- Standalone strips stay client-hidden, but their single native tab
        -- usually still exposes the correct icon. Notes may have no children.
        local entries = strip(tabs)
        if entries and #entries == 1 then
            nativeIcon = entries[1].icon
        elseif spec.name == "TOPLEVEL_V2__NOTES_WINDOW" then
            nativeIcon = id.Sprite.CHILD_TAB_ICON_NOTES
        end
        -- A lock rebuild can clear a hidden strip. Retain only an icon already
        -- captured for this bound frame; new hosts still require discovery.
        local bound = byFrame[frameKey]
        if not nativeIcon and bound and not bound.grouped then
            for _, previous in ipairs(bound.hosts) do
                if previous.key == frameKey then nativeIcon = previous.nativeIcon; break end
            end
        end
        if not nativeIcon then return nil end
        backgrounds, children, signature, used = {}, {}, "", WIDTH
    end
    return { frame = frame, content = content, scroll = scroll, tabs = tabs,
        backdrop = backdrop, key = frameKey, owner = frame.interfaceID,
        backgrounds = backgrounds, children = children, signature = signature,
        used = used, grouped = grouped, spec = spec,
        nativeIcon = nativeIcon }
end

-- Whole rendered roots captured from standalone hosts. Prayer's separate
-- LISTENERS_AND_TIMERS root must remain live; it is not part of the page.
local standaloneRoots = {
    TOPLEVEL_V2_INVENTORY__MAIN_LAYER = true,
    TOPLEVEL_V2_PRAYER__MAIN_LAYER = true,
    TOPLEVEL_V2_WORN__CONTENT_LAYER = true,
    CHATDEFAULT__CHAT_CONTAINER = true,
    STATS_CHILD__CANVAS = true,
    EMOTES2__MAIN_LAYER = true,
    TELEMETRY__TELEMETRY_WINDOW_CONTENT = true,
    DROPLOG__DROPLOG_WINDOW_CONTENT = true,
    GRAPH__GRAPH_WINDOW_CONTENT = true,
    FRIENDS2__MAIN = true,
    GROUP_CHILD__BASE = true,
    TOPLEVEL_V2_PLUGIN_CONTENT__MAIN_LAYER = true,
    CHEEVO_TRACKER__ACTIVITY_TRACKER_ROOT = true,
    CHEEVO_PATHS__CHEEVO_PATHS_ROOT = true,
}

-- These standalone pages have no common wrapper. Preserve each captured
-- root's anchors and relative geometry while reserving the same header band.
local splitRoots = {
    TOPLEVEL_V2__QUESTLIST_WINDOW = {
        { name = "QUESTLIST_V4__LIST_MAIN", layout = { 0, 30, 0, 0, 0, 0, 0, -30, 1, 1 } },
        { name = "QUESTLIST_V4__CONTROLS_LAYER", layout = { 4, 2, 0, 0, 0, 0, -8, 30, 1, 0 } },
        { name = "QUESTLIST_V4__CONTROLS_FILTERS_LAYER", layout = { 4, 32, 0, 0, 0, 0, -30, 130, 1, 0 } },
    },
    TOPLEVEL_V2__CLAN_LIST_WINDOW = {
        { name = "CLAN_CHAT__MAIN_CONTENT_LAYER", layout = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1 } },
        { name = "CLAN_CHAT__TOOLTIP", layout = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1 } },
    },
}

local function snapshotRoot(child, original, inset)
    return { component = child, owner = child.interfaceID, key = identity(child),
        packed = (child.interfaceID << 16) | child.staticID,
        original = original, inset = inset, hidden = child.hidden, changed = false }
end

-- Familiar availability swaps an embedded page for native edit-block children.
-- Keep their captured layouts separate; never resize the outer edit container.
local familiarPlaceholder = {
    { kind = 1, layout = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1 } },
    { kind = 2, layout = { 5, 5, 0, 0, 0, 0, -10, -10, 1, 1 } },
    { kind = 3, layout = { 0, 20, 0.5, 0, 0.5, 0, 64, 64, 0, 0 } },
}

local function familiarRootsFor(host, previous)
    local roots, retained = {}, {}
    for _, saved in ipairs(previous or {}) do retained[saved.key] = saved end
    local function include(child, expected, parent, kind)
        if not child then return true end
        if not same(child.parent, parent) or kind and child.type ~= kind then return false end
        local saved = retained[identity(child)]
        if saved then
            saved.component = child
        else
            local original = layout(child)
            if not original or child.hidden then return false end
            for index, value in ipairs(expected) do
                if original[index] ~= value then return false end
            end
            local inset = { table.unpack(original) }
            inset[2], inset[8] = inset[2] + HEIGHT, inset[8] - HEIGHT * inset[10]
            if parent.width * inset[9] + inset[7] <= 0
                or parent.height * inset[10] + inset[8] <= 0 then return false end
            saved = snapshotRoot(child, original, inset)
        end
        roots[#roots + 1] = saved
        return true
    end
    local packed = id.Component.LORE_STATS_SIDE__CONTENT_LAYER
    local page = type(packed) == "number" and packed >= 0 and component(packed) or nil
    -- The client keeps 662:0 alive but unparented while unavailable. A loaded
    -- interface is not necessarily a page mounted in this native host.
    if page and not same(page.parent, host.content) then page = nil end
    -- The full-size familiar page has the same centered anchors as Equipment.
    if not include(page, { 0, 0, 0.5, 0.5, 0.5, 0.5, 0, 0, 1, 1 }, host.content) then return nil end
    if page and not retained[identity(page)] then
        -- Normalize both parent/self anchors when shrinking a centered root.
        roots[#roots].inset = { 0, HEIGHT, 0, 0, 0, 0, 0, -HEIGHT, 1, 1 }
    end
    local edit = component(host.spec.EDIT_BLOCK)
    if not edit or not same(edit.parent, host.frame) then return nil end
    for index, schema in ipairs(familiarPlaceholder) do
        local child = ui.Interfaces:GetComponent(edit.interfaceID, edit.staticID, 0, index - 1)
        if not include(child, schema.layout, edit, schema.kind) then return nil end
    end
    -- A bound host may briefly have neither page during the native swap.
    if #roots == 0 and not previous then return nil end
    return roots
end

-- A standalone inset requires actual parentage and full-size anchored content,
-- not a matching rectangle or an unrendered interface with a similar name.
local wrappers
local function nativeRootsFor(host)
    if host.spec.name == "TOPLEVEL_V2__LORE_WINDOW" then return familiarRootsFor(host) end
    local schema = splitRoots[host.spec.name]
    if schema then
        local roots = {}
        for _, entry in ipairs(schema) do
            local packed = id.Component[entry.name]
            if type(packed) ~= "number" or packed < 0 then return nil end
            local child = component(packed)
            if not child or child.hidden or not same(child.parent, host.content) then return nil end
            local original = layout(child)
            if not original then return nil end
            for index, value in ipairs(entry.layout) do
                if original[index] ~= value then return nil end
            end
            local inset = { table.unpack(original) }
            inset[2] = inset[2] + HEIGHT
            inset[8] = inset[8] - HEIGHT * inset[10]
            if host.content.width * inset[9] + inset[7] <= 0
                or host.content.height * inset[10] + inset[8] <= 0 then return nil end
            roots[#roots + 1] = snapshotRoot(child, original, inset)
        end
        return roots
    end
    if not wrappers then
        wrappers = {}
        for packed, name in pairs(id.Component) do
            if type(name) == "string" and type(packed) == "number"
                and (name:match("_WRAPPER$") or standaloneRoots[name]
                    or name:match("^TOPLEVEL_V2_WINDOW_ABILITY_BOOK_.+__MAIN_LAYER$")) then
                wrappers[#wrappers + 1] = packed
            end
        end
    end
    local chosen
    for _, packed in ipairs(wrappers) do
        local child = component(packed)
        if child and same(child.parent, host.content) then
            if chosen and not same(chosen, child) then return nil end
            chosen = child
        end
    end
    if not chosen or chosen.hidden or chosen.x ~= 0 or chosen.y ~= 0
        or chosen.width ~= host.content.width or chosen.height ~= host.content.height then return nil end
    local saved = layout(chosen)
    if not saved or saved[1] ~= 0 or saved[2] ~= 0
        or saved[7] ~= 0 or saved[8] ~= 0
        or saved[9] ~= 1 or saved[10] ~= 1 then return nil end
    -- Normalizing full-size roots also handles Equipment's centered anchors.
    return { snapshotRoot(chosen, saved, { 0, HEIGHT, 0, 0, 0, 0, 0, -HEIGHT, 1, 1 }) }
end

local function discover(area)
    indexSpecs()
    local found = {}
    for _, spec in pairs(specByID) do
        local ok, host = pcall(capture, spec, area, true)
        if ok and host then found[#found + 1] = host end
    end
    return found
end

local function related(host, other)
    if not host.grouped then return host.key == other.key end
    -- Hidden frame copies may keep their previous bounds while the visible
    -- frame moves/resizes. Membership is the native tab signature, not geometry.
    return other.grouped and other.owner == host.owner and other.signature == host.signature
        and (other.key == host.key or not (host.frame.visibleGlobal and other.frame.visibleGlobal))
end

local function resolve(host)
    if type(host) == "table" and host.group and host.free then
        local group = host.group
        for _, item in ipairs(group.hosts) do
            if item.frame.visibleGlobal then return item.spec.frame end
        end
        return group.hosts[group.current].spec.frame
    end
    if type(host) == "table" and host.spec and host.frame then return host.spec.frame end
    if type(host) == "table" and host._nisNative then return resolve(host._nisNative) end
    if type(host) == "number" then
        if specByID[host] then return host end
        host = component(host)
    end
    local visited = {}
    for _ = 1, 32 do
        if not host then return nil end
        local key = identity(host)
        if not key or visited[key] then return nil end
        visited[key] = true
        local packed = host.interfaceID * 65536 + host.staticID
        if specByID[packed] then return packed end
        host = host.parent
    end
    return nil
end

local function frameGroup(host)
    return host and byFrame[host.key]
end

local function selectedFrame(group)
    local index
    for i, host in ipairs(group.hosts) do
        if host.frame.visibleGlobal then
            if index then return nil end
            index = i
        end
    end
    return index
end

local function rectInParent(panel, component)
    local origin, parentOrigin = component.xyGlobal, panel.parent.xyGlobal
    return math.floor(origin.x - parentOrigin.x), math.floor(origin.y - parentOrigin.y),
        component.width, component.height
end

local function freeRect(panel)
    return { x = panel.root.x, y = panel.root.y,
        width = panel.root.width, height = panel.root.height }
end

function Native.candidate(panel, x, y)
    if not panel or panel._nisNative or not panel.root or panel.locked
        or not ui.Interfaces:GetInterface(panel.interfaceID) then return nil end
    local area = component(id.Component.TOPLEVEL_V2__GAME_AREA)
    if not area then return nil end
    if not same(panel.parent, area) then return nil end
    local px, py = panel.parent.xyGlobal.x + x, panel.parent.xyGlobal.y + y
    local best, found = nil, discover(area)
    for _, host in ipairs(found) do
        if host.frame.visibleGlobal then
            local band = tabBand(host)
            local top = band.xyGlobal
            local targetY = host.grouped and top.y or host.frame.xyGlobal.y
            if px >= top.x and px < top.x + band.width
                and py >= targetY and py < top.y + HEIGHT then
                local relatedHosts = {}
                for _, other in ipairs(found) do
                    if related(host, other) then relatedHosts[#relatedHosts + 1] = other end
                end
                local occupied = frameGroup(host)
                local extra = panel._nisGroup and #panel._nisGroup.members or 1
                local capacity = true
                for _, item in ipairs(relatedHosts) do
                    if item.used + WIDTH * ((occupied and #occupied.members or 0) + extra) > tabBand(item).width then
                        capacity = false
                    end
                end
                local height = host.content.height - (host.grouped and 0 or HEIGHT)
                for _, member in ipairs(panel._nisGroup and panel._nisGroup.members or { panel }) do
                    if host.content.width < member.minWidth or height < member.minHeight
                        or host.content.width > (member.maxWidth or math.huge)
                        or height > (member.maxHeight or math.huge) then capacity = false end
                end
                if capacity
                    and (occupied or not host.content.hidden and (not host.scroll or not host.scroll.hidden))
                    and (occupied or host.grouped or nativeRootsFor(host)) then
                    if best then return nil end
                    best = host
                end
            end
        end
    end
    return best
end

function Native.rect(panel, host)
    indexSpecs()
    local spec = specByID[resolve(host)]
    if not spec then return nil end
    local frame = component(spec.frame)
    if not frame or not panel or not panel.parent then return nil end
    local x, y, width, height = rectInParent(panel, frame)
    return { x = x, y = y, width = width, height = height }
end

local function validHost(group, host)
    if not (live(group) and identity(host.frame) == host.key
        and same(host.frame.parent, group.area)
        and same(host.content.parent, host.frame)
        and (not host.scroll or same(host.scroll.parent, host.frame))
        and same(host.tabs.parent, host.frame) and host.tabs.visible == host.grouped
        and tabBand(host).width >= host.used + WIDTH * #group.members) then return false end
    if not group.grouped then return true end
    return host.content.y >= host.tabs.y + HEIGHT
end

local function restoreFlag(group, saved)
    if not saved.changed then return end
    if live(group) and identity(saved.component) == saved.key then
        saved.component.hidden = saved.hidden
    end
    saved.changed = false
end

local function conceal(group, host)
    local changed = false
    for _, saved in ipairs(host.flags) do
        saved.changed = true -- setter may apply before throwing
        if not saved.component.hidden then
            saved.component.hidden = true
            changed = true
        end
    end
    return changed
end

local function restoreArtwork(group)
    local saved = group.artwork
    if not saved then return end
    if live(group) and identity(saved.component) == saved.key then
        local current = saved.component[saved.field]
        if current == art.tabUnselected then
            local another = false
            for _, bg in ipairs(saved.host.backgrounds) do
                if bg.key ~= saved.key and bg.component.visible and not bg.component.hidden
                    and spriteID(bg.component) == art.tabSelected then another = true; break end
            end
            if not another then saved.component[saved.field] = saved.original end
        end
    end
    group.artwork = nil
end

local function hideSeams(group)
    for _, host in ipairs(group.hosts) do
        if host.seam and not host.seam.hidden then host.seam.hidden = true end
    end
end

local function nativePage(group)
    hideSeams(group)
    restoreArtwork(group)
    for _, host in ipairs(group.hosts) do
        for _, saved in ipairs(host.flags) do restoreFlag(group, saved) end
        if host.nativeTab then host.nativeTab.background.spriteID = art.tabUnselected end
    end
    group.active, group.pending, group.needsConceal = nil, nil, nil
end

local function borrow(group, host)
    if group.artwork then return end
    local chosen
    for _, bg in ipairs(host.backgrounds) do
        if bg.component.visibleGlobal and not bg.component.hidden
            and spriteID(bg.component) == art.tabSelected then
            if chosen then return end -- native artwork is not an own-page prerequisite
            chosen = bg
        end
    end
    if not chosen then return end -- the native getter need not reflect the painted page
    local saved = { component = chosen.component, key = chosen.key, field = chosen.field,
        original = art.tabSelected, host = host }
    group.artwork = saved -- before a setter that can partially apply
    chosen.component[chosen.field] = art.tabUnselected -- NOT .sprite (fails to paint native tabs)
    if chosen.component[chosen.field] ~= art.tabUnselected then error("native editor-field write failed") end
end

local function ownSprite(parent, resource)
    local item = Components.new(ui.Sprite, parent)
    item.spriteID, item.clickthrough = resource, true
    return item
end

local function releaseTab(tab)
    if tab.tooltipAttachment then tab.tooltipAttachment:Hide() end
    Tooltip.unbind(tab, "tooltipAttachment")
    if tab.hit and ui.Interfaces:GetInterface(tab.interfaceID) then tab.hit:Destroy() end
    tab.hit, tab.retained, tab.dragOwner = nil, nil, nil
end

local Tab = {}
Tab.__index = Tab
Tab.Release = releaseTab

local function destroyTab(tab)
    if tab.visual and ui.Interfaces:GetInterface(tab.frameID) then tab.visual:Destroy() end
    tab.visual = nil
    if tab.retained then
        -- The drag gesture owns the enlarged GAME_AREA capture until release.
        if tab.tooltipAttachment then tab.tooltipAttachment:Hide() end
        Tooltip.unbind(tab, "tooltipAttachment")
    else
        tab:Release()
    end
end

local function makeVisual(tab, host, icon)
    tab.host, tab.frameID = host, host.owner
    tab.visual = Components.new(ui.Layer, host.chrome, { _categoryPolicy = "auto" })
    tab.visual:SetSize(WIDTH, HEIGHT)
    tab.visual.clickthrough = true
    tab.background = ownSprite(tab.visual, art.tabUnselected)
    tab.background:SetSize(WIDTH, HEIGHT)
    local iconSprite = ownSprite(tab.visual, icon)
    iconSprite:SetPos(8, 2)
    iconSprite:SetSize(24, 24)
end

local function newTab(group, host, panel, icon, native)
    local tab = setmetatable({ member = panel, frameID = host.owner,
        interfaceID = panel.interfaceID, host = host, group = group, native = native }, Tab)
    group.constructingTab = tab
    makeVisual(tab, host, icon)
    tab.hit = Components.new(ui.Layer, panel.parent, {
        _categoryPolicy = Components.policyOf(panel.root),
    })
    tab.hit:SetSize(WIDTH, HEIGHT)
    tab.hit.clickthrough = false
    tab.hit.hidden, tab.hit.enabled = true, false
    Cursor.apply(tab.hit, nil, false)
    if native then
        tab.hit:Subscribe(ui.Hook.ONCLICK, function()
            local ok, problem = pcall(function()
                nativePage(group)
                Native.sync(panel)
            end)
            if not ok then group.failure = problem end
            return false
        end)
    else
        tab.hit:Subscribe(ui.Hook.ONCLICK, function(component, x, y)
            local actor = tab.dragOwner or panel
            local ok, problem = pcall(function()
                actor:_BeginNativeTabDrag(component, x, y, tab)
                Native.select(panel)
            end)
            if not ok then group.failure = problem end
            return false
        end)
        local function move(component, x, y)
            local actor = tab.dragOwner or panel
            local ok, problem = pcall(function() actor:_MoveNativeTabDrag(component, x, y) end)
            if not ok then group.failure = problem end
            return false
        end
        tab.hit:Subscribe(ui.Hook.ONHOLD, move)
        tab.hit:Subscribe(ui.Hook.ONDRAG, move)
        local function stop(component, x, y)
            local actor = tab.dragOwner or panel
            local ok, problem = pcall(function() actor:_StopNativeTabDrag(component, x, y) end)
            if not ok then group.failure = problem end
            return false
        end
        tab.hit:Subscribe(ui.Hook.ONRELEASE, stop)
        tab.hit:Subscribe(ui.Hook.ONDRAGCOMPLETE, function(component, _, x, y)
            return stop(component, x, y)
        end)
        Tooltip.bind(tab, tab.hit, panel.parent, {
            text = panel.tabText or "Panel", placement = "above", placementFallback = false,
        }, "tooltipAttachment")
    end
    group.constructingTab = nil
    return tab
end

local function alignTab(tab, x, y, show)
    if not tab.visual then return end
    if tab.visual.x ~= x or tab.visual.y ~= y then tab.visual:SetPos(x, y) end
    if tab.visual.hidden == show then tab.visual.hidden = not show end
    local hit = tab.hit
    if hit and not tab.retained then
        local tx, ty = rectInParent(tab.member or tab.group.members[1], tab.host.frame)
        tx, ty = tx + x, ty + y
        if hit.x ~= tx or hit.y ~= ty then hit:SetPos(tx, ty) end
        if hit.hidden == show then hit.hidden = not show end
        if hit.enabled ~= show then hit.enabled = show end
        if show and not tab.shown then hit:MoveToFront() end
        tab.shown = show
    end
end

local function cancelScrollCapture(scroll)
    if not scroll then return end
    if scroll.dragStart and scroll.thumbDrag then
        InterfaceMouse.EndCapture(scroll.thumbDrag)
        scroll.dragStart = nil
        scroll.thumbCaptureExpanded = false
        scroll.thumbDrag.hidden = true
    end
    for child in pairs(scroll.childScrolls or {}) do cancelScrollCapture(child) end
end

local function suspend(group)
    group.transient = true
    for _, panel in ipairs(group.members) do
        local binding = group.bindings[panel]
        for _, tab in ipairs(binding.tabs) do
            if tab.visual then alignTab(tab, tab.visual.x, tab.visual.y, false) end
        end
        if panel.root and ui.Interfaces:GetInterface(panel.interfaceID) then
            if not panel.root.hidden or panel.root.enabled ~= false then
                cancelScrollCapture(panel._scroll)
                panel.root.hidden, panel.root.enabled = true, false
                if panel.content then Tooltip.hideContextTooltips(panel.content) end
                if panel._scroll then panel._scroll:_RefreshClipTargets() end
                panel:_SyncChrome()
                panel:_SyncOverlays(true)
            end
            binding.visible = false
        end
    end
    for _, host in ipairs(group.hosts) do
        if host.nativeTab and host.nativeTab.visual then
            alignTab(host.nativeTab, host.nativeTab.visual.x, host.nativeTab.visual.y, false)
        end
        if host.seam and not host.seam.hidden then host.seam.hidden = true end
        if host.chrome and not host.chrome.hidden then host.chrome.hidden = true end
    end
end

local function align(group)
    local current = selectedFrame(group)
    if not current then error("native group has no unique visible frame") end
    for i, host in ipairs(group.hosts) do
        local show = i == current
        local band = tabBand(host)
        local chrome = host.chrome
        local x, y, width, height = rectInParent(group.members[1], host.frame)
        if chrome.x ~= x or chrome.y ~= y then chrome:SetPos(x, y) end
        if chrome.width ~= width or chrome.height ~= height then chrome:SetSize(width, height) end
        if chrome.hidden == show then chrome.hidden = not show end
        if host.tabBuffer then
            if host.tabBuffer.x ~= band.x or host.tabBuffer.y ~= band.y then
                host.tabBuffer:SetPos(band.x, band.y)
            end
            if host.tabBuffer.width ~= band.width then host.tabBuffer:SetSize(band.width, HEIGHT - SEAM) end
        end
        if host.nativeTab then
            alignTab(host.nativeTab, band.x, band.y, show)
            local nativeSprite = (not group.active and show) and art.tabSelected or art.tabUnselected
            if host.nativeTab.background.spriteID ~= nativeSprite then
                host.nativeTab.background.spriteID = nativeSprite
            end
        end
        if host.divider then
            local dx, dy = band.x, band.y + HEIGHT - SEAM
            if host.divider.x ~= dx or host.divider.y ~= dy then host.divider:SetPos(dx, dy) end
            if host.divider.width ~= band.width then host.divider:SetSize(band.width, SEAM) end
        end
        for index, panel in ipairs(group.members) do
            local tab = group.bindings[panel].tabs[i]
            alignTab(tab, band.x + host.used + (index - 1) * WIDTH, band.y, show)
            local selected = show and group.active == panel
            local value = selected and art.tabSelected or art.tabUnselected
            if tab.background.spriteID ~= value then tab.background.spriteID = value end
        end
        local seam = host.seam
        if seam then
            local selected = show and group.active ~= nil
                and group.artwork ~= nil and group.artwork.host == host
            if selected then
                local bg = group.artwork.component
                local x, y = host.tabs.x + bg.x, host.tabs.y + HEIGHT - SEAM
                if seam.x ~= x or seam.y ~= y then seam:SetPos(x, y) end
                if seam.width ~= bg.width or seam.height ~= SEAM then seam:SetSize(bg.width, SEAM) end
            end
            if seam.hidden == selected then seam.hidden = not selected end
        end
    end
    group.current = current
    local host = group.hosts[current]
    for _, panel in ipairs(group.members) do
        local binding = group.bindings[panel]
        if panel.root and ui.Interfaces:GetInterface(panel.interfaceID) then
            local x, y, width, height = rectInParent(panel, host.content)
            if not group.grouped then y, height = y + HEIGHT, height - HEIGHT end
            local changed = panel.root.x ~= x or panel.root.y ~= y
                or panel.root.width ~= width or panel.root.height ~= height
            if changed or binding.visible == nil then
                local old = panel._updatingBounds
                panel._updatingBounds = true
                local ok, problem = pcall(function()
                    panel.root:SetPos(x, y)
                    panel.root:SetSize(width, height)
                    panel.width, panel.height = width, height
                    panel:_LayoutBody()
                    panel:RefreshRowBackgrounds()
                end)
                panel._updatingBounds = old
                if not ok then error(problem) end
            end
            local visible = group.active == panel and panel._nisHidden ~= true
            local visibilityChanged = binding.visible ~= visible or panel.root.hidden == visible
                or panel.root.enabled ~= visible
            if visibilityChanged then
                if not visible then cancelScrollCapture(panel._scroll) end
                panel.root.hidden, panel.root.enabled = not visible, visible
                if not visible and panel.content then Tooltip.hideContextTooltips(panel.content) end
                if panel._scroll then panel._scroll:_RefreshClipTargets() end
            end
            if changed or visibilityChanged then
                panel:_SyncChrome()
                panel:_SyncOverlays(not visible)
            end
            binding.visible = visible
            binding.current = current
        end
    end
end

local function raiseGroup(group)
    local host = group.hosts[group.current]
    host.chrome:MoveToFront()
    if group.active then
        group.active.root:MoveToFront()
        group.active:_SyncOverlays(false)
    end
    local function raiseTab(tab)
        if tab and tab.shown and tab.hit and not tab.retained then tab.hit:MoveToFront() end
    end
    raiseTab(host.nativeTab)
    for _, panel in ipairs(group.members) do
        raiseTab(group.bindings[panel].tabs[group.current])
    end
end

local function subscribeHost(group, component)
    local key = identity(component)
    if not key then return end
    local hook = group.hookKeys[key]
    if hook then
        if hook.component ~= component then
            hook.component:Unsubscribe(ui.Hook.ONCLICK, group.hookID)
            hook.component = component
            component:Subscribe(ui.Hook.ONCLICK, group.hookID, hook.callback)
        end
        return
    end
    hook = { component = component, key = key }
    group.hookKeys[key] = hook
    group.hooks[#group.hooks + 1] = hook -- before partially successful Subscribe
    hook.callback = function()
        local ok, problem = pcall(function()
            if not group.dead and #group.members > 0 and selectedFrame(group) then
                group.pending = true
                hideSeams(group) -- immediate, before native script/listener processing
                restoreArtwork(group)
            end
        end)
        if not ok then group.failure = problem end
        return true -- never intercept original native listeners/scripts
    end
    component:Subscribe(ui.Hook.ONCLICK, group.hookID, hook.callback)
end

local function createHost(group, host, chrome)
    host.flags = {}
    host.chrome = chrome or Components.new(ui.Layer, group.area, { _categoryPolicy = "auto" })
    if not chrome then
        host.chrome.clickthrough, host.chrome.enabled, host.chrome.hidden = true, false, true
    end
    local edit = component(host.spec.EDIT_BLOCK)
    if edit and not same(edit.parent, host.frame) then
        error("native edit layer is outside its frame")
    end
    local function remember(comp)
        if comp then
            host.flags[#host.flags + 1] = {
                component = comp, key = identity(comp), hidden = comp.hidden,
            }
        end
    end
    if group.nativeRoots then
        for _, saved in ipairs(group.nativeRoots) do remember(saved.component) end
    else
        remember(host.content)
    end
    remember(host.scroll)
    remember(edit)
    subscribeHost(group, host.tabs)
    for _, child in ipairs(host.children) do subscribeHost(group, child) end
    if group.grouped then
        host.seam = Components.new(ui.Sprite, host.chrome, { _categoryPolicy = "auto" })
        host.seam.spriteID = art.tabBarTile
        host.seam.isTiling = true
        host.seam.enabled, host.seam.clickthrough, host.seam.hidden = false, true, true
    else
        host.tabBuffer = ownSprite(host.chrome, art.tabBufferTile)
        host.tabBuffer:SetSize(tabBand(host).width, HEIGHT - SEAM)
        host.tabBuffer.isTiling = true
        host.divider = Components.new(ui.Sprite, host.chrome, { _categoryPolicy = "auto" })
        host.divider.spriteID = art.tabBarTile
        host.divider.isTiling = true
        host.divider.enabled, host.divider.clickthrough = false, true
        -- The native-page input is created after the first member supplies a
        -- GAME_AREA parent. No client-hidden native tab strip is revealed.
    end
end

local function releaseObservers(group)
    for _, hook in ipairs(group.hooks) do
        if not hook.removed then
            if live(group) and identity(hook.component) == hook.key then
                hook.component:Unsubscribe(ui.Hook.ONCLICK, group.hookID)
            end
            hook.removed = true
        end
    end
    group.hooks, group.hookKeys = {}, {}
end

local function matchingHost(a, b)
    if a.key ~= b.key or a.owner ~= b.owner or a.grouped ~= b.grouped
        or a.signature ~= b.signature or a.used ~= b.used
        or a.nativeIcon ~= b.nativeIcon
        or not same(a.content, b.content) or not same(a.scroll, b.scroll)
        or not same(a.tabs, b.tabs) or not same(a.backdrop, b.backdrop)
        or #a.backgrounds ~= #b.backgrounds or #a.children ~= #b.children then return false end
    for i, bg in ipairs(a.backgrounds) do
        if bg.key ~= b.backgrounds[i].key then return false end
    end
    for i, child in ipairs(a.children) do
        if not same(child, b.children[i]) then return false end
    end
    return true
end

-- Equal public IDs establish membership, not a native object's lifetime.
-- Always adopt the current lookup handles, including unchanged-ID rebuilds.
local function refreshHost(group, host, current)
    for _, field in ipairs({ "frame", "content", "scroll", "tabs", "backdrop",
        "backgrounds", "children" }) do host[field] = current[field] end
    local roots = group.nativeRoots
    if roots and host.spec.name == "TOPLEVEL_V2__LORE_WINDOW" then
        local currentRoots = familiarRootsFor(host, roots)
        if not currentRoots then error("unrecognized familiar page layout") end
        local unavailable = component(host.spec.EDIT_BLOCK).visible == true
        local availabilityChanged = group.familiarUnavailable ~= unavailable
        group.familiarUnavailable = unavailable
        local retained = {}
        for _, saved in ipairs(currentRoots) do retained[saved.key] = true end
        for index = #host.flags, 1, -1 do
            local flag = host.flags[index]
            for _, saved in ipairs(roots) do
                if saved.key == flag.key and not retained[saved.key] then
                    -- Dismissal can unparent a still-live page rather than
                    -- unload it. Release our inset before a later remount.
                    local fresh = saved.changed and component(saved.packed)
                    if fresh and identity(fresh) == saved.key and fresh.parent == nil then
                        saved.component = fresh
                        applyLayout(fresh, saved.original)
                        fresh.hidden = saved.hidden
                        saved.changed = false
                    end
                    table.remove(host.flags, index)
                    break
                end
            end
        end
        group.nativeRoots, roots = currentRoots, currentRoots
        for _, saved in ipairs(roots) do
            if not saved.changed then
                saved.changed = true -- setters can partially apply before throwing
                applyLayout(saved.component, saved.inset)
                host.flags[#host.flags + 1] = {
                    component = saved.component, key = saved.key, hidden = saved.hidden,
                }
            elseif availabilityChanged then
                saved.baselineReset = true
            end
        end
    elseif roots then
        for _, saved in ipairs(roots) do
            local fresh = component(saved.packed)
            if not fresh or identity(fresh) ~= saved.key or not same(fresh.parent, host.content) then
                error("native content root retired")
            end
            saved.component = fresh
        end
    end
    local edit = component(host.spec.EDIT_BLOCK)
    for _, saved in ipairs(host.flags) do
        local fresh
        if roots then
            for _, root in ipairs(roots) do
                if saved.key == root.key then fresh = root.component; break end
            end
        end
        if not fresh then
            if saved.key == identity(host.content) then fresh = host.content
            elseif saved.key == identity(host.scroll) then fresh = host.scroll
            elseif saved.key == identity(edit) then fresh = edit end
        end
        if not fresh then error("native concealment component retired") end
        saved.component = fresh
    end
    local artwork = group.artwork
    if artwork and artwork.host == host then
        for _, bg in ipairs(host.backgrounds) do
            if bg.key == artwork.key then artwork.component = bg.component; break end
        end
    end
    subscribeHost(group, host.tabs)
    for _, child in ipairs(host.children) do subscribeHost(group, child) end
end

-- A former frame identity anchors the group. Rectangles and matching tab
-- art alone cannot confer ownership of an unrelated native window.
local function reconcile(group)
    if not live(group) then error("native interface retired") end
    local open = false
    for _, host in ipairs(group.hosts) do
        local frame = component(host.spec.frame)
        if frame and frame.visible ~= false and not frame.hidden
            and same(frame.parent, group.area) then open = true; break end
    end
    if not open then error("native group closed") end
    local found = discover(group.area)
    local previous = {}
    for _, host in ipairs(group.hosts) do previous[host.key] = host end
    local anchor
    local preferred = group.hosts[group.current]
    for _, host in ipairs(found) do
        if previous[host.key] and host.grouped == group.grouped
            and host.frame.visibleGlobal then anchor = host; break end
    end
    if not anchor then
        for _, host in ipairs(found) do
            if previous[host.key] and host.key == preferred.key
                and host.grouped == group.grouped then anchor = host; break end
        end
    end
    if not anchor then
        for _, host in ipairs(found) do
            if previous[host.key] and host.grouped == group.grouped then anchor = host; break end
        end
    end
    if not anchor or anchor.grouped ~= group.grouped then
        if not selectedFrame(group) then
            for _, host in ipairs(group.hosts) do
                local frame = component(host.spec.frame)
                if frame and same(frame.parent, group.area) then return nil end
            end
        end
        error("native host closed or changed to an unsupported arrangement")
    end
    local hosts = {}
    for _, host in ipairs(found) do
        if related(anchor, host) then
            if byFrame[host.key] and byFrame[host.key] ~= group then
                error("native host belongs to another docked group")
            end
            hosts[#hosts + 1] = host
        end
    end
    if group.grouped and #hosts == 1 and #group.hosts > 1 then
        -- Frame copies rebuilt at different moments still share their native
        -- geometry; wait for their tab signatures to agree before adopting them.
        for _, other in ipairs(found) do
            if previous[other.key] and other.key ~= anchor.key and other.grouped
                and other.owner == anchor.owner
                and other.frame.x == anchor.frame.x and other.frame.y == anchor.frame.y
                and other.frame.width == anchor.frame.width
                and other.frame.height == anchor.frame.height
                and other.tabs.x == anchor.tabs.x and other.tabs.y == anchor.tabs.y
                and other.tabs.width == anchor.tabs.width
                and other.content.y == anchor.content.y then return nil end
        end
        if not selectedFrame(group) then return nil end
    end
    local changed = #hosts ~= #group.hosts
    if not changed then
        for i, host in ipairs(hosts) do
            if not matchingHost(group.hosts[i], host) then changed = true; break end
        end
    end
    if not changed then
        for i, host in ipairs(hosts) do refreshHost(group, group.hosts[i], host) end
        return false
    end

    local active, savedFlags, oldTabs = group.active, {}, {}
    restoreArtwork(group)
    for _, host in ipairs(group.hosts) do
        for _, flag in ipairs(host.flags) do
            if flag.key then savedFlags[flag.key] = flag.hidden end
            restoreFlag(group, flag)
        end
    end
    releaseObservers(group)
    for _, panel in ipairs(group.members) do
        local tabs = {}
        for i, host in ipairs(group.hosts) do tabs[host.key] = group.bindings[panel].tabs[i] end
        oldTabs[panel] = tabs
    end
    local nativeTabs = {}
    for _, host in ipairs(group.hosts) do
        byFrame[host.key] = nil
        nativeTabs[host.key] = host.nativeTab
        for _, key in ipairs({ "tabBuffer", "seam", "divider" }) do
            if host[key] and live(group) then host[key]:Destroy() end
        end
    end
    group.current = nil
    group.hosts = hosts
    for i, host in ipairs(hosts) do
        byFrame[host.key] = group
        if host.key == preferred.key then group.current = i end
        createHost(group, host, previous[host.key] and previous[host.key].chrome)
        for _, flag in ipairs(host.flags) do
            if flag.key and savedFlags[flag.key] ~= nil then flag.hidden = savedFlags[flag.key] end
        end
    end
    group.current = group.current or selectedFrame(group) or 1
    for _, panel in ipairs(group.members) do
        local binding, tabs = group.bindings[panel], oldTabs[panel]
        local updated = {}
        for i, host in ipairs(hosts) do
            local tab = tabs[host.key]
            if tab then
                if tab.visual and live(group) then tab.visual:Destroy() end
                makeVisual(tab, host, panel.tabIcon or art.defaultIcon)
                tabs[host.key] = nil
            else
                tab = newTab(group, host, panel, panel.tabIcon or art.defaultIcon, false)
            end
            updated[i] = tab
        end
        binding.tabs = updated
        for _, tab in pairs(tabs) do destroyTab(tab) end
    end
    for _, host in ipairs(hosts) do
        local tab = nativeTabs[host.key]
        if tab then
            if tab.visual and live(group) then tab.visual:Destroy() end
            makeVisual(tab, host, host.nativeIcon)
            host.nativeTab = tab
            nativeTabs[host.key] = nil
        elseif not group.grouped then
            host.nativeTab = newTab(group, host, group.members[1], host.nativeIcon, true)
        end
    end
    for _, tab in pairs(nativeTabs) do destroyTab(tab) end
    for key, oldHost in pairs(previous) do
        if byFrame[key] ~= group and oldHost.chrome and live(group) then oldHost.chrome:Destroy() end
    end
    if active and not group.pending then
        local current = selectedFrame(group)
        if current then
            local host = hosts[current]
            if group.grouped then borrow(group, host) end
            conceal(group, host)
            group.needsConceal = nil
        else
            group.needsConceal = true
        end
    end
    return true
end

local function moveActive(group, current)
    restoreArtwork(group)
    for _, host in ipairs(group.hosts) do
        for _, flag in ipairs(host.flags) do restoreFlag(group, flag) end
    end
    local host = group.hosts[current]
    if group.grouped then borrow(group, host) end
    conceal(group, host)
    group.needsConceal = nil
end

local function reconcilePage(group, current)
    if not group.active then return false end
    local host, artwork = group.hosts[current], group.artwork
    if artwork and (artwork.host ~= host or artwork.component[artwork.field] ~= art.tabUnselected) then
        restoreArtwork(group)
    end
    if group.grouped and not group.artwork then borrow(group, host) end
    -- Native repaint is not native selection. Only observed input/frame
    -- selection relinquishes the own page; changed flags/art repair once.
    local changed = conceal(group, host)
    return changed or artwork ~= group.artwork
end

-- Locking is a native chrome/layout transition, not a request to select a
-- native page. Reconcile its one-off repaint without a per-tick paint fight.
local function reconcileLock(group, current)
    if not group.lockTransition then return end
    if group.active then
        local host = group.hosts[current]
        if current ~= group.current then
            moveActive(group, current)
        else
            local saved = group.artwork
            if saved and (saved.host ~= host or saved.component[saved.field] ~= art.tabUnselected) then
                restoreArtwork(group)
            end
            if group.grouped and not group.artwork then borrow(group, host) end
            conceal(group, host)
            group.needsConceal = nil
        end
    end
    group.lockTransition = nil
    return true
end

local function sameLayout(first, second)
    if not first then return false end
    for index = 1, 10 do
        if first[index] ~= second[index] then return false end
    end
    return true
end

local function reconcileRoots(group)
    local changed = false
    if not group.nativeRoots then return changed end
    for _, saved in ipairs(group.nativeRoots) do
        if saved.changed then
            local actual = layout(saved.component)
            if not actual then error("native content layout retired") end
            if not sameLayout(actual, saved.inset) then
                if not saved.baselineReset or not sameLayout(actual, saved.original) then
                    error("native script overwrote tab inset")
                end
                local parent, expected = saved.component.parent, saved.inset
                if parent.width * expected[9] + expected[7] <= 0
                    or parent.height * expected[10] + expected[8] <= 0 then
                    error("native content root resized below its bounds")
                end
                -- One baseline reset per lock/familiar-availability transition.
                -- Keep the allowance across idle ticks for deferred reflow.
                saved.baselineReset = nil
                applyLayout(saved.component, expected)
                if not sameLayout(layout(saved.component), expected) then
                    error("native reflow did not retain tab inset")
                end
                changed = true
            end
            if saved.component.width <= 0 or saved.component.height <= 0 then
                error("native content root resized below its bounds")
            end
        end
    end
    return changed
end

local function saveGroup(group)
    if restoring or group.attaching then return end
    local frames = {}
    for _, host in ipairs(group.hosts) do frames[#frames + 1] = host.spec.name end
    table.sort(frames)
    for index, panel in ipairs(group.members) do
        if not panel._nisNativeTransaction then
            Persistence.native(panel, {
                frame = group.hosts[group.current].spec.name, frames = frames,
                index = index, selected = group.active == panel,
                free = group.bindings[panel].free,
            })
        end
    end
end

local function stopTick()
    if subscribed and #groups == 0 and next(pending) == nil then
        Event.Logic.Unsubscribe(EVENT_ID)
        subscribed = false
    end
end

local function removeGroup(group)
    group.dead = true
    for _, host in ipairs(group.hosts) do byFrame[host.key] = nil end
    for index, member in ipairs(groups) do
        if member == group then table.remove(groups, index); break end
    end
    stopTick()
end

local function finishGroup(group)
    local failed
    local function attempt(callback)
        local ok, problem = pcall(callback)
        if not ok then failed = failed or problem end
    end
    if group.constructingTab then
        attempt(function() destroyTab(group.constructingTab); group.constructingTab = nil end)
    end
    attempt(function() nativePage(group) end)
    attempt(function() releaseObservers(group) end)
    if group.nativeRoots then
        for _, saved in ipairs(group.nativeRoots) do
            if saved.changed then
                attempt(function()
                    if live(group) and identity(saved.component) == saved.key
                        and ui.Interfaces:GetInterface(saved.owner) ~= nil then
                        applyLayout(saved.component, saved.original)
                        saved.component.hidden = saved.hidden
                    end
                    saved.changed = false
                end)
            end
        end
    end
    for _, host in ipairs(group.hosts) do
        if host.nativeTab then attempt(function() destroyTab(host.nativeTab); host.nativeTab = nil end) end
        for _, key in ipairs({ "tabBuffer", "seam", "divider", "chrome" }) do
            local owned = host[key]
            if owned then
                attempt(function()
                    if live(group) then owned:Destroy() end
                    host[key] = nil
                end)
            end
        end
    end
    if failed then
        group.failure = failed
        warn(failed)
        return false
    end
    removeGroup(group)
    return true
end

local function tick()
    for panel in pairs(pending) do
        if not panel._nisNativePending or panel._destroyed or not panel.root
            or not ui.Interfaces:GetInterface(panel.interfaceID) then
            pending[panel] = nil
        elseif not panel.dragState and not panel._nisTabPress
            and not (panel.resize and panel.resize.dragState) then
            restorePending(panel)
        end
    end
    stopTick()
    -- Reconcile one shared group at a time; native clients own frame geometry.
    for index = #groups, 1, -1 do
        local group = groups[index]
        if not group.dead and #group.members > 0 then
            local ok, problem = pcall(function()
                local changed = reconcile(group)
                if changed == nil then suspend(group); return end
                for _, host in ipairs(group.hosts) do
                    if not validHost(group, host) then error("native host resized out of capacity or retired") end
                    local height = host.content.height - (group.grouped and 0 or HEIGHT)
                    for _, panel in ipairs(group.members) do
                        if host.content.width < panel.minWidth or height < panel.minHeight
                            or host.content.width > (panel.maxWidth or math.huge)
                            or height > (panel.maxHeight or math.huge) then
                            error("native host resized outside the panel's limits")
                        end
                    end
                end
                local current = selectedFrame(group)
                local selectionChanged = group.pending or current ~= group.current
                if group.pending then nativePage(group) end
                if current then
                    if group.active and (group.needsConceal
                        or not changed and group.transient and current ~= group.current) then
                        moveActive(group, current)
                    elseif not changed and current ~= group.current and not group.lockTransition then
                        nativePage(group)
                    end
                    group.transient = nil
                    local rootReflow = reconcileRoots(group)
                    local lockReflow = reconcileLock(group, current)
                    local repainted = reconcilePage(group, current)
                    if group.failure then error(group.failure) end
                    align(group)
                    if lockReflow or repainted or rootReflow then raiseGroup(group) end
                    if changed or selectionChanged then saveGroup(group) end
                else
                    suspend(group)
                end
            end)
            if not ok then
                warn(problem)
                local members = { table.unpack(group.members) }
                for _, panel in ipairs(members) do Native.detach(panel) end
                if not group.dead and #group.members == 0 then finishGroup(group) end
            end
        end
    end
end

local function startTick()
    if subscribed then return end
    Event.Logic.Subscribe(EVENT_ID, function()
        local ok, problem = pcall(tick)
        if not ok then warn(problem) end
    end)
    subscribed = true
end

local function buildGroup(host, area)
    local found = discover(area)
    local hosts = {}
    for _, other in ipairs(found) do
        if related(host, other) then
            if byFrame[other.key] then return nil end
            hosts[#hosts + 1] = other
        end
    end
    if #hosts == 0 then return nil end
    local current
    for i, item in ipairs(hosts) do
        if item.frame.visibleGlobal then
            if current then return nil end
            current = i
        end
    end
    if not current then return nil end
    local group = { area = area, owner = host.owner,
        hosts = hosts, members = {}, bindings = {}, hooks = {}, hookKeys = {},
        grouped = host.grouped, current = current }
    if not host.grouped then
        group.nativeRoots = nativeRootsFor(host)
        if not group.nativeRoots then return nil end
        if host.spec.name == "TOPLEVEL_V2__LORE_WINDOW" then
            group.familiarUnavailable = component(host.spec.EDIT_BLOCK).visible == true
        end
    end
    return group
end

local function abandonMember(group, panel)
    local binding = group.bindings[panel]
    if not binding then return end
    for _, tab in ipairs(binding.tabs) do destroyTab(tab) end
    group.bindings[panel] = nil
    for index, member in ipairs(group.members) do
        if member == panel then table.remove(group.members, index); break end
    end
    panel._nisNative = nil
    local nativeOK, nativeError = true, nil
    if group.active == panel then nativeOK, nativeError = pcall(nativePage, group) end
    if panel.root and ui.Interfaces:GetInterface(panel.interfaceID) then
        local rect = binding.free
        panel.root:SetPos(rect.x, rect.y)
        panel.root:SetSize(rect.width, rect.height)
        panel.width, panel.height = rect.width, rect.height
        panel.root.hidden, panel.root.enabled = panel._nisHidden == true, true
        if panel.dragBounds then
            panel.dragBounds:Clamp()
            panel.dragBounds:RememberPosition()
        end
        if panel._scroll then panel._scroll:_RefreshClipTargets() end
        panel:_LayoutBody()
        panel:RefreshRowBackgrounds()
        if not panel.root.hidden then panel.root:MoveToFront() end
        panel:_SyncChrome()
        panel:_SyncOverlays(panel.root.hidden)
        panel:_NotifyBoundsChange()
    end
    if not nativeOK then error(nativeError) end
end

function Native.detach(panel)
    if panel and not restoring then
        panel._nisNativePending, pending[panel] = nil, nil
        stopTick()
    end
    local binding = panel and panel._nisNative
    if not binding then return false end
    local group = binding.group
    panel._nisNativeDetaching = true
    local ok, problem = pcall(abandonMember, group, panel)
    panel._nisNativeDetaching = nil
    if not ok then warn(problem); group.failure = problem; return false end
    if #group.members == 0 then return finishGroup(group) end
    for _, host in ipairs(group.hosts) do
        if host.nativeTab then host.nativeTab.member = group.members[1] end
    end
    if selectedFrame(group) then
        local valid, issue = pcall(align, group)
        if not valid then warn(issue); group.failure = issue end
        return valid
    end
    return true
end
local function attach(panel, group, free)
    local binding = { group = group, free = free or freeRect(panel), tabs = {} }
    if #group.members == 0 then group.locked = panel.locked end
    group.members[#group.members + 1] = panel
    group.bindings[panel] = binding
    panel._nisNative = binding
    for index, host in ipairs(group.hosts) do
        binding.tabs[index] = newTab(group, host, panel, panel.tabIcon or art.defaultIcon, false)
    end
    if not group.grouped and #group.members == 1 then
        for _, host in ipairs(group.hosts) do
            host.nativeTab = newTab(group, host, panel, host.nativeIcon, true)
        end
    end
    return binding
end

local function dock(panel, target, savedFree)
    if not panel or panel._nisNative or panel.locked and not restoring or not panel.root
        or not ui.Interfaces:GetInterface(panel.interfaceID) then return false end
    local area = component(id.Component.TOPLEVEL_V2__GAME_AREA)
    if not area then return false end
    if not same(panel.parent, area) then return false end
    indexSpecs()
    local key = resolve(target)
    local spec = specByID[key]
    if not spec then return false end
    local okCapture, host = pcall(capture, spec, area, true)
    if not okCapture or not host or not host.frame.visibleGlobal then return false end
    local group = frameGroup(host)
    if group and (group.failure or not live(group) or group.grouped ~= host.grouped) then return false end
    if group then
        local refreshed, settled = pcall(reconcile, group)
        if not refreshed or settled == nil or group.failure or not byFrame[host.key] then return false end
    end
    if not group and (host.content.hidden or host.scroll and host.scroll.hidden) then return false end
    if not group then group = buildGroup(host, area) end
    if not group then return false end
    local members = panel._nisGroup and { table.unpack(panel._nisGroup.members) } or { panel }
    for _, member in ipairs(members) do
        if member._nisNative or member.locked and not restoring or member._nisHidden
            or not member.root or not same(member.parent, panel.parent)
            or not ui.Interfaces:GetInterface(member.interfaceID) then return false end
    end
    for _, item in ipairs(group.hosts) do
        if item.used + (#group.members + #members) * WIDTH > tabBand(item).width then return false end
        local height = item.content.height - (group.grouped and 0 or HEIGHT)
        for _, member in ipairs(members) do
            if item.content.width < member.minWidth or height < member.minHeight
                or item.content.width > (member.maxWidth or math.huge)
                or height > (member.maxHeight or math.huge) then return false end
        end
    end
    local oldGroup = NisGroup.snapshot(panel)
    local frees = {}
    for index, member in ipairs(members) do frees[index] = member == panel and savedFree or freeRect(member) end
    local created = #group.members == 0
    group.attaching = true
    local success, problem = pcall(function()
        if created then
            nextHook = nextHook + 1
            group.hookID = "prettyui_nis_native_" .. nextHook
            groups[#groups + 1] = group
            for _, item in ipairs(group.hosts) do
                byFrame[item.key] = group
                item.flags = {} -- cleanup is valid even before chrome construction
            end
            if group.nativeRoots then
                for _, saved in ipairs(group.nativeRoots) do
                    saved.changed = true -- setters can partially apply before throwing
                    applyLayout(saved.component, saved.inset)
                end
            end
            for _, item in ipairs(group.hosts) do createHost(group, item) end
        end
        for index, member in ipairs(members) do
            if member._nisGroup then NisGroup.undock(member) end
            if not restoring then Persistence.detach(member) end
            attach(member, group, frees[index])
        end
        if not subscribed then startTick() end
        align(group)
        assert(Native.select(panel), "native page selection failed")
    end)
    group.attaching = nil
    if not success then
        if group.constructingTab then
            local cleanupOK, cleanupError = pcall(destroyTab, group.constructingTab)
            if not cleanupOK then warn(cleanupError) end
            group.constructingTab = nil
        end
        warn(problem)
        for _, member in ipairs(members) do
            if member._nisNative and member._nisNative.group == group then Native.detach(member) end
        end
        if created and #group.members == 0 and not group.dead then finishGroup(group) end
        if oldGroup then NisGroup.restore(oldGroup, false) end
        return false
    end
    saveGroup(group)
    return true
end

function Native.dock(panel, target, savedFree)
    return dock(panel, target, savedFree)
end

-- Rebind by named host identity once the native layout is available. Startup
-- restoration is allowed while locked; explicit docking still is not.
restorePending = function(panel)
    local snapshot = panel._nisNativePending
    if not snapshot or panel._nisHidden or panel._nisGroup then return end
    restoring = true
    local ok, restored = pcall(function()
        local targets = { snapshot.frame }
        for _, name in ipairs(snapshot.frames) do
            if name ~= snapshot.frame then targets[#targets + 1] = name end
        end
        for _, name in ipairs(targets) do
            local target = component(id.Component[name])
            if target and target.visibleGlobal then
                local previous = byFrame[identity(target)]
                local active = previous and previous.active
                if dock(panel, target, snapshot.free) then
                    local binding = panel._nisNative
                    local group = binding.group
                    binding.restoreIndex = snapshot.index
                    table.sort(group.members, function(a, b)
                        return (group.bindings[a].restoreIndex or math.huge)
                            < (group.bindings[b].restoreIndex or math.huge)
                    end)
                    if snapshot.selected then
                        Native.select(panel)
                    elseif active then
                        Native.select(active)
                    else
                        nativePage(group)
                        align(group)
                    end
                    return true
                end
            end
        end
        return false
    end)
    restoring = false
    if ok and restored then
        panel._nisNativePending, pending[panel] = nil, nil
    elseif not ok then
        warn(restored)
    end
end

function Native.register(panel)
    if not panel._nisNativePending then return end
    pending[panel] = true
    startTick()
    restorePending(panel)
end

function Native.lockChanged(panel, locked)
    local binding = panel._nisNative
    if not binding then return end
    local group = binding.group
    if group.locked ~= locked then
        group.locked, group.lockTransition = locked, true
        if group.nativeRoots then
            for _, saved in ipairs(group.nativeRoots) do saved.baselineReset = true end
        end
        for _, member in ipairs(group.members) do
            for _, tab in ipairs(group.bindings[member].tabs) do tab.shown = false end
        end
    end
end

function Native.select(panel)
    local binding = panel and panel._nisNative
    if not binding then return false end
    local group = binding.group
    local ok, selected = pcall(function()
        local changed = reconcile(group)
        if changed == nil then return false end
        local current = selectedFrame(group)
        if not current then return false end
        if not validHost(group, group.hosts[current]) then error("native frame unavailable") end
        reconcileRoots(group)
        if group.pending then
            nativePage(group)
        elseif group.active and (group.needsConceal
            or not changed and group.transient and current ~= group.current) then
            moveActive(group, current)
        elseif not changed and group.current ~= current and not group.lockTransition then
            nativePage(group)
        end
        group.transient = nil
        reconcileLock(group, current)
        local host = group.hosts[current]
        if not group.active then
            if group.grouped then borrow(group, host) end
            conceal(group, host)
        end
        group.active, group.current = panel, current
        reconcilePage(group, current)
        align(group)
        -- Show first; only reorder GAME_AREA siblings, never native artwork.
        raiseGroup(group)
        saveGroup(group)
        return true
    end)
    if not ok then group.failure = selected; warn(selected); return false end
    return selected
end

function Native.sync(panel)
    local binding = panel and panel._nisNative
    if not binding then return false end
    local ok, problem = pcall(function()
        local group = binding.group
        if reconcile(group) == nil then return end
        if group.pending then nativePage(group) end
        local current = selectedFrame(group)
        if not current then return end
        local rootReflow = reconcileRoots(group)
        if group.active and group.needsConceal then moveActive(group, current) end
        local lockReflow = reconcileLock(group, current)
        local repainted = reconcilePage(group, current)
        align(group)
        if lockReflow or repainted or rootReflow then raiseGroup(group) end
        saveGroup(group)
    end)
    if not ok then binding.group.failure = problem; warn(problem); return false end
    return true
end

function Native.contains(panel, x, y)
    local binding = panel and panel._nisNative
    if not binding then return false end
    local group = binding.group
    local current = selectedFrame(group)
    local host = current and group.hosts[current]
    if not host then return false end
    local band = tabBand(host)
    local origin, parentOrigin = band.xyGlobal, panel.parent.xyGlobal
    local left, top = origin.x - parentOrigin.x, origin.y - parentOrigin.y
    return x >= left and x < left + band.width and y >= top and y < top + HEIGHT
end

function Native.snapshot(panel)
    local binding = panel and panel._nisNative
    if not binding then return nil end
    local group, index = binding.group, nil
    for i, member in ipairs(group.members) do
        if member == panel then index = i; break end
    end
    local frames = {}
    for _, host in ipairs(group.hosts) do frames[#frames + 1] = host.spec.frame end
    return { frame = group.hosts[group.current].spec.frame, frames = frames, index = index,
        free = { x = binding.free.x, y = binding.free.y,
            width = binding.free.width, height = binding.free.height },
        selected = group.active == panel }
end

function Native.restore(panel, snapshot)
    if not snapshot or panel._nisNative then return false end
    if not Native.dock(panel, snapshot.frame, snapshot.free) then
        local restored = false
        for _, frame in ipairs(snapshot.frames) do
            if frame ~= snapshot.frame and Native.dock(panel, frame, snapshot.free) then
                restored = true
                break
            end
        end
        if not restored then return false end
    end
    local group = panel._nisNative.group
    if snapshot.index then
        for index, member in ipairs(group.members) do
            if member == panel then
                table.remove(group.members, index)
                table.insert(group.members, math.min(snapshot.index, #group.members + 1), panel)
                break
            end
        end
    end
    if snapshot.selected then return Native.select(panel) end
    return Native.sync(panel)
end

function Native.shutdown()
    for panel in pairs(pending) do panel._nisNativePending = nil end
    pending = {}
    local complete = true
    local existing = { table.unpack(groups) }
    for _, group in ipairs(existing) do
        local members = { table.unpack(group.members) }
        for _, panel in ipairs(members) do
            if not Native.detach(panel) then complete = false end
        end
        if not group.dead and #group.members == 0 and not finishGroup(group) then
            complete = false
        end
    end
    -- Shutdown restores native state, but keeps persisted named memberships.
    if subscribed then Event.Logic.Unsubscribe(EVENT_ID); subscribed = false end
    return complete
end

return Native
