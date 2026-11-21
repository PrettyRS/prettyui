-- Native tab geometry and render ordering, shared by docking integration scenarios.
return function(f)
    local component, Interfaces = f.component, f.Interfaces
    local function removeChild(parent, child)
        if not parent then return end
        for index, entry in ipairs(parent.children) do
            if entry == child then table.remove(parent.children, index); return end
        end
    end
    local function removeRenderChild(parent, child)
        if not parent then return false end
        for index, entry in ipairs(parent.renderChildren) do
            if entry == child then table.remove(parent.renderChildren, index); return true end
        end
        return false
    end
    local oldGet, oldInterface = ui.Interfaces.GetComponent, ui.Interfaces.GetInterface
    local nativeNodes = {}
    local function nativeNode(interfaceID, staticID, owner, x, y, width, height)
        local node = component(nil, "native")
        node.type = 20
        node.clickthrough = true -- structural layers; native inputs are their children
        node.strictNativeHooks = true
        node.dragConfig.renderBehaviour = ui.DragRenderBehaviour.OPAQUE
        node.scrollable = true
        node.scrollX, node.scrollY, node.scrollWidth, node.scrollHeight = 0, 0, 0, 0
        node.interfaceID, node.staticID = interfaceID, staticID
        node.parentStatic = nil
        Interfaces.component(node)
        node.parent = owner
        if owner then
            owner.children[#owner.children + 1] = node
            owner.renderChildren[#owner.renderChildren + 1] = node
        end
        node.position = { x = x, y = y, xParentPc = 0, yParentPc = 0, xSelfPc = 0, ySelfPc = 0 }
        node.size = { width = width, height = height, widthParentPc = 0, heightParentPc = 0 }
        node.nativeShown = true
        local spriteMeta = getmetatable(node)
        setmetatable(node, { __index = function(self, key)
            if key == "xyGlobal" then
                local origin = self.parent and self.parent.xyGlobal or { x = 0, y = 0 }
                return { x = origin.x + self.x, y = origin.y + self.y }
            elseif key == "visibleGlobal" then
                return self.nativeShown and self.visible ~= false and not self.hidden
                    and (not self.parent or self.parent.visibleGlobal ~= false)
            end
            return spriteMeta.__index(self, key)
        end, __newindex = spriteMeta.__newindex })
        function node:SetPos(px, py, xp, yp, xs, ys)
            self.position = { x = px, y = py, xParentPc = xp or 0, yParentPc = yp or 0,
                xSelfPc = xs or 0, ySelfPc = ys or 0 }
            self.x = px + (self.parent and self.parent.width or 0) * (xp or 0) - self.width * (xs or 0)
            self.y = py + (self.parent and self.parent.height or 0) * (yp or 0) - self.height * (ys or 0)
        end
        function node:SetSize(w, h, wp, hp)
            self.size = { width = w, height = h, widthParentPc = wp or 0, heightParentPc = hp or 0 }
            self.width = w + (self.parent and self.parent.width or 0) * (wp or 0)
            self.height = h + (self.parent and self.parent.height or 0) * (hp or 0)
            local pos = self.position
            self.x = pos.x + (self.parent and self.parent.width or 0) * pos.xParentPc - self.width * pos.xSelfPc
            self.y = pos.y + (self.parent and self.parent.height or 0) * pos.yParentPc - self.height * pos.ySelfPc
            for _, child in ipairs(self.children) do child:Relayout() end
            self:EmitResize()
        end
        function node:Relayout()
            local p, s = self.position, self.size
            self:SetPos(p.x, p.y, p.xParentPc, p.yParentPc, p.xSelfPc, p.ySelfPc)
            self:SetSize(s.width, s.height, s.widthParentPc, s.heightParentPc)
        end
        function node:IterateStaticComponents(callback)
            for _, child in ipairs(self.children) do
                if child.categoryID == -1 and callback(child, child.visibleGlobal) then return end
            end
        end
        function node:MoveToFront()
            if not self.parent then return end
            removeChild(self.parent, self)
            assert(removeRenderChild(self.parent, self), "native frame remains in its parent's render list")
            self.parent.children[#self.parent.children + 1] = self
            self.parent.renderChildren[#self.parent.renderChildren + 1] = self
        end
        node.x, node.y, node.width, node.height = x, y, width, height
        local retired = nativeNodes[(interfaceID << 16) | staticID]
        if retired then
            removeChild(retired.parent, retired)
            removeRenderChild(retired.parent, retired)
            retired.destroyed = true
        end
        nativeNodes[(interfaceID << 16) | staticID] = node
        return node
    end
    local area = nativeNode(1477, 61, nil, 80, 40, 1000, 700)
    -- Sample painter order as well as visibility: a sibling can cover live tabs.
    local function paintedAt(node, x, y, transparentSprite)
        if node.hidden or node.visibleGlobal == false then return nil end
        local origin = node.xyGlobal
        if x < origin.x or x >= origin.x + node.width
            or y < origin.y or y >= origin.y + node.height then return nil end
        for index = #node.renderChildren, 1, -1 do
            local painted = paintedAt(node.renderChildren[index],
                x + (node.scrollX or 0), y + (node.scrollY or 0), transparentSprite)
            if painted then return painted end
        end
        return (node.spriteID or node.runtimeSprite) and node.spriteID ~= transparentSprite and node or nil
    end
    local frames = {}
    function area:IterateStaticComponents(callback)
        for _, frame in ipairs(frames) do if callback(frame, frame.visibleGlobal) then break end end
    end
    local function host(first, name, shown, icons)
        local frame = nativeNode(1477, first, area, 500, 100, 379, 357)
        frame.nativeShown = shown
        frames[#frames + 1] = frame
        local body = nativeNode(1477, first + 2, frame, 4, 44, 371, 309)
        nativeNode(1477, first + 3, frame, 4, 44, 371, 309)
        local scroll = nativeNode(1477, first + 4, frame, 4, 44, 371, 309)
        nativeNode(1477, first + 7, frame, 0, 16, 379, 28)
        local tabs = nativeNode(1477, first + 8, frame, 4, 16, 371, 28)
        tabs.visible = true
        local tabControls = nativeNode(1477, first + 9, frame, 4, 16, 371, 28)
        local prefix, suffix = name:match("^(.+_WINDOW)(.*)$")
        if not prefix then
            prefix, suffix = name == "NOTES" and "NOTES_WINDOW" or "ABILITY_WINDOW",
                name == "NOTES" and "" or "_" .. name
        end
        id.Component["TOPLEVEL_V2__" .. prefix .. suffix] = (1477 << 16) | first
        id.Component["TOPLEVEL_V2__" .. prefix .. "_CONTENT" .. suffix] = (1477 << 16) | (first + 2)
        id.Component["TOPLEVEL_V2__" .. prefix .. "_EDIT_BLOCK" .. suffix] = (1477 << 16) | (first + 3)
        id.Component["TOPLEVEL_V2__" .. prefix .. "_SCROLL" .. suffix] = (1477 << 16) | (first + 4)
        id.Component["TOPLEVEL_V2__" .. prefix .. "_TABS" .. suffix] = (1477 << 16) | (first + 8)
        id.Component["TOPLEVEL_V2__" .. prefix .. "_TABS_SCROLL" .. suffix] = (1477 << 16) | (first + 9)
        id.Component["TOPLEVEL_V2__" .. prefix .. "_TAB_BACKGROUND" .. suffix] = (1477 << 16) | (first + 7)
        local result = { frame = frame, body = body, scroll = scroll, tabs = tabs, tabControls = tabControls }
        function result:rebuild(order, selected)
            for _, child in ipairs({ table.unpack(tabs.children) }) do child:Destroy() end
            self.backgrounds = {}
            for index, iconID in ipairs(order) do
                local background = component(tabs, "sprite", 0, (index - 1) * 4)
                background.type, background.visible, background.nativeShown = 3, true, true
                background.strictNativeHooks = true
                background.dragConfig.renderBehaviour = ui.DragRenderBehaviour.OPAQUE
                setmetatable(background, getmetatable(tabs))
                background:SetPos((index - 1) * 44, 0)
                background:SetSize(44, 28)
                background.spriteID = index == selected
                    and id.Sprite.RS3_CHILD_TAB_SELECTED or id.Sprite.RS3_CHILD_TAB_UNSELECTED
                self.backgrounds[index] = background
                local icon = component(tabs, "sprite", 0, (index - 1) * 4 + 1)
                icon.type, icon.visible, icon.nativeShown = 3, true, true
                icon.strictNativeHooks = true
                icon.dragConfig.renderBehaviour = ui.DragRenderBehaviour.OPAQUE
                setmetatable(icon, getmetatable(tabs))
                icon:SetPos((index - 1) * 44 + 10, 2)
                icon:SetSize(24, 24)
                icon.spriteID = iconID
            end
        end
        result:rebuild(icons or { 9001, 9002 }, icons and 1 or (shown and 1 or 2))
        return result
    end
    local notes = host(545, "NOTES", true)
    local ranged = host(158, "RANGED", false)
    local magic = host(2000, "MAGIC", false, { 9003 })
    magic.frame:SetPos(50, 200)
    local wrapper = nativeNode(1417, 3, notes.body, 0, 0, 371, 309)
    wrapper:SetSize(0, 0, 1, 1)
    id.Component.NOTES_CHILD__WRAPPER = (1417 << 16) | 3
    setmetatable(id.Component, { __pairs = function(values)
        local name
        return function()
            name = next(values, name)
            if name then return values[name], name end
        end
    end })
    function ui.Interfaces:GetComponent(first, second, ...)
        if select("#", ...) == 0 then
            local packed = second and ((first << 16) | second) or first
            if nativeNodes[packed] then return nativeNodes[packed] end
        end
        return oldGet(self, first, second, ...)
    end
    function ui.Interfaces:GetInterface(number)
        local loaded = oldInterface(self, number)
        if loaded and (number == 1477 or number == 1417) then
            -- Interface wrappers need not have stable Lua object identity.
            return setmetatable({ id = number }, { __index = loaded })
        end
        return loaded
    end
    f.parent = area
    return { area = area, notes = notes, ranged = ranged, magic = magic,
        wrapper = wrapper, node = nativeNode, host = host, nodes = nativeNodes,
        paintedAt = paintedAt }
end
