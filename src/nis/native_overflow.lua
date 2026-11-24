-- Native tabs retain their own layer and scroll region. Only artwork and input
-- for the navigation gutters belong to GAME_AREA.
local Components = require("src/core/components")

local Overflow = {}
Overflow.__index = Overflow

local HEIGHT, GUTTER, STEP = 28, 11, 40
local positions = { "x", "y", "xParentPc", "yParentPc", "xSelfPc", "ySelfPc" }
local sizes = { "width", "height", "widthParentPc", "heightParentPc" }

local function ids(component)
    if not component then return nil end
    local ok, a, b, c, d = pcall(
        function()
            return component.interfaceID, component.staticID, component.categoryID, component.dynamicID
        end
    )
    if not ok or type(a) ~= "number" or type(b) ~= "number" or type(c) ~= "number" or type(d) ~= "number" then
        return nil
    end
    return a, b, c, d
end

local function matchesID(record, component)
    local a, b, c, d = ids(component)
    return a
        and record
        and a == record.interfaceID
        and b == record.staticID
        and c == record.categoryID
        and d == record.dynamicID
end

local function sameIDs(first, second)
    local a, b, c, d = ids(first)
    local e, f, g, h = ids(second)
    return a and e and a == e and b == f and c == g and d == h
end

local function loaded(component)
    local a, b, c, d = ids(component)
    if not a or not ui.Interfaces:GetInterface(a) then return nil end
    local fresh
    if c == -1 then
        fresh = ui.Interfaces:GetComponent(a, b)
    else
        fresh = ui.Interfaces:GetComponent(a, b, c, d)
    end
    local fa, fb, fc, fd = ids(fresh)
    if fa == a and fb == b and fc == c and fd == d then return fresh end
    return nil
end

local function native(host, field)
    local handle = host[field]
    local fresh = handle and loaded(handle)
    if fresh and sameIDs(fresh.parent, host.frame) then return fresh end
    return nil
end

local function capture(object, fields)
    local values = {}
    for index, field in ipairs(fields) do
        local value = object[field]
        if type(value) ~= "number" then return nil end
        values[index] = value
    end
    return values
end

local function matches(object, fields, values)
    if not values then return false end
    for index, field in ipairs(fields) do
        if object[field] ~= values[index] then return false end
    end
    return true
end

local function scrollSize(component)
    return { component.scrollWidth, component.scrollHeight }
end

local function scrollPos(component)
    return { component.scrollX, component.scrollY }
end

local function matchesExtent(component, values)
    return values and component.scrollWidth == values[1] and component.scrollHeight == values[2]
end

local function matchesScroll(component, values)
    return values and component.scrollX == values[1] and component.scrollY == values[2]
end

local function observe(record, component)
    local pos, size = component.position, component.size
    if not matches(pos, positions, record.writtenPosition or record.position) then
        record.position = capture(pos, positions)
        record.writtenPosition = nil
    end
    if not matches(size, sizes, record.writtenSize or record.size) then
        record.size = capture(size, sizes)
        record.writtenSize = nil
    end
    if not matchesExtent(component, record.writtenExtent or record.extent) then
        record.extent = scrollSize(component)
        record.writtenExtent = nil
    end
    if not matchesScroll(component, record.writtenScroll or record.scroll) then
        record.scroll = scrollPos(component)
        record.writtenScroll = nil
    end
    return pos, size
end

local function restoreNative(record, host, field)
    if not record then return end
    local component = native(host, field)
    if not component or not matchesID(record, component) then return end
    -- Decide ownership before setters: restoring the viewport or scroll extent
    -- can itself change the scroll position by clamping it.
    local ownPosition = matches(component.position, positions, record.writtenPosition)
    local ownSize = matches(component.size, sizes, record.writtenSize)
    local ownExtent = matchesExtent(component, record.writtenExtent)
    local ownScroll = matchesScroll(component, record.writtenScroll)
    if ownPosition then component:SetPos(table.unpack(record.position, 1, 6)) end
    if ownSize then component:SetSize(table.unpack(record.size, 1, 4)) end
    if ownExtent then component:SetScrollSize(record.extent[1], record.extent[2]) end
    if ownScroll then component:SetScrollPos(record.scroll[1], record.scroll[2]) end
