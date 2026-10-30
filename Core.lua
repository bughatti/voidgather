----------------------------------------------------------------------
-- VoidGather — Core
--
-- Remembers every mining / herb / skinning node you gather and shows the
-- spots on the world map + minimap, so routes build themselves as you play.
-- Works on retail (12.x) and WoW Forever (TOC 16001): both run the modern
-- client, and everything here reads only the PLAYER's own casts, position
-- and loot — none of which are secret values.
--
-- Files:
--   Core.lua      namespace, kinds, config, node database, slash
--   Gather.lua    detects gathers (UNIT_SPELLCAST_SENT/SUCCEEDED + loot)
--   Sync.lua      shares spots with other players (hidden VoidGatherNet channel)
--   Waypoint.lua  click a pin -> Blizzard waypoint + arrow
--   Pins.lua/xml  world-map pins (MapCanvas data provider)
--   Minimap.lua   minimap pins
--   Tracking.lua  optional auto-switch Find Minerals <-> Find Herbs
--   MapButton.lua filter / options menu on the world map
----------------------------------------------------------------------
local ADDON, VG = ...
_G.VoidGather = VG

VG.PREFIX = "|cff00c7ffVoidGather|r"

-- spells = base profession spell IDs; their LOCALIZED names are matched at
-- runtime, so every expansion's own "Mining"/"Herb Gathering" cast counts
-- (retail uses many spell IDs, Forever/Classic use these base ones).
VG.KINDS = {
    mining = { label = "Mining",       icon = "Interface\\Icons\\Trade_Mining",
               color = { 0.30, 0.55, 1.00 }, spells = { 2575, 2576, 3564, 10248 },
               merge = 12 },
    herb   = { label = "Herbalism",    icon = "Interface\\Icons\\Trade_Herbalism",
               color = { 0.30, 1.00, 0.30 }, spells = { 2366, 2368, 3570, 11993 },
               merge = 12 },
    skin   = { label = "Skinning",     icon = "Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
               color = { 0.95, 0.95, 0.95 }, spells = { 8613, 8617, 8618, 10768 },
               merge = 45 },   -- corpses: cluster into "skinnable mobs here" areas
    -- Midnight housing lumber (no profession needed). Woodchopping verified in game 2026-10-06
    -- on "Thalassian Lumber"; the icon comes from the spell when the client has it.
    lumber = { label = "Lumber",       icon = "Interface\\Icons\\INV_Misc_QuestionMark",
               color = { 0.15, 0.90, 0.80 }, spells = { 1239682 },
               merge = 12 },
}
VG.KIND_ORDER = { "mining", "herb", "skin", "lumber" }
do
    local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(1239682)
    if tex then VG.KINDS.lumber.icon = tex end
end

VG.defaults = {
    show = { mining = true, herb = true, skin = true, lumber = true },
    showMinimap = true,
    autoTrack = false,      -- cycle Find Minerals / Find Herbs (see Tracking.lua)
    autoTrackSecs = 3,
    pinSize = 16,
    share = true,           -- send/receive spots over VoidGatherNet (see Sync.lua)
    showWorld = true,       -- dots on the world map (minimap pins are separate)
    onlyMine = true,        -- hide kinds you can't gather (lumber always shows)
}

function VG:Config()
    VoidGatherDB = VoidGatherDB or {}
    local db = VoidGatherDB
    db.config = db.config or CopyTable(VG.defaults)
    local cfg = db.config
    for k, v in pairs(VG.defaults) do
        if cfg[k] == nil then cfg[k] = (type(v) == "table") and CopyTable(v) or v end
    end
    for k, v in pairs(VG.defaults.show) do
        if cfg.show[k] == nil then cfg.show[k] = v end
    end
    return cfg
end

----------------------------------------------------------------------
-- Node database: VoidGatherDB.nodes[mapID] = { {k,n,x,y,c,t}, ... }
--   k = kind, n = node name ("Copper Vein"), x/y = map coords (0-1),
--   c = times gathered, t = last gathered (time()).
----------------------------------------------------------------------
local function nodesFor(mapID)
    VoidGatherDB = VoidGatherDB or {}
    VoidGatherDB.nodes = VoidGatherDB.nodes or {}
    VoidGatherDB.nodes[mapID] = VoidGatherDB.nodes[mapID] or {}
    return VoidGatherDB.nodes[mapID]
end
VG.NodesFor = function(_, mapID) return nodesFor(mapID) end

-- Distance in yards between two points on a map (nil if the map has no size).
function VG:Yards(mapID, x1, y1, x2, y2)
    local w, h = C_Map.GetMapWorldSize(mapID)
    if not (w and h and w > 0 and h > 0) then return nil end
    local dx, dy = (x1 - x2) * w, (y1 - y2) * h
    return math.sqrt(dx * dx + dy * dy)
end

