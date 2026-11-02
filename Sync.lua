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
local CHANNEL_NAME  = "VoidGatherNet"
local MAX_LEN       = 250    -- SendAddonMessage cap is 255
local SEND_EVERY    = 1.1    -- seconds between our outgoing messages
local QUEUE_MAX     = 60
local REPLY_MAX     = 300    -- spots per answer
local REPLY_CD      = 120    -- answer the same map at most this often
local QUERY_CD      = 900    -- ask about the same map at most this often
local SENDER_WINDOW = 60
local SENDER_MAX    = 40     -- messages accepted per sender per window

local KIND_CODE = { mining = "m", herb = "h", skin = "s", lumber = "l" }
local CODE_KIND = { m = "mining", h = "herb", s = "skin", l = "lumber" }

local queue, sending = {}, nil
local bucket = {}        -- [sender] = { n, start }
local replyTimer = {}    -- [mapID] = C_Timer handle while we wait to answer
local lastReply = {}     -- [mapID] = GetTime()
local lastQuery = {}     -- [mapID] = GetTime()
local pingNonce, pingGot
local me
local refreshPending

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
-- channel traffic, so we never burst)
----------------------------------------------------------------------
local function pump()
    local msg = table.remove(queue, 1)
    if not msg then
        if sending then sending:Cancel(); sending = nil end
        return
    end
    local idx = netIndex()
    if idx and C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(PREFIX, msg, "CHANNEL", idx)
    end
end

-- urgent = jump the queue (who's-here answers are only useful within seconds)
local function send(msg, urgent)
    if #queue >= QUEUE_MAX then return end
    if urgent then table.insert(queue, 1, msg) else queue[#queue + 1] = msg end
    if not sending then
        pump()
        -- always start the ticker: pump() just emptied the queue, so a
        -- "#queue > 0" check here never fired and bursts went out unpaced.
        -- The ticker cancels itself once the queue is empty.
        sending = C_Timer.NewTicker(SEND_EVERY, pump)
    end
end

-- Pack spots into as few messages as fit under MAX_LEN.
local function sendSpots(kindTag, mapID, recs)
    local head = ("%s:%s:%d:"):format(kindTag, PROTO, mapID)
    local parts, len = {}, #head
    for _, rec in ipairs(recs) do
        if KIND_CODE[rec.k] then
            local e = encode(rec)
            if #parts > 0 and len + 1 + #e > MAX_LEN then
                send(head .. table.concat(parts, ";"))
                parts, len = {}, #head
            end
            parts[#parts + 1] = e
            len = len + #e + 1
        end
    end
    if #parts > 0 then send(head .. table.concat(parts, ";")) end
end

-- Called by Gather a moment after a NEW spot of yours (loot has named it by then).
function Sync:Share(mapID, rec)
    if not (enabled() and mapID and rec) then return end
    sendSpots("N", mapID, { rec })
end

function Sync:Ask(mapID)
    if not (enabled() and mapID and netIndex()) then return end
    if lastQuery[mapID] and GetTime() - lastQuery[mapID] < QUERY_CD then return end
    lastQuery[mapID] = GetTime()
    send(("Q:%s:%d"):format(PROTO, mapID))
end

local function answer(mapID)
    replyTimer[mapID] = nil
    lastReply[mapID] = GetTime()
    local own, out = VG:NodesFor(mapID), {}
    -- newest first, so a capped answer carries the freshest spots
    for i = #own, math.max(1, #own - REPLY_MAX + 1), -1 do out[#out + 1] = own[i] end
    sendSpots("B", mapID, out)
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
    local n = 0
    for _ in pairs(hereZone and rosters[hereZone] or {}) do n = n + 1 end
    VoidPresence:Set("VoidGather", "VoidGather", n, capped[hereZone or 0] or n >= HERE_CAP, enabled() and hereZone ~= nil)
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

function Sync:WhoHere()
    if not enabled() then
        print(VG.PREFIX .. " sharing is |cffff5555off|r — /vg share to turn it on.")
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
local function rateOK(sender)
    local b = bucket[sender]
    if not b or GetTime() - b.start > SENDER_WINDOW then
        bucket[sender] = { n = 1, start = GetTime() }
        return true
    end
    b.n = b.n + 1
    return b.n <= SENDER_MAX
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

function Sync:OnMessage(msg, sender)
    if type(msg) ~= "string" then return end

    local nonce = msg:match("^PING:(.+)$")
    if nonce then
        if nonce == pingNonce then pingGot = true end
        return
    end

    if not enabled() or sender == me then return end
    if not rateOK(sender) then return end

    local tag, proto, mapS, body = msg:match("^(%a):(%d+):(%d+):?(.*)$")
    if proto ~= PROTO then return end
    local mapID = tonumber(mapS)
    if not validMap(mapID) then return end

    if tag == "Q" then
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
    elseif (tag == "P" or tag == "H" or tag == "L") and body == "" then
        onHere(tag, mapID, sender)
    end
end

----------------------------------------------------------------------
-- Channel join + zone catch-up
----------------------------------------------------------------------
function Sync:JoinNet()
    if not enabled() then return end
    if not netIndex() then JoinTemporaryChannel(CHANNEL_NAME) end
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
        C_Timer.After(3, function() askHere(); arrive() end)
    elseif netIndex() then
        LeaveChannelByName(CHANNEL_NAME)
    end
    publish()
end

-- The box was just turned on: count now instead of waiting for the next recount.
function Sync:CountNow()
    publish()
    recount()
end

function Sync:Init()
    me = UnitName("player")
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    f:RegisterEvent("ZONE_CHANGED")
    f:SetScript("OnEvent", function(_, event, prefix, msg, _, sender)
        if event == "CHAT_MSG_ADDON" then
            if prefix ~= PREFIX then return end
            local who = Ambiguate and Ambiguate(sender or "", "none") or sender
            if who and who ~= me and type(msg) == "string" and not msg:find("^PING:") then
                Sync.heard[who] = (Sync.heard[who] or 0) + 1
                Sync.heardTotal = Sync.heardTotal + 1
            end
            Sync:OnMessage(msg, who)
        else
            askHere()
            arrive()
        end
    end)
    -- the chat/channel system needs a few seconds after login
    C_Timer.After(8, function()
        Sync:JoinNet()
        C_Timer.After(3, function() askHere(); arrive() end)
    end)
    C_Timer.NewTicker(RECOUNT, recount)
    VoidPresence:Listen(function() Sync:CountNow() end)
end

----------------------------------------------------------------------
-- Network health: other players heard from this session, and how many players
-- are in VoidGatherNet right now (= VoidGather users online on your realm
-- group, incl. you). Selecting the display channel asks the server for the roster.
----------------------------------------------------------------------
Sync.heard, Sync.heardTotal = {}, 0

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
