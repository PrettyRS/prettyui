local Components = require("src/core/components")
local RowBackgrounds = {}
local BACKGROUND_PADDING = 4

function RowBackgrounds.clear(backgrounds, interfaceID)
    if ui.Interfaces:GetInterface(interfaceID) == nil then return end
    for _, background in ipairs(backgrounds or {}) do
        background:Destroy()
    end
end


function RowBackgrounds.apply(content, viewportHeight, owner, colours, edgeToEdge)
    local backgrounds = {}
    if type(colours) ~= "table" or #colours == 0 then return backgrounds end

    local rowsByY = {}
    for _, entry in ipairs(owner._managedFlowEntries or {}) do
        local placement = entry.placement or {}
        local component = entry.component
        local root = component and (component.root or component) or nil
        if placement._flowAbsolute ~= true then
            local y = math.floor(tonumber(root and root.y) or tonumber(placement.y) or 0)
            local height = math.max(
                0,
                math.floor(tonumber(root and root.height) or tonumber(placement.height) or 0))
            local row = rowsByY[y]
            if row == nil then
                row = { top = y, bottom = y + height }
                rowsByY[y] = row
            else
                row.bottom = math.max(row.bottom, y + height)
            end

            if placement.rowBackground ~= false then
                row.included = true
                local group = placement.rowBackgroundGroup
                if group ~= nil then
                    if row.groupSet and row.group ~= group then
                        error("Components sharing a flow row must use the same rowBackgroundGroup")
                    end
                    row.group = group
                    row.groupSet = true
                end
            end
        end
    end

    local rowYs = {}
    for y in pairs(rowsByY) do rowYs[#rowYs + 1] = y end
    table.sort(rowYs)

    local regions = {}
    for _, y in ipairs(rowYs) do
        local row = rowsByY[y]
        local region = regions[#regions]
        if row.included ~= true then
            regions[#regions + 1] = {
                top = row.top,
                bottom = row.bottom,
                excluded = true,
            }
        elseif row.groupSet
            and region
            and region.excluded ~= true
            and region.groupSet
            and region.group == row.group then
            region.bottom = math.max(region.bottom, row.bottom)
        else
            regions[#regions + 1] = {
                top = row.top,
                bottom = row.bottom,
                group = row.group,
                groupSet = row.groupSet,
            }
        end
    end

    local contentHeight = 0
    local paddingLeft = 0
    local paddingRight = 0
    if edgeToEdge == true then
        contentHeight = math.max(
            tonumber(viewportHeight) or 0,
            tonumber(owner.contentHeight) or 0)
    else
        local layout = owner._flowLayout or {}
        paddingLeft = tonumber(layout.paddingLeft) or 0
        paddingRight = tonumber(layout.paddingRight) or 0
    end

    local colourIndex = 0
    for index, region in ipairs(regions) do
        if region.excluded ~= true then
            local top = region.top
            local bottom = region.bottom
            local left = paddingLeft
            local width = -(paddingLeft + paddingRight)
            if edgeToEdge == true then
                local centre = (region.top + region.bottom) * 0.5
                local previous = regions[index - 1]
                local following = regions[index + 1]
                top = previous == nil and 0 or math.floor(
                    ((previous.top + previous.bottom) * 0.5 + centre) * 0.5 + 0.5)
                bottom = following == nil and contentHeight or math.floor(
                    (centre + (following.top + following.bottom) * 0.5) * 0.5 + 0.5)
                left = 0
                width = 0
            end
            if edgeToEdge ~= true then
                top = top - BACKGROUND_PADDING
                bottom = bottom + BACKGROUND_PADDING
                left = left - BACKGROUND_PADDING
                width = width + BACKGROUND_PADDING * 2
            end
            colourIndex = colourIndex + 1
            local background = Components.new(ui.Rectangle, content)
            background:SetPos(left, top)
            background:SetSize(width, math.max(0, bottom - top), 1.0, 0)
            background.fill = true
            background.rgba = colours[(colourIndex - 1) % #colours + 1]
            background.clickthrough = true
            background:MoveToBack()
            backgrounds[#backgrounds + 1] = background
        end
    end

    return backgrounds
end

return RowBackgrounds
