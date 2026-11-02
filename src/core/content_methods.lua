local Components = require("src/core/components")
local Layout = require("src/core/layout")

local ContentMethods = {}

-- Component hosts all expose the same Add... API, but differ in how many concrete
-- components they create. Windows, simple views, and tab pages create one; panels
-- create a dock/popout pair. This registry keeps component construction and flow
-- defaults in one place so adding a component does not require copying a method
-- into every host.
--
-- Modules are required lazily when an Add... method is called. This is important
-- for nested hosts such as Tabs and Panel, which also install these methods.
--
-- Registry fields:
--   export         named component exported by a shared module
--   optionsIndex   position of the options argument (and number of constructor args)
--   measured       obtain default dimensions from the component's getSize function
--   measureArgs    number of non-option arguments accepted by getSize, when it
--                  differs from the constructor (ItemGrid is the current example)
--   fitInline     use measured width instead of filling the row when inline
--   flowOptions    normalize options with the component's flowOptions function
--   bindFlow       bind a component whose height can alter its owner's flow layout
--   proxyCallbacks replace the concrete panel child passed to callbacks with its proxy
--   refreshRowBackgrounds  refresh painted rows after adding a control
local COMPONENTS = {
    { method = "AddText", textTitle = false },
    { method = "AddTitle", textTitle = true },
    { method = "AddSprite", module = "src/sprite", optionsIndex = 2, measured = true, measureArgs = 0 },
    { method = "AddSpinner", module = "src/spinner", optionsIndex = 1, width = 72, height = 72 },
    { method = "AddBigSpinner", module = "src/big_spinner", optionsIndex = 1, width = 72, height = 72 },
    { method = "AddTimeGraph", module = "src/time_graph", optionsIndex = 1, measured = true, fillWidth = true },
    { method = "AddBarChart", module = "src/bar_chart", optionsIndex = 1, measured = true, fillWidth = true },
    { method = "AddHistogram", module = "src/histogram", optionsIndex = 1, measured = true, fillWidth = true },
    {
        method = "AddDivider",
        module = "src/divider",
        optionsIndex = 1,
        width = 0,
        height = 60,
        fillWidth = true,
        flowOptions = true,
    },
    { method = "AddItemSlot", module = "src/item_slot", optionsIndex = 2, width = 40, height = 40 },
    {
        method = "AddItemGrid",
        module = "src/item_grid",
        optionsIndex = 2,
        measured = true,
        measureArgs = 0,
    },
    {
        method = "AddTabs",
        module = "src/tabs",
        optionsIndex = 2,
        measured = true,
        fillWidth = true,
        flowOptions = true,
        bindFlow = true,
    },
    {
        method = "AddCollapseButton",
        module = "src/collapse_button",
        optionsIndex = 2,
        measured = true,
        fillWidth = true,
        bindFlow = true,
    },
    {
        method = "AddPanel",
        module = "src/panel",
        optionsIndex = 1,
        measured = true,
        fillWidth = true,
        bindFlow = true,
        flowManaged = true,
        paired = false,
    },
    {
        method = "AddRadioButton",
        module = "src/selection_button",
        export = "RadioButton",
        optionsIndex = 2,
        measured = true,
        fillWidth = true,
        fitInline = true,
        proxyCallbacks = { "onChange" },
    },
    {
        method = "AddCheckboxButton",
        module = "src/selection_button",
        export = "CheckboxButton",
        optionsIndex = 2,
        measured = true,
        fillWidth = true,
        fitInline = true,
        proxyCallbacks = { "onChange" },
    },
    { method = "AddColourPicker", module = "src/colour_picker", optionsIndex = 1, measured = true },
    {
        method = "AddTextField",
        module = "src/text_field",
        optionsIndex = 1,
        measured = true,
        fillWidth = true,
    },
    {
        method = "AddKeybindField",
        module = "src/keybind_field",
        optionsIndex = 1,
        measured = true,
        fillWidth = true,
    },
    {
        method = "AddComboBox",
        module = "src/combo_box",
        optionsIndex = 1,
        measured = true,
        fillWidth = true,
    },
    { method = "AddList", module = "src/list", optionsIndex = 1, measured = true, fillWidth = true },
    {
        method = "AddRibbonButton",
        module = "src/ribbon_button",
        optionsIndex = 3,
        actionIndex = 2,
        width = 32,
        height = 32,
    },
    {
        method = "AddSimpleButton",
        module = "src/simple_button",
        optionsIndex = 3,
        actionIndex = 2,
        measured = true,
        measureArgs = 1,
    },
    {
        method = "AddSlider",
        module = "src/slider",
        optionsIndex = 1,
        measured = true,
        fillWidth = true,
        refreshRowBackgrounds = true,
    },
    {
        method = "AddFancyButton",
        module = "src/fancy_button",
        optionsIndex = 3,
        actionIndex = 2,
        measured = true,
        measureArgs = 1,
    },
    {
        method = "AddSpriteButton",
        module = "src/sprite_button",
        optionsIndex = 3,
        actionIndex = 2,
        width = 24,
        height = 24,
    },
}

local function copyTable(value)
    local copied = {}
    if type(value) == "table" then
        for key, entry in pairs(value) do copied[key] = entry end
    end
    return copied