----------------------------------------------------------------------
-- Shared spots (from other players over VoidGatherNet, see Sync.lua):
-- VoidGatherDB.shared[mapID] = { {k,n,x,y,c,t,f,by}, ... }
--   c = how many different players reported it (stops counting at 5),
--   f = first reporter, by = set of reporters (dedupe).
-- Kept apart from your own spots; a shared spot is dropped the moment you
-- gather there yourself.
----------------------------------------------------------------------
local SHARED_CAP = 2000   -- per map; oldest dropped first
local CONFIRMED  = 5      -- stop counting reporters past this

local function sharedFor(mapID)
    VoidGatherDB = VoidGatherDB or {}
    VoidGatherDB.shared = VoidGatherDB.shared or {}
    VoidGatherDB.shared[mapID] = VoidGatherDB.shared[mapID] or {}
    return VoidGatherDB.shared[mapID]
end
VG.SharedFor = function(_, mapID) return sharedFor(mapID) end

local function sameSpot(mapID, r, kind, name, x, y)
    if r.k ~= kind then return false end
    local d = VG:Yards(mapID, r.x, r.y, x, y)
    if not (d and d <= VG.KINDS[kind].merge) then return false end
    if r.n == name or r.n == "?" or name == "?" then return true end
    -- shared names were cleaned/capped for the wire (Sync.CleanName); compare
    -- that form so long localized names still match your own full-name spots
    local clean = VG.Sync and VG.Sync.CleanName
    return clean ~= nil and clean(r.n) == clean(name)
end

