local ADDON_NAME, ns = ...

-- Distinct from GreenWall's own single-letter opcodes (C/B/N/R/M/E) so our
-- traffic can never be mistaken for theirs on the shared channel.
local MSG_PREFIX = 'GWGR'

GreenWallGuildRosterDB = GreenWallGuildRosterDB or { peers = {} }
GreenWallGuildRosterDB.peers = GreenWallGuildRosterDB.peers or {}

ns.peerNames = {}
ns.ownTag = nil
ns.ownGuild = nil
ns.channelName = nil
ns.channelPassword = nil
ns.channelNumber = nil
ns.lastRosterUpdate = 0

-- Reads GreenWall's own GWp directives from the guild info page purely for
-- the tag <-> guild name mapping (harmless, read-only). The actual roster
-- traffic does NOT reuse GreenWall's GWc bridge channel: GreenWall hashes
-- every message it sends and flags anything on that channel it doesn't
-- recognize as "message corruption" from another addon - which is exactly
-- what happened when this addon shared it. So the roster channel comes
-- from its own separate directive, "GWGRoster:name:password", which
-- GreenWall's parser ignores (it only matches "GW" + a single lowercase
-- letter + ":", and the "G" in "GWGRoster" breaks that pattern).
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
    local channel, password = info:match('GWGRoster:([^:\r\n]+):([^\r\n]*)')
    if channel and channel ~= '' then
        cfg.channel = strtrim(channel)
        cfg.password = strtrim(password or '')
    end
    return cfg
end

local function JoinChannel()
    if not ns.channelName then return end
    JoinTemporaryChannel(ns.channelName, ns.channelPassword)
    local number = GetChannelName(ns.channelName)
    if number and number > 0 then
        ns.channelNumber = number
        -- Keep it out of the visible chat frames, same as GreenWall does.
        for i = 1, 10 do
            local frameChannels = { GetChatWindowMessages(i) }
            for _, v in ipairs(frameChannels) do
                if v == ns.channelName then
                    local cf = _G['ChatFrame' .. i]
                    if cf then ChatFrame_RemoveChannel(cf, ns.channelName) end
                end
            end
        end
    else
        ns.channelNumber = nil
        C_Timer.After(5, JoinChannel)
    end
end

local function UpdateConfig()
    local cfg = ParseConfig()
    if not cfg or not cfg.channel then return false end
    local guildName = GetGuildInfo('player')
    if not guildName then return false end

    ns.peerNames = cfg.peers
    for tag, gname in pairs(cfg.peers) do
        if gname:lower() == guildName:lower() then
            ns.ownTag = tag
            ns.ownGuild = gname
        end
    end

    if ns.channelName ~= cfg.channel or ns.channelPassword ~= cfg.password then
        ns.channelName = cfg.channel
        ns.channelPassword = cfg.password
        JoinChannel()
    end
    return true
end

-- Strips characters that would either break our own field/row delimiters
-- or trip SendChatMessage's "invalid escape code" guard against bare '|'.
local function Sanitize(s)
    if not s or s == '' then return '' end
    return (s:gsub('[|;~]', ''))
end

