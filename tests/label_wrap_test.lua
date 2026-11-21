local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local created = {}

-- Resolve native size anchors on access, so a component follows its ancestors' size changes.
local function component(parent, categoryID, dynamicID)
    local value = {
        parent = parent,
        x = 0,
        y = 0,
        hidden = false,
        subscriptions = {},
        opConfig = { ClearOpCursors = function() end, SetOpCursor = function() end },
        cursorConfig = {},
    }
    setmetatable(value, {
        __index = function(self, key)
            if key == "width" then return (self.w or 0) + (parent and parent.width or 0) * (self.wa or 0) end
            if key == "height" then return (self.h or 0) + (parent and parent.height or 0) * (self.ha or 0) end
        end,
    })
    function value:SetPos(x, y)
        self.x, self.y = x, y
    end
    function value:SetSize(w, h, wa, ha)
        self.w, self.h, self.wa, self.ha = w, h, wa, ha
    end
    function value:SetY(y)
        self.y = y
    end
    function value:SetWidth(w, wa)
        self.w, self.wa = w, wa
    end
    function value:SetHeight(h, ha)
        self.h, self.ha = h, ha
    end
    function value:SetScrollSize(w, h)
        self.scrollWidth, self.scrollHeight = w, h
    end
    function value:SetScrollPos(x, y)
        self.scrollX, self.scrollY = x, y
    end
    function value:Subscribe(hook, name, callback) self.subscriptions[hook] = callback or name end
    function value:Unsubscribe(hook) self.subscriptions[hook] = nil end
    value.MoveToFront = function() end
    value.MoveToBack = function() end
    function value:Destroy() self.destroyed = true end
    Interfaces.component(value, parent, categoryID, dynamicID)
    created[#created + 1] = value
    return value
end

-- The client sends ONRESIZE to every component whose size follows a resized ancestor.
local function resizeParent(parent, width, ...)
    parent:SetSize(width, parent.height)
    -- A scroll host sizes its content itself, as a window does when it is resized.
    for _, view in ipairs({ ... }) do
        view:Refresh()
    end
    for _, value in ipairs(created) do
        local onResize = value.subscriptions.ONRESIZE
        if onResize and not value.destroyed then onResize() end
    end
end

local CHARACTER_WIDTH = 7
local font = {
    baseline = 18,
    GetStringLineCount = function(_, text, width)
        return math.max(1, math.ceil(#text * CHARACTER_WIDTH / width))
    end,
    GetStringWidth = function(_, text) return #text * CHARACTER_WIDTH end,
}
local enum = setmetatable({}, { __index = function(_, key) return key end })
ui = {
    Layer = { new = component },
    Sprite = { new = component },
    Text = { new = component },
    Rectangle = { new = component },
    Hook = enum,
    AlignMode = enum,
}
id = { Sprite = enum, Font = enum }
config = { Cursor = enum, Font = { MUSEO_SANS_15PT_REGULAR = font, CINZEL_13PT_BOLD = font } }
Keyboard = { IsAvailable = function() return false end }
Event = { Logic = { Subscribe = function() end, Unsubscribe = function() end } }

local SimpleView = require("src/simple_view")

local LONG = "Chat heads always look towards the centre of the screen"
local ROW_HEIGHT = 22
local LABEL_X = 22
-- Sections space controls like pages: 2 below text, the layout's row gap below anything else.
local TEXT_GAP = 2
local CONTROL_GAP = 8

local function linesAt(width) return math.ceil(#LONG * CHARACTER_WIDTH / width) end

local parent = component()
parent:SetSize(1400, 800)
local view = SimpleView.new(parent, { width = -600, widthAnchor = 1, height = 600 })

local checkboxes = view:AddCheckboxButton({ "Short", LONG }, { maxLines = 0 })
local radios = view:AddRadioButton({ LONG, "Short" }, { maxLines = 0 })
local capped = view:AddCheckboxButton({ LONG }, { maxLines = 2 })
local unchanged = view:AddCheckboxButton({ LONG }, {})
local inline = view:AddCheckboxButton({ LONG }, { inline = true, maxLines = 0 })
local section = view:AddCollapseButton("Details", { expanded = true })
local sectionText = section:AddText(LONG)
local sectionButton = section:AddSimpleButton("Apply", function() end)
-- Controls placed with an explicit y: one beside wrapping text, and one taller than the text beside it.
local besideSection = view:AddCollapseButton("Beside", { expanded = true })
local besideText = besideSection:AddText(LONG)
local besideButton = besideSection:AddSimpleButton("Beside", function() end, { x = 120, y = 0 })
local tallSection = view:AddCollapseButton("Tall", { expanded = true })
local tallButton = tallSection:AddFancyButton("Tall", function() end)
local tallText = tallSection:AddText({ text = LONG, x = 150, y = 0 })
local belowTall = tallSection:AddSimpleButton("Below", function() end)
-- Two wrapping texts side by side, with a button below both.
local pairSection = view:AddCollapseButton("Pair", { expanded = true })
local leftText = pairSection:AddText(LONG)
local rightText = pairSection:AddText({ text = LONG, x = 150, y = 0 })
local belowPair = pairSection:AddSimpleButton("Below", function() end)
-- Checkbox lists inside a section: one that wraps, one without maxLines, and a button below them.
local listSection = view:AddCollapseButton("Lists", { expanded = true })
local sectionChecks = listSection:AddCheckboxButton({ LONG }, { maxLines = 0 })
local sectionDefault = listSection:AddRadioButton({ LONG }, {})
local listSectionButton = listSection:AddSimpleButton("Below the lists", function() end)
-- Page text whose content changes after it is added.
local changingText = view:AddText("Short")
local after = view:AddText({ text = "After", height = 24 })

-- A closed section that refits its view, in a view the player has made taller by hand.
local fitView = SimpleView.new(parent, { width = -600, widthAnchor = 1, height = 200 })
local fitSection = fitView:AddCollapseButton("Fits its view", { resizeParent = true })
local fitText = fitSection:AddText(LONG)
local PLAYER_HEIGHT = 300
fitView.root:SetHeight(PLAYER_HEIGHT)

local function checkWide()
    expect(linesAt(checkboxes.root.width - LABEL_X), 1, "the wide page fits the long label on one line")
    expect(checkboxes.root.height, 2 * ROW_HEIGHT, "one-line checkbox labels keep 22-high rows")
    expect(checkboxes.items[2].row.y, ROW_HEIGHT, "the second checkbox row follows the first")
    expect(radios.root.height, 2 * ROW_HEIGHT, "one-line radio labels keep 22-high rows")
    expect(radios.root.y, checkboxes.root.y + checkboxes.root.height + 8, "radios follow the checkboxes")
    expect(sectionText.height, 24, "section text keeps one line")
    expect(sectionButton.root.y, 24 + TEXT_GAP, "the section button follows its text")
    expect(sectionChecks.root.height, ROW_HEIGHT, "a section list that fits keeps one row")
    expect(sectionDefault.root.y, ROW_HEIGHT + CONTROL_GAP, "the next section list follows the first")
    expect(listSectionButton.root.y, 2 * (ROW_HEIGHT + CONTROL_GAP), "the section button follows the lists")
end

checkWide()
local wideAfterY = after.y

resizeParent(parent, 800, view, fitView)

local labelWidth = checkboxes.root.width - LABEL_X
local lines = linesAt(labelWidth)
expect(lines > 1, true, "the narrow page wraps the long label")
local wrappedRow = ROW_HEIGHT + (lines - 1) * 18
expect(checkboxes.items[1].row.height, ROW_HEIGHT, "a label that fits keeps its row height")
expect(checkboxes.items[2].row.height, wrappedRow, "the wrapped checkbox row grows by a line spacing per line")
expect(checkboxes.items[2].label.height, wrappedRow, "the label follows its row's height")
expect(checkboxes.root.height, ROW_HEIGHT + wrappedRow, "the checkbox list reports its wrapped height")
expect(radios.root.y, checkboxes.root.y + checkboxes.root.height + 8, "the page re-flows below the checkboxes")
expect(radios.items[1].row.height, wrappedRow, "radio labels wrap too")
expect(radios.items[2].row.y, wrappedRow, "the radio row below a wrapped one moves down")
expect(lines > 2, true, "the narrow page needs more than two lines")
expect(capped.root.height, ROW_HEIGHT + 18, "maxLines caps how far a row grows")
expect(capped.items[1].label.maxLines, 2, "the label draws at most maxLines lines")
expect(unchanged.items[1].label.maxLines, 1, "without maxLines choices stay on one line, as before")
expect(unchanged.root.height, ROW_HEIGHT, "without maxLines the row keeps its height")
expect(unchanged.items[1].label.subscriptions.ONRESIZE, nil, "without maxLines the list does not watch resizes")
expect(inline.items[1].label.maxLines, 1, "inline choices stay on one line")
expect(inline.root.height, ROW_HEIGHT, "inline choices keep one row")
expect(inline.items[1].label.subscriptions.ONRESIZE, nil, "inline choices do not watch resizes")

local textLines = linesAt(sectionText.width)
expect(textLines > 1, true, "the narrow section wraps its text")
expect(sectionText.height, (textLines - 1) * 18 + 18 + 6, "section text measures like page text")
expect(besideButton.root.y, 0, "a control beside wrapping text stays where it was placed")
expect(besideSection.contentHeight, besideText.height, "the section fits the wrapped text beside the control")
expect(
    belowTall.root.y,
    math.max(tallButton.root.height + CONTROL_GAP, tallText.height + TEXT_GAP),
    "the control below text beside a taller one moves only as far as the row grew"
)
expect(
    belowPair.root.y,
    math.max(leftText.height, rightText.height) + TEXT_GAP,
    "two wrapping texts side by side move the control below once, not twice"
)
expect(sectionButton.root.y, sectionText.height + TEXT_GAP, "the section button moves below the wrapped text")
local sectionLines = linesAt(sectionChecks.items[1].label.width)
expect(sectionLines > 1, true, "the narrow section wraps its list's label")
local sectionRow = ROW_HEIGHT + (sectionLines - 1) * 18
expect(sectionChecks.root.height, sectionRow, "a section list grows with its wrapped label")
expect(sectionDefault.root.y, sectionRow + CONTROL_GAP, "the next section list moves below the wrapped one")
expect(sectionDefault.root.height, ROW_HEIGHT, "a section list without maxLines keeps one line")
expect(listSectionButton.root.y, sectionRow + ROW_HEIGHT + 2 * CONTROL_GAP, "the section button moves below the lists")
expect(after.y > wideAfterY, true, "rows below the wrapped lists and section move down")
expect(fitText.height > 24, true, "text in a closed section still wraps")
expect(fitView.root.height, PLAYER_HEIGHT, "a closed section does not refit its view when its text wraps")
fitSection:SetExpanded(true)
expect(fitView.root.height, fitView.contentHeight, "opening the section fits the view to the wrapped text")

resizeParent(parent, 1400, view, fitView)
checkWide()
expect(
    tallSection.contentHeight >= tallButton.root.y + tallButton.root.height,
    true,
    "a section never shrinks below its tallest control"
)
expect(after.y, wideAfterY, "widening restores the page layout")

-- RefreshLayout fits text to content changed in place, on the page and, through the section, inside it.
resizeParent(parent, 800, view, fitView)
local shortAfterY = after.y
changingText.content = LONG
expect(changingText.height, 24, "changing content alone sends no resize")
view:RefreshLayout()
local changedLines = linesAt(changingText.width)
expect(changedLines > 1, true, "the new page text needs more than one line")
local changedHeight = (changedLines - 1) * 18 + 18 + 6
expect(changingText.height, changedHeight, "RefreshLayout fits page text to its longer content")
expect(after.y, shortAfterY + changedHeight - 24, "the page moves down for the longer text")
changingText.content = "Short"
view:RefreshLayout()
expect(changingText.height, 24, "RefreshLayout fits page text to its shorter content")
expect(after.y, shortAfterY, "the page moves back up for the shorter text")
local wrappedSectionHeight = sectionText.height
sectionText.content = "Short"
view:RefreshLayout()
expect(sectionText.height, 24, "RefreshLayout reaches text inside a collapse section")
expect(after.y, shortAfterY - (wrappedSectionHeight - 24), "the page moves up as the section shrinks")
expect(sectionButton.root.y, 24 + TEXT_GAP, "the section button moves up with the shorter text")

print("label_wrap_test: ok")
