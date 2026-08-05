local ADDON_NAME, ns = ...

-- Addon message prefixes are capped at 16 chars.
local ADDON_MSG_PREFIX = 'GWGRoster'

ns.peerNames = {}
ns.ownTag = nil
ns.ownGuild = nil
ns.lastRosterUpdate = 0
ns.debugAddonMsg = false

local ResetGuildSessionState

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
    local guildName = GetGuildInfo('player')
    local oldTag, oldGuild = ns.ownTag, ns.ownGuild

    if not guildName then
        ns.peerNames = {}
        ns.ownTag = nil
        ns.ownGuild = nil
        if (oldTag or oldGuild) and ResetGuildSessionState then ResetGuildSessionState() end
        return false
    end

    local cfg = ParseConfig()
    if not cfg then
        -- Guild info text can be briefly unavailable while the roster loads. Preserve
        -- state only while Blizzard still reports the same guild; on a confirmed guild
        -- change, invalidate the old tag immediately so nothing is sent under it.
        if not oldGuild or oldGuild:lower() ~= guildName:lower() then
            ns.peerNames = {}
            ns.ownTag = nil
            ns.ownGuild = guildName
            if ResetGuildSessionState then ResetGuildSessionState() end
        end
        return false
    end

    ns.peerNames = cfg.peers
    local nextTag
    for tag, gname in pairs(cfg.peers) do
        if gname:lower() == guildName:lower() then
            nextTag = tag
            break
        end
    end
    ns.ownTag = nextTag
    ns.ownGuild = guildName

    if oldTag ~= ns.ownTag or not oldGuild or oldGuild:lower() ~= guildName:lower() then
        if ResetGuildSessionState then ResetGuildSessionState() end
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

-- '2' = Guild Master (rankIndex 0, always - GuildControlGetRankFlags comes
-- back empty for rank 0, so there's nothing to check there anyway), '1' =
-- officer, '0' = everyone else. "Officer" was tried twice before landing
-- here: first as GuildControlGetRankFlags' officer-chat-listen bit (index
-- 5), which live testing showed gets granted to non-officer ranks too
-- (Milchbar's "Neoyuki", a base "Mitglied" rank with no native crown, has
-- index 5 = true); then as a flat "rankIndex <= 1" cutoff, which undercounts
-- guilds using more than two officer-tier ranks (Saftladen's "Saftadel" is
-- rankIndex 2 and does have the native crown). Index 3 (its wowhead/addon-
-- ecosystem convention name is "Invite") is the one flag that actually
-- matched the native crown across every rank checked in both guilds -
-- true for every crowned rank (Milchbar's Offizier, Saftladen's
-- Saftlord/Saftadel), false for every uncrowned one (Milchbar's
-- Initiand/Mitglied, Saftladen's Fruchttiger/Milchbulle) - 9 for 9, no
-- exceptions, across two guilds with unrelated custom rank names/orders.
-- Pure badge-flag logic lives in Logic.lua (ns.RankBadge) so it's unit
-- testable without a real WoW client; this just supplies the real API call.
local function RankBadge(rankIndex)
    return ns.RankBadge(rankIndex, C_GuildInfo.GuildControlGetRankFlags)
end

-- Zone translation table (ZONE_EN_DE, ToCanonicalZone/FromCanonicalZone)
-- moved to ZoneData.lua, exposed as ns.ToCanonicalZone/ns.FromCanonicalZone.

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
-- A full resync every 10 minutes regardless bounds how stale things can
-- get if a message ever goes missing, since peers only refresh the
-- staleness flag off however long since they last heard about someone at
-- all.
--
-- Full snapshots are sent only after a presence-confirmed handshake. The
-- timestamp still bounds how often a sender includes unchanged online rows
-- if several confirmed exchanges happen during one session.
local lastOnlineSet = {}
local lastFullSyncTime = 0
local FULL_SYNC_INTERVAL = 600

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
-- every roster collection) means a one-off blip
-- self-corrects on the very next scan instead of propagating.
local MISSING_STREAK_THRESHOLD = 3
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

