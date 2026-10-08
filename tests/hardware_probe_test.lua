local root = (arg[0]:match('(.*[/\\])') or './')
local time, channel, sends, receiver, enter = 10, 1, 0
local failSend, reenter, deferEcho = false, false, false
local output = {}
local realPrint = print
print = function(message) output[#output + 1] = message end
GetTime = function() return time end
NUM_CHAT_WINDOWS = 1
SlashCmdList = {}
ChatFrame1EditBox = { HookScript = function(_, script, callback)
    assert(script == 'OnEnterPressed')
    assert(not enter, 'hook installed twice')
    enter = callback
end }
GreenWallAPI = {
    GetChannelNumbers = function() return { channel } end,
    AddMessageHandler = function(callback, name, priority)
        assert(type(priority) == 'number' and priority % 1 == 0,
            'GreenWall requires an explicit integer priority')
        assert(name == 'GreenWallHardwareProbe')
        receiver = callback
        return 'handler'
    end,
    SendMessage = function(name, payload)
        sends = sends + 1
        if reenter then enter() end
        if failSend then error('simulated blocked call') end
        receiver(name, 'other', payload, false)
        receiver(name, 'self', 'wrong', true)
        if not deferEcho then receiver(name, 'self', payload, true) end
    end,
}
assert(loadfile(root .. 'GreenWallHardwareProbe/Probe.lua'))('GreenWallHardwareProbe')
local command = SlashCmdList.GREENWALLHARDWAREPROBE
command('arm')
enter()
assert(sends == 0, 'arming Enter sent a frame')
time = 11
reenter = true
enter()
enter()
assert(sends == 1, 'one-shot/reentrancy failed')
command('status')
assert(output[#output - 1]:find('submitted=1 echoed=1 failed=0 pendingEcho=false', 1, true))
command('arm')
time = 72
enter()
assert(sends == 1, 'expired arm sent')
command('arm')
channel = 0
time = 73
enter()
assert(sends == 1, 'lost channel sent')
command('arm')
channel = 1
time = 74
enter()
assert(sends == 1, 'unready arm persisted')
command('arm')
command('off')
time = 75
enter()
assert(sends == 1, 'cancelled arm sent')
command('arm')
command('status')
time = 76
enter()
assert(sends == 1, 'status did not disarm')
command('arm')
failSend = true
time = 77
enter()
enter()
assert(sends == 2, 'failure retried')
command('status')
assert(output[#output - 1]:find('submitted=2 echoed=1 failed=1 pendingEcho=false', 1, true))
failSend, deferEcho = false, true
command('arm')
time = 78
enter()
command('status')
assert(output[#output - 1]:find('submitted=3 echoed=1 failed=1 pendingEcho=true', 1, true),
    'submission or unrelated echo counted as confirmation')
print = realPrint
print('Hardware probe lifecycle checks passed (hardware permission requires live test).')
