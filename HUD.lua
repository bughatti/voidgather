----------------------------------------------------------------------
-- VoidGather — Gathering HUD: the game's own minimap, big and see-through
--
-- Turning it on moves the real minimap into a large frame over the world,
-- zoomed all the way out and turning with you, then fades the minimap itself
-- away. The game still draws its own dots at full strength (Find Herbs /
-- Find Minerals nodes, quest and other blips), so those float around you.
-- VoidGather's and VoidSweep's spots come along: they're drawn on the minimap
-- and ignore its fade (SetIgnoreParentAlpha in their minimap code).
--
-- Whatever hangs off the minimap (its zoom buttons, the compass ring, other
-- addons' minimap buttons) is parked on a stand-in frame where the minimap
-- normally sits, so nothing flies across the screen. Turning it off puts
-- everything back exactly as it was.
--
-- Some addons' minimap buttons are protected, so it only switches outside
-- combat; a toggle in combat happens as soon as combat ends. Click-through
-- while you play; "Move HUD" unlocks it to drag.
----------------------------------------------------------------------
local ADDON, VG = ...
VG.HUD = {}
local H = VG.HUD

local A = { 0, 0.78, 1 }   -- Void cyan
local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask"   -- a soft white disc
local hud, standIn
local saved                -- the minimap's state before the HUD took it
local parked = {}          -- [object] = { parent?, layer? / strata+level?, points? }
local unfaded = {}         -- other addons' pins we told to ignore the fade (undone on give-back)
local unclicked = {}       -- other addons' pins we made click-through (undone on give-back)
local fixLater = {}        -- parked objects that re-anchored on the minimap in combat
local hooked = {}          -- objects whose SetPoint we watch (they may re-anchor on the minimap)
local active = false       -- the minimap is in the HUD right now
local moving = false
local pending              -- what to do once combat ends (true = on, false = off)
local zooming = false      -- our own SetZoom, which the zoom hook lets through

----------------------------------------------------------------------
-- Parking what hangs off the minimap
----------------------------------------------------------------------
-- Map pins drawn in minimap coordinates stay on the minimap.
local function otherPin(obj)
    local name = obj.GetName and obj:GetName()
    if name and (name:find("^GatherMate") or name:find("^HandyNotes")) then return true end
    local HBD = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
    return HBD and HBD.minimapPins and HBD.minimapPins[obj] ~= nil
end

local function keep(obj)
    if obj.voidKeep then return true end
    -- Blizzard's second minimap renderer (some zones draw the map through it): a
    -- black square clipped round by a mask. Moved, it lost the clip and left a
    -- square behind; it stays on the minimap and fades with it in the HUD.
    if obj == _G.HybridMinimap then return true end
    if otherPin(obj) then
        -- another addon's map pin: stays, and must not vanish with the fade
        if obj.SetIgnoreParentAlpha and obj.IsIgnoringParentAlpha and not obj:IsIgnoringParentAlpha() then
            obj:SetIgnoreParentAlpha(true)
            unfaded[obj] = true
        end
        -- the HUD sits over the world: its pins let clicks through
        if obj.IsMouseEnabled and obj:IsMouseEnabled() and not InCombatLockdown() then
            obj:EnableMouse(false)
            unclicked[obj] = true
        end
        return true
    end
    return false
end

local function pointsOf(obj)
    local pts = {}
    for i = 1, obj:GetNumPoints() do pts[i] = { obj:GetPoint(i) } end
    return pts
end

-- Re-point anything anchored on the minimap at the stand-in (point list in).
-- Offsets measured on the big HUD minimap are scaled down to the stand-in, so a
-- ring button (Void hub, minimap-button libraries) that re-placed itself while
-- the minimap was HUD-sized lands on the small ring instead of off the screen.
local reanchoring = false
local function reanchor(obj, pts, fromHud)
    local k = 1
    if fromHud then
        -- on the stand-in now: its offsets are in the stand-in's own units, so the
        -- ratio of the two widths; still on its own parent: a ratio on screen
        local mw, sw = Minimap:GetWidth(), standIn:GetWidth()
        if obj:GetParent() ~= standIn then
            mw, sw = mw * Minimap:GetEffectiveScale(), sw * standIn:GetEffectiveScale()
        end
        if mw > 0 and sw > 0 then k = sw / mw end
    end
    reanchoring = true
    pcall(function()
        obj:ClearAllPoints()
        for _, p in ipairs(pts) do
            if p[2] == Minimap then
                obj:SetPoint(p[1], standIn, p[3], (p[4] or 0) * k, (p[5] or 0) * k)
            else
                obj:SetPoint(p[1], p[2], p[3], p[4], p[5])
            end
        end
    end)
    reanchoring = false
end

-- A parked button that re-anchors itself on the minimap (minimap-button
-- libraries do on drag or refresh) would jump onto the HUD: send it back.
local function watch(obj)
    if hooked[obj] or not obj.SetPoint then return end
    hooked[obj] = true
    hooksecurefunc(obj, "SetPoint", function(self)
        if not active or reanchoring or not parked[self] then return end
        local pts, onMinimap = {}, false
        for i = 1, self:GetNumPoints() do
            pts[i] = { self:GetPoint(i) }
            if pts[i][2] == Minimap then onMinimap = true end
        end
        if not onMinimap then return end
        -- never touch frames in combat (some are protected): fix it after
        if InCombatLockdown() then fixLater[self] = pts else reanchor(self, pts, true) end
    end)
end

-- fromHud: the minimap is in the HUD already, so anything placed on it since
-- (a button created after the HUD took the minimap) has HUD-sized offsets.
local function park(obj, fromHud)
    if not obj or obj == Minimap or parked[obj] or keep(obj) then return end
    local rec, pts = {}, pointsOf(obj)
    if obj:GetParent() == Minimap then
        rec.parent = Minimap
        if obj.GetDrawLayer then
            rec.layer = { obj:GetDrawLayer() }
        else
            rec.strata, rec.level = obj:GetFrameStrata(), obj:GetFrameLevel()
        end
        obj:SetParent(standIn)
        if rec.layer then obj:SetDrawLayer(rec.layer[1], rec.layer[2])
        else obj:SetFrameStrata(rec.strata); obj:SetFrameLevel(rec.level) end
    end
    local onMinimap = false
    for _, p in ipairs(pts) do
        if p[2] == Minimap then onMinimap = true; break end
    end
    if onMinimap then
        rec.points = pts
        rec.fromHud = fromHud
        reanchor(obj, pts, fromHud)
    end
    if rec.parent or rec.points then
        parked[obj] = rec
        watch(obj)
    end
end

local function unparkOne(obj, rec)
    if rec.parent then
        obj:SetParent(rec.parent)
        if rec.layer then obj:SetDrawLayer(rec.layer[1], rec.layer[2])
        elseif rec.strata then obj:SetFrameStrata(rec.strata); obj:SetFrameLevel(rec.level) end
    end
    if rec.points then
        -- (read where it sits now before clearing it)
        local pts = {}
        for i = 1, obj:GetNumPoints() do pts[i] = { obj:GetPoint(i) } end
        obj:ClearAllPoints()
        if rec.fromHud then
            -- placed while the minimap was HUD-sized: its stand-in spot (scaled to the
            -- minimap's normal size) is the right one, so carry that over
            for _, p in ipairs(#pts > 0 and pts or rec.points) do
                obj:SetPoint(p[1], p[2] == standIn and Minimap or p[2], p[3], p[4], p[5])
            end
        else
            for _, p in ipairs(rec.points) do obj:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
        end
    end
end

-- HybridMinimap stays on the minimap, and its map canvas takes the mouse: on the
-- HUD that would be an invisible layer catching your clicks on the world.
local unwheeled = {}
local function hybridClickThrough()
    local hm = _G.HybridMinimap
    if not hm then return end
    local canvas = hm.MapCanvas
    for _, f in ipairs({ hm, canvas, canvas and canvas.ScrollContainer }) do
        if f and f.IsMouseEnabled then
            if f:IsMouseEnabled() then f:EnableMouse(false); unclicked[f] = true end
            if f.IsMouseWheelEnabled and f:IsMouseWheelEnabled() then f:EnableMouseWheel(false); unwheeled[f] = true end
        end
    end
end

local function parkAll(fromHud)
    -- a pin library reuses its pins: one parked while it was idle is a pin again
    for obj, rec in pairs(parked) do
        if otherPin(obj) then
            parked[obj] = nil   -- first, so our SetPoint watch leaves it alone
            if rec.parent then obj:SetParent(Minimap) end
            -- the library has just placed it (our watch moved that onto the stand-in):
            -- put it back on the HUD minimap at the matching, scaled-up offset
            local sw, mw = standIn:GetWidth(), Minimap:GetWidth()
            local k = (sw > 0 and mw > 0) and (mw / sw) or 1
            local pts = {}
            for i = 1, obj:GetNumPoints() do pts[i] = { obj:GetPoint(i) } end
            obj:ClearAllPoints()
            for _, p in ipairs(pts) do
                if p[2] == standIn then
                    obj:SetPoint(p[1], Minimap, p[3], (p[4] or 0) * k, (p[5] or 0) * k)
                else
                    obj:SetPoint(p[1], p[2], p[3], p[4], p[5])
                end
            end
        end
    end
    hybridClickThrough()
    for _, c in ipairs({ Minimap:GetChildren() }) do park(c, fromHud) end
    for _, r in ipairs({ Minimap:GetRegions() }) do park(r, fromHud) end
    -- the compass ring is MinimapBackdrop's, but anchored on the minimap itself
    park(_G.MinimapCompassTexture, fromHud)
    -- pieces of the minimap cluster anchored on the minimap (the coordinates
    -- line): only re-anchored, they keep their parent
    local cluster = _G.MinimapCluster
    for _, holder in ipairs({ cluster, cluster and cluster.MinimapContainer }) do
        if holder then
            for _, c in ipairs({ holder:GetChildren() }) do park(c, fromHud) end
            for _, r in ipairs({ holder:GetRegions() }) do park(r, fromHud) end
        end
    end
end

local function unparkAll()
    for obj, rec in pairs(parked) do unparkOne(obj, rec) end
    wipe(parked)
    for f in pairs(unwheeled) do f:EnableMouseWheel(true) end
    wipe(unwheeled)
    for obj in pairs(unfaded) do obj:SetIgnoreParentAlpha(false) end
    wipe(unfaded)
    for obj in pairs(unclicked) do obj:EnableMouse(true) end
    wipe(unclicked)
    wipe(fixLater)
end

----------------------------------------------------------------------
-- Frames
----------------------------------------------------------------------
local function build()
    local cfg = VG:Config()
    hud = CreateFrame("Frame", "VoidGatherHUD", UIParent, "BackdropTemplate")
    hud:SetFrameStrata("BACKGROUND")
    hud:SetClampedToScreen(true)
    hud:SetMovable(true)
    hud:RegisterForDrag("LeftButton")
    hud:SetScript("OnDragStart", hud.StartMoving)
    hud:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local pt, _, rel, x, y = self:GetPoint()
        cfg.hudPos = { pt, rel, x, y }
    end)
    -- a faint disc so you can see where the HUD's edge is. A round texture tinted,
    -- not a color fill with a mask: masks don't clip color fills, which drew
    -- this and the stand-in's background as squares.
    hud.edge = hud:CreateTexture(nil, "BACKGROUND", nil, -1)
    hud.edge:SetAllPoints()
    hud.edge:SetTexture(DISC)
    hud.hint = hud:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hud.hint:SetPoint("BOTTOM", hud, "TOP", 0, 22)

    -- Compass: N / E / S / W on the rim, turning with you (up on the HUD is the way
    -- you face), and your heading just above the ring.
    hud.compass = {}
    for _, d in ipairs({ { "N", 0 }, { "E", 1 }, { "S", 2 }, { "W", 3 } }) do
        local fs = hud:CreateFontString(nil, "OVERLAY", d[1] == "N" and "GameFontNormalLarge" or "GameFontNormal")
        fs:SetText(d[1])
        if d[1] == "N" then fs:SetTextColor(A[1], A[2], A[3], 1) else fs:SetTextColor(1, 1, 1, 0.65) end
        fs.quarter = d[2]
        hud.compass[#hud.compass + 1] = fs
    end
    hud.heading = hud:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hud.heading:SetPoint("BOTTOM", hud, "TOP", 0, 2)
    hud.heading:SetTextColor(A[1], A[2], A[3])
    local HEADINGS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
    hud:SetScript("OnUpdate", function(self)
        local facing = GetPlayerFacing()   -- nil where the game hides it (instances)
        for _, fs in ipairs(self.compass) do fs:SetShown(facing ~= nil) end
        self.heading:SetShown(facing ~= nil)
        if not facing then return end
        -- north sits at (sin f, cos f) from the center; east, south and west follow
        -- a quarter turn apart, clockwise on screen
        local r = self:GetWidth() / 2 - 14
        for _, fs in ipairs(self.compass) do
            local a = facing + fs.quarter * math.pi / 2
            fs:ClearAllPoints()
            fs:SetPoint("CENTER", self, "CENTER", math.sin(a) * r, math.cos(a) * r)
        end
        -- facing turns counterclockwise from north; a bearing turns clockwise
        local bearing = (360 - math.deg(facing)) % 360
        self.heading:SetText(HEADINGS[math.floor((bearing + 22.5) / 45) % 8 + 1])
    end)
    hud.hint:SetText("Drag to move the HUD  ·  Move HUD (or /vg hud move) again to lock")
    hud:Hide()

    -- where the minimap normally sits: its buttons and ring wait here
    standIn = CreateFrame("Frame", "VoidGatherMinimapStandIn", UIParent)
    standIn.bg = standIn:CreateTexture(nil, "BACKGROUND")
    standIn.bg:SetAllPoints()
    standIn.bg:SetTexture(DISC)
    standIn.bg:SetVertexColor(0, 0, 0, 0.55)
    standIn.note = standIn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    standIn.note:SetPoint("CENTER")
    standIn.note:SetText("Minimap is\nin the HUD")
    standIn.note:SetTextColor(A[1], A[2], A[3], 0.8)
    standIn:Hide()
end

local function hudSize()
    local cfg = VG:Config()
    local share = tonumber(cfg.hudSize) or 0.7
    -- the first HUD (2026-11-02) saved a pixel size (300 / 380 / 480): as a share of
    -- the screen that made it 380 screens wide and invisible. Reset anything off-scale.
    if share > 1 or share < 0.3 then share = 0.7; cfg.hudSize = share end
    return math.floor(UIParent:GetHeight() * share)
end

-- Size, place and style the HUD (and the minimap inside it while active).
local function layout()
    local cfg = VG:Config()
    local size = hudSize()
    hud:SetSize(size, size)
    hud:ClearAllPoints()
    local p = cfg.hudPos
    if p then hud:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else hud:SetPoint("CENTER", UIParent, "CENTER", 0, -30) end
    hud.edge:SetVertexColor(A[1], A[2], A[3], moving and 0.12 or 0.03)
    hud:EnableMouse(moving)   -- click-through unless you're placing it
    if moving then
        hud:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        hud:SetBackdropBorderColor(A[1], A[2], A[3], 0.8)
        hud.hint:Show()
    else
        hud:SetBackdrop(nil)
        hud.hint:Hide()
    end
    if active then
        Minimap:SetSize(size, size)
        Minimap:SetAlpha(cfg.hudTerrain or 0)
        zooming = true
        Minimap:SetZoom(0)   -- all the way out
        zooming = false
    end
end

----------------------------------------------------------------------
-- Taking the minimap and giving it back
----------------------------------------------------------------------
-- HybridMinimap (Blizzard's second minimap renderer, some zones) forgets its map
-- while the minimap is hidden and sizes it from the minimap's zoom, which it only
-- hears about on a zoom event: after our hide / show it drew at the old scale (a
-- square) until you moved. Re-read the map and zoom on the next frame.
local function refreshHybrid()
    C_Timer.After(0, function()
        local hm = _G.HybridMinimap
        if not (hm and hm.CheckMap) then return end
        -- only where the game uses it: elsewhere this would switch it back on
        if C_Minimap.ShouldUseHybridMinimap and not C_Minimap.ShouldUseHybridMinimap() then return end
        pcall(function()
            hm.mapID = nil
            hm:CheckMap()
            if hm:IsShown() and hm.mapID and hm.UpdateZoom then hm:UpdateZoom() end
        end)
    end)
end

local function take()
    if active then return true end
    -- FarmHud's HUD has the minimap right now: two would fight over it
    local holder = Minimap:GetParent()
    if holder and holder.GetName and holder:GetName() == "FarmHud" then
        print(VG.PREFIX .. " FarmHud's HUD has the minimap right now: turn that off first.")
        return false
    end
    saved = {
        parent = Minimap:GetParent(), points = pointsOf(Minimap), size = { Minimap:GetSize() },
        scale = Minimap:GetScale(), strata = Minimap:GetFrameStrata(), level = Minimap:GetFrameLevel(),
        alpha = Minimap:GetAlpha(), zoom = Minimap:GetZoom(), mouse = Minimap:IsMouseEnabled(),
        wheel = Minimap:IsMouseWheelEnabled(),
    }
    -- your own minimap settings (game-saved): rotation, and the zoom outdoors and
    -- indoors. Kept in VoidGatherDB too, so a /reload with the HUD on never
    -- mistakes the HUD's settings for yours. (A game crash before VoidGatherDB is
    -- written can still lose them; a logout or /reload always restores them.)
    local cfg = VG:Config()
    cfg.hudOwn = cfg.hudOwn or { rotate = GetCVar("rotateMinimap"), zoom = GetCVar("minimapZoom"),
                                 inside = GetCVar("minimapInsideZoom") }
    saved.own = cfg.hudOwn
    -- the stand-in takes the minimap's exact place
    standIn:SetParent(saved.parent)
    standIn:SetScale(saved.scale)
    standIn:SetSize(saved.size[1], saved.size[2])
    standIn:SetFrameStrata(saved.strata)
    standIn:SetFrameLevel(saved.level)
    standIn:ClearAllPoints()
    for _, p in ipairs(saved.points) do standIn:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
    standIn:Show()
    parkAll()

    -- hidden while it moves, shown again once sized (Refresh): the game only
    -- redraws the minimap at its new size and place after a hide / show
    Minimap:Hide()
    Minimap:SetParent(hud)
    Minimap:ClearAllPoints()
    Minimap:SetPoint("CENTER", hud, "CENTER")
    Minimap:SetScale(1)
    Minimap:SetFrameStrata("BACKGROUND")
    Minimap:EnableMouse(false)
    Minimap:EnableMouseWheel(false)
    SetCVar("rotateMinimap", "1")   -- up = the way you face
    active = true
    if H._syncShift then H._syncShift() end   -- Shift already held
    return true
end

local function giveBack()
    if not active then return end
    active = false
    local s = saved
    Minimap:Hide()   -- (same hide / show on the way back)
    Minimap:SetParent(s.parent)
    Minimap:ClearAllPoints()
    for _, p in ipairs(s.points) do Minimap:SetPoint(p[1], p[2], p[3], p[4], p[5]) end
    Minimap:SetSize(s.size[1], s.size[2])
    Minimap:SetScale(s.scale)
    Minimap:SetFrameStrata(s.strata)
    Minimap:SetFrameLevel(s.level)
    Minimap:SetAlpha(s.alpha)
    Minimap:EnableMouse(s.mouse)
    if H._shiftOff then H._shiftOff() end   -- (a held Shift had turned it on)
    Minimap:EnableMouseWheel(s.wheel)
    local own = s.own
    SetCVar("rotateMinimap", own.rotate)
    if own.zoom then SetCVar("minimapZoom", own.zoom) end
    if own.inside then SetCVar("minimapInsideZoom", own.inside) end
    -- your zoom for where you stand now (indoors and outdoors are separate)
    local z = tonumber(IsIndoors() and own.inside or own.zoom) or s.zoom
    zooming = true
    Minimap:SetZoom(math.min(z, Minimap:GetZoomLevels() - 1))
    zooming = false
    VG:Config().hudOwn = nil
    unparkAll()
    standIn:Hide()
    Minimap:Show()
    refreshHybrid()
    saved = nil
end

-- Apply the setting now, or after combat.
function H:Refresh()
    local want = VG:Config().hud
    if InCombatLockdown() and want ~= active then
        pending = want
        return
    end
    pending = nil
    if not hud then
        if not want then return end
        build()
    end
    if want then
        if not take() then
            VG:Config().hud = false
            return
        end
        layout()
        hud:Show()
        Minimap:Show()
        refreshHybrid()
    else
        giveBack()
        moving = false
        hud:Hide()
    end
end

function H:SetShown(on)
    VG:Config().hud = on
    self:Refresh()
    local later = pending ~= nil
    print(VG.PREFIX .. " gathering HUD " .. (on and "|cff33ff33on|r" or "|cffff5555off|r")
        .. (later and " |cffffd200(after combat)|r" or "")
        .. (on and " |cff888888(hold Shift over it to see what a dot is)|r" or ""))
end

function H:Toggle() self:SetShown(not VG:Config().hud) end

-- Unlock to drag (turns it on if it was off), lock again.
function H:ToggleMove()
    moving = not moving
    if moving and not VG:Config().hud then
        self:SetShown(true)
    elseif hud and active then
        layout()
    end
    if H._syncShift then H._syncShift() end
    print(VG.PREFIX .. (moving and " HUD unlocked: drag it, then Move HUD (or /vg hud move) again to lock."
        or " HUD locked: it lets clicks through again."))
end

function H:IsMoving() return moving end

-- /vg hud debug: where everything is, for fixing it from a screenshot
function H:Debug()
    local function d(name, f)
        if not f then print(("  %s: |cffff5555missing|r"):format(name)); return end
        local p = f.GetParent and f:GetParent()
        local pt, rel, rp, x, y = f:GetPoint(1)
        local relName = rel and (rel.GetName and rel:GetName() or "?") or "-"
        print(("  %s: parent=%s shown=%s visible=%s size=%dx%d scale=%.2f alpha=%.2f eff=%.2f strata=%s lvl=%d pt=%s %s %s %d,%d"):format(
            name, p and (p:GetName() or "?") or "-", tostring(f:IsShown()), tostring(f:IsVisible()),
            f:GetWidth(), f:GetHeight(), f:GetScale(), f:GetAlpha(), f:GetEffectiveAlpha(),
            f.GetFrameStrata and f:GetFrameStrata() or "-", f.GetFrameLevel and f:GetFrameLevel() or 0,
            tostring(pt), relName, tostring(rp), x or 0, y or 0))
    end
    print(VG.PREFIX .. (" HUD debug: active=%s moving=%s pending=%s zoom=%s rotate=%s"):format(
        tostring(active), tostring(moving), tostring(pending), tostring(Minimap:GetZoom()), tostring(GetCVar("rotateMinimap"))))
    d("Minimap", Minimap)
    d("HUD", hud)
    d("StandIn", standIn)
    d("Hub", _G.VoidHubMinimapBtn)
    local n = 0
    for _ in pairs(parked) do n = n + 1 end
    print(("  parked=%d"):format(n))
end
function H:IsActive() return active end
function H:Invalidate() end   -- (pins are drawn by Minimap.lua; nothing cached here)

function H:Init()
    -- keep the minimap zoomed out while it's in the HUD (zone changes reset zoom)
    hooksecurefunc(Minimap, "SetZoom", function()
        if active and not zooming and Minimap:GetZoom() ~= 0 then
            zooming = true
            Minimap:SetZoom(0)
            zooming = false
        end
    end)
    -- pins and buttons other addons add to the minimap after the HUD took it
    C_Timer.NewTicker(1, function()
        if active and not InCombatLockdown() then parkAll(true) end
    end)
    -- What's that yellow dot? (the user, 2026-11-07: the HUD hid the game's dot tooltips.)
    -- The minimap is click-through in the HUD, so the game's own hover tooltip
    -- (Minimap_OnEnter -> SetMinimapMouseover) never runs. Asking the minimap ourselves
    -- with the mouse off gives nothing (tested in game), and leaving its mouse on would
    -- take over the middle of the screen (world mouseover, clicking nodes). So: hold
    -- Shift over the HUD and the minimap takes the mouse; let go and it's click-through.
    -- Synced on Shift changes, HUD on / off / move and combat end (Sol, 2026-11-07: a Shift
    -- already held when the HUD came on, or a release blocked in combat, stuck otherwise).
    local shiftMouse = false
    local function syncShift()
        local want = active and not moving and IsShiftKeyDown() and true or false
        if want == shiftMouse then return end
        if InCombatLockdown() and Minimap:IsProtected() then return end   -- retried when combat ends
        shiftMouse = want
        Minimap:EnableMouse(want)
    end
    H._syncShift = syncShift
    local mod = CreateFrame("Frame")
    mod:RegisterEvent("MODIFIER_STATE_CHANGED")
    mod:RegisterEvent("PLAYER_REGEN_ENABLED")
    mod:SetScript("OnEvent", syncShift)
    H._shiftOff = function()   -- giving the minimap back resets its mouse itself
        shiftMouse = false
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_LOGOUT")
    f:RegisterEvent("MINIMAP_UPDATE_ZOOM")   -- indoors / outdoors switches zoom without SetZoom
    f:RegisterEvent("UI_SCALE_CHANGED")
    f:RegisterEvent("DISPLAY_SIZE_CHANGED")
    f:SetScript("OnEvent", function(_, ev)
        if ev == "PLAYER_LOGOUT" then
            -- the minimap's rotation is a saved game setting: hand back your own
            -- (a /reload is a logout too; the HUD takes them again on the way back in)
            local own = active and saved and saved.own
            if own then
                SetCVar("rotateMinimap", own.rotate)
                if own.zoom then SetCVar("minimapZoom", own.zoom) end
                if own.inside then SetCVar("minimapInsideZoom", own.inside) end
            end
        elseif ev == "PLAYER_REGEN_ENABLED" then
            if pending ~= nil then H:Refresh() end
            if active then
                for obj, pts in pairs(fixLater) do
                    -- only if it still sits on the minimap
                    for i = 1, obj:GetNumPoints() do
                        if select(2, obj:GetPoint(i)) == Minimap then reanchor(obj, pts, true); break end
                    end
                end
            end
            wipe(fixLater)
        elseif ev == "MINIMAP_UPDATE_ZOOM" then
            if active and not zooming and Minimap:GetZoom() ~= 0 then
                zooming = true
                Minimap:SetZoom(0)
                zooming = false
            end
        elseif active then
            layout()
        end
    end)
    self:Refresh()
end

-- Key binding (Bindings.xml)
BINDING_HEADER_VOIDGATHER = "VoidGather"
BINDING_NAME_VOIDGATHER_HUD = "Gathering HUD on/off"
function VoidGather_ToggleHUD() H:Toggle() end

-- A switch in the Void hub's quick box (left-click the hub; VoidHubBundle.lua)
VoidHubToggles = VoidHubToggles or {}
table.insert(VoidHubToggles, {
    id = "VoidGather.hud", group = "Gathering", label = "Gathering HUD",
    tip = "The big see-through minimap with the game's herb and ore dots. Hold Shift over it to see what a dot is.",
    get = function() return VG:Config().hud end,
    set = function(on) H:SetShown(on and true or false) end,
})
