local root = (arg[0]:match('(.*[/\\])') or './') .. '../'
local now, sends, frame, hooks = 1, 0, nil, {}
local combat = false
InCombatLockdown = function() return combat end
GetTime = function() return now end
C_AddOns = { GetAddOnInfo = function(name) return name end }
GreenWallGuildRosterDB = { safePassThrough = false }
GreenWallAPI = { GetChannelNumbers = function() return { 1 } end,
    SendMessage = function() sends = sends + 1 end }
NUM_CHAT_WINDOWS = 1
local box = { text = '', focus = true, chatType = 'GUILD' }
function box:GetText() return self.text end
function box:HasFocus() return self.focus end
function box:GetAttribute() return self.chatType end
function box:OnPreSendText() end
function box:HookScript(event, fn) assert(not hooks[event]); hooks[event] = fn end
ChatFrame1EditBox = box
hooksecurefunc = function(object, method, callback)
    local original = object[method]
    object[method] = function(self, ...) original(self, ...); callback(self, ...) end
end
CreateFrame = function()
    frame = { RegisterEvent = function() end, SetScript = function(self, _, callback) self.event = callback end }
    return frame
end
local addon = {}
assert(loadfile(root .. 'Core/HardwareBroker.lua'))('GreenWallGuildRoster', addon)
assert(loadfile(root .. 'Core/HardwareChat.lua'))('GreenWallGuildRoster', addon)
frame.event()
frame.event() -- no duplicate hooks
local api = addon.HardwareAPI
assert(not api.OnChatEnter, 'flush leaked into public API')
assert(not api.IsReady(), 'disabled option ignored')
GreenWallGuildRosterDB.safePassThrough = true
assert(api.IsReady())
GreenWallGuildRosterDB.safePassThrough = nil
assert(api.IsReady(), 'default setting should enable the internal sender')
assert(GuildMapGreenWallHardwareAPI == nil, 'sender exposed a GuildMap dependency')
local function typeText(text, userInput)
    box.text = text; hooks.OnTextChanged(box, userInput)
end
local function enter()
    box:OnPreSendText()
    -- Blizzard clears after sending and before the OnEnterPressed post-hook.
    typeText('', false)
    hooks.OnEnterPressed(box)
end
assert(api.Enqueue('Producer', 'key', 'frame'))
combat = true
assert(not api.IsReady())
typeText('combat text', true); enter()
assert(api.Pending() == 1 and sends == 0, 'combat entered GreenWall deferred queue')
combat = false
GreenWallAPI.SendMessage('OtherAddon', 'death notification')
assert(api.Pending() == 1 and sends == 1)
enter(); assert(api.Pending() == 1, 'empty Enter drained')
typeText('/run anything()', true); enter(); assert(api.Pending() == 1, 'slash drained')
typeText('programmatic', false); enter(); assert(api.Pending() == 1, 'addon text drained')
typeText('test', true); hooks.OnEscapePressed(); enter(); assert(api.Pending() == 1, 'cancelled text drained')
typeText('test', true); box.focus = false; enter(); assert(api.Pending() == 1, 'unfocused box drained')
box.focus = true
for _, chatType in ipairs({ 'GUILD', 'PARTY', 'SAY', 'WHISPER' }) do
    box.chatType = chatType
    typeText('ordinary text', true)
    local before = sends
    enter()
    assert(sends == before + 1 and api.Pending() == 0, chatType)
    assert(api.Enqueue('Producer', 'key', 'frame'))
    now = now + 1
end
-- A prior SendText observation cannot authorize a later empty Enter.
typeText('test', true); box:OnPreSendText(); typeText('', false)
now = now + 1
hooks.OnEnterPressed(box)
assert(api.Pending() == 1)
GreenWallGuildRosterDB.safePassThrough = false
addon.ClearHardwareQueue()
assert(api.Pending() == 0 and not api.IsReady())
print('Hardware chat: supported hooks, typed eligibility, exclusions and toggle passed.')

-- Explicit button and opt-in source isolation, without replacing original scripts.
GreenWallGuildRosterDB.safePassThrough = true
local function clickObject()
    local obj = { hooks = {} }
    function obj:HasScript() return true end
    function obj:HookScript(event, fn) assert(not self.hooks[event]); self.hooks[event] = fn end
    function obj:RegisterForClicks() end
    function obj:SetScript(event, fn) self.hooks[event] = fn end
    return obj
end
ActionButton1, WorldFrame = clickObject(), clickObject()
local sync = clickObject()
addon.BindSyncButton(sync)
local function queue()
    now = now + 1
    assert(api.Enqueue('Producer', 'key', 'frame'))
end
queue()
local before = sends
sync.hooks.OnClick(sync, 'RightButton'); assert(sends == before)
sync.hooks.OnClick(sync, 'LeftButton'); assert(sends == before + 1)
queue()
addon.SetClickTest('action')
assert(sends == before + 1, 'arming sent a frame')
ActionButton1.hooks.PostClick(ActionButton1, 'LeftButton', true)
WorldFrame.hooks.OnMouseUp(WorldFrame, 'LeftButton')
assert(sends == before + 1, 'down or disabled source sent')
ActionButton1.hooks.PostClick(ActionButton1, 'LeftButton', false)
assert(sends == before + 2)
assert(api.Enqueue('Producer', 'key', 'frame'))
addon.SetClickTest('all')
WorldFrame.hooks.OnMouseUp(WorldFrame, 'LeftButton')
assert(sends == before + 2, 'overlapping callback sent twice')
now = now + 1; combat = true
WorldFrame.hooks.OnMouseUp(WorldFrame, 'RightButton')
assert(sends == before + 2 and api.Pending() == 1)
combat = false
WorldFrame.hooks.OnMouseUp(WorldFrame, 'RightButton')
assert(sends == before + 3)
queue()
frame.event(nil, 'ADDON_ACTION_BLOCKED', 'GreenWall')
ActionButton1.hooks.PostClick(ActionButton1, 'LeftButton', false)
assert(sends == before + 3, 'blocked action did not stop experiment')
addon.SetClickTest('world')
local originalSend = GreenWallAPI.SendMessage
GreenWallAPI.SendMessage = function() error('protected test failure') end
WorldFrame.hooks.OnMouseUp(WorldFrame, 'LeftButton')
assert(api.Status().failed == 1)
GreenWallAPI.SendMessage = originalSend
queue()
WorldFrame.hooks.OnMouseUp(WorldFrame, 'LeftButton')
assert(sends == before + 3, 'send failure did not stop experiment')
sync.hooks.OnClick(sync, 'LeftButton')
assert(sends == before + 4, 'explicit button unavailable after experiment stopped')
addon.HardwareEcho('frame')
addon.SetClickTest('status')
print('Click sources: opt-in isolation, down/up filtering, deduplication, combat and error stop passed.')
