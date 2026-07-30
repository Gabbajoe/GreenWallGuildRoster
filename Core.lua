local ADDON_NAME, ns = ...

-- Addon message prefixes are capped at 16 chars.
local ADDON_MSG_PREFIX = 'GWGRoster'

ns.peerNames = {}
ns.ownTag = nil
ns.ownGuild = nil
ns.lastRosterUpdate = 0
ns.debugAddonMsg = false

C_ChatInfo.RegisterAddonMessagePrefix(ADDON_MSG_PREFIX)

-- Reads GreenWall's own GWp directives from the guild info page purely for
-- the tag <-> guild name mapping (harmless, read-only).
local function ParseConfig()
    local info = GetGuildInfoText()
    if not info or info == '' then return nil end
    local cfg = { peers = {} }
    for line in info:gmatch('GW:?(%l:[^\n]*)') do
        local field = { strsplit(':', line) }
        if field[1] == 'p' and field[2] and field[3] then
            cfg.peers[strtrim(field[3])] = strtrim(field[2])
        end
    end
    return cfg
end

-- GreenWall's own third-party API (GreenWallAPI.SendMessage/AddMessageHandler,
-- see GreenWall's API.md) rides its already-established, already-joined
-- confederation channel, framed with our addon name so it can never be
-- mistaken for GreenWall's own C/B/N/R/M traffic and is explicitly exempt
-- from the "message corruption" cross-check that flagged our first attempt
-- at sharing that channel directly. Used this way, it makes the separate
-- "GWGRoster:name:password" directive this addon used to require entirely
-- unnecessary - no setup beyond having GreenWall itself configured.
local function GreenWallAPIAvailable()
    return C_AddOns.IsAddOnLoaded('GreenWall') and GreenWallAPI ~= nil and GreenWallAPI.version and GreenWallAPI.version >= 1
end

local function UpdateConfig()
    local cfg = ParseConfig()
    if not cfg then return false end
    local guildName = GetGuildInfo('player')
    if not guildName then return false end

    ns.peerNames = cfg.peers
    for tag, gname in pairs(cfg.peers) do
        if gname:lower() == guildName:lower() then
            ns.ownTag = tag
            ns.ownGuild = gname
        end
    end

    -- One-time cleanup: a self-tagged entry could have gotten stored under
    -- GreenWallGuildRosterDB.peers[ownTag] from an earlier build (before
    -- the self-filter in MergePeerPayload was reliable), and would sit
    -- there forever otherwise since it's a SavedVariable. Showing up next
    -- to the live own-guild data, it looked like every own-guild member
    -- appearing twice with stale zone/status info in the older copy.
    if ns.ownTag and GreenWallGuildRosterDB.peers[ns.ownTag] then
        GreenWallGuildRosterDB.peers[ns.ownTag] = nil
    end

    return true
end

-- Strips characters that would either break our own field/row delimiters
-- or trip SendChatMessage's "invalid escape code" guard against bare '|'.
local function Sanitize(s)
    if not s or s == '' then return '' end
    return (s:gsub('[|;~]', ''))
end

-- '2' = Guild Master (rankIndex 0), '1' = officer (rankIndex 1), '0' =
-- everyone else. Originally tried to derive "officer" from
-- GuildControlGetRankFlags' officer-chat permission bit, but live testing
-- showed that flag can be granted to non-officer ranks too (a "Veteran"
-- rank got a crown our heuristic said it should have, the native guild
-- frame disagreed) - Blizzard's own crown badge turns out to just be
-- "the second rank slot", not permission-based at all.
local function RankBadge(rankIndex)
    if rankIndex == 0 then return '2' end
    if rankIndex == 1 then return '1' end
    return '0'
end

-- Zone translation table (ZONE_EN_DE, ToCanonicalZone/FromCanonicalZone)
-- moved to ZoneData.lua, exposed as ns.ToCanonicalZone/ns.FromCanonicalZone.
ns.RankBadge = RankBadge

