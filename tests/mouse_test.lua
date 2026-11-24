local rawPosition

Mouse = {
    GetPosition = function()
        return rawPosition
    end,
}

game = {
    options = {
        InterfaceScale = {
            setting = 100,
        },
    },
}

local InterfaceMouse = require("src/core/mouse")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end
local function expectNear(actual, expected, message)
    if math.abs(actual - expected) > 1e-9 then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

rawPosition = { x = 600, y = 300 }
local position = InterfaceMouse.GetPosition()
expect(position.x, 600, "100% scale preserves x")
expect(position.y, 300, "100% scale preserves y")

game.options.InterfaceScale.setting = 150
position = InterfaceMouse.GetPosition()
expect(position.x, 400, "150% scale converts x to interface units")
expect(position.y, 200, "150% scale converts y to interface units")

game.options.InterfaceScale.setting = 300
position = InterfaceMouse.GetPosition()
expect(position.x, 200, "300% scale converts x to interface units")
expect(position.y, 100, "300% scale converts y to interface units")

rawPosition = nil
expect(InterfaceMouse.GetPosition(), nil, "unavailable mouse remains nil")

local eventPosition = InterfaceMouse.GetPosition({ x = 20, y = 30 }, 5, 7)
expect(eventPosition.x, 25, "hook coordinates include the component x position")
expect(eventPosition.y, 37, "hook coordinates include the component y position")

local capture = { x = 100, y = 80 }
InterfaceMouse.BeginCapture(capture)
capture.x, capture.y = 0, 0
eventPosition = InterfaceMouse.GetPosition(capture, 8, 9)
expect(eventPosition.x, 108, "capture preserves the original component x position")
expect(eventPosition.y, 89, "capture preserves the original component y position")
InterfaceMouse.EndCapture(capture)

rawPosition = { x = 250, y = 125 }
capture = { x = 100, y = 50 }
InterfaceMouse.BeginScreenCapture(capture, 100, 50)
capture.x, capture.y = 0, 0
rawPosition = { x = 275, y = 150 }
eventPosition = InterfaceMouse.GetPosition(capture, 0, 0)
expect(eventPosition.x, 220, "screen capture accounts for OS scaling on x")
expect(eventPosition.y, 120, "screen capture accounts for OS scaling on y")
InterfaceMouse.EndCapture(capture)

game.options.InterfaceScale.setting = 100
rawPosition = { x = 384, y = 172.8 }
local nativeLayer = { xyGlobal = { x = 280, y = 90 } }
expect(
    InterfaceMouse.CalibrateFromHook(nativeLayer, 40, 54),
    true,
    "native mouse hook calibrates the shared pointer conversion"
)
position = InterfaceMouse.GetPosition()
expectNear(position.x, 320, "OS-scaled x uses the shared calibration")
expectNear(position.y, 144, "OS-scaled y uses the shared calibration")
position = InterfaceMouse.FromRawPosition({ x = 384, y = 120 })
expectNear(position.x, 320, "saved opening x uses the same conversion")
expectNear(position.y, 100, "saved opening y uses the same conversion")
rawPosition = { x = 384, y = 240 }
expect(
    InterfaceMouse.CalibrateFromHook(nativeLayer, 40, 54),
    false,
    "inconsistent hook coordinates do not overwrite calibration"
)
position = InterfaceMouse.FromRawPosition({ x = 384, y = 120 })
expectNear(position.x, 320, "rejected calibration preserves previous x conversion")
expectNear(position.y, 100, "rejected calibration preserves previous y conversion")

game.options.InterfaceScale.setting = 150
rawPosition = { x = 525, y = 225 }
position = InterfaceMouse.GetPosition()
expect(position.x, 350, "changing interface scale invalidates the previous calibration")
expect(position.y, 150, "uncalibrated pointer uses the current interface scale")
nativeLayer.xyGlobal.x, nativeLayer.xyGlobal.y = 300, 100
rawPosition = { x = 630, y = 270 }
expect(
    InterfaceMouse.CalibrateFromHook(nativeLayer, 50, 50),
    true,
    "native hook recalibrates after an interface-scale change"
)
position = InterfaceMouse.FromRawPosition({ x = 576, y = 180 })
expectNear(position.x, 320, "new combined scale converts opening x")
expectNear(position.y, 100, "new combined scale converts opening y")

print("mouse_test: ok")
