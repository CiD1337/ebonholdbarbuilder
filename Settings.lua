--[[----------------------------------------------------------------------------
    Configuration constants and settings management.
    Settings are stored in EBB_CharDB.settings and are character-specific.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.Settings = {}

local Settings = EBB.Settings

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

Settings.VERSION = "0.5.4"
Settings.MAX_LEVEL = 80

Settings.DEBOUNCE_TIME = 0.5
Settings.RESTORE_DELAY = 0.5
Settings.VERIFY_DELAY = 0.8
Settings.VERIFY_RETRIES = 2

Settings.TOTAL_SLOTS = 120
Settings.SLOTS_PER_BAR = 12
Settings.TOTAL_BARS = 10

--------------------------------------------------------------------------------
-- Default Settings
--------------------------------------------------------------------------------

local DEFAULT_SETTINGS = {
    barLabels = {
        [1] = "Action Bar 1",
        [2] = "Action Bar 2",
        [3] = "Action Bar 3",
        [4] = "Action Bar 4",
        [5] = "Action Bar 5",
        [6] = "Action Bar 6",
        [7] = "Stance Bar A",
        [8] = "Stance Bar B",
        [9] = "Stance Bar C",
        [10] = "Stance Bar D",
    },
}

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function Settings:Initialize()
    if not EBB_CharDB.settings then
        EBB_CharDB.settings = {}
    end
    
    for key, value in pairs(DEFAULT_SETTINGS) do
        if EBB_CharDB.settings[key] == nil then
            if type(value) == "table" then
                EBB_CharDB.settings[key] = EBB.Utils:DeepCopy(value)
            else
                EBB_CharDB.settings[key] = value
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Get / Set
--------------------------------------------------------------------------------

function Settings:Get(key)
    if EBB_CharDB.settings then
        return EBB_CharDB.settings[key]
    end
    return DEFAULT_SETTINGS[key]
end

function Settings:Set(key, value)
    if not EBB_CharDB.settings then
        EBB_CharDB.settings = {}
    end
    EBB_CharDB.settings[key] = value
end

--------------------------------------------------------------------------------
-- Bar Labels
--------------------------------------------------------------------------------

function Settings:GetBarLabel(barNumber)
    if barNumber < 1 or barNumber > self.TOTAL_BARS then
        return nil
    end
    
    local labels = self:Get("barLabels")
    if labels and labels[barNumber] then
        return labels[barNumber]
    end
    
    return "Action Bar " .. barNumber
end

function Settings:SetBarLabel(barNumber, label)
    if barNumber < 1 or barNumber > self.TOTAL_BARS then
        return false
    end
    
    local labels = self:Get("barLabels")
    if not labels then
        labels = EBB.Utils:DeepCopy(DEFAULT_SETTINGS.barLabels)
    end
    
    labels[barNumber] = label
    self:Set("barLabels", labels)
    return true
end

function Settings:ResetBarLabels()
    self:Set("barLabels", EBB.Utils:DeepCopy(DEFAULT_SETTINGS.barLabels))
end
