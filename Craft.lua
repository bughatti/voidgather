----------------------------------------------------------------------
-- VoidGather — Craft: what a gathered material is worth crafted
--
-- CraftData.lua (generated from the game's tables) lists every Midnight
-- recipe that turns a raw material into something sellable. For a material
-- this works out, per recipe, what each piece of it is worth when crafted:
--
--   (what the recipe makes x its price - the other materials' cost)
--     / how many of this material it takes
--
-- Prices come from Earnings.lua (VoidAH, Auctionator, TSM). A recipe is left
-- out when its result has only a vendor price or a material has no price at
-- all, so a tip is never built on a guess. The cheapest rank of each result
-- and material is used, and crafting bonuses (multicraft, resourcefulness)
-- are not counted, so it's a floor, not a ceiling.
----------------------------------------------------------------------
local ADDON, VG = ...
VG.Craft = {}
local C = VG.Craft

local uses        -- itemID -> { recipe, ... }
local cache = {}  -- itemID -> { t, options }
local CACHE_SECS = 30

local function index()
    if uses then return end
    uses = {}
    for _, r in ipairs(VG.CRAFT or {}) do
        for _, m in ipairs(r.mats) do
            for _, id in ipairs(m.ids) do
                uses[id] = uses[id] or {}
                table.insert(uses[id], r)
            end
        end
    end
end

function C:Known(id)
    index()
    return uses[id] ~= nil
end

-- The cheapest priced rank of a slot (copper per item), or nil.
-- market = true (what a recipe makes): auction prices only.
-- Otherwise (a material you'd buy): the auction price, else what a vendor
-- charges (CRAFT_BUY) -- not the vendor's sell price, which is far lower.
local function slotPrice(ids, market)
    local best
    for _, id in ipairs(ids) do
        local p, src = VG.Earn:Price(id)
        if src == "vendor" then p = nil end
        if not p and not market then p = VG.CRAFT_BUY and VG.CRAFT_BUY[id] end
        if p and (not best or p < best) then best = p end
    end
    return best
end

-- Professions this character has (base skill lines), for "you can make this".
local mine, mineTime
local function myProfs()
    if mine and GetTime() - mineTime < 10 then return mine end
    mine, mineTime = {}, GetTime()
    if GetProfessions and GetProfessionInfo then
        for _, idx in pairs({ GetProfessions() }) do
            local line = idx and select(7, GetProfessionInfo(idx))
            if line then mine[line] = true end
        end
    end
    return mine
end

-- Every way to use one piece of item `id`, best first:
-- { { name, prof, profName, value = copper per piece, have = true/false }, ... }
function C:Options(id)
    index()
    if not (id and uses[id]) then return {} end
    local c = cache[id]
    if c and GetTime() - c.t < CACHE_SECS then return c.options end
    local options, seen = {}, {}
    for _, r in ipairs(uses[id]) do
        local made = slotPrice(r.makes.ids, true)
        local need, other, ok = 0, 0, made ~= nil
        for _, m in ipairs(r.mats) do
            if not ok then break end
            local isThis = false
            for _, mid in ipairs(m.ids) do
                if mid == id then isThis = true; break end
            end
            if isThis then
                need = need + m.n
            else
                local p = slotPrice(m.ids)
                if p then other = other + p * m.n else ok = false end
            end
        end
        if ok and need > 0 then
            local value = (made * r.makes.n - other) / need
            -- recipes that share a name (ranks / variants): keep the best one
            local prev = seen[r[2]]
            if value > 0 and (not prev or value > prev.value) then
                local o = prev or {}
                o.name, o.spell, o.prof, o.value = r[2], r[1], r[3], value
                o.profName = VG.CRAFT_PROFS[r[3]] or "?"
                o.have = myProfs()[r[3]] == true
                if not prev then
                    seen[r[2]] = o
                    options[#options + 1] = o
                end
            end
        end
    end
    table.sort(options, function(a, b) return a.value > b.value end)
    cache[id] = { t = GetTime(), options = options }
    return options
end

-- The best option that beats selling raw by 10%+, and the raw price.
function C:Best(id)
    local raw = VG.Earn:Price(id)
    local best = self:Options(id)[1]
    if best and (not raw or best.value > raw * 1.1) then return best, raw end
    return nil, raw
end

----------------------------------------------------------------------
-- Item tooltips: "VoidGather: sell 12g each · as Imbued Mulch 18g (you can make it)"
----------------------------------------------------------------------
local function addLines(tt, id)
    if not VG:Config().craftTips or not C:Known(id) then return end
    local options = C:Options(id)
    local raw, src = VG.Earn:Price(id)
    if #options == 0 and not raw then return end
    tt:AddLine(" ")
    tt:AddLine("VoidGather — what it's worth", 0, 0.78, 1)
    if raw then
        tt:AddDoubleLine("Sell as is", VG.Earn.Money(raw) .. (src == "vendor" and " |cff8c8c9e(vendor)|r" or ""),
            0.8, 0.8, 0.8, 1, 1, 1)
    end
    for i, o in ipairs(options) do
        if i > 3 then break end
        local who = "|cff8c8c9e" .. o.profName .. "|r"
        if o.have then
            -- only claim it when the game confirms the recipe is learned; it can
            -- only tell while that profession's data is loaded
            -- (not while a linked or guild profession is open: then the game
            -- answers for that player, not you)
            local T = C_TradeSkillUI
            local external = T and ((T.IsTradeSkillLinked and T.IsTradeSkillLinked())
                or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
                or (T.IsTradeSkillGuildMember and T.IsTradeSkillGuildMember())
                or (T.IsNPCCrafting and T.IsNPCCrafting()))
            local info = not external and T and T.GetRecipeInfo and T.GetRecipeInfo(o.spell)
            if info and info.learned then
                who = "|cff55ff55you can make it|r"
            elseif info then
                who = "|cff8c8c9e" .. o.profName .. ", not learned|r"
            else
                who = "|cff8c8c9eyour " .. o.profName .. "|r"
            end
        end
        tt:AddDoubleLine(("As %s  %s"):format(o.name, who), VG.Earn.Money(o.value), 0.8, 0.8, 0.8, 1, 1, 1)
    end
end

function C:Init()
    if not (TooltipDataProcessor and Enum.TooltipDataType and Enum.TooltipDataType.Item) then return end
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
        if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
        local id = data and data.id
        if not id or (issecretvalue and issecretvalue(id)) then return end
        pcall(addLines, tt, id)
    end)
end