-- Online members only. A big guild (900+) turned into hundreds of chunked
-- SendChatMessage calls fired synchronously, back-to-back, with no way to
-- pace them (SendChatMessage can't be called from a timer - see Broadcast
-- below) - that's a chat flood in a fraction of a second, and matches a
-- reported disconnect immediately after clicking Broadcast. Trading full
-- offline visibility for actually not flooding the server.
-- Hard cap regardless of how many are online, so even a mega-guild during
-- a packed raid night can't blow past a safe number of chat messages in
-- one synchronous burst.
local MAX_BROADCAST_ROWS = 200

-- Names we reported online in our last broadcast, and when we last sent
-- a *full* snapshot rather than just a delta. Steady-state broadcasts
-- only need to say what changed (who came online, who went offline) -
-- resending everyone who's still online and unchanged is pure waste.
-- A full resync every 15 minutes regardless bounds how stale things can
-- get if a message ever goes missing, since peers only refresh the
-- "unbekannt" staleness flag off however long since they last heard
-- about someone at all.
local lastOnlineSet = {}
local lastFullSyncTime = 0
local FULL_SYNC_INTERVAL = 120

-- Separate from lastOnlineSet: tracks every member seen in the guild at
-- all (online or offline), so an actual departure - not just "hasn't been
-- seen online in a while" - can be detected and explicitly signaled.
-- Without this, a peer who leaves their guild would just sit in everyone
-- else's saved roster forever, stuck at whatever status they last had -
-- going stale is not the same as being gone, and nothing ever cleared it.
local lastKnownMembers = {}
-- How many consecutive scans someone has to be missing before actually
-- declaring them gone. GetGuildRosterInfo can come back short-handed for a
-- moment (e.g. right after a loading screen, before the client's guild
-- roster cache has fully repopulated) - trusting a single scan meant one
-- glitchy read broadcast "everyone left" for the whole guild, and every
-- peer receiving it deleted their entire cache of that guild's members.
-- Requiring the same name to be missing on two scans in a row (they run
-- every FULL_SYNC_INTERVAL/AutoBroadcast cycle) means a one-off blip
-- self-corrects on the very next scan instead of propagating.
local MISSING_STREAK_THRESHOLD = 2
local missingStreak = {}
-- Sentinel in the existing online field (normally '0'/'1') - '2' means
-- "no longer a member, delete this entry" rather than "offline".
local LEAVE_MARKER = '2'

