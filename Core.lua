--[[----------------------------------------------------------------------------
    Main addon initialization and event coordination.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.Core = {}

local Core = EBB.Core
local Utils = EBB.Utils
local Settings = EBB.Settings
local Profile = EBB.Profile
local Layout = EBB.Layout
local Capture = EBB.Capture
local Restore = EBB.Restore
local Spec = EBB.Spec
local FirstRun = EBB.FirstRun

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local isInitialized = false

--------------------------------------------------------------------------------
-- Debug Logging
--------------------------------------------------------------------------------

local debugMode = false

local function DebugPrint(...)
    if debugMode then
        local args = {...}
        local msg = ""
        for i, v in ipairs(args) do
            msg = msg .. tostring(v)
            if i < #args then msg = msg .. " " end
        end
        Utils:Print("|cFFFFFF00[DEBUG]|r " .. msg)
    end
end

function Core:SetDebugMode(enabled)
    debugMode = enabled
    Utils:Print("Debug mode: " .. (enabled and "ON" or "OFF"))
end

function Core:IsDebugMode()
    return debugMode
end

--------------------------------------------------------------------------------
-- SavedVariables Initialization
--------------------------------------------------------------------------------

local function MigrateCompanionSlots(newVersion)
    if not EBB_CharDB.specs then return end

    local enriched = 0
    for specIndex, spec in pairs(EBB_CharDB.specs) do
        if spec.layouts then
            for level, layout in pairs(spec.layouts) do
                if layout.slots then
                    for slot, info in pairs(layout.slots) do
                        if info.type == "companion" and not info.name then
                            local ct = info.companionType or info.subType
                            if not ct then break end

                            -- Try direct index lookup first
                            if info.id then
                                local _, name = GetCompanionInfo(ct, info.id)
                                if name then
                                    info.name = name
                                    enriched = enriched + 1
                                end
                            end

                            -- Fallback: match by icon texture
                            if not info.name and info.icon then
                                for i = 1, GetNumCompanions(ct) do
                                    local _, name, _, icon = GetCompanionInfo(ct, i)
                                    if icon == info.icon then
                                        info.name = name
                                        enriched = enriched + 1
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if enriched > 0 then
        Utils:PrintForced("|cFF00FF00Migration to v" .. newVersion
            .. ":|r Enriched " .. enriched .. " companion slot(s)")
    end
end

local function MigrateToVersion(oldVersion, newVersion)
    if not oldVersion or oldVersion < "0.4.0" then
        -- v0.3.0: Only keep the highest saved layout per spec.
        -- Previous versions stored one layout per level (1-80).
        -- The new restore logic uses the highest layout as a master
        -- and restores it at every level during reruns.
        if EBB_CharDB.specs then
            for specIndex, spec in pairs(EBB_CharDB.specs) do
                if spec.layouts then
                    local highestLevel = nil
                    for level in pairs(spec.layouts) do
                        if not highestLevel or level > highestLevel then
                            highestLevel = level
                        end
                    end

                    if highestLevel then
                        local kept = spec.layouts[highestLevel]
                        spec.layouts = { [highestLevel] = kept }

                        -- Seed highestSeenLevel from the data we have
                        if not EBB_CharDB.highestSeenLevel
                           or highestLevel > EBB_CharDB.highestSeenLevel then
                            EBB_CharDB.highestSeenLevel = highestLevel
                        end
                    end
                end
            end
            Utils:PrintForced("|cFF00FF00Migration to v" .. newVersion
                .. " complete:|r Pruned layouts, kept highest per spec"
                .. " (highestSeenLevel: " .. (EBB_CharDB.highestSeenLevel or 0) .. ")")
            return true
        else
            Utils:PrintForced("|cFFFF0000Migration to v" .. newVersion
                .. " failed:|r No spec data found")
            return false
        end
    end

    return true
end

local function InitializeSavedVariables()
    if not EBB_CharDB then
        EBB_CharDB = {
            version = Settings.VERSION,
        }
    end

    local oldVersion = EBB_CharDB.version

    Settings:Initialize()
    Profile:Initialize()

    if oldVersion ~= Settings.VERSION then
        local success = MigrateToVersion(oldVersion, Settings.VERSION)
        EBB_CharDB.version = Settings.VERSION
    end
end

--------------------------------------------------------------------------------
-- Level Tracking
--------------------------------------------------------------------------------

local function GetLastKnownLevel()
    return EBB_CharDB.lastKnownLevel
end

local function SetLastKnownLevel(level)
    EBB_CharDB.lastKnownLevel = level
end

local function GetHighestSeenLevel()
    return EBB_CharDB.highestSeenLevel or 0
end

function Core:GetHighestSeenLevel()
    return GetHighestSeenLevel()
end

local function UpdateHighestSeenLevel(level)
    local current = EBB_CharDB.highestSeenLevel or 0
    if level > current then
        EBB_CharDB.highestSeenLevel = level
    end
end

--------------------------------------------------------------------------------
-- Level-Up Handling with Restore from Highest Known Layout
--------------------------------------------------------------------------------

local function HandleLevelUp(newLevel)
    local oldLevel = GetLastKnownLevel() or (newLevel - 1)
    local prevHighest = GetHighestSeenLevel()
    SetLastKnownLevel(newLevel)
    UpdateHighestSeenLevel(newLevel)

    local highest = GetHighestSeenLevel()

    -- During a rerun, always restore from the master layout with forceClear
    -- to remove server-placed spells. This includes both:
    --   (a) still below the highest level (mid-rerun), and
    --   (b) reaching the exact highest level from below (end of rerun).
    -- Case (b) matters because the server auto-places newly learned spells
    -- during level-ups, and those placements must be cleared even at the
    -- peak level. Without this, reaching highestSeenLevel after a death
    -- reset would skip forceClear and leave server-placed spells behind.
    if prevHighest >= newLevel and oldLevel < prevHighest then
        Capture:Cancel()
        DebugPrint(string.format("Level %d: Rerun, restoring from master (level %d)", newLevel, highest))
        Restore:Perform(highest, true)
        return
    end

    -- At or above the highest known level: restore if a permanent layout
    -- exists for this exact level.
    if Layout:Has(newLevel) then
        Capture:Cancel()
        Restore:Perform(newLevel)
        return
    end

    -- First-time leveling or no layout exists.
    -- Do not save here; the debounced ACTIONBAR_SLOT_CHANGED capture
    -- will save the current bars once they stabilize.
end

--------------------------------------------------------------------------------
-- Level 1 Return Detection
--------------------------------------------------------------------------------

local function HandleLevelChange(newLevel)
    local oldLevel = GetLastKnownLevel()

    if oldLevel and oldLevel > 1 and newLevel == 1 then
        -- Death reset detected (e.g. 80 -> 1). By the time this event
        -- fires the server has already stripped high-level spells from
        -- the action bars, so a snapshot taken NOW would be incomplete.
        -- Only save if no layout exists yet; otherwise the previously
        -- captured (complete) layout is more trustworthy.
        Capture:Cancel()
        if not Layout:Has(oldLevel) then
            local snapshot = Capture:GetSnapshot()
            if snapshot then
                Layout:Save(oldLevel, snapshot)
                DebugPrint(string.format("Death reset: Level %d saved (no prior layout)", oldLevel))
            end
        else
            DebugPrint(string.format("Death reset: Level %d layout preserved (already saved)", oldLevel))
        end

        SetLastKnownLevel(newLevel)
        if Layout:Has(1) then
            Utils:Print("Returned to level 1: Restoring bars")
            Restore:Perform(1)
        end

        -- Save a session snapshot so Master Sync has a diff baseline
        -- at level 1. Without this, the first Capture:Perform() finds
        -- no old snapshot and skips the sync entirely.
        C_Timer.After(Settings.RESTORE_DELAY, function()
            local snapshot = Capture:GetSnapshot()
            if snapshot then
                Layout:SaveSession(newLevel, snapshot)
            end
        end)
        return true
    end

    return false
end

--------------------------------------------------------------------------------
-- Public State
--------------------------------------------------------------------------------

function Core:IsReady()
    return isInitialized and FirstRun:CanAddonRun() and Spec:IsConfirmed()
end

function Core:RegisterSpecChangeCallback(callback)
    return Spec:RegisterChangeCallback(callback)
end

function Core:GetActiveSpec()
    return Spec:GetActive()
end

function Core:SwitchSpec(specIndex)
    return Spec:Switch(specIndex)
end

function Core:IsSpecSwitchPending()
    return Spec:IsSwitchPending()
end

function Core:GetPendingSpec()
    return Spec:GetPendingSpec()
end

--------------------------------------------------------------------------------
-- Event Handlers
--------------------------------------------------------------------------------

local function OnAddonLoaded(addonName)
    if addonName ~= ADDON_NAME then return end
    
    DebugPrint("ADDON_LOADED:", addonName)
    InitializeSavedVariables()
end

local function OnPlayerEnteringWorld()
    DebugPrint("PLAYER_ENTERING_WORLD, isInitialized:", tostring(isInitialized))
    
    if isInitialized then return end
    isInitialized = true
    
    local firstRunResult = FirstRun:CheckOnLoad()
    DebugPrint("FirstRun check result:", firstRunResult)
    
    if firstRunResult == "show_popup" then
        C_Timer.After(0.5, function()
            FirstRun:Show()
        end)
        return
    elseif firstRunResult == "disabled_permanent" then
        DebugPrint("Addon disabled by user choice")
        return
    end
    
    Core:InitializeAddon()
end

function Core:OnAddonEnabled()
    if not isInitialized then return end
    self:InitializeAddon()
end

function Core:InitializeAddon()
    local currentLevel = Utils:GetPlayerLevel()
    if not GetLastKnownLevel() then
        SetLastKnownLevel(currentLevel)
    end
    if not EBB_CharDB.highestSeenLevel then
        EBB_CharDB.highestSeenLevel = currentLevel
    end
    UpdateHighestSeenLevel(currentLevel)

    -- Companion migration requires the companion API which is only
    -- available after PLAYER_ENTERING_WORLD, not during ADDON_LOADED.
    if not EBB_CharDB.companionsMigrated then
        MigrateCompanionSlots(Settings.VERSION)
        EBB_CharDB.companionsMigrated = true
    end

    local specRequested = Spec:Initialize()

    if not specRequested then
        -- Capture on login only if no layout exists for the current level.
        -- When a layout already exists, it is preserved; the debounced
        -- capture from ACTIONBAR_SLOT_CHANGED will update it if the player
        -- makes manual changes after login.
        if not Layout:Has(currentLevel) then
            C_Timer.After(Settings.RESTORE_DELAY, function()
                Capture:Perform()
                -- During a rerun Capture:Perform() skips saving; ensure
                -- a session snapshot exists so Master Sync has a baseline.
                if not Layout:Has(currentLevel) then
                    local snapshot = Capture:GetSnapshot()
                    if snapshot then
                        Layout:SaveSession(currentLevel, snapshot)
                    end
                end
            end)
        else
            -- Ensure a session-only snapshot exists for Master Sync diffing.
            -- Without this, the first slot change after login would have
            -- no oldSnapshot to compare against.
            C_Timer.After(Settings.RESTORE_DELAY, function()
                local snapshot = Capture:GetSnapshot()
                if snapshot then
                    Layout:SaveSession(currentLevel, snapshot)
                end
            end)
        end
        Utils:Print(string.format("v%s loaded", Settings.VERSION))
    end
end

local pendingLevelUpTimer = nil
local pendingCombatLevelUp = nil

local function GetEventFrame()
    return EbonholdBarBuilderFrame
end

local function ExecuteLevelUp(newLevel)
    if UnitAffectingCombat("player") then
        -- Attempt a restore now — may partially succeed even in combat.
        -- Then schedule a full retry after combat drops as safety net.
        C_Timer.After(Settings.VERIFY_DELAY, function()
            HandleLevelUp(newLevel)
        end)
        pendingCombatLevelUp = newLevel
        GetEventFrame():RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    HandleLevelUp(newLevel)
end

local function OnPlayerRegenEnabled()
    GetEventFrame():UnregisterEvent("PLAYER_REGEN_ENABLED")
    if pendingCombatLevelUp then
        local level = pendingCombatLevelUp
        pendingCombatLevelUp = nil
        C_Timer.After(Settings.RESTORE_DELAY, function()
            HandleLevelUp(level)
        end)
    end
end

local function OnPlayerLevelUp(newLevel)
    if not FirstRun:CanAddonRun() then return end
    if not Spec:IsConfirmed() then return end

    -- Cancel any pending level-up timer. The events can be spaced further
    -- apart than RESTORE_DELAY (server sends each level individually), so
    -- a simple value comparison is not enough — we must explicitly cancel.
    if pendingLevelUpTimer then
        pendingLevelUpTimer.cancelled = true
    end

    local timer = { cancelled = false }
    pendingLevelUpTimer = timer

    C_Timer.After(Settings.RESTORE_DELAY, function()
        if timer.cancelled then return end
        pendingLevelUpTimer = nil
        ExecuteLevelUp(newLevel)
    end)
end

local function OnUnitLevel(unit)
    if unit ~= "player" then return end
    if not FirstRun:CanAddonRun() then return end
    if not Spec:IsConfirmed() then return end
    
    local newLevel = Utils:GetPlayerLevel()
    HandleLevelChange(newLevel)
end

local function OnActionBarSlotChanged(slot)
    if not isInitialized then return end
    if not FirstRun:CanAddonRun() then return end
    if not Spec:IsConfirmed() then return end
    if Restore:IsInProgress() then return end
    if Spec:IsSwitchPending() then return end
    
    Capture:Schedule()
end

local function OnSpellsChanged()
    if not isInitialized then return end
    if not FirstRun:CanAddonRun() then return end
    if not Spec:IsConfirmed() then return end
    
    Spec:CheckTimeout()
end

local function OnBonusBarUpdate()
    if not isInitialized then return end
    if not FirstRun:CanAddonRun() then return end
    if not Spec:IsConfirmed() then return end
    if Restore:IsInProgress() then return end
    if Spec:IsSwitchPending() then return end
    
    DebugPrint("UPDATE_BONUS_ACTIONBAR, stance:", EBB.ActionBar:GetStanceIndex())
    Capture:Schedule()
end

--------------------------------------------------------------------------------
-- Event Frame
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame", "EbonholdBarBuilderFrame")

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_LEVEL_UP")
frame:RegisterEvent("UNIT_LEVEL")
frame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        OnAddonLoaded(...)
    elseif event == "PLAYER_ENTERING_WORLD" then
        OnPlayerEnteringWorld()
    elseif event == "PLAYER_LEVEL_UP" then
        OnPlayerLevelUp(...)
    elseif event == "UNIT_LEVEL" then
        OnUnitLevel(...)
    elseif event == "ACTIONBAR_SLOT_CHANGED" then
        OnActionBarSlotChanged(...)
    elseif event == "SPELLS_CHANGED" then
        OnSpellsChanged()
    elseif event == "UPDATE_BONUS_ACTIONBAR" then
        OnBonusBarUpdate()
    elseif event == "PLAYER_REGEN_ENABLED" then
        OnPlayerRegenEnabled()
    end
end)

--------------------------------------------------------------------------------
-- Slash Commands
--------------------------------------------------------------------------------

SLASH_EBB1 = "/ebb"
SlashCmdList["EBB"] = function(msg)
    msg = msg and strtrim(msg):lower() or ""

    if msg == "enable" then
        FirstRun:ResetChoice()
        FirstRun:SetSessionDisabled(false)
        FirstRun:Show()
        return
    end
    
    if msg == "debug" then
        Core:SetDebugMode(not debugMode)
        return
    end
    
    if msg == "debugstatus" then
        Utils:Print("=== Debug Status ===")
        Utils:Print("isInitialized: " .. tostring(isInitialized))
        Utils:Print("addonEnabled: " .. tostring(FirstRun:GetEnabledState()))
        Utils:Print("canAddonRun: " .. tostring(FirstRun:CanAddonRun()))
        Utils:Print("stanceIndex: " .. tostring(EBB.ActionBar:GetStanceIndex()))
        return
    end
    
    if not FirstRun:CanAddonRun() then
        Utils:Print("Addon is disabled. Use '/ebb enable' to enable.")
        return
    end
    
    if msg == "save" then
        if not Spec:IsConfirmed() then
            Utils:PrintError("Waiting for spec confirmation...")
            return
        end
        Capture:Perform(true, true)

    elseif msg == "restore" then
        if not Spec:IsConfirmed() then
            Utils:PrintError("Waiting for spec confirmation...")
            return
        end
        Restore:Perform()
        
    elseif msg == "status" then
        local specIndex = Profile:GetActive()
        local specName = Profile:GetSpecName(specIndex)
        local level = Utils:GetPlayerLevel()
        local layout, source = Layout:Get(level)
        
        Utils:Print(string.format("Spec: %s (#%d)", specName, specIndex))
        Utils:Print(string.format("Enabled slots: %d/%d", 
            Profile:GetEnabledSlotCount(), Settings.TOTAL_SLOTS))
        
        if layout then
            Utils:Print(string.format("Level %d: %d slots saved (%s)", 
                level, layout.configuredSlots or 0, source))
        else
            Utils:Print(string.format("Level %d: No layout saved", level))
        end
        
        Utils:Print(string.format("Total layouts: %d", Layout:GetCount()))
        
    elseif msg == "list" then
        local specIndex = Profile:GetActive()
        local specName = Profile:GetSpecName(specIndex)
        Utils:Print(string.format("Layouts in '%s':", specName))
        local levels = Layout:GetSavedLevels()
        
        if #levels == 0 then
            Utils:Print("  (none)")
        else
            for _, level in ipairs(levels) do
                local layout = Layout:Get(level)
                Utils:Print(string.format("  Level %d: %d slots", level, layout.configuredSlots or 0))
            end
        end
        
    elseif msg == "specs" then
        Utils:Print("Specs:")
        local active = Profile:GetActive()
        
        for specIndex = 1, 5 do
            local marker = (specIndex == active) and " (active)" or ""
            local specName = Profile:GetSpecName(specIndex)
            local layoutCount = Layout:GetCount(specIndex)
            Utils:Print(string.format("  %d. %s: %d layouts%s", specIndex, specName, layoutCount, marker))
        end
        
    elseif msg == "clear" then
        Layout:ClearAll()
        Utils:PrintSuccess("All layouts cleared for current spec")
        
    elseif msg == "ui" or msg == "config" then
        if EBB.Explorer then
            EBB.Explorer:Toggle()
        else
            Utils:PrintError("Explorer UI not loaded")
        end
        
    else
        Utils:Print("Commands:")
        Utils:Print("  /ebb ui - Open configuration panel")
        Utils:Print("  /ebb status - Show current status")
        Utils:Print("  /ebb save - Save current level")
        Utils:Print("  /ebb restore - Restore current level")
        Utils:Print("  /ebb clear - Clear all layouts in current spec")
    end
end
