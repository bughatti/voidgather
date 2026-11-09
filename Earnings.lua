----------------------------------------------------------------------
-- VoidGather — Earnings: what your gathering is worth
--
-- The loot from every gather (and from fishing) is priced when you loot
-- it and added to the session: total, gold per hour of gathering, and a
-- split by kind, item and zone. Each zone keeps a running record, so
-- "/vg earn zones" tells you where your gathering pays best.
--
-- Price, from the first source that knows the item: VoidAH's scan data,
-- Auctionator, TSM, then the vendor price. Soulbound loot has none and
-- isn't counted.
--
-- Gathering time = the time between loots; a gap over 5 minutes (flying
-- home, a dungeon, AFK) isn't counted, so the hourly rate is for time
-- actually spent gathering. The session survives a /reload.
----------------------------------------------------------------------
-- Borders are one screen pixel (tools/cmd/pixelfix, 2026-11-09). WoW snaps each border
-- piece to the pixel grid, and a thin line on a fractional position can snap to 0 px: a side
-- of a box vanishes. VoidPX() asks for one real pixel, and the hook below (installed once, by
-- the first Void addon loaded) turns snapping off on the edges of flat WHITE8X8 borders, like
-- Blizzard's NineSliceUtil.DisableSharpening, so a 1 px line always covers a pixel.
local function VoidPX()
    local s = UIParent and UIParent:GetEffectiveScale()
    if s and s > 0 and PixelUtil and PixelUtil.GetPixelToUIUnitFactor then return PixelUtil.GetPixelToUIUnitFactor() / s end
    return 1
