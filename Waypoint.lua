----------------------------------------------------------------------
-- VoidGather — click a pin -> Blizzard user waypoint + arrow
-- (same approach as VoidSweep: C_Map.SetUserWaypoint is not protected).
-- Pins go through this addon's Route.lua: across continents it points at the
-- portal first, and the waypoint clears itself when you arrive.
----------------------------------------------------------------------
local ADDON, VG = ...
VG.Nav = {}
local Nav = VG.Nav

local ARRIVE = 20   -- yards

local function toast(msg, r, g, b)
    UIErrorsFrame:AddMessage(VG.PREFIX .. "  " .. msg, r or 0.3, g or 1, b or 0.3)
end

function Nav:Goto(mapID, x, y, name)
    if not (mapID and x and y) then return end
    local ok = VG.Route:Go({ map = mapID, x = x, y = y, name = name or "node" },
        { arrive = ARRIVE, say = function(msg) toast(msg) end })
    if not ok then toast("can't place a waypoint on this map", 1, 0.3, 0.3) end
end
