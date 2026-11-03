----------------------------------------------------------------------
-- VoidGather — settings window (Void hub icon, world map button, /vg options)
--
-- Same look as the other Void addons: dark panel, cyan title bar, x to
-- close (Esc too), drag the title bar to move. Everything the old map menu
-- had: skill-ups with a Go button, which pins show (with counts for the
-- open map, else your zone), pin options, gathering helpers.
----------------------------------------------------------------------
local ADDON, VG = ...
VG.Settings = {}
local S = VG.Settings

local A = { 0, 0.78, 1 }   -- Void cyan
local FONT = "Fonts\\FRIZQT__.TTF"
local W = 380
local PAD = 14
local GOAL_ROWS = 5   -- the window doesn't scroll; the rest are in the earnings box tooltip
local panel

local function text(parent, size, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size or 11, flags or "")
    fs:SetJustifyH("LEFT")
    fs:SetTextColor(0.92, 0.92, 0.95)
    return fs
end

local function backdrop(f, r, g, b, a, borderAlpha)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(r, g, b, a)
    f:SetBackdropBorderColor(A[1], A[2], A[3], borderAlpha or 0.5)
end

local function tooltip(owner, title, line)
    owner:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        local l = type(line) == "function" and line() or line
        if l then GameTooltip:AddLine(l, 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
    end)
    owner:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

-- A small Void-style button.
local function button(parent, label, width, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width, 20)
    backdrop(b, 0.10, 0.12, 0.15, 1, 0.6)
    b.text = text(b, 10)
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.18, 0.22, 0.28, 1)
        self:SetBackdropBorderColor(A[1], A[2], A[3], 1)
    end)
    b:SetScript("OnLeave", function(self)
        if not self.selected then
            self:SetBackdropColor(0.10, 0.12, 0.15, 1)
            self:SetBackdropBorderColor(A[1], A[2], A[3], 0.6)
        end
    end)
    b:SetScript("OnClick", onClick)
    function b:SetSelected(on)
        self.selected = on
        self:SetBackdropColor(on and A[1] * 0.3 or 0.10, on and A[2] * 0.3 or 0.12, on and A[3] * 0.3 or 0.15, 1)
        self:SetBackdropBorderColor(A[1], A[2], A[3], on and 1 or 0.6)
        self.text:SetTextColor(on and 1 or 0.8, on and 1 or 0.8, on and 1 or 0.85)
    end
    return b
end

-- A checkbox row: cyan square when on.
local function checkbox(parent, label, get, toggle, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(18)
    local box = CreateFrame("Frame", nil, b, "BackdropTemplate")
    box:SetSize(12, 12)
    box:SetPoint("LEFT")
    backdrop(box, 0.10, 0.12, 0.15, 1, 0.7)
    local fill = box:CreateTexture(nil, "OVERLAY")
    fill:SetPoint("TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", -2, 2)
    fill:SetColorTexture(A[1], A[2], A[3], 1)
    b.label = text(b, 11)
    b.label:SetPoint("LEFT", box, "RIGHT", 8, 0)
    b.label:SetPoint("RIGHT")
    b.label:SetText(label)
    b:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 1, 1) end)
    b:SetScript("OnLeave", function(self) self.label:SetTextColor(0.92, 0.92, 0.95) end)
    b:SetScript("OnClick", function() toggle(); S:Refresh() end)
    if tip then tooltip(b, label, tip) end
    function b:Update() fill:SetShown(get() and true or false) end
    return b
end

