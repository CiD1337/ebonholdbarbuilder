--[[----------------------------------------------------------------------------
    Behavior and event handling for the first-run opt-in dialog.
    Manages addon enabled state and user choice persistence.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.FirstRun = {}

local FirstRun = EBB.FirstRun
local UI = EBB.UI
local Utils = EBB.Utils

--------------------------------------------------------------------------------
-- State Queries
--------------------------------------------------------------------------------

function FirstRun:GetEnabledState()
    if not EBB_CharDB then return nil end
    return EBB_CharDB.addonEnabled
end

function FirstRun:IsAddonActive()
    return self:GetEnabledState() == true
end

function FirstRun:NeedsUserChoice()
    return self:GetEnabledState() == nil
end

function FirstRun:IsExplicitlyDisabled()
    return self:GetEnabledState() == false
end

--------------------------------------------------------------------------------
-- State Management
--------------------------------------------------------------------------------

function FirstRun:SetEnabled(enabled, remember)
    if not EBB_CharDB then return end
    
    if remember then
        EBB_CharDB.addonEnabled = enabled
    else
        EBB_CharDB.addonEnabled = enabled
        EBB_CharDB.rememberChoice = false
    end
    
    if remember then
        EBB_CharDB.rememberChoice = true
    end
end

function FirstRun:ResetChoice()
    if not EBB_CharDB then return end
    EBB_CharDB.addonEnabled = nil
    EBB_CharDB.rememberChoice = nil
end

--------------------------------------------------------------------------------
-- Session State
--------------------------------------------------------------------------------

local sessionDisabled = false

function FirstRun:SetSessionDisabled(disabled)
    sessionDisabled = disabled
end

function FirstRun:IsSessionDisabled()
    return sessionDisabled
end

function FirstRun:CanAddonRun()
    if sessionDisabled then return false end
    local state = self:GetEnabledState()
    return state == true
end

--------------------------------------------------------------------------------
-- Show / Hide / Toggle
--------------------------------------------------------------------------------

function FirstRun:Show()
    local frame = UI:CreateFirstRunFrame()
    self:Initialize()
    
    frame.RememberCheckbox:SetChecked(false)
    
    frame:Show()
end

function FirstRun:Hide()
    if UI.FirstRunFrame then
        UI.FirstRunFrame:Hide()
    end
end

function FirstRun:IsVisible()
    return UI.FirstRunFrame and UI.FirstRunFrame:IsShown()
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

local isInitialized = false

function FirstRun:Initialize()
    if isInitialized then return end
    isInitialized = true
    
    local frame = UI.FirstRunFrame
    
    frame.YesButton:SetScript("OnClick", function()
        FirstRun:OnYesClick()
    end)
    
    frame.NoButton:SetScript("OnClick", function()
        FirstRun:OnNoClick()
    end)
end

--------------------------------------------------------------------------------
-- Button Handlers
--------------------------------------------------------------------------------

function FirstRun:OnYesClick()
    local frame = UI.FirstRunFrame
    local remember = frame.RememberCheckbox:GetChecked()
    
    self:SetEnabled(true, remember)
    self:SetSessionDisabled(false)
    self:Hide()

    if EBB.Core and EBB.Core.OnAddonEnabled then
        EBB.Core:OnAddonEnabled()
    end
    
    Utils:PrintForced("Enabled")
end

function FirstRun:OnNoClick()
    local frame = UI.FirstRunFrame
    local remember = frame.RememberCheckbox:GetChecked()
    
    self:SetEnabled(false, remember)
    self:SetSessionDisabled(true)
    self:Hide()
    
    if remember then
        Utils:PrintForced("Disabled (remember)")
    else
        Utils:PrintForced("Disabled")
    end
end

--------------------------------------------------------------------------------
-- Check on Load
--------------------------------------------------------------------------------

function FirstRun:CheckOnLoad()
    if EBB_CharDB and EBB_CharDB.askNextLogin then
        EBB_CharDB.askNextLogin = false
        self:ResetChoice()
        return "show_popup"
    end
    
    local state = self:GetEnabledState()
    local remembered = EBB_CharDB and EBB_CharDB.rememberChoice
    
    if state == nil then
        return "show_popup"
    elseif state == false then
        if remembered then
            self:SetSessionDisabled(true)
            return "disabled_permanent"
        else
            self:ResetChoice()
            return "show_popup"
        end
    else
        return "enabled"
    end
end
