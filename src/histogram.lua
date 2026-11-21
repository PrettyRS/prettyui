local Data = require("src/core/chart_data")
local Renderer = require("src/core/bar_renderer")

local Histogram = setmetatable({}, { __index = Renderer })
Histogram.__index = Histogram
Histogram.getSize = Renderer.getSize

-- [lower, upper) intervals use floor((sample - origin) / binWidth). Exact
-- boundaries enter the following bin, including for negative samples. The
-- inclusive first-to-last bin span, or explicit bin array, is capped at 1,024;
-- unrepresentable indices/bounds and unsafe counts are rejected atomically.
function Histogram.new(parent, options)
    options = options or {}
    local binWidth = options.binWidth == nil and 5 or options.binWidth
    local origin = options.origin == nil and 0 or options.origin
    assert(Data.finite(binWidth) and binWidth > 0, "histogram binWidth must be positive and finite")
    assert(Data.finite(origin), "histogram origin must be finite")
    local bins, sampleCount = Data.samples(options.samples == nil and {} or options.samples, binWidth, origin)
    local self = setmetatable({
        kind = "histogram",
        orientation = "vertical",
        rows = bins,
        binWidth = binWidth,
        origin = origin,
        sampleCount = sampleCount,
    }, Histogram)
    return Renderer.init(self, parent, options)
end

function Histogram:SetSamples(samples)
    if self.root == nil then return false end
    local bins, sampleCount = Data.samples(samples, self.binWidth, self.origin)
    self.rows, self.sampleCount = bins, sampleCount
    self:_DataChanged()
    return true
end

-- Explicit bins may have unequal widths, but must be increasing, contiguous
-- and finite. They replace sampled bins without changing sampling parameters.
function Histogram:SetBins(bins)
    if self.root == nil then return false end
    local copy, sampleCount = Data.bins(bins)
    self.rows, self.sampleCount = copy, sampleCount
    self:_DataChanged()
    return true
end

function Histogram:GetSnapshot()
    return {
        label = self.label,
        binWidth = self.binWidth,
        origin = self.origin,
        sampleCount = self.sampleCount,
        bins = Data.copyRows(self.rows, true),
    }
end

function Histogram:Reset()
    if self.root == nil then return false end
    self.rows, self.sampleCount = {}, 0
    self:_DataChanged()
    return true
end

function Histogram.Shutdown()
    Renderer.shutdown("histogram")
end

return Histogram
