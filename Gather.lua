----------------------------------------------------------------------
-- VoidGather — Gather detection + session tally
--
-- UNIT_SPELLCAST_SENT (player) carries the spell AND what it was cast on
-- ("Copper Vein", "Peacebloom", the skinned mob's name). We remember it,
-- and on UNIT_SPELLCAST_SUCCEEDED for that castGUID we record the node at
-- the player's position (you stand on the node to gather it). The loot
-- window that follows feeds the session tally.
--
-- Player casts aren't secret, but the SENT "target" is ConditionalSecret,
-- so it's checked with issecretvalue; if it's ever hidden we fall back to
-- naming the spot after its first loot item.
----------------------------------------------------------------------
local ADDON, VG = ...
VG.Gather = {}
local G = VG.Gather

local kindBySpellID = {}    -- exact IDs we know
local kindBySpellName = {}  -- localized names of the base spells
local pending               -- { kind, name, guid, t }
local lastGather            -- { kind, t, rec, mapID } for naming from loot
local function newSession() return { started = time(), items = {}, nodes = {} } end
local session = newSession()

local function secret(v) return issecretvalue and issecretvalue(v) end

function G:Init()
    for kind, def in pairs(VG.KINDS) do
        for _, id in ipairs(def.spells) do
            kindBySpellID[id] = kind
            local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
            if name and not secret(name) then kindBySpellName[name] = kind end
        end
    end
    local f = CreateFrame("Frame")
    f:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    f:RegisterEvent("LOOT_READY")       -- before fast-loot addons empty the window
    f:RegisterEvent("LOOT_OPENED")
    f:RegisterEvent("LOOT_SLOT_CLEARED")
    f:RegisterEvent("LOOT_CLOSED")
    f:SetScript("OnEvent", function(_, event, ...) G[event](G, ...) end)
end

-- Expansion casts can carry the expansion's name: Midnight's ore cast is
-- "Midnight Mining" (471013), so matching only the base names missed every
-- Midnight ore (found 2026-10-30: herbs saved, ore never). A name that ENDS in
-- the base word counts too.
local SUFFIX_KIND = { { "Mining$", "mining" }, { "Skinning$", "skin" }, { "Herb Gathering$", "herb" } }

local function kindFor(spellID)
    if not spellID or secret(spellID) then return nil end
    local k = kindBySpellID[spellID]
    if k then return k end
    local name = C_Spell.GetSpellName(spellID)
    if not name or secret(name) then return nil end
    if kindBySpellName[name] then return kindBySpellName[name] end
    for _, s in ipairs(SUFFIX_KIND) do
        if name:find(s[1]) then return s[2] end
    end
end

function G:UNIT_SPELLCAST_SENT(unit, target, castGUID, spellID)
    local kind = kindFor(spellID)
    if G.debug then
        local sname = spellID and not secret(spellID) and C_Spell.GetSpellName(spellID)
        print(("%s debug: cast %s (%s) on %s -> %s"):format(VG.PREFIX,
            secret(spellID) and "<hidden>" or tostring(spellID),
            sname and not secret(sname) and sname or "?",
            secret(target) and "<hidden>" or tostring(target),
            kind or "not a gather"))
    end
    if not kind then return end
    local name = (target and not secret(target) and target ~= "") and target or nil
    pending = { kind = kind, name = name, guid = castGUID, t = GetTime() }
end

function G:UNIT_SPELLCAST_FAILED(unit, castGUID)
    if pending and pending.guid == castGUID then pending = nil end
end
G.UNIT_SPELLCAST_INTERRUPTED = G.UNIT_SPELLCAST_FAILED

function G:UNIT_SPELLCAST_SUCCEEDED(unit, castGUID, spellID)
    if not (pending and pending.guid == castGUID) then return end
    local p = pending
    pending = nil
    local mapID = C_Map.GetBestMapForUnit("player")
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return end            -- instances: no map position
    local x, y = pos:GetXY()
    if not x or x == 0 and y == 0 then return end
    local rec, isNew = VG:Record(p.kind, p.name or "?", mapID, x, y)
    session.nodes[p.kind] = (session.nodes[p.kind] or 0) + 1
    -- picked: faded on the map until it's back, on this layer only (Picked.lua)
    if VG.Picked then
        VG.Picked:Note(p.kind, mapID, rec and rec.x or x, rec and rec.y or y)
        if not isNew then VG:Refresh() end
    end
    lastGather = { kind = p.kind, t = GetTime(), rec = rec, mapID = mapID }
    if isNew then
        VG:Refresh()
        print(("%s saved a new %s spot: %s"):format(VG.PREFIX, VG.KINDS[p.kind].label,
            p.name or "(named after your loot)"))
        -- share it once the loot window has had a chance to name it
        C_Timer.After(2, function() VG.Sync:Share(mapID, rec) end)
    end
end

-- Tally loot from a gather (or fishing: priced by Earnings.lua, no map spot);
-- name an unnamed spot after its first item.
local lastFish = 0
local lootKind, lootSlots   -- the open gather / fishing window: slot -> item, priced when taken
local lootReadAt            -- when this window was read (LOOT_READY, then LOOT_OPENED)
function G:LOOT_OPENED()
    -- LOOT_READY already read this window (expires on its own, in case a close is ever missed)
    if lootReadAt and GetTime() - lootReadAt < 1 then return end
    lootReadAt = GetTime()
    lootSlots = nil
    local kind
    if lastGather and (GetTime() - lastGather.t) <= 6 then
        kind = lastGather.kind
    elseif IsFishingLoot and IsFishingLoot() then
        if GetTime() - lastFish < 1 then return end   -- the same window reported twice
        lastFish, kind = GetTime(), "fish"
    else
        lastGather = nil
        return
    end
    local first
    lootKind, lootSlots = kind, {}
    for slot = 1, (GetNumLootItems() or 0) do
        local link = GetLootSlotLink(slot)
        local _, name, qty = GetLootSlotInfo(slot)
        if link and not secret(link) and name and not secret(name) then
            qty = (qty and not secret(qty)) and qty or 1
            local it = session.items[name] or { link = link, n = 0 }
            it.n = it.n + qty
            session.items[name] = it
            first = first or name
            local id = tonumber(link:match("item:(%d+)"))
            if id then lootSlots[slot] = { id = id, qty = qty, link = link } end
        end
    end
    if first and lastGather and lastGather.rec and lastGather.rec.n == "?" then
        lastGather.rec.n = first
        VG:Refresh()
    end
    lastGather = nil
end

-- Priced only once it's in your bags: a window closed early, or loot that
-- didn't fit, isn't counted.
G.LOOT_READY = G.LOOT_OPENED

function G:LOOT_SLOT_CLEARED(slot)
    local it = lootSlots and lootSlots[slot]
    if not it then return end
    lootSlots[slot] = nil
    VG.Earn:Loot(lootKind, { it })
end

-- A fast-loot addon can close the window from inside a LOOT_SLOT_CLEARED
-- handler that runs before ours, so the last item's event arrives after
-- LOOT_CLOSED: keep the snapshot until the next frame.
function G:LOOT_CLOSED()
    lootReadAt = nil
    local snap = lootSlots
    C_Timer.After(0, function()
        if lootSlots == snap then lootSlots = nil end
    end)
end

function G:PrintSession()
    local mins = math.max(1, math.floor((time() - session.started) / 60))
    local parts = {}
    for _, k in ipairs(VG.KIND_ORDER) do
        parts[#parts + 1] = ("%d %s"):format(session.nodes[k] or 0, VG.KINDS[k].label:lower())
    end
    print(("%s this session (%d min): %s gathers"):format(VG.PREFIX, mins, table.concat(parts, ", ")))
    local worth = VG.Earn:SessionLine()
    if worth then print("  " .. worth) end
    local names = {}
    for name in pairs(session.items) do names[#names + 1] = name end
    table.sort(names, function(a, b) return session.items[a].n > session.items[b].n end)
    if #names == 0 then
        print("  nothing gathered yet")
        return
    end
    for i, name in ipairs(names) do
        if i > 12 then print(("  …and %d more"):format(#names - 12)); break end
        local it = session.items[name]
        print(("  %s x%d  (%.0f/hr)"):format(it.link, it.n, it.n * 60 / mins))
    end
end

function G:ResetSession()
    session = newSession()
end
