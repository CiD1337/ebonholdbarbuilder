--[[----------------------------------------------------------------------------
    Behavior and event handling for the Explorer configuration panel.
    Manages spec dropdown, level list, slot grid display.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.Explorer = {}

local Explorer = EBB.Explorer
local UI = EBB.UI
local ActionBar = EBB.ActionBar
local Utils = EBB.Utils
local Settings = EBB.Settings
local Profile = EBB.Profile
local Layout = EBB.Layout
local Core = EBB.Core
local Restore = EBB.Restore
local ClassBars = EBB.ClassBars

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local viewedSpecIndex = nil  
local selectedLevel = nil
local currentMapping = nil  

--------------------------------------------------------------------------------
-- Display Mapping
--------------------------------------------------------------------------------

function Explorer:BuildMapping()
    local isActiveSpec = self:IsViewingActiveSpec()
    local stanceIndex = isActiveSpec and ActionBar:GetStanceIndex() or 0

    currentMapping = ClassBars:GetDisplayMapping(stanceIndex, isActiveSpec)
end

function Explorer:GetCurrentMapping()
    if not currentMapping then
        self:BuildMapping()
    end
    return currentMapping
end

--------------------------------------------------------------------------------
-- Show / Hide / Toggle
--------------------------------------------------------------------------------

function Explorer:Show()
    local frame = UI:CreateExplorerFrame()
    self:Initialize()
    
    viewedSpecIndex = Profile:GetActive()
    selectedLevel = nil
    
    self:Refresh()
    frame:Show()
end

function Explorer:Hide()
    if UI.ExplorerFrame then
        UI.ExplorerFrame:Hide()
    end
end

function Explorer:Toggle()
    if UI.ExplorerFrame and UI.ExplorerFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function Explorer:IsVisible()
    return UI.ExplorerFrame and UI.ExplorerFrame:IsShown()
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

local isInitialized = false

function Explorer:Initialize()
    if isInitialized then return end
    isInitialized = true
    
    local frame = UI.ExplorerFrame
    
    UIDropDownMenu_Initialize(frame.SpecDropdown, function(self, level)
        Explorer:InitializeSpecDropdown(self, level)
    end)
    
    for barIndex = 1, Settings.TOTAL_BARS do
        local toggle = frame.BarToggles[barIndex]
        toggle:SetScript("OnClick", function(self)
            Explorer:OnBarToggleClick(self.barIndex)
        end)
    end
    
    if frame.SwitchSpecButton then
        frame.SwitchSpecButton:SetScript("OnClick", function()
            Explorer:OnSwitchSpecClick()
        end)
    end

    if frame.PropagateToggle then
        frame.PropagateToggle:SetScript("OnClick", function(self)
            Explorer:OnPropagateToggleClick(self)
        end)
    end

    if frame.RestoreButton then
        frame.RestoreButton:SetScript("OnClick", function()
            Restore:Perform()
        end)
    end
    
    for slot = 1, Settings.TOTAL_SLOTS do
        local button = frame.SlotButtons[slot]
        button:SetScript("OnEnter", function(self)
            Explorer:OnSlotEnter(self)
        end)
        button:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)
    end
    
    Core:RegisterSpecChangeCallback(function(newSpecIndex)
        Explorer:OnActiveSpecChanged(newSpecIndex)
    end)
end

--------------------------------------------------------------------------------
-- Spec Dropdown
--------------------------------------------------------------------------------

function Explorer:InitializeSpecDropdown(dropdown, level)
    local activeSpec = Profile:GetActive()
    
    for specIndex = 1, 5 do
        local info = UIDropDownMenu_CreateInfo()
        local specName = Profile:GetSpecName(specIndex)
        
        if specIndex == activeSpec then
            info.text = specName .. " |cFF00FF00(active)|r"
        else
            info.text = specName
        end
        
        info.value = specIndex
        info.checked = (specIndex == viewedSpecIndex)
        info.func = function()
            Explorer:OnSpecSelected(specIndex)
        end
        UIDropDownMenu_AddButton(info, level)
    end
end

function Explorer:RefreshSpecDropdown()
    local frame = UI.ExplorerFrame
    if not frame then return end
    
    local specName = Profile:GetSpecName(viewedSpecIndex)
    local activeSpec = Profile:GetActive()
    
    if viewedSpecIndex == activeSpec then
        UIDropDownMenu_SetText(frame.SpecDropdown, specName .. " |cFF00FF00(active)|r")
    else
        UIDropDownMenu_SetText(frame.SpecDropdown, specName)
    end
end

function Explorer:OnSpecSelected(specIndex)
    if specIndex == viewedSpecIndex then
        return
    end
    
    viewedSpecIndex = specIndex
    selectedLevel = nil
    self:Refresh()
end

function Explorer:OnActiveSpecChanged(newSpecIndex)
    viewedSpecIndex = newSpecIndex
    selectedLevel = nil
    
    if self:IsVisible() then
        self:Refresh()
    end
end

--------------------------------------------------------------------------------
-- Viewed Spec Helpers
--------------------------------------------------------------------------------

function Explorer:GetViewedSpec()
    return viewedSpecIndex or Profile:GetActive()
end

function Explorer:IsViewingActiveSpec()
    return self:GetViewedSpec() == Profile:GetActive()
end

--------------------------------------------------------------------------------
-- Switch Spec Button
--------------------------------------------------------------------------------

function Explorer:RefreshSwitchButton()
    local frame = UI.ExplorerFrame
    if not frame or not frame.SwitchSpecButton then return end
    
    local button = frame.SwitchSpecButton
    
    local isPending = Core.IsSpecSwitchPending and Core:IsSpecSwitchPending()
    
    if isPending then
        button:SetText("Switching...")
        button:Disable()
    elseif self:IsViewingActiveSpec() then
        button:SetText("Active Spec")
        button:Disable()
    else
        button:SetText("Switch Spec")
        button:Enable()
    end
end

function Explorer:OnSwitchSpecClick()
    local targetSpec = self:GetViewedSpec()
    if targetSpec == Profile:GetActive() then return end

    if Core.SwitchSpec then
        local success = Core:SwitchSpec(targetSpec)
        if success then
            self:RefreshSwitchButton()
        end
    end
end

--------------------------------------------------------------------------------
-- Propagate Changes Toggle
--------------------------------------------------------------------------------

function Explorer:RefreshPropagateToggle()
    local frame = UI.ExplorerFrame
    if not frame or not frame.PropagateToggle then return end

    local specIndex = self:GetViewedSpec()
    local enabled = Profile:GetPropagateChanges(specIndex)
    frame.PropagateToggle:SetChecked(enabled)
end

function Explorer:OnPropagateToggleClick(toggle)
    local specIndex = self:GetViewedSpec()
    local newValue = toggle:GetChecked() and true or false
    Profile:SetPropagateChanges(newValue, specIndex)
end

--------------------------------------------------------------------------------
-- Level List
--------------------------------------------------------------------------------

function Explorer:RefreshLevelList()
    local frame = UI.ExplorerFrame
    if not frame then return end

    local specIndex = self:GetViewedSpec()
    local currentLevel = Utils:GetPlayerLevel()
    local highestLevel = EBB_CharDB.highestSeenLevel or currentLevel

    for _, button in pairs(frame.LevelButtons) do
        button:Hide()
    end

    -- Build a fixed entry list: current level first, master second (if different)
    local entries = {}
    if currentLevel == highestLevel then
        entries[1] = { level = currentLevel, label = "Master", isCurrent = true }
    else
        entries[1] = { level = currentLevel, label = "Level " .. currentLevel, isCurrent = true }
        if Layout:Has(highestLevel, specIndex) then
            entries[2] = { level = highestLevel, label = "Master", isCurrent = false }
        end
    end

    -- Auto-select: default to current level
    local found = false
    for _, entry in ipairs(entries) do
        if entry.level == selectedLevel then found = true; break end
    end
    if not found then
        selectedLevel = currentLevel
    end

    local yOffset = 0
    for i, entry in ipairs(entries) do
        local button = UI:GetOrCreateLevelButton(frame.LevelScrollChild, i)
        button:SetPoint("TOPLEFT", 0, -yOffset)
        button.Text:SetText(entry.label)
        button.level = entry.level

        if entry.level == selectedLevel then
            button.SelectedTexture:Show()
        else
            button.SelectedTexture:Hide()
        end

        if entry.isCurrent and self:IsViewingActiveSpec() then
            button.CurrentIndicator:Show()
        else
            button.CurrentIndicator:Hide()
        end

        button:SetScript("OnClick", function(self)
            Explorer:OnLevelSelected(self.level)
        end)

        button:Show()
        yOffset = yOffset + 20
    end

end

function Explorer:OnLevelSelected(level)
    selectedLevel = level
    self:RefreshSpecDropdown()
    self:RefreshSwitchButton()
    self:RefreshLevelList()
    self:BuildMapping()
    self:RefreshSlotGrid()
    self:RefreshBarLabels()
    self:RefreshBarToggles()
end

--------------------------------------------------------------------------------
-- Keybinding Helpers
--------------------------------------------------------------------------------

-- Maps a data bar to its binding command prefix.
-- Stance bars (7-10) share ACTIONBUTTON bindings with Bar 1.
local BINDING_PREFIX = {
    [1]  = "ACTIONBUTTON",
    [2]  = "ACTIONBUTTON",
    [3]  = "MULTIACTIONBAR3BUTTON",
    [4]  = "MULTIACTIONBAR4BUTTON",
    [5]  = "MULTIACTIONBAR2BUTTON",
    [6]  = "MULTIACTIONBAR1BUTTON",
    [7]  = "ACTIONBUTTON",
    [8]  = "ACTIONBUTTON",
    [9]  = "ACTIONBUTTON",
    [10] = "ACTIONBUTTON",
}

local KEYBIND_ABBREV = {
    ["ALT%-"]   = "A",
    ["CTRL%-"]  = "C",
    ["SHIFT%-"] = "S",
    ["NUMPAD"]  = "N",
    ["MOUSEWHEELUP"]   = "WU",
    ["MOUSEWHEELDOWN"] = "WD",
    ["BUTTON"]  = "M",
    ["MINUS"]   = "-",
    ["PLUS"]    = "+",
    ["MULTIPLY"] = "*",
    ["DIVIDE"]  = "/",
    ["DECIMAL"] = ".",
}

local function AbbrevKeybind(key)
    if not key then return nil end
    for pattern, replacement in pairs(KEYBIND_ABBREV) do
        key = key:gsub(pattern, replacement)
    end
    return key
end

local function GetSlotKeybind(dataBar, pos)
    local prefix = BINDING_PREFIX[dataBar]
    if not prefix then return nil end
    local key = GetBindingKey(prefix .. pos)
    return AbbrevKeybind(key)
end

--------------------------------------------------------------------------------
-- Slot Grid
--------------------------------------------------------------------------------

function Explorer:RefreshSlotGrid()
    local frame = UI.ExplorerFrame
    if not frame then return end
    
    local mapping   = self:GetCurrentMapping()
    local specIndex = self:GetViewedSpec()
    local currentLevel = Utils:GetPlayerLevel()
    local useLiveData  = self:IsViewingActiveSpec() and selectedLevel == currentLevel
    
    local layout = nil
    if not useLiveData and selectedLevel then
        layout = Layout:Get(selectedLevel, specIndex)
    end
    
    for displayRow = 1, Settings.TOTAL_BARS do
        local rowInfo = mapping[displayRow]
        local dataBar = rowInfo and rowInfo.dataBar
        
        for pos = 1, Settings.SLOTS_PER_BAR do
            local visualSlot = ((displayRow - 1) * Settings.SLOTS_PER_BAR) + pos
            local button = frame.SlotButtons[visualSlot]
            
            if not dataBar then
                button.Icon:SetTexture(nil)
                button.KeybindText:SetText("")
                button.MacroName:SetText("")
                button.DisabledOverlay:Hide()
                button.slotInfo = nil
                button.dataSlot = nil
            else
                local dataSlot = ((dataBar - 1) * Settings.SLOTS_PER_BAR) + pos
                local slotInfo
                
                if useLiveData then
                    slotInfo = ActionBar:GetSlotInfo(dataSlot)
                else
                    slotInfo = layout and layout.slots and layout.slots[dataSlot]
                end
                
                local isEnabled = Profile:IsSlotEnabled(dataSlot, specIndex)
                
                if slotInfo and slotInfo.icon then
                    button.Icon:SetTexture(slotInfo.icon)
                elseif slotInfo and slotInfo.type and slotInfo.type ~= "empty" then
                    button.Icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                else
                    button.Icon:SetTexture(nil)
                end

                if isEnabled then
                    button.DisabledOverlay:Hide()
                else
                    button.DisabledOverlay:Show()
                end
                
                button.KeybindText:SetText(GetSlotKeybind(dataBar, pos) or "")

                if slotInfo and slotInfo.type == "macro" and slotInfo.name then
                    button.MacroName:SetText(slotInfo.name)
                else
                    button.MacroName:SetText("")
                end

                button.slotInfo = slotInfo
                button.dataSlot = dataSlot
            end
        end
    end
end

function Explorer:OnSlotEnter(button)
    local info = button.slotInfo
    local dataSlot = button.dataSlot
    
    if not info or info.type == "empty" then
        return
    end
    
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    local currentLevel = Utils:GetPlayerLevel()
    local useLiveData = self:IsViewingActiveSpec() and selectedLevel == currentLevel
    
    if useLiveData and dataSlot then
        GameTooltip:SetAction(dataSlot)
    else
        GameTooltip:AddLine(info.name or "Unknown", 1, 1, 1)
        if info.type == "macro" and info.body then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(info.body, 0.7, 0.7, 0.7, true)
        end
    end
    
    if dataSlot then
        local bar = ActionBar:GetBarFromSlot(dataSlot)
        local pos = ActionBar:GetPositionInBar(dataSlot)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(
            string.format("Slot %d (Bar %d, #%d)", dataSlot, bar, pos),
            0.4, 0.4, 0.4
        )
    end
    
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Bar Labels
--------------------------------------------------------------------------------

local LABEL_COLOR_NORMAL = { r = 1.0, g = 0.82, b = 0.0 }
local LABEL_COLOR_ACTIVE = { r = 0.0, g = 1.0,  b = 0.0 }
local LABEL_COLOR_GRAYED = { r = 0.5, g = 0.5,  b = 0.5 }

function Explorer:RefreshBarLabels()
    local frame = UI.ExplorerFrame
    if not frame then return end
    
    local mapping = self:GetCurrentMapping()
    
    for displayRow = 1, Settings.TOTAL_BARS do
        local label   = frame.BarLabels[displayRow]
        local rowInfo = mapping[displayRow]
        
        label:SetText(rowInfo.label)
        
        if rowInfo.isActive then
            label:SetTextColor(LABEL_COLOR_ACTIVE.r, LABEL_COLOR_ACTIVE.g, LABEL_COLOR_ACTIVE.b)
        elseif rowInfo.grayed then
            label:SetTextColor(LABEL_COLOR_GRAYED.r, LABEL_COLOR_GRAYED.g, LABEL_COLOR_GRAYED.b)
        else
            label:SetTextColor(LABEL_COLOR_NORMAL.r, LABEL_COLOR_NORMAL.g, LABEL_COLOR_NORMAL.b)
        end
    end
end

--------------------------------------------------------------------------------
-- Bar Toggles
--------------------------------------------------------------------------------

function Explorer:RefreshBarToggles()
    local frame = UI.ExplorerFrame
    if not frame then return end
    
    local mapping   = self:GetCurrentMapping()
    local specIndex = self:GetViewedSpec()
    
    for displayRow = 1, Settings.TOTAL_BARS do
        local toggle  = frame.BarToggles[displayRow]
        local rowInfo = mapping[displayRow]
        local dataBar = rowInfo and rowInfo.dataBar
        
        if not dataBar then
            toggle:SetChecked(false)
            toggle.MixedTexture:Hide()
            toggle.state = "unchecked"
        else
            local fullyEnabled     = Profile:IsBarFullyEnabled(dataBar, specIndex)
            local partiallyEnabled = Profile:IsBarPartiallyEnabled(dataBar, specIndex)
            
            if fullyEnabled then
                toggle:SetChecked(true)
                toggle.MixedTexture:Hide()
                toggle.state = "checked"
            elseif partiallyEnabled then
                toggle:SetChecked(false)
                toggle.MixedTexture:Show()
                toggle.state = "mixed"
            else
                toggle:SetChecked(false)
                toggle.MixedTexture:Hide()
                toggle.state = "unchecked"
            end
        end
    end
end

function Explorer:OnBarToggleClick(displayRow)
    local frame = UI.ExplorerFrame
    if not frame then return end
    
    local mapping = self:GetCurrentMapping()
    local rowInfo = mapping[displayRow]
    if not rowInfo or not rowInfo.dataBar then return end
    
    local dataBar  = rowInfo.dataBar
    local specIndex = self:GetViewedSpec()
    
    local newEnabled = not Profile:IsBarFullyEnabled(dataBar, specIndex)
    Profile:SetBarEnabled(dataBar, newEnabled, specIndex)
    
    self:RefreshBarToggles()
    self:RefreshSlotGrid()
end

--------------------------------------------------------------------------------
-- Full Refresh
--------------------------------------------------------------------------------

function Explorer:Refresh()
    if not UI.ExplorerFrame then return end

    self:RefreshSpecDropdown()
    self:RefreshSwitchButton()
    self:RefreshPropagateToggle()
    self:RefreshLevelList()
    self:BuildMapping()
    self:RefreshSlotGrid()
    self:RefreshBarLabels()
    self:RefreshBarToggles()
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
eventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
eventFrame:SetScript("OnEvent", function(self, event, slot)
    if not Explorer:IsVisible() then return end
    if not Explorer:IsViewingActiveSpec() then return end

    if event == "PLAYER_LEVEL_UP" then
        C_Timer.After(Settings.RESTORE_DELAY, function()
            if Explorer:IsVisible() then
                Explorer:Refresh()
            end
        end)
        return
    end
    
    local currentLevel = Utils:GetPlayerLevel()
    if selectedLevel == currentLevel then
        if event == "UPDATE_BONUS_ACTIONBAR" then
            Explorer:BuildMapping()
            Explorer:RefreshBarLabels()
            Explorer:RefreshBarToggles()
        end
        Explorer:RefreshSlotGrid()
    end
end)
