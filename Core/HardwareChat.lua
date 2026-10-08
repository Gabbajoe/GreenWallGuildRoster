-- Never hook global SendChatMessage. Observe supported edit boxes only;
-- actual submission stays in the OnEnterPressed post-hook proven by the spike.
local _, addon = ...
local hooked = setmetatable({}, { __mode = 'k' })
local hookCount = 0
local allowed = { GUILD = true, OFFICER = true, PARTY = true, RAID = true,
    RAID_WARNING = true, SAY = true, YELL = true, WHISPER = true, INSTANCE_CHAT = true }
local broker = addon.NewHardwareBroker({
    now = GetTime,
    installed = function(name)
        return C_AddOns and C_AddOns.GetAddOnInfo(name) == name
    end,
    ready = function()
        if not GreenWallGuildRosterDB or GreenWallGuildRosterDB.safePassThrough == false or hookCount == 0 then return false end
        -- GreenWall defers its own queue in combat and flushes it from an event
        -- afterwards. Never hand it a pass-through frame on that deferred path.
        if InCombatLockdown and InCombatLockdown() then return false end
        if not GreenWallAPI or type(GreenWallAPI.SendMessage) ~= 'function'
            or type(GreenWallAPI.GetChannelNumbers) ~= 'function' then return false end
        local ok, channels = pcall(GreenWallAPI.GetChannelNumbers)
        return ok and type(channels) == 'table' and type(channels[1]) == 'number' and channels[1] > 0
    end,
    send = function(owner, payload) GreenWallAPI.SendMessage(owner, payload) end,
})
-- Do not expose the flush operation to producers, timers or other addons.
addon.HardwareAPI = { VERSION = 1, IsReady = broker.IsReady,
    Enqueue = broker.Enqueue, Cancel = broker.Cancel, Pending = broker.Pending,
    Status = broker.Status }
function addon.ClearHardwareQueue()
    broker.Clear()
end
function addon.HardwareStatus()
    local s = broker.Status()
    return string.format('Hardware enabled=%s ready=%s hooks=%d queue=%d/%dB submitted=%d failed=%d expired=%d rejected=%d high=%d',
        tostring(GreenWallGuildRosterDB and GreenWallGuildRosterDB.safePassThrough ~= false),
        tostring(s.ready), hookCount, s.depth, s.bytes, s.submitted, s.failed, s.expired, s.rejected, s.highWater)
end
local function Install()
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local box = _G['ChatFrame' .. i .. 'EditBox']
        if box and not hooked[box] and type(box.OnPreSendText) == 'function' then
            local typed, eligibleAt
            -- Programmatic SetText, cancelled text and reuse of an old edit box
            -- cannot authorize a frame. No text or chat attributes are modified.
            box:HookScript('OnTextChanged', function(self, userInput)
                typed = userInput and self:GetText() or nil
                if typed then eligibleAt = nil end
            end)
            box:HookScript('OnEscapePressed', function() typed, eligibleAt = nil, nil end)
            hooksecurefunc(box, 'OnPreSendText', function(self)
                eligibleAt = nil
                local text = self:GetText()
                if typed and typed == text and text:match('%S') and not text:match('^%s*/')
                    and self:HasFocus() and allowed[self:GetAttribute('chatType')] then
                    eligibleAt = GetTime()
                end
                typed = nil
            end)
            box:HookScript('OnEnterPressed', function()
                local eligible = eligibleAt and eligibleAt == GetTime()
                typed, eligibleAt = nil, nil
                if eligible then broker.OnChatEnter() end
            end)
            hooked[box], hookCount = true, hookCount + 1
        end
    end
end
local frame = CreateFrame('Frame')
frame:RegisterEvent('PLAYER_LOGIN')
frame:RegisterEvent('UPDATE_CHAT_WINDOWS')
frame:SetScript('OnEvent', Install)