end

local function recordFor(view, component)
    local record = view.tabState
    if not matchesID(record, component) then
        local a, b, c, d = ids(component)
        record = { interfaceID = a, staticID = b, categoryID = c, dynamicID = d }
        view.tabState = record
    end
    return record
end

local function setNative(view, width, total, offset, overflow)
    local component = native(view.host, "tabs")
    if not component then
        view.tabState = nil
        return
    end
    local record = recordFor(view, component)
    local pos, size = observe(record, component)
    if not record.position or not record.size then return end
    local beforeExtentX, beforeExtentY = component.scrollWidth, component.scrollHeight
    local beforeScrollX, beforeScrollY = component.scrollX, component.scrollY
    local desiredX = view.host.content.x + (overflow and GUTTER or 0)
    -- Retain native parent/self anchors so the viewport follows a frame resize
    -- immediately, before the next PrettyUI layout pass.
    if component.x ~= desiredX then
        component:SetPos(pos.x + desiredX - component.x, pos.y, pos.xParentPc, pos.yParentPc, pos.xSelfPc, pos.ySelfPc)
        record.writtenPosition = capture(component.position, positions)
    end
    if component.width ~= width then
        component:SetSize(size.width + width - component.width, size.height, size.widthParentPc, size.heightParentPc)
        record.writtenSize = capture(component.size, sizes)
    end
    -- Extents precede the position: resizing can clamp the current scroll.
    if component.scrollWidth ~= total or component.scrollHeight ~= HEIGHT then
        component:SetScrollSize(total, HEIGHT)
        record.writtenExtent = scrollSize(component)
    end
    -- Resizing or changing the extent may clamp a scroll position without an
    -- explicit SetScrollPos call; that change is still ours to undo.
    if component.scrollWidth ~= beforeExtentX or component.scrollHeight ~= beforeExtentY then
        record.writtenExtent = scrollSize(component)
    end
    if component.scrollX ~= beforeScrollX or component.scrollY ~= beforeScrollY then
        record.writtenScroll = scrollPos(component)
    end
    if component.scrollX ~= offset or component.scrollY ~= 0 then
        component:SetScrollPos(offset, 0)
        record.writtenScroll = scrollPos(component)
    end
end

local function controlFor(view, component)
    local record = view.controlsState
    if not matchesID(record, component) then
        local a, b, c, d = ids(component)
        record = { interfaceID = a, staticID = b, categoryID = c, dynamicID = d, hidden = component.hidden }
        view.controlsState = record
    elseif record.written ~= nil and component.hidden ~= record.written then
        record.hidden, record.written = component.hidden, nil
    end
    if not component.hidden then
        component.hidden = true
        record.written = true
    end
end

local function restoreControls(view)
    local record = view.controlsState
    if not record then return end
    local component = native(view.host, "tabControls")
    if component and matchesID(record, component) and record.written ~= nil and component.hidden == record.written then
        component.hidden = record.hidden
    end
    view.controlsState = nil
end

local function visible(component, show)
    if component.hidden == show then Components.setHidden(component, not show) end
end

