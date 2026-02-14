--[[----------------------------------------------------------------------------
    Spec integration
    Handles spec detection, switching, and synchronization.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.Spec = {}

local Spec = EBB.Spec
local Utils = EBB.Utils
local Settings = EBB.Settings
local Profile = EBB.Profile
local Layout = EBB.Layout
local Capture = EBB.Capture
local Restore = EBB.Restore

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local isConfirmed = false
local hasProjectEbonhold = false
local changeCallbacks = {}
local pendingSwitch = nil
local pendingSwitchTime = nil
local lastProcessedSpec = nil

--------------------------------------------------------------------------------
-- Check if version is PE (troubleshooting)
--------------------------------------------------------------------------------

function Spec:HasProjectEbonhold()
    return hasProjectEbonhold
end

--------------------------------------------------------------------------------
-- Callback Registration (for Explorer UI)
--------------------------------------------------------------------------------

function Spec:RegisterChangeCallback(callback)
    table.insert(changeCallbacks, callback)
end

local function FireChangeCallbacks(newSpecIndex)
    for _, callback in ipairs(changeCallbacks) do
        callback(newSpecIndex)
    end
end

--------------------------------------------------------------------------------
-- Spec Request
--------------------------------------------------------------------------------

local function RequestCurrentSpec()
    if not hasProjectEbonhold then
        isConfirmed = true
        return false
    end
    
    if ProjectEbonhold.sendToServer and ProjectEbonhold.CS and ProjectEbonhold.CS.REQUEST_CURRENT_SPEC then
        ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_CURRENT_SPEC, "")
        return true
    end
    
    isConfirmed = true
    return false
end

--------------------------------------------------------------------------------
-- Spec Switch Handling
--------------------------------------------------------------------------------

local function HandleSpecSwitch(newSpecIndex, oldSpecIndex)
    local snapshot = Capture:GetSnapshot()
    
    if snapshot then
        Layout:Save(Utils:GetPlayerLevel(), snapshot, oldSpecIndex)
    end
    
    Profile:SetActive(newSpecIndex)
    
    local level = Utils:GetPlayerLevel()
    if Layout:Has(level, newSpecIndex) then
        Restore:Perform(level)
    else
        local levels = Layout:GetSavedLevels(newSpecIndex)
        if #levels > 0 then
            local mostRecent = levels[#levels]
            Utils:Print(string.format("Level %d: No layout found, using level %d", level, mostRecent))
            Restore:Perform(mostRecent)
        else
            if snapshot then
                Layout:Save(level, snapshot, newSpecIndex)
                Utils:Print(string.format("Level %d: Initial layout saved", level))
            end
        end
    end
    
    local specName = Profile:GetSpecName(newSpecIndex)
    Utils:Print(string.format("Switched to: %s", specName))
    
    FireChangeCallbacks(newSpecIndex)
end

local function OnSpecSwitchDetected(newSpecIndex, source)
    if not newSpecIndex or newSpecIndex < 1 or newSpecIndex > 5 then
        return
    end
    
    local oldSpecIndex = Profile:GetActive()
    
    pendingSwitch = nil
    pendingSwitchTime = nil
    
    if lastProcessedSpec == newSpecIndex and isConfirmed then
        FireChangeCallbacks(newSpecIndex)
        return
    end
    
    lastProcessedSpec = newSpecIndex
    
    if not isConfirmed then
        isConfirmed = true
        Profile:SetActive(newSpecIndex)

        local currentLevel = Utils:GetPlayerLevel()
        if not Layout:Has(currentLevel, newSpecIndex) then
            C_Timer.After(Settings.RESTORE_DELAY, function()
                Capture:Perform()
                -- During a rerun Capture:Perform() skips saving; ensure
                -- a session snapshot exists so Master Sync has a baseline.
                if not Layout:Has(currentLevel, newSpecIndex) then
                    local snapshot = Capture:GetSnapshot()
                    if snapshot then
                        Layout:SaveSession(currentLevel, snapshot, newSpecIndex)
                    end
                end
            end)
        end
        
        local specName = Profile:GetSpecName(newSpecIndex)
        Utils:Print(string.format("v%s loaded: %s", Settings.VERSION, specName))
        
        FireChangeCallbacks(newSpecIndex)
        return
    end
    
    if newSpecIndex ~= oldSpecIndex then
        HandleSpecSwitch(newSpecIndex, oldSpecIndex)
    else
        FireChangeCallbacks(newSpecIndex)
    end
    
    if source ~= "UpdateSelectedSpec" and hasProjectEbonhold then
        if ProjectEbonhold.Spec and ProjectEbonhold.Spec.UpdateSelectedSpec then
            ProjectEbonhold.Spec.UpdateSelectedSpec(newSpecIndex)
        end
    end
end

--------------------------------------------------------------------------------
-- Hook System
--------------------------------------------------------------------------------

local function HookSpecSystem()
    if not hasProjectEbonhold then
        return false
    end
    
    local function TryHook()
        local hookCount = 0
        
        if ProjectEbonhold.SpecService and ProjectEbonhold.SpecService.ApplySpec then
            local originalApplySpec = ProjectEbonhold.SpecService.ApplySpec
            
            ProjectEbonhold.SpecService.ApplySpec = function(specIndex)
                originalApplySpec(specIndex)
                
                if specIndex and specIndex >= 1 and specIndex <= 5 then
                    OnSpecSwitchDetected(specIndex, "ApplySpec")
                end
            end
            
            hookCount = hookCount + 1
        end
        
        if ProjectEbonhold.Spec and ProjectEbonhold.Spec.UpdateSelectedSpec then
            local originalUpdateSelectedSpec = ProjectEbonhold.Spec.UpdateSelectedSpec
            
            ProjectEbonhold.Spec.UpdateSelectedSpec = function(specIndex)
                originalUpdateSelectedSpec(specIndex)
                
                if specIndex and specIndex >= 1 and specIndex <= 5 then
                    if lastProcessedSpec ~= specIndex then
                        OnSpecSwitchDetected(specIndex, "UpdateSelectedSpec")
                    end
                end
            end
            
            hookCount = hookCount + 1
        end
        
        if hookCount > 0 then
            if not isConfirmed then
                RequestCurrentSpec()
            end
            return true
        end
        
        return false
    end
    
    if TryHook() then
        return true
    end
    
    C_Timer.After(0.1, function()
        if not TryHook() then
            C_Timer.After(1, function()
                if not TryHook() then
                    if ProjectEbonhold.onEventReceived and ProjectEbonhold.SS then
                        ProjectEbonhold.onEventReceived(ProjectEbonhold.SS.SEND_PLAYER_SPEC_INDEX, function(body)
                            local specIndex = tonumber(body)
                            if specIndex then
                                OnSpecSwitchDetected(specIndex, "EventFallback")
                            end
                        end)
                    end
                end
            end)
        end
    end)
    
    return true
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function Spec:Initialize()
    hasProjectEbonhold = (ProjectEbonhold ~= nil)
    
    if hasProjectEbonhold then
        HookSpecSystem()
        return RequestCurrentSpec()
    else
        isConfirmed = true
        return false
    end
end

function Spec:IsConfirmed()
    return isConfirmed
end

function Spec:GetActive()
    return Profile:GetActive()
end

function Spec:Switch(specIndex)
    if not specIndex or specIndex < 1 or specIndex > 5 then
        Utils:PrintError("Invalid spec index")
        return false
    end
    
    if specIndex == Profile:GetActive() then
        return true
    end
    
    if not hasProjectEbonhold then
        Utils:PrintError("Project Ebonhold not available")
        return false
    end
    
    pendingSwitch = specIndex
    pendingSwitchTime = GetTime()
    
    if ProjectEbonhold.SpecService and ProjectEbonhold.SpecService.ApplySpec then
        ProjectEbonhold.SpecService.ApplySpec(specIndex)
        return true
    end
    
    if ProjectEbonhold.sendToServer and ProjectEbonhold.CS and ProjectEbonhold.CS.REQUEST_APPLY_SPECS then
        ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_APPLY_SPECS, tostring(specIndex))
        OnSpecSwitchDetected(specIndex, "DirectSend")
        return true
    end
    
    pendingSwitch = nil
    pendingSwitchTime = nil
    return false
end

function Spec:IsSwitchPending()
    return pendingSwitch ~= nil
end

function Spec:GetPendingSpec()
    return pendingSwitch
end

--------------------------------------------------------------------------------
-- Timeout Check
--------------------------------------------------------------------------------

function Spec:CheckTimeout()
    if pendingSwitch and pendingSwitchTime then
        if GetTime() - pendingSwitchTime > 5 then
            Utils:Print("Spec switch timed out: Resetting")
            pendingSwitch = nil
            pendingSwitchTime = nil
            FireChangeCallbacks(Profile:GetActive())
        end
    end
end
