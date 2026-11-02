----------------------------------------------------------------------
-- VoidGather — world-map button and Void hub icon: both open the settings
-- window (Settings.lua). The map button sits under VoidSweep's if both are
-- installed.
----------------------------------------------------------------------
local ADDON, VG = ...
VG.MapButton = {}

-- Void hub icon (VoidHubBundle.lua): left-click opens the settings window,
-- right-click turns the earnings box on or off.
VoidHubLaunchers = VoidHubLaunchers or {}
VoidHubLaunchers.VoidGather = {
    icon = "Interface\\Icons\\Trade_Mining",
    onClick = function(button)
        if button == "RightButton" then
            VG.Earn:SetShown(not VG:Config().showEarn)
        else
            VG.Settings:Toggle()
        end
    end,
}

function VG.MapButton:Init()
    if self.btn then return end
    local canvas = WorldMapFrame and WorldMapFrame.GetCanvasContainer and WorldMapFrame:GetCanvasContainer()
    if not canvas then return end
    local btn = CreateFrame("Button", "VoidGatherMapButton", canvas)
    btn:SetSize(31, 31)
    -- Sit under VoidSweep's button when it's installed. VoidSweep loads after
    -- us (alphabetical), so its button may not exist yet at login: re-check
    -- every time the map opens.
    local function place()
        btn:ClearAllPoints()
        btn:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -4, _G.VoidSweepMapButton and -106 or -72)
    end
    place()
    WorldMapFrame:HookScript("OnShow", place)
    btn:SetFrameStrata("HIGH")
    btn:SetFrameLevel(canvas:GetFrameLevel() + 500)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(24, 24); bg:SetPoint("CENTER")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER"); icon:SetSize(20, 20)
    icon:SetTexture("Interface\\Icons\\Trade_Mining")
    icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    -- ring sits in the top-left of its 64x64 file: TOPLEFT at 53x53 centers it on 31x31
    local ring = btn:CreateTexture(nil, "OVERLAY")
    ring:SetSize(53, 53); ring:SetPoint("TOPLEFT")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    btn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
        GameTooltip:SetText("VoidGather")
        GameTooltip:AddLine("Gathering spots — yours and other players'.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btn:SetScript("OnClick", function() VG.Settings:Toggle() end)
    self.btn = btn
end
