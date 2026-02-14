--[[----------------------------------------------------------------------------
    Restore coordination and slot placement.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.Restore = {}

local Restore = EBB.Restore
local Utils = EBB.Utils
local Settings = EBB.Settings
local ActionBar = EBB.ActionBar
local Profile = EBB.Profile
local Layout = EBB.Layout
local Capture = EBB.Capture

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local isRestoring = false
local pendingVerify = false
local verifyGeneration = 0

function Restore:IsInProgress()
    return isRestoring or pendingVerify
end

function Restore:ResetInProgress()
    isRestoring = false
    pendingVerify = false
    verifyGeneration = verifyGeneration + 1
end

--------------------------------------------------------------------------------
-- Spell Aliases
--------------------------------------------------------------------------------

local SPELL_ALIASES = {
    ["Attack"] = "Auto Attack",
    ["Shoot"] = "Auto Shot",
}

local function GetSpellbookName(tooltipName)
    if not tooltipName then return nil end
    return SPELL_ALIASES[tooltipName] or tooltipName
end

--------------------------------------------------------------------------------
-- Spellbook Search
--------------------------------------------------------------------------------

-- Iterates the entire spellbook and returns the last match for spellName.
-- In 3.3.5a the spellbook is ordered lowest rank first, so the last match
-- is always the highest learned rank.
local function FindSpellInSpellbook(spellName)
    if not spellName then return nil, nil end

    local numTabs = GetNumSpellTabs()
    local bestIndex, bestPassive = nil, nil

    for tabIndex = 1, numTabs do
        local _, _, offset, numSpells = GetSpellTabInfo(tabIndex)

        for spellIndex = offset + 1, offset + numSpells do
            local bookSpellName = GetSpellInfo(spellIndex, BOOKTYPE_SPELL)

            if bookSpellName and bookSpellName == spellName then
                bestIndex = spellIndex
                bestPassive = IsPassiveSpell(spellIndex, BOOKTYPE_SPELL)
            end
        end
    end

    return bestIndex, bestPassive
end

--------------------------------------------------------------------------------
-- Placement Functions
--------------------------------------------------------------------------------

local function PlaceSpell(slot, info)
    local spellName = info.name

    if not spellName then
        return false, "no name"
    end

    local currentName = ActionBar:GetSpellNameFromTooltip(slot)
    if currentName and currentName == spellName then
        return true, nil
    end

    local spellbookName = GetSpellbookName(spellName)
    local spellbookIndex, isPassive = FindSpellInSpellbook(spellbookName)

    if not spellbookIndex and spellbookName ~= spellName then
        spellbookIndex, isPassive = FindSpellInSpellbook(spellName)
    end
    
    if spellbookIndex then
        if isPassive then
            return false, "passive"
        end
        
        PickupSpell(spellbookIndex, BOOKTYPE_SPELL)
        if CursorHasSpell() then
            PlaceAction(slot)
            ClearCursor()
            return true, nil
        end
        ClearCursor()
    end
    
    return false, "not found"
end

local function IsItemInBags(itemID)
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        for bagSlot = 1, numSlots do
            local link = GetContainerItemLink(bag, bagSlot)
            if link then
                local id = tonumber(link:match("item:(%d+)"))
                if id == itemID then
                    return true
                end
            end
        end
    end
    return false
end

local function PlaceItem(slot, info)
    local itemID = info.id
    if not itemID then return false, "no id" end

    -- Check if the correct item is already in this slot
    local currentType, currentID = GetActionInfo(slot)
    if currentType == "item" and currentID == itemID then
        return true, nil
    end

    -- Verify the item is in bags before attempting placement
    if not IsItemInBags(itemID) then
        return false, "not in bags"
    end

    PickupItem(itemID)
    if CursorHasItem() then
        PlaceAction(slot)
        ClearCursor()
        return true, nil
    end
    ClearCursor()
    return false, "not found"
end

local function PlaceMacro(slot, info)
    local macroName = info.name
    if not macroName then return false, "no name" end
    
    local macroIndex = GetMacroIndexByName(macroName)
    if macroIndex and macroIndex > 0 then
        PickupMacro(macroIndex)
        PlaceAction(slot)
        ClearCursor()
        return true, nil
    end
    return false, "not found"
end

local function PlaceCompanion(slot, info)
    local companionType = info.companionType or info.subType
    local companionName = info.name
    if not companionType or not companionName then return false, "missing info" end

    local numCompanions = GetNumCompanions(companionType)
    for i = 1, numCompanions do
        local _, name = GetCompanionInfo(companionType, i)
        if name == companionName then
            PickupCompanion(companionType, i)
            PlaceAction(slot)
            ClearCursor()
            return true, nil
        end
    end
    return false, "not found"
end

local function PlaceEquipmentSet(slot, info)
    local setName = info.setName or info.id
    if not setName then return false, "no name" end
    
    local numSets = GetNumEquipmentSets()
    for i = 1, numSets do
        local name = GetEquipmentSetInfo(i)
        if name == setName then
            PickupEquipmentSetByName(setName)
            PlaceAction(slot)
            ClearCursor()
            return true, nil
        end
    end
    return false, "not found"
end

--------------------------------------------------------------------------------
-- Single Slot Restore
--------------------------------------------------------------------------------

local function RestoreSlot(slot, info, forceClear)
    if not info then
        ActionBar:ClearSlot(slot)
        return true, nil
    end

    local actionType = info.type

    if actionType == "empty" then
        ActionBar:ClearSlot(slot)
        return true, nil
    end

    -- For items, try placement without clearing first.
    -- This prevents destroying a working item slot (e.g. Hearthstone)
    -- when the item cannot be re-placed from bags.
    if actionType == "item" then
        local success, reason = PlaceItem(slot, info)
        if not success and reason == "not in bags" then
            return false, reason
        end
        return success, reason
    end

    -- For spells, verify the spell exists in the spellbook before
    -- clearing. During a rerun with forceClear, clear the slot anyway
    -- so server-placed spells are removed. Without forceClear, keep
    -- whatever is in the slot (talent preservation).
    if actionType == "spell" then
        local success, reason = PlaceSpell(slot, info)
        if not success and reason == "not found" then
            if forceClear then
                ActionBar:ClearSlot(slot)
                return true, nil
            end
            return false, reason
        end
        return success, reason
    end

    -- Remaining types: clear slot first, then place
    ActionBar:ClearSlot(slot)

    local success, reason

    if actionType == "macro" then
        success, reason = PlaceMacro(slot, info)
    elseif actionType == "companion" then
        success, reason = PlaceCompanion(slot, info)
    elseif actionType == "equipmentset" then
        success, reason = PlaceEquipmentSet(slot, info)
    else
        return false, "unknown type"
    end
    
    ClearCursor()
    return success, reason
end

--------------------------------------------------------------------------------
-- Full Restore
--------------------------------------------------------------------------------

function Restore:FromSnapshot(snapshot, forceClear)
    if not snapshot or not snapshot.slots then
        return 0, {}
    end

    local restored = 0
    local failures = {}

    for slot = 1, Settings.TOTAL_SLOTS do
        if Profile:IsSlotEnabled(slot) then
            local slotInfo = snapshot.slots[slot]

            if slotInfo then
                local success, reason = RestoreSlot(slot, slotInfo, forceClear)
                
                if success then
                    if slotInfo.type ~= "empty" then
                        restored = restored + 1
                    end
                else
                    table.insert(failures, {
                        slot = slot,
                        type = slotInfo.type,
                        name = slotInfo.name or slotInfo.setName or ("id:" .. tostring(slotInfo.id)),
                        reason = reason or "unknown",
                    })
                end
            else
                ActionBar:ClearSlot(slot)
            end
        end
    end
    
    return restored, failures
end

--------------------------------------------------------------------------------
-- Restore Execution
--------------------------------------------------------------------------------

local function SummarizeFailures(failures)
    local byReason = {}
    for _, f in ipairs(failures) do
        local reason = f.reason
        if not byReason[reason] then
            byReason[reason] = { count = 0, examples = {} }
        end
        byReason[reason].count = byReason[reason].count + 1
        if #byReason[reason].examples < 2 then
            table.insert(byReason[reason].examples, f.name or "unknown")
        end
    end
    return byReason
end

local REASON_LABELS = {
    ["not found"] = "not in spellbook/bags (slot kept)",
    ["not in bags"] = "item not in inventory (slot kept)",
    ["passive"] = "passive (can't place)",
    ["no name"] = "missing name data",
    ["no id"] = "missing ID data",
    ["missing info"] = "incomplete data",
    ["unknown type"] = "unsupported action type",
}

local function GetReasonLabel(reason)
    return REASON_LABELS[reason] or reason
end

--------------------------------------------------------------------------------
-- Slot Comparison (for verify pass)
--------------------------------------------------------------------------------

local function SlotMatchesCurrent(slot, expectedInfo)
    if not expectedInfo or expectedInfo.type == "empty" then
        local actionType = GetActionInfo(slot)
        return not actionType
    end

    local actionType, id, subType = GetActionInfo(slot)

    if not actionType then return false end
    if actionType ~= expectedInfo.type then return false end

    if actionType == "spell" then
        local currentName = ActionBar:GetSpellNameFromTooltip(slot)
        return currentName and currentName == expectedInfo.name
    elseif actionType == "item" then
        return id == expectedInfo.id
    elseif actionType == "macro" then
        local macroName = GetMacroInfo(id)
        return macroName == expectedInfo.name
    elseif actionType == "companion" then
        if (subType or "") ~= (expectedInfo.companionType or expectedInfo.subType or "") then
            return false
        end
        if expectedInfo.name then
            local _, name = GetCompanionInfo(subType, id)
            return name and name == expectedInfo.name
        end
        return id == expectedInfo.id
    elseif actionType == "equipmentset" then
        return id == (expectedInfo.setName or expectedInfo.id)
    end

    return false
end

--------------------------------------------------------------------------------
-- Post-Restore Verify Pass
--------------------------------------------------------------------------------

local function VerifyAndFix(snapshot, attempt, forceClear, generation)
    if not snapshot or not snapshot.slots then return end
    if generation ~= verifyGeneration then return end

    local fixed = 0

    isRestoring = true

    for slot = 1, Settings.TOTAL_SLOTS do
        if Profile:IsSlotEnabled(slot) then
            local expectedInfo = snapshot.slots[slot]
            if expectedInfo and not SlotMatchesCurrent(slot, expectedInfo) then
                local success = RestoreSlot(slot, expectedInfo, forceClear)
                if success then
                    fixed = fixed + 1
                end
            end
        end
    end

    isRestoring = false

    if fixed > 0 then
        Utils:Print(string.format("  Verify pass %d: %d slot(s) corrected", attempt, fixed))
    end

    -- Schedule another verify if we fixed something and have retries left
    if fixed > 0 and attempt < Settings.VERIFY_RETRIES then
        C_Timer.After(Settings.VERIFY_DELAY, function()
            VerifyAndFix(snapshot, attempt + 1, forceClear, generation)
        end)
    else
        -- Save a session snapshot now that all verify passes are done,
        -- so Master Sync has an accurate baseline that reflects forceClear
        -- and all verify corrections.
        if forceClear then
            local freshSnapshot = Capture:GetSnapshot()
            if freshSnapshot then
                Layout:SaveSession(Utils:GetPlayerLevel(), freshSnapshot)
            end
        end
        pendingVerify = false
    end
end

--------------------------------------------------------------------------------
-- Restore Execution
--------------------------------------------------------------------------------

function Restore:Perform(level, forceClear)
    level = level or Utils:GetPlayerLevel()

    local layout, source = Layout:Get(level)

    -- During a rerun, always use the master layout. Session snapshots
    -- at the current level are only diff baselines for Master Sync,
    -- not authoritative layouts to restore from. Enable forceClear so
    -- server-placed spells that don't belong in the master layout are
    -- removed instead of kept.
    local highest = EBB_CharDB.highestSeenLevel or 0
    if highest > level then
        local masterLayout, masterSource = Layout:Get(highest)
        if masterLayout then
            layout = masterLayout
            source = masterSource
            forceClear = true
        end
    end

    if not layout then
        Utils:Print(string.format("Level %d: No saved layout found", level))
        return false
    end

    isRestoring = true

    local ok, restored, failures = pcall(function()
        return self:FromSnapshot(layout, forceClear)
    end)

    isRestoring = false

    if not ok then
        Utils:PrintError("Restore error: " .. tostring(restored))
        return false
    end

    local failCount = #failures

    if failCount == 0 then
        Utils:Print(string.format("Level %d: %d slots restored", level, restored))
    else
        Utils:Print(string.format("Level %d: %d slots restored, %d failed", level, restored, failCount))
    end

    if failCount > 0 then
        local byReason = SummarizeFailures(failures)
        for reason, data in pairs(byReason) do
            local label = GetReasonLabel(reason)
            local examples = table.concat(data.examples, ", ")
            if data.count > #data.examples then
                examples = examples .. ", ..."
            end
            Utils:Print(string.format("  %d %s: %s", data.count, label, examples))
        end
    end

    -- Run an immediate verify pass to catch server-injected spells.
    -- The server places new spells on the main bar after a level-up,
    -- overwriting what the addon just restored. The first pass runs
    -- immediately; if it finds corrections, a second pass is scheduled
    -- after VERIFY_DELAY as a safety net (e.g. brief combat edge cases).
    -- Each Perform() bumps the generation so only the latest verify runs.
    verifyGeneration = verifyGeneration + 1
    local gen = verifyGeneration
    pendingVerify = true
    VerifyAndFix(layout, 1, forceClear, gen)

    return true
end

--------------------------------------------------------------------------------
-- Clear All Slots
--------------------------------------------------------------------------------

function Restore:ClearAllSlots()
    isRestoring = true
    
    local ok, cleared = pcall(function()
        local count = 0
        for slot = 1, Settings.TOTAL_SLOTS do
            if Profile:IsSlotEnabled(slot) then
                ActionBar:ClearSlot(slot)
                count = count + 1
            end
        end
        return count
    end)
    
    isRestoring = false
    
    if not ok then
        Utils:PrintError("Clear error: " .. tostring(cleared))
        return 0
    end
    
    return cleared
end
