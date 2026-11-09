----------------------------------------------------------------------
-- VoidGather — Sync: share spots with other players
--
-- Every VoidGather client joins the same hidden custom channel
-- (VoidGatherNet; the stock General/Trade/LFG channels reject addon
-- messages in 12.x — proven with VoidSweep). Realm-cluster wide.
--
-- Messages (prefix VGATHER, protocol 1):
--   N:1:mapID:entries   a spot you just gathered for the first time (live)
--   Q:1:mapID           "anyone have spots for this map?" (on zone change)
--   B:1:mapID:entries   answer to Q — your own spots for that map, in batches
--   P:1:zoneID / H:1:zoneID   who's here: "I arrived" / "I'm here too"
--   PING:nonce          /vg net self-test (you receive your own messages)
-- entries = "k,x,y,name;k,x,y,name" with k = m/h/s/l, x/y = 0..9999.
--
-- One player answers each Q: everyone who could answer waits a random
-- 1-6 s and stands down if somebody else's B for that map shows up first.
--
-- WoW FOREVER (live 2026-11-05) refuses addon messages in custom channels,
-- so there VoidGatherNet is only a member list (WhisperNet.lua) and the same
-- messages go by addon whisper to the bare "First Surname" name: N to up to
-- FANOUT random members, Q to up to ASK_PEERS, and each of them whispers its
-- B straight back to the asker (at most one answer per player per REPLY_GAP).
-- "Who's here" can't be counted by zone there: the box shows how many
-- VoidGather players are online (the channel's member count) instead, and no
-- P/H/L goes out. /vg net whispers a PING to yourself.
--
-- SECURITY: the channel is public and the prefix ships in our code, so
-- every inbound message is untrusted. A message can only ADD a shared spot
-- (kept apart from your own, drawn faded until a 2nd player confirms it,
-- dropped when you gather there yourself). Fields are parsed with strict
-- patterns, names are stripped of escape codes and capped, coords and
-- map IDs are checked, and each sender is rate-limited. Nothing is ever
-- executed and only your OWN gathers are passed on, so a bad report
-- can't spread past the people who heard it directly.
----------------------------------------------------------------------
local ADDON, VG = ...
VG.Sync = {}
local Sync = VG.Sync

local PREFIX        = "VGATHER"
local PROTO         = "1"
local CHANNEL_NAME  = "VoidGatherNet"   -- retail (older versions are there too)
-- WoW Forever: a new channel every day, joined with a password, both worked out from the
-- server's date (WhisperNet.lua "Daily channel"). Nobody can /join it by hand, own it and
-- /ban players (that happened to VoidQuestNet, 2026-11-08), and if someone works it out
-- anyway, it only lasts until 00:00 UTC. Set in Sync:Init once the game says it's Forever.
local OLD_CHANNELS  = { "VoidGatherNet", "VoidGatherLink" }   -- left on Forever
local DAILY_TAG, DAILY_SALT = "Vg", 48271
local CHANNEL_PW
local daily = false      -- Forever: CHANNEL_NAME is the day's channel
local MAX_LEN       = 250    -- SendAddonMessage cap is 255
local SEND_EVERY    = 1.1    -- seconds between our outgoing messages
local QUEUE_MAX     = 60
local REPLY_MAX     = 300    -- spots per answer
local REPLY_CD      = 120    -- answer the same map at most this often
local QUERY_CD      = 900    -- ask about the same map at most this often
local SENDER_WINDOW = 60
local SENDER_MAX    = 40     -- messages accepted per sender per window
-- Forever (whispers)
local SEND_EVERY_W  = 1.5    -- whispers are paced a little slower
local FANOUT        = 6      -- members each new spot is whispered to
local ASK_PEERS     = 4      -- members asked on entering a zone
local REPLY_MAX_W   = 60     -- spots per whispered answer (~6 messages)
local ANSWER_EVERY  = 30     -- at most one whispered answer (to anyone) per this
local lastAnyReply
local REPLY_GAP     = 60     -- one answer per player per this, any map

local KIND_CODE = { mining = "m", herb = "h", skin = "s", lumber = "l" }
local CODE_KIND = { m = "mining", h = "herb", s = "skin", l = "lumber" }

local queue, sending = {}, nil
local bucket = {}        -- [sender] = { n, start }
local replyTimer = {}    -- [mapID] = C_Timer handle while we wait to answer
local lastReply = {}     -- [mapID] = GetTime()  (Forever: [sender .. ":" .. mapID])
local lastReplyTo = {}   -- Forever: [sender] = GetTime() of our last answer to them
local lastQuery = {}     -- [mapID] = GetTime()
local pingNonce, pingGot
local me
local refreshPending
local net                -- WhisperNet object on Forever, nil on retail (= channel)
Sync.gen = 0             -- bumped when sharing is turned off; scheduled answers check it

local function enabled() return VG:Config().share ~= false end

local function netIndex()
    local id = GetChannelName(CHANNEL_NAME)
    if id and id > 0 then return id end
end

-- Strip anything that could act as an escape code or break the format,
-- and cap the length without cutting a UTF-8 character in half.
local function cleanName(s)
    if type(s) ~= "string" then return "?" end
    s = (s:gsub("[%c|;,:]", ""))
    s = (s:gsub("^%s+", ""):gsub("%s+$", ""))
    if #s > 40 then
        s = s:sub(1, 40)
        s = (s:gsub("[\192-\255][\128-\191]*$", ""))
    end
    if s == "" then return "?" end
    return s
end

Sync.CleanName = cleanName   -- Core matches local names against wire names

local function encode(rec)
    return ("%s,%d,%d,%s"):format(KIND_CODE[rec.k],
        math.floor(rec.x * 10000 + 0.5), math.floor(rec.y * 10000 + 0.5), cleanName(rec.n))
end

----------------------------------------------------------------------
-- Outgoing (one message every SEND_EVERY seconds; the server throttles
-- addon traffic, so we never burst). An item with .to is an addon whisper
-- (Forever), without one it goes on the channel (retail).
----------------------------------------------------------------------
local function pump()
    local item = table.remove(queue, 1)
    if not item then
        if sending then sending:Cancel(); sending = nil end
        return
    end
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    if item.to then
        if net then net:Noted(item.to) end
        local result = C_ChatInfo.SendAddonMessage(PREFIX, item.msg, "WHISPER", item.to)
        if net then net:Sent(item.to, result) end
    else
        local idx = netIndex()
        if idx then C_ChatInfo.SendAddonMessage(PREFIX, item.msg, "CHANNEL", idx) end
    end
end

-- urgent = jump the queue (who's-here answers are only useful within seconds)
-- to = whisper target; Forever drops anything without one (its channel refuses them)
local function send(msg, urgent, to)
    if #queue >= QUEUE_MAX then return end
    if net and not to then return end
    local item = { msg = msg, to = to }
    if urgent then table.insert(queue, 1, item) else queue[#queue + 1] = item end
    if not sending then
        pump()
        -- always start the ticker: pump() just emptied the queue, so a
        -- "#queue > 0" check here never fired and bursts went out unpaced.
        -- The ticker cancels itself once the queue is empty.
        sending = C_Timer.NewTicker(net and SEND_EVERY_W or SEND_EVERY, pump)
    end
end

-- Who a message to "everyone" goes to: nil = the channel (retail); on Forever up
-- to k random members of VoidGatherNet (empty when nobody else is online).
local function targets(k)
    if not net then return nil end
    net:RequestRoster()
    return net:Pick(k)
end

-- Pack spots into as few messages as fit under MAX_LEN; each to every target
-- (to = nil: once, on the channel).
local function sendSpots(kindTag, mapID, recs, to)
    local head = ("%s:%s:%d:"):format(kindTag, PROTO, mapID)
    local msgs, parts, len = {}, {}, #head
    for _, rec in ipairs(recs) do
        if KIND_CODE[rec.k] then
            local e = encode(rec)
            if #parts > 0 and len + 1 + #e > MAX_LEN then
                msgs[#msgs + 1] = head .. table.concat(parts, ";")
                parts, len = {}, #head
            end
            parts[#parts + 1] = e
            len = len + #e + 1
        end
    end
    if #parts > 0 then msgs[#msgs + 1] = head .. table.concat(parts, ";") end
    if not to then
        for _, m in ipairs(msgs) do send(m) end
        return
    end
    for _, name in ipairs(to) do
        for _, m in ipairs(msgs) do send(m, false, name) end
    end
end

-- Called by Gather a moment after a NEW spot of yours (loot has named it by then).
function Sync:Share(mapID, rec)
    if not (enabled() and mapID and rec) then return end
    -- every VoidGather ships with the seed's spots: don't send those (keep traffic small)
    if VG:SeedHas(rec.k, rec.n, mapID, rec.x, rec.y) then return end
    sendSpots("N", mapID, { rec }, targets(FANOUT))
end

function Sync:Ask(mapID)
    if not (enabled() and mapID and netIndex()) then return end
    if lastQuery[mapID] and GetTime() - lastQuery[mapID] < QUERY_CD then return end
    if net then
        net:RequestRoster()
        if #net.roster == 0 then return end   -- nobody to ask yet; try again on the next zone change
        lastQuery[mapID] = GetTime()
        for _, to in ipairs(net:Pick(ASK_PEERS)) do send(("Q:%s:%d"):format(PROTO, mapID), false, to) end
        return
    end
    lastQuery[mapID] = GetTime()
    send(("Q:%s:%d"):format(PROTO, mapID))
end

-- Your own spots for a map, newest first, so a capped answer carries the freshest.
-- Spots in the seed are left out: the asker's VoidGather ships with them.
local function ownSpots(mapID, cap)
    local own, out = VG:NodesFor(mapID), {}
    for i = #own, 1, -1 do
        if #out >= cap then break end
        local r = own[i]
        if not VG:SeedHas(r.k, r.n, mapID, r.x, r.y) then out[#out + 1] = r end
    end
    return out
end

local function answer(mapID)
    replyTimer[mapID] = nil
    lastReply[mapID] = GetTime()
    sendSpots("B", mapID, ownSpots(mapID, REPLY_MAX))
end

----------------------------------------------------------------------
-- Who's here: entering a zone tells you how many other VoidGather players
-- are in it.
--   P:1:zoneID   "I just arrived" (sent when you enter a zone)
--   H:1:zoneID   "I'm here too" (answer from players already in that zone)
-- Answerers wait 0.5-4 s at random and stand down once HERE_CAP others have
-- answered, so a busy zone sends about HERE_CAP answers and shows "10+".
-- Subzones and caves count as their zone; instances are skipped. Only
-- players on a VoidGather with this feature answer.
----------------------------------------------------------------------
local HERE_CAP   = 10
local HERE_WAIT  = 6      -- seconds the arrival listens before printing
local ARRIVE_CD  = 120    -- announce the same zone at most this often
local ASK_CD     = 15     -- /vg here at most this often

local hereZone            -- zone you're in now (nil in instances)
local announced           -- zone you last announced
local lastArrive = {}     -- [zoneID] = GetTime()
local listen              -- { zone, from = {[name]=true}, n, always, recount }
local rounds = {}         -- [zoneID] = { n = answers heard, timer = our pending answer }

-- Who's in your zone now, for the "players here" box (PresenceBox.lua): filled
-- by arrivals (P), answers (H) and departures (L:1:zoneID, sent when you leave
-- a zone; older versions ignore it), and rebuilt by a quiet recount every 10
-- minutes while the box is shown (catches players who logged off).
local RECOUNT = 600
local rosters = {}        -- [zoneID] = { [name] = true }
local rosterZone          -- the zone we last counted
local capped = {}         -- [zoneID] = true: the last count hit HERE_CAP (busy zone)
local LEAVE_DELAY = 10    -- seconds out of a zone before "left" goes out (border flapping)
local leaveTimer = {}     -- [zoneID] = pending "left" timer

local function publish()
    if not _G.VoidPresence then return end
    local note = enabled() and VG.WhisperNet and VG.WhisperNet.BlockNote(CHANNEL_NAME) or nil
    if net then
        -- Forever: players online on the channel (no zone counts without channel messages)
        local others = net:Others()
        VoidPresence:Set("VoidGather", "VoidGather online", others or 0, false, enabled() and others ~= nil, note)
        return
    end
    local n = 0
    for _ in pairs(hereZone and rosters[hereZone] or {}) do n = n + 1 end
    VoidPresence:Set("VoidGather", "VoidGather", n, capped[hereZone or 0] or n >= HERE_CAP, enabled() and hereZone ~= nil, note)
end

-- Roll a map up to its zone (city floors, caves and subzones count as the zone).
local function zoneOf(mapID)
    local ZONE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    local info = mapID and C_Map.GetMapInfo(mapID)
    local hops = 0
    while info and info.mapType and info.mapType > ZONE and (info.parentMapID or 0) > 0 and hops < 5 do
        info = C_Map.GetMapInfo(info.parentMapID)
        hops = hops + 1
    end
    if info and info.mapType == ZONE then return info.mapID, info.name end
end

local function currentZone()
    if IsInInstance() then return nil end
    return zoneOf(C_Map.GetBestMapForUnit("player"))
end

local function report(zone)
    local l = listen
    if not (l and l.zone == zone) then return end
    listen = nil
    local now, name = currentZone()
    if now ~= zone then return end
    if l.recount then rosters[zone] = l.from end
    -- a busy zone stays "10+" through departures, until a count says otherwise
    capped[zone] = l.n >= HERE_CAP
    publish()
    -- the box shows the count: chat only when asked by hand or the box is off
    if l.recount or (not l.always and _G.VoidPresence and VoidPresence:IsShown()) then return end
    if l.n == 0 then
        if l.always then
            print(("%s no other VoidGather players answered in %s."):format(VG.PREFIX, name or "this zone"))
        end
        return
    end
    local count = l.n >= HERE_CAP and (HERE_CAP .. "+") or tostring(l.n)
    print(("%s |cff33ff33%s|r other VoidGather player%s in %s."):format(VG.PREFIX,
        count, l.n == 1 and " is" or "s are", name or "this zone"))
end

-- always = asked by hand: skip the cooldowns and say so even when nobody answers
local function arrive(always)
    local zone = currentZone()
    if net then   -- Forever: no P/H/L (the channel refuses them); the box counts members
        hereZone = zone
        publish()
        return
    end
    if zone ~= rosterZone then
        -- left a zone: tell the players there, so their count drops
        -- left a zone: after a few seconds away tell the players there, so their count
        -- drops (coming back before then cancels it; flying along a border sends nothing)
        local left = rosterZone
        if left and enabled() and netIndex() and not leaveTimer[left] then
            leaveTimer[left] = C_Timer.NewTimer(LEAVE_DELAY, function()
                leaveTimer[left] = nil
                if hereZone ~= left and enabled() and netIndex() then
                    send(("L:%s:%d"):format(PROTO, left), true)
                    lastArrive[left] = nil   -- they dropped us: coming back announces again
                    if announced == left then announced = nil end
                end
            end)
        end
        if zone and leaveTimer[zone] then leaveTimer[zone]:Cancel(); leaveTimer[zone] = nil end
        rosterZone = zone
        if zone then rosters[zone] = rosters[zone] or {} end
    end
    hereZone = zone
    publish()
    if not zone then announced = nil end   -- back from an instance = arriving again
    if not zone or not enabled() or not netIndex() then return end
    local cd = always and ASK_CD or ARRIVE_CD
    if not always and zone == announced then return end
    if lastArrive[zone] and GetTime() - lastArrive[zone] < cd then
        if always then print(VG.PREFIX .. " asked a moment ago, try again in a few seconds.") end
        return
    end
    announced = zone
    lastArrive[zone] = GetTime()
    listen = { zone = zone, from = {}, n = 0, always = always }
    send(("P:%s:%d"):format(PROTO, zone), true)
    C_Timer.After(HERE_WAIT, function() report(zone) end)
end

-- Forever: "N other VoidGather players online" from the channel's member list.
local function printOnline()
    local others = net:Others()
    local why = VG.WhisperNet.BlockReason(CHANNEL_NAME)
    if why then
        print(VG.PREFIX .. " |cffff5555" .. why .. "|r")
    elseif not others then
        print(VG.PREFIX .. " couldn't read " .. CHANNEL_NAME .. "'s member list yet, try again in a few seconds.")
    else
        print(("%s %s%d|r other VoidGather player%s online (WoW Forever can't count by zone)."):format(VG.PREFIX,
            others > 0 and "|cff33ff33" or "|cffffd200", others, others == 1 and " is" or "s are"))
    end
end

function Sync:WhoHere()
    if not enabled() then
        print(VG.PREFIX .. " sharing is |cffff5555off|r — /vg share to turn it on.")
    elseif net then
        self:JoinNet()
        net:RequestRoster(true)
        C_Timer.After(3.5, printOnline)
    elseif not currentZone() then
        print(VG.PREFIX .. " not counted inside instances.")
    else
        arrive(true)
    end
end

-- Quiet recount for the box: same as arriving, no chat, and the answers
-- replace the roster.
local function recount()
    local zone = currentZone()
    if not (_G.VoidPresence and VoidPresence:IsShown()) then return end
    if net then
        publish()   -- a blocked channel is never read, so say so now
        if enabled() then net:RequestRoster(true) end   -- publish() runs when it's read
        return
    end
    if not zone or zone ~= hereZone or listen or not enabled() or not netIndex() then return end
    lastArrive[zone] = GetTime()
    listen = { zone = zone, from = {}, n = 0, recount = true }
    send(("P:%s:%d"):format(PROTO, zone), true)
    C_Timer.After(HERE_WAIT, function() report(zone) end)
end

local function onHere(tag, zone, sender)
    if tag == "L" then   -- someone left this zone
        if rosters[zone] then rosters[zone][sender] = nil end
        -- and out of a count in progress, or the recount would add them back
        if listen and listen.zone == zone and listen.from[sender] then
            listen.from[sender] = nil
            listen.n = listen.n - 1
        end
        if zone == hereZone then publish() end
        return
    end
    -- an arrival counts everyone who says they're in its zone
    if listen and listen.zone == zone and not listen.from[sender] then
        listen.from[sender] = true
        listen.n = listen.n + 1
    end
    if zone ~= hereZone then return end
    rosters[zone] = rosters[zone] or {}
    if not rosters[zone][sender] then
        rosters[zone][sender] = true
        publish()
    end

    -- a round lasts until our answer goes out; a P after that starts a new one
    local r = rounds[zone]
    if tag == "P" then
        if r and r.timer then
            r.n = 0   -- answers heard so far came before this arrival; ours still covers both
        else
            r = { n = 0 }
            rounds[zone] = r
            r.timer = C_Timer.NewTimer(0.5 + math.random() * 3.5, function()
                r.timer = nil
                if hereZone == zone and r.n < HERE_CAP and enabled() then
                    send(("H:%s:%d"):format(PROTO, zone), true)
                end
            end)
        end
    elseif r and r.timer then
        r.n = r.n + 1
        if r.n >= HERE_CAP and r.timer then
            r.timer:Cancel()
            r.timer = nil
        end
    end
end

----------------------------------------------------------------------
-- Incoming — untrusted
----------------------------------------------------------------------
local lastSweep = 0
local function rateOK(sender)
    local now = GetTime()
    if now - lastSweep > SENDER_WINDOW then   -- forget senders whose window ran out
        lastSweep = now
        for k, b in pairs(bucket) do
            if now - b.start > SENDER_WINDOW then bucket[k] = nil end
        end
        if net then
            for k, t in pairs(lastReply) do
                if now - t > REPLY_CD then lastReply[k] = nil end
            end
            for k, t in pairs(lastReplyTo) do
                if now - t > REPLY_GAP then lastReplyTo[k] = nil end
            end
        end
    end
    local b = bucket[sender]
    if not b or now - b.start > SENDER_WINDOW then
        bucket[sender] = { n = 1, start = now }
        return true
    end
    b.n = b.n + 1
    return b.n <= SENDER_MAX
end

-- Forever: whisper our own spots for a map back to the player who asked. Each
-- asker gets one answer per REPLY_GAP (any map) and one per map per REPLY_CD,
-- and only when there's something to say, so a stranger can't make us spam.
local function answerWhisper(mapID, sender, replyTo)
    if not replyTo then return end
    local key, now = sender .. ":" .. mapID, GetTime()
    if lastReply[key] and now - lastReply[key] < REPLY_CD then return end
    if lastReplyTo[sender] and now - lastReplyTo[sender] < REPLY_GAP then return end
    if #VG:NodesFor(mapID) == 0 then return end
    -- and one answer to anyone every ANSWER_EVERY seconds, so answers can't fill the
    -- queue and crowd out live spots
    if lastAnyReply and now - lastAnyReply < ANSWER_EVERY then return end
    lastReply[key], lastReplyTo[sender], lastAnyReply = now, now, now
    local gen = Sync.gen
    C_Timer.After(1 + math.random() * 3, function()
        -- not if sharing was turned off in the meantime (even if it's back on)
        if enabled() and Sync.gen == gen then sendSpots("B", mapID, ownSpots(mapID, REPLY_MAX_W), { replyTo }) end
    end)
end

local function validMap(mapID)
    return mapID and mapID > 0 and C_Map.GetMapInfo(mapID) ~= nil
end

local function scheduleRefresh()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(1, function() refreshPending = nil; VG:Refresh() end)
end

local function takeSpots(mapID, body, sender)
    local changed = false
    local n = 0
    for entry in body:gmatch("[^;]+") do
        n = n + 1
        if n > 40 then break end
        local code, xs, ys, name = entry:match("^(%a),(%d%d?%d?%d?),(%d%d?%d?%d?),(.+)$")
        local kind = code and CODE_KIND[code]
        if kind then
            local x, y = tonumber(xs) / 10000, tonumber(ys) / 10000
            if x > 0 and x < 1 and y > 0 and y < 1 then
                if VG:AddShared(kind, cleanName(name), mapID, x, y, sender) then changed = true end
            end
        end
    end
    if changed then scheduleRefresh() end
end

-- sender = one name per player (rate limits, dedupe); replyTo = the name to whisper
-- back, as the game gave it (Forever)
function Sync:OnMessage(msg, sender, replyTo)
    if type(msg) ~= "string" or type(sender) ~= "string" or sender == "" then return end

    local nonce = msg:match("^PING:(.+)$")
    if nonce then
        -- Forever: only our own whisper counts (anyone can whisper a PING)
        if nonce == pingNonce and (not net or sender == me) then pingGot = true end
        return
    end

    if not enabled() or sender == me then return end
    if not rateOK(sender) then return end

    local tag, proto, mapS, body = msg:match("^(%a):(%d+):(%d+):?(.*)$")
    if proto ~= PROTO then return end
    local mapID = tonumber(mapS)
    if not validMap(mapID) then return end

    if tag == "Q" and net then
        if body == "" then answerWhisper(mapID, sender, replyTo) end
    elseif tag == "Q" then
        -- someone entered a zone: answer if we have spots there, unless another player beats us to it
        if replyTimer[mapID] or (lastReply[mapID] and GetTime() - lastReply[mapID] < REPLY_CD) then return end
        if #VG:NodesFor(mapID) == 0 then return end
        replyTimer[mapID] = C_Timer.NewTimer(1 + math.random() * 5, function() answer(mapID) end)
    elseif tag == "B" then
        if replyTimer[mapID] then
            replyTimer[mapID]:Cancel()
            replyTimer[mapID] = nil
            lastReply[mapID] = GetTime()
        end
        takeSpots(mapID, body, sender)
    elseif tag == "N" then
        takeSpots(mapID, body, sender)
    elseif (tag == "P" or tag == "H" or tag == "L") and body == "" and not net then
        onHere(tag, mapID, sender)
    end
end

----------------------------------------------------------------------
-- Channel join + zone catch-up
----------------------------------------------------------------------
-- Joining is blocked in combat and during the chat lockdown (encounters): wait, then retry.
local function chatLocked()
    if InCombatLockdown() then return true end
    local f = C_ChatInfo and C_ChatInfo.InChatMessagingLockdown
    if not f then return false end
    local ok, v = pcall(f)
    if not ok then return true end
    if issecretvalue and issecretvalue(v) then return true end
    return v == true
end
local joinRetry = CreateFrame("Frame")
joinRetry:SetScript("OnEvent", function(self)
    if chatLocked() then return end
    self:UnregisterAllEvents()
    Sync:JoinNet()
end)

function Sync:JoinNet()
    if not enabled() then return end
    -- Forever: out of the old channels first, so their slots are free for the new one (Codex
    -- review). A banned one can't be left; it goes at logout.
    if daily and not chatLocked() then
        for _, old in ipairs(OLD_CHANNELS) do
            if (GetChannelName(old) or 0) > 0 then LeaveChannelByName(old) end
        end
    end
    if not netIndex() then
        if chatLocked() then
            joinRetry:RegisterEvent("PLAYER_REGEN_ENABLED")
            joinRetry:RegisterEvent("ZONE_CHANGED_NEW_AREA")
            joinRetry:RegisterEvent("ENCOUNTER_END")
            -- fires when a chat / addon restriction lifts (PvP match end, ...): Codex review
            pcall(joinRetry.RegisterEvent, joinRetry, "ADDON_RESTRICTION_STATE_CHANGED")
            return
        end
        JoinTemporaryChannel(CHANNEL_NAME, CHANNEL_PW)
        C_Timer.After(5, publish)   -- a refused join shows as "blocked"
    end
    -- keep it out of the chat tabs
    if netIndex() and ChatFrame_RemoveChannel then
        for i = 1, (NUM_CHAT_WINDOWS or 10) do
            local cf = _G["ChatFrame" .. i]
            if cf then ChatFrame_RemoveChannel(cf, CHANNEL_NAME) end
        end
    end
end

local function askHere()
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID then Sync:Ask(mapID) end
end

function Sync:Apply()
    if enabled() then
        self:JoinNet()
        C_Timer.After(3, function()
            if net then net:RequestRoster(true) end
            -- Forever: the member list arrives ~3 s after it's asked for; ask the zone then
            C_Timer.After(net and 4 or 0, function() askHere(); arrive() end)
        end)
    else
        -- off means off: nothing queued or scheduled goes out any more
        Sync.gen = Sync.gen + 1
        wipe(queue)
        if sending then sending:Cancel(); sending = nil end
        for m, t in pairs(replyTimer) do t:Cancel(); replyTimer[m] = nil end
        if netIndex() then LeaveChannelByName(CHANNEL_NAME) end
    end
    publish()
end

-- The box was just turned on: count now instead of waiting for the next recount.
function Sync:CountNow()
    publish()
    recount()
end

local HEARD_MAX = 500   -- players remembered for /vg net

function Sync:Init()
    local Net = VG.WhisperNet
    if Net and Net.Active() then
        daily = true
        local today
        CHANNEL_NAME, CHANNEL_PW, today = Net.DailyChannel(DAILY_TAG, DAILY_SALT)
        -- channels survive a /reload: yesterday's goes too (reload across 00:00 UTC, Codex)
        table.insert(OLD_CHANNELS, (Net.DailyChannel(DAILY_TAG, DAILY_SALT, today - 1)))
        -- WoW Forever: the channel is a member list, messages go by addon whisper
        -- offline marks (players whose whisper bounced): this session only, never saved (the user,
        -- 2026-11-09: "get rid of the offline list"); the old saved list is deleted
        VoidGatherDB = VoidGatherDB or {}
        VoidGatherDB.netOffline = nil
        net = Net.New(CHANNEL_NAME, publish, {})
        me = Net.Me()
    else
        me = UnitName("player")
    end
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:RegisterEvent("ZONE_CHANGED")
    f:SetScript("OnEvent", function(_, event, prefix, msg, dist, sender)
        if event == "CHAT_MSG_ADDON" then
            if prefix ~= PREFIX then return end
            -- Forever: whispers only. A Q arriving by guild / raid would otherwise make every
            -- member who heard it whisper back at once.
            if net and dist ~= "WHISPER" then return end
            local who
            if net then
                who = Net.Canon(sender)
            else
                who = Ambiguate and Ambiguate(sender or "", "none") or sender
            end
            if who and who ~= me and type(msg) == "string" and not msg:find("^PING:") then
                if not net or Sync.heard[who] or Sync.heardPeople < HEARD_MAX then   -- cap: Forever only
                    if not Sync.heard[who] then Sync.heardPeople = Sync.heardPeople + 1 end
                    Sync.heard[who] = (Sync.heard[who] or 0) + 1
                end
                Sync.heardTotal = Sync.heardTotal + 1
            end
            Sync:OnMessage(msg, who, sender)
        else
            askHere()
            arrive()
        end
    end)
    -- the chat/channel system needs a few seconds after login
    C_Timer.After(8, function()
        Sync:JoinNet()
        C_Timer.After(3, function()
            if net then net:RequestRoster(true) end
            -- Forever: the member list arrives ~3 s after it's asked for
            C_Timer.After(net and 4 or 0, function() askHere(); arrive() end)
        end)
    end)
    C_Timer.NewTicker(RECOUNT, recount)
    VoidPresence:Listen(function() Sync:CountNow() end)
    -- Forever: at 00:00 UTC everyone moves to the new day's channel together
    if daily then
        C_Timer.NewTicker(60, function()
            local name, pw = Net.DailyChannel(DAILY_TAG, DAILY_SALT)
            if name == CHANNEL_NAME then return end
            local old = CHANNEL_NAME
            CHANNEL_NAME, CHANNEL_PW = name, pw
            net:SetChannel(name)
            table.insert(OLD_CHANNELS, old)   -- JoinNet leaves it (now, or once chat unlocks)
            publish()   -- "—" until the new list is read
            if not enabled() then
                if (GetChannelName(old) or 0) > 0 and not chatLocked() then LeaveChannelByName(old) end
                return
            end
            C_Timer.After(2, function()
                Sync:JoinNet()
                C_Timer.After(3, function() net:RequestRoster(true) end)
            end)
        end)
    end
end

----------------------------------------------------------------------
-- Network health: other players heard from this session, and how many players
-- are in VoidGatherNet right now (= VoidGather users online on your realm
-- group, incl. you). Selecting the display channel asks the server for the roster.
----------------------------------------------------------------------
Sync.heard, Sync.heardTotal, Sync.heardPeople = {}, 0, 0

local function channelMembers()
    if not (GetNumDisplayChannels and GetChannelDisplayInfo) then return nil end
    for i = 1, GetNumDisplayChannels() do
        local name, header, _, _, count = GetChannelDisplayInfo(i)
        if not header and name and name:lower() == CHANNEL_NAME:lower() then
            return count, i
        end
    end
end

function Sync:NetStats()
    if net then
        net:RequestRoster(true)
        C_Timer.After(3.5, function()
            printOnline()
            print(("%s this session -- %d message%s from %d other player%s."):format(VG.PREFIX,
                Sync.heardTotal, Sync.heardTotal == 1 and "" or "s", Sync.heardPeople, Sync.heardPeople == 1 and "" or "s"))
        end)
        return
    end
    local _, idx = channelMembers()
    if idx and SetSelectedDisplayChannel then pcall(SetSelectedDisplayChannel, idx) end
    C_Timer.After(2, function()
        local count = channelMembers()
        local people = 0
        for _ in pairs(Sync.heard) do people = people + 1 end
        if count and count > 0 then
            local others = count - 1
            print(("%s %s%d|r other VoidGather player%s online on your realm group right now."):format(
                VG.PREFIX, others > 0 and "|cff33ff33" or "|cffffd200", others, others == 1 and " is" or "s are"))
        else
            print(VG.PREFIX .. " couldn't read the channel's member count yet.")
        end
        print(("%s this session -- %d message%s from %d other player%s."):format(VG.PREFIX,
            Sync.heardTotal, Sync.heardTotal == 1 and "" or "s", people, people == 1 and "" or "s"))
    end)
end

----------------------------------------------------------------------
-- /vg net — you receive your own channel messages, so a ping that comes
-- back proves the channel works on this client/realm.
----------------------------------------------------------------------
function Sync:SelfTest()
    if not enabled() then
        print(VG.PREFIX .. " sharing is |cffff5555off|r — /vg share to turn it on.")
        return
    end
    self:JoinNet()
    if net then
        -- Forever: an addon whisper to yourself comes back if whispers get through
        print(VG.PREFIX .. " testing sharing by addon whisper (~5s)...")
        pingNonce, pingGot = ("%d-%d"):format(math.floor(GetTime() * 1000), math.random(1000, 9999)), false
        if me then C_ChatInfo.SendAddonMessage(PREFIX, "PING:" .. pingNonce, "WHISPER", me) end
        C_Timer.After(4, function()
            local spots = 0
            for _, list in pairs(VoidGatherDB.shared or {}) do spots = spots + #list end
            if pingGot then
                print(("%s addon whispers |cff33ff33work|r — sharing is live. Shared spots received so far: %d"):format(
                    VG.PREFIX, spots))
                Sync:NetStats()
            else
                print(VG.PREFIX .. " addon whispers |cffff5555didn't come back|r — messages aren't getting through here.")
            end
        end)
        return
    end
    print(VG.PREFIX .. " testing the sharing channel (~5s)...")
    C_Timer.After(1.5, function()
        local idx = netIndex()
        if not idx then
            print(VG.PREFIX .. " |cffff5555not in " .. CHANNEL_NAME .. " yet|r — try again in a few seconds.")
            return
        end
        pingNonce, pingGot = ("%d"):format(math.floor(GetTime() * 1000)), false
        C_ChatInfo.SendAddonMessage(PREFIX, "PING:" .. pingNonce, "CHANNEL", idx)
        C_Timer.After(3.5, function()
            local spots = 0
            for _, list in pairs(VoidGatherDB.shared or {}) do spots = spots + #list end
            if pingGot then
                print(("%s %s |cff33ff33works|r — sharing is live. Shared spots received so far: %d"):format(
                    VG.PREFIX, CHANNEL_NAME, spots))
                Sync:NetStats()
            else
                print(("%s %s |cffff5555no echo|r — messages aren't getting through on this realm."):format(
                    VG.PREFIX, CHANNEL_NAME))
            end
        end)
    end)
end
