local Data = require("src/core/chart_data")
local Renderer = require("src/core/bar_renderer")

local BarChart = setmetatable({}, { __index = Renderer })
BarChart.__index = BarChart
BarChart.getSize = Renderer.getSize

-- Rows remain in caller order. label is the heading; there is no unit suffix
-- or implicit aggregation. Inputs and snapshots never alias chart-owned rows.
function BarChart.new(parent, options)
    options = options or {}
    local orientation = options.orientation == nil and "horizontal" or options.orientation
    assert(orientation == "horizontal" or orientation == "vertical", "bar orientation must be horizontal or vertical")
    local rows = Data.rows(options.data == nil and {} or options.data, options.rgba)
    local self = setmetatable({ kind = "bar", orientation = orientation, rows = rows }, BarChart)
    return Renderer.init(self, parent, options)
end

function BarChart:SetData(rows)
    if self.root == nil then return false end
    local copy = Data.rows(rows, self.barRGBA)
    self.rows = copy
    self:_DataChanged()
    return true
end

function BarChart:GetSnapshot()
    return { label = self.label, data = Data.copyRows(self.rows, false) }
end

function BarChart:Reset()
    if self.root == nil then return false end
    self.rows = {}
    self:_DataChanged()
    return true
end

function BarChart.Shutdown()
    Renderer.shutdown("bar")
end

return BarChart
