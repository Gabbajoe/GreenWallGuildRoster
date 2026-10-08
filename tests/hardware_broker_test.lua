local root = (arg[0]:match('(.*[/\\])') or './') .. '../'
local addon = {}
assert(loadfile(root .. 'Core/HardwareBroker.lua'))('GreenWallGuildRoster', addon)
local now, ready, sent = 0, false, {}
local broker
broker = addon.NewHardwareBroker({ now = function() return now end,
    ready = function() return ready end, installed = function(name) return name == 'A' or name == 'B' end,
    send = function(owner, payload)
        sent[#sent + 1] = owner .. payload
        broker.OnChatEnter() -- recursive entry must not drain
    end })
assert(not broker.Enqueue('unknown', 'k', 'data'))
assert(not broker.Enqueue('A', 'k', string.rep('x', 121)))
assert(not broker.Enqueue('A', 'k', 'x', { ttl = 0/0 }))
assert(broker.Enqueue('A', '1', '1'))
assert(broker.Enqueue('A', '1', '1'))
assert(not broker.Enqueue('A', '1', 'different'))
assert(broker.Pending() == 1)
assert(broker.Enqueue('A', '2', '2'))
assert(broker.Enqueue('B', '1', '1'))
broker.OnChatEnter()
assert(#sent == 0 and broker.Pending() == 3)
ready = true
broker.OnChatEnter()
assert(#sent == 1 and sent[1] == 'A1')
broker.OnChatEnter()
assert(sent[2] == 'B1')
broker.OnChatEnter()
assert(sent[3] == 'A2' and broker.Pending() == 0)
for i = 1, 8 do assert(broker.Enqueue('A', tostring(i), 'x')) end
assert(not broker.Enqueue('A', '9', 'x'))
broker.Cancel('A', '1')
assert(broker.Pending('A') == 7)
broker.Cancel('A')
assert(broker.Pending() == 0)
assert(broker.Enqueue('A', 'expired', 'x', { ttl = 1 }))
now = 2
broker.OnChatEnter()
assert(#sent == 3 and broker.Status().expired == 1)
assert(broker.Enqueue('A', 'invalid', 'x', { validate = function() return false end }))
broker.OnChatEnter()
assert(#sent == 3 and broker.Status().rejected == 1)
assert(broker.Enqueue('B', 'paused', 'x'))
ready = false
broker.OnChatEnter()
assert(broker.Pending() == 1)
ready = true
broker.OnChatEnter()
assert(sent[4] == 'Bx')
local full = addon.NewHardwareBroker({ now = function() return now end,
    ready = function() return true end, installed = function() return true end,
    send = function() error('must not send during queue operations') end })
for owner = 1, 8 do
    for key = 1, 8 do assert(full.Enqueue(tostring(owner), tostring(key), string.rep('x', 120))) end
end
assert(full.Pending() == 64 and full.Status().bytes == 7680)
assert(not full.Enqueue('9', '1', 'x'), 'global limit exceeded')
full.Clear(); assert(full.Pending() == 0 and full.Status().bytes == 0)
local failures = 0
assert(full.Enqueue('A', 'failure', 'x', { onFailure = function() failures = failures + 1 end }))
full.OnChatEnter()
assert(failures == 1 and full.Status().failed == 1 and full.Pending() == 0)
print('Hardware broker: bounds, deduplication, fairness, expiry, readiness and recursion passed.')
