local root = (arg[0]:match('(.*[/\\])') or './') .. '../'
local ns, addon = {}, {}
assert(loadfile(root .. 'Core/TransactionProtocol.lua'))('GreenWallGuildRoster', ns)
assert(loadfile(root .. 'Core/PassThrough.lua'))('GreenWallGuildRoster', ns)
assert(loadfile(root .. 'Core/HardwareBroker.lua'))('GreenWallGuildRoster', addon)
local function fixture()
    local f = { now = 10, enabled = true, ready = true, capable = true, revision = 0,
        committed = 0, aborted = 0, completed = 0, sent = {}, stats = {}, rows = {
            'Alice;MAGE;60;Stormwind;;1;;0', 'Bob;WARRIOR;60;Stormwind;;1;;0',
            'Charlie;ROGUE;60;Stormwind;;1;;0', 'David;MAGE;60;Stormwind;;1;;0' } }
    f.broker = addon.NewHardwareBroker({ now = function() return f.now end,
        ready = function() return f.ready end, installed = function() return true end,
        send = function(_, payload)
            assert(#payload <= 120)
            f.sent[#f.sent + 1] = payload
            if f.autoEcho then f.sender.Echo(payload) end
        end })
    f.broker.VERSION = 1
    f.sender = ns.PassThrough.New({ owner = 'GreenWallGuildRoster', now = function() return f.now end,
        session = function() return 1790670000 end, stats = f.stats,
        tag = function() return f.tag or 'A' end, broker = function() return f.broker end,
        enabled = function() return f.enabled end, capable = function() return f.capable end,
        valid = function(s) return s.revision == f.revision end,
        prepare = function() return { rows = f.rows, kind = 'full', revision = f.revision } end,
        commit = function(s)
            assert(s.revision == f.revision); f.committed = f.committed + 1; return true
        end,
        abort = function() f.aborted = f.aborted + 1 end,
        completed = function() f.completed = f.completed + 1 end,
    })
    return f
end
local f = fixture()
f.sender.Service()
assert(#f.sent == 0 and f.committed == 0 and f.broker.Pending() == 1)
f.sender.Service()
assert(f.broker.Pending() == 1)
f.broker.OnChatEnter()
assert(#f.sent == 1 and f.committed == 0)
f.broker.OnChatEnter()
assert(#f.sent == 1, 'advanced before echo')
assert(not f.sender.Echo('wrong'))
assert(f.sender.Echo(f.sent[1]))
assert(not f.sender.Echo(f.sent[1]), 'duplicate echo advanced')
local receiver = ns.TransactionProtocol.NewStager()
assert(receiver:Handle('A', 'Alice', f.sent[1]:match('^A#(.*)$'), f.now) == 'staged')
local result
while f.completed == 0 do
    f.now = f.now + 1
    f.broker.OnChatEnter()
    local payload = f.sent[#f.sent]
    local status, received = receiver:Handle('A', 'Alice', payload:match('^A#(.*)$'), f.now)
    if status == 'committed' then result = received end
    f.sender.Echo(payload)
end
assert(f.committed == 1 and f.completed == 1 and result.payload == table.concat(f.rows, '~'))
f.sender.Service()
assert(f.broker.Pending() == 0, 'immediate duplicate full snapshot')
-- Timeout requeues but never sends; a late echo removes the queued retry.
f = fixture(); f.sender.Service(); f.broker.OnChatEnter()
f.now = f.now + 16; f.sender.Service()
assert(#f.sent == 1 and f.broker.Pending() == 1 and f.stats.passThroughRetried == 1)
f.sender.Echo(f.sent[1]); f.broker.OnChatEnter()
assert(f.sent[2] ~= f.sent[1], 'late echo left retry queued')
-- Bounded retries.
f = fixture(); f.sender.Service()
for i = 1, 3 do f.broker.OnChatEnter(); f.now = f.now + 16; f.sender.Service() end
assert(#f.sent == 3 and f.aborted == 1 and f.committed == 0 and f.broker.Pending() == 0)
-- Channel pauses and recovers; expiry does not commit.
f = fixture(); f.sender.Service(); f.ready = false; f.broker.OnChatEnter(); f.sender.Service()
assert(#f.sent == 0 and f.broker.Pending() == 1)
f.ready = true; f.broker.OnChatEnter(); assert(#f.sent == 1)
f.now = 131; f.sender.Service(); assert(f.aborted == 1 and f.committed == 0)
-- A parallel whisper commit or option disable invalidates queued work.
for _, field in ipairs({ 'revision', 'enabled', 'capable' }) do
    f = fixture(); f.sender.Service()
    f[field] = field == 'revision' and 1 or false
    f.broker.OnChatEnter()
    assert(#f.sent == 0 and f.aborted == 1 and f.broker.Pending() == 0, field)
end
-- Capability gate, absent broker and oversized rows never send/commit.
f = fixture(); f.capable = false; f.sender.Service(); assert(f.broker.Pending() == 0)
f = fixture(); f.rows = { string.rep('x', 121) }; f.sender.Service()
assert(f.aborted == 1 and f.committed == 0 and f.broker.Pending() == 0)
f = fixture(); f.broker = nil; f.sender.Service(); assert(f.sender.Status() == 'broker-absent')
f = fixture(); f.rows = {}
for i = 1, 33 do f.rows[i] = string.rep('x', 80) end
f.sender.Service(); assert(f.aborted == 1 and f.broker.Pending() == 0, 'chunk cap exceeded')
f = fixture(); f.tag = string.rep('A', 16); f.sender.Service()
while f.completed == 0 do
    f.broker.OnChatEnter(); assert(#f.sent[#f.sent] <= 120); f.sender.Echo(f.sent[#f.sent])
end
-- Synchronous echo during SendMessage must work, with at most one frame per Enter.
f = fixture(); f.autoEcho = true; f.sender.Service(); f.broker.OnChatEnter()
assert(#f.sent == 1 and f.broker.Pending() == 1 and f.committed == 0)
f.sender.Abort('manual-broadcast', 600); assert(f.broker.Pending() == 0)
print('Pass-through: round trip, echo, retries, expiry, invalidation, bounds and fallback passed.')
