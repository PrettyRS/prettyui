local ContentMethods = require("src/core/content_methods")
local Layout = require("src/core/layout")
local Scroll = require("src/core/scroll")
local Tooltip = require("src/tooltip")

local SimpleView = {}
SimpleView.__index = SimpleView
setmetatable(SimpleView, { __index = Scroll })

function SimpleView.new(parent, options)
    options = options or {}

    local parentContext = Tooltip.getContext(parent)
    local tooltipParent = parentContext and parentContext.parent or parent
    local ownerWindow = Scroll.findOwnerWindow(parentContext)
    local controller = Scroll.new(parent, {
        categoryID = options.categoryID,
        _categoryPolicy = options._categoryPolicy,
        x = options.x,
        y = options.y,
        xAnchor = options.xAnchor,
        yAnchor = options.yAnchor,
        width = options.width,
        height = options.height,
        widthAnchor = options.widthAnchor,
        heightAnchor = options.heightAnchor,
        contentHeight = options.contentHeight,
        scrollable = options.scrollable,
        scrollStep = options.scrollStep,
        _onScrollWheel = options._onScrollWheel,
        parentContext = parentContext,
        overlayParent = tooltipParent,
        ownerWindow = ownerWindow,
        position = function(root)
            if parentContext then return parentContext.position(root) end
            return root.x or 0, root.y or 0
        end,
    })
    local self = setmetatable(controller, SimpleView)
    self.tooltipContext = Tooltip.registerContext(
        self.content,
        tooltipParent,
        function(target)
            local rootX, rootY = self:_AbsolutePosition()
            return rootX + (target.x or 0), rootY + (target.y or 0) - self.scrollY
        end,
        parentContext
    )
    Layout.configure(self, options.layout or options.textLayout)
    Tooltip.bind(self, self.root, parent, options.tooltip)
    return self
end

ContentMethods.installSingle(SimpleView)

function SimpleView:_FitContent()
    self.root:SetHeight(math.max(1, self.contentHeight))
    self:Refresh()
end

function SimpleView:SetTooltip(value)
    return Tooltip.set(self, value)
end

function SimpleView:Destroy()
    if self.content then
        Tooltip.unregisterContext(self.content)
        self.tooltipContext = nil
    end
    Layout.destroyManaged(self)
    Tooltip.unbind(self)
    Scroll.Destroy(self)
end

return SimpleView
