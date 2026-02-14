--[[----------------------------------------------------------------------------   
    Visual frame structure for the first-run opt-in dialog.
    Creates frames and visual elements only - behavior in FirstRun.lua
------------------------------------------------------------------------------]]

local ADDON_NAME, EBB = ...
EBB.UI = EBB.UI or {}

local UI = EBB.UI

--------------------------------------------------------------------------------
-- Layout Constants
--------------------------------------------------------------------------------

local LAYOUT = {
    FRAME_WIDTH = 300,
    FRAME_HEIGHT = 140,
    FRAME_PADDING = 15,
    
    BUTTON_WIDTH = 80,
    BUTTON_HEIGHT = 22,
    BUTTON_SPACING = 15,
    
    CHECKBOX_TOP_MARGIN = 10,
    
    BACKDROP_ALPHA = 1,
}

--------------------------------------------------------------------------------
-- Textures
--------------------------------------------------------------------------------

local BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
}

--------------------------------------------------------------------------------
-- Main Frame Creation
--------------------------------------------------------------------------------

function UI:CreateFirstRunFrame()
    if UI.FirstRunFrame then
        return UI.FirstRunFrame
    end
    
    local frame = CreateFrame("Frame", "EBBFirstRunFrame", UIParent)
    frame:SetWidth(LAYOUT.FRAME_WIDTH)
    frame:SetHeight(LAYOUT.FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0, 0, 0, LAYOUT.BACKDROP_ALPHA)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    
    tinsert(UISpecialFrames, "EBBFirstRunFrame")
    
    UI.FirstRunFrame = frame
    
    self:CreateFirstRunContent(frame)
    
    return frame
end

--------------------------------------------------------------------------------
-- Content Creation
--------------------------------------------------------------------------------

function UI:CreateFirstRunContent(parent)
    local yOffset = -LAYOUT.FRAME_PADDING
    
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, yOffset)
    title:SetText("Ebonhold Bar Builder")
    parent.Title = title
    
    yOffset = yOffset - title:GetStringHeight() - 12
    
    local question = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    question:SetPoint("TOP", 0, yOffset)
    question:SetText("Enable action bar saving for this character?")
    parent.Question = question
    
    yOffset = yOffset - question:GetStringHeight() - 15
    
    local buttonContainer = CreateFrame("Frame", nil, parent)
    buttonContainer:SetPoint("TOP", 0, yOffset)
    buttonContainer:SetWidth(LAYOUT.BUTTON_WIDTH * 2 + LAYOUT.BUTTON_SPACING)
    buttonContainer:SetHeight(LAYOUT.BUTTON_HEIGHT)
    
    local yesButton = CreateFrame("Button", "EBBFirstRunYesButton", buttonContainer, "UIPanelButtonTemplate")
    yesButton:SetWidth(LAYOUT.BUTTON_WIDTH)
    yesButton:SetHeight(LAYOUT.BUTTON_HEIGHT)
    yesButton:SetPoint("LEFT", 0, 0)
    yesButton:SetText("Yes")
    parent.YesButton = yesButton
    
    local noButton = CreateFrame("Button", "EBBFirstRunNoButton", buttonContainer, "UIPanelButtonTemplate")
    noButton:SetWidth(LAYOUT.BUTTON_WIDTH)
    noButton:SetHeight(LAYOUT.BUTTON_HEIGHT)
    noButton:SetPoint("LEFT", yesButton, "RIGHT", LAYOUT.BUTTON_SPACING, 0)
    noButton:SetText("No")
    parent.NoButton = noButton
    
    yOffset = yOffset - LAYOUT.BUTTON_HEIGHT - LAYOUT.CHECKBOX_TOP_MARGIN
    
    local checkbox = CreateFrame("CheckButton", "EBBFirstRunRememberCheckbox", parent, "UICheckButtonTemplate")
    checkbox:SetPoint("TOP", 0, yOffset)
    checkbox:SetWidth(24)
    checkbox:SetHeight(24)
    parent.RememberCheckbox = checkbox
    
    local checkboxLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    checkboxLabel:SetPoint("LEFT", checkbox, "RIGHT", 2, 0)
    checkboxLabel:SetText("Remember my choice")
    parent.RememberLabel = checkboxLabel
    
    local totalWidth = checkbox:GetWidth() + 2 + checkboxLabel:GetStringWidth()
    checkbox:SetPoint("TOP", -(totalWidth / 2) + (checkbox:GetWidth() / 2), yOffset)
end

--------------------------------------------------------------------------------
-- Get Layout Constants
--------------------------------------------------------------------------------

function UI:GetFirstRunLayout()
    return LAYOUT
end
