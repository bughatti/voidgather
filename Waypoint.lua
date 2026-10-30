----------------------------------------------------------------------
-- VoidGather — click a pin -> Blizzard user waypoint + arrow
-- (same approach as VoidSweep: C_Map.SetUserWaypoint is not protected).
-- The waypoint clears itself when you arrive.
----------------------------------------------------------------------
local ADDON, VG = ...
VG.Nav = {}
local Nav = VG.Nav

local ARRIVE = 20   -- yards

local function toast(msg, r, g, b)
    UIErrorsFrame:AddMessage(VG.PREFIX .. "  " .. msg, r or 0.3, g or 1, b or 0.3)
end

-- Is the current user waypoint still the one we placed?
local function ours()
    local t = Nav.target
    if not (t and C_Map.GetUserWaypoint()) then return false end
    local pos = C_Map.GetUserWaypointPositionForMap(t.mapID)
    if not pos then return false end
    local x, y = pos:GetXY()
    return math.abs(x - t.x) < 0.001 and math.abs(y - t.y) < 0.001
end

local function watch()
    if not Nav.tracking then return end
    -- gone, or replaced by another waypoint: stop watching, never clear it
    if not ours() then Nav.tracking = false; return end
    -- GetDistance() is to the SUPER-TRACKED target (could be a quest now)
    if C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint
       and not C_SuperTrack.IsSuperTrackingUserWaypoint() then return end
    local d = C_Navigation and C_Navigation.GetDistance and C_Navigation.GetDistance()
    if d and d > 0 and d <= ARRIVE then
        C_Map.ClearUserWaypoint()
        Nav.tracking = false
        toast("arrived — waypoint cleared")
    end
end

function Nav:Goto(mapID, x, y, name)
    if not (mapID and x and y) then return end
    if not C_Map.CanSetUserWaypointOnMap(mapID) then
        toast("can't place a waypoint on this map", 1, 0.3, 0.3)
        return
    end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
    Nav.target = { mapID = mapID, x = x, y = y }
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
    Nav.tracking = true
    Nav.ticker = Nav.ticker or C_Timer.NewTicker(0.5, watch)
    toast("navigating to " .. (name or "node"))
end
