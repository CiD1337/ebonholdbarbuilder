--[[----------------------------------------------------------------------------
    Class-specific action bar metadata and display mapping.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.ClassBars = {}

local ClassBars = EBB.ClassBars
local Settings 

--------------------------------------------------------------------------------
-- Class Data
--------------------------------------------------------------------------------

local CLASS_DATA = {
    WARRIOR = {
        alwaysInStance = true,
        casterBarName  = "Base Bar",
        stances = {
            [1] = { bar = 7,  name = "Battle Stance" },
            [2] = { bar = 8,  name = "Defensive Stance" },
            [3] = { bar = 9,  name = "Berserker Stance" },
        },
    },
    DRUID = {
        alwaysInStance = false,
        casterBarName  = "Caster Form",
        stances = {
            [1] = { bar = 7,  name = "Cat Form" },
            [3] = { bar = 9,  name = "Bear Form" },
            [4] = { bar = 10, name = "Moonkin Form" },
        },
    },
    ROGUE = {
        alwaysInStance = false,
        casterBarName  = "Normal",
        stances = {
            [1] = { bar = 7,  name = "Stealth" },
        },
    }
}

--------------------------------------------------------------------------------
-- Player Class Cache
--------------------------------------------------------------------------------

local playerClass = nil

function ClassBars:GetPlayerClass()
    if not playerClass then
        local _, classFile = UnitClass("player")
        playerClass = classFile
    end
    return playerClass
end

function ClassBars:GetClassData()
    return CLASS_DATA[self:GetPlayerClass()]
end

function ClassBars:HasStances()
    return self:GetClassData() ~= nil
end

--------------------------------------------------------------------------------
-- Label Helpers
--------------------------------------------------------------------------------

function ClassBars:GetStanceLabel(barIndex)
    local data = self:GetClassData()
    if not data then return nil end

    for _, stance in pairs(data.stances) do
        if stance.bar == barIndex then
            return stance.name
        end
    end
    return nil
end

function ClassBars:GetCasterBarLabel()
    local data = self:GetClassData()
    return data and data.casterBarName or nil
end

--------------------------------------------------------------------------------
-- Display Mapping
--------------------------------------------------------------------------------

function ClassBars:GetDisplayMapping(stanceIndex, isLiveView)
    if not Settings then Settings = EBB.Settings end

    local data = self:GetClassData()
    stanceIndex = stanceIndex or 0

    local mapping = {}

    --------------------------------------------------------------------
    -- No stance class (plain 1-10)
    --------------------------------------------------------------------
    if not data then
        for i = 1, Settings.TOTAL_BARS do
            mapping[i] = {
                dataBar  = i,
                label    = Settings:GetBarLabel(i),
                isActive = false,
                grayed   = false,
            }
        end
        return mapping
    end

    --------------------------------------------------------------------
    -- Build lookups
    --------------------------------------------------------------------
    local stanceByBar  = {}
    local barByStance  = {}
    for stanceIdx, stance in pairs(data.stances) do
        stanceByBar[stance.bar] = stance
        barByStance[stanceIdx]  = stance.bar
    end

    local activeBar = barByStance[stanceIndex]

    --------------------------------------------------------------------
    -- SAVED VIEW
    --------------------------------------------------------------------
    if not isLiveView then
        mapping[1] = {
            dataBar  = 1,
            label    = data.casterBarName or Settings:GetBarLabel(1),
            isActive = false,
            grayed   = false,
        }
        for i = 2, 6 do
            mapping[i] = {
                dataBar  = i,
                label    = Settings:GetBarLabel(i),
                isActive = false,
                grayed   = false,
            }
        end
        for i = 7, 10 do
            local stance = stanceByBar[i]
            mapping[i] = {
                dataBar  = i,
                label    = stance and stance.name or Settings:GetBarLabel(i),
                isActive = false,
                grayed   = false,
            }
        end
        return mapping
    end

    --------------------------------------------------------------------
    -- LIVE VIEW
    --------------------------------------------------------------------

    local row1Bar
    if activeBar then
        row1Bar = activeBar
        mapping[1] = {
            dataBar  = activeBar,
            label    = stanceByBar[activeBar].name,
            isActive = true,
            grayed   = false,
        }
    else
        row1Bar = 1
        mapping[1] = {
            dataBar  = 1,
            label    = data.casterBarName or Settings:GetBarLabel(1),
            isActive = true,
            grayed   = false,
        }
    end

    for i = 2, 6 do
        mapping[i] = {
            dataBar  = i,
            label    = Settings:GetBarLabel(i),
            isActive = false,
            grayed   = false,
        }
    end

    local lowerBars = {}
    for _, barIndex in ipairs({ 7, 8, 9, 10 }) do
        if barIndex ~= row1Bar then
            table.insert(lowerBars, barIndex)
        end
    end
    if row1Bar ~= 1 then
        table.insert(lowerBars, 1)
    end

    for i, barIndex in ipairs(lowerBars) do
        local displayRow = 6 + i
        local stance = stanceByBar[barIndex]
        local label, grayed

        if barIndex == 1 then
            label  = data.casterBarName or Settings:GetBarLabel(1)
            grayed = true
        elseif stance then
            label  = stance.name
            grayed = true
        else
            label  = Settings:GetBarLabel(barIndex)
            grayed = false
        end

        mapping[displayRow] = {
            dataBar  = barIndex,
            label    = label,
            isActive = false,
            grayed   = grayed,
        }
    end

    return mapping
end
