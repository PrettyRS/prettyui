-- Native host identity, discovery, geometry and rendered-root schemas.
local Components = require("src/core/components")
local Sprites = require("src/core/sprites")
local TabLayout = require("src/nis/native_tab_layout")
local NativeInterfaceSettings = require("src/core/native_interface_settings")

local Host = {}

-- Discovery caches belong to one coordinator, including after a facade reload.
function Host.new(byFrame)
    local HEIGHT, WIDTH, SEAM, MAX_TABS = 28, 40, 4, 128
    local art = Sprites.NIS_PANEL
    local positions = { "x", "y", "xParentPc", "yParentPc", "xSelfPc", "ySelfPc" }
    local sizes = { "width", "height", "widthParentPc", "heightParentPc" }
    local specKinds = { "CONTENT", "EDIT_BLOCK", "SCROLL", "TAB_BACKGROUND", "TABS_SCROLL", "TABS" }

    local function identity(component)
        if not component then return nil end
        local a, b, c, d = component.interfaceID, component.staticID, component.categoryID, component.dynamicID
        if type(a) ~= "number" or type(b) ~= "number" or type(c) ~= "number" or type(d) ~= "number" then return nil end
        return a .. ":" .. b .. ":" .. c .. ":" .. d
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
                for _, kind in ipairs(specKinds) do
                    local base, suffix = name:match("^(.+_WINDOW)_" .. kind .. "(.*)$")
                    if base and (suffix == "" or suffix:sub(1, 1) == "_") then
                        local frameName = base .. suffix
                        local spec = specs[frameName]
                        if not spec then spec = { name = frameName }; specs[frameName] = spec end
                        spec[kind] = packed
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
    local function mapReady(group)
        if not live(group) or group.area.visibleGlobal == false then return false end
        for _, host in pairs(group.frames) do
            local frame = component(host.spec.frame)
            if frame and frame.visible ~= false and not frame.hidden
                and same(frame.parent, group.area) then return true end
        end
        return false
    end

    local function editingLocked(group)
        if group.locked or NativeInterfaceSettings.isLocked() then return true end
        for _, panel in ipairs(group.members) do
            if panel.locked then return true end
        end
        return false
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
                children[#children + 1] = child
                seen[key] = true
                -- Neither a native background nor a usable icon can be hidden.
                if child.visible and child.hidden ~= true then
                    local value, field = spriteID(child)
                    seen[key] = value or true
                    if value == art.tabSelected or value == art.tabUnselected then
                        backgrounds[#backgrounds + 1] = { component = child, key = key, field = field }
                    end
                end
            end
            return false
        end)
        if overflow or #backgrounds == 0 then return nil end
        local nativeLayout = TabLayout.capture(tabs, children)
        if not nativeLayout then return nil end
        local byKey, icons = {}, {}
        for _, saved in ipairs(nativeLayout) do
            byKey[saved.key] = saved
            local child = saved.component
            if saved.width == 24 and saved.height == 24 and child.visible
                and child.hidden ~= true and child.y == 2 and not icons[saved.x] then
                local value = seen[saved.key]
                if type(value) == "number" then icons[saved.x] = value end
            end
        end
        for _, entry in ipairs(backgrounds) do entry.layout = byKey[entry.key] end
        table.sort(backgrounds, function(a, b) return a.layout.x < b.layout.x end)
        local signature, right = {}, 0
        for _, entry in ipairs(backgrounds) do
            local bg = entry.component
            local x = entry.layout.x
            if bg.width < WIDTH or bg.height ~= HEIGHT or x < 0 then return nil end
            local icon = icons[x + math.floor((bg.width - 24) / 2)]
            if not icon then return nil end
            signature[#signature + 1] = tostring(x) .. ":" .. tostring(bg.width) .. ":" .. tostring(icon)
            entry.icon = icon
            right = math.max(right, x + bg.width)
        end
        return backgrounds, children, table.concat(signature, "/"), right, nativeLayout, byKey
    end

    -- Client-hidden native strips need not reflow when the standalone content does.
    local function tabBand(host)
        return host.grouped and host.tabs or host.content
    end

    local function tabOrigin(host)
        return host.overflow and host.overflow.x or tabBand(host).x
    end

    local function tabScroll(host)
        return host.overflow and host.overflow.scrollX or host.grouped and host.tabs.scrollX or 0
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
        local backgrounds, children, signature, used, nativeIcon, nativeLayout, nativeByKey
        if grouped then
            if tabs.height ~= HEIGHT or tabs.width <= 0
                or tabs.x < content.x or tabs.x + tabs.width > content.x + content.width
                or backdrop.y ~= tabs.y then return nil end
            backgrounds, children, signature, used, nativeLayout, nativeByKey = strip(tabs)
            if not backgrounds or content.y < tabs.y + HEIGHT then return nil end
        else
            if not frame.visibleGlobal or content.width < WIDTH then return nil end
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
            tabControls = component(spec.TABS_SCROLL),
            backgrounds = backgrounds, children = children, signature = signature,
            used = used, grouped = grouped, spec = spec,
            nativeIcon = nativeIcon, nativeLayout = nativeLayout, nativeByKey = nativeByKey }
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

    -- Cheap broad phase: dragging over free space or a native body must not
    -- capture every tab tree. Resolve live components so rebuilds and visibility
    -- changes are reflected without retaining native handles between samples.
    local function captureAt(spec, area, x, y)
        local frame = component(spec.frame)
        if not frame or not frame.visibleGlobal or not same(frame.parent, area) then return nil end
        local tabs = component(spec.TABS)
        local grouped = tabs and tabs.visible == true
        local content = component(spec.CONTENT)
        local band = grouped and tabs or content
        if not band or not content then return nil end
        local top = band.xyGlobal
        local targetY = grouped and top.y or frame.xyGlobal.y
        local left = content.xyGlobal.x
        if x >= left and x < left + content.width and y >= targetY and y < top.y + HEIGHT then
            return capture(spec, area, true)
        end
    end

    local function captureHiddenGroup(spec, area)
        local frame = component(spec.frame)
        if not frame or frame.visibleGlobal or frame.hidden or not same(frame.parent, area) then return nil end
        local tabs = component(spec.TABS)
        if tabs and tabs.visible == true then return capture(spec, area, true) end
    end

    local function hasCapacity(group, host)
        if host.content.width < WIDTH or host.content.height <= HEIGHT then return false end
        local height = host.content.height - (group.grouped and 0 or HEIGHT)
        for _, panel in ipairs(group.members) do
            if host.content.width < panel.minWidth or height < panel.minHeight
                or host.content.width > (panel.maxWidth or math.huge)
                or height > (panel.maxHeight or math.huge) then return false end
        end
        return true
    end

    local function checkCapacity(group)
        for _, host in ipairs(group.hosts) do
            if not hasCapacity(group, host) then
                group.capacityLost = true
                error("native host resized out of docking capacity")
            end
        end
    end

    local function validHost(group, host)
        if not (live(group) and identity(host.frame) == host.key
            and same(host.frame.parent, group.area)
            and same(host.content.parent, host.frame)
            and (not host.scroll or same(host.scroll.parent, host.frame))
            and same(host.tabs.parent, host.frame) and host.tabs.visible == host.grouped
            and host.content.width >= WIDTH) then return false end
        if not group.grouped then return true end
        return host.content.y >= host.tabs.y + HEIGHT
    end

    return {
        identity = identity, component = component, same = same, live = live,
        mapReady = mapReady, editingLocked = editingLocked,
        applyLayout = applyLayout, spriteID = spriteID,
        tabBand = tabBand, tabOrigin = tabOrigin, tabScroll = tabScroll,
        capture = capture, familiarRootsFor = familiarRootsFor, nativeRootsFor = nativeRootsFor,
        discover = discover, related = related, resolve = resolve,
        frameGroup = frameGroup, selectedFrame = selectedFrame,
        rectInParent = rectInParent, freeRect = freeRect,
        captureAt = captureAt, captureHiddenGroup = captureHiddenGroup,
        indexSpecs = indexSpecs, checkCapacity = checkCapacity,
        validHost = validHost, specByID = specByID,
        HEIGHT = HEIGHT, WIDTH = WIDTH, SEAM = SEAM,
    }
end

return Host
