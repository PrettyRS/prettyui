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
    local function indexSpec(packed, name)
        if type(name) ~= "string" or type(packed) ~= "number" then return end
        for _, kind in ipairs(specKinds) do
            local base, suffix = name:match("^(.+_WINDOW)_" .. kind .. "(.*)$")
            if base and (suffix == "" or suffix:sub(1, 1) == "_") then
                local frameName = base .. suffix
                local spec = specs[frameName]
                if not spec then
                    spec = { name = frameName }
                    specs[frameName] = spec
                end
                spec[kind] = packed
                break
            end
        end
    end

    local function indexSpecs()
        if indexed then return end
        indexed = true
        for packed, name in pairs(id.Component) do
            indexSpec(packed, name)
        end
        for name, spec in pairs(specs) do
            spec.frame = id.Component[name]
            if
                type(spec.frame) == "number"
                and spec.frame >= 0
                and spec.CONTENT
                and spec.TABS
                and spec.TAB_BACKGROUND
            then
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
            if frame and frame.visible ~= false and not frame.hidden and same(frame.parent, group.area) then
                return true
            end
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

    local function layout(node)
        local result, pos, size = {}, node.position, node.size
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

    local function applyLayout(node, saved)
        node:SetPos(table.unpack(saved, 1, 6))
        node:SetSize(table.unpack(saved, 7, 10))
    end

    local function fieldOf(item, field)
        return item[field]
    end

    local function spriteID(item)
        local ok, value = pcall(fieldOf, item, "spriteID")
        if ok and type(value) == "number" then return value, "spriteID" end
        ok, value = pcall(fieldOf, item, "spriteId")
        if ok and type(value) == "number" then return value, "spriteId" end
        return nil
    end

    local function orderedRow(backgrounds, icons, sprites)
        table.sort(backgrounds, function(a, b) return a.layout.x < b.layout.x end)
        local signature, right = {}, 0
        for _, entry in ipairs(backgrounds) do
            local bg, x = entry.component, entry.layout.x
            if bg.width < WIDTH or bg.height ~= HEIGHT or x < right then return nil end
            local icon = icons[x + math.floor((bg.width - 24) / 2)]
            if not icon then return nil end
            entry.icon, entry.iconKey = sprites[icon.key], icon.key
            signature[#signature + 1] = x .. ":" .. bg.width .. ":" .. entry.icon
            right = x + bg.width
        end
        return table.concat(signature, "/"), right
    end

    -- Native category-zero tabs are four dynamic children per slot: background,
    -- icon, then two optional badges. The client can move a dragged background
    -- and icon independently of the settled row, so position alone is not identity.
    local function pairedRow(backgrounds, records, seen)
        table.sort(
            backgrounds,
            function(a, b)
                return a.component.dynamicID < b.component.dynamicID
            end
        )
        local slots = {}
        for _, saved in ipairs(records) do
            local child = saved.component
            if child.categoryID == 0 and type(child.dynamicID) == "number" then
                if child.dynamicID < 0 or child.dynamicID >= #backgrounds * 4 or slots[child.dynamicID] then
                    return nil
                end
                slots[child.dynamicID] = saved
            end
        end
        for index, bg in ipairs(backgrounds) do
            local child = bg.component
            local slot = (index - 1) * 4
            local icon = slots[slot + 1]
            if
                child.categoryID ~= 0
                or child.dynamicID ~= slot
                or bg.layout.width < WIDTH
                or bg.layout.height ~= HEIGHT
                or not icon
                or icon.width ~= 24
                or icon.height ~= 24
                or icon.component.y ~= 2
                or not icon.component.visible
                or icon.component.hidden
                or type(seen[icon.key]) ~= "number"
            then
                return nil
            end
            bg.icon, bg.iconKey = seen[icon.key], icon.key
        end
        return slots
    end

    local function previewSlot(reference, backgrounds)
        if not reference or not reference.grouped or #backgrounds ~= #reference.backgrounds + 1 then
            return nil
        end
        local previous, inserted = 1, nil
        for index, bg in ipairs(backgrounds) do
            local peer = reference.backgrounds[previous]
            if peer and peer.icon == bg.icon then
                previous = previous + 1
            elseif inserted or spriteID(bg.component) ~= art.tabSelected then
                return nil
            else
                inserted = index
            end
        end
        if previous ~= #reference.backgrounds + 1 then return nil end
        return inserted
    end

    local function projectChild(record, bg, index, physical, x, moving)
        local child = record.component
        record.nativeSlot = index
        if index == moving then return end
        local originalX = record.x
        local target = x + originalX - physical
        if child.dynamicID % 4 == 1 then target = x + math.floor((bg.layout.width - 24) / 2) end
        local correction = target - originalX
        record.correction, record.x = correction, target
        record.offset = record.offset - correction
    end

    local function projectPreview(reference, backgrounds, slots, moving)
        local x, signature = reference.backgrounds[1].layout.x, {}
        for index, bg in ipairs(backgrounds) do
            local physical = bg.layout.x
            local first = (index - 1) * 4
            signature[#signature + 1] = x .. ":" .. bg.layout.width .. ":" .. bg.icon
            for childID = first, first + 3 do
                local record = slots[childID]
                if record then projectChild(record, bg, index, physical, x, moving) end
            end
            if index == moving then
                -- The row needs a logical slot; its input records keep the
                -- actual captured coordinates for repaint detection.
                bg.layout = { x = x, width = bg.component.width }
            end
            x = x + bg.layout.width
        end
        return table.concat(signature, "/"), x
    end

    -- During native drop preview a background can already occupy a neighbour's
    -- slot while its icon still has the old position. Geometry cannot identify
    -- that row. Only project the last complete row if every slot and icon is
    -- accounted for and nothing but horizontal positions has changed.
    local function retainedRow(previous, backgrounds, records, seen)
        if not previous or #previous.backgrounds ~= #backgrounds or #previous.nativeLayout ~= #records then
            return nil
        end
        for _, bg in ipairs(previous.backgrounds) do
            local sprite = seen[bg.key]
            if sprite ~= art.tabSelected and sprite ~= art.tabUnselected then return nil end
            if seen[bg.iconKey] ~= bg.icon then return nil end
        end
        for _, record in ipairs(records) do
            local old = previous.nativeByKey[record.key]
            if not old or old.width ~= record.width or old.height ~= record.height then return nil end
            for i = 2, 6 do
                if old.original[i] ~= record.original[i] then return nil end
            end
            local correction = old.x - record.x
            record.correction, record.x = correction, old.x
            record.offset = record.offset - correction
            record._conflicted = false
        end
        table.sort(backgrounds, function(a, b) return a.layout.x < b.layout.x end)
        for i, bg in ipairs(backgrounds) do
            local old = previous.backgrounds[i]
            bg.icon, bg.iconKey = old.icon, old.iconKey
        end
        return previous.signature, previous.used
    end

    local function strip(tabs, previous, reference)
        local backgrounds, children, seen, overflow, count = {}, {}, {}, false, 0
        tabs:IterateDynamicComponents(function(child)
            count = count + 1
            if count > MAX_TABS then
                overflow = true
                return true
            end
            local key = identity(child)
            if not key then
                overflow = true
                return true
            end
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
            saved.y, saved.rowSprite = child.y, seen[saved.key]
            if
                saved.width == 24
                and saved.height == 24
                and child.visible
                and child.hidden ~= true
                and child.y == 2
                and not icons[saved.x]
            then
                local value = seen[saved.key]
                if type(value) == "number" then icons[saved.x] = saved end
            end
        end
        for _, entry in ipairs(backgrounds) do
            entry.layout = byKey[entry.key]
        end
        local verified = reference and pairedRow(backgrounds, nativeLayout, seen)
        local moving = verified and previewSlot(reference, backgrounds)
        local signature, right
        if moving then
            signature, right = projectPreview(reference, backgrounds, verified, moving)
        else
            signature, right = orderedRow(backgrounds, icons, seen)
            if not signature then
                signature, right = retainedRow(previous, backgrounds, nativeLayout, seen)
            end
        end
        if not signature then return nil end
        for _, bg in ipairs(backgrounds) do
            byKey[bg.iconKey].tabIcon = bg.icon
        end
        return backgrounds, children, signature, right, nativeLayout, byKey, moving
    end

    -- Reuse only a complete, verified row. Dynamic IDs survive rebuilds;
    -- fresh handles must still reach artwork, input observers and cleanup.
    local function residentStrip(host, tabs)
        if not host.grouped or host.previewIncoming then return false end
        local records = host.nativeLayout
        local count, changed, replacements = 0, false, nil
        tabs:IterateDynamicComponents(function(child)
            if not same(child.parent, tabs) then return false end
            count = count + 1
            local record = records[count]
            if
                not record
                or (record.component ~= child and identity(child) ~= record.key)
                or child.y ~= record.y
                or not TabLayout.unchanged(record, child)
            then
                changed = true
                return true
            end
            local sprite = child.visible and not child.hidden and spriteID(child) or true
            if sprite ~= record.rowSprite then
                changed = true
                return true
            end
            if record.component ~= child then
                replacements = replacements or {}
                replacements[count] = child
            end
            return false
        end)
        if changed or count ~= #records then return false end
        if replacements then
            for index, child in pairs(replacements) do
                records[index].component, host.children[index] = child, child
            end
            for _, bg in ipairs(host.backgrounds) do
                bg.component = bg.layout.component
            end
        end
        return true
    end

    local function previewReference(reference, frame, key, bound)
        if not reference or not reference.grouped or reference.owner ~= frame.interfaceID then return nil end
        if not frame.visibleGlobal then return nil end
        if reference.candidate then
            if reference.candidate ~= key then return nil end
        elseif bound or not reference.frame.visibleGlobal then
            return nil
        end
        if frame.x ~= (reference.previewTargetX or reference.frame.x) then return nil end
        if frame.y ~= (reference.previewTargetY or reference.frame.y) then return nil end
        return reference
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

    local function standaloneIcon(spec, tabs, frameKey)
        -- Standalone strips stay client-hidden, but their single native tab
        -- usually still exposes the correct icon. Notes may have no children.
        local entries = strip(tabs)
        local icon
        if entries and #entries == 1 then
            icon = entries[1].icon
        elseif spec.name == "TOPLEVEL_V2__NOTES_WINDOW" then
            icon = id.Sprite.CHILD_TAB_ICON_NOTES
        end
        -- A lock rebuild can clear a hidden strip. Retain only an icon already
        -- captured for this bound frame; new hosts still require discovery.
        local bound = byFrame[frameKey]
        if icon or not bound or bound.grouped then return icon end
        for _, previous in ipairs(bound.hosts) do
            if previous.key == frameKey then return previous.nativeIcon end
        end
        return nil
    end

    local function groupedStrip(tabs, content, backdrop, previous, reference, resident)
        if
            tabs.height ~= HEIGHT
            or tabs.width <= 0
            or tabs.x < content.x
            or tabs.x + tabs.width > content.x + content.width
            or backdrop.y ~= tabs.y
        then
            return nil
        end
        local backgrounds, children, signature, used, nativeLayout, nativeByKey, previewSource
        if resident and residentStrip(resident, tabs) then
            backgrounds, children = resident.backgrounds, resident.children
            signature, used = resident.signature, resident.used
            nativeLayout, nativeByKey = resident.nativeLayout, resident.nativeByKey
        else
            backgrounds, children, signature, used, nativeLayout, nativeByKey, previewSource =
                strip(tabs, previous, reference)
        end
        if not backgrounds or content.y < tabs.y + HEIGHT then return nil end
        return backgrounds, children, signature, used, nativeLayout, nativeByKey, previewSource
    end

    local function captureParts(spec, frame, allowHidden)
        local content, scroll, tabs, backdrop =
            component(spec.CONTENT), component(spec.SCROLL), component(spec.TABS), component(spec.TAB_BACKGROUND)
        if
            not content
            or not tabs
            or not backdrop
            or spec.SCROLL and not scroll
            or not same(content.parent, frame)
            or scroll and not same(scroll.parent, frame)
            or not same(tabs.parent, frame)
            or not same(backdrop.parent, frame)
            or content.width < 0
            or content.height < 0
            or not allowHidden and (content.hidden or scroll and scroll.hidden)
        then
            return nil
        end
        return content, scroll, tabs, backdrop
    end

    local function capture(spec, area, allowHidden, reference, resident)
        local frame = component(spec.frame)
        if not frame or not same(frame.parent, area) or frame.hidden then return nil end
        local content, scroll, tabs, backdrop = captureParts(spec, frame, allowHidden)
        if not content then return nil end
        local grouped = tabs.visible == true
        local frameKey = identity(frame)
        local backgrounds, children, signature, used, nativeIcon, nativeLayout, nativeByKey, previewSource
        if grouped then
            local group = byFrame[frameKey]
            local previous = group and not group.nativeSort and group.hosts[group.current]
            if previous and (not previous.grouped or previous.key ~= frameKey) then previous = nil end
            reference = previewReference(reference, frame, frameKey, group)
            backgrounds, children, signature, used, nativeLayout, nativeByKey, previewSource =
                groupedStrip(tabs, content, backdrop, previous, reference, resident)
            if not backgrounds then return nil end
        else
            if not frame.visibleGlobal then return nil end
            nativeIcon = standaloneIcon(spec, tabs, frameKey)
            if not nativeIcon then return nil end
            backgrounds, children, signature, used = {}, {}, "", WIDTH
        end
        return {
            frame = frame,
            content = content,
            scroll = scroll,
            tabs = tabs,
            backdrop = backdrop,
            key = frameKey,
            owner = frame.interfaceID,
            tabControls = component(spec.TABS_SCROLL),
            backgrounds = backgrounds,
            children = children,
            signature = signature,
            used = used,
            grouped = grouped,
            spec = spec,
            nativeIcon = nativeIcon,
            nativeLayout = nativeLayout,
            nativeByKey = nativeByKey,
            previewIncoming = previewSource ~= nil,
            previewSource = previewSource,
            previewTargetX = previewSource and frame.x,
            previewTargetY = previewSource and frame.y,
        }
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

    local function fitInset(saved)
        local inset, parent = saved.inset, saved.component.parent
        local width = math.max(saved.widthInset, -parent.width * inset[9])
        local height = math.max(saved.heightInset, -parent.height * inset[10])
        if width == inset[7] and height == inset[8] then return end
        local oldWidth, oldHeight = inset[7], inset[8]
        inset[7], inset[8] = width, height
        return oldWidth, oldHeight
    end

    local function snapshotRoot(child, original, inset)
        local saved = {
            component = child,
            owner = child.interfaceID,
            key = identity(child),
            packed = (child.interfaceID << 16) | child.staticID,
            original = original,
            inset = inset,
            widthInset = inset[7],
            heightInset = inset[8],
            hidden = child.hidden,
            changed = false,
        }
        fitInset(saved)
        return saved
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
        for _, saved in ipairs(previous or {}) do
            retained[saved.key] = saved
        end
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
            local saved = roots[#roots]
            saved.inset = { 0, HEIGHT, 0, 0, 0, 0, 0, -HEIGHT, 1, 1 }
            saved.widthInset, saved.heightInset = 0, -HEIGHT
            fitInset(saved)
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
    local function splitRoot(host, entry)
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
        return snapshotRoot(child, original, inset)
    end

    local function splitRootList(host, schema)
        local roots = {}
        for _, entry in ipairs(schema) do
            local root = splitRoot(host, entry)
            if not root then return nil end
            roots[#roots + 1] = root
        end
        return roots
    end

    local function findWrapper(host)
        if not wrappers then
            wrappers = {}
            for packed, name in pairs(id.Component) do
                if
                    type(name) == "string"
                    and type(packed) == "number"
                    and (
                        name:match("_WRAPPER$")
                        or standaloneRoots[name]
                        or name:match("^TOPLEVEL_V2_WINDOW_ABILITY_BOOK_.+__MAIN_LAYER$")
                    )
                then
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
        return chosen
    end

    local function standaloneRoot(host)
        local chosen = findWrapper(host)
        if
            not chosen
            or chosen.hidden
            or chosen.x ~= 0
            or chosen.y ~= 0
            or chosen.width ~= host.content.width
            or chosen.height ~= host.content.height
        then
            return nil
        end
        local saved = layout(chosen)
        if
            not saved
            or saved[1] ~= 0
            or saved[2] ~= 0
            or saved[7] ~= 0
            or saved[8] ~= 0
            or saved[9] ~= 1
            or saved[10] ~= 1
        then
            return nil
        end
        -- Normalizing full-size roots also handles Equipment's centered anchors.
        return { snapshotRoot(chosen, saved, { 0, HEIGHT, 0, 0, 0, 0, 0, -HEIGHT, 1, 1 }) }
    end

    local function nativeRootsFor(host)
        if host.spec.name == "TOPLEVEL_V2__LORE_WINDOW" then return familiarRootsFor(host) end
        local schema = splitRoots[host.spec.name]
        if schema then return splitRootList(host, schema) end
        return standaloneRoot(host)
    end

    local function discover(area, reference)
        indexSpecs()
        local found = {}
        for _, spec in pairs(specByID) do
            local ok, host = pcall(capture, spec, area, true, reference)
            if ok and host then found[#found + 1] = host end
        end
        return found
    end
    local function incomingPreview(group, reference)
        if not reference or not reference.grouped then return false end
        indexSpecs()
        local x, y = reference.frame.x, reference.frame.y
        local visible = false
        group.area:IterateStaticComponents(function(frame, shown)
            if shown == false then return false end
            local packed = (frame.interfaceID << 16) | frame.staticID
            local spec = specByID[packed]
            if not spec or frame.x ~= x or frame.y ~= y or not frame.visibleGlobal then return false end
            if not byFrame[identity(frame)] then
                local tabs = component(spec.TABS)
                if not tabs or not tabs.visible then return false end
                local ok, host = pcall(capture, spec, group.area, true, reference)
                if ok and host and host.previewIncoming then
                    visible = true
                    return true
                end
            end
            return false
        end)
        return visible
    end

    local function related(host, other)
        if not host.grouped then return host.key == other.key end
        -- Hidden frame copies may keep their previous bounds while the visible
        -- frame moves/resizes. Membership is the native tab signature, not geometry.
        return other.grouped
            and other.owner == host.owner
            and other.signature == host.signature
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
                if index and not group.selectionHandoff then return nil end
                if not index or i == group.current then index = i end
            end
        end
        return index
    end

    local function rectInParent(panel, node)
        local origin, parentOrigin = node.xyGlobal, panel.parent.xyGlobal
        return math.floor(origin.x - parentOrigin.x), math.floor(origin.y - parentOrigin.y), node.width, node.height
    end

    local function freeRect(panel)
        return { x = panel.root.x, y = panel.root.y, width = panel.root.width, height = panel.root.height }
    end

    -- Cheap broad phase: dragging over free space or a native body must not
    -- capture every tab tree. Resolve live components so rebuilds and visibility
    -- changes are reflected without retaining native handles between samples.
    local function captureAt(spec, area, x, y)
        local frame = component(spec.frame)
        if not frame or not frame.visibleGlobal or not same(frame.parent, area) then return nil end
        local tabs = component(spec.TABS)
        local grouped = tabs and tabs.visible == true
        local band = grouped and tabs or component(spec.CONTENT)
        if not band then return nil end
        local top = band.xyGlobal
        local targetY = grouped and top.y or frame.xyGlobal.y
        if x >= top.x and x < top.x + band.width and y >= targetY and y < top.y + HEIGHT then
            return capture(spec, area, true)
        end
    end

    local function captureHiddenGroup(spec, area)
        local frame = component(spec.frame)
        if not frame or frame.visibleGlobal or frame.hidden or not same(frame.parent, area) then return nil end
        local tabs = component(spec.TABS)
        if tabs and tabs.visible == true then return capture(spec, area, true) end
    end

    local function validHost(group, host)
        if
            not (
                live(group)
                and identity(host.frame) == host.key
                and same(host.frame.parent, group.area)
                and same(host.content.parent, host.frame)
                and (not host.scroll or same(host.scroll.parent, host.frame))
                and same(host.tabs.parent, host.frame)
                and host.tabs.visible == host.grouped
            )
        then
            return false
        end
        if not group.grouped then return true end
        return host.content.y >= host.tabs.y + HEIGHT
    end

    return {
        identity = identity,
        component = component,
        same = same,
        live = live,
        mapReady = mapReady,
        editingLocked = editingLocked,
        applyLayout = applyLayout,
        spriteID = spriteID,
        tabBand = tabBand,
        tabOrigin = tabOrigin,
        tabScroll = tabScroll,
        capture = capture,
        familiarRootsFor = familiarRootsFor,
        nativeRootsFor = nativeRootsFor,
        discover = discover,
        incomingPreview = incomingPreview,
        related = related,
        resolve = resolve,
        frameGroup = frameGroup,
        selectedFrame = selectedFrame,
        rectInParent = rectInParent,
        freeRect = freeRect,
        captureAt = captureAt,
        captureHiddenGroup = captureHiddenGroup,
        indexSpecs = indexSpecs,
        fitInset = fitInset,
        validHost = validHost,
        specByID = specByID,
        HEIGHT = HEIGHT,
        WIDTH = WIDTH,
        SEAM = SEAM,
    }
end

return Host
