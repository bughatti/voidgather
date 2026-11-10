----------------------------------------------------------------------
-- VoidGather — HoverNodes: a herb or ore dot you point at on the minimap is a live node, right
-- there, right now. The user, 2026-11-10 (minimap probe): the game's own dot tooltip ("Mageroyal",
-- "▾ Bruiseweed") is readable, and where the cursor is gives the dot's spot (MinimapHover.lua).
-- So a dot you hover is saved like a gathered spot, without counting as a gather (RecordSeen),
-- and a NEW one is shared like any new spot of yours (Sync:Share, seed spots aren't sent).
-- Only names VoidGather knows as a herb or an ore (VG.SKILLUP), so a quest giver or a flight
-- master you hover is never saved.
----------------------------------------------------------------------
local _, VG = ...
local H = VG.MinimapHover
if not H then return end

local kindOf
local function KindOf(name)
    if not kindOf then
        kindOf = {}
        for kind, def in pairs(VG.SKILLUP or {}) do
            for n in pairs(def.nodes or {}) do kindOf[n] = kind end
        end
    end
    return kindOf[name]
end

H:Listen(function(names, mapID, x, y)
    if InCombatLockdown() then return end
    for _, n in ipairs(names) do
        local kind = KindOf(n)
        if kind and VG.KINDS[kind] then
            local rec, isNew = VG:RecordSeen(kind, n, mapID, x, y)
            if isNew and rec then
                VG:Refresh()
                if VG.Sync and VG.Sync.Share then C_Timer.After(1, function() VG.Sync:Share(mapID, rec) end) end
            end
        end
    end
end)
