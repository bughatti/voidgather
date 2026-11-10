----------------------------------------------------------------------
-- VoidGather — Skill: which nodes still give you skill
--
-- GatherData.lua (generated from Blizzard's game tables) gives each current-
-- expansion node its yellow and grey skill; your skill comes from the game for
-- this expansion's line (Midnight Herbalism / Mining). Pins get an outline in
-- the profession window's colors -- orange = always a skill-up, yellow = most
-- of the time, green = rarely, grey = never -- grey pins fade, and the map
-- menu's "Only nodes that give skill" hides them.
--
-- No coloring when it can't help: nodes from other expansions, a profession
-- you don't have, or a maxed profession (everything would be grey while you
-- farm). WoW Forever uses the Classic table below instead of GatherData.lua.
----------------------------------------------------------------------
local ADDON, VG = ...
VG.Skill = {}
local S = VG.Skill

S.COLORS = {
    orange = { 1.00, 0.50, 0.25 }, yellow = { 1.00, 1.00, 0.00 },
    green  = { 0.25, 0.75, 0.25 }, grey   = { 0.50, 0.50, 0.50 },
}

-- WoW Forever: GatherData.lua only knows Midnight nodes and lines, so Forever had no
-- colouring, no Settings skill rows and "/vg best" said there was nothing to level.
-- Classic node skills (same table as VoidProf/GatherPlan.lua; VoidGather must not need
-- VoidProf loaded) with Classic's gathering colours: orange below req+25, yellow below
-- req+50, green below req+100, then grey. Entry = { yellow, grey, green, req }; skill is
-- read by base skill line (182 / 186, or the tier lines 2944 / 2946) (Forever audit, 2026-11-10).
if VG.IS_FOREVER then
    local REQ = {
        herb = {
            ["Peacebloom"] = 1, ["Silverleaf"] = 1, ["Earthroot"] = 15, ["Mageroyal"] = 50, ["Briarthorn"] = 70,
            ["Stranglekelp"] = 85, ["Bruiseweed"] = 100, ["Wild Steelbloom"] = 115, ["Grave Moss"] = 120,
            ["Kingsblood"] = 125, ["Liferoot"] = 150, ["Fadeleaf"] = 160, ["Goldthorn"] = 170,
            ["Khadgar's Whisker"] = 185, ["Wintersbite"] = 195, ["Firebloom"] = 205, ["Purple Lotus"] = 210,
            ["Arthas' Tears"] = 220, ["Sungrass"] = 230, ["Blindweed"] = 235, ["Ghost Mushroom"] = 245,
            ["Gromsblood"] = 250, ["Golden Sansam"] = 260, ["Dreamfoil"] = 270, ["Mountain Silversage"] = 280,
            ["Plaguebloom"] = 285, ["Icecap"] = 290, ["Black Lotus"] = 300,
        },
        mining = {
            ["Copper Vein"] = 1, ["Tin Vein"] = 65, ["Incendicite Mineral Vein"] = 65, ["Silver Vein"] = 75,
            ["Lesser Bloodstone Deposit"] = 75, ["Iron Deposit"] = 125, ["Gold Vein"] = 155, ["Mithril Deposit"] = 175,
            ["Truesilver Deposit"] = 230, ["Dark Iron Deposit"] = 230, ["Small Thorium Vein"] = 245, ["Rich Thorium Vein"] = 275,
        },
    }
    local function build(kind, label, lines)
        local nodes = {}
        for name, req in pairs(REQ[kind]) do nodes[name] = { req + 25, req + 100, req + 50, req } end
        return { label = label, lines = lines, forever = true, nodes = nodes }
    end
    VG.SKILLUP = {
        herb   = build("herb", "Herbalism", { [182] = true, [2944] = true }),
        mining = build("mining", "Mining", { [186] = true, [2946] = true }),
    }
end

-- Skill per kind for this expansion's line: { level, max } or nil. Cached
-- briefly: the minimap asks every frame.
local cache, cacheTime = {}, 0
function S:Level(kind)
    local def = VG.SKILLUP and VG.SKILLUP[kind]
    if not def then return nil end
    if GetTime() - cacheTime > 2 then wipe(cache); cacheTime = GetTime() end
    if cache[kind] == nil then
        local v = false
        local fn = C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID
        if fn and def.line then   -- Forever defs have no .line: the book below only (Forever audit, 2026-11-10)
            local ok, info = pcall(fn, def.line)
            if ok and info and (info.maxSkillLevel or 0) > 0 then v = { info.skillLevel or 0, info.maxSkillLevel } end
        end
        -- That only answers once a profession window has loaded the line. The
        -- Professions book's own call works any time and names the line its
        -- numbers are for ("Midnight Herbalism", or e.g. "Legion Alchemy"): use it
        -- only when it's this expansion's line.
        if not v and GetProfessions and GetProfessionInfo then
            local p1, p2 = GetProfessions()
            for _, idx in ipairs({ p1 or 0, p2 or 0 }) do
                if idx ~= 0 then
                    local _, _, rank, maxRank, _, _, skillLine, _, _, _, lineName = GetProfessionInfo(idx)
                    -- Forever: match the 7th return (skill line id) instead of the Midnight
                    -- line name (Forever audit, 2026-11-10)
                    local match
                    if def.lines then match = skillLine and def.lines[skillLine]
                    else match = lineName and lineName == def.lineName end
                    if match and (maxRank or 0) > 0 then v = { rank or 0, maxRank } end
                end
            end
        end
        cache[kind] = v
    end
    return cache[kind] or nil
