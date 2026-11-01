----------------------------------------------------------------------
-- VoidGather — world-map button: filters + options in one click
-- (sits under VoidSweep's button if both are installed).
----------------------------------------------------------------------
local ADDON, VG = ...
VG.MapButton = {}

local function refresh() return MenuResponse and MenuResponse.Refresh end

local function generator(_, root)
    local cfg = VG:Config()
    local mapID = WorldMapFrame and WorldMapFrame:GetMapID()
    local counts, shared = VG:CountNodes(mapID)
    -- your skill and which nodes give it now (Skill.lua), for the professions you have
    local any = false
    for _, k in ipairs({ "herb", "mining" }) do
        local line = VG.Skill:Summary(k)
        if line then
            if not any then root:CreateTitle("Skill-ups"); any = true end
            root:CreateTitle(line)
            -- where to go: the best known spot, click for a waypoint
            local spot = VG.Skill:BestSpots(k, 1)[1]
            if spot then
                root:CreateButton("  Go: " .. VG.Skill:SpotText(spot), function() VG.Skill:GoBest(k) end)
            end
        end
    end
    if any then root:CreateDivider() end
    root:CreateTitle("VoidGather — show on map")
    for _, k in ipairs(VG.KIND_ORDER) do
        local def = VG.KINDS[k]
        local label = ("|T%s:14:14:0:0:64:64:6:58:6:58|t  %s (%d yours, %d shared)"):format(
            def.icon, def.label, counts[k] or 0, shared[k] or 0)
        root:CreateCheckbox(label,
            function() return cfg.show[k] ~= false end,
            function() cfg.show[k] = not (cfg.show[k] ~= false); VG:Refresh(); return refresh() end)
    end
    root:CreateDivider()
    root:CreateCheckbox("Only nodes that give skill",
        function() return cfg.skillOnly end,
        function() cfg.skillOnly = not cfg.skillOnly; VG:Refresh(); return refresh() end)
    root:CreateCheckbox("Only my professions",
        function() return cfg.onlyMine end,
        function() cfg.onlyMine = not cfg.onlyMine; VG:Refresh(); return refresh() end)
    root:CreateCheckbox("World map dots",
        function() return cfg.showWorld end,
        function() cfg.showWorld = not cfg.showWorld; VG:Refresh(); return refresh() end)
    root:CreateCheckbox("Minimap pins",
        function() return cfg.showMinimap end,
        function() cfg.showMinimap = not cfg.showMinimap; VG:Refresh(); return refresh() end)
    -- Minimap pin size / opacity: the pins redraw every frame, so a pick shows at once.
    local size = root:CreateButton("Minimap pin size")
    for _, o in ipairs({ { "Small", 9 }, { "Medium", 11 }, { "Large", 13 } }) do
        size:CreateRadio(o[1], function() return (cfg.mmPinSize or 11) == o[2] end,
            function() cfg.mmPinSize = o[2]; return refresh() end)
    end
    local alpha = root:CreateButton("Minimap pin opacity")
    for _, o in ipairs({ { "Faint (50%)", 0.5 }, { "See-through (70%)", 0.7 }, { "Solid (100%)", 1 } }) do
        alpha:CreateRadio(o[1], function() return (cfg.mmAlpha or 0.7) == o[2] end,
            function() cfg.mmAlpha = o[2]; return refresh() end)
    end
    root:CreateCheckbox("Auto-switch Find Minerals / Find Herbs",
        function() return cfg.autoTrack end,
        function() cfg.autoTrack = not cfg.autoTrack; VG.Tracking:Apply(); return refresh() end)
    root:CreateCheckbox("Share spots with other players",
        function() return cfg.share end,
        function() cfg.share = not cfg.share; VG.Sync:Apply(); return refresh() end)
    root:CreateDivider()
    root:CreateButton("Show this session's loot", function() VG.Gather:PrintSession() end)
end

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
    btn:SetScript("OnClick", function()
        if MenuUtil and MenuUtil.CreateContextMenu then MenuUtil.CreateContextMenu(btn, generator) end
    end)
    self.btn = btn
end