-- "Label   [A] [B] [C]" — pick one.
local function choice(parent, label, options, get, set)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(20)
    local fs = text(row, 11)
    fs:SetPoint("LEFT")
    fs:SetText(label)
    row.buttons = {}
    local x = 0
    for i = #options, 1, -1 do
        local o = options[i]
        local b = button(row, o[1], 58, function() set(o[2]); S:Refresh() end)
        b:SetPoint("RIGHT", -x, 0)
        b.value = o[2]
        row.buttons[#row.buttons + 1] = b
        x = x + 62
    end
    function row:Update()
        local v = get()
        for _, b in ipairs(self.buttons) do b:SetSelected(b.value == v) end
    end
    return row
end

-- "Vede · Harandar Celebration   [-] 5 [+] [x]"
local function goalRow(parent)
    local G = VG.Goals
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(20)
    row:EnableMouse(true)
    local function bump(d) G:Set(row.key, row.name, (G:Get(row.key, row.name) or 0) + d) end
    row.del = button(row, "|cffff5555x|r", 20, function() G:Set(row.key, row.name, 0) end)
    row.del:SetPoint("RIGHT")
    row.plus = button(row, "+", 20, function() bump(1) end)
    row.plus:SetPoint("RIGHT", row.del, "LEFT", -8, 0)
    row.n = text(row, 11)
    row.n:SetWidth(26)
    row.n:SetJustifyH("CENTER")
    row.n:SetPoint("RIGHT", row.plus, "LEFT", -2, 0)
    row.minus = button(row, "-", 20, function() bump(-1) end)
    row.minus:SetPoint("RIGHT", row.n, "LEFT", -2, 0)
    row.fs = text(row, 11)
    row.fs:SetPoint("LEFT")
    row.fs:SetPoint("RIGHT", row.minus, "LEFT", -6, 0)
    row.fs:SetWordWrap(false)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(("%s x%d"):format(self.name, self.goal.n), 1, 1, 1)
        GameTooltip:AddLine("Crafted on " .. G:Who(self.key), 0.8, 0.8, 0.8)
        for _, m in ipairs(G:Mats(self.goal)) do
            local id = m.ids[1]
            local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or ("item " .. id)
            GameTooltip:AddDoubleLine(name,
                ("%d/%d"):format(m.have, m.need), 0.8, 0.8, 0.8, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function header(parent, str)
    local fs = text(parent, 11, "OUTLINE")
    fs:SetTextColor(A[1], A[2], A[3])
    fs:SetText(str)
    return fs
end

-- The map the counts are for: the open world map, else where you are.
local function countMap()
    if WorldMapFrame and WorldMapFrame:IsShown() then return WorldMapFrame:GetMapID() end
    return C_Map.GetBestMapForUnit("player")
end

local function build()
    local cfg = VG:Config()
    local f = CreateFrame("Frame", "VoidGatherSettings", UIParent, "BackdropTemplate")
    f:SetWidth(W)
    f:SetFrameStrata("DIALOG")   -- above the world map, which it opens from
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    backdrop(f, 0.08, 0.08, 0.10, 0.97, 0.4)
    local p = cfg.settingsPos
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("CENTER", 0, 80) end
    f:Hide()
    tinsert(UISpecialFrames, "VoidGatherSettings")   -- Esc closes it

    -- Title bar
    local tb = CreateFrame("Frame", nil, f)
    tb:SetPoint("TOPLEFT")
    tb:SetPoint("TOPRIGHT")
    tb:SetHeight(28)
    tb:EnableMouse(true)
    tb:RegisterForDrag("LeftButton")
    tb:SetScript("OnDragStart", function() f:StartMoving() end)
    tb:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local pt, _, rel, x, y = f:GetPoint()
        cfg.settingsPos = { pt, rel, x, y }
    end)
    local bg = tb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.06, 0.08, 1)
    local line = tb:CreateTexture(nil, "BORDER")
    line:SetPoint("BOTTOMLEFT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetHeight(1)
    line:SetColorTexture(A[1], A[2], A[3], 0.6)
    local icon = tb:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("LEFT", 10, 0)
    icon:SetTexture("Interface\\Icons\\Trade_Mining")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local title = text(tb, 13, "OUTLINE")
    title:SetTextColor(A[1], A[2], A[3])
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText("VoidGather - Gathering")
    local close = CreateFrame("Button", nil, tb)
    close:SetSize(22, 22)
    close:SetPoint("RIGHT", -6, 0)
    local x = text(close, 14, "OUTLINE")
    x:SetPoint("CENTER")
    x:SetText("|cffff5555x|r")
    close:SetScript("OnClick", function() f:Hide() end)
    tooltip(close, "Close")

    local w = {}
    f.w = w

    -- Skill-ups (only for the professions you have that still level)
    w.skillHead = header(f, "Skill-ups")
    w.skill = {}
    for i, k in ipairs({ "herb", "mining" }) do
        local row = CreateFrame("Frame", nil, f)
        row:SetHeight(20)
        row.kind = k
        row.fs = text(row, 11)
        row.fs:SetPoint("LEFT")
        row.fs:SetPoint("RIGHT", -64, 0)
        row.fs:SetWordWrap(false)   -- one line; the node list is on hover
        row:EnableMouse(true)
        tooltip(row, k == "herb" and "Herbalism skill-ups" or "Mining skill-ups", function()
            return (VG.Skill:Summary(k) or ""):gsub(" %- ", "\n", 1) .. "\n|cff8c8c9eOrange always gives a point, yellow usually.|r"
        end)
        row.go = button(row, "Go", 56, function() VG.Skill:GoBest(k) end)
        row.go:SetPoint("RIGHT")
        tooltip(row.go, "Waypoint to the best spot", function()
            local spot = VG.Skill:BestSpots(k, 1)[1]
            return spot and VG.Skill:SpotText(spot) or "No known spot that gives you skill yet."
        end)
        w.skill[i] = row
    end

    -- Show on map
    w.showHead = header(f, "Show on map")
    w.kinds = {}
    for _, k in ipairs(VG.KIND_ORDER) do
        local cb = checkbox(f, VG.KINDS[k].label,
            function() return cfg.show[k] ~= false end,
            function() cfg.show[k] = not (cfg.show[k] ~= false); VG:Refresh() end)
        cb.kind = k
        w.kinds[#w.kinds + 1] = cb
    end

    -- Pins
    w.pinHead = header(f, "Pins")
    w.pinChecks = {
        checkbox(f, "Only nodes that give skill",
            function() return cfg.skillOnly end,
            function() cfg.skillOnly = not cfg.skillOnly; VG:Refresh() end,
            "Hide herb and ore pins that no longer give you skill (grey)."),
        checkbox(f, "Only my professions",
            function() return cfg.onlyMine end,
            function() cfg.onlyMine = not cfg.onlyMine; VG:Refresh() end,
            "Hide spots for professions you don't have. Lumber always shows."),
        checkbox(f, "World map dots",
            function() return cfg.showWorld end,
            function() cfg.showWorld = not cfg.showWorld; VG:Refresh() end),
        checkbox(f, "Minimap pins",
            function() return cfg.showMinimap end,
            function() cfg.showMinimap = not cfg.showMinimap; VG:Refresh() end),
    }
    w.size = choice(f, "Minimap pin size", { { "Small", 9 }, { "Medium", 11 }, { "Large", 13 } },
        function() return cfg.mmPinSize or 11 end, function(v) cfg.mmPinSize = v end)
    w.alpha = choice(f, "Minimap pin opacity", { { "50%", 0.5 }, { "70%", 0.7 }, { "100%", 1 } },
        function() return cfg.mmAlpha or 0.7 end, function(v) cfg.mmAlpha = v end)

    -- Gathering helpers
    w.helpHead = header(f, "Gathering")
    w.helpChecks = {
        checkbox(f, "Auto-switch Find Minerals / Find Herbs",
            function() return cfg.autoTrack end,
            function() cfg.autoTrack = not cfg.autoTrack; VG.Tracking:Apply() end,
            "For miner-herbalists: flips between the two trackers while you move, out of combat."),
        checkbox(f, "Share spots with other players",
            function() return cfg.share end,
            function() cfg.share = not cfg.share; VG.Sync:Apply() end,
            "Send your new spots to other VoidGather players and receive theirs."),
        checkbox(f, "Earnings box on screen (drag to move)",
            function() return cfg.showEarn end,
            function() VG.Earn:SetShown(not cfg.showEarn) end,
            "What your gathering is worth this session and per hour. Hover it for details."),
        checkbox(f, "Players-here box (drag to move)",
            function() return VoidPresence:IsShown() end,
            function() VoidPresence:SetShown(not VoidPresence:IsShown()) end,
            "How many other players in your zone run VoidGather (and VoidSweep, if you have it), counted over the sharing channel."),
        checkbox(f, "Item tooltips: what materials are worth crafted",
            function() return cfg.craftTips end,
            function() cfg.craftTips = not cfg.craftTips end,
            "Hover a herb, ore, leather or cooking ingredient: its sell price, and what each piece is worth turned into a potion, mulch, ingot and so on. Uses your auction prices."),
    }
    -- Crafting goals (Goals.lua): rows are made as goals appear
    w.goalHead = header(f, "Crafting goals")
    w.goalRows = {}
    w.goalHint = text(f, 10)
    w.goalHint:SetTextColor(0.55, 0.55, 0.62)
    w.goalHint:SetWidth(W - 2 * PAD - 4)
    w.goalHint:SetWordWrap(true)
    w.goalAdd = button(f, "Add a goal", 150, function(self) VG.Goals:AddMenu(self) end)
    tooltip(w.goalAdd, "Add a crafting goal", "Pick a recipe one of your characters knows and how many to craft. "
        .. "The gathered materials still missing show in the earnings box on every character.")

    -- Gathering HUD (HUD.lua)
    w.hudHead = header(f, "Gathering HUD")
    w.hudChecks = {
        checkbox(f, "Show the HUD",
            function() return cfg.hud end,
            function() VG.HUD:SetShown(not cfg.hud) end,
            "Your minimap, big and see-through in front of you and turning with you: the game's own herb and ore dots (Find Herbs / Find Minerals) plus VoidGather's spots. Its buttons wait where the minimap was. Also on a key binding (Options > Keybindings > AddOns > VoidGather) and /vg hud. Switches outside combat."),
    }
    w.hudSize = choice(f, "Size", { { "Small", 0.5 }, { "Medium", 0.7 }, { "Large", 0.9 } },
        function() return cfg.hudSize or 0.7 end, function(v) cfg.hudSize = v; VG.HUD:Refresh() end)
    w.hudTerrain = choice(f, "Map underneath", { { "Off", 0 }, { "Faint", 0.15 }, { "Light", 0.35 } },
        function() return cfg.hudTerrain or 0 end, function(v) cfg.hudTerrain = v; VG.HUD:Refresh() end)
    w.hudMove = button(f, "Move HUD", 150, function() VG.HUD:ToggleMove(); S:Refresh() end)
    tooltip(w.hudMove, "Move the HUD", "Unlocks it so you can drag it; click again to lock. Locked, it lets your clicks through.")

    w.loot = button(f, "Session loot (chat)", 150, function() VG.Gather:PrintSession() end)
    w.zones = button(f, "Best zones (chat)", 150, function() VG.Earn:PrintZones() end)
    tooltip(w.zones, "Best gold per hour by zone", "From all your sessions, zones with 10+ minutes of gathering.")
    return f
end

-- Lay the window out top to bottom (the skill-up block comes and goes).
function S:Refresh()
    if not (panel and panel:IsShown()) then return end
    local f, w = panel, panel.w
    local cfg = VG:Config()
    local y = -28 - 12
    local function place(region, height, indent)
        region:ClearAllPoints()
        region:SetPoint("TOPLEFT", PAD + (indent or 0), y)
        if region:GetObjectType() ~= "FontString" then   -- rows stretch to the right edge
            region:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
        end
        region:Show()
        y = y - height
    end

    local anySkill = false
    for _, row in ipairs(w.skill) do
        local line, short = VG.Skill:Summary(row.kind)
        if line then
            if not anySkill then place(w.skillHead, 18); anySkill = true end
            row.fs:SetText(short or line)
            row.go:SetShown(VG.Skill:BestSpots(row.kind, 1)[1] ~= nil)
            place(row, 22, 4)
        else
            row:Hide()
        end
    end
    if anySkill then y = y - 8 else w.skillHead:Hide() end

    local mapID = countMap()
    local counts, shared = VG:CountNodes(mapID)
    local info = mapID and C_Map.GetMapInfo(mapID)
    w.showHead:SetText("Show on map" .. (info and ("|cff8c8c9e  ·  " .. info.name .. "|r") or ""))
    place(w.showHead, 18)
    for _, cb in ipairs(w.kinds) do
        local def = VG.KINDS[cb.kind]
        cb.label:SetText(("|T%s:14:14:0:0:64:64:6:58:6:58|t  %s  |cff8c8c9e%d yours, %d shared|r"):format(
            def.icon, def.label, counts[cb.kind] or 0, shared[cb.kind] or 0))
        cb:Update()
        place(cb, 20, 4)
    end
    y = y - 8

    place(w.pinHead, 18)
    for _, cb in ipairs(w.pinChecks) do cb:Update(); place(cb, 20, 4) end
    w.size:Update(); place(w.size, 24, 4)
    w.alpha:Update(); place(w.alpha, 24, 4)
    y = y - 8

    place(w.helpHead, 18)
    for _, cb in ipairs(w.helpChecks) do cb:Update(); place(cb, 20, 4) end
    y = y - 8

    place(w.goalHead, 18)
    local goals = VG.Goals:List()
    local more = #goals - GOAL_ROWS
    while #goals > GOAL_ROWS do table.remove(goals) end
    for i, g in ipairs(goals) do
        local row = w.goalRows[i] or goalRow(f)
        w.goalRows[i] = row
        row.key, row.name, row.goal = g.key, g.name, g
        row.fs:SetText(("%s  |cff8c8c9e·|r  %s"):format(VG.Goals:Who(g.key), g.name))
        row.n:SetText(g.n)
        place(row, 22, 4)
    end
    for i = #goals + 1, #w.goalRows do w.goalRows[i]:Hide() end
    local hint
    if more > 0 then
        hint = ("…and %d more: hover the earnings box for all of them."):format(more)
    elseif not next(VoidGatherDB.crafters or {}) then
        hint = "Open a profession window once on each of your characters; VoidGather then knows what they craft."
    elseif #goals == 0 then
        hint = "Pick something one of your characters crafts. Its gathered materials still missing show in the earnings box."
    end
    if hint and not cfg.showEarn then hint = hint .. " Turn the earnings box on above." end
    if not hint and not cfg.showEarn then hint = "The missing materials show in the earnings box: turn it on above." end
    if hint then
        w.goalHint:SetText(hint)
        place(w.goalHint, w.goalHint:GetStringHeight() + 6, 4)
    else
        w.goalHint:Hide()
    end
    w.goalAdd:ClearAllPoints()
    w.goalAdd:SetPoint("TOPLEFT", PAD + 4, y)
    w.goalAdd:Show()
    y = y - 22 - 8

    place(w.hudHead, 18)
    for _, cb in ipairs(w.hudChecks) do cb:Update(); place(cb, 20, 4) end
    w.hudSize:Update(); place(w.hudSize, 24, 4)
    w.hudTerrain:Update(); place(w.hudTerrain, 24, 4)
    w.hudMove.text:SetText(VG.HUD:IsMoving() and "Lock HUD" or "Move HUD")
    w.hudMove:ClearAllPoints()
    w.hudMove:SetPoint("TOPLEFT", PAD + 4, y)
    w.hudMove:Show()
    y = y - 22 - 10

    w.loot:ClearAllPoints()
    w.loot:SetPoint("TOPLEFT", PAD, y)
    w.zones:ClearAllPoints()
    w.zones:SetPoint("TOPRIGHT", -PAD, y)
    y = y - 20 - PAD
    f:SetHeight(-y)
end

function S:Toggle()
    panel = panel or build()
    if panel:IsShown() then
        panel:Hide()
    else
        panel:Show()
        panel:Raise()
        self:Refresh()
    end
end