local function arrow(view, right)
    local sprite = Components.new(ui.Sprite, view.host.chrome, { _categoryPolicy = "auto" })
    sprite.spriteID = id.Sprite.RS3_BTN_CHILD_TAB_SCROLL_SML_4
    sprite.isFlippedHorizontally = right
    sprite:SetSize(GUTTER, 18)
    sprite.clickthrough, sprite.enabled = true, false
    visible(sprite, false)
    local hit = Components.new(ui.Layer, view.host.area or view.area, {
        _categoryPolicy = Components.policyOf(view.host.chrome),
    })
    hit:SetSize(GUTTER, HEIGHT)
    hit.clickthrough, hit.enabled = false, false
    visible(hit, false)
    hit:Subscribe(ui.Hook.ONCLICK, function()
        if
            view.shown
            and view.clickEnabled
            and view.onScroll
            and (right and view.scrollX < view.maxScroll or not right and view.scrollX > 0)
        then
            view.onScroll(right and STEP or -STEP)
        end
        return false
    end)
    return sprite, hit
end

local function ensureArrows(view)
    if view.leftArrow then return end
    view.leftArrow, view.leftHit = arrow(view, false)
    view.rightArrow, view.rightHit = arrow(view, true)
end

function Overflow.width(host, total)
    local width = host.content.width
    return math.max(1, total > width and width - 2 * GUTTER or width)
end

function Overflow.new(host, area, onScroll)
    local band = host.grouped and host.tabs or host.content
    local self = setmetatable({
        host = host,
        area = area,
        onScroll = onScroll,
        scrollX = host.grouped and (host.tabs.scrollX or 0) or 0,
        maxScroll = 0,
        shown = false,
    }, Overflow)
    self.viewport = Components.new(ui.Layer, host.chrome, { _categoryPolicy = "auto" })
    self.viewport:SetPos(0, 0)
    self.viewport:SetSize(host.chrome.width, host.chrome.height)
    self.viewport.clickthrough, self.viewport.enabled = true, false
    self.x, self.y, self.width = band.x, band.y, band.width
    self.bandWidth = host.content.width
    return self
end

local function layoutViewport(view, host, x, y, width, total, overflow)
    local viewport = view.viewport
    local vx, vy = overflow and x or 0, overflow and y or 0
    local vw, vh = overflow and width or host.chrome.width, overflow and HEIGHT or host.chrome.height
    if viewport.x ~= vx or viewport.y ~= vy then viewport:SetPos(vx, vy) end
    if viewport.width ~= vw or viewport.height ~= vh then viewport:SetSize(vw, vh) end
    local extent = overflow and math.max(total, vw + 1) or vw
    if viewport.scrollWidth ~= extent or viewport.scrollHeight ~= vh then
        viewport:SetScrollSize(extent, vh)
    end
    if viewport.scrollX ~= 0 or viewport.scrollY ~= 0 then viewport:SetScrollPos(0, 0) end
end

local function layoutNative(view, host, width, total, offset, overflow)
    if host.manageNative ~= false then
        if host.grouped then setNative(view, width, total, offset, overflow) end
        local controls = native(host, "tabControls")
        if controls then
            controlFor(view, controls)
        else
            view.controlsState = nil
        end
    else
        -- A preview over an occupied row shares the group's native strip and
        -- its already-owned navigation. Its viewport is independent artwork.
        view.tabState, view.controlsState = nil, nil
    end
end

local function positionArrows(view, content, y, bandWidth)
    local leftX, rightX = content.x + 1, content.x + bandWidth - GUTTER - 1
    if view.leftArrow.x ~= leftX or view.leftArrow.y ~= y + 5 then
        view.leftArrow:SetPos(leftX, y + 5)
    end
    if view.rightArrow.x ~= rightX or view.rightArrow.y ~= y + 5 then
        view.rightArrow:SetPos(rightX, y + 5)
    end
    local frame = view.host.frame
    local hx, hy = frame.x + content.x, frame.y + y
    local rightHitX = hx + bandWidth - GUTTER
    if view.leftHit.x ~= hx or view.leftHit.y ~= hy then view.leftHit:SetPos(hx, hy) end
    if view.rightHit.x ~= rightHitX or view.rightHit.y ~= hy then
        view.rightHit:SetPos(rightHitX, hy)
    end
end

