--[[---------------------------------------------------------------------------- 
    Spec-based profile management
    Manages per-spec slot enabled states.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.Profile = {}

local Profile = EBB.Profile
local Utils = EBB.Utils
local Settings = EBB.Settings

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local NUM_SPECS = 5
local DEFAULT_SPEC_NAMES = {
    "Primary Specialization",
    "Secondary Specialization",
    "Third Specialization",
    "Fourth Specialization",
    "Fifth Specialization",
}

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

local function CreateDefaultSpec()
    local enabledSlots = {}
    for slot = 1, Settings.TOTAL_SLOTS do
        enabledSlots[slot] = true
    end
    return {
        enabledSlots = enabledSlots,
        layouts = {},
    }
end

function Profile:Initialize()
    if not EBB_CharDB.specs then
        EBB_CharDB.specs = {}
    end
    
    for specIndex = 1, NUM_SPECS do
        if not EBB_CharDB.specs[specIndex] then
            EBB_CharDB.specs[specIndex] = CreateDefaultSpec()
        end
    end
    
    if not EBB_CharDB.activeSpecIndex or 
       EBB_CharDB.activeSpecIndex < 1 or 
       EBB_CharDB.activeSpecIndex > NUM_SPECS then
        EBB_CharDB.activeSpecIndex = 1
    end
end

--------------------------------------------------------------------------------
-- Spec Name
--------------------------------------------------------------------------------

function Profile:GetSpecName(specIndex)
    if specIndex < 1 or specIndex > NUM_SPECS then
        return nil
    end
    
    if SpecCustomNames and SpecCustomNames[specIndex] and SpecCustomNames[specIndex] ~= "" then
        return SpecCustomNames[specIndex]
    end
    
    return DEFAULT_SPEC_NAMES[specIndex]
end

--------------------------------------------------------------------------------
-- Active Spec
--------------------------------------------------------------------------------

function Profile:GetActive()
    return EBB_CharDB.activeSpecIndex or 1
end

function Profile:SetActive(specIndex)
    if not specIndex or specIndex < 1 or specIndex > NUM_SPECS then
        return false
    end
    
    EBB_CharDB.activeSpecIndex = specIndex
    return true
end

function Profile:GetActiveData()
    local specIndex = self:GetActive()
    return EBB_CharDB.specs[specIndex], specIndex
end

--------------------------------------------------------------------------------
-- Spec Listing
--------------------------------------------------------------------------------

function Profile:GetAll()
    local specs = {}
    for i = 1, NUM_SPECS do
        specs[i] = i
    end
    return specs
end

function Profile:GetCount()
    return NUM_SPECS
end

function Profile:Exists(specIndex)
    return specIndex >= 1 and specIndex <= NUM_SPECS
end

--------------------------------------------------------------------------------
-- Enabled Slots Management
--------------------------------------------------------------------------------

function Profile:IsSlotEnabled(slot, specIndex)
    specIndex = specIndex or self:GetActive()
    
    local spec = EBB_CharDB.specs[specIndex]
    if not spec or not spec.enabledSlots then
        return true
    end
    
    if spec.enabledSlots[slot] == nil then
        return true
    end
    
    return spec.enabledSlots[slot]
end

function Profile:SetSlotEnabled(slot, enabled, specIndex)
    specIndex = specIndex or self:GetActive()
    
    local spec = EBB_CharDB.specs[specIndex]
    if not spec then
        return false
    end
    
    if not spec.enabledSlots then
        spec.enabledSlots = {}
    end
    
    spec.enabledSlots[slot] = enabled
    return true
end

function Profile:SetBarEnabled(barNumber, enabled, specIndex)
    specIndex = specIndex or self:GetActive()
    
    if barNumber < 1 or barNumber > Settings.TOTAL_BARS then
        return false
    end
    
    local startSlot = ((barNumber - 1) * Settings.SLOTS_PER_BAR) + 1
    local endSlot = startSlot + Settings.SLOTS_PER_BAR - 1
    
    for slot = startSlot, endSlot do
        self:SetSlotEnabled(slot, enabled, specIndex)
    end
    
    return true
end

function Profile:IsBarFullyEnabled(barNumber, specIndex)
    specIndex = specIndex or self:GetActive()
    
    if barNumber < 1 or barNumber > Settings.TOTAL_BARS then
        return false
    end
    
    local startSlot = ((barNumber - 1) * Settings.SLOTS_PER_BAR) + 1
    local endSlot = startSlot + Settings.SLOTS_PER_BAR - 1
    
    for slot = startSlot, endSlot do
        if not self:IsSlotEnabled(slot, specIndex) then
            return false
        end
    end
    
    return true
end

function Profile:IsBarPartiallyEnabled(barNumber, specIndex)
    specIndex = specIndex or self:GetActive()
    
    if barNumber < 1 or barNumber > Settings.TOTAL_BARS then
        return false
    end
    
    local startSlot = ((barNumber - 1) * Settings.SLOTS_PER_BAR) + 1
    local endSlot = startSlot + Settings.SLOTS_PER_BAR - 1
    
    local hasEnabled = false
    local hasDisabled = false
    
    for slot = startSlot, endSlot do
        if self:IsSlotEnabled(slot, specIndex) then
            hasEnabled = true
        else
            hasDisabled = true
        end
        
        if hasEnabled and hasDisabled then
            return true
        end
    end
    
    return false
end

function Profile:SetAllSlotsEnabled(enabled, specIndex)
    specIndex = specIndex or self:GetActive()
    
    for slot = 1, Settings.TOTAL_SLOTS do
        self:SetSlotEnabled(slot, enabled, specIndex)
    end
    
    return true
end

function Profile:GetEnabledSlotCount(specIndex)
    specIndex = specIndex or self:GetActive()

    local count = 0
    for slot = 1, Settings.TOTAL_SLOTS do
        if self:IsSlotEnabled(slot, specIndex) then
            count = count + 1
        end
    end

    return count
end

--------------------------------------------------------------------------------
-- Propagate Changes (per-spec)
--------------------------------------------------------------------------------

function Profile:GetPropagateChanges(specIndex)
    specIndex = specIndex or self:GetActive()

    local spec = EBB_CharDB.specs[specIndex]
    if not spec then
        return false
    end

    if spec.propagateChanges == nil then
        return true
    end

    return spec.propagateChanges
end

function Profile:SetPropagateChanges(enabled, specIndex)
    specIndex = specIndex or self:GetActive()

    local spec = EBB_CharDB.specs[specIndex]
    if not spec then
        return false
    end

    spec.propagateChanges = enabled
    return true
end
