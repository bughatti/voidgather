----------------------------------------------------------------------
-- VoidGather — Picked: nodes you just gathered, per layer (2026-11-08)
--
-- A herb or ore node you picked is gone until it respawns, but only on the layer you
-- picked it on (WoW Forever splits zones into layers, Layer.lua). So:
--   * a node you picked on YOUR layer shows faded, "Picked 4 min ago" in its tooltip,
--     until about when it should be back;
--   * a node you picked on ANOTHER layer shows normally: "picked on another layer, may
--     be up here" (hop and it's there);
--   * retail has no layers: picked nodes just fade until they're back.
-- How long a node takes to come back is learned from your own picks: gathering a spot
-- you picked before, on the same layer, is one sample. Until there are 3 samples for a
-- kind it guesses 15 minutes.
-- Skinning isn't tracked (the mobs move). All of it stays on your PC; nothing is sent.
--   VoidGatherDB.picks   = { { k, m, x, y, t, layer }, ... }   last hour, 300 max
--   VoidGatherDB.respawn = { [kind] = { seconds, ... } }        20 per kind
----------------------------------------------------------------------
local ADDON, VG = ...
VG.Picked = {}
local P = VG.Picked

local KEEP        = 3600        -- a pick is remembered this long
local MAX_PICKS   = 300
local GUESS       = 15 * 60     -- respawn guess until it's learned
local MIN_RESPAWN, MAX_RESPAWN = 5 * 60, 45 * 60
local SAMPLES     = 20
local NEAR_YARDS  = 15          -- a pick this close to a spot is that spot
local TRACKED     = { mining = true, herb = true, lumber = true }

local byMap       -- [mapID] = { pick, ... } (rebuilt from the saved list)
local alphaMemo   -- see P:Alpha
local worldSize = {}   -- [mapID] = { w, h } yards

local function forever() return RegionalUniqueNamesEnabled ~= nil and RegionalUniqueNamesEnabled() == true end

local function db()
    VoidGatherDB = VoidGatherDB or {}
    VoidGatherDB.picks = VoidGatherDB.picks or {}
    VoidGatherDB.respawn = VoidGatherDB.respawn or {}
    return VoidGatherDB
end