local function styleArrows(view, display, offset, maxScroll)
    local leftEnabled = display and view.clickEnabled and offset > 0
    local rightEnabled = display and view.clickEnabled and offset < maxScroll
    local leftSprite = id.Sprite[leftEnabled and "RS3_BTN_CHILD_TAB_SCROLL_SML_0" or "RS3_BTN_CHILD_TAB_SCROLL_SML_4"]
    local rightSprite = id.Sprite[rightEnabled and "RS3_BTN_CHILD_TAB_SCROLL_SML_0" or "RS3_BTN_CHILD_TAB_SCROLL_SML_4"]
    if view.leftArrow.spriteID ~= leftSprite then view.leftArrow.spriteID = leftSprite end
    if view.rightArrow.spriteID ~= rightSprite then view.rightArrow.spriteID = rightSprite end
    visible(view.leftArrow, display)
    visible(view.rightArrow, display)
    visible(view.leftHit, display)
    visible(view.rightHit, display)
    if view.leftHit.enabled ~= leftEnabled then view.leftHit.enabled = leftEnabled end
    if view.rightHit.enabled ~= rightEnabled then view.rightHit.enabled = rightEnabled end
end

function Overflow:Layout(total, scrollX, show, enabled)
    local host, content = self.host, self.host.content
    local bandWidth = content.width
    local overflow = total > bandWidth
    local width = Overflow.width(host, total)
    local x = content.x + (overflow and GUTTER or 0)
    local y = host.grouped and host.tabs.y or content.y
    local maxScroll = math.max(0, total - width)
    local offset = math.min(maxScroll, math.max(0, math.floor(scrollX or 0)))
    self.x, self.y, self.width, self.bandWidth = x, y, width, bandWidth
    self.scrollX, self.maxScroll = offset, maxScroll
    layoutViewport(self, host, x, y, width, total, overflow)
    layoutNative(self, host, width, total, offset, overflow)

    local display = overflow and show == true and host.manageNative ~= false
    local newlyShown = display and not self.shown
    self.shown, self.clickEnabled = display, enabled ~= false
    if display then ensureArrows(self) end
    if self.leftArrow then
        positionArrows(self, content, y, bandWidth)
        styleArrows(self, display, offset, maxScroll)
        if newlyShown then self:Raise() end
    end
    return offset
end

function Overflow:Clip(x, width)
    local left = math.max(self.x, math.min(x, self.x + self.width))
    local right = math.min(self.x + self.width, x + width)
    return left, math.max(0, right - left)
end

function Overflow:Hide()
    self.shown = false
    if not self.leftHit then return end
    visible(self.leftArrow, false)
    visible(self.rightArrow, false)
    visible(self.leftHit, false)
    visible(self.rightHit, false)
    self.leftHit.enabled, self.rightHit.enabled = false, false
end

function Overflow:Raise()
    if not self.shown or not self.leftHit then return end
    self.leftHit:MoveToFront()
    self.rightHit:MoveToFront()
end

function Overflow:Restore()
    if self.tabState and self.host.manageNative ~= false then
        restoreNative(self.tabState, self.host, "tabs")
    end
    if self.host.manageNative ~= false then restoreControls(self) end
    self.tabState, self.controlsState = nil, nil
    self:Hide()
end

function Overflow:Destroy()
    self:Restore()
    if self.leftHit then
        if loaded(self.area) then
            if loaded(self.leftHit) then self.leftHit:Destroy() end
            if loaded(self.rightHit) then self.rightHit:Destroy() end
        end
        self.leftHit, self.rightHit = nil, nil
    end
    if self.viewport and loaded(self.host.chrome) then
        if self.leftArrow and loaded(self.leftArrow) then self.leftArrow:Destroy() end
        if self.rightArrow and loaded(self.rightArrow) then self.rightArrow:Destroy() end
        if loaded(self.viewport) then self.viewport:Destroy() end
    end
    self.leftArrow, self.rightArrow, self.viewport = nil, nil, nil
end

return Overflow