end

function S:Invalidate() wipe(cache) end

-- A node's { yellow, grey }. "Transplanted Mana Lily" is the same herb.
local function Lookup(kind, name)
    local def = VG.SKILLUP and VG.SKILLUP[kind]
    if not (def and name) then return nil end
    local t = def.nodes[name]
    if not t then
        local base = name:gsub("^Transplanted ", "")
        -- Forever: "Ooze Covered Silver Vein" needs the same skill as the plain vein
        -- (Forever audit, 2026-11-10)
        if def.forever then base = base:gsub("^Ooze Covered ", "") end
        t = def.nodes[base]
    end
    return t
end

-- "orange" | "yellow" | "green" | "grey", the node's { yellow, grey }, your
-- { level, max } -- or nil when there's nothing useful to say.
function S:Color(kind, name)
    local t = Lookup(kind, name)
    if not t then return nil end
    local lv = self:Level(kind)
    if not lv or lv[1] >= lv[2] then return nil end   -- not learned / maxed
    local s, y, g = lv[1], t[1], t[2]
    -- Forever entries carry t[3] = green and t[4] = skill needed: below it you can't
    -- gather the node at all, so no colour (Forever audit, 2026-11-10)
    if t[4] and s < t[4] then return nil end
    if s >= g then return "grey", t, lv end
    if s < y then return "orange", t, lv end
    if s < (t[3] or (y + g) / 2) then return "yellow", t, lv end
    return "green", t, lv
end

-- Should this spot draw? Hidden only when "Only nodes that give skill" is on
-- and it's grey for you.
function S:Hidden(rec)
    return VG:Config().skillOnly and self:Color(rec.k, rec.n) == "grey"
end

local WHAT = {
    orange = "always gives skill", yellow = "usually gives skill",
    green = "rarely gives skill", grey = "no skill for you any more",
}

