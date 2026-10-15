-- Exercise real Core + Versioning wiring, including capability/session gates.
local root = (arg[0]:match('(.*[/\\])') or './') .. '../'
local dotted = arg[2] == '--dotted' or arg[1] == '--dotted'
local ownTag, peerTag = dotted and 'Comp.' or 'A', dotted and 'Fel.' or 'B'
local controls = {}
local now, frames, timers, apiHandler, sent, queued = 100, {}, {}, nil, {}, nil
local channel, channelMembers = 0, {}
local displayIndex, namesPending, countReady = 3, false, false
local selected, selections, channelWindowOpen = 2, {}, false
GetSelectedDisplayChannel = function() return selected end
SetSelectedDisplayChannel = function(index)
    selected = index; selections[#selections + 1] = index
end
ChannelFrame = { IsShown = function() return channelWindowOpen end }
GetNumDisplayChannels = function() return 4 end
GetChannelDisplayInfo = function(index)
    if index == 1 then return 'Header', true, false, channel, 500, true end
    if index == displayIndex and channel > 0 then
        return 'GreenWall', false, false, channel, countReady and #channelMembers or nil, true
    end
    return 'Other', false, false, 99, 100, true
end
GetNumChannelMembers = function() error('must use display info count, not chat number') end
GetChannelRosterInfo = function(channelIndex, index)
    assert(channelIndex == displayIndex and channelIndex ~= channel, 'wrong roster index')
    if not namesPending then return channelMembers[index] end
end
GetTime = function() return now end
time = function() return 1790670000 + now end
GetLocale = function() return 'enUS' end
wipe = function(t) for k in pairs(t) do t[k] = nil end end
strtrim = function(s) return s:match('^%s*(.-)%s*$') end
strjoin = function(separator, ...) return table.concat({...}, separator) end
strsplit = function(separator, value)
    local fields = {}; for field in (value .. separator):gmatch('(.-)' .. separator) do fields[#fields + 1] = field end
    return table.unpack(fields)
end
local guild = 'LocalGuild'
GetGuildInfo = function() return guild end
GetGuildInfoText = function() return 'GW:p:LocalGuild:' .. ownTag .. '\nGW:p:PeerGuild:' .. peerTag end
GetNumGuildMembers = function() return 1 end
GetGuildRosterInfo = function() return 'Alice', '', 0, 60, 'Mage', 'Stormwind', '', '', true, '', 'MAGE' end
UnitName = function() return 'Alice' end
IsInInstance = function() return false end
C_GuildInfo = { GuildRoster = function() end, GuildControlGetRankFlags = function() return {} end }
C_AddOns = { IsAddOnLoaded = function() return true end, GetAddOnMetadata = function() return '1.3.0' end }
C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
if arg[1] == '--namespaced' or arg[1] == '--mixed' then
    C_ChatInfo.GetChannelRosterInfo, GetChannelRosterInfo = GetChannelRosterInfo, nil
    if arg[1] == '--namespaced' then
        C_ChatInfo.GetNumChannelMembers, GetNumChannelMembers = GetNumChannelMembers, nil
    end
end
ChatThrottleLib = { SendAddonMessage = function(_, _, _, message) controls[#controls + 1] = message end }
C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay, fn } end }
CreateFrame = function()
    local f = { events = {}, RegisterEvent = function(self, e) self.events[e] = true end,
        SetScript = function(self, _, fn) self.event = fn end }
    frames[#frames + 1] = f; return f
end
ChatFrame_AddMessageEventFilter = function() end
SlashCmdList = {}
GreenWallGuildRosterDB = { versioning = { knownCapabilities = { bob = { capabilities = 'TX1', seenAt = time() } } } }
GreenWallAPI = { version = 1, GetChannelNumbers = function() return { channel } end,
    AddMessageHandler = function(fn, _, priority) assert(priority == 0); apiHandler = fn end,
    SendMessage = function(_, payload) sent[#sent + 1] = payload end }
local testHardwareAPI = { VERSION = 1, IsReady = function() return true end,
    Enqueue = function(_, _, payload, options) queued = { payload = payload, options = options }; return true end,
    Cancel = function() queued = nil end }
local ns = { HardwareAPI = testHardwareAPI }
for _, path in ipairs({ 'Core/Logic.lua', 'Core/ZoneData.lua', 'Core/TransactionProtocol.lua',
        'Core/PassThrough.lua', 'Core/Core.lua', 'Core/Versioning.lua' }) do
    assert(loadfile(root .. path))('GreenWallGuildRoster', ns)
end
local function event(name, ...)
    for _, f in ipairs(frames) do if f.events[name] then f.event(f, name, ...) end end
end
local function service()
    for i, timer in ipairs(timers) do
        if timer[1] == 5 then table.remove(timers, i); timer[2](); return end
    end
    error('missing pass-through timer')
end
local function msg(text, sender)
    event('CHAT_MSG_ADDON', 'GWGRoster', text, 'WHISPER', sender or 'Bob')
end
local function handshakeService()
    for i, timer in ipairs(timers) do
        if timer[1] >= 25 and timer[1] <= 35 then
            table.remove(timers, i); timer[2](); return
        end
    end
    error('missing handshake timer')
end
local function finishRequest()
    for i, timer in ipairs(timers) do
        if timer[1] == 4 then table.remove(timers, i); timer[2](); return end
    end
    error('missing roster request callback')
end
local function sendEcho()
    assert(queued)
    local item = queued; queued = nil
    assert(item.options.validate())
    item.options.onSubmit()
    GreenWallAPI.SendMessage('GreenWallGuildRoster', item.payload)
    -- Actual GreenWall dispatch labels own echoes as BOTH echo and guild.
    apiHandler('GreenWallGuildRoster', 'Alice', item.payload, true, true)
end
event('ADDON_LOADED', 'GreenWallGuildRoster')
event('GUILD_ROSTER_UPDATE')
service(); assert(not queued and #sent == 0)
-- Neither a channel-member join event nor a guild update arrives after login.
handshakeService(); assert(ns.syncStats.helloTX == 0)
channel = 1
handshakeService(); assert(ns.syncStats.helloTX == 0, 'empty roster guessed a peer')
msg('GWGR_HELLO#' .. peerTag .. '#123') -- association arrives BEFORE channel presence
assert(ns.syncStats.ackTX == 1, 'HELLO tag was not recognized')
assert(selected == displayIndex and #selections == 1, 'missing count did not request roster')
handshakeService(); assert(#selections == 1, 'inflight request repeated')
countReady = true
channelMembers = { 'Alice', 'Bob' }
finishRequest()
assert(selected == 2 and #selections == 2, 'previous channel selection not restored')
handshakeService()
assert(ns.syncStats.helloTX == 1 and #sent == 0, 'late channel roster not discovered')
local nonce
for _, message in ipairs(controls) do
    nonce = message:match('^GWGR_HELLO#[^#]+#(%d+)$') or nonce
end
assert(nonce)
local timerCount = #timers
msg('GWGR_ACK#' .. peerTag .. '#' .. nonce)
assert(#timers == timerCount + 1, 'ACK did not schedule roster transfer')
-- Isolate this scheduled transfer from the delay-based service helpers below:
-- its randomized 3-8s delay can overlap the 4s roster or 5s sender service.
table.remove(timers, timerCount + 1)
-- A moved display index must be resolved again on the next scan.
displayIndex = 4
handshakeService()
assert(ns.syncStats.helloTX == 1, 'rescan reset handshake cooldown')
-- Transiently missing names must not discard already-confirmed presence.
namesPending = true
handshakeService()

service(); assert(not queued, 'persisted capability authorized new session')
msg('GWGR_CAPS#TX10'); service(); assert(not queued, 'substring matched TX1')
msg('GWGR_CAPS#TX1'); service(); assert(queued and #sent == 0)
assert(not GreenWallGuildRosterDB.lastBroadcast)
sendEcho(); assert(not GreenWallGuildRosterDB.lastBroadcast)
sendEcho(); assert(not GreenWallGuildRosterDB.lastBroadcast)
sendEcho(); assert(GreenWallGuildRosterDB.lastBroadcast == time())
assert(ns.syncStats.passThroughEchoed == 3 and ns.syncStats.committed == 1)
-- A complete roster without Bob revokes presence even with fresh TX1 data.
namesPending = false
channelMembers = { 'Alice' }
handshakeService()
now = now + 601
msg('GWGR_CAPS#TX1'); service(); assert(not queued, 'departed peer still authorized sending')
channelMembers = { 'Alice', 'Bob' }
handshakeService()

now = now + 601
msg('GWGR_CAPS#TX1'); service(); assert(queued)
ns.SetSafePassThrough(false); assert(not queued)
ns.SetSafePassThrough(true); service(); assert(queued)
-- Changing guild cancels old-tag work and clears session capabilities.
guild = nil; event('PLAYER_GUILD_UPDATE'); assert(not queued)
assert(not ns.HasTransactionCapability('Bob'))
-- Manual legacy broadcast still operates with no broker.
guild = 'LocalGuild'; event('GUILD_ROSTER_UPDATE')
ns.HardwareAPI = nil
local before = #sent
ns.Broadcast()
assert(#sent == before + 1 and not sent[#sent]:find('T1|', 1, true))
-- Background acquisition must not move an open UI or override user changes.
countReady = false
now = now + 31
channelWindowOpen = true
local selectionCount, messageCount = #selections, #sent
handshakeService(); assert(#selections == selectionCount, 'open channel UI was changed')
channelWindowOpen = false
handshakeService(); assert(selected == displayIndex)
selected = 1 -- user changes selection while the response is pending
finishRequest(); assert(selected == 1, 'user selection overwritten')
now = now + 31
selected = 2
handshakeService()
channelWindowOpen = true
finishRequest(); assert(selected == displayIndex, 'selection changed while channel UI opened')
channelWindowOpen = false
handshakeService(); assert(#sent == messageCount, 'roster request sent protected chat')
print('Pass-through runtime: fresh capabilities, own echo dispatch, commit, toggle, guild reset and manual fallback passed.')

ns.HardwareAPI = testHardwareAPI
countReady = true
handshakeService()
msg('GWGR_HELLO#' .. peerTag .. '#12345'); msg('GWGR_CAPS#TX1')
local beforeRestart = #sent
SlashCmdList.GWGROSTER('syncrestart')
assert(#sent == beforeRestart, 'restart command sent protected chat')
assert(ns.GetSyncProgress().total > 0, 'restart did not prepare transaction')
local echoes = 0
ns.HardwareEcho = function() echoes = echoes + 1 end
sendEcho()
assert(echoes == 1, 'accepted echo did not reach source diagnostics')
print('Runtime: restart prepares without sending and accepted echo reaches input diagnostics.')

local function row(name) return name .. ';MAGE;60;Stormwind;;1;;0' end
apiHandler('GreenWallGuildRoster', 'Bob', peerTag .. '#' .. row('Legacy'), false, false)
assert(GreenWallGuildRosterDB.peers[peerTag].Legacy, 'legacy broadcast tag rejected')
msg(peerTag .. '#' .. row('Whisper'))
assert(GreenWallGuildRosterDB.peers[peerTag].Whisper, 'whisper tag rejected')
event('CHAT_MSG_ADDON', 'GWGRoster', 'GWGR_LOCAL#' .. peerTag .. '#' .. row('Fanout'), 'GUILD', 'Alice')
assert(GreenWallGuildRosterDB.peers[peerTag].Fanout, 'local fan-out tag rejected')
local protocol = ns.TransactionProtocol
for _, payload in ipairs({ protocol.EncodeBegin('tagtest', 'full', 1),
    protocol.EncodeData('tagtest', 1, row('Transaction')), protocol.EncodeCommit('tagtest') }) do
    apiHandler('GreenWallGuildRoster', 'Bob', peerTag .. '#' .. payload, false, false)
end
assert(GreenWallGuildRosterDB.peers[peerTag].Transaction, 'transaction tag rejected')
print('Tag compatibility (' .. ownTag .. '/' .. peerTag .. '): HELLO, ACK, sender, legacy, whisper, fan-out and transaction passed.')
