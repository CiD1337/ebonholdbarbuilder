--[[----------------------------------------------------------------------------
    Per-level layout storage and retrieval within the active spec.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.Layout = {}

local Layout = EBB.Layout
local Utils = EBB.Utils
local Settings = EBB.Settings
local Profile = EBB.Profile

--------------------------------------------------------------------------------
-- Session Storage
--------------------------------------------------------------------------------

local sessionLayouts = {}

--------------------------------------------------------------------------------
-- Get layouts table for a spec
--------------------------------------------------------------------------------

local function GetSpecLayouts(specIndex)
    specIndex = specIndex or Profile:GetActive()
    
    local spec = EBB_CharDB.specs[specIndex]
    if not spec then
        return nil
    end
    
    if not spec.layouts then
        spec.layouts = {}
    end
    
    return spec.layouts
end

local function GetSessionLayouts(specIndex)
    specIndex = specIndex or Profile:GetActive()
    
    if not sessionLayouts[specIndex] then
        sessionLayouts[specIndex] = {}
    end
    
    return sessionLayouts[specIndex]
end

--------------------------------------------------------------------------------
-- Layout Operations
--------------------------------------------------------------------------------

function Layout:Save(level, snapshot, specIndex)
    if not snapshot then return false end
    
    level = level or Utils:GetPlayerLevel()
    specIndex = specIndex or Profile:GetActive()
    
    local layouts = GetSpecLayouts(specIndex)
    if not layouts then
        return false
    end
    
    layouts[level] = Utils:DeepCopy(snapshot)
    
    local session = GetSessionLayouts(specIndex)
    session[level] = Utils:DeepCopy(snapshot)
    
    return true
end

function Layout:SaveSession(level, snapshot, specIndex)
    if not snapshot then return false end

    level = level or Utils:GetPlayerLevel()
    specIndex = specIndex or Profile:GetActive()

    local session = GetSessionLayouts(specIndex)
    session[level] = Utils:DeepCopy(snapshot)

    return true
end

function Layout:Get(level, specIndex)
    level = level or Utils:GetPlayerLevel()
    specIndex = specIndex or Profile:GetActive()
    
    local layouts = GetSpecLayouts(specIndex)
    if layouts and layouts[level] then
        return layouts[level], "saved"
    end
    
    local session = GetSessionLayouts(specIndex)
    if session and session[level] then
        return session[level], "session"
    end
    
    return nil, nil
end

function Layout:Has(level, specIndex)
    level = level or Utils:GetPlayerLevel()
    specIndex = specIndex or Profile:GetActive()
    
    local layouts = GetSpecLayouts(specIndex)
    if layouts and layouts[level] then
        return true
    end
    
    local session = GetSessionLayouts(specIndex)
    if session and session[level] then
        return true
    end
    
    return false
end

function Layout:Delete(level, specIndex)
    level = level or Utils:GetPlayerLevel()
    specIndex = specIndex or Profile:GetActive()
    
    local layouts = GetSpecLayouts(specIndex)
    if layouts then
        layouts[level] = nil
    end
    
    local session = GetSessionLayouts(specIndex)
    if session then
        session[level] = nil
    end
end

function Layout:PruneBelow(keepLevel, specIndex)
    specIndex = specIndex or Profile:GetActive()

    local layouts = GetSpecLayouts(specIndex)
    if not layouts then return 0 end

    local pruned = 0
    for level in pairs(layouts) do
        if level < keepLevel then
            layouts[level] = nil
            pruned = pruned + 1
        end
    end

    return pruned
end

function Layout:ClearAll(specIndex)
    specIndex = specIndex or Profile:GetActive()
    
    local spec = EBB_CharDB.specs[specIndex]
    if spec then
        spec.layouts = {}
    end
    
    sessionLayouts[specIndex] = {}
end

--------------------------------------------------------------------------------
-- Layout Listing
--------------------------------------------------------------------------------

function Layout:GetSavedLevels(specIndex)
    specIndex = specIndex or Profile:GetActive()
    
    local levels = {}
    local layouts = GetSpecLayouts(specIndex)
    
    if layouts then
        for level in pairs(layouts) do
            table.insert(levels, level)
        end
    end
    
    table.sort(levels)
    return levels
end

function Layout:GetCount(specIndex)
    specIndex = specIndex or Profile:GetActive()
    
    local count = 0
    local layouts = GetSpecLayouts(specIndex)
    
    if layouts then
        for _ in pairs(layouts) do
            count = count + 1
        end
    end
    
    return count
end

--------------------------------------------------------------------------------
-- Session Management
--------------------------------------------------------------------------------

function Layout:ClearSessionData()
    sessionLayouts = {}
end

--------------------------------------------------------------------------------
-- Slot Matching Helpers
--------------------------------------------------------------------------------

local function SlotsMatch(a, b)
    if not a and not b then return true end
    if not a or not b then return false end
    if a.type ~= b.type then return false end
    if a.type == "empty" and b.type == "empty" then return true end
    if a.type == "spell" then
        return a.name == b.name
    elseif a.type == "item" then
        return a.id == b.id
    elseif a.type == "macro" then
        return a.name == b.name
    elseif a.type == "companion" then
        return a.id == b.id and (a.companionType or a.subType) == (b.companionType or b.subType)
    elseif a.type == "equipmentset" then
        return (a.setName or a.id) == (b.setName or b.id)
    end
    return false
end

local function IsEmptyOrNil(info)
    return not info or info.type == "empty"
end

--------------------------------------------------------------------------------
-- Master Sync
--
-- Detects user-initiated moves, swaps, and placements on a low-level bar
-- and applies them to the master layout (highest saved level).
--
-- Move:  Spell dragged from slot A to empty slot B
--        → Master swaps A ↔ B (B was likely occupied on the master).
-- Swap:  Spell dragged onto an occupied slot (WoW swaps them)
--        → Master swaps A ↔ B.
-- Place: New spell from spellbook/bag placed onto a slot
--        → Master sets the target slot; de-duplicates if spell existed
--          elsewhere in the master.
-- Clear: Slot emptied (spell/item dragged off bar)
--        → Ignored for spells and items to prevent accidental removal
--          of higher-level abilities the player has not re-learned.
--        → Synced for companions and macros, which are always available
--          regardless of level.
--------------------------------------------------------------------------------

local function CanSyncClear(oldInfo)
    if not oldInfo then return false end
    local t = oldInfo.type
    return t == "companion" or t == "macro" or t == "equipmentset"
end

function Layout:SyncToMaster(oldSnapshot, newSnapshot, specIndex)
    specIndex = specIndex or Profile:GetActive()

    if not oldSnapshot or not oldSnapshot.slots then return 0 end
    if not newSnapshot or not newSnapshot.slots then return 0 end

    -- Fetch master layout from the highest known level.
    local highestSeen = EBB_CharDB and EBB_CharDB.highestSeenLevel or 0
    if highestSeen <= 0 then return 0 end

    local masterLayout = self:Get(highestSeen, specIndex)
    if not masterLayout or not masterLayout.slots then return 0 end

    -- Collect changed slots. Empty new values are only included when the
    -- old slot held a companion, macro, or equipment set (always available
    -- at any level). Spell/item clears are ignored to prevent accidental
    -- removal of higher-level abilities not yet re-learned.
    local changes = {}
    for slot = 1, Settings.TOTAL_SLOTS do
        if Profile:IsSlotEnabled(slot, specIndex) then
            local oldInfo = oldSnapshot.slots[slot]
            local newInfo = newSnapshot.slots[slot]

            if not SlotsMatch(oldInfo, newInfo) then
                if not IsEmptyOrNil(newInfo) or CanSyncClear(oldInfo) then
                    changes[slot] = { old = oldInfo, new = newInfo }
                end
            end
        end
    end

    if not next(changes) then return 0 end

    local syncCount = 0

    for targetSlot, change in pairs(changes) do
        if IsEmptyOrNil(change.new) then
            -- Clear: companion, macro, or equipment set removed from bar.
            -- Directly clear the master slot.
            masterLayout.slots[targetSlot] = { type = "empty", slot = targetSlot }
            syncCount = syncCount + 1
        else
            -- Determine whether the spell in change.new was moved from another
            -- slot (source detection).  Two indicators:
            --   1. The old snapshot had this spell in a different slot, AND
            --   2. That slot is now either empty (move) or contains the spell
            --      that was previously in targetSlot (swap / WoW auto-swap).
            local sourceSlot = nil
            for slot = 1, Settings.TOTAL_SLOTS do
                if slot ~= targetSlot
                   and not IsEmptyOrNil(oldSnapshot.slots[slot])
                   and SlotsMatch(oldSnapshot.slots[slot], change.new) then
                    local nowInSource = newSnapshot.slots[slot]
                    if IsEmptyOrNil(nowInSource)
                       or SlotsMatch(nowInSource, change.old) then
                        sourceSlot = slot
                        break
                    end
                end
            end

            if sourceSlot then
                -- Move or Swap: swap the two slots in the master layout.
                local masterTarget = masterLayout.slots[targetSlot]
                local masterSource = masterLayout.slots[sourceSlot]
                masterLayout.slots[targetSlot] = masterSource
                    and Utils:DeepCopy(masterSource)
                    or { type = "empty", slot = targetSlot }
                masterLayout.slots[sourceSlot] = masterTarget
                    and Utils:DeepCopy(masterTarget)
                    or { type = "empty", slot = sourceSlot }
                syncCount = syncCount + 1
            else
                -- Placement from spellbook / bag / new binding.
                -- De-duplicate: if the spell already exists elsewhere in the
                -- master, clear that slot so the spell is not on the bar twice.
                for slot = 1, Settings.TOTAL_SLOTS do
                    if slot ~= targetSlot
                       and SlotsMatch(masterLayout.slots[slot], change.new) then
                        masterLayout.slots[slot] = { type = "empty", slot = slot }
                        break
                    end
                end
                masterLayout.slots[targetSlot] = Utils:DeepCopy(change.new)
                syncCount = syncCount + 1
            end
        end
    end

    if syncCount > 0 then
        -- Persist updated master to session storage as well.
        local session = GetSessionLayouts(specIndex)
        if session and session[highestSeen] then
            session[highestSeen] = Utils:DeepCopy(masterLayout)
        end
    end

    return syncCount
end
