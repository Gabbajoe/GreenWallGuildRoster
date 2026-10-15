-- Never hook global SendChatMessage. Chat and the explicit sync button use
-- synchronous callbacks; opt-in click paths are experimental and session-only.
local _, addon = ...
local hooked = setmetatable({}, { __mode = 'k' })
local hookCount = 0
local clickMode = 'off' -- session-only: experimental hooks never re-arm on login
local lastAttempt = -math.huge
local source = 'chat'
local diagnostics, pendingEcho = {}, {}
local function diagnostic(name)
    diagnostics[name] = diagnostics[name] or { observed = 0, submitted = 0, echoed = 0, failed = 0 }
    return diagnostics[name]
end
local allowed = { GUILD = true, OFFICER = true, PARTY = true, RAID = true,
    RAID_WARNING = true, SAY = true, YELL = true, WHISPER = true, INSTANCE_CHAT = true }
local broker = addon.NewHardwareBroker({
    now = GetTime,
    installed = function(name)
        return C_AddOns and C_AddOns.GetAddOnInfo(name) == name
    end,
    ready = function()
        if not GreenWallGuildRosterDB or GreenWallGuildRosterDB.safePassThrough == false then return false end
        -- GreenWall defers its own queue in combat and flushes it from an event
        -- afterwards. Never hand it a pass-through frame on that deferred path.
        if InCombatLockdown and InCombatLockdown() then return false end
        if not GreenWallAPI or type(GreenWallAPI.SendMessage) ~= 'function'
            or type(GreenWallAPI.GetChannelNumbers) ~= 'function' then return false end
        local ok, channels = pcall(GreenWallAPI.GetChannelNumbers)
        return ok and type(channels) == 'table' and type(channels[1]) == 'number' and channels[1] > 0
    end,
    send = function(owner, payload)
        local d = diagnostic(source)
        d.submitted = d.submitted + 1
        pendingEcho[payload] = source
        local ok, err = pcall(GreenWallAPI.SendMessage, owner, payload)
        if not ok then
            d.failed = d.failed + 1
            clickMode = 'off'
            error(err)
        end
    end,
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
function addon.HardwareEcho(payload)
    local name = pendingEcho[payload]
    if name then diagnostic(name).echoed = diagnostic(name).echoed + 1; pendingEcho[payload] = nil end
end
local function Submit(name)
    diagnostic(name).observed = diagnostic(name).observed + 1
    -- Deduplicate overlapping hooks and rapid down/up paths, including sync echoes.
    if GetTime() - lastAttempt < 0.2 then return end
    if not broker.IsReady() then return end
    if addon.PrepareHardwareSync then addon.PrepareHardwareSync() end
    if broker.Pending() == 0 then return end
    lastAttempt, source = GetTime(), name
    pendingEcho = {} -- only the current frame can be outstanding
    broker.OnChatEnter()
end
function addon.BindSyncButton(button)
    button:RegisterForClicks('LeftButtonUp')
    button:SetScript('OnClick', function(self, mouseButton)
        if self.syncCanSend == false then return end
        if mouseButton == 'LeftButton' then Submit('button') end
    end)
end
local extraHooked = setmetatable({}, { __mode = 'k' })
local actionHooks, worldHooks = 0, 0
local function InstallClickHooks()
    if InCombatLockdown and InCombatLockdown() then return end
    local function hook(object, event, name)
        if not object or extraHooked[object] or not object.HasScript or not object:HasScript(event) then return end
        object:HookScript(event, function(_, button, down)
            if clickMode ~= name and clickMode ~= 'all' then return end
            if name == 'action' and down then return end
            if button ~= 'LeftButton' and button ~= 'RightButton' and button ~= 'MiddleButton'
                and button ~= 'Button4' and button ~= 'Button5' then return end
            Submit(name)
        end)
        extraHooked[object] = true
        if name == 'action' then actionHooks = actionHooks + 1 else worldHooks = worldHooks + 1 end
    end
    for _, prefix in ipairs({ 'ActionButton', 'MultiBarBottomLeftButton', 'MultiBarBottomRightButton',
        'MultiBarRightButton', 'MultiBarLeftButton', 'PetActionButton' }) do
        for i = 1, 12 do hook(_G[prefix .. i], 'PostClick', 'action') end
    end
    hook(WorldFrame, 'OnMouseUp', 'world')
end
function addon.SetClickTest(mode)
    if mode == 'off' or mode == 'action' or mode == 'world' or mode == 'all' then
        clickMode = mode
        if mode ~= 'off' then InstallClickHooks() end
    elseif mode ~= 'status' then
        print('GWGR: /gwgr clicktest off|action|world|all|status')
        return
    end
    print(('GWGR clicktest=%s action-hooks=%d world-hooks=%d'):format(clickMode, actionHooks, worldHooks))
    for _, name in ipairs({ 'chat', 'button', 'action', 'world' }) do
        local d = diagnostic(name)
        print(('GWGR %s observed=%d submitted=%d echoed=%d failed=%d'):format(name, d.observed, d.submitted, d.echoed, d.failed))
    end
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
                if eligible then Submit('chat') end
            end)
            hooked[box], hookCount = true, hookCount + 1
        end
    end
end
local frame = CreateFrame('Frame')
frame:RegisterEvent('PLAYER_LOGIN')
frame:RegisterEvent('UPDATE_CHAT_WINDOWS')
frame:RegisterEvent('PLAYER_REGEN_ENABLED')
frame:RegisterEvent('ADDON_ACTION_BLOCKED')
frame:RegisterEvent('ADDON_ACTION_FORBIDDEN')
frame:SetScript('OnEvent', function(_, event, culprit)
    if event == 'ADDON_ACTION_BLOCKED' or event == 'ADDON_ACTION_FORBIDDEN' then
        if culprit == 'GreenWallGuildRoster' or culprit == 'GreenWall' then
            clickMode = 'off'
            print('GWGR: click tests stopped after protected-action error; inspect BugGrabber.')
        end
        return
    end
    Install()
    if clickMode ~= 'off' then InstallClickHooks() end
end)
