local Settings = {}

local POSITION_IDS = { left = 1, right = 2, top = 3 }
local POSITION_VALUES = { "left", "right", "top" }
local GENERAL_OPTIONS = { "allowClassicMovement", "respectInterfaceLock" }
local DESCRIPTION_COLOUR = 0xB4A092FF
local ROW_BACKGROUND_COLOURS = { 0x24211EFF, 0x2E2825FF }

-- Definition keys are also the persisted keys; keep them stable across releases.
local definitions = {
    allowClassicMovement = { default = false, text = "Unlock PrettyUI in classic UI mode" },
    respectInterfaceLock = {
        default = true,
        text = "Follow native interface lock in modern UI mode",
    },
    ribbonBarPosition = {
        default = "left",
        normalize = function(value)
            local position = string.lower(tostring(value))
            if POSITION_IDS[position] then return position end
        end,
    },
    ribbonBarAutoHide = { default = false, text = "Auto-hide ribbon" },
    ribbonBarButtonCap = {
        default = 10,
        min = 1,
        max = 50,
        normalize = function(value, definition)
            local number = tonumber(value)
            if number ~= nil and number == number then
                return math.max(definition.min, math.min(definition.max, math.floor(number)))
            end
        end,
    },
}

local values, views, watchers = {}, {}, {}
for key, definition in pairs(definitions) do
    values[key] = definition.default
end

local function normalize(definition, value)
    if value == nil then return definition.default end
    if definition.normalize then return definition.normalize(value, definition) or definition.default end
    return value == true
end

local function update(key, value)
    if values[key] == value then return end
    values[key] = value
    for host, controls in pairs(views) do
        if ui.Interfaces:GetInterface(host.interfaceID) ~= nil then controls[key](value) end
    end
    for _, callback in pairs(watchers) do
        callback(key)
    end
end

function Settings.load()
    for key, definition in pairs(definitions) do
        local kind = type(definition.default)
        local value
        if kind == "boolean" then
            value = PersistentDB:GetBool(key)
        elseif kind == "string" then
            value = PersistentDB:GetString(key)
        else
            value = PersistentDB:GetInt(key)
        end
        update(key, normalize(definition, value))
    end
end

function Settings.get(key)
    return values[key]
end

function Settings.set(key, value)
    value = normalize(definitions[key], value)
    local kind = type(value)
    if kind == "boolean" then
        PersistentDB:SetBool(key, value)
    elseif kind == "string" then
        PersistentDB:SetString(key, value)
    else
        PersistentDB:SetInt(key, value)
    end
    update(key, value)
end

function Settings.watch(owner, callback)
    watchers[owner] = callback
end

function Settings.unwatch(owner)
    watchers[owner] = nil
end

local function addSection(host, title, description)
    host:AddTitle({ text = title, marginBottom = 2, rowBackgroundGroup = title })
    host:AddText({
        text = description,
        colour = DESCRIPTION_COLOUR,
        marginBottom = 8,
        rowBackgroundGroup = title,
    })
end

function Settings.build(host, showTitle)
    if showTitle then
        host:AddTitle({ text = "PrettyUI settings", font = id.Font.CINZEL_18PT_BOLD, rowBackground = false })
    end
    local general, ribbon = "General", "Ribbon"
    addSection(host, general, "These options apply to all PrettyUI windows and panels.")
    local choices = {}
    for index, key in ipairs(GENERAL_OPTIONS) do
        local definition = definitions[key]
        choices[index] = { text = definition.text, tooltip = definition.tooltip, value = key, selected = values[key] }
    end
    local movement = host:AddCheckboxButton(choices, {
        rowBackgroundGroup = general,
        maxLines = 0,
        onChange = function(_, _, key, selected) Settings.set(key, selected) end,
    })

    addSection(host, ribbon, "These preferences apply to the Modern Interface ribbon.")
    host:AddText({ text = "Ribbon alignment", rowBackgroundGroup = ribbon })
    local position = host:AddComboBox({
        rowBackgroundGroup = ribbon,
        entries = {
            { label = "Left", id = POSITION_IDS.left },
            { label = "Right", id = POSITION_IDS.right },
            { label = "Top", id = POSITION_IDS.top },
        },
        selectedID = POSITION_IDS[values.ribbonBarPosition],
        onChange = function(_, entryID) Settings.set("ribbonBarPosition", POSITION_VALUES[entryID]) end,
    })
    local autoHide = host:AddCheckboxButton({
        { text = definitions.ribbonBarAutoHide.text, value = "autoHide", selected = values.ribbonBarAutoHide },
    }, {
        rowBackgroundGroup = ribbon,
        maxLines = 0,
        onChange = function(_, _, _, selected) Settings.set("ribbonBarAutoHide", selected) end,
    })
    local capLabel = host:AddText({
        text = "Visible panel buttons: " .. values.ribbonBarButtonCap,
        rowBackgroundGroup = ribbon,
    })
    local cap = host:AddSlider({
        rowBackgroundGroup = ribbon,
        min = definitions.ribbonBarButtonCap.min,
        max = definitions.ribbonBarButtonCap.max,
        step = 1,
        value = values.ribbonBarButtonCap,
        onChange = function(_, value) Settings.set("ribbonBarButtonCap", value) end,
    })

    views[host] = {
        ribbonBarPosition = function(value) position:Select(POSITION_IDS[value], false) end,
        ribbonBarAutoHide = function(value) autoHide:SetSelected("autoHide", value, false) end,
        ribbonBarButtonCap = function(value)
            cap:SetValue(value, false)
            capLabel.content = "Visible panel buttons: " .. value
        end,
    }
    for _, key in ipairs(GENERAL_OPTIONS) do
        views[host][key] = function(value) movement:SetSelected(key, value, false) end
    end
    host.rowBackgroundColours = ROW_BACKGROUND_COLOURS
    host:RefreshRowBackgrounds()
end

function Settings.destroy(host)
    if host then
        views[host] = nil
        host:Destroy()
    end
end

return Settings