local function CollectOwnRoster()
    if not ns.ownTag then return {} end
    local rows = {}
    local total = GetNumGuildMembers() or 0
    for i = 1, total do
        local name, _, _, level, _, zone, note, _, online, _, classFile = GetGuildRosterInfo(i)
        if name then
            name = name:match('^[^-]+') or name
            rows[#rows + 1] = strjoin(';', Sanitize(name), classFile or '', tostring(level or 0), Sanitize(zone), Sanitize(note), online and '1' or '0')
        end
    end
    return rows
end

-- Splits the roster into chat-message-sized chunks. Sent as plain (but
-- hidden) channel chat, the same transport GreenWall itself already uses
-- successfully for its own bridging - not SendAddonMessage, which turned
-- out not to reach the other side on this setup.
--
-- SendChatMessage is a protected function in this client build: calling it
-- from a timer callback or an automatic event handler gets silently
-- blocked (ADDON_ACTION_BLOCKED). So this only ever runs synchronously,
-- and only from a direct user action (slash command or button click) -
-- never staggered via C_Timer.After, never called from an event handler.
local function Broadcast()
    if not ns.channelNumber or not ns.ownTag then return end
    local rows = CollectOwnRoster()
    if #rows == 0 then return end

    local chunks = {}
    local chunk, chunkLen = {}, 0
    for _, row in ipairs(rows) do
        if chunkLen + #row + 1 > 200 and #chunk > 0 then
            chunks[#chunks + 1] = table.concat(chunk, '~')
            chunk, chunkLen = {}, 0
        end
        chunk[#chunk + 1] = row
        chunkLen = chunkLen + #row + 1
    end
    if #chunk > 0 then
        chunks[#chunks + 1] = table.concat(chunk, '~')
    end

    for _, payload in ipairs(chunks) do
        SendChatMessage(MSG_PREFIX .. ns.ownTag .. '#' .. payload, 'CHANNEL', nil, ns.channelNumber)
    end

    GreenWallGuildRosterDB.lastBroadcast = time()
    if ns.RefreshFrame then ns.RefreshFrame() end
end

local function OnChannelMessage(message, sender)
    local tag, payload = message:match('^' .. MSG_PREFIX .. '(%a+)#(.*)$')
    if not tag or not payload or tag == ns.ownTag then return end

    GreenWallGuildRosterDB.peers[tag] = GreenWallGuildRosterDB.peers[tag] or {}
    local store = GreenWallGuildRosterDB.peers[tag]
    for row in payload:gmatch('[^~]+') do
        local name, class, level, zone, note, online = strsplit(';', row)
        if name and name ~= '' then
            store[name] = {
                class = class, level = tonumber(level) or 0, zone = zone,
                note = note, online = online == '1', ts = time(),
            }
        end
    end

    if ns.RefreshFrame then ns.RefreshFrame() end
end

local frame = CreateFrame('Frame')
frame:RegisterEvent('PLAYER_ENTERING_WORLD')
frame:RegisterEvent('GUILD_ROSTER_UPDATE')
frame:RegisterEvent('CHAT_MSG_CHANNEL')

frame:SetScript('OnEvent', function(_, event, ...)
    if event == 'PLAYER_ENTERING_WORLD' then
        C_GuildInfo.GuildRoster()
        C_Timer.After(3, UpdateConfig)
    elseif event == 'GUILD_ROSTER_UPDATE' then
        UpdateConfig()
        if ns.RefreshFrame then ns.RefreshFrame() end
    elseif event == 'CHAT_MSG_CHANNEL' then
        local message, sender, _, _, _, _, _, chanNum = ...
        if ns.channelNumber and chanNum == ns.channelNumber then
            OnChannelMessage(message, sender)
        end
    end
end)

-- No automatic/periodic broadcasting: SendChatMessage only works when
-- called directly from a user action (see the note on Broadcast above), so
-- everyone needs to hit the Broadcast button or run "/gwgr broadcast"
-- themselves every so often to refresh what the other co-guild sees.
ns.Broadcast = Broadcast

SLASH_GWGROSTER1 = '/gwgr'
SlashCmdList['GWGROSTER'] = function(msg)
    msg = (msg or ''):lower():match('^%s*(.-)%s*$')
    if msg == 'broadcast' then
        Broadcast()
        print('|cff33ff99GreenWallGuildRoster|r: Broadcast gesendet.')
    elseif msg == 'status' then
        print(('|cff33ff99GreenWallGuildRoster|r: Kanal=%s (#%s), eigenes Tag=%s'):format(
            tostring(ns.channelName), tostring(ns.channelNumber), tostring(ns.ownTag)))
    elseif ns.ToggleFrame then
        ns.ToggleFrame()
    end
end