local function rebuild()
    byMap = {}
    local now, keep = time(), {}
    for _, p in ipairs(db().picks) do
        if now - (p.t or 0) <= KEEP then
            keep[#keep + 1] = p
            local l = byMap[p.m] or {}
            l[#l + 1] = p
            byMap[p.m] = l
        end
    end
    VoidGatherDB.picks = keep
end

local function yards(mapID)
    local s = worldSize[mapID]
    if s == nil then
        local w, h = C_Map.GetMapWorldSize(mapID)
        s = (w and h and w > 0 and h > 0) and { w, h } or false
        worldSize[mapID] = s
    end
    return s
end

local function near(mapID, x1, y1, x2, y2)
    local s = yards(mapID)
    if not s then return math.abs(x1 - x2) < 0.004 and math.abs(y1 - y2) < 0.004 end
    local dx, dy = (x1 - x2) * s[1], (y1 - y2) * s[2]
    return dx * dx + dy * dy <= NEAR_YARDS * NEAR_YARDS
end

-- a pick saved before 2026-11-14 holds "<server>-<own number>": compare the server number only (Layer.lua L.Canon)
local function canon(p) local L = VG.Layer; return (L and L.Canon) and L.Canon(p) or p end

local function layerFor(mapID)
    local L = VG.Layer
    return L and L:Current(L:Zone(mapID)) or nil
end

-- How long a kind takes to come back (seconds): the median of what you've seen.
local respawnCache = {}   -- [kind] = { seconds, learned }; cleared when a sample is added
function P:Respawn(kind)
    local c = respawnCache[kind]
    if c then return c[1], c[2] end
    local s = db().respawn[kind]
    if not s or #s < 3 then
        respawnCache[kind] = { GUESS, false }
        return GUESS, false
    end
    local sorted = {}
    for i, v in ipairs(s) do sorted[i] = v end
    table.sort(sorted)
    local m = math.max(MIN_RESPAWN, math.min(MAX_RESPAWN, sorted[math.floor((#sorted + 1) / 2)]))
    respawnCache[kind] = { m, true }
    return m, true
end

-- You just gathered here (Gather.lua).
function P:Note(kind, mapID, x, y)
    if not (TRACKED[kind] and mapID and x and y) then return end
    rebuild()   -- drops expired picks first, so no gap older than KEEP is sampled (Codex)
    local now, layer = time(), layerFor(mapID)
    -- the same spot picked before on the same layer: it had come back, so the gap to the
    -- LATEST such pick is at most its respawn time: one sample (Codex: every earlier pick
    -- counted, so gaps spanning several respawns pushed the estimate up)
    local prev
    for _, p in ipairs(byMap[mapID] or {}) do
        if p.k == kind and canon(p.layer) == layer and near(mapID, p.x, p.y, x, y) and (not prev or p.t > prev.t) then
            prev = p
        end
    end
    if prev and now - prev.t >= 60 then
        local s = db().respawn[kind] or {}
        s[#s + 1] = now - prev.t
        while #s > SAMPLES do table.remove(s, 1) end
        VoidGatherDB.respawn[kind] = s
        respawnCache[kind] = nil
    end
    local p = { k = kind, m = mapID, x = x, y = y, t = now, layer = layer }
    local list = db().picks
    list[#list + 1] = p
    while #list > MAX_PICKS do table.remove(list, 1) end
    rebuild()
    wipe(alphaMemo)   -- this spot fades right away
end

-- "mine" (picked on your layer, or no layers here / layer unknown), "other" (picked on
-- another layer only), or nil; plus the pick and the respawn estimate. A pick on YOUR
-- layer always wins over a later one elsewhere (Codex: pick on A, then B, back on A ->
-- it's still gone on A).
function P:State(mapID, r)
    if not (TRACKED[r.k] and mapID) then return nil end
    if not byMap then rebuild() end
    local respawn, now = self:Respawn(r.k), time()
    local cur = forever() and layerFor(mapID) or nil
    local mine, other
    for _, p in ipairs(byMap[mapID] or {}) do
        if p.k == r.k and now - p.t < respawn and near(mapID, p.x, p.y, r.x, r.y) then
            if cur and p.layer and canon(p.layer) ~= cur then
                if not other or p.t > other.t then other = p end
            elseif not mine or p.t > mine.t then
                mine = p
            end
        end
    end
    if mine then return "mine", mine, respawn end
    if other then return "other", other, respawn end
end

-- Pin opacity factor: faded while it's gone on your layer. The minimap asks for every
-- pin every frame, so the answer is kept for a second per spot; a map with no picks
-- answers at once.
alphaMemo = alphaMemo or setmetatable({}, { __mode = "k" })   -- [record] = { t, mapID, alpha } (declared at the top)
function P:Alpha(mapID, r)
    if not byMap then rebuild() end
    if not byMap[mapID] then return 1 end
    local m, now = alphaMemo[r], GetTime()
    if m and m[2] == mapID and now - m[1] < 1 then return m[3] end
    local a = self:State(mapID, r) == "mine" and 0.3 or 1
    alphaMemo[r] = { now, mapID, a }
    return a
end

-- Tooltip line(s).
function P:Tooltip(mapID, r)
    local st, p, respawn = self:State(mapID, r)
    if not st then return end
    local ago = SecondsToTime(math.max(60, time() - p.t), true)
    local left = math.max(0, respawn - (time() - p.t))
    local _, learned = self:Respawn(r.k)
    local back = ("back in about %s%s"):format(SecondsToTime(math.max(60, left), true), learned and "" or " (a guess)")
    if st == "other" then
        GameTooltip:AddLine(("You picked this %s ago on another layer: it may be up on yours."):format(ago), 0.3, 1, 0.3, true)
    elseif forever() and p.layer then
        GameTooltip:AddLine(("Picked %s ago on your layer · %s"):format(ago, back), 1, 0.6, 0.3, true)
    else
        GameTooltip:AddLine(("Picked %s ago · %s"):format(ago, back), 1, 0.6, 0.3, true)
    end
end

-- Faded pins come back on their own: once a minute drop expired picks and redraw while
-- any are left (Codex: expired ones were never dropped while idle, so this redrew forever).
C_Timer.NewTicker(60, function()
    if not (byMap and next(byMap)) then return end
    rebuild()
    wipe(alphaMemo)
    VG:Refresh()
end)
