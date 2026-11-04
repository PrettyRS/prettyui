local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function component(parent, categoryID, dynamicID)
    local value = {}
    function value:SetPos(x, y) self.x, self.y = x, y end
    function value:SetSize(width, height) self.width, self.height = width, height end
    function value:Destroy() self.destroyed = true end
    return Interfaces.component(value, parent, categoryID, dynamicID)
end

ui = { Sprite = { new = component }, Layer = { new = component } }
id = { Sprite = setmetatable({}, { __index = function(_, name) return name end }) }
local subscribers = {}
Event = { Logic = {
    Subscribe = function(name, callback) subscribers[name] = callback end,
    Unsubscribe = function(name) subscribers[name] = nil end,
} }
package.loaded["src/tooltip"] = { bind = function() end, unbind = function() end }
package.loaded["src/core/wheel"] = { bind = function() end }

local function advance(updates)
    for _ = 1, updates do
        for _, callback in pairs(subscribers) do callback() end
    end
end

local Spinner = require("src/spinner")
local BigSpinner = require("src/big_spinner")
expect(BigSpinner, Spinner, "BigSpinner module aliases Spinner")
local parent = component()

local spinner = Spinner.new(parent, { rotation = 350, degreesPerLogicUpdate = 15, autoPlay = false })
expect(spinner.root.width, 72, "spinner defaults to the large surface")
expect(spinner.root.height, 72, "spinner defaults to the large surface height")
expect(spinner.backdrop.spriteID, id.Sprite.RS3_LOADING_SPINNER_PARENT_BACKING, "spinner uses the large backdrop")
expect(spinner.rotating.spriteID, id.Sprite.RS3_LOADING_SPINNER_CHILD, "spinner uses the rotating foreground")
advance(1)
expect(spinner.rotating.rotationDegrees, 350, "paused spinner holds its rotation")
spinner:Start()
advance(1)
expect(spinner.rotating.rotationDegrees, 5, "rotation advances per logic update and wraps")
spinner:SetDegreesPerLogicUpdate(-10)
advance(1)
expect(spinner.rotating.rotationDegrees, 355, "rotation speed can reverse direction")
spinner:Stop()
advance(1)
expect(spinner.rotating.rotationDegrees, 355, "stopped spinner holds its rotation")
spinner:Reset()
expect(spinner.rotating.rotationDegrees, 0, "reset restores the initial angle")

local spinnerRoot = spinner.root
spinner:Destroy()
expect(spinnerRoot.destroyed, true, "destroy removes the spinner surface")
expect(next(subscribers), nil, "destroy removes animation subscriptions")
local Host = {}
require("src/core/content_methods").installSingle(Host)
local hostContent = component()
hostContent.width = 200
local host = setmetatable({
    content = hostContent,
    contentHeight = 0,
    contentWidth = 200,
}, { __index = Host })
function host:SetContentHeight(height) self.contentHeight = height end

local canonical = host:AddSpinner({ autoPlay = false })
local alias = host:AddBigSpinner({ autoPlay = false })
expect(getmetatable(canonical), Spinner, "AddSpinner constructs Spinner")
expect(getmetatable(alias), Spinner, "AddBigSpinner aliases AddSpinner")
expect(canonical.root.width, 72, "AddSpinner reserves the large spinner width")
expect(alias.root.height, 72, "AddBigSpinner reserves the large spinner height")
canonical:SetRotation(3)
canonical:Start()
alias:Start()
advance(1)
expect(canonical.rotating.rotationDegrees, 357, "default rotation decreases and wraps below zero")
expect(alias.rotating.rotationDegrees, 354, "BigSpinner uses the same default direction")
advance(1)
expect(canonical.rotating.rotationDegrees, 351, "default rotation continues in the corrected direction")
canonical:Stop()
alias:Stop()
canonical:Destroy()
alias:Destroy()

print("spinner_test: rotation, speed, playback and lifecycle passed")