-- Tooltip line for a pin.
function S:Tooltip(rec)
    local c, t, lv = self:Color(rec.k, rec.n)
    if not c then
        -- Forever: say what skill a node you can't gather yet needs (Forever audit, 2026-11-10)
        t, lv = Lookup(rec.k, rec.n), self:Level(rec.k)
        if t and t[4] and lv and lv[1] < t[4] then
            GameTooltip:AddLine(("%s %d/%d: needs %d to gather"):format(VG.SKILLUP[rec.k].label, lv[1], lv[2], t[4]),
                1, 0.25, 0.25)
        end
        return
    end
    local col = self.COLORS[c]
    GameTooltip:AddLine(("%s %d/%d: %s"):format(VG.SKILLUP[rec.k].label, lv[1], lv[2], WHAT[c]),
        col[1], col[2], col[3])
    if t[3] then   -- Forever: Classic has a fixed green step too (Forever audit, 2026-11-10)
        GameTooltip:AddLine(("Yellow at %d, green at %d, grey at %d"):format(t[1], t[3], t[2]), 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine(("Yellow at %d, grey at %d"):format(t[1], t[2]), 0.6, 0.6, 0.6)
    end
end

-- One line per profession: your skill and which node types are orange /
-- yellow now. nil when there's nothing to say. Second value: a short form
-- (skill + how many types of each) for the settings window, which shows the
-- full line on hover.
function S:Summary(kind)
    local def = VG.SKILLUP and VG.SKILLUP[kind]
    local lv = def and self:Level(kind)
    if not lv then return nil end
    if lv[1] >= lv[2] then
        -- Forever: 75/150/225 is a rank cap, not the end (Forever audit, 2026-11-10)
        local maxed = (def.forever and lv[2] < 300)
            and ("%s %d/%d: at the cap, train the next rank"):format(def.label, lv[1], lv[2])
            or ("%s %d/%d: maxed"):format(def.label, lv[1], lv[2])
        return maxed, maxed
    end
    local orange, yellow, green = {}, {}, 0
    for name in pairs(def.nodes) do
        local c = self:Color(kind, name)
        if c == "orange" then orange[#orange + 1] = name
        elseif c == "yellow" then yellow[#yellow + 1] = name
        elseif c == "green" then green = green + 1 end
    end
    table.sort(orange); table.sort(yellow)
    local function short(list)   -- the first 4 names, then "+N more"
        local out = {}
        for i = 1, math.min(#list, 4) do out[#out + 1] = list[i] end
        if #list > 4 then out[#out + 1] = ("+%d more"):format(#list - 4) end
        return table.concat(out, ", ")
    end
    local parts = { ("%s %d/%d"):format(def.label, lv[1], lv[2]) }
    if #orange > 0 then parts[#parts + 1] = "|cffff8040" .. short(orange) .. "|r" end
    if #yellow > 0 then parts[#parts + 1] = "|cffffff00" .. short(yellow) .. "|r" end
    if #orange + #yellow == 0 then
        parts[#parts + 1] = green > 0 and ("|cff40c040only green nodes left (%d types): skill-ups are rare|r"):format(green)
            or "no node gives you skill"
    end
    local counts = {}
    if #orange > 0 then counts[#counts + 1] = ("|cffff8040%d orange|r"):format(#orange) end
    if #yellow > 0 then counts[#counts + 1] = ("|cffffff00%d yellow|r"):format(#yellow) end
    if #counts == 0 then
        counts[1] = green > 0 and ("|cff40c040%d green|r"):format(green) or "none give skill"
    end
    return table.concat(parts, " - "),
        ("%s %d/%d  |cff8c8c9e·|r  %s"):format(def.label, lv[1], lv[2], table.concat(counts, ", "))
end

-- Where to go: every known spot (yours + shared, every zone) that still gives
-- you skill, weighted orange 1 / yellow 0.6 / green 0.2, summed per zone and
-- per tenth-of-the-map square; the best square of the best zones wins.
-- Returns up to n { mapID, x, y, name, orange, yellow, green, score }, best first.
local WEIGHT = { orange = 1, yellow = 0.6, green = 0.2 }
function S:BestSpots(kind, n)
    local lv = self:Level(kind)
    if not lv or lv[1] >= lv[2] then return {} end
    local zones = {}
    local function add(mapID, r)
        if r.k ~= kind then return end
        local c = self:Color(kind, r.n)
        local w = c and WEIGHT[c]
        if not w then return end
        local z = zones[mapID]
        if not z then z = { mapID = mapID, score = 0, cells = {} }; zones[mapID] = z end
        z.score = z.score + w
        -- x or y of exactly 1 gives bin 10, so 100 per column, not 10: (0,10) and
        -- (1,0) were the same key
        local key = math.floor(r.x * 10) * 100 + math.floor(r.y * 10)
        local cell = z.cells[key]
        if not cell then cell = { score = 0, sx = 0, sy = 0, n = 0, orange = 0, yellow = 0, green = 0 }; z.cells[key] = cell end
        cell.score, cell.sx, cell.sy, cell.n = cell.score + w, cell.sx + r.x, cell.sy + r.y, cell.n + 1
        cell[c] = cell[c] + 1
    end
    for mapID, list in pairs(VoidGatherDB and VoidGatherDB.nodes or {}) do
        for _, r in ipairs(list) do add(mapID, r) end
    end
    for mapID, list in pairs(VoidGatherDB and VoidGatherDB.shared or {}) do
        for _, r in ipairs(list) do add(mapID, r) end
    end
    for mapID in pairs(VG.SeedData or {}) do   -- spots VoidGather ships with (Seed.lua)
        for _, r in ipairs(VG:SeedFor(mapID)) do add(mapID, r) end
    end
    local out = {}
    for mapID, z in pairs(zones) do
        local best
        for _, cell in pairs(z.cells) do
            if not best or cell.score > best.score then best = cell end
        end
        local info = C_Map.GetMapInfo(mapID)
        out[#out + 1] = { mapID = mapID, x = best.sx / best.n, y = best.sy / best.n,
            name = info and info.name or ("map " .. mapID), score = z.score,
            orange = best.orange, yellow = best.yellow, green = best.green }
    end
    table.sort(out, function(a, b) return a.score > b.score end)
    for i = #out, (n or 3) + 1, -1 do out[i] = nil end
    return out
end

-- "Eversong Woods 45, 62 -- 9 orange, 3 yellow nearby"
function S:SpotText(spot)
    local bits = {}
    if spot.orange > 0 then bits[#bits + 1] = ("|cffff8040%d orange|r"):format(spot.orange) end
    if spot.yellow > 0 then bits[#bits + 1] = ("|cffffff00%d yellow|r"):format(spot.yellow) end
    if spot.green > 0 then bits[#bits + 1] = ("|cff40c040%d green|r"):format(spot.green) end
    return ("%s %d, %d -- %s nearby"):format(spot.name, math.floor(spot.x * 100 + 0.5),
        math.floor(spot.y * 100 + 0.5), table.concat(bits, ", "))
end

-- Waypoint to the best spot for a profession; prints where.
function S:GoBest(kind)
    local spot = self:BestSpots(kind, 1)[1]
    local label = VG.SKILLUP and VG.SKILLUP[kind] and VG.SKILLUP[kind].label or kind
    if not spot then
        print(("%s no known %s spots that give you skill yet -- gather a few and other players' spots fill in too."):format(VG.PREFIX, label))
        return
    end
    VG.Nav:Goto(spot.mapID, spot.x, spot.y, label .. " skill-ups")
    print(("%s best for %s: %s"):format(VG.PREFIX, label, self:SpotText(spot)))
end

-- A skill-up recolors pins (batched).
local pending
local ev = CreateFrame("Frame")
ev:RegisterEvent("SKILL_LINES_CHANGED")
ev:SetScript("OnEvent", function()
    S:Invalidate()
    if pending then return end
    pending = true
    C_Timer.After(1, function() pending = false; VG:Refresh() end)
end)
