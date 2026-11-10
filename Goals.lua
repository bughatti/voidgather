----------------------------------------------------------------------
-- VoidGather — Goals: gathering for your own crafters
--
-- When a character opens one of its profession windows, the recipes from
-- CraftData.lua it has learned are saved (the game only tells a character
-- its own recipes). Then, on any of your characters:
--   - a material's tooltip names who crafts what from it;
--   - a goal ("5 Harandar Celebration on Vede", set in that recipe's
--     profession window or in the settings window) puts the materials
--     still missing in the earnings box, gathered ones first: "Azeroot 9/15".
-- A line leaves the box once you have enough, and the goal counts down as
-- the crafter crafts it, so the list clears itself.
--
-- Counted: this character's bags + bank, the warband bank, and what each of
-- your other characters held the last time you played it (saved as bags
-- change; before that, VoidBags' record of its bags if you have VoidBags).
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
VG.Goals = {}
local G = VG.Goals

local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetItemNameByID = (C_Item and C_Item.GetItemNameByID) or function() end

local AMOUNTS = { 1, 2, 3, 5, 10, 20 }
-- Trade goods (class 7) a gatherer brings in: leather, metal & stone, herb, elemental.
-- Plus anything that ever came out of one of your gathers (fish, motes, ...).
local GATHERED_SUB = { [6] = true, [7] = true, [9] = true, [10] = true }

local function store()
    VoidGatherDB = VoidGatherDB or {}
    local d = VoidGatherDB
    d.crafters = d.crafters or {}   -- ["Name-Realm"] = { class, t, recipes = { [spellID] = true } }
    d.goals = d.goals or {}         -- ["Name-Realm"] = { [recipe name] = crafts left }
    d.stock = d.stock or {}         -- ["Name-Realm"] = { [itemID] = bags + bank }, saved at logout
    d.stockVer = d.stockVer or {}   -- ["Name-Realm"] = STOCK_VER of that count (Goals.heldBy)
    d.gathered = d.gathered or {}   -- [itemID] = kind, every item a gather gave you
    return d
end

local me
local function myKey()
    if not me then
        local name = UnitName("player")
        local realm = GetNormalizedRealmName and GetNormalizedRealmName()
        if not (name and realm and realm ~= "") then return nil end
        me = name .. "-" .. realm
    end
    return me
end
G.MyKey = myKey

local bySpell, byName, made, allMats
local function index()
    if bySpell then return end
    bySpell, byName, made, allMats = {}, {}, {}, {}
    for _, r in ipairs(VG.CRAFT or {}) do
        bySpell[r[1]] = r
        byName[r[2]] = byName[r[2]] or r
        for _, id in ipairs(r.makes.ids) do made[id] = true end   -- bars, leather: crafted, not gathered
        for _, m in ipairs(r.mats) do
            for _, id in ipairs(m.ids) do allMats[id] = true end
        end
    end
end

-- The recipe behind a goal: a rank the crafter learned, else any rank.
local function recipeFor(key, name)
    index()
    local c = store().crafters[key]
    if c then
        for spell in pairs(c.recipes) do
            local r = bySpell[spell]
            if r and r[2] == name then return r end
        end
    end
    return byName[name]
end

-- How many of item `id` one craft of recipe `r` takes (nil = none).
local function takes(r, id)
    for _, m in ipairs(r.mats) do
        for _, mid in ipairs(m.ids) do
            if mid == id then return m.n end
        end
    end
end

-- "Vede" in class color ("Vede-OtherRealm" when it's from another realm).
function G:Who(key)
    local name, realm = key:match("^([^%-]+)%-(.+)$")
    local shown = (realm and realm == (GetNormalizedRealmName and GetNormalizedRealmName())) and name or key
    local c = store().crafters[key]
    local color = c and c.class and C_ClassColor and C_ClassColor.GetClassColor(c.class)
    return color and color:WrapTextInColorCode(shown) or shown
end

----------------------------------------------------------------------
-- Saving recipes: profession window open on your own profession
----------------------------------------------------------------------
-- A linked, guild or NPC profession answers for someone else, not you.
local function external()
    local T = C_TradeSkillUI
    return T and ((T.IsTradeSkillLinked and T.IsTradeSkillLinked())
        or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
        or (T.IsTradeSkillGuildMember and T.IsTradeSkillGuildMember())
        or (T.IsNPCCrafting and T.IsNPCCrafting()))
end

local function record()
    local T = C_TradeSkillUI
    local key = myKey()
    if not (key and T and T.GetBaseProfessionInfo and T.GetRecipeInfo) or external() then return end
    local base = T.GetBaseProfessionInfo()
    local child = T.GetChildProfessionInfo and T.GetChildProfessionInfo()
    local line, parent = base and base.professionID, child and child.parentProfessionID
    if not (line and line > 0) and not parent then return end
    local d = store()
    local c = d.crafters[key] or { recipes = {} }
    d.crafters[key] = c
    c.class = select(2, UnitClass("player"))
    c.t = time()
    local changed = false
    for _, r in ipairs(VG.CRAFT or {}) do
        if r[3] == line or r[3] == parent then
            local info = T.GetRecipeInfo(r[1])
            if info then
                local now = info.learned and true or nil
                if c.recipes[r[1]] ~= now then
                    c.recipes[r[1]] = now
                    changed = true
                end
            end
        end
    end
    if changed then G:Changed() end
end

----------------------------------------------------------------------
-- Counting what you have
----------------------------------------------------------------------
local function count(id, warband)
    return GetItemCount(id, true, false, true, warband) or 0
end

-- Your characters' bags as VoidBags last saw them: ["Name-Realm"] =
-- { [itemID] = count }. Rebuilt every few seconds.
local vbByChar, vbTime
local function voidBags()
    if vbByChar and GetTime() - vbTime < 5 then return vbByChar end
    vbByChar, vbTime = {}, GetTime()
    local chars = type(_G.VoidBagsDB) == "table" and type(VoidBagsDB.characters) == "table" and VoidBagsDB.characters
    if not chars then return vbByChar end
    index()
    for _, c in pairs(chars) do
        local k = type(c) == "table" and c.displayKey
        if k and type(c.bags) == "table" then
            local t = {}
            for _, it in pairs(c.bags) do
                if type(it) == "table" and type(it.id) == "number" and allMats[it.id] then
                    t[it.id] = (t[it.id] or 0) + (tonumber(it.count) or 1)
                end
            end
            vbByChar[k] = t
        end
    end
    return vbByChar
end

-- What another character holds of `ids`: its bags + bank as VoidGather last
-- counted them -- once that count covers every profession's materials
-- (STOCK_VER, 2026-11-03) -- else its bags as VoidBags saw them, else the
-- older count. One source per character: taking the larger of two per item
-- added a stale count to a fresh one (Codex Sol, 2026-11-03).
local STOCK_VER = 2
local function heldBy(k, ids)
    local d = store()
    local s, vb = d.stock[k], voidBags()[k]
    local src = s
    if not (s and d.stockVer[k] == STOCK_VER) and vb then src = vb end
    local n = 0
    for _, id in ipairs(ids) do n = n + (src and src[id] or 0) end
    return n
end

local function others()
    local keys, key = {}, myKey()
    for k in pairs(store().stock) do keys[k] = true end
    for k in pairs(voidBags()) do keys[k] = true end
    keys[key or ""] = nil
    return keys
end

local function sum(ids, warband)
    local n = 0
    for _, id in ipairs(ids) do n = n + count(id, warband) end
    return n
end

-- All your characters: this one live (bags, bank, warband bank) + the others.
function G:Have(ids)
    local n = sum(ids, true)
    for k in pairs(others()) do n = n + heldBy(k, ids) end
    return n
end

-- Where you hold `ids`: { here = this character's bags + bank, warband =
-- the warband bank, ["Name-Realm"] = another character's last count }.
-- VoidAH's leveling plan uses it to take what you own off the shopping list.
function G:Where(ids)
    -- Forever: only Midnight materials are counted for alts, so this answered 0 for them;
    -- nil makes VoidProf's planner (Planner.lua Owned) fall back to its own count
    -- (Forever audit, 2026-11-10)
    if VG.IS_FOREVER then return nil end
    local here = sum(ids, false)
    local out = { here = here, warband = sum(ids, true) - here }
    for k in pairs(others()) do
        local n = heldBy(k, ids)
        if n > 0 then out[k] = n end
    end
    return out
end

-- How short each crafter still is of one material (needBy = { [key] = n }):
-- its own bags + bank first, then the warband bank, shared out ONCE across
-- the crafters (not credited to each of them in full).
local function shortages(ids, needBy)
    local key = myKey()
    local wb = sum(ids, true) - sum(ids, false)
    local keys = {}
    for k in pairs(needBy) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do
        local own = (k == key) and sum(ids, false) or heldBy(k, ids)
        local short = math.max(0, needBy[k] - own)
        local use = math.min(wb, short)
        wb = wb - use
        out[k] = short - use
    end
    return out
end

-- What this character holds (bags + bank) of every material any recipe
-- uses, so a goal set later on another character counts it too. Saved on
-- every bag change (the game batches those): at logout it already reports 0
-- for everything, so a deposit right before logging out must be saved by then.
local function saveStock()
    local key = myKey()
    if not key then return end
    index()
    local s = {}
    for id in pairs(allMats) do
        local n = count(id, false)
        if n > 0 then s[id] = n end
    end
    store().stock[key] = s
    store().stockVer[key] = STOCK_VER
end

-- A dropped profession takes its saved recipes with it. `loaded` = the
-- profession list is known to be loaded (SKILL_LINES_CHANGED), so an empty
-- one means no professions at all, not "not loaded yet".
-- Each character's skill per profession (base skill line), saved at login: a
-- profession it has never leveled (a rogue at Cooking 1/100) doesn't count as
-- one it crafts with, for its own deposits or for others' (2026-11-04).
local function saveSkills()
    local key = myKey()
    if not (key and GetProfessions and GetProfessionInfo) then return end
    local d = store()
    local c = d.crafters[key] or { recipes = {} }
    d.crafters[key] = c
    c.class = c.class or select(2, UnitClass("player"))
    c.skills = {}
    for _, idx in pairs({ GetProfessions() }) do
        local _, _, rank, _, _, _, line = GetProfessionInfo(idx)
        if line then c.skills[line] = rank or 0 end
    end
end
G.SaveSkills = saveSkills

-- Does character `k` really use profession `line`? Unknown skill: yes.
local function leveled(k, line)
    local c = k and store().crafters[k]
    local s = c and c.skills and c.skills[line]
    return s == nil or s > 1
end

local function prune(loaded)
    local key = myKey()
    local c = key and store().crafters[key]
    if not (c and GetProfessions and GetProfessionInfo) then return end
    local lines, any = {}, false
    for _, idx in pairs({ GetProfessions() }) do
        local line = idx and select(7, GetProfessionInfo(idx))
        if line then lines[line] = true; any = true end
    end
    if not any and not loaded then return end
    index()
    local changed = false
    for spell in pairs(c.recipes) do
        local r = bySpell[spell]
        if not (r and lines[r[3]]) then
            c.recipes[spell] = nil
            changed = true
        end
    end
    if changed then G:Changed() end
end

function G:Gathered(id, kind)
    if id then store().gathered[id] = kind end
end

function G:Gatherable(ids)
    local d = store()
    index()
    for _, id in ipairs(ids) do
        if d.gathered[id] then return true end
        local _, _, _, _, _, classID, sub = GetItemInfoInstant(id)
        if classID == 7 and GATHERED_SUB[sub] and not made[id] then return true end
    end
    return false
end

----------------------------------------------------------------------
-- Goals
----------------------------------------------------------------------
function G:Get(key, name)
    local list = key and store().goals[key]
    return list and list[name]
end

function G:Set(key, name, n)
    if not (key and name) then return end
    local goals = store().goals
    n = math.max(0, math.floor(n or 0))
    goals[key] = goals[key] or {}
    goals[key][name] = n > 0 and n or nil
    if not next(goals[key]) then goals[key] = nil end
    if key == myKey() then saveStock() end
    G:Changed()
end

-- { { key, name, n, recipe }, ... }: yours first, then by name.
function G:List()
    local out, key = {}, myKey()
    for k, list in pairs(store().goals) do
        for name, n in pairs(list) do
            local r = recipeFor(k, name)
            if r then out[#out + 1] = { key = k, name = name, n = n, recipe = r } end
        end
    end
    table.sort(out, function(a, b)
        if (a.key == key) ~= (b.key == key) then return a.key == key end
        if a.key ~= b.key then return a.key < b.key end
        return a.name < b.name
    end)
    return out
end

function G:Any() return next(store().goals) ~= nil end

-- One goal's materials: { { ids, need, have, gathered }, ... }
function G:Mats(g)
    local rows = {}
    for _, m in ipairs(g.recipe.mats) do
        rows[#rows + 1] = { ids = m.ids, need = g.n * m.n, have = self:Have(m.ids), gathered = self:Gatherable(m.ids) }
    end
    return rows
end

local function itemName(id)
    return GetItemNameByID(id) or ("item " .. id)
end

local function icon(id)
    local tex = select(5, GetItemInfoInstant(id))
    return tex and ("|T%s:12:12:0:0:64:64:6:58:6:58|t "):format(tex) or ""
end

-- Earnings box lines, per material over all goals (two goals sharing one
-- add their need up), gathered ones first:
--   short overall           "Azeroot 9/15"                  gather or buy more
--   the crafter is you      "Plant Protein 5/200 here (+214 on your other characters)"
--   another crafter         "Send Vede: Plant Protein x106" (from this character)
-- then the goals whose crafter can reach everything: "all in, craft on Vede".
function G:BoxLines()
    local lines, byId, rows, used = {}, {}, {}, {}
    local key = myKey()
    local list = self:List()
    for gi, g in ipairs(list) do
        used[gi] = {}
        for _, m in ipairs(g.recipe.mats) do
            local id = m.ids[1]
            local row = byId[id]
            if not row then
                row = { id = id, ids = m.ids, need = 0, needBy = {}, have = self:Have(m.ids),
                        gathered = self:Gatherable(m.ids), order = #rows }
                byId[id] = row
                rows[#rows + 1] = row
            end
            row.need = row.need + g.n * m.n
            row.needBy[g.key] = (row.needBy[g.key] or 0) + g.n * m.n
            used[gi][#used[gi] + 1] = row
        end
    end
    table.sort(rows, function(a, b)
        if a.gathered ~= b.gathered then return a.gathered end
        return a.order < b.order
    end)
    local name
    for _, row in ipairs(rows) do
        row.short = shortages(row.ids, row.needBy)
        name = icon(row.id) .. itemName(row.id)
        if row.have < row.need then
            lines[#lines + 1] = ("%s  |cffffffff%d/%d|r"):format(name, row.have, row.need)
        else
            for k, need in pairs(row.needBy) do
                local short = row.short[k]
                if short > 0 then
                    if k == key then
                        lines[#lines + 1] = ("%s  |cffffffff%d/%d|r here |cff8c8c9e(+%d on your other characters)|r"):format(
                            name, need - short, need, row.have - (need - short))
                    else
                        local mine = sum(row.ids, false)
                        if mine > 0 then
                            lines[#lines + 1] = ("Send %s: %s x%d"):format(self:Who(k), name, math.min(mine, short))
                        else
                            lines[#lines + 1] = ("|cff8c8c9e%s needs %d more %s from your other characters|r"):format(
                                self:Who(k), short, itemName(row.id))
                        end
                    end
                end
            end
        end
    end
    for gi, g in ipairs(list) do
        local ready = true
        for _, row in ipairs(used[gi]) do
            if row.have < row.need or row.short[g.key] > 0 then ready = false end
        end
        if ready then
            lines[#lines + 1] = ("|cff55ff55%s x%d: all in, craft on|r %s"):format(g.name, g.n, self:Who(g.key))
        end
    end
    return lines
end

-- For VoidBags' warband bank view: what in this character's bags another of
-- your characters crafts with. First the crafting goals' shortfalls (exact
-- counts), then everything else a recipe they know takes, all of it: the user
-- asked (2026-11-03) for "all items any crafting needs", not just goals.
-- Only what the warband bank accepts (not soulbound).
-- { { id, ids, count, key }, ... }, one material split over two crafters
-- never promises the same items twice.
-- Herbs that mill into a pigment (same table as VoidProf's Planner.lua): an
-- inscriber with an ink recipe uses the herbs too, though no recipe lists them.
local MILLED_FROM = {
    [245807] = { 236761, 236767 }, [245808] = { 236761, 236767 },   -- Tranquility Bloom
    [245803] = { 236776, 236777 }, [245804] = { 236776, 236777 },   -- Argentleaf
    [245865] = { 236770, 236771 }, [245864] = { 236770, 236771 },   -- Sanguithorn
    [245867] = { 236778, 236779 }, [245866] = { 236778, 236779 },   -- Mana Lily
}
local millHerb = {}
for _, herbs in pairs(MILLED_FROM) do for _, id in ipairs(herbs) do millHerb[id] = true end end
-- What disenchanting gives (Eversinging Dust, Radiant Shard, Dawn Crystal, both
-- ranks): always deposited, so it pools for the enchanter you level, even from
-- a character that enchants too (the user's pick, 2026-11-03).
local DE_MATS = { [243599] = true, [243600] = true, [243602] = true, [243603] = true,
                  [243605] = true, [243606] = true }

-- Only crafting materials move: trade goods (herbs, ore, cloth, dust, inks...) and
-- reagents. Not potions, food or gear a recipe happens to take (a cauldron takes
-- potions: health potions showed up to deposit, 2026-11-04).
local function isMaterial(id)
    local classID = select(6, GetItemInfoInstant(id))
    return classID == 7 or classID == 5
end

-- Every material this character's own professions craft with (+ herbs it mills).
local function ownUseSet()
    index()
    local mine = {}
    for _, idx in pairs({ GetProfessions() }) do
        local _, _, rank, _, _, _, line = GetProfessionInfo(idx)
        if line and (rank or 0) > 1 then mine[line] = true end   -- never leveled: not yours to keep for
    end
    local own = {}
    for _, r in ipairs(VG.CRAFT or {}) do
        if mine[r[3]] then
            for _, m in ipairs(r.mats) do
                for _, id in ipairs(m.ids) do
                    own[id] = true
                    for _, herb in ipairs(MILLED_FROM[id] or {}) do own[herb] = true end
                end
            end
        end
    end
    return own
end

-- The other way round, for VoidBags' "Take my materials": what in the warband
-- bank this character crafts with, so a deposit from another character (or
-- the old deposit-everything) comes back in one click. Leaves disenchanting
-- materials (they pool for your enchanter) and anything another character's
-- crafting goal still needs. { [itemID] = count in the warband bank }; empty
-- while the warband bank can't be read.
function G:ToTake()
    local out = {}
    local account = Enum and Enum.BankType and Enum.BankType.Account
    if not (account and C_Bank and C_Bank.CanViewBank and C_Bank.CanViewBank(account)) then return out end
    local own, key = ownUseSet(), myKey()
    -- disenchanting materials stay in the warband bank for the enchanter, so the
    -- enchanter itself takes them (Murrath got 7 items and no dust, 2026-11-04)
    local enchants = false
    for _, idx in pairs({ GetProfessions() }) do
        if idx and select(7, GetProfessionInfo(idx)) == 333 then enchants = true end
    end
    local held = {}
    for _, g in ipairs(self:List()) do
        if g.key ~= key then
            for _, m in ipairs(g.recipe.mats) do
                for _, id in ipairs(m.ids) do held[id] = true end
            end
        end
    end
    for _, tab in ipairs(C_Bank.FetchPurchasedBankTabData(account) or {}) do
        for slot = 1, C_Container.GetContainerNumSlots(tab.ID) or 0 do
            local info = C_Container.GetContainerItemInfo(tab.ID, slot)
            local id = info and info.itemID
            if id and own[id] and (enchants or not DE_MATS[id]) and not held[id] and isMaterial(id) then
                out[id] = (out[id] or 0) + (info.stackCount or 1)
            end
        end
    end
    return out
end

function G:ToDeposit()
    index()
    local key, mats, out = myKey(), {}, {}
    -- what can go in the warband bank, per item, from the bags
    local canGo = {}
    local bankType = Enum and Enum.BankType and Enum.BankType.Account
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and (allMats[info.itemID] or millHerb[info.itemID]) and isMaterial(info.itemID) then
                local ok = true
                if bankType and C_Bank and C_Bank.IsItemAllowedInBankType then
                    ok = C_Bank.IsItemAllowedInBankType(bankType, ItemLocation:CreateFromBagAndSlot(bag, slot))
                end
                if ok then canGo[info.itemID] = (canGo[info.itemID] or 0) + (info.stackCount or 1) end
            end
        end
    end
    -- Your other characters' professions (base skill line): from the recipes
    -- saved here, and VoidBags' record of every character's professions. A
    -- profession counts for all its recipes' materials, learned or not yet
    -- (Dawn Crystals before the enchanter knows a recipe that takes them).
    local profsOf = {}
    local function addProf(k, line)
        if k and k ~= key and type(line) == "number" and leveled(k, line) then
            profsOf[k] = profsOf[k] or {}
            profsOf[k][line] = true
        end
    end
    for k, c in pairs(store().crafters) do
        for spell in pairs(c.recipes) do addProf(k, bySpell[spell] and bySpell[spell][3]) end
    end
    local chars = type(_G.VoidBagsDB) == "table" and type(VoidBagsDB.characters) == "table" and VoidBagsDB.characters
    for _, c in pairs(chars or {}) do
        if type(c) == "table" and type(c.professions) == "table" and type(c.displayKey) == "string" then
            -- VoidBags keys by GetRealmName ("Laughing Skull"); ours is normalized
            local name, realm = c.displayKey:match("^([^%-]+)%-(.+)$")
            local k = name and (name .. "-" .. realm:gsub("[%s%-]", ""))
            for line in pairs(c.professions) do addProf(k, line) end
        end
    end
    -- item -> every one of those characters whose profession takes it ({ [key] = true })
    local users = {}
    local function use(id, k)
        users[id] = users[id] or {}
        users[id][k] = true
    end
    for _, r in ipairs(VG.CRAFT or {}) do
        for k, lines in pairs(profsOf) do
            if lines[r[3]] then
                for _, m in ipairs(r.mats) do
                    for _, id in ipairs(m.ids) do
                        use(id, k)
                        for _, herb in ipairs(MILLED_FROM[id] or {}) do use(herb, k) end
                    end
                end
            end
        end
    end
    -- What this character crafts with itself stays in its bags: depositing
    -- everything sent Vede's own herbs and cooking ingredients away (11-03).
    local ownUse = ownUseSet()
    -- sorted list: keys[1] is shown first, all of them are named; nil = keep it
    local function usersOf(id)
        if not users[id] or (ownUse[id] and not DE_MATS[id]) then return nil end
        local l = {}
        for k in pairs(users[id]) do l[#l + 1] = k end
        table.sort(l)
        return l
    end
    local seen = {}
    -- per material, every crafter's need (yours too: it shares the warband bank)
    for _, g in ipairs(self:List()) do
        for _, m in ipairs(g.recipe.mats) do
            local e = mats[m.ids[1]] or { ids = m.ids, needBy = {} }
            e.needBy[g.key] = (e.needBy[g.key] or 0) + g.n * m.n
            mats[m.ids[1]] = e
        end
    end
    for id, e in pairs(mats) do
        local left = 0
        for _, mid in ipairs(e.ids) do
            left = left + (canGo[mid] or 0)
            seen[mid] = true
        end
        local short = shortages(e.ids, e.needBy)
        local keys = {}
        for k in pairs(short) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local n = math.min(short[k], left)
            if k ~= key and n > 0 then
                left = left - n
                out[#out + 1] = { id = id, ids = e.ids, count = n, key = k, goal = true }
            end
        end
        -- the rest of it, when another character crafts with it anyway
        local other = usersOf(id)
        if left > 0 and other then
            out[#out + 1] = { id = id, ids = e.ids, count = left, key = other[1], keys = other }
        end
    end
    -- everything else your other characters craft with
    for id, n in pairs(canGo) do
        local other = not seen[id] and usersOf(id)
        if other then
            out[#out + 1] = { id = id, ids = { id }, count = n, key = other[1], keys = other }
        end
    end
    table.sort(out, function(a, b)
        if (a.goal or false) ~= (b.goal or false) then return a.goal == true end   -- goals first
        if a.key ~= b.key then return a.key < b.key end
        return a.id < b.id
    end)
    return out
end

function G:AddBoxTooltip(tt)
    local list = self:List()
    if #list == 0 then return end
    tt:AddLine(" ")
    tt:AddLine("Crafting goals", 0, 0.78, 1)
    for _, g in ipairs(list) do
        tt:AddDoubleLine(("%s x%d"):format(g.name, g.n), self:Who(g.key), 1, 1, 1, 1, 1, 1)
        for _, m in ipairs(self:Mats(g)) do
            local done = m.have >= m.need
            tt:AddDoubleLine("   " .. icon(m.ids[1]) .. itemName(m.ids[1]),
                ("%d/%d"):format(m.have, m.need), 0.8, 0.8, 0.8, done and 0.33 or 1, 1, done and 0.33 or 1)
        end
    end
end

----------------------------------------------------------------------
-- Tooltip: who of yours crafts what from this item
----------------------------------------------------------------------
function G:Users(id)
    index()
    local out, key = {}, myKey()
    for k, c in pairs(store().crafters) do
        local seen = {}
        for spell in pairs(c.recipes) do
            local r = bySpell[spell]
            local n = r and not seen[r[2]] and takes(r, id)
            if n then
                seen[r[2]] = true
                out[#out + 1] = { key = k, name = r[2], n = n, goal = self:Get(k, r[2]) }
            end
        end
    end
    table.sort(out, function(a, b)
        if (a.goal ~= nil) ~= (b.goal ~= nil) then return a.goal ~= nil end
        if (a.key == key) ~= (b.key == key) then return a.key == key end
        if a.key ~= b.key then return a.key < b.key end
        return a.name < b.name
    end)
    return out
end

function G:AddTooltip(tt, users, id)
    if #users == 0 then return end
    tt:AddLine("Your crafters", 0, 0.78, 1)
    for i, u in ipairs(users) do
        if i > 5 then
            tt:AddLine(("…and %d more"):format(#users - 5), 0.6, 0.6, 0.6)
            break
        end
        local right = ("%d each"):format(u.n)
        if u.goal then
            local r = recipeFor(u.key, u.name)
            local ids = { id }
            for _, m in ipairs(r and r.mats or {}) do
                for _, mid in ipairs(m.ids) do
                    if mid == id then ids = m.ids end
                end
            end
            right = ("goal %d: %d/%d"):format(u.goal, self:Have(ids), u.goal * u.n)
        end
        tt:AddDoubleLine(("%s: %s"):format(self:Who(u.key), u.name), right, 0.8, 0.8, 0.8, 1, 1, 1)
    end
end

----------------------------------------------------------------------
-- Menus: pick a goal (settings window), set one (profession window)
----------------------------------------------------------------------
local function amounts(menu, key, name)
    local cur = G:Get(key, name)
    for _, n in ipairs(AMOUNTS) do
        menu:CreateButton((n == cur and "|cff00c7ff%d crafts|r" or "%d crafts"):format(n),
            function() G:Set(key, name, n) end)
    end
    if cur then menu:CreateButton("|cffff5555Clear the goal|r", function() G:Set(key, name, 0) end) end
end

function G:AddMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
    index()
    local key = myKey()
    local keys = {}
    for k in pairs(store().crafters) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if (a == key) ~= (b == key) then return a == key end
        return a < b
    end)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Add a crafting goal")
        local any = false
        for _, k in ipairs(keys) do
            local names, seen = {}, {}
            for spell in pairs(store().crafters[k].recipes) do
                local r = bySpell[spell]
                if r and not seen[r[2]] then
                    seen[r[2]] = r
                    names[#names + 1] = r[2]
                end
            end
            table.sort(names)
            if #names > 0 then
                any = true
                local sub = root:CreateButton(("%s  |cff8c8c9e%d recipes|r"):format(self:Who(k), #names))
                if sub.SetScrollMode then sub:SetScrollMode(420) end
                for _, name in ipairs(names) do
                    local prof = VG.CRAFT_PROFS[seen[name][3]] or ""
                    amounts(sub:CreateButton(("%s  |cff8c8c9e%s|r"):format(name, prof)), k, name)
                end
            end
        end
        if not any then
            root:CreateTitle("|cff8c8c9eNo recipes saved yet: open a profession|r")
            root:CreateTitle("|cff8c8c9ewindow once on each character.|r")
        end
    end)
end

-- Profession window: "Crafting goal" button under Track Recipe, for every
-- recipe in CraftData (all professions: inks and enchants too, not just the
-- ones made from gathered materials).
local profBtn

local function selected()
    local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
    local form = page and page.SchematicForm
    local info = form and form.GetRecipeInfo and form:GetRecipeInfo()
    if not info then return end
    index()
    return bySpell[info.recipeID] or (info.name and byName[info.name]), form
end

local function profTooltip(self)
    local key, r = myKey(), self.recipe
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("VoidGather crafting goal", 1, 1, 1)
    GameTooltip:AddLine("How many you want to craft. The materials still missing show in the "
        .. "earnings box on all your characters, and the goal counts down as you craft.", 0.8, 0.8, 0.8, true)
    local n = r and G:Get(key, r[2])
    if n then
        for _, m in ipairs(G:Mats({ n = n, recipe = r })) do
            GameTooltip:AddDoubleLine(icon(m.ids[1]) .. itemName(m.ids[1]), ("%d/%d"):format(m.have, m.need),
                0.8, 0.8, 0.8, 1, 1, 1)
        end
    end
    GameTooltip:Show()
end

local function updateProf()
    local r, form = selected()
    if not r or external() then
        if profBtn then profBtn:Hide() end
        return
    end
    if not profBtn then
        local b = CreateFrame("Button", nil, form, "BackdropTemplate")
        b:SetHeight(20)
        b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = VoidPX() })
        b:SetBackdropColor(0.10, 0.12, 0.15, 0.95)
        b:SetBackdropBorderColor(0, 0.78, 1, 0.6)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("CENTER")
        b:SetScript("OnClick", function(self)
            if self.recipe and MenuUtil and MenuUtil.CreateContextMenu then
                MenuUtil.CreateContextMenu(self, function(_, root)
                    root:CreateTitle(self.recipe[2])
                    amounts(root, myKey(), self.recipe[2])
                end)
            end
        end)
        b:SetScript("OnEnter", profTooltip)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        profBtn = b
    end
    profBtn:SetParent(form)
    profBtn:ClearAllPoints()
    profBtn:SetPoint("TOPRIGHT", form, "TOPRIGHT", -14, -44)
    profBtn.recipe = r
    local n = G:Get(myKey(), r[2])
    profBtn.text:SetText(n and ("|cff00c7ffCrafting goal:|r %d"):format(n) or "|cff00c7ffSet a crafting goal|r")
    profBtn:SetWidth(profBtn.text:GetStringWidth() + 18)
    profBtn:Show()
end

----------------------------------------------------------------------
function G:Changed()
    VG.Earn:Update()
    if VG.Settings then VG.Settings:Refresh() end
    if profBtn and profBtn:IsShown() then updateProf() end
end

local pending
local function recordSoon()
    if pending then return end
    pending = true
    C_Timer.After(0.5, function()
        pending = nil
        record()
    end)
end

function G:Init()
    local loginAt = GetTime()
    local f = CreateFrame("Frame")
    for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED",
                         "BAG_UPDATE_DELAYED", "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED" }) do
        pcall(f.RegisterEvent, f, e)
    end
    f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            local spellID = select(3, ...)
            if not spellID or (issecretvalue and issecretvalue(spellID)) then return end
            index()
            local r = bySpell[spellID]
            local key = myKey()
            local n = r and G:Get(key, r[2])
            if n then
                G:Set(key, r[2], n - 1)
                if n == 1 then print(("%s goal done: %s."):format(VG.PREFIX, r[2])) end
            end
        elseif event == "BAG_UPDATE_DELAYED" then
            saveStock()
            if G:Any() then VG.Earn:Update() end
        elseif event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(5, saveStock)   -- bags may not be counted yet the moment you log in
            C_Timer.After(5, saveSkills)
        elseif event == "SKILL_LINES_CHANGED" then
            -- an empty list means "no professions" only well after login
            prune(GetTime() - loginAt > 15)
            saveSkills()
        else
            recordSoon()
        end
    end)
    C_Timer.After(20, function() prune(true) end)   -- well after login the list is loaded
    if EventRegistry then
        EventRegistry:RegisterCallback("ProfessionsRecipeListMixin.Event.OnRecipeSelected", function()
            C_Timer.After(0, updateProf)
        end, G)
    end
end
