local InterfaceMouse = {}

local DEFAULT_SCALE_PERCENT = 100
local eventOrigins = setmetatable({}, { __mode = "k" })
local calibratedScale
local calibratedInterfaceScale

local function getInterfaceScale()
    local options = game and game.options
    local interfaceScale = options and options.InterfaceScale
    local percent = interfaceScale and tonumber(interfaceScale.setting) or DEFAULT_SCALE_PERCENT
    if percent <= 0 then percent = DEFAULT_SCALE_PERCENT end
    return percent / DEFAULT_SCALE_PERCENT
end

local function screenScale(raw, expectedX, expectedY)
    local scaleX = math.abs(expectedX) >= 32 and raw.x / expectedX or nil
    local scaleY = math.abs(expectedY) >= 32 and raw.y / expectedY or nil
    if scaleX ~= nil and (scaleX < 0.5 or scaleX > 4) then scaleX = nil end
    if scaleY ~= nil and (scaleY < 0.5 or scaleY > 4) then scaleY = nil end
    if scaleX ~= nil and scaleY ~= nil then
        local average = (scaleX + scaleY) / 2
        if math.abs(scaleX - scaleY) <= average * 0.1 then
            return math.abs(expectedX) >= math.abs(expectedY) and scaleX or scaleY
        end
        return nil
    end
    return scaleX or scaleY
end

local function currentScreenScale()
    local interfaceScale = getInterfaceScale()
    if calibratedInterfaceScale == interfaceScale then return calibratedScale end
    return interfaceScale
end

-- Hook positions are in interface units; raw mouse positions may additionally
-- include OS display scaling. A native hook supplies both coordinate systems.
function InterfaceMouse.CalibrateFromHook(component, x, y)
    if component == nil or type(x) ~= "number" or type(y) ~= "number" then return false end
    local raw = Mouse.GetPosition()
    local origin = component.xyGlobal
    if raw == nil or origin == nil then return false end
    local scale = screenScale(raw, origin.x + x, origin.y + y)
    if scale == nil then return false end
    calibratedScale = scale
    calibratedInterfaceScale = getInterfaceScale()
    return true
end

function InterfaceMouse.FromRawPosition(raw)
    if raw == nil then return nil end
    local scale = currentScreenScale()
    return { x = raw.x / scale, y = raw.y / scale }
end

-- Pointer hooks supply coordinates in interface units relative to their
-- component. Prefer those coordinates when available because raw window pixels
-- are also affected by OS display scaling. Adding the component position returns
-- coordinates in its parent's interface space.
function InterfaceMouse.GetPosition(component, x, y)
    if component ~= nil and type(x) == "number" and type(y) == "number" then
        local origin = eventOrigins[component]
        if origin and origin.screenScale then
            local raw = Mouse.GetPosition()
            if raw ~= nil then
                return {
                    x = raw.x / origin.screenScale,
                    y = raw.y / origin.screenScale,
                }
            end
        end
        return {
            x = (origin and origin.x or component.x or 0) + x,
            y = (origin and origin.y or component.y or 0) + y,
        }
    end

    return InterfaceMouse.FromRawPosition(Mouse.GetPosition())
end

function InterfaceMouse.BeginScreenCapture(component, x, y)
    if component == nil then return end
    local originX = component.x or 0
    local originY = component.y or 0
    local raw = Mouse.GetPosition()
    eventOrigins[component] = {
        x = originX,
        y = originY,
        screenScale = raw and screenScale(raw, originX + x, originY + y) or currentScreenScale(),
    }
end

function InterfaceMouse.BeginCapture(component)
    if component == nil then return end
    eventOrigins[component] = {
        x = component.x or 0,
        y = component.y or 0,
    }
end

function InterfaceMouse.EndCapture(component)
    if component ~= nil then eventOrigins[component] = nil end
end

return InterfaceMouse
