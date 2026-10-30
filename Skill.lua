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
-- you don't have, WoW Forever (no data), or a maxed profession (everything
-- would be grey while you farm).
----------------------------------------------------------------------
local ADDON, VG = ...
VG.Skill = {}
local S = VG.Skill

S.COLORS = {
    orange = { 1.00, 0.50, 0.25 }, yellow = { 1.00, 1.00, 0.00 },
    green  = { 0.25, 0.75, 0.25 }, grey   = { 0.50, 0.50, 0.50 },
}

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
        if fn then
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
                    local _, _, rank, maxRank, _, _, _, _, _, _, lineName = GetProfessionInfo(idx)
                    if lineName and lineName == def.lineName and (maxRank or 0) > 0 then v = { rank or 0, maxRank } end
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
    if s >= g then return "grey", t, lv end
    if s < y then return "orange", t, lv end
    if s < (y + g) / 2 then return "yellow", t, lv end
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
    if not c then return end
    local col = self.COLORS[c]
    GameTooltip:AddLine(("%s %d/%d: %s"):format(VG.SKILLUP[rec.k].label, lv[1], lv[2], WHAT[c]),
        col[1], col[2], col[3])
    GameTooltip:AddLine(("Yellow at %d, grey at %d"):format(t[1], t[2]), 0.6, 0.6, 0.6)
end

-- One line per profession for the map menu: your skill and which node types
-- are orange / yellow now. nil when there's nothing to say.
function S:Summary(kind)
    local def = VG.SKILLUP and VG.SKILLUP[kind]
    local lv = def and self:Level(kind)
    if not lv then return nil end
    if lv[1] >= lv[2] then return ("%s %d/%d: maxed"):format(def.label, lv[1], lv[2]) end
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
    return table.concat(parts, " - ")
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
