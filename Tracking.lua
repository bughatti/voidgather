----------------------------------------------------------------------
-- VoidGather — optional auto-switch of Find Minerals / Find Herbs
--
-- Classic-style tracking allows ONE at a time, so a miner-herbalist has to
-- keep flipping. When enabled (/vg track or the map menu), this flips every
-- few seconds — but only while moving or mounted, out of combat, and not
-- casting or looting, so it never gets in the way (in Forever a tracking
-- switch can trigger the global cooldown). Where the client allows both at
-- once (retail), it simply turns both on and stops flipping.
----------------------------------------------------------------------
local ADDON, VG = ...
VG.Tracking = {}
local T = VG.Tracking

local FIND_MINERALS, FIND_HERBS = 2580, 2383

local function findIndices()
    local minerals, herbs
    local n = C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetNumTrackingTypes() or 0
    for i = 1, n do
        local info = C_Minimap.GetTrackingInfo(i)
        if info and info.spellID == FIND_MINERALS then minerals = i end
        if info and info.spellID == FIND_HERBS then herbs = i end
    end
    return minerals, herbs
end

local function isActive(i)
    local info = i and C_Minimap.GetTrackingInfo(i)
    return info and info.active
end

local function safeToSwitch()
    if InCombatLockdown() or UnitAffectingCombat("player") then return false end
    if UnitCastingInfo("player") or UnitChannelInfo("player") then return false end
    if LootFrame and LootFrame:IsShown() then return false end
    if UnitIsDeadOrGhost("player") then return false end
    if IsInInstance() then return false end   -- no herbs or ore there
    if IsMounted() then return true end
    -- Speed is a secret value in some places (Warsong Gulch, 2026-11-04): don't compare it.
    local speed = GetUnitSpeed("player")
    if not speed or (issecretvalue and issecretvalue(speed)) then return false end
    return speed > 0
end

local function tick()
    if not VG:Config().autoTrack then return end
    local minerals, herbs = findIndices()
    if not (minerals and herbs) then return end   -- you don't have both
    if isActive(minerals) and isActive(herbs) then return end   -- client allows both
    if not safeToSwitch() then return end
    if isActive(minerals) then
        C_Minimap.SetTracking(herbs, true)
    else
        C_Minimap.SetTracking(minerals, true)
    end
end

function T:Apply()
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    if VG:Config().autoTrack then
        self.ticker = C_Timer.NewTicker(math.max(2, VG:Config().autoTrackSecs or 3), tick)
    end
end

function T:Init() self:Apply() end
