local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- Sizes and positions follow their anchors live, as the client's do, so a parent
-- resize stretches anchored children without anyone telling them.
local function parentWidth(self) return self.parent and self.parent.width or 0 end
local function parentHeight(self) return self.parent and self.parent.height or 0 end
local geometry = {
    width = function(self) return self._width + parentWidth(self) * self._widthAnchor end,
    height = function(self) return self._height + parentHeight(self) * self._heightAnchor end,
    x = function(self) return self._x + parentWidth(self) * self._xAnchor end,
    y = function(self) return self._y + parentHeight(self) * self._yAnchor end,
}
local Component = {}
function Component:SetPos(x, y, xAnchor, yAnchor)
    self._x, self._y, self._xAnchor, self._yAnchor = x, y, xAnchor or 0, yAnchor or 0
end
function Component:SetSize(width, height, widthAnchor, heightAnchor)
    self._width, self._height = width, height
    self._widthAnchor, self._heightAnchor = widthAnchor or 0, heightAnchor or 0
end
function Component:SetX(x) self._x = x end
function Component:SetWidth(width, widthAnchor)
    self._width = width
    if widthAnchor ~= nil then self._widthAnchor = widthAnchor end
end
function Component:SetHeight(height) self._height = height end
function Component:SetScrollSize() end
function Component:SetScrollPos() end
function Component:Subscribe() end
function Component:Unsubscribe() end
function Component:MoveToBack() end
function Component:MoveToFront() end
function Component:Destroy() self.destroyed = true end
local metatable = {
    __index = function(self, key)
        if geometry[key] then return geometry[key](self) end
        return Component[key]
    end,
}

local function component(parent, categoryID, dynamicID)
    local value = setmetatable({
        parent = parent, hidden = false,
        _x = 0, _y = 0, _xAnchor = 0, _yAnchor = 0,
        _width = 0, _height = 0, _widthAnchor = 0, _heightAnchor = 0,
    }, metatable)
    return Interfaces.component(value, parent, categoryID, dynamicID)
end

ui = {
    Sprite = { new = component },
    Layer = { new = component },
    Hook = { ONCLICK = 1, ONMOUSEOVER = 2, ONMOUSELEAVE = 3, ONRELEASE = 4,
        ONHOLD = 5, ONDRAG = 6, ONDRAGCOMPLETE = 7 },
}
config = { Cursor = { CURSOR_BLANK = 0 } }
package.loaded["src/core/sprites"] = {
    SLIDER = {
        backingEnd = 2, backingTile = 3, barEnd = 4, barTile = 5,
        thumb = { normal = 6, disabled = 7 },
        decrease = { normal = 8, disabled = 9 },
        increase = { normal = 10, disabled = 11 },
    },
}
-- Hosts register a tooltip context on their content, naming it as the collection.
local contexts = {}
package.loaded["src/tooltip"] = {
    bind = function() end, unbind = function() end,
    getContext = function(collection) return contexts[collection] end,
}
package.loaded["src/core/wheel"] = { bind = function() end }
package.loaded["src/core/cursor"] = { apply = function() end }
package.loaded["src/core/mouse"] = { EndCapture = function() end }

local Scroll = require("src/core/scroll")
local Slider = require("src/slider")

local host = component()
host:SetSize(300, 200)
local scroll = Scroll.new(host, { width = 0, height = 0, widthAnchor = 1.0, heightAnchor = 1.0 })
local outerContext = { collection = scroll.content }
contexts[scroll.content] = outerContext
local slider = Slider.new(scroll.content, { x = 14, width = -28, widthAnchor = 1.0, value = 100 })

local function travel() return slider.track.width - slider.thumb.width end
expect(slider.thumb.x, travel(), "a full slider starts with its marker at the track end")

host:SetSize(500, 200)
scroll:Refresh()
expect(slider.thumb.x, travel(), "the marker follows the track end when the host widens")
expect(slider.thumbDrag.x, slider.root.x + slider.track.x + slider.thumb.x,
    "the marker's grab area follows it")

host:SetSize(260, 200)
scroll:Refresh()
expect(slider.thumb.x, travel(), "the marker stays inside the track when the host narrows")

slider:SetValue(50)
scroll:SetContentHeight(1000)
expect(slider.thumb.x, math.floor(travel() / 2 + 0.5), "a scrollbar appearing re-places the marker")

-- A nested scroll inside a frame anchored to the outer content, as a panel in a window has.
local frame = component(scroll.content)
frame:SetSize(-28, 120, 1.0)
local inner = Scroll.new(frame, {
    width = 0, height = 0, widthAnchor = 1.0, heightAnchor = 1.0, parentContext = outerContext,
})
expect(inner.parentScroll, scroll, "a nested scroll finds the scroll around it through its host's context")
local innerContext = { collection = inner.content, parentContext = outerContext }
contexts[inner.content] = innerContext
local nested = Slider.new(inner.content, { x = 14, width = -28, widthAnchor = 1.0, value = 100 })
expect(nested.widthScroll, inner, "a slider follows the nearest scroll around it")

-- A slider on a section inside the scroll, as in a collapse section, finds it through the chain.
local section = component(inner.content)
section:SetSize(0, 40, 1.0)
contexts[section] = { collection = section, parentContext = innerContext }
local sectionSlider = Slider.new(section, { width = 0, widthAnchor = 1.0 })
expect(sectionSlider.widthScroll, inner, "a slider in a section follows the scroll around the section")
sectionSlider:Destroy()
local function nestedTravel() return nested.track.width - nested.thumb.width end
local before = nestedTravel()
host:SetSize(600, 200)
scroll:Refresh()
expect(nestedTravel() > before, true, "a nested scroll's content stretches with the outer one")
expect(nested.thumb.x, nestedTravel(), "a nested slider's marker follows its track end")
nested:Destroy()
inner:Destroy()

slider:Destroy()
expect(next(scroll.widthTargets), nil, "a destroyed slider unregisters")
host:SetSize(400, 200)
scroll:Refresh()

local loose = Slider.new(host, { width = 200 })
expect(loose.widthScroll, nil, "a slider on a layer of its caller's listens to nothing")
loose:Destroy()

-- Its caller resizes the layer, then refreshes the slider itself.
local row = component(host)
row:SetSize(-28, 23, 1.0)
local rowSlider = Slider.new(row, { width = 0, widthAnchor = 1.0, value = 100 })
local function rowTravel() return rowSlider.track.width - rowSlider.thumb.width end
host:SetSize(700, 200)
expect(rowSlider.thumb.x < rowTravel(), true, "a slider on a caller's layer isn't told of a resize")
rowSlider:Refresh()
expect(rowSlider.thumb.x, rowTravel(), "Refresh places the marker at the track end again")
rowSlider:Destroy()

print("slider_resize_test: ok")
