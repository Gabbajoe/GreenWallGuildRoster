-- Development spike only. This is not a production chat eligibility detector.
-- No SavedVariables, timers, automatic retries, or production roster frames.
local addonName = ...
local armedAt, pending, handler
local serial, submitted, echoed, failed = 0, 0, 0, 0
local hooked = setmetatable({}, { __mode = "k" })

local function Print(message)
    print("|cff66ccffGW probe:|r " .. message)
end

local function Ready()
    local api = GreenWallAPI
    if not api or type(api.SendMessage) ~= "function"
        or type(api.AddMessageHandler) ~= "function"
        or type(api.GetChannelNumbers) ~= "function" then return false end
    local ok, channels = pcall(api.GetChannelNumbers)
    return ok and type(channels) == "table"
        and type(channels[1]) == "number" and channels[1] > 0
end

local function OnEnter()
    -- Arming via a slash command must not submit on that command's own Enter.
    if not armedAt or GetTime() <= armedAt then return end
    local age = GetTime() - armedAt
    armedAt = nil -- consume BEFORE entering GreenWall, including failure paths
    if age > 60 then
        Print("Arm expired; no frame sent. Use /gwprobe arm again.")
        return
    end
    if not Ready() then
        Print("Channel unavailable; disarmed without sending.")
        return
    end
    serial = serial + 1
    pending = "HWPROBE1:" .. tostring(GetTime()) .. ":" .. tostring(serial)
    submitted = submitted + 1
    -- The only SendMessage call is synchronous in the Enter post-hook.
    local ok, err = pcall(GreenWallAPI.SendMessage, addonName, pending)
    if not ok then
        failed = failed + 1
        pending = nil
        Print("Submission error: " .. tostring(err))
    else
        Print("One frame submitted from Enter post-hook; inspect echo and BugGrabber.")
    end
end

local function InstallHooks()
    local count = 0
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local editbox = _G["ChatFrame" .. i .. "EditBox"]
        if editbox and editbox.HookScript then
            if not hooked[editbox] then
                editbox:HookScript("OnEnterPressed", OnEnter)
                hooked[editbox] = true
            end
            count = count + 1
        end
    end
    return count
end

SLASH_GREENWALLHARDWAREPROBE1 = "/gwprobe"
SlashCmdList.GREENWALLHARDWAREPROBE = function(command)
    command = (command or ""):match("^%s*(.-)%s*$"):lower()
    if command == "off" then
        armedAt, pending = nil, nil
        Print("Disarmed.")
    elseif command == "arm" then
        armedAt, pending = nil, nil
        if not Ready() then
            Print("GreenWall guild channel is not ready; not armed.")
            return
        end
        if not handler then
            handler = GreenWallAPI.AddMessageHandler(function(_, _, message, echo)
                if echo and pending and message == pending then
                    echoed = echoed + 1
                    pending = nil
                    Print("Matching own echo received.")
                end
            end, addonName, 0)
        end
        local count = InstallHooks()
        if count == 0 then
            Print("No supported chat edit box found; not armed.")
            return
        end
        armedAt = GetTime()
        Print("Armed for ONE later chat Enter (60 seconds). Type a normal chat message now.")
    else
        -- Querying status must never itself consume an armed diagnostic send.
        armedAt = nil
        Print(string.format("Disarmed. submitted=%d echoed=%d failed=%d pendingEcho=%s ready=%s",
            submitted, echoed, failed, tostring(pending ~= nil), tostring(Ready())))
        Print("/gwprobe arm | /gwprobe off | /gwprobe status")
    end
end
