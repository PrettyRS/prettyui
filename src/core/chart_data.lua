local hsvToRgb = require("src/core/colour").hsvToRgb

local Data = {}

-- Sampling includes every empty interval between the extrema. Bound the span
-- before allocating those intervals; explicit bins obey the same 1,024-bin cap.
Data.MAX_BINS = 1024
local MAX_SAFE_INTEGER = 9007199254740991

function Data.finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Data.arrayLength(values, name)
    assert(type(values) == "table", name .. " must be an array")
    local count = 0
    for key in pairs(values) do
        assert(Data.finite(key) and key >= 1 and key == math.floor(key), name .. " must be a dense array")
        count = count + 1
    end
    for index = 1, count do
        assert(rawget(values, index) ~= nil, name .. " must be a dense array")
    end
    return count
end

function Data.colour(value)
    assert(
        value == nil or (Data.finite(value) and value >= 0 and value <= 0xFFFFFFFF and value == math.floor(value)),
        "chart rgba must be an unsigned 32-bit integer"
    )
    return value
end

local function categoryColour(id)
    -- Stable across sorting, removal/reinsertion, and independent chart views.
    -- Mix the string hash so similar IDs (such as adjacent skill IDs) do not
    -- cluster into the same hue. Restrict saturation/value for the dark theme.
    local hash = 2166136261
    for index = 1, #id do
        hash = ((hash ~ id:byte(index)) * 16777619) & 0xFFFFFFFF
    end
    hash = ((hash ~ (hash >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
    hash = ((hash ~ (hash >> 16)) * 0x45D9F3B) & 0xFFFFFFFF
    hash = hash ~ (hash >> 16)
    local hue = (hash % 3600) / 3600
    local saturation = 0.55 + ((hash >> 12) & 255) / 255 * 0.20
    local value = 0.80 + ((hash >> 20) & 255) / 255 * 0.12
    local red, green, blue = hsvToRgb(hue, saturation, value)
    return (math.floor(red * 255 + 0.5) << 24)
        | (math.floor(green * 255 + 0.5) << 16)
        | (math.floor(blue * 255 + 0.5) << 8)
        | 255
end

function Data.rows(rows, defaultRGBA)
    local count = Data.arrayLength(rows, "bar data")
    local copy = {}
    for index = 1, count do
        local row = rows[index]
        assert(
            type(row) == "table" and type(row.id) == "string" and type(row.label) == "string" and Data.finite(row.value),
            "bar rows require string id, string label and finite value"
        )
        copy[index] = {
            id = row.id,
            label = row.label,
            value = row.value,
            rgba = Data.colour(row.rgba) or defaultRGBA or categoryColour(row.id),
        }
    end
    return copy
end

function Data.bins(bins)
    local count = Data.arrayLength(bins, "histogram bins")
    assert(count <= Data.MAX_BINS, "histogram exceeds the 1024-bin budget")
    local copy, sampleCount, previousUpper = {}, 0, nil
    for index = 1, count do
        local bin = bins[index]
        assert(
            type(bin) == "table" and Data.finite(bin.lower) and Data.finite(bin.upper) and bin.lower < bin.upper,
            "histogram bins require finite increasing lower and upper bounds"
        )
        assert(previousUpper == nil or previousUpper == bin.lower, "histogram bins must be ordered and contiguous")
        assert(
            Data.finite(bin.count)
                and bin.count >= 0
                and bin.count <= MAX_SAFE_INTEGER
                and bin.count == math.floor(bin.count),
            "histogram counts must be nonnegative safe integers"
        )
        assert(bin.count <= MAX_SAFE_INTEGER - sampleCount, "histogram sample count exceeds the safe integer range")
        sampleCount = sampleCount + bin.count
        copy[index] = { lower = bin.lower, upper = bin.upper, count = bin.count }
        previousUpper = bin.upper
    end
    return copy, sampleCount
end

function Data.samples(samples, binWidth, origin)
    local count = Data.arrayLength(samples, "histogram samples")
    local counts, first, last = {}, nil, nil
    for index = 1, count do
        local value = samples[index]
        assert(Data.finite(value), "histogram samples must be finite numbers")
        local offset = (value - origin) / binWidth
        assert(Data.finite(offset), "histogram sample offset is not representable")
        local slot = math.floor(offset)
        -- Adjacent integer boundaries and their physical values must remain
        -- representable; accepting rounded/collapsed bins would misclassify data.
        assert(math.abs(slot) < MAX_SAFE_INTEGER, "histogram bin index exceeds the safe integer range")
        first = first and math.min(first, slot) or slot
        last = last and math.max(last, slot) or slot
        assert(last - first < Data.MAX_BINS, "histogram exceeds the 1024-bin budget")
        counts[slot] = (counts[slot] or 0) + 1
    end
    local bins = {}
    if first == nil then return bins, 0 end
    local lower = origin + first * binWidth
    for slot = first, last do
        local upper = origin + (slot + 1) * binWidth
        assert(
            Data.finite(lower) and Data.finite(upper) and lower < upper,
            "histogram bin boundaries are not representable"
        )
        bins[#bins + 1] = { lower = lower, upper = upper, count = counts[slot] or 0 }
        lower = upper
    end
    return bins, count
end

function Data.copyRows(rows, histogram)
    local copy = {}
    for index, row in ipairs(rows) do
        if histogram then
            copy[index] = { lower = row.lower, upper = row.upper, count = row.count }
        else
            copy[index] = { id = row.id, label = row.label, value = row.value, rgba = row.rgba }
        end
    end
    return copy
end

return Data