-- forceFull: used by the manual Broadcast button, so it always visibly
-- does something and updates the "last broadcast" timestamp even if the
-- automatic delta sync happens to have nothing new to report right then -
-- it shouldn't silently no-op just because nobody's status changed in
-- the last 30 seconds.
local function CollectOwnRoster(forceFull)
    if not ns.ownTag then return {} end

    local total = GetNumGuildMembers() or 0
    -- A real guild is never reported as having zero members (you're always
    -- at least one) - total==0 means the roster cache hasn't loaded yet,
    -- not that everyone's actually gone. Bail out before touching
    -- lastKnownMembers at all, so a transient empty read can never look
    -- like a mass departure.
    if total == 0 then return {} end

    local currentOnlineSet = {}
    local currentMembers = {}
    local onlineRow = {}
    for i = 1, total do
        local name, _, rankIndex, level, _, zone, note, _, online, _, classFile = GetGuildRosterInfo(i)
        if name then
            name = name:match('^[^-]+') or name
            currentMembers[name] = true
            if online then
                currentOnlineSet[name] = true
                local linkedMain = GreenWallGuildRosterDB.mainLinks[name] or ''
                local badge = RankBadge(rankIndex)
                onlineRow[name] = strjoin(';', Sanitize(name), classFile or '', tostring(level or 0), Sanitize(ns.ToCanonicalZone(zone)), Sanitize(note), '1', Sanitize(linkedMain), badge)
            end
        end
    end

    local rows = {}
    local isFullSync = forceFull or (GetTime() - lastFullSyncTime) >= FULL_SYNC_INTERVAL

    if isFullSync then
        for _, row in pairs(onlineRow) do
            if #rows >= MAX_BROADCAST_ROWS then break end
            rows[#rows + 1] = row
        end
        lastFullSyncTime = GetTime()
    else
        for name, row in pairs(onlineRow) do
            if not lastOnlineSet[name] and #rows < MAX_BROADCAST_ROWS then
                rows[#rows + 1] = row
            end
        end
        -- Anyone we said was online last time but isn't anymore gets one
        -- final explicit "now offline" row - a second, targeted pass since
        -- they're not in onlineRow above. Skipped for anyone who actually
        -- left (handled by the leave-row pass below instead).
        for prevName in pairs(lastOnlineSet) do
            if not currentOnlineSet[prevName] and currentMembers[prevName] and #rows < MAX_BROADCAST_ROWS then
                for i = 1, total do
                    local name, _, rankIndex, level, _, zone, note, _, _, _, classFile = GetGuildRosterInfo(i)
                    if name then
                        name = name:match('^[^-]+') or name
                        if name == prevName then
                            local linkedMain = GreenWallGuildRosterDB.mainLinks[name] or ''
                            rows[#rows + 1] = strjoin(';', Sanitize(name), classFile or '', tostring(level or 0), Sanitize(ns.ToCanonicalZone(zone)), Sanitize(note), '0', Sanitize(linkedMain), RankBadge(rankIndex))
                            break
                        end
                    end
                end
            end
        end
    end

    -- Anyone known from a previous scan but missing from the guild now -
    -- confirmed across MISSING_STREAK_THRESHOLD consecutive scans, not
    -- just this one - has actually left. Send an explicit delete signal
    -- rather than leaving their last known status to just go stale
    -- forever. Still-missing-but-under-threshold names have to stay in
    -- the tracked set for next scan's comparison (simply overwriting with
    -- currentMembers would drop them after their first miss, before a
    -- second scan ever got a chance to confirm it).
    local newKnownMembers = {}
    for name in pairs(currentMembers) do
        newKnownMembers[name] = true
    end
    for prevName in pairs(lastKnownMembers) do
        if not currentMembers[prevName] then
            local streak = (missingStreak[prevName] or 0) + 1
            if streak >= MISSING_STREAK_THRESHOLD then
                if #rows < MAX_BROADCAST_ROWS then
                    rows[#rows + 1] = strjoin(';', Sanitize(prevName), '', '0', '', '', LEAVE_MARKER, '', '0')
                end
                missingStreak[prevName] = nil
                -- confirmed gone - not added to newKnownMembers, so this stops here.
            else
                missingStreak[prevName] = streak
                newKnownMembers[prevName] = true
            end
        else
            missingStreak[prevName] = nil
        end
    end

    lastOnlineSet = currentOnlineSet
    lastKnownMembers = newKnownMembers
    return rows
end

-- Shared by both transports below: splits the roster into chunks that fit
-- comfortably under the ~255-char chat/addon-message length limit.
local function ChunkRows(rows, limit)
    local chunks = {}
    local chunk, chunkLen = {}, 0
    for _, row in ipairs(rows) do
        if chunkLen + #row + 1 > limit and #chunk > 0 then
            chunks[#chunks + 1] = table.concat(chunk, '~')
            chunk, chunkLen = {}, 0
        end
        chunk[#chunk + 1] = row
        chunkLen = chunkLen + #row + 1
    end
    if #chunk > 0 then
        chunks[#chunks + 1] = table.concat(chunk, '~')
    end
    return chunks
end

-- Rebuilding the window means iterating the whole combined roster (900+
-- rows for a big guild) into fresh Lua tables. Calling that straight from
-- every single received message chunk was fine for occasional traffic,
-- but a burst of duplicate whispers meant dozens of full rebuilds in a
-- couple of seconds - allocation faster than the GC could keep up with,
-- which is what a steadily climbing addon memory figure during a message
-- burst actually looks like. Collapse any burst into at most one refresh
-- every 2 seconds.
local refreshPending = false
local function RequestRefresh()
    if not ns.RefreshFrame then return end
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(2, function()
        refreshPending = false
        ns.RefreshFrame()
    end)
end

-- Shared by both transports: merges a received chunk into the peer cache.
-- Only accepted from a tag that's actually one of GreenWall's declared
-- GWp co-guilds - otherwise a stranger who happens to land on the same
-- channel name (channel names are realm-wide, first-come-first-served)
-- could get merged into the roster as if they were part of the
-- confederation.
local function MergePeerPayload(tag, payload)
    if not tag or not payload or tag == ns.ownTag then return end
    if not ns.peerNames[tag] then return end

    GreenWallGuildRosterDB.peers[tag] = GreenWallGuildRosterDB.peers[tag] or {}
    local store = GreenWallGuildRosterDB.peers[tag]
    for row in payload:gmatch('[^~]+') do
        local name, class, level, zone, note, online, linkedMain, badge = strsplit(';', row)
        if name and name ~= '' then
            if online == LEAVE_MARKER then
                store[name] = nil
            else
                store[name] = {
                    class = class, level = tonumber(level) or 0, zone = zone,
                    note = note, online = online == '1', ts = time(),
                    linkedMain = (linkedMain and linkedMain ~= '') and linkedMain or nil,
                    badge = badge,
                }
            end
        end
    end

    RequestRefresh()
end

-- Manual transport: GreenWallAPI.SendMessage, riding GreenWall's own
-- already-joined confederation channel (see GreenWallAPIAvailable above).
--
-- Under the hood this still ends up at the same protected SendChatMessage
-- GreenWall itself uses for everything else on that channel: calling it
-- from a timer callback or an automatic event handler gets silently
-- blocked (ADDON_ACTION_BLOCKED). So this only ever runs synchronously,
-- and only from a direct user action (slash command or button click) -
-- never staggered via C_Timer.After, never called from an event handler.
--
-- GreenWall base64-encodes the payload and caps the final wire segment at
-- 255 chars total (addon name + tag + framing overhead included, and it
-- truncates rather than splitting), so the chunk budget here is smaller
-- than the raw whisper transport's - 140 raw chars comes to a little under
-- 190 chars of base64, leaving room for the rest of the frame.
local function Broadcast()
    if not GreenWallAPIAvailable() or not ns.ownTag then return end
    local rows = CollectOwnRoster(true)
    if #rows == 0 then return end

    local chunks = ChunkRows(rows, 140)
    for _, payload in ipairs(chunks) do
        GreenWallAPI.SendMessage(ADDON_NAME, ns.ownTag .. '#' .. payload)
    end

    GreenWallGuildRosterDB.lastBroadcast = time()
    if ns.RefreshFrame then ns.RefreshFrame() end
end

-- GreenWallAPI's handler contract doesn't pass the sender's actual co-guild
-- tag/id through to third-party listeners (only "guild": whether it was
-- our own) - so, same as before, we still self-report our own tag inside
-- the message body and validate it against ns.peerNames on receipt.
local function OnAPIMessage(addon, sender, message, echo, guild)
    -- echo (sent by us) implies guild (originated in our own co-guild), so
    -- checking guild alone also covers echo. Own-guild traffic - whether
    -- our own echoed broadcast or a guildmate also running this addon - is
    -- pure noise here: we already have that data directly and completely
    -- from GetGuildRosterInfo.
    if guild then return end
    local tag, payload = message:match('^(%a+)#(.*)$')
    MergePeerPayload(tag, payload)
end

-- Automatic transport: addon messages. Turns out Classic disables
-- SendAddonMessage's 'CHANNEL' target specifically ("to prevent players
-- communicating over custom chat channels" - confirmed via
-- Enum.SendAddonMessageResult.InvalidChatType on every attempt), so this
-- targets 'WHISPER' instead, at a handful of co-guild members we already
-- know are online from the last data we received. Whisper-target addon
-- messages aren't gated behind a direct user action the way
-- SendChatMessage is, so this can run unattended from timers/events.
--
-- No handshake/reachability check before whispering: if a target logged
-- off or doesn't have the addon, the message just goes nowhere, silently
-- and harmlessly. Trying a few targets each cycle, every few minutes,
-- with both sides doing this simultaneously, is enough redundancy without
-- needing to first verify anyone can "answer".
-- Rather than a fixed target count, bound the actual thing that matters
-- for flood-safety: total addon messages fired in one synchronous burst
-- (targets * chunks-per-target). A small guild or a small delta (few
-- chunks) can safely reach more people within the same budget; a big
-- full sync with many chunks stays conservative automatically. Hardware/
-- FPS isn't a relevant signal here - the real constraint is Blizzard's
-- server-side addon-message rate limiting, which is the same for every
-- client and isn't exposed to addons to measure anyway.
local MESSAGE_BUDGET_PER_GUILD = 15
local MAX_WHISPER_TARGETS_PER_GUILD = 6
-- Picking straight off pairs() iteration order means the same handful of
-- names would get hit cycle after cycle (Lua's table iteration order is
-- stable between calls unless the table is mutated) - if those particular
-- few happen to be offline or without the addon, sync stalls even though
-- plenty of other known members could carry it. Shuffling the full
-- candidate pool before capping spreads whisper traffic across everyone
-- we know about over time instead of hammering the same 2-3 people.
local function PickWhisperTargets(perGuildLimit)
    local targets = {}
    for tag, members in pairs(GreenWallGuildRosterDB.peers or {}) do
        if tag ~= ns.ownTag and ns.peerNames[tag] then
            local candidates = {}
            for name, info in pairs(members) do
                if info.online then
                    candidates[#candidates + 1] = name
                end
            end
            for i = #candidates, 2, -1 do
                local j = math.random(i)
                candidates[i], candidates[j] = candidates[j], candidates[i]
            end
            for i = 1, math.min(perGuildLimit, #candidates) do
                targets[#targets + 1] = candidates[i]
            end
        end
    end
    return targets
end

local lastAutoBroadcast = 0
-- forceFull: same idea as Broadcast()'s forceFull - "/gwgr auto" is meant
-- for testing the whisper transport on demand, so it should actually
-- push a full snapshot rather than possibly finding an empty delta and
-- silently doing nothing.
local function AutoBroadcast(forceFull)
    if not ns.ownTag then return end
    if not next(GreenWallGuildRosterDB.peers or {}) then return end

    local rows = CollectOwnRoster(forceFull)
    if #rows == 0 then return end
    local chunks = ChunkRows(rows, 200)

    local perGuildLimit = math.max(1, math.min(MAX_WHISPER_TARGETS_PER_GUILD, math.floor(MESSAGE_BUDGET_PER_GUILD / #chunks)))
    local targets = PickWhisperTargets(perGuildLimit)
    if #targets == 0 then
        if ns.debugAddonMsg then
            print('|cff33ff99GreenWallGuildRoster|r: ' .. ns.L['AutoBroadcast: no known online targets in the partner guild.'])
        end
        return
    end

    for _, target in ipairs(targets) do
        for i, payload in ipairs(chunks) do
            local ok = C_ChatInfo.SendAddonMessage(ADDON_MSG_PREFIX, ns.ownTag .. '#' .. payload, 'WHISPER', target)
            if ns.debugAddonMsg then
                print(('|cff33ff99GreenWallGuildRoster|r: TX addon-msg to %s chunk %d/%d ok=%s'):format(target, i, #chunks, tostring(ok)))
            end
        end
    end
    lastAutoBroadcast = GetTime()
end

local function OnAddonMessage(prefix, message, channel, sender)
    -- Only our own prefix, not every addon message on the client (that
    -- was drowning the debug log in unrelated traffic from GuildMap,
    -- Safeguard, etc., making it hard to see whether our own RX/TX was
    -- actually happening).
    if prefix ~= ADDON_MSG_PREFIX then return end
    if ns.debugAddonMsg then
        print(('|cff33ff99GreenWallGuildRoster|r: RX addon-msg channel=%s sender=%s'):format(
            tostring(channel), tostring(sender)))
    end
    if channel ~= 'WHISPER' then return end
    local tag, payload = message:match('^(%a+)#(.*)$')
    MergePeerPayload(tag, payload)
end

local apiHandlerRegistered = false
local function EnsureAPIHandler()
    if apiHandlerRegistered or not GreenWallAPIAvailable() then return end
    GreenWallAPI.AddMessageHandler(OnAPIMessage, ADDON_NAME, 0)
    apiHandlerRegistered = true
end

-- Dungeon/instance names aren't covered by the uiMapID scan /gwgr
-- exportzones does (confirmed empty after scanning 1-8000 - Classic Era's
-- C_Map just doesn't register them) - GetInstanceInfo()'s instanceID is
-- the equivalent stable, locale-neutral key for these instead (same
-- numbering other instance-tracking addons like Nova Instance Tracker use
-- for their own hardcoded dungeon list), but it's only readable while
-- actually standing inside the instance, not brute-forceable ahead of
-- time. So this just quietly records whatever instance you're in whenever
-- you zone in - the same zoneExport table fills in with dungeon entries
-- over ordinary play, on top of whatever /gwgr exportzones already
-- collected for outdoor zones.
local function RecordCurrentInstance()
    local inInstance = IsInInstance()
    if not inInstance then return end
    local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    if not instanceID or instanceID == 0 or not name or name == '' then return end
    GreenWallGuildRosterDB.zoneExport = GreenWallGuildRosterDB.zoneExport or { locale = GetLocale(), map = {} }
    GreenWallGuildRosterDB.zoneExport.locale = GetLocale()
    GreenWallGuildRosterDB.zoneExport.map[instanceID] = name
end

local frame = CreateFrame('Frame')
frame:RegisterEvent('ADDON_LOADED')
frame:RegisterEvent('PLAYER_ENTERING_WORLD')
frame:RegisterEvent('GUILD_ROSTER_UPDATE')
frame:RegisterEvent('CHAT_MSG_ADDON')

frame:SetScript('OnEvent', function(_, event, ...)
    if event == 'ADDON_LOADED' then
        -- Real SavedVariables data gets injected right before this fires,
        -- overwriting whatever was in the global beforehand - initializing
        -- defaults any earlier (e.g. at file top-level) means they get
        -- silently discarded the moment the actual saved table lands.
        -- That's exactly what happened to mainLinks: a fresh-table default
        -- set too early, then wiped out when the real (older) save without
        -- that field replaced it.
        local loadedAddon = ...
        if loadedAddon ~= ADDON_NAME then return end
        GreenWallGuildRosterDB = GreenWallGuildRosterDB or {}
        GreenWallGuildRosterDB.peers = GreenWallGuildRosterDB.peers or {}
        GreenWallGuildRosterDB.mainLinks = GreenWallGuildRosterDB.mainLinks or {}
    elseif event == 'PLAYER_ENTERING_WORLD' then
        C_GuildInfo.GuildRoster()
        EnsureAPIHandler()
        RecordCurrentInstance()
        if not C_AddOns.IsAddOnLoaded('GreenWall') then
            print('|cffff3333GreenWallGuildRoster|r: ' .. ns.L['GreenWall is not installed or not enabled - this addon needs it (get "GreenWall - Revived" from CurseForge) to bridge with your co-guilds.'])
        end
        C_Timer.After(3, function()
            UpdateConfig()
            AutoBroadcast()
        end)
    elseif event == 'GUILD_ROSTER_UPDATE' then
        EnsureAPIHandler()
        UpdateConfig()
        if GetTime() - lastAutoBroadcast > 30 then
            AutoBroadcast()
        end
        RequestRefresh()
    elseif event == 'CHAT_MSG_ADDON' then
        OnAddonMessage(...)
    end
end)

-- Addon messages aren't protected, so this can run unattended. Matches
-- FULL_SYNC_INTERVAL (120s) - was 300s, shortened for a more current combined
-- roster; the message-budget target selection above keeps the per-cycle
-- burst bounded regardless of how often this fires.
C_Timer.NewTicker(120, AutoBroadcast)

ns.Broadcast = Broadcast

SLASH_GWGROSTER1 = '/gwgr'
SlashCmdList['GWGROSTER'] = function(rawMsg)
    rawMsg = (rawMsg or ''):match('^%s*(.-)%s*$')
    local cmd, rest = rawMsg:match('^(%S*)%s*(.-)$')
    cmd = cmd:lower()

    if cmd == 'help' or cmd == '?' then
        print('|cff33ff99GreenWallGuildRoster|r ' .. ns.L['GreenWallGuildRoster commands:'])
        print('  |cffffd200/gwgr|r - ' .. ns.L['/gwgr - open/close the roster window'])
        print('  |cffffd200/gwgr broadcast|r - ' .. ns.L["/gwgr broadcast - send a full roster snapshot over GreenWall's confederation channel (GreenWallAPI)"])
        print('  |cffffd200/gwgr auto|r - ' .. ns.L['/gwgr auto - force an immediate full sync over the whisper channel (for testing)'])
        print('  |cffffd200/gwgr setmain <name>|r - ' .. ns.L["/gwgr setmain <name> - mark the character you're on as an alt of <name>; no name clears it"])
        print('  |cffffd200/gwgr status|r - ' .. ns.L['/gwgr status - show GreenWallAPI availability, own tag, and known confederation tags'])
        print('  |cffffd200/gwgr debug|r - ' .. ns.L['/gwgr debug - toggle addon-message RX/TX logging'])
        print('  |cffffd200/gwgr minimap|r - ' .. ns.L['/gwgr minimap - toggle the minimap button (also in Options > AddOns > GreenWall GuildRoster)'])
        print('  |cffffd200/gwgr exportzones|r - export all known zone names for your client language, for building translation tables')
        print('  |cffffd200/gwgr help|r - ' .. ns.L['/gwgr help - this list'])
    elseif cmd == 'auto' then
        print('|cff33ff99GreenWallGuildRoster|r: ' .. ns.L['Force full AutoBroadcast (addon message, all online members)...'])
        AutoBroadcast(true)
    elseif cmd == 'broadcast' then
        Broadcast()
        print('|cff33ff99GreenWallGuildRoster|r: ' .. ns.L['Broadcast sent.'])
    elseif cmd == 'status' then
        print(('|cff33ff99GreenWallGuildRoster|r: ' .. ns.L['GreenWallAPI=%s, own tag=%s']):format(
            tostring(GreenWallAPIAvailable()), tostring(ns.ownTag)))
        local peers = {}
        for tag in pairs(ns.peerNames or {}) do peers[#peers + 1] = tag end
        print(('|cff33ff99GreenWallGuildRoster|r: ' .. ns.L['Known confederation tags: %s']):format(table.concat(peers, ', ')))
    elseif cmd == 'debug' then
        ns.debugAddonMsg = not ns.debugAddonMsg
        print(('|cff33ff99GreenWallGuildRoster|r: ' .. ns.L['Addon message debug=%s']):format(tostring(ns.debugAddonMsg)))
    elseif cmd == 'minimap' then
        if ns.SetMinimapButtonShown then
            ns.SetMinimapButtonShown(GreenWallGuildRosterDB.minimapHidden and true or false)
            print(('|cff33ff99GreenWallGuildRoster|r: ' .. ns.L['Minimap button %s.']):format(
                GreenWallGuildRosterDB.minimapHidden and ns.L['hidden'] or ns.L['shown']))
        end
    elseif cmd == 'exportzones' then
        -- Dumps every zone name C_Map knows about, for the CURRENT client's
        -- language, keyed by uiMapID - a stable, locale-neutral ID Blizzard
        -- assigns itself, unlike zone text which only exists pre-localized
        -- with no ID exposed anywhere in GetGuildRosterInfo. Brute-force
        -- technique lifted from HereBeDragons (bundled with the installed
        -- GuildMap addon), which does this same kind of ID scan on every
        -- load in this exact client - proven cheap and safe, not guessed.
        -- Range widened past HereBeDragons' own 2500 cutoff: that library
        -- only cares about outdoor zones for coordinate math, but the first
        -- real export here came back with only outdoor zones/cities/
        -- battlegrounds - no dungeons (Blackrock Depths, Scholomance,
        -- Stratholme, ...) - meaning those instance map IDs live somewhere
        -- past 2500. Still a one-shot command, not a per-frame cost, so
        -- scanning further is cheap insurance either way.
        -- Two exports (English + another language) sharing the same IDs is
        -- what actually builds a correct EN<->XX zone table, instead of
        -- researching names by hand and getting them wrong.
        -- Merges into whatever's already there rather than replacing it -
        -- RecordCurrentInstance (see below) may have already collected
        -- dungeon entries via GetInstanceInfo from ordinary play, and a
        -- fresh export shouldn't wipe those back out.
        GreenWallGuildRosterDB.zoneExport = GreenWallGuildRosterDB.zoneExport or { locale = GetLocale(), map = {} }
        GreenWallGuildRosterDB.zoneExport.locale = GetLocale()
        local map = GreenWallGuildRosterDB.zoneExport.map
        local count = 0
        for id = 1, 8000 do
            local info = C_Map.GetMapInfo(id)
            if info and info.name and info.name ~= '' then
                map[id] = info.name
                count = count + 1
            end
        end
        print(('|cff33ff99GreenWallGuildRoster|r: Exported %d zone names for locale "%s" into SavedVariables.'):format(count, GetLocale()))
        print('|cff33ff99GreenWallGuildRoster|r: /reload or log out to flush to disk, then find GreenWallGuildRosterDB.zoneExport in your SavedVariables/GreenWallGuildRoster.lua and send it over.')
    elseif cmd == 'setmain' then
        local own = UnitName('player')
        if rest == '' then
            GreenWallGuildRosterDB.mainLinks[own] = nil
            print('|cff33ff99GreenWallGuildRoster|r: ' .. ns.L['Main link removed for this character.'])
        else
            -- WoW character names are always Capitalized-then-lowercase -
            -- normalize so "gabbaliator"/"GABBALIATOR" and "Gabbaliator"
            -- all resolve to the same name once broadcast and compared.
            local mainName = rest:sub(1, 1):upper() .. rest:sub(2):lower()
            if mainName:lower() == own:lower() then
                print('|cff33ff99GreenWallGuildRoster|r: ' .. ns.L["You can't set yourself as your own main."])
                return
            end
            GreenWallGuildRosterDB.mainLinks[own] = mainName
            print(('|cff33ff99GreenWallGuildRoster|r: ' .. ns.L['%s is now marked as an alt of %s.']):format(own, mainName))
        end
        -- Delta broadcasts only fire on online/offline transitions, so a
        -- field-only change like this would otherwise sit unsent until the
        -- next full resync. A slash command is a direct user action, same
        -- as a button click, so calling Broadcast() straight from here is
        -- safe and makes the change visible immediately.
        Broadcast()
    elseif ns.ToggleFrame then
        ns.ToggleFrame()
    end
end
