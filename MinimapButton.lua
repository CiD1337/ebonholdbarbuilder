--[[----------------------------------------------------------------------------  
    Minimap button for quick access to the Explorer panel.
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.MinimapButton = {}

local MinimapButton = EBB.MinimapButton

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local BUTTON_RADIUS = 80          
local BUTTON_SIZE = 31            
local DEFAULT_ANGLE = 220         

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local button = nil
local isDragging = false

--------------------------------------------------------------------------------
-- Position Management
--------------------------------------------------------------------------------

local function GetSavedAngle()
    if EBB_CharDB and EBB_CharDB.minimapAngle then
        return EBB_CharDB.minimapAngle
    end
    return DEFAULT_ANGLE
end

local function SaveAngle(angle)
    if EBB_CharDB then
        EBB_CharDB.minimapAngle = angle
    end
end

local function UpdatePosition(angle)
    if not button then return end
    
    local radian = math.rad(angle)
    local x = math.cos(radian) * BUTTON_RADIUS
    local y = math.sin(radian) * BUTTON_RADIUS
    
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function GetAngleFromCursor()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    
    cx = cx / scale
    cy = cy / scale
    
    local dx = cx - mx
    local dy = cy - my
    
    return math.deg(math.atan2(dy, dx))
end

--------------------------------------------------------------------------------
-- Button Creation
--------------------------------------------------------------------------------

function MinimapButton:Create()
    if button then return button end
    
    button = CreateFrame("Button", "EBBMinimapButton", Minimap)
    button:SetWidth(BUTTON_SIZE)
    button:SetHeight(BUTTON_SIZE)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    
    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetWidth(53)
    overlay:SetHeight(53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT", 0, 0)
    
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetWidth(20)
    background:SetHeight(20)
    background:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    background:SetPoint("CENTER", -1, 1)
    background:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.Icon = background
    
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    
    button:SetScript("OnClick", function(self, btn)
        if btn == "LeftButton" and not isDragging then
            MinimapButton:OnLeftClick()
        elseif btn == "RightButton" then
            MinimapButton:OnRightClick()
        end
    end)
    
    button:SetScript("OnDragStart", function(self)
        isDragging = true
        self:SetScript("OnUpdate", function()
            local angle = GetAngleFromCursor()
            UpdatePosition(angle)
            SaveAngle(angle)
        end)
    end)
    
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        isDragging = false
    end)
    
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Ebonhold Bar Builder", 1, 1, 1)
        GameTooltip:AddLine("Left-click to open settings", 0.7, 0.7, 0.7)
        if EBB.FirstRun and EBB.FirstRun:CanAddonRun() then
            GameTooltip:AddLine("Right-click for options", 0.7, 0.7, 0.7)
        end
        GameTooltip:AddLine("Drag to move", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    
    button:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    UpdatePosition(GetSavedAngle())
    
    return button
end

--------------------------------------------------------------------------------
-- Context Menu
--------------------------------------------------------------------------------

local contextMenu = nil

local function InitializeContextMenu(self, level)
    if not level then return end
    
    local info = UIDropDownMenu_CreateInfo()
    
    info.text = "Disable"
    info.notCheckable = true
    info.colorCode = "|cFFFF4444"
    info.func = function()
        if EBB.FirstRun then
            EBB.FirstRun:ResetChoice()
            EBB.FirstRun:SetSessionDisabled(true)
            EBB.Utils:PrintForced("Disabled for this session")
        end
    end
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.disabled = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)
    
    info = UIDropDownMenu_CreateInfo()
    info.text = "Status"
    info.notCheckable = true
    info.func = function()
        if not EBB.Spec:IsConfirmed() then
            EBB.Utils:PrintError("Waiting for spec confirmation...")
            return
        end
        
        local specIndex = EBB.Profile:GetActive()
        local specName = EBB.Profile:GetSpecName(specIndex)
        local level = EBB.Utils:GetPlayerLevel()
        local layout, source = EBB.Layout:Get(level)
        
        EBB.Utils:Print(string.format("Spec: %s (#%d)", specName, specIndex))
        EBB.Utils:Print(string.format("Enabled slots: %d/%d", 
            EBB.Profile:GetEnabledSlotCount(), EBB.Settings.TOTAL_SLOTS))
        
        if layout then
            EBB.Utils:Print(string.format("Level %d: %d slots saved (%s)", 
                level, layout.configuredSlots or 0, source))
        else
            EBB.Utils:Print(string.format("Level %d: No layout saved", level))
        end
        
        EBB.Utils:Print(string.format("Total layouts: %d", EBB.Layout:GetCount()))
    end
    UIDropDownMenu_AddButton(info, level)
    
    info = UIDropDownMenu_CreateInfo()
    info.text = "Save"
    info.notCheckable = true
    info.func = function()
        if not EBB.Spec:IsConfirmed() then
            EBB.Utils:PrintError("Waiting for spec confirmation...")
            return
        end
        EBB.Capture:Perform(true, true)
    end
    UIDropDownMenu_AddButton(info, level)
    
    info = UIDropDownMenu_CreateInfo()
    info.text = "Restore"
    info.notCheckable = true
    info.func = function()
        if not EBB.Spec:IsConfirmed() then
            EBB.Utils:PrintError("Waiting for spec confirmation...")
            return
        end
        EBB.Restore:Perform()
    end
    UIDropDownMenu_AddButton(info, level)
    
    info = UIDropDownMenu_CreateInfo()
    info.disabled = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)
    
    info = UIDropDownMenu_CreateInfo()
    info.text = "Ask"
    info.checked = (EBB_CharDB and EBB_CharDB.askNextLogin) or false
    info.isNotRadio = true
    info.keepShownOnClick = true
    info.func = function()
        if EBB_CharDB then
            EBB_CharDB.askNextLogin = not EBB_CharDB.askNextLogin
        end
    end
    UIDropDownMenu_AddButton(info, level)
    
    info = UIDropDownMenu_CreateInfo()
    info.text = "Shush"
    info.checked = EBB.Utils:IsShushed()
    info.isNotRadio = true
    info.keepShownOnClick = true
    info.func = function()
        local newState = not EBB.Utils:IsShushed()
        EBB.Utils:SetShush(newState)
        EBB.Utils:PrintForced(newState and "Chat messages muted" or "Chat messages enabled")
    end
    UIDropDownMenu_AddButton(info, level)
end

local function CreateContextMenu()
    if contextMenu then return contextMenu end
    
    contextMenu = CreateFrame("Frame", "EBBMinimapContextMenu", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(contextMenu, InitializeContextMenu, "MENU")
    
    return contextMenu
end

--------------------------------------------------------------------------------
-- Click Handlers
--------------------------------------------------------------------------------

function MinimapButton:OnLeftClick()
    if EBB.FirstRun and not EBB.FirstRun:CanAddonRun() then
        EBB.FirstRun:Show()
        return
    end
    
    if EBB.Explorer then
        EBB.Explorer:Toggle()
    end
end

function MinimapButton:OnRightClick()
    if not EBB.FirstRun or not EBB.FirstRun:CanAddonRun() then
        return
    end
    
    local menu = CreateContextMenu()
    ToggleDropDownMenu(1, nil, menu, "cursor", 0, 0)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function MinimapButton:Show()
    if button then
        button:Show()
    end
end

function MinimapButton:Hide()
    if button then
        button:Hide()
    end
end

function MinimapButton:IsVisible()
    return button and button:IsShown()
end

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        MinimapButton:Create()
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end)
