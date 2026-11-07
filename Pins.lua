----------------------------------------------------------------------
-- VoidGather — World-map pins (MapCanvas data provider)
-- One small colored dot per remembered spot (color = kind), drawn on the
-- map's lowest pin layer so quests, flight points and entrances always sit
-- on top. Hover = what it is + how often you've gathered it; click = waypoint.
----------------------------------------------------------------------
local ADDON, VG = ...
local PIN_TEMPLATE = "VoidGatherPinTemplate"
local DOT = 9   -- px; shared spots draw 2px smaller

VoidGatherPinMixin = CreateFromMixins(MapCanvasPinMixin)

-- Diamonds, not circles: VoidSweep draws round dots, so the shape alone says
-- which addon a pin belongs to. A square texture rotated 45 degrees.
function VoidGatherPinMixin:OnLoad()
    self:SetScalingLimits(1, 0.9, 1.2)
    self:UseFrameLevelType("PIN_FRAME_LEVEL_DIG_SITE")   -- below quests/POIs
    self.ring:SetTexture("Interface\\Buttons\\WHITE8X8") -- dark outline
    self.ring:SetVertexColor(0, 0, 0)
    self.ring:SetRotation(math.rad(45))
    self.icon:ClearAllPoints()
    self.icon:SetPoint("CENTER")
    self.icon:SetTexture("Interface\\Buttons\\WHITE8X8") -- tinted diamond
    self.icon:SetRotation(math.rad(45))
end

function VoidGatherPinMixin:OnAcquired(rec, mapID, shared)
    self.rec, self.mapID, self.shared = rec, mapID, shared
    local def = VG.KINDS[rec.k]
    local size = shared and DOT - 2 or DOT
    self:SetSize(size, size)
    self:SetPosition(rec.x, rec.y)
    -- a rotated square's diagonal is 1.41x its side: shrink so the diamond
    -- covers about the same area as a round dot
    local side = math.floor(size * 0.75 + 0.5)
    self.icon:SetSize(side, side)
    self.icon:SetVertexColor(def.color[1], def.color[2], def.color[3])
    -- outline = skill-up color (orange / yellow / green / grey) when it applies,
    -- else the plain dark one. Same size either way: a thicker colored outline
    -- made those diamonds look bigger than the rest (the user, 2026-10-30).
    local c = VG.Skill:Color(rec.k, rec.n)
    local col = c and VG.Skill.COLORS[c]
    if col then
        self.ring:SetVertexColor(col[1], col[2], col[3])
    else
        self.ring:SetVertexColor(0, 0, 0)
    end
    self.ring:SetSize(side + 2, side + 2)
    self:SetAlpha(VG:PinAlpha(rec, shared) * (c == "grey" and 0.35 or 1))
    self:Show()
end

function VoidGatherPinMixin:OnReleased()
    self.rec, self.mapID, self.shared = nil, nil, nil
end

function VoidGatherPinMixin:OnMouseEnter()
    local r = self.rec
    if not r then return end
    local def = VG.KINDS[r.k]
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(r.n ~= "?" and r.n or def.label, 1, 1, 1)
    GameTooltip:AddLine(def.label, def.color[1], def.color[2], def.color[3])
    VG.Skill:Tooltip(r)
    VG:TooltipSource(r, self.shared)
    GameTooltip:AddLine("Click for a waypoint", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function VoidGatherPinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

function VoidGatherPinMixin:OnMouseClickAction(button)
    if button == "LeftButton" and self.rec then
        VG.Nav:Goto(self.mapID, self.rec.x, self.rec.y, self.rec.n ~= "?" and self.rec.n or nil)
    end
end

----------------------------------------------------------------------
-- Data provider
----------------------------------------------------------------------
VoidGatherDataProviderMixin = CreateFromMixins(MapCanvasDataProviderMixin)

function VoidGatherDataProviderMixin:RemoveAllData()
    if self:GetMap() then self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE) end
end

function VoidGatherDataProviderMixin:RefreshAllData()
    -- Acquiring pins calls protected mouse setters (blocked in combat); keep the
    -- existing world-anchored pins and redraw on PLAYER_REGEN_ENABLED.
    -- Releasing (hide + clear anchors) is fine in combat, so if the viewed map
    -- changed, drop the old map's pins rather than leave them over the new one.
    local map = self:GetMap()
    local mapID = map and map:GetMapID()
    if InCombatLockdown() then
        if mapID ~= self.drawnMapID then
            self:RemoveAllData()
            self.drawnMapID = nil
        end
        return
    end
    self:RemoveAllData()
    self.drawnMapID = mapID
    if not mapID then return end
    if not VG:Config().showWorld then return end
    for _, rec in ipairs(VG:SeedFor(mapID)) do   -- spots VoidGather ships with (Seed.lua)
        if VG:Visible(rec.k) and not VG.Skill:Hidden(rec) then
            map:AcquirePin(PIN_TEMPLATE, rec, mapID, true)
        end
    end
    for _, rec in ipairs(VG:SharedFor(mapID)) do
        if VG:Visible(rec.k) and not VG.Skill:Hidden(rec) then
            map:AcquirePin(PIN_TEMPLATE, rec, mapID, true)
        end
    end
    for _, rec in ipairs(VG:NodesFor(mapID)) do
        if VG:Visible(rec.k) and not VG.Skill:Hidden(rec) then
            map:AcquirePin(PIN_TEMPLATE, rec, mapID, false)
        end
    end
end

VG.Pins = {}

function VG.Pins:Init()
    if self.provider then return end
    self.provider = CreateFromMixins(VoidGatherDataProviderMixin)
    WorldMapFrame:AddDataProvider(self.provider)
end

function VG.Pins:Refresh()
    if self.provider and WorldMapFrame:IsShown() then
        self.provider:RefreshAllData()
    end
end
