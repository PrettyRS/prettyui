-- Each scenario gets fresh client state and fresh PrettyUI module singletons.
local Fixture = {}

function Fixture.new()
    for name in pairs(package.loaded) do
        if name:match("^src/") or name == "tests/interface_fixture" then package.loaded[name] = nil end
    end
    local Interfaces = require("tests/interface_fixture")

    local function expect(actual, expected, message)
        if actual ~= expected then
            error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
        end
    end

    local function removeChild(parent, child)
        if not parent then return end
        for index, candidate in ipairs(parent.children) do
            if candidate == child then
                table.remove(parent.children, index)
                return
            end
        end
    end

    local function removeRenderChild(parent, child)
        if not parent then return false end
        for index, candidate in ipairs(parent.renderChildren) do
            if candidate == child then
                table.remove(parent.renderChildren, index)
                return true
            end
        end
        return false
    end

    local function component(parent, kind, categoryID, dynamicID)
        local result = {
            parent = parent,
            kind = kind,
            children = {},
            renderChildren = {},
            subscriptions = {},
            namedSubscriptions = {},
            x = 0,
            y = 0,
            width = 0,
            height = 0,
            hidden = false,
            opConfig = { ClearOpCursors = function() end, SetOpCursor = function() end },
            position = { x = 0, y = 0, xParentPc = 0, yParentPc = 0, xSelfPc = 0, ySelfPc = 0 },
            cursorConfig = {},
            dragConfig = {},
            resizeOrder = {},
        }
        local position, size = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
        function result:SetPos(x, y, xAnchor, yAnchor, xSelf, ySelf)
            assert(not self.destroyed, "positioning destroyed component")
            position = { x, y, xAnchor or 0, yAnchor or 0, xSelf or 0, ySelf or 0 }
            self.position = {
                x = x,
                y = y,
                xParentPc = position[3],
                yParentPc = position[4],
                xSelfPc = position[5],
                ySelfPc = position[6],
            }
            self.x = x + ((parent and parent.width or 0) * position[3]) - self.width * position[5]
            self.y = y + ((parent and parent.height or 0) * position[4]) - self.height * position[6]
        end
        function result:EmitResize()
            for _, key in ipairs(self.resizeOrder) do
                local callback = (self.namedSubscriptions[ui.Hook.ONRESIZE] or {})[key]
                if callback then callback(self) end
            end
        end
        function result:Relayout()
            self:SetPos(table.unpack(position))
            self.width = size[1] + ((parent and parent.width or 0) * size[3])
            self.height = size[2] + ((parent and parent.height or 0) * size[4])
            for _, child in ipairs(self.children) do
                child:Relayout()
            end
            self:EmitResize()
        end
        function result:SetSize(width, height, widthAnchor, heightAnchor)
            size = { width, height, widthAnchor or 0, heightAnchor or 0 }
            self.size = { width = width, height = height, widthParentPc = size[3], heightParentPc = size[4] }
            self:Relayout()
        end
        function result:SetWidth(width, anchor)
            self:SetSize(width, size[2], anchor or 0, size[4])
        end
        function result:SetHeight(height, anchor)
            self:SetSize(size[1], height, size[3], anchor or 0)
        end
        function result:SetScrollSize(width, height)
            self.scrollWidth, self.scrollHeight = width, height
        end
        function result:SetScrollPos(x, y)
            self.scrollX, self.scrollY = x, y
        end
        function result:Subscribe(hook, name, callback)
            if callback then
                self.namedSubscriptions[hook] = self.namedSubscriptions[hook] or {}
                if hook == ui.Hook.ONRESIZE and self.namedSubscriptions[hook][name] == nil then
                    self.resizeOrder[#self.resizeOrder + 1] = name
                end
                self.namedSubscriptions[hook][name] = callback
            else
                self.subscriptions[hook] = name
            end
        end
        function result:Unsubscribe(hook, name)
            if name then
                if
                    self.strictNativeHooks
                    and not (self.namedSubscriptions[hook] and self.namedSubscriptions[hook][name])
                then
                    error("Component doesn't have an active hook of type " .. tostring(hook))
                end
                if self.namedSubscriptions[hook] then self.namedSubscriptions[hook][name] = nil end
            else
                self.subscriptions[hook] = nil
            end
        end
        function result:MoveToFront()
            if not parent then return end
            assert(removeRenderChild(parent, self), "cannot reorder an absent native render entry")
            self.frontMoves = (self.frontMoves or 0) + 1
            removeChild(parent, self)
            parent.children[#parent.children + 1] = self
            parent.renderChildren[#parent.renderChildren + 1] = self
        end
        function result:MoveToBack()
            if not parent then return end
            assert(removeRenderChild(parent, self), "cannot reorder an absent native render entry")
            removeChild(parent, self)
            table.insert(parent.children, 1, self)
            table.insert(parent.renderChildren, 1, self)
        end
        function result:Destroy()
            while #self.children > 0 do
                self.children[#self.children]:Destroy()
            end
            removeChild(parent, self)
            removeRenderChild(parent, self)
            self.destroyed = true
        end
        setmetatable(result, {
            __index = function(self, key)
                if key == "sprite" then return self._runtimeSprite or self._spriteID end
                if key == "spriteID" then return self._spriteID end
                if key == "runtimeSprite" then return self._runtimeSprite end
                if key ~= "xyGlobal" then return nil end
                local origin = parent and parent.xyGlobal or { x = 0, y = 0 }
                return { x = origin.x + self.x, y = origin.y + self.y }
            end,
            __newindex = function(self, key, value)
                if key == "sprite" or key == "spriteID" then
                    if key == "spriteID" then
                        assert(value == nil or type(value) == "number", "spriteID only accepts built-in numeric IDs")
                    else
                        assert(
                            value == nil or type(value) == "number" or type(value) == "table" and value.imageResource,
                            "sprite accepts built-in IDs or image resources"
                        )
                    end
                    rawset(self, "_spriteID", type(value) == "number" and value or nil)
                    rawset(self, "_runtimeSprite", type(value) == "table" and { resource = value } or nil)
                else
                    rawset(self, key, value)
                end
            end,
        })
        if parent then
            parent.children[#parent.children + 1] = result
            parent.renderChildren[#parent.renderChildren + 1] = result
        end
        return Interfaces.component(result, parent, categoryID, dynamicID)
    end

    local function factory(kind)
        return {
            new = function(parent, categoryID, dynamicID)
                return component(parent, kind, categoryID, dynamicID)
            end,
        }
    end

    ui = {
        Layer = factory("layer"),
        Sprite = factory("sprite"),
        Rectangle = factory("rectangle"),
        Text = factory("text"),
        Hook = {
            ONCLICK = 1,
            ONHOLD = 2,
            ONDRAG = 3,
            ONRELEASE = 4,
            ONDRAGCOMPLETE = 5,
            ONSCROLLWHEEL = 6,
            ONMOUSEOVER = 7,
            ONMOUSELEAVE = 8,
            ONMOUSEREPEAT = 9,
            ONRESIZE = 10,
        },
        AlignMode = { TOPLEFT = 1, CENTRE = 2 },
        DragRenderBehaviour = { INVISIBLE = 0, OPAQUE = 1, OPAQUE_OVERLAY = 2, TRANSPARENT_OVERLAY = 3 },
    }
    Plugin = { resources = { image = { imageResource = true, path = "resources/image.png" } } }
    local nextSpriteID = 10000
    id = {
        Sprite = setmetatable({}, {
            __index = function(sprites, key)
                nextSpriteID = nextSpriteID + 1
                rawset(sprites, key, nextSpriteID)
                return nextSpriteID
            end,
        }),
        Font = { MUSEO_SANS_15PT_REGULAR = 1, CINZEL_13PT_BOLD = 2, MUSEO_SANS_11PT_REGULAR_MULTILINE = 3 },
        VarPlayer = {
            TOPLEVEL_V2_SKINS_VARP = 12,
            TOPLEVEL_V2_TRANSPARENCY = -13,
            TOPLEVEL_V2_GENERAL_VARP = 14,
        },
        Component = {
            TOPLEVEL_V2__GAME_AREA = (1477 << 16) | 61,
            TOPLEVEL_V2__PLUGIN_BUILD_LAYER_BOTTOM = (1477 << 16) | 62,
        },
    }
    local font = {
        baseline = 18,
        GetStringLineCount = function() return 1 end,
        GetStringWidth = function(_, text) return #text * 7 end,
        GetStringHeightAndLineCount = function() return 18 end,
    }
    local tabFont = {
        baseline = 16,
        GetStringWidth = function(_, text) return #text * 6 end,
        GetStringHeightAndLineCount = function() return 16 end,
    }
    config = {
        Cursor = {
            TOPLEVEL_V2_MOVE = 194,
            TOPLEVEL_V2_SCALE_VERT = 195,
            TOPLEVEL_V2_SCALE_HORZ = 196,
            TOPLEVEL_V2_SCALE_DIAG_1 = 197,
            TOPLEVEL_V2_SCALE_DIAG_2 = 198,
        },
        Font = {
            MUSEO_SANS_15PT_REGULAR = font,
            CINZEL_13PT_BOLD = font,
            MUSEO_SANS_11PT_REGULAR_MULTILINE = tabFont,
        },
    }
    Mouse = { GetPosition = function() return nil end }
    Keyboard = {
        IsAvailable = function() return true end,
        IsBlocked = function() return false end,
        IsAltDown = function() return false end,
    }
    game = { options = { InterfaceScale = { setting = 100 } } }
    GameKey = { ESCAPE = 27 }
    local events = {}
    local function event(name)
        events[name] = {}
        return {
            Subscribe = function(key, callback) events[name][key] = callback end,
            Unsubscribe = function(key)
                -- Native event bindings need a Lua caller to resolve plugin ownership.
                assert(debug.getinfo(2, "S").what ~= "C", "native unsubscribe lost its Lua plugin caller")
                events[name][key] = nil
            end,
        }
    end
    Event = {
        Logic = event("Logic"),
        Draw = event("Draw"),
        VarTransmit = event("VarTransmit"),
        KeyDown = event("KeyDown"),
        WindowFocusChanged = event("WindowFocusChanged"),
        SettingsLayerReady = event("SettingsLayerReady"),
    }
    local locked, transparency = true, 0
    local classicMode = { value = 0 }
    var = {
        VarPlayer = {
            TOPLEVEL_V2_LEGACY_INTERFACE = classicMode,
            TOPLEVEL_V2_CUSTOMIZATION_LOCK = setmetatable({}, {
                __index = function() return locked and 1 or 0 end,
            }),
            TOPLEVEL_V2_TRANSPARENCY = setmetatable({
                isVarBit = true,
                baseVar = { id = 12 },
                varBitMask = 0xFF00,
            }, {
                __index = function(_, key)
                    if key == "value" then return transparency end
                end,
            }),
        },
    }
    local function transmit(varID)
        for _, callback in pairs(events.VarTransmit) do
            callback({ var = { id = varID } })
        end
    end
    local function fire(target, hook, ...)
        return assert(target.subscriptions[hook], "missing hook " .. tostring(hook))(target, ...)
    end

    local function hitAt(area, x, y)
        for index = #area.renderChildren, 1, -1 do
            local child = area.renderChildren[index]
            if
                not child.hidden
                and child.visibleGlobal ~= false
                and child.enabled ~= false
                and x >= child.x
                and x < child.x + child.width
                and y >= child.y
                and y < child.y + child.height
            then
                local target = hitAt(child, x - child.x, y - child.y)
                if target then return target end
                if child.clickthrough ~= true then return child end
            end
        end
    end

    local savedLayouts = {}
    local function copy(value)
        if type(value) ~= "table" then return value end
        local result = {}
        for key, child in pairs(value) do
            result[key] = copy(child)
        end
        return result
    end
    local savedPreferences = {}
    PersistentDB = {
        GetString = function(_, key) return savedPreferences[key] end,
        SetString = function(_, key, value)
            savedPreferences[key] = value
            return true
        end,
        GetBool = function(_, key) return savedPreferences[key] end,
        SetBool = function(_, key, value)
            savedPreferences[key] = value
            return true
        end,
        GetInt = function(_, key) return savedPreferences[key] end,
        SetInt = function(_, key, value)
            savedPreferences[key] = value
            return true
        end,
        GetStructuredData = function(_, key) return copy(savedLayouts[key]) end,
        SetStructuredData = function(_, key, value)
            savedLayouts[key] = copy(value)
            return true
        end,
    }

    local f = {
        expect = expect,
        component = component,
        fire = fire,
        hitAt = hitAt,
        events = events,
        event = event,
        font = font,
        Interfaces = Interfaces,
        savedLayouts = savedLayouts,
        classicMode = classicMode,
        copy = copy,
        panels = {},
    }
    f.NisPanel = require("src/nis_panel")
    f.parent = component(nil, "parent")
    f.parent:SetSize(1000, 700)
    locked = false

    function f.emit(_, name, payload)
        for _, callback in pairs(events[name]) do
            callback(payload or {})
        end
    end
    function f.lock(_, value)
        locked = value
        transmit(12)
    end
    function f.transparency(_, value)
        transparency = value
        transmit(12)
    end
    function f:panel(extra)
        local options = { x = 100, y = 100, width = 300, height = 200 }
        for key, value in pairs(extra or {}) do
            options[key] = value
        end
        local panel = self.NisPanel.new(self.parent, options)
        self.panels[#self.panels + 1] = panel
        return panel
    end
    function f.begin(_, panel)
        fire(panel.dragLayer, ui.Hook.ONCLICK, panel.root.width / 2, 6)
    end
    function f.move(_, panel, x, y)
        fire(panel.dragLayer, ui.Hook.ONDRAG, x - panel.dragLayer.x, y - panel.dragLayer.y)
    end
    function f.release(_, panel)
        fire(panel.dragLayer, ui.Hook.ONRELEASE)
    end
    function f.resize(_, panel, edge, dx, dy)
        local hit = panel.resize.handles[edge]
        fire(hit, ui.Hook.ONCLICK, 2, 2)
        fire(hit, ui.Hook.ONHOLD, 2 + dx, 2 + dy)
        fire(hit, ui.Hook.ONRELEASE)
    end
    function f:restart()
        for _, name in ipairs({
            "src/nis_panel",
            "src/nis/group",
            "src/nis/drag",
            "src/nis/native",
            "src/nis/persistence",
            "src/ribbon_bar",
        }) do
            package.loaded[name] = nil
        end
        self.NisPanel = require("src/nis_panel")
    end
    function f.saved(_, panelID)
        return savedLayouts["prettyui.nis-layout.v1"].panels[panelID]
    end
    return f
end

function Fixture.rect(actual, x, y, width, height)
    for key, value in pairs({ x = x, y = y, width = width, height = height }) do
        assert(actual[key] == value, key .. ": expected " .. value .. ", got " .. tostring(actual[key]))
    end
end

function Fixture.run(name, scenario)
    io.write(name .. " ... ")
    local f = Fixture.new()
    scenario(f)
    for _, panel in ipairs(f.panels) do
        panel:Destroy()
    end
    require("src/ribbon_bar").Shutdown()
    print("ok")
end

return Fixture
