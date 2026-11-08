----------------------------------------------------------------------
-- VoidGather — Minimap pins
-- The minimap isn't a MapCanvas, so place pins by hand: map offset ->
-- yards (C_Map.GetMapWorldSize) -> minimap pixels (C_Minimap.GetViewRadius),
-- rotated when the minimap rotates. Same math as VoidSweep's minimap layer.
-- Pins at the edge of the minimap's range stay faint; close ones solid.
----------------------------------------------------------------------
local ADDON, VG = ...
VG.Minimap = {}
local MM = VG.Minimap

-- Repositioned EVERY frame (no tick): the minimap scrolls per frame, so a 0.1s
-- cadence made pins lag then snap -- visible jitter while flying (2026-10-21).
-- Node lists are cached per map, so per-frame work is arithmetic + SetPoint.
local pool, nActive = {}, 0
local cacheMap, cacheOwn, cacheShared, cacheSeed

local function acquire()
    nActive = nActive + 1
    local p = pool[nActive]
    if not p then
        p = CreateFrame("Frame", nil, Minimap)
        p:SetFrameLevel(Minimap:GetFrameLevel() + 5)
        -- a gathering HUD (ours or another addon's) fades the minimap and moves
        -- what hangs off it: pins stay on it and keep their own opacity
        p.voidKeep = true
        p:SetIgnoreParentAlpha(true)
        p.ring = p:CreateTexture(nil, "BACKGROUND")
        p.ring:SetAtlas("WhiteCircle-RaidBlips")
        p.ring:SetPoint("CENTER")
        -- skill-up frame: a solid square 2px around the (square) icon. The round
        -- ring hides behind the icon, so its color never showed (seen 2026-10-30).
        p.frame = p:CreateTexture(nil, "BACKGROUND", nil, 1)
        p.frame:SetPoint("CENTER")
        p.icon = p:CreateTexture(nil, "ARTWORK")
        p.icon:SetAllPoints()
        p.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        -- "around" mode (the game tracks this kind): four ticks round the spot, the
        -- middle left empty for the game's own yellow dot (see MM:Update)
        p.ticks = {}
        for i = 1, 4 do
            local t = p:CreateTexture(nil, "ARTWORK")
            t:SetSize(3, 3)
            p.ticks[i] = t
        end
        p:EnableMouse(true)
        p:SetScript("OnEnter", function(self)
            local r = self.rec
            if not r then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(r.n ~= "?" and r.n or VG.KINDS[r.k].label, 1, 1, 1)
            VG.Skill:Tooltip(r)
            VG:TooltipSource(r, self.shared)
            GameTooltip:Show()
        end)
        p:SetScript("OnLeave", function() GameTooltip:Hide() end)
        pool[nActive] = p
    end
    p:Show()
    return p
end

-- on the gathering HUD the pins let clicks through (it sits over the world); "around"
-- pins too, so hovering the game's yellow dot shows the game's own tooltip
local function setMouse(p, mouse)
    if p.mouseOn ~= mouse then p:EnableMouse(mouse); p.mouseOn = mouse end
end

local TICK = { { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }

local function hideRest()
    for i = nActive + 1, #pool do pool[i]:Hide(); pool[i].rec = nil end
end

function MM:Invalidate() cacheMap = nil end

function MM:Update()
    nActive = 0
    local cfg = VG:Config()
    if not cfg.showMinimap then hideRest(); return end

    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then hideRest(); return end
    local ppos = C_Map.GetPlayerMapPosition(mapID, "player")
    -- NOT `mapID and C_Map.GetMapWorldSize(mapID)`: `a and f()` keeps only f's FIRST
    -- return, so h was always nil and minimap pins never drew (found 2026-10-18).
    local w, h = C_Map.GetMapWorldSize(mapID)
    if not (ppos and w and h and w > 0 and h > 0) then hideRest(); return end
    if cacheMap ~= mapID then
        cacheMap, cacheOwn, cacheShared = mapID, VG:NodesFor(mapID), VG:SharedFor(mapID)
        cacheSeed = VG:SeedFor(mapID)   -- spots VoidGather ships with (Seed.lua)
    end

    local px, py = ppos:GetXY()
    local radius = (C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()) or 133
    if radius <= 0 then radius = 133 end
    local half = Minimap:GetWidth() / 2
    local scale = half / radius
    local rotate = GetCVar("rotateMinimap") == "1"
    local facing = rotate and (GetPlayerFacing() or 0) or 0
    local sinF, cosF = math.sin(facing), math.cos(facing)
    local baseSize = VG.HUD:IsActive() and (cfg.hudPinSize or 16) or cfg.mmPinSize or 11
    local mmAlpha = cfg.mmAlpha or 0.7
    -- visibility per kind once per frame, not VG:Visible() per record
    local vis, around = {}, {}
    for k in pairs(VG.KINDS) do
        vis[k] = VG:Visible(k)
        -- the game shows live nodes of this kind as yellow dots: our pins can never cover
        -- them (child frames always draw over the minimap's own dots), so they mark the
        -- spot from around it instead (the user, 2026-11-07)
        around[k] = VG.Tracking and VG.Tracking.GameTracks and VG.Tracking:GameTracks(k) or false
    end
    local hud = VG.HUD:IsActive()

    local function place(list, shared)
        local size = shared and math.max(7, baseSize - 2) or baseSize
        for _, r in ipairs(list) do
            if vis[r.k] and not VG.Skill:Hidden(r) then
                local sx = (r.x - px) * w * scale
                local sy = -((r.y - py) * h) * scale
                if rotate then sx, sy = sx * cosF + sy * sinF, -sx * sinF + sy * cosF end
                local dist2 = sx * sx + sy * sy
                if dist2 <= (half - 4) * (half - 4) then
                    local p = acquire()
                    local def = VG.KINDS[r.k]
                    p.rec, p.shared = r, shared
                    p:SetSize(size, size)
                    local c = VG.Skill:Color(r.k, r.n)
                    local col = c and VG.Skill.COLORS[c]
                    if around[r.k] then
                        -- four ticks just outside the game's dot, in the skill-up color
                        -- (else the kind's); nothing over the middle
                        p.ring:Hide(); p.frame:Hide(); p.icon:Hide()
                        local tc = col or def.color
                        local off = math.max(7, size * 0.75)
                        for i, t in ipairs(p.ticks) do
                            t:SetColorTexture(tc[1], tc[2], tc[3])
                            t:ClearAllPoints()
                            t:SetPoint("CENTER", p, "CENTER", TICK[i][1] * off, TICK[i][2] * off)
                            t:Show()
                        end
                        setMouse(p, false)
                    else
                        for _, t in ipairs(p.ticks) do t:Hide() end
                        p.ring:Show(); p.icon:Show()
                        p.ring:SetSize(size + 3, size + 3)
                        p.ring:SetVertexColor(def.color[1], def.color[2], def.color[3])
                        -- skill-up color as a frame around the icon (see Skill.lua)
                        if col then
                            p.frame:SetSize(size + 2, size + 2)   -- 1px skill-color edge
                            p.frame:SetColorTexture(col[1], col[2], col[3])
                            p.frame:Show()
                        else
                            p.frame:Hide()
                        end
                        p.icon:SetTexture(def.icon)
                        setMouse(p, not hud)
                    end
                    local edge = dist2 > (half * 0.75) ^ 2 and 0.55 or 1
                    p:SetAlpha(mmAlpha * edge * VG:PinAlpha(r, shared) * (c == "grey" and 0.35 or 1))
                    p:ClearAllPoints()
                    p:SetPoint("CENTER", Minimap, "CENTER", sx, sy)
                end
            end
        end
    end
    place(cacheSeed, true)
    place(cacheShared, true)
    place(cacheOwn, false)
    hideRest()
end

function MM:Init()
    local f = CreateFrame("Frame", nil, Minimap)   -- parented: stops when the minimap is hidden
    f.voidKeep = true
    f:SetScript("OnUpdate", function() MM:Update() end)
end
