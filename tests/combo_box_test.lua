local Interfaces = require("tests/interface_fixture")

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
    end
end

local function comboField(parent, categoryID, dynamicID)
    local result = {
        entries = {},
        entryLabels = {},
        entryText = {},
        hasSelection = false,
        selectedID = -1,
        selectedLabel = "",
    }
    function result:SetPos() end
    function result:SetSize() end
    function result:Subscribe() end
    function result:Clear()
        self.entries = {}
        self.entryLabels = {}
        self.hasSelection = false
        self.selectedID = -1
        self.selectedLabel = ""
    end
    function result:SetEntries(entriesMap, selectedID)
        self:Clear()
        self.bulkSetEntriesCalls = (self.bulkSetEntriesCalls or 0) + 1
        local labels = {}
        for label, entryID in pairs(entriesMap) do
            self.entries[#self.entries + 1] = { id = entryID, text = label }
            self.entryLabels[entryID] = label
            labels[#labels + 1] = label
        end
        table.sort(labels)
        table.sort(self.entries, function(left, right) return left.text < right.text end)
        local selectedLabel = labels[selectedID]
        if selectedLabel == nil then return false end
        -- Mirrors the target client: selectedID is treated as the sorted
        -- label's one-based position rather than the map's explicit ID.
        local selectedEntryID
        for entryID, label in pairs(self.entryLabels) do
            if label == selectedLabel then
                selectedEntryID = entryID
                break
            end
        end
        self.hasSelection = true
        self.selectedID = selectedEntryID
        self.selectedLabel = self.entryLabels[selectedEntryID]
        return true
    end
    function result:Add(label, entryID)
        self.entries[#self.entries + 1] = { id = entryID, text = label }
        self.entryLabels[entryID] = label
        table.sort(self.entries, function(left, right) return left.text < right.text end)
        -- Mirrors the native combo's implicit first-entry selection.
        if not self.hasSelection then
            self.hasSelection = true
            self.selectedID = entryID
            self.selectedLabel = label
        end
        return true
    end
    function result:UnselectAll(triggerEvents)
        if type(triggerEvents) ~= "boolean" then
            error("UnselectAll requires a triggerEvents boolean")
        end
        self.hasSelection = false
        self.selectedID = -1
        self.selectedLabel = ""
    end
    function result:Select(entryID, triggerEvents)
        local selectedEntry
        for _, entry in ipairs(self.entries) do
            if entry.id == entryID then selectedEntry = entry break end
        end
        if selectedEntry == nil then return false end
        self.hasSelection = true
        self.selectedID = entryID
        self.selectedLabel = selectedEntry.text
        self.lastSelectTriggerEvents = triggerEvents
        return true
    end
    function result:Destroy() end
    return Interfaces.component(result, parent, categoryID, dynamicID)
end

ui = {
    ComboField = { new = comboField },
    Margin = { new = function() return {} end },
    Hook = { ONSELECTIONCHANGED = 1 },
}
id = {
    StyleSheet = { COMBO_DEFAULT = 1 },
    Font = { MUSEO_SANS_15PT_REGULAR = 1 },
}

package.loaded["src/core/control_palette"] = {
    TEXT = 1,
    DISABLED_TEXT = 2,
    HOVER = 3,
    SELECTED = 4,
    CARET = 5,
}
package.loaded["src/core/wheel"] = { bind = function() end }
package.loaded["src/tooltip"] = {
    bind = function() end,
    set = function() return true end,
    unbind = function() end,
}
package.loaded["src/ordered_combo_box"] = {
    new = function(_, options)
        return { ordered = true, options = options }
    end,
}
package.loaded["src/combo_box"] = nil

local ComboBox = require("src/combo_box")

local combo = ComboBox.new(Interfaces.component({}), {
    entries = {
        { label = "Small", id = 1 },
        { label = "Medium", id = 2 },
        { label = "Large", id = 3 },
    },
    selectedID = 3,
})

expect(combo:GetSelectedID(), 3, "constructor replaces implicit first selection")
expect(combo:GetSelectedLabel(), "Large", "constructor restores selected label")
expect(combo:Select(2, false), true, "programmatic selection changes entry")
expect(combo:GetSelectedID(), 2, "programmatic selection updates selected ID")
expect(combo:GetSelectedLabel(), "Medium", "programmatic selection updates label")
expect(combo.root.lastSelectTriggerEvents, false, "silent selection does not emit native events")
expect(combo.root.bulkSetEntriesCalls, 2, "large selection uses sorted-position fallback")

local smallCombo = ComboBox.new(Interfaces.component({}), {
    entries = {
        { label = "Small", id = 1 },
        { label = "Medium", id = 2 },
        { label = "Large", id = 3 },
    },
    selectedID = 1,
})
expect(smallCombo:GetSelectedID(), 1, "sorted-position fallback restores small ID")
expect(smallCombo:GetSelectedLabel(), "Small", "sorted-position fallback restores small header")
expect(smallCombo.root.bulkSetEntriesCalls, 2, "small selection uses sorted-position fallback")

local orderedCombo = ComboBox.new(Interfaces.component({}), {
    entries = {
        { label = "Zulu", id = 10 },
        { label = "Beta", id = 20, order = 2 },
        { label = "Alpha", id = 30, order = 2 },
        { label = "First", id = 40, order = 1 },
    },
    selectedID = 20,
})
expect(orderedCombo.ordered, true, "ordered entries use the custom combobox")
expect(orderedCombo.options.selectedID, 20, "custom combobox receives constructor options")

local validOrder, orderError = pcall(function()
    ComboBox.new(Interfaces.component({}), { entries = { { label = "Invalid", order = 1.5 } } })
end)
expect(validOrder, false, "fractional entry order is rejected")
expect(orderError:find("must be an integer", 1, true) ~= nil, true,
    "invalid entry order explains the requirement")

print("combo_box_test: ok")