-- Add a spot someone else reported. Returns true if anything changed.
function VG:AddShared(kind, name, mapID, x, y, sender)
    for _, r in ipairs(nodesFor(mapID)) do
        if sameSpot(mapID, r, kind, name, x, y) then return false end   -- you know it already
    end
    local list = sharedFor(mapID)
    for _, r in ipairs(list) do
        if sameSpot(mapID, r, kind, name, x, y) then
            if r.c >= CONFIRMED or r.by[sender] then return false end
            r.by[sender] = true
            r.c = r.c + 1
            r.t = time()
            if r.n == "?" and name ~= "?" then r.n = name end
            return true
        end
    end
    if #list >= SHARED_CAP then table.remove(list, 1) end
    list[#list + 1] = { k = kind, n = name, x = x, y = y, c = 1, t = time(), f = sender, by = { [sender] = true } }
    return true
end

local function dropShared(mapID, kind, name, x, y)
    local list = sharedFor(mapID)
    for i = #list, 1, -1 do
        if sameSpot(mapID, list[i], kind, name, x, y) then table.remove(list, i) end
    end
end

-- Add or merge a gathered node. Returns the record and whether it was new.
function VG:Record(kind, name, mapID, x, y)
    dropShared(mapID, kind, name, x, y)
    local list = nodesFor(mapID)
    local radius = VG.KINDS[kind].merge
    for _, r in ipairs(list) do
        -- "?" = name hidden at cast time (loot names it later): match either way
        if r.k == kind and (r.n == name or r.n == "?" or name == "?") then
            local d = VG:Yards(mapID, r.x, r.y, x, y)
            if d and d <= radius then
                if r.n == "?" and name ~= "?" then r.n = name end
                -- nudge toward the average so repeated gathers settle on the spot
                r.x = (r.x * r.c + x) / (r.c + 1)
                r.y = (r.y * r.c + y) / (r.c + 1)
                r.c = r.c + 1
                r.t = time()
                return r, false
            end
        end
    end
    local r = { k = kind, n = name, x = x, y = y, c = 1, t = time() }
    list[#list + 1] = r
    return r, true
end

-- counts[kind] = your spots, shared[kind] = spots from other players
function VG:CountNodes(mapID)
    local counts, shared = {}, {}
    if not mapID then return counts, shared end
    for _, r in ipairs(nodesFor(mapID)) do counts[r.k] = (counts[r.k] or 0) + 1 end
    for _, r in ipairs(sharedFor(mapID)) do shared[r.k] = (shared[r.k] or 0) + 1 end
    return counts, shared
end

----------------------------------------------------------------------
-- Which kinds you can gather. Retail: the profession skill lines
-- (GetProfessions); Forever/Classic: the base gather spells. Lumber needs
-- no profession. Cached for a few seconds (the minimap asks 10x/second).
----------------------------------------------------------------------
local SKILL_KIND = { [186] = "mining", [182] = "herb", [393] = "skin" }
local mineCache, mineTime

function VG:MyKinds()
    if mineCache and GetTime() - mineTime < 5 then return mineCache end
    local mine = { lumber = true }
    if GetProfessions and GetProfessionInfo then
        local p1, p2 = GetProfessions()
        for _, idx in ipairs({ p1 or 0, p2 or 0 }) do
            if idx ~= 0 then
                local skillLine = select(7, GetProfessionInfo(idx))
                if SKILL_KIND[skillLine] then mine[SKILL_KIND[skillLine]] = true end
            end
        end
    end
    if IsPlayerSpell then
        for kind, def in pairs(VG.KINDS) do
            for _, id in ipairs(def.spells) do
                if IsPlayerSpell(id) then mine[kind] = true end
            end
        end
    end
    mineCache, mineTime = mine, GetTime()
    return mine
end

-- Should pins of this kind draw? (category filter + "only my professions")
function VG:Visible(kind)
    local cfg = VG:Config()
    if cfg.show[kind] == false then return false end
    return not cfg.onlyMine or VG:MyKinds()[kind] == true
end

-- Your spots solid; shared spots faded until a second player confirms them.
function VG:PinAlpha(r, shared)
    if not shared then return 1 end
    return (r.c or 1) >= 2 and 0.8 or 0.5
end

-- Tooltip line(s) saying where a spot came from.
function VG:TooltipSource(r, shared)
    local ago = SecondsToTime(math.max(60, time() - (r.t or time())), true)
    if shared then
        local who = (r.c or 1) >= 2 and ("%d players"):format(r.c) or (r.f or "another player")
        GameTooltip:AddLine(("Shared by %s · %s ago"):format(who, ago), 0.4, 0.8, 1)
        if (r.c or 1) < 2 then
            GameTooltip:AddLine("Unconfirmed until a second player reports it", 0.6, 0.6, 0.6)
        end
    else
        GameTooltip:AddLine(("You gathered here %d time%s · last %s ago"):format(r.c or 1,
            (r.c or 1) == 1 and "" or "s", ago), 0.8, 0.8, 0.8)
    end
end

function VG:Refresh()
    if VG.Pins then VG.Pins:Refresh() end
    if VG.Minimap then VG.Minimap:Invalidate() end
end

----------------------------------------------------------------------
-- Slash (/vg, /voidgather)
----------------------------------------------------------------------
SLASH_VOIDGATHER1 = "/voidgather"
SLASH_VOIDGATHER2 = "/vg"
SlashCmdList.VOIDGATHER = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cfg = VG:Config()
    if VG.KINDS[msg] then
        cfg.show[msg] = not cfg.show[msg]
        VG:Refresh()
        print(("%s %s pins %s"):format(VG.PREFIX, VG.KINDS[msg].label,
            cfg.show[msg] and "|cff33ff33shown|r" or "|cffff5555hidden|r"))
    elseif msg == "minimap" then
        cfg.showMinimap = not cfg.showMinimap
        VG:Refresh()
        print(VG.PREFIX .. " minimap pins " .. (cfg.showMinimap and "|cff33ff33on|r" or "|cffff5555off|r"))
    elseif msg == "track" then
        cfg.autoTrack = not cfg.autoTrack
        if VG.Tracking then VG.Tracking:Apply() end
        print(VG.PREFIX .. " auto-switch Find Minerals/Herbs " .. (cfg.autoTrack and "|cff33ff33on|r" or "|cffff5555off|r"))
    elseif msg == "stats" then
        VG.Gather:PrintSession()
    elseif msg == "reset" then
        VG.Gather:ResetSession()
        print(VG.PREFIX .. " session tally reset.")
    elseif msg == "zone" then
        local mapID = C_Map.GetBestMapForUnit("player")
        local c, s = VG:CountNodes(mapID)
        local info = mapID and C_Map.GetMapInfo(mapID)
        local yours, shared = {}, {}
        for _, k in ipairs(VG.KIND_ORDER) do
            yours[#yours + 1] = ("%d %s"):format(c[k] or 0, VG.KINDS[k].label:lower())
            shared[#shared + 1] = ("%d %s"):format(s[k] or 0, VG.KINDS[k].label:lower())
        end
        print(("%s %s — yours: %s · shared: %s"):format(VG.PREFIX, info and info.name or "?",
            table.concat(yours, ", "), table.concat(shared, ", ")))
    elseif msg == "share" then
        cfg.share = not cfg.share
        VG.Sync:Apply()
        print(VG.PREFIX .. " sharing with other players " .. (cfg.share and "|cff33ff33on|r" or "|cffff5555off|r"))
    elseif msg == "net" then
        VG.Sync:SelfTest()
    elseif msg == "debug" then
        VG.Gather.debug = not VG.Gather.debug
        print(VG.PREFIX .. " debug " .. (VG.Gather.debug and "on — your casts are printed to chat" or "off"))
    else
        print(VG.PREFIX .. " — gathered spots show on your map automatically. Map button (top right of the world map) for filters.")
        print("  /vg stats — this session's loot · /vg zone — spots known here · /vg track — auto-switch Find Minerals/Herbs")
        print("  /vg mining | herb | skin | lumber — show/hide · /vg minimap — minimap pins")
        print("  /vg share — share spots with other players on/off · /vg net — test the sharing channel")
    end
end

----------------------------------------------------------------------
-- Boot
----------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_REGEN_ENABLED")
boot:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        VG:Config()
        VG.Gather:Init()
        VG.Sync:Init()
        VG.Pins:Init()
        VG.Minimap:Init()
        VG.Tracking:Init()
        VG.MapButton:Init()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if VG.Pins then VG.Pins:Refresh() end   -- pins are skipped in combat
    end
end)
