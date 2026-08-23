local ADDON_NAME, ns = ...

local VERSION_PREFIX = 'GWGR_VERSION#'
local versionSentAt = {}
local forwardedVersions = {}
local state

local function AddonVersion()
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(ADDON_NAME, 'Version') or '0.0.0'
    end
    return GetAddOnMetadata(ADDON_NAME, 'Version') or '0.0.0'
end

local function SendVersion(channel, target, version)
    ChatThrottleLib:SendAddonMessage('NORMAL', 'GWGRoster', VERSION_PREFIX .. (version or AddonVersion()),
        channel, target, 'GWGRoster:version:' .. (target or channel))
end

function ns.SendVersionTo(target)
    if not target or target == '' then return end
    local key, now = ns.ClientKey(target), GetTime()
    if versionSentAt[key] and now - versionSentAt[key] < 600 then return end
    versionSentAt[key] = now
    SendVersion('WHISPER', target)
end

function ns.HandleVersionMessage(message, channel, sender)
    local version = message:match('^' .. VERSION_PREFIX .. '([%w%.%-]+)$')
    if not version then return false end

    state.knownVersions[ns.ClientKey(sender)] = { version = version, seenAt = time() }
    local current = AddonVersion()
    if ns.CompareVersions(version, current) > 0 and state.lastNotifiedVersion ~= version then
        state.lastNotifiedVersion = version
        print(('|cff33ff99GreenWallGuildRoster|r: ' .. ns.L['A newer version is available: %s (installed: %s). Please update through CurseForge, Wago, or GitHub.']):format(version, current))
    end

    -- A version learned through a cross-guild whisper is announced once to
    -- the local guild. GUILD announcements are never repeated, preventing
    -- loops while still letting one bridge inform all local users.
    if channel == 'WHISPER' and not forwardedVersions[version] then
        forwardedVersions[version] = true
        SendVersion('GUILD', nil, version)
    end
    return true
end

local frame = CreateFrame('Frame')
frame:RegisterEvent('ADDON_LOADED')
frame:RegisterEvent('PLAYER_LOGIN')
frame:SetScript('OnEvent', function(_, event, addon)
    if event == 'ADDON_LOADED' then
        if addon ~= ADDON_NAME then return end

        -- Preserve the useful update state from the development monitor,
        -- then discard its samples/settings so release SavedVariables stay
        -- small and contain no retired background instrumentation.
        local oldDiagnostics = type(GreenWallGuildRosterDB.diagnostics) == 'table'
            and GreenWallGuildRosterDB.diagnostics or nil
        GreenWallGuildRosterDB.versioning = type(GreenWallGuildRosterDB.versioning) == 'table'
            and GreenWallGuildRosterDB.versioning or {}
        state = GreenWallGuildRosterDB.versioning
        state.knownVersions = type(state.knownVersions) == 'table' and state.knownVersions
            or (oldDiagnostics and oldDiagnostics.knownVersions) or {}
        if state.lastNotifiedVersion == nil and oldDiagnostics then
            state.lastNotifiedVersion = oldDiagnostics.lastNotifiedVersion
        end
        GreenWallGuildRosterDB.diagnostics = nil
    elseif event == 'PLAYER_LOGIN' then
        C_Timer.After(math.random(8, 18), function() SendVersion('GUILD') end)
    end
end)
