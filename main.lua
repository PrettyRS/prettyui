local TextField = require("src/text_field")
local KeybindField = require("src/keybind_field")
local RibbonBar = require("src/ribbon_bar")
local BuffBar = require("src/buff_bar")
local TimeGraph = require("src/time_graph")
local BarChart = require("src/bar_chart")
local Histogram = require("src/histogram")
local Dialog = require("src/dialog")
local Confirm = require("src/confirm")
local SelectionButtons = require("src/selection_button")
local PrettyMiniMenu = require("src/minimenu")
local OverheadBar = require("src/overhead_bar")
local CategoryGroups = require("src/core/category_groups")
local Components = require("src/core/components")

local resources = Plugin.resources
TextField.SetDefaultSprite(resources and (resources.input_default or resources["input_default.png"]))

local PrettyUI = {
    AchievementPopup = require("src/achievement_popup"),
    AnchoredTooltip = require("src/anchored_tooltip"),
    BarChart = BarChart,
    BuildCategoryGroup = CategoryGroups.build,
    NewComponent = Components.new,
    RefreshComponentIDs = Components.refresh,
    WithCategoryBatch = CategoryGroups.withBatch,
    BigSpinner = require("src/big_spinner"),
    CheckboxButton = SelectionButtons.CheckboxButton,
    ColourPicker = require("src/colour_picker"),
    ComboBox = require("src/combo_box"),
    CollapseButton = require("src/collapse_button"),
    Confirm = Confirm,
    Dialog = Dialog,
    Divider = require("src/divider"),
    FancyButton = require("src/fancy_button"),
    Histogram = Histogram,
    TimeGraph = TimeGraph,
    ItemSlot = require("src/item_slot"),
    ItemGrid = require("src/item_grid"),
    KeybindField = KeybindField,
    List = require("src/list"),
    MiniMenu = PrettyMiniMenu,
    Panel = require("src/panel"),
    OverheadBar = OverheadBar,
    Sprites = require("src/core/sprites"),
    RibbonButton = require("src/ribbon_button"),
    RibbonBar = RibbonBar,
    RadioButton = SelectionButtons.RadioButton,
    SimpleButton = require("src/simple_button"),
    Slider = require("src/slider"),
    Sprite = require("src/sprite"),
    SpriteButton = require("src/sprite_button"),
    Spinner = require("src/spinner"),
    Tabs = require("src/tabs"),
    Text = require("src/text"),
    TextField = TextField,
    Tooltip = require("src/tooltip"),
    Window = require("src/window"),
    Scrollbar = require("src/scrollbar"),
    SimpleView = require("src/simple_view"),
    BuffBar = BuffBar,
}

PrettyUI.version = "1.3.0-beta"

RibbonBar.Start()
PrettyMiniMenu.Start()

function PluginShutdown()
    KeybindField.Shutdown()
    PrettyMiniMenu.Shutdown()
    Dialog.Shutdown()
    RibbonBar.Shutdown()
    BuffBar.Shutdown()
    TimeGraph.Shutdown()
    BarChart.Shutdown()
    Histogram.Shutdown()
    OverheadBar.Shutdown()
end

return PrettyUI
