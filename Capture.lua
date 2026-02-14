--[[----------------------------------------------------------------------------
    Capture coordination and debounce logic.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.Capture = {}

local Capture = EBB.Capture
local Utils = EBB.Utils
local Settings = EBB.Settings
local ActionBar = EBB.ActionBar
local Profile = EBB.Profile
local Layout = EBB.Layout

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local pendingCapture = false
local lastDebounceTime = 0

--------------------------------------------------------------------------------
-- Capture All Slots
--------------------------------------------------------------------------------

local function CaptureAllSlots()
    local snapshot = {
        timestamp = Utils:GetTimestamp(),
        playerLevel = Utils:GetPlayerLevel(),
        slots = {},
    }
    
    local configuredCount = 0
    local capturedCount = 0
    
    for slot = 1, Settings.TOTAL_SLOTS do
        if Profile:IsSlotEnabled(slot) then
            local slotInfo = ActionBar:GetSlotInfo(slot)
            if slotInfo then
                snapshot.slots[slot] = slotInfo
                capturedCount = capturedCount + 1
                if slotInfo.type ~= "empty" then
                    configuredCount = configuredCount + 1
                end
            end
        end
    end
    
    snapshot.configuredSlots = configuredCount
    snapshot.capturedSlots = capturedCount
    
    return snapshot
end

--------------------------------------------------------------------------------
-- Get Snapshot (without saving)
--------------------------------------------------------------------------------

function Capture:GetSnapshot()
    if ActionBar:IsFullyBlocked() then
        return nil
    end
    
    return CaptureAllSlots()
end

--------------------------------------------------------------------------------
-- Capture Execution
--------------------------------------------------------------------------------

local CONTEXT_MESSAGES = {
    ["vehicle"] = "in vehicle",
    ["possess"] = "mind controlling",
}

local function GetFriendlyContext(context)
    if CONTEXT_MESSAGES[context] then
        return CONTEXT_MESSAGES[context]
    end
    if context and context:find("^bonus:") then
        return "in stance or form"
    end
    return context
end

function Capture:Perform(allowPropagate, forceSave)
    if ActionBar:IsFullyBlocked() then
        local context = ActionBar:GetCaptureContext()
        local friendly = GetFriendlyContext(context)
        Utils:Print("Skipped save: " .. friendly)
        return false
    end

    local level = Utils:GetPlayerLevel()
    local highestSeen = EBB_CharDB and EBB_CharDB.highestSeenLevel or 0
    local isRerun = highestSeen > 0 and level < highestSeen

    -- During a rerun, sync bar changes to the master layout instead of
    -- saving. The bars are incomplete at lower levels so a full save
    -- would create redundant layouts.
    if isRerun and not forceSave then
        if allowPropagate and Profile:GetPropagateChanges() then
            local oldSnapshot = nil
            local candidate = Layout:Get(level)
            if candidate and candidate.playerLevel == level then
                oldSnapshot = candidate
            end

            local snapshot = CaptureAllSlots()
            if snapshot and oldSnapshot then
                local synced = Layout:SyncToMaster(oldSnapshot, snapshot)
                if synced > 0 then
                    Utils:Print(string.format(
                        "  %d slot(s) synced to master layout", synced))
                    local Explorer = EBB.Explorer
                    if Explorer then Explorer:Refresh() end
                end
                -- Save a session-only snapshot so the next debounce can
                -- diff against the updated state (not the stale one).
                Layout:SaveSession(level, snapshot)
            elseif snapshot then
                -- No old snapshot to diff against (first change after
                -- login/reload/death reset). Save as baseline so the
                -- next change can be synced.
                Layout:SaveSession(level, snapshot)
            end
        end
        return false
    end

    local snapshot = CaptureAllSlots()

    if not snapshot then
        Utils:PrintError("Failed to capture action bars")
        return false
    end

    local success = Layout:Save(level, snapshot)

    if success then
        Utils:Print(string.format("Level %d: %d slots saved", level, snapshot.configuredSlots or 0))
        -- Only the highest level layout is authoritative. Remove any
        -- permanent layouts below the current level so they do not
        -- accumulate during first-time leveling.
        Layout:PruneBelow(level)
    else
        Utils:PrintError("Failed to save layout")
    end

    return success
end

--------------------------------------------------------------------------------
-- Debounced Capture Scheduling
--------------------------------------------------------------------------------

function Capture:Schedule()
    if ActionBar:IsFullyBlocked() then
        return
    end
    
    local now = GetTime()
    lastDebounceTime = now
    pendingCapture = true
    
    C_Timer.After(Settings.DEBOUNCE_TIME, function()
        if pendingCapture and lastDebounceTime == now then
            pendingCapture = false
            self:Perform(true)
        end
    end)
end

--------------------------------------------------------------------------------
-- State Management
--------------------------------------------------------------------------------

function Capture:Cancel()
    pendingCapture = false
end

function Capture:IsPending()
    return pendingCapture
end