end

local function callWithOptions(fn, receiver, args, optionsIndex, options)
    if optionsIndex == 1 then return fn(receiver, options) end
    if optionsIndex == 2 then return fn(receiver, args[1], options) end
    return fn(receiver, args[1], args[2], options)
end

local function measure(component, spec, args, options)
    if not spec.measured then return spec.width, spec.height end
    local measureArgs = spec.measureArgs
    if measureArgs == nil then measureArgs = spec.optionsIndex - 1 end
    if measureArgs == 0 then return component.getSize(options) end
    if measureArgs == 1 then return component.getSize(args[1], options) end
    return component.getSize(args[1], args[2], options)
end

local function place(owner, component, spec, args, options)
    local width, height = measure(component, spec, args, options)
    if spec.flowOptions then options = component.flowOptions(options) end
    return Layout.place(owner, options, {
        width = width,
        height = height,
        fillWidth = spec.fillWidth and not (spec.fitInline and options and options.inline == true),
    })
end

local function construct(component, spec, parent, args, placed)
    if spec.flowManaged then return component.new(parent, placed, true) end
    return callWithOptions(component.new, parent, args, spec.optionsIndex, placed)
end

local function loadComponent(spec)
    local component = require(spec.module)
    if spec.export then return component[spec.export] end
    return component
end

local function addSingle(owner, spec, args)
    if spec.textTitle ~= nil then
        return require("src/text").append(owner, args[1], spec.textTitle)
    end

    local component = loadComponent(spec)
    local placed = place(owner, component, spec, args, args[spec.optionsIndex])
    local result = Layout.manage(owner, construct(component, spec, owner.content, args, placed), placed)
    if spec.refreshRowBackgrounds and owner.rowBackgroundColours
        and #owner.rowBackgroundColours > 0 and owner.RefreshRowBackgrounds then
        owner:RefreshRowBackgrounds()
    end
    if spec.bindFlow then return result:BindFlow(owner) end
    return result
end

local function pairedArgs(spec, args, proxyReference)
    local copied = copyTable(args)
    if spec.actionIndex and copied[spec.actionIndex] then
        local action = copied[spec.actionIndex]
        copied[spec.actionIndex] = function(_, ...)
            action(proxyReference(), ...)
        end
    end
    return copied
end

local function pairedOptions(spec, options, proxyReference)
    local copied = copyTable(options)
    for _, callbackName in ipairs(spec.proxyCallbacks or {}) do
        if copied[callbackName] then
            local callback = copied[callbackName]
            copied[callbackName] = function(_, ...)
                callback(proxyReference(), ...)
            end
        end
    end
    return copied
end

local function addPaired(container, spec, args, getSides, pair)
    local sides = getSides(container)
    if spec.textTitle ~= nil then
        local Text = require("src/text")
        return pair(
            container,
            Text.append(sides[1].owner, args[1], spec.textTitle),
            Text.append(sides[2].owner, args[1], spec.textTitle)
        )
    end

    -- Each panel surface owns an independent component and layout entry. The
    -- returned proxy fans property and method access out to both concrete objects.
    local component = loadComponent(spec)
    local proxy
    local results = {}
    for index, side in ipairs(sides) do
        local sideArgs = pairedArgs(spec, args, function() return proxy end)
        sideArgs[spec.optionsIndex] = pairedOptions(
            spec,
            args[spec.optionsIndex],
            function() return proxy end
        )
        results[index] = Components.withBatch(side.content, function()
            local placed = place(
                side.owner,
                component,
                spec,
                sideArgs,
                sideArgs[spec.optionsIndex]
            )
            local result = Layout.manage(
                side.owner,
                construct(component, spec, side.content, sideArgs, placed),
                placed
            )
            if spec.bindFlow then result:BindFlow(side.owner) end
            return result
        end)
    end
    proxy = pair(container, results[1], results[2])
    if spec.refreshRowBackgrounds and container.rowBackgroundColours
        and #container.rowBackgroundColours > 0 and container.RefreshRowBackgrounds then
        container:RefreshRowBackgrounds()
    end
    return proxy
end

local function isIncluded(spec, options, paired)
    if paired and spec.paired == false then return false end
    return not (options and options.exclude and options.exclude[spec.method])
end

function ContentMethods.installSingle(class, options)
    -- Install at class-definition time; component modules themselves stay lazy.
    for _, component in ipairs(COMPONENTS) do
        local spec = component
        if isIncluded(spec, options, false) then
            class[spec.method] = function(self, ...)
                local args = { ... }
                return Components.withBatch(self.content, function()
                    return addSingle(self, spec, args)
                end)
            end
        end
    end
end

function ContentMethods.installPaired(class, getSides, pair, options)
    -- Panel-like hosts provide their surfaces and decide how the two results are
    -- represented. Stateful controls may overwrite an installed method afterward.
    for _, component in ipairs(COMPONENTS) do
        local spec = component
        if isIncluded(spec, options, true) then
            class[spec.method] = function(self, ...)
                return addPaired(self, spec, { ... }, getSides, pair)
            end
        end
    end
end

return ContentMethods