-- Sends a chunked roster payload to one target via ChatThrottleLib,
-- chaining one chunk at a time instead of a flat loop - the next chunk is
-- only ever enqueued from the previous one's callback, once it's
-- confirmed Enum.SendAddonMessageResult.Success (0). A target that fails
-- once fails identically for every remaining chunk too (observed live: a
-- wall of repeated "no player named X" system errors, one per chunk, for
-- a target that can't actually be reached) - chaining like this means we
-- never even enqueue the next chunk after a failure, rather than firing
-- them all up front and hoping to cancel the rest (CTL has no public
-- "cancel this queue" API, so that wouldn't actually stop anything
-- already queued).
local function SendChunkedTo(target, chunks, debugLabel)
    debugLabel = debugLabel or ''
    local queueName = ADDON_MSG_PREFIX .. ':' .. target
    local function sendChunk(i)
        if i > #chunks then return end
        ChatThrottleLib:SendAddonMessage('BULK', ADDON_MSG_PREFIX, ns.ownTag .. '#' .. chunks[i], 'WHISPER', target, queueName,
            function(_, didSend, sendResult)
                if ns.debugAddonMsg then
                    print(('|cff33ff99GreenWallGuildRoster|r: TX addon-msg%s to %s chunk %d/%d didSend=%s sendResult=%s'):format(debugLabel, target, i, #chunks, tostring(didSend), tostring(sendResult)))
                end
                if sendResult == 0 then
                    sendChunk(i + 1)
                end
            end)
    end
    sendChunk(1)
end

-- Sends a full roster snapshot to one specific whisper target - the same
-- payload/chunking used by the presence-confirmed whisper path. Shared by
-- the handshake initiator and the first-contact reply in MergePeerPayload.
local function SendFullRosterTo(target)
    if not ns.ownTag then return end
    local rows = CollectOwnRoster(true)
    if #rows == 0 then return end
    local chunks = ChunkRows(rows, 200)
    SendChunkedTo(target, chunks, ' (reply)')
end

-- A client is only eligible for a roster whisper after it was seen joining
-- GreenWall's shared channel and answered this small handshake.  Presence
-- does not guarantee delivery forever, but it avoids the stale-cache and
-- /who guesses that produced the repeated "player not reachable" messages.
local HELLO_PREFIX = 'GWGR_HELLO#'
local ACK_PREFIX = 'GWGR_ACK#'
local LOCAL_GUILD_PREFIX = 'GWGR_LOCAL#'
local HELLO_RETRY_SECONDS = 900
local SYNC_COOLDOWN_SECONDS = 600
local HANDSHAKE_DISPATCH_INTERVAL = 30
local presence = {}
local handshakeState = {}
local handshakeQueue = {}
local handshakeQueued = {}
local acceptedHello = {}

ResetGuildSessionState = function()
    wipe(lastOnlineSet)
    lastFullSyncTime = 0
    wipe(lastKnownMembers)
    wipe(missingStreak)
    wipe(presence)
    wipe(handshakeState)
    wipe(handshakeQueue)
    wipe(handshakeQueued)
    wipe(acceptedHello)
    ns.lastRosterUpdate = 0
end

local function ClientKey(name)
    -- CHAT_MSG_CHANNEL_* and CHAT_MSG_ADDON do not consistently include a
    -- realm suffix on every Classic client. The bridge channel is realm
    -- scoped, so the short character name is the stable key for matching a
    -- JOIN with its later ADDON acknowledgement.
    return name and (name:match('^[^-]+') or name):lower() or ''
end

local function SendControlMessage(target, message, label)
    ChatThrottleLib:SendAddonMessage('NORMAL', ADDON_MSG_PREFIX, message, 'WHISPER', target,
        ADDON_MSG_PREFIX .. ':control:' .. target, function(_, didSend, sendResult)
            if ns.debugAddonMsg then
                print(('|cff33ff99GreenWallGuildRoster|r: %s %s didSend=%s sendResult=%s'):format(
                    label, target, tostring(didSend), tostring(sendResult)))
            end
        end)
end

-- One confirmed cross-guild exchange is enough for every GuildRoster user
-- in the sender's own guild. Re-distribute received chunks via the normal
-- guild addon channel instead of making each local client repeat the same
-- full whisper sync independently.
local function SendLocalGuildPayload(tag, payload)
    ChatThrottleLib:SendAddonMessage('NORMAL', ADDON_MSG_PREFIX,
        LOCAL_GUILD_PREFIX .. tag .. '#' .. payload, 'GUILD', nil,
        ADDON_MSG_PREFIX .. ':guild:' .. tag)
end

local function QueueHandshake(player)
    if not ns.ownTag or not player or player == '' then return end
    local ownName = UnitName('player')
    if player:match('^[^-]+') == ownName then return end

    local key, now = ClientKey(player), GetTime()
    presence[key] = player
    local state = handshakeState[key]
    if (state and state.retryAfter > now) or handshakeQueued[key] then return end

    -- The queue deliberately releases just one HELLO every 30 seconds.
    -- A large guild therefore cannot turn one channel join into a burst of
    -- dozens of whispers or full-roster transfers; every visible client is
    -- eventually considered, including clients already present at login.
    handshakeQueued[key] = true
    handshakeQueue[#handshakeQueue + 1] = key
end

local function ServiceHandshakeQueue()
    local now = GetTime()
    while #handshakeQueue > 0 do
        local key = table.remove(handshakeQueue, 1)
        handshakeQueued[key] = nil
        local player = presence[key]
        local state = handshakeState[key]
        if player and (not state or state.retryAfter <= now) then
            local nonce = tostring(math.random(100000, 999999))
            handshakeState[key] = { nonce = nonce, retryAfter = now + HELLO_RETRY_SECONDS }
            SendControlMessage(player, HELLO_PREFIX .. ns.ownTag .. '#' .. nonce, 'TX handshake to')
            return
        end
    end
end

local function QueueDueHandshakes()
    for _, player in pairs(presence) do
        QueueHandshake(player)
    end
end

local function RefreshChannelPresence()
    if not GreenWallAPI or not GreenWallAPI.GetChannelNumbers
        or not GetNumChannelMembers or not GetChannelRosterInfo then return end
    local guildChannel = GreenWallAPI.GetChannelNumbers()[1]
    if not guildChannel or guildChannel == 0 then return end

    -- Channel join events only describe changes after the addon is loaded.
    -- Enumerating the current roster closes the "everyone was already
    -- online when I logged in" gap without using /who.
    wipe(presence)
    local memberCount = GetNumChannelMembers(guildChannel) or 0
    for index = 1, memberCount do
        local player = GetChannelRosterInfo(guildChannel, index)
        if player and player ~= '' then QueueHandshake(player) end
    end
end

local function HandlePresence(player, joined)
    local key = ClientKey(player)
    if joined then
        QueueHandshake(player)
    else
        -- A client that left the bridge is no longer a valid sync target.
        presence[key] = nil
        handshakeState[key] = nil
        handshakeQueued[key] = nil
    end
end

local function IsGuildChannel(number)
    if not GreenWallAPI or not GreenWallAPI.GetChannelNumbers then return false end
    -- GetChannelNumbers returns the normal guild bridge first and the
    -- optional officer bridge second. Roster presence belongs only to the
    -- normal bridge; using the officer channel too would create duplicate
    -- handshakes for officers.
    local guildChannel = GreenWallAPI.GetChannelNumbers()[1]
    return guildChannel ~= 0 and guildChannel == number
end


-- Shared by both transports: merges a received chunk into the peer cache.
-- Only accepted from a tag that's actually one of GreenWall's declared
-- GWp co-guilds - otherwise a stranger who happens to land on the same
-- channel name (channel names are realm-wide, first-come-first-served)
-- could get merged into the roster as if they were part of the
-- confederation.
--
-- sender (optional, whisper only): when this is the FIRST data we've ever
-- gotten from this co-guild, reply with our own roster right back at
-- whoever just sent it, instead of waiting for our own next scheduled
-- broadcast cycle (up to 2 minutes away) to notice they're now a known
-- target. Otherwise a ping-triggered first contact stayed one-directional
-- until that delay passed - we'd have their data, but they wouldn't have
-- ours yet.
-- source ('broadcast' or 'whisper'): which transport this payload arrived
-- over, stored per-entry purely for the roster window's source-marker
-- column - has no effect on sync behavior itself.
-- Best-effort integration with Prat-3.0 (an optional third-party addon, not
-- a dependency of this one). Prat keeps its own name->level cache
-- (Prat:GetModule('PlayerNames'):addName(...)) that its native chat
-- formatting reads to show "[Level:Name]" with class-color and a working
-- whisper/invite right-click - it already does this for real guildmates by
-- scanning GetGuildRosterInfo itself, but has no level data for a
-- GreenWall-bridged co-guild member, so those chat lines fall back to a
-- plain, level-less name. We already learn a peer's level/class from sync
-- data anyway, so feeding it into Prat's own cache here makes Prat's
-- existing native formatting pick it up automatically - no need to touch
-- GreenWall's or Prat's own files at all. Fully optional: no-ops silently
-- if Prat isn't installed, and pcall-wrapped since Prat's internals aren't
-- ours to depend on breaking safely.
local function FeedPratNameCache(name, classFile, level)
    if not GreenWallGuildRosterDB or not GreenWallGuildRosterDB.pratIntegration then return end
    if not name or not level or level <= 0 then return end
    if not (Prat and Prat.GetModule) then return end
    local ok, module = pcall(Prat.GetModule, Prat, 'PlayerNames')
    if ok and module and module.addName then
        pcall(module.addName, module, name, nil, classFile, level, nil, 'GUILD')
    end
end

-- Prat's own cache is keyed by the exact sender string it sees on the chat
-- line (e.g. "Hekinata-Sou", with whatever realm suffix GreenWall's bridge
-- embeds) - GreenWallGuildRoster's own sync data only ever has the bare
-- short name (guild rosters never carry a realm suffix), so seeding the
-- cache from sync data alone stores it under the wrong key and Prat's own
-- lookup on the actual chat line misses every time. GreenWall replicates
-- bridged chat by calling ChatFrame_MessageEventHandler directly, which
-- still runs the normal ChatFrame_AddMessageEventFilter chain - registering
-- one here gets us the exact sender string Prat itself will look up with,
-- so we can seed the *correct* key right as the line comes in. Returns
-- false always: this only ever reads/reacts, never suppresses the message.
local function ChatLevelCacheFilter(_, _, _, sender)
    if not (GreenWallGuildRosterDB and GreenWallGuildRosterDB.pratIntegration) then return false end
    if not sender or sender == '' then return false end
    local shortName = sender:match('^[^%-]+') or sender
    for _, store in pairs(GreenWallGuildRosterDB and GreenWallGuildRosterDB.peers or {}) do
        local info = store[shortName]
        if info and info.level and info.level > 0 then
            FeedPratNameCache(sender, info.class, info.level)
            break
        end
    end
    return false
end
ChatFrame_AddMessageEventFilter('CHAT_MSG_GUILD', ChatLevelCacheFilter)
ChatFrame_AddMessageEventFilter('CHAT_MSG_OFFICER', ChatLevelCacheFilter)

-- Deeper Prat-3.0 integration: hide the realm suffix and show the co-guild
-- tag *inside* the [Level:Name] bracket (colored to match that guild, same
-- palette as the roster window), instead of GreenWall's own literal
-- "<Tag>" text prefix in the message body.
--
-- Traced Prat's actual message pipeline (services/chatsections.lua +
-- addon/addon.lua) rather than guessing: chat lines are built from a fixed
-- ordered list of named fields (SplitMessageIdx), concatenated verbatim by
-- Prat.BuildChatText. PlayerNames.lua injects PLAYERGROUP/POSTPLAYERDELIM
-- into that list via RegisterMessageItem (originally meant for showing a
-- raid subgroup number) - it only ever *sets* those fields when its own
-- "am I grouped with them" condition is true, it never clears them
-- otherwise. So setting them ourselves in our own Prat_FrameMessage hook
-- (fired before BuildChatText runs, same event PlayerNames itself uses)
-- makes Prat render our value in that slot regardless of group state.
-- Clearing message.SERVER here works the same way ServerNames.lua's own
-- "hide realm" option does internally, just scoped to bridged senders only
-- instead of every chat line globally.
-- Palette-cycling logic lives in Logic.lua (ns.NewPaletteAssigner), shared
-- with RosterFrame.lua's own per-guild coloring so both stay visually
-- consistent instead of each hand-rolling their own color cache.
local ColorHexForTag = ns.NewPaletteAssigner()

local PratFrameMessageHook = {}
function PratFrameMessageHook:Prat_FrameMessage(_, message)
    if not (GreenWallGuildRosterDB and GreenWallGuildRosterDB.pratIntegration) then return end
    if not message or not message.PLAYERLINK or message.PLAYERLINK == '' then return end
    local shortName = message.PLAYERLINK:match('^[^%-]+') or message.PLAYERLINK
    for tag, store in pairs(GreenWallGuildRosterDB.peers or {}) do
        local info = store[shortName]
        if info and info.level and info.level > 0 then
            message.SERVER = ''
            message.PLAYERGROUP = ('|cff%s%s|r'):format(ColorHexForTag(tag), tag)
            message.POSTPLAYERDELIM = ':'
            break
        end
    end
end
local function MergePeerPayload(tag, payload, sender, source)
    if not tag or not payload or tag == ns.ownTag then return end
    if not ns.peerNames[tag] then return end

    local isFirstContact = sender and not next(GreenWallGuildRosterDB.peers[tag] or {})

    GreenWallGuildRosterDB.peers[tag] = GreenWallGuildRosterDB.peers[tag] or {}
    local store = GreenWallGuildRosterDB.peers[tag]

    -- Defense in depth against a sender whose own leave-detection glitched
    -- (older build, or the sanity guard in CollectOwnRoster missed some
    -- other edge case) - a single payload chunk claiming a large chunk of
    -- an already-known guild has left all at once is far more likely to be
    -- a bad read than a real mass departure. Skip leave markers for this
    -- chunk in that case (other rows in it still apply normally); a
    -- genuine departure gets picked up again on the next real sync.
    local knownCount = 0
    for _ in pairs(store) do knownCount = knownCount + 1 end
    local leaveCount = 0
    for row in payload:gmatch('[^~]+') do
        local online = select(6, strsplit(';', row))
        if online == LEAVE_MARKER then leaveCount = leaveCount + 1 end
    end
    local suspiciousLeaveBurst = leaveCount >= 3 and knownCount > 0 and leaveCount > knownCount * 0.5
    if suspiciousLeaveBurst and ns.debugAddonMsg then
        print(('|cff33ff99GreenWallGuildRoster|r: MergePeerPayload: ignoring %d leave-marker(s) from tag %s (looks like a bad read, known=%d).'):format(leaveCount, tag, knownCount))
    end

    for row in payload:gmatch('[^~]+') do
        local name, class, level, zone, note, online, linkedMain, badge = strsplit(';', row)
        if name and name ~= '' then
            if online == LEAVE_MARKER then
                if not suspiciousLeaveBurst then
                    store[name] = nil
                end
            else
                local levelNum = tonumber(level) or 0
                store[name] = {
                    class = class, level = levelNum, zone = zone,
                    note = note, online = online == '1', ts = time(),
                    linkedMain = (linkedMain and linkedMain ~= '') and linkedMain or nil,
                    badge = badge, source = source,
                }
                FeedPratNameCache(name, class, levelNum)
                -- A real player can only be in one guild at a time - if
                -- this name is a confirmed member of tag's guild, any
                -- entry still cached under a DIFFERENT co-guild tag is a
                -- stale leftover from before they switched guilds (e.g.
                -- Milchbar -> Saftladen), which would otherwise sit there
                -- forever unless someone still active in the OLD guild
                -- happens to notice the departure across
                -- MISSING_STREAK_THRESHOLD consecutive scans. Purge it
                -- eagerly instead of waiting on that.
                for otherTag, otherStore in pairs(GreenWallGuildRosterDB.peers) do
                    if otherTag ~= tag and otherStore[name] then
                        otherStore[name] = nil
                    end
                end
            end
        end
    end

    RequestRefresh()

    if isFirstContact then
        if ns.debugAddonMsg then
            print(('|cff33ff99GreenWallGuildRoster|r: MergePeerPayload: first contact with tag %s, replying to %s immediately.'):format(tag, sender))
        end
        SendFullRosterTo(sender)
    end
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
    MergePeerPayload(tag, payload, sender, 'broadcast')
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
    if channel == 'GUILD' then
        local tag, payload = message:match('^' .. LOCAL_GUILD_PREFIX .. '(%a+)#(.*)$')
        if tag and payload then
            MergePeerPayload(tag, payload, nil, 'whisper')
        end
        return
    end
    if channel ~= 'WHISPER' then return end

    local helloTag, helloNonce = message:match('^' .. HELLO_PREFIX .. '(%a+)#(%d+)$')
    if helloTag then
        -- One acknowledged sender per co-guild is sufficient: received
        -- chunks are fanned out to the sender's own guild through the safe
        -- GUILD addon-message channel below. This prevents every visible
        -- client from triggering the same full whisper sync.
        if helloTag ~= ns.ownTag and ns.peerNames[helloTag] then
            local now = GetTime()
            if not acceptedHello[helloTag] or acceptedHello[helloTag] <= now then
                acceptedHello[helloTag] = now + SYNC_COOLDOWN_SECONDS
                SendControlMessage(sender, ACK_PREFIX .. ns.ownTag .. '#' .. helloNonce, 'TX handshake acknowledgement to')
            end
        end
        return
    end

    local ackTag, ackNonce = message:match('^' .. ACK_PREFIX .. '(%a+)#(%d+)$')
    if ackTag then
        local pending = handshakeState[ClientKey(sender)]
        if pending and pending.nonce == ackNonce and ackTag ~= ns.ownTag and ns.peerNames[ackTag] then
            -- Keep a successful pair quiet until the normal sync cooldown
            -- elapses, then let the presence queue consider it again.
            pending.nonce = nil
            pending.retryAfter = GetTime() + SYNC_COOLDOWN_SECONDS
            -- Keep the expensive roster transfer outside the join event and
            -- behind a successful acknowledgement.
            C_Timer.After(math.random(3, 8), function()
                SendFullRosterTo(sender)
            end)
        end
        return
    end

    local tag, payload = message:match('^(%a+)#(.*)$')
    MergePeerPayload(tag, payload, sender, 'whisper')
    if tag and payload and tag ~= ns.ownTag and ns.peerNames[tag] then
        SendLocalGuildPayload(tag, payload)
    end
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
frame:RegisterEvent('PLAYER_GUILD_UPDATE')
frame:RegisterEvent('CHAT_MSG_ADDON')
frame:RegisterEvent('CHAT_MSG_CHANNEL_JOIN')
frame:RegisterEvent('CHAT_MSG_CHANNEL_LEAVE')

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
        -- /who discovery was removed: discard its obsolete cached rows on
        -- the first load after updating, so they cannot reappear in a later
        -- version or inflate the saved-variable file indefinitely.
        GreenWallGuildRosterDB.whoSeen = nil
        if GreenWallGuildRosterDB.pratIntegration == nil then
            GreenWallGuildRosterDB.pratIntegration = false
        end
        GreenWallGuildRosterDB.whoDiscoveryEnabled = nil
        if ns.ApplyMinimapButtonVisibility then ns.ApplyMinimapButtonVisibility() end
        if ns.ApplyMinimapButtonPosition then ns.ApplyMinimapButtonPosition() end
    elseif event == 'PLAYER_ENTERING_WORLD' then
        C_GuildInfo.GuildRoster()
        EnsureAPIHandler()
        RecordCurrentInstance()
        if not C_AddOns.IsAddOnLoaded('GreenWall') then
            print('|cffff3333GreenWallGuildRoster|r: ' .. ns.L['GreenWall is not installed or not enabled - this addon needs it (get "GreenWall" from CurseForge) to bridge with your co-guilds.'])
        end
        C_Timer.After(3, function()
            UpdateConfig()
            RefreshChannelPresence()
            -- Desynchronize clients that loaded during the same loading
            -- screen before releasing the first queued HELLO.
            C_Timer.After(math.random(2, 5), ServiceHandshakeQueue)
            -- Backfill Prat's name cache from peer data already known from
            -- a previous session, so chat lines look right immediately at
            -- login instead of only after the next sync updates someone.
            for _, store in pairs(GreenWallGuildRosterDB.peers or {}) do
                for name, info in pairs(store) do
                    FeedPratNameCache(name, info.class, info.level)
                end
            end
            -- Registered here, not at file-load time: Prat isn't a declared
            -- dependency, so there's no guarantee its Prat global exists
            -- yet while this file's own top-level code runs. By
            -- PLAYER_ENTERING_WORLD every addon has finished loading.
            if Prat and Prat.RegisterChatEvent then
                Prat.RegisterChatEvent(PratFrameMessageHook, 'Prat_FrameMessage')
            end
        end)
    elseif event == 'GUILD_ROSTER_UPDATE' then
        EnsureAPIHandler()
        UpdateConfig()
        C_Timer.After(2, RefreshChannelPresence)
        RequestRefresh()
    elseif event == 'PLAYER_GUILD_UPDATE' then
        -- Fires for joining, leaving and switching guilds. Invalidate the old identity
        -- immediately, then retry after Blizzard has populated the new guild info text.
        UpdateConfig()
        C_GuildInfo.GuildRoster()
        C_Timer.After(2, function()
            UpdateConfig()
            RefreshChannelPresence()
            RequestRefresh()
        end)
    elseif event == 'CHAT_MSG_ADDON' then
        OnAddonMessage(...)
    elseif event == 'CHAT_MSG_CHANNEL_JOIN' or event == 'CHAT_MSG_CHANNEL_LEAVE' then
        local _, player, _, _, _, _, _, channelNumber = ...
        if IsGuildChannel(channelNumber) then
            HandlePresence(player, event == 'CHAT_MSG_CHANNEL_JOIN')
        end
    end
end)

-- Retry presence-confirmed peers only. This never consults /who or the old
-- roster cache; a target that leaves the GreenWall channel is removed at
-- once and cannot be retried until it appears again.
local function ScheduleHandshakeService()
    C_Timer.After(math.random(HANDSHAKE_DISPATCH_INTERVAL - 5, HANDSHAKE_DISPATCH_INTERVAL + 5), function()
        QueueDueHandshakes()
        ServiceHandshakeQueue()
        ScheduleHandshakeService()
    end)
end
ScheduleHandshakeService()

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
        print('  |cffffd200/gwgr setmain <name>|r - ' .. ns.L["/gwgr setmain <name> - mark the character you're on as an alt of <name>; no name clears it"])
        print('  |cffffd200/gwgr status|r - ' .. ns.L['/gwgr status - show GreenWallAPI availability, own tag, and known confederation tags'])
        print('  |cffffd200/gwgr debug|r - ' .. ns.L['/gwgr debug - toggle addon-message RX/TX logging'])
        print('  |cffffd200/gwgr minimap|r - ' .. ns.L['/gwgr minimap - toggle the minimap button (also in Options > AddOns > GreenWall GuildRoster)'])
        print('  |cffffd200/gwgr exportzones|r - ' .. ns.L['/gwgr exportzones - export all known zone names for your client language, for building translation tables'])
        print('  |cffffd200/gwgr help|r - ' .. ns.L['/gwgr help - this list'])
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
        print(('|cff33ff99GreenWallGuildRoster|r: ' .. ns.L['Exported %d zone names for locale "%s" into SavedVariables.']):format(count, GetLocale()))
        print('|cff33ff99GreenWallGuildRoster|r: ' .. ns.L['/reload or log out to flush to disk, then find GreenWallGuildRosterDB.zoneExport in your SavedVariables/GreenWallGuildRoster.lua and send it over.'])
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