end
if not _G.__VoidBorderHook and hooksecurefunc and NineSliceUtil and NineSliceUtil.ApplyLayout then
    _G.__VoidBorderHook = true
    local EDGES = { "TopEdge", "BottomEdge", "LeftEdge", "RightEdge",
                    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner" }
    hooksecurefunc(NineSliceUtil, "ApplyLayout", function(c)
        local i = type(c) == "table" and c.backdropInfo
        local e = i and i.edgeFile
        if type(e) ~= "string" or not e:lower():find("white8x8", 1, true) or (tonumber(i.edgeSize) or 0) > 3 then return end
        for _, k in ipairs(EDGES) do
            local t = c[k]
            if t and t.SetSnapToPixelGrid then
                t:SetSnapToPixelGrid(false)
                t:SetTexelSnappingBias(0)
            end
        end
    end)
end
local ADDON, VG = ...
VG.Earn = {}
local E = VG.Earn

local GAP     = 300   -- seconds between loots that still count as gathering
local FIRST   = 30    -- seconds credited for the first loot after a gap
local RESUME  = 900   -- a session whose last loot is this recent carries over a /reload
local HISTORY = 50    -- finished sessions kept
local MIN_ACTIVE = 60 -- no hourly rate before a minute of gathering

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

E.EXTRA_KINDS = { fish = { label = "Fishing", icon = "Interface\\Icons\\Trade_Fishing" } }
E.KIND_ORDER  = { "mining", "herb", "skin", "lumber", "fish" }

function E.KindDef(k) return VG.KINDS[k] or E.EXTRA_KINDS[k] end

local function store()
    VoidGatherDB = VoidGatherDB or {}
    local e = VoidGatherDB.earn or {}
    VoidGatherDB.earn = e
    e.sessions = e.sessions or {}
    e.zones = e.zones or {}
    return e
end

local function newSession()
    return { start = time(), last = 0, active = 0, value = 0, unpriced = 0, kinds = {}, items = {}, zones = {} }
end

local archive

-- The current session; one whose last loot is over 15 minutes old is filed
-- under recent sessions and a new one starts (also when you stay logged in).
function E:Session()
    local e = store()
    local s = e.current
    if s and s.last > 0 and time() - s.last > RESUME then
        archive(s)
        s = nil
    end
    e.current = s or newSession()
    return e.current
end

----------------------------------------------------------------------
-- Money + rates
----------------------------------------------------------------------
local fmtNum = BreakUpLargeNumbers or tostring

function E.Money(c)
    c = math.floor(c or 0)
    if c >= 100000 then return fmtNum(math.floor(c / 10000)) .. "|cffffd700g|r" end
    if c >= 10000 then   -- under 10g the silver matters (1g 60s, not 1g)
        local s = math.floor(c % 10000 / 100)
        return math.floor(c / 10000) .. "|cffffd700g|r" .. (s > 0 and (" " .. s .. "|cffc7c7cfs|r") or "")
    end
    if c >= 100 then return math.floor(c / 100) .. "|cffc7c7cfs|r" end
    return c .. "|cffeda55fc|r"
end

-- copper per hour, or nil before a minute of gathering
function E.Rate(value, active)
    if not active or active < MIN_ACTIVE then return nil end
    return value * 3600 / active
end

local function minutes(sec) return math.floor((sec or 0) / 60 + 0.5) end

local function mapName(m)
    local info = m and C_Map.GetMapInfo(m)
    return info and info.name or "?"
end

----------------------------------------------------------------------
-- Prices
----------------------------------------------------------------------
function E:Price(id)
    local db = _G.VoidUIAuctionDB
    local realm = db and db[GetRealmName()]
    local entry = realm and realm[tostring(id)]
    if type(entry) == "table" and (entry.m or 0) > 0 then return entry.m, "VoidAH" end
    local A = _G.Auctionator
    if A and A.API and A.API.v1 and A.API.v1.GetAuctionPriceByItemID then
        local ok, p = pcall(A.API.v1.GetAuctionPriceByItemID, ADDON, id)
        if ok and type(p) == "number" and p > 0 then return p, "Auctionator" end
    end
    local T = _G.TSM_API
    if T and T.GetCustomPriceValue then
        local ok, p = pcall(T.GetCustomPriceValue, "dbmarket", "i:" .. id)
        if ok and type(p) == "number" and p > 0 then return p, "TSM" end
    end
    local sell = select(11, GetItemInfo(id))
    if sell and sell > 0 then return sell, "vendor" end
end

----------------------------------------------------------------------
-- One loot window from a gather or fishing: items = { {id, qty, link}, ... }
----------------------------------------------------------------------
function E:Loot(kind, items)
    if #items == 0 then return end
    local s = self:Session()
    local now = time()
    local dt = (s.last > 0 and now - s.last <= GAP) and (now - s.last) or FIRST
    s.last, s.active = now, s.active + dt
    local total = 0
    for _, it in ipairs(items) do
        VG.Goals:Gathered(it.id, kind)
        local p = self:Price(it.id)
        local v = (p or 0) * it.qty
        if not p then s.unpriced = s.unpriced + it.qty end
        local row = s.items[it.id] or { n = 0, v = 0, link = it.link, k = kind }
        row.n, row.v = row.n + it.qty, row.v + v
        s.items[it.id] = row
        total = total + v
    end
    s.value = s.value + total
    s.kinds[kind] = (s.kinds[kind] or 0) + total
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID then
        local z = s.zones[mapID] or { v = 0, a = 0 }
        z.v, z.a = z.v + total, z.a + dt
        s.zones[mapID] = z
        -- the zone's running record across sessions
        local life = store().zones
        local L = life[mapID] or { v = 0, a = 0, k = {} }
        L.v, L.a = L.v + total, L.a + dt
        L.k[kind] = (L.k[kind] or 0) + total
        life[mapID] = L
    end
    self:Update()
end

----------------------------------------------------------------------
-- Session start / end
----------------------------------------------------------------------
function archive(s)
    if not s or (s.value or 0) <= 0 then return end
    local best, bestV
    for m, z in pairs(s.zones) do
        if not bestV or z.v > bestV then best, bestV = m, z.v end
    end
    local list = store().sessions
    table.insert(list, 1, { start = s.start, stop = s.last, active = s.active, value = s.value,
                            kinds = s.kinds, map = best })
    while #list > HISTORY do table.remove(list) end
end

function E:Reset()
    local e = store()
    archive(e.current)
    e.current = newSession()
    self:Update()
end

----------------------------------------------------------------------
-- Chat output
----------------------------------------------------------------------
function E:SessionLine()
    local s = self:Session()
    if s.value <= 0 then return nil end
    local rate = E.Rate(s.value, s.active)
    return ("worth %s%s · %d min gathering"):format(E.Money(s.value),
        rate and (" · " .. E.Money(rate) .. "/hr") or "", minutes(s.active))
end

function E:PrintZones()
    local rows = {}
    for m, z in pairs(store().zones) do
        local rate = E.Rate(z.v, z.a)
        if rate and z.a >= 600 and z.v > 0 then rows[#rows + 1] = { m = m, rate = rate, z = z } end
    end
    table.sort(rows, function(a, b) return a.rate > b.rate end)
    if #rows == 0 then
        print(VG.PREFIX .. " no zone has 10 minutes of priced gathering yet.")
        return
    end
    print(VG.PREFIX .. " best gold per hour by zone (all your sessions):")
    for i, r in ipairs(rows) do
        if i > 8 then break end
        local topK, topV
        for k, v in pairs(r.z.k or {}) do
            if not topV or v > topV then topK, topV = k, v end
        end
        local def = topK and E.KindDef(topK)
        print(("  %s  %s/hr  |cff999999%d min%s|r"):format(mapName(r.m), E.Money(r.rate), minutes(r.z.a),
            def and (", mostly " .. def.label:lower()) or ""))
    end
end

function E:PrintHistory()
    self:Session()   -- files a session that went idle 15+ minutes ago
    local list = store().sessions
    if #list == 0 then
        print(VG.PREFIX .. " no finished sessions yet (a session ends with /vg reset, or 15 minutes after your last loot).")
        return
    end
    print(VG.PREFIX .. " recent sessions:")
    for i, s in ipairs(list) do
        if i > 10 then break end
        local rate = E.Rate(s.value, s.active)
        print(("  %s  %s%s  |cff999999%d min, %s|r"):format(date("%b %d %H:%M", s.start), E.Money(s.value),
            rate and (" (" .. E.Money(rate) .. "/hr)") or "", minutes(s.active), mapName(s.map)))
    end
end

----------------------------------------------------------------------
-- Earnings box: total, gold per hour; hover for the split, drag to move,
-- right-click for options. Ticked on (map menu or /vg earn) it stays on
-- screen, at 0g too, so it can be placed before the first gather.
----------------------------------------------------------------------
local bar

local function tooltip(f)
    local s = E:Session()
    GameTooltip:SetOwner(f, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("VoidGather — this session")
    local rate = E.Rate(s.value, s.active)
    GameTooltip:AddDoubleLine("Worth", E.Money(s.value), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Per hour of gathering", rate and E.Money(rate) or "—", 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine("Time gathering", minutes(s.active) .. " min", 0.8, 0.8, 0.8, 1, 1, 1)
    local kinds = {}
    for _, k in ipairs(E.KIND_ORDER) do
        if (s.kinds[k] or 0) > 0 then kinds[#kinds + 1] = k end
    end
    if #kinds > 1 then
        GameTooltip:AddLine(" ")
        for _, k in ipairs(kinds) do
            local def = E.KindDef(k)
            GameTooltip:AddDoubleLine(("|T%s:14|t %s"):format(def.icon, def.label), E.Money(s.kinds[k]),
                0.8, 0.8, 0.8, 1, 1, 1)
        end
    end
    local ids = {}
    for id, row in pairs(s.items) do
        if row.v > 0 then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b) return s.items[a].v > s.items[b].v end)
    if #ids > 0 then
        GameTooltip:AddLine(" ")
        -- crafted instead (Craft.lua): green = what it would be worth as the best recipe
        local upTo, anyBetter = 0, false
        for i, id in ipairs(ids) do
            local row = s.items[id]
            local best = VG.Craft:Best(id)
            upTo = upTo + (best and best.value * row.n or row.v)
            anyBetter = anyBetter or best ~= nil
            if i <= 8 then
                local right = E.Money(row.v)
                if best then
                    right = right .. ("  |cff55ff55%s as %s|r"):format(E.Money(best.value * row.n), best.name)
                end
                GameTooltip:AddDoubleLine(("%s x%d"):format(row.link or ("item " .. id), row.n), right,
                    1, 1, 1, 1, 1, 1)
            elseif i == 9 then
                GameTooltip:AddLine(("…and %d more"):format(#ids - 8), 0.6, 0.6, 0.6)
            end
        end
        if anyBetter and upTo > s.value then
            GameTooltip:AddDoubleLine("Worth up to, crafted", E.Money(upTo), 0.33, 1, 0.33, 0.33, 1, 0.33)
        end
    end
    if s.unpriced > 0 then
        GameTooltip:AddLine(("%d item%s with no price (soulbound, or not seen at auction yet)"):format(
            s.unpriced, s.unpriced == 1 and "" or "s"), 0.6, 0.6, 0.6, true)
    end
    VG.Goals:AddBoxTooltip(GameTooltip)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Drag to move · right-click for options", 0.4, 0.8, 1)
    GameTooltip:Show()
end

local function menu(f)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    MenuUtil.CreateContextMenu(f, function(_, root)
        root:CreateTitle("VoidGather earnings")
        root:CreateButton("Start a new session", function() E:Reset() end)
        root:CreateButton("Best zones (chat)", function() E:PrintZones() end)
        root:CreateButton("Recent sessions (chat)", function() E:PrintHistory() end)
        root:CreateButton("Hide the box", function() E:SetShown(false) end)
    end)
end

local function buildBar()
    local cfg = VG:Config()
    local f = CreateFrame("Button", "VoidGatherEarnBar", UIParent, "BackdropTemplate")
    f:SetSize(150, 34)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = VoidPX() })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.8)
    f:SetBackdropBorderColor(0, 0.78, 1, 0.45)
    local p = cfg.earnPos
    if p then f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else f:SetPoint("TOP", UIParent, "TOP", 0, -160) end
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:RegisterForClicks("RightButtonUp")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local pt, _, rel, x, y = self:GetPoint()
        cfg.earnPos = { pt, rel, x, y }
    end)
    f:SetScript("OnClick", menu)
    f:SetScript("OnEnter", tooltip)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.top = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.top:SetPoint("TOP", 0, -4)
    f.bottom = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.bottom:SetPoint("TOP", f.top, "BOTTOM", 0, -3)
    f.goals = {}   -- crafting-goal lines under the totals (Goals.lua)
    f:Hide()
    return f
end

local GOAL_LINES = 10

-- Crafting goals: the materials still missing. Returns the widest line.
local function goalLines(f)
    local lines = VG.Goals:BoxLines()
    local widest = 0
    for i = 1, math.max(#f.goals, math.min(#lines, GOAL_LINES + 1)) do
        local fs = f.goals[i]
        local str = lines[i]
        if i == GOAL_LINES + 1 and #lines > GOAL_LINES then str = ("|cff8c8c9e…and %d more|r"):format(#lines - GOAL_LINES) end
        if i > GOAL_LINES + 1 then str = nil end
        if str and not fs then
            fs = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("TOPLEFT", 10, -34 - (i - 1) * 14)
            fs:SetJustifyH("LEFT")
            f.goals[i] = fs
        end
        if fs then
            fs:SetText(str or "")
            fs:SetShown(str ~= nil)
            if str then widest = math.max(widest, fs:GetStringWidth()) end
        end
    end
    local shown = math.min(#lines, GOAL_LINES + 1)
    f:SetHeight(34 + (shown > 0 and shown * 14 + 4 or 0))
    return widest
end

function E:Update()
    local cfg = VG:Config()
    local s = self:Session()
    if not cfg.showEarn then
        if bar then bar:Hide() end
        return
    end
    bar = bar or buildBar()
    local rate = E.Rate(s.value, s.active)
    bar.top:SetText(E.Money(s.value))
    bar.bottom:SetText((rate and (E.Money(rate) .. "/hr") or "—/hr") .. ("  ·  %d min"):format(minutes(s.active)))
    local goals = goalLines(bar)
    bar:SetWidth(math.max(120, bar.bottom:GetStringWidth() + 24, bar.top:GetStringWidth() + 24, goals + 20))
    bar:Show()
end

function E:SetShown(on)
    VG:Config().showEarn = on
    self:Update()
    print(VG.PREFIX .. " earnings box " .. (on and "|cff33ff33on|r (drag it anywhere)" or "|cffff5555off|r"))
end

function E:Init()
    -- a session from before a /reload or a short disconnect carries on
    -- (Session() files an older one under recent sessions)
    self:Update()
end
