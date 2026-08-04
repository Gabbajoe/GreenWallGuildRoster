local ADDON_NAME, ns = ...

local CLASS_COLORS = RAID_CLASS_COLORS
local CLASS_ICON_TEXTURE = 'Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes'

local frame = CreateFrame('Frame', 'GreenWallGuildRosterFrame', UIParent, 'BasicFrameTemplateWithInset')
frame:SetSize(710, 520)
frame:SetPoint('CENTER')
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag('LeftButton')
frame:SetScript('OnDragStart', frame.StartMoving)
frame:SetScript('OnDragStop', frame.StopMovingOrSizing)
frame:SetClampedToScreen(true)
-- 'MEDIUM' is the strata Blizzard's own windows use by default (bags,
-- spellbook, character, guild frame, quest log never call
-- SetFrameStrata, so they stay on CreateFrame's default of 'MEDIUM') -
-- BasicFrameTemplateWithInset apparently doesn't inherit that default, so
-- leaving it unset meant this window could never come forward over them.
-- 'HIGH' (tried earlier) overcorrected: that's structurally above
-- 'MEDIUM' regardless of click order, so it stayed permanently on top
-- instead. SetToplevel(true) gives normal click-to-raise within the
-- shared 'MEDIUM' strata, same pattern as SaveWhispers' main window.
frame:SetFrameStrata('MEDIUM')
frame:SetToplevel(true)
frame:Hide()
frame.TitleText:SetText(ns.L['GreenWall GuildRoster'])
-- Opts this window into the default UI's Escape-key handling, same as
-- every other Blizzard/addon window - without this, Escape closes
-- nothing here and the player has to click the X manually.
tinsert(UISpecialFrames, 'GreenWallGuildRosterFrame')

GreenWallGuildRosterDB = GreenWallGuildRosterDB or {}
if GreenWallGuildRosterDB.showOffline == nil then
    GreenWallGuildRosterDB.showOffline = false
end
if GreenWallGuildRosterDB.showSourceColumn == nil then
    GreenWallGuildRosterDB.showSourceColumn = false
end

-- Column layout shared by the header and the body. Each column is one
-- FontString spanning every row (see below) rather than a grid of
-- per-row frames, so this reuses the exact CreateFontString-in-a-Frame
-- pattern already proven to render reliably in this client. Class icons
-- are embedded as inline |T texture markup inside the text itself, for
-- the same reason - no separate per-row Texture regions needed.
--
-- The trailing "#" (source-marker) column's structure is built
-- unconditionally, regardless of the saved showSourceColumn toggle -
-- deliberately NOT branched on that setting here, because this code runs
-- at file load time, before the real per-character SavedVariables value
-- has actually been injected (that only happens right before ADDON_LOADED
-- fires - see the identical note in Core.lua's ADDON_LOADED handler,
-- learned the hard way once already with mainLinks). Branching on the
-- setting here always saw a stale/default value and silently built the
-- wrong layout every time. Instead, the column always exists structurally
-- (Alt is always the narrower 100px to make room for it), and
-- UpdateHeaderText/Refresh below - which only ever run in response to a
-- real event, always safely after data has loaded - decide whether to
-- actually show its header/content or leave it blank.
local CONTENT_WIDTH = 660
local headers = { 'Lvl', ns.L['Class'], ns.L['Name'], ns.L['Zone'], ns.L['Guild'], ns.L['Status'], ns.L['Alt'], '#' }
local colX =    { 0,     36,            80,           220,         390,           470,            520,        620 }

local offlineCheck = CreateFrame('CheckButton', nil, frame, 'UICheckButtonTemplate')
offlineCheck:SetSize(22, 22)
offlineCheck:SetPoint('TOPLEFT', 14, -30)
offlineCheck:SetChecked(GreenWallGuildRosterDB.showOffline)
local offlineLabel = offlineCheck:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
offlineLabel:SetPoint('LEFT', offlineCheck, 'RIGHT', 2, 1)
offlineLabel:SetText(ns.L['Show Offline'])
offlineCheck:SetScript('OnClick', function(self)
    GreenWallGuildRosterDB.showOffline = self:GetChecked() and true or false
    if ns.RefreshFrame then ns.RefreshFrame() end
end)

-- Per-guild online counts, same row as the checkbox. Filled in by
-- BuildEntries (it already walks every entry with guild/online/stale on
-- it before the showOffline filter discards anything), read back out by
-- Refresh.
local onlineCountFS = frame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
onlineCountFS:SetPoint('TOPRIGHT', -16, -33)
onlineCountFS:SetJustifyH('RIGHT')

-- Column index -> sortable field. 'online' is stored as 0/1 so it sorts
-- like a number; everything else falls back to '' or 0 when missing so
-- mixed nil/non-nil values never break the comparator.
local sortFields = {
    { key = 'level', numeric = true, defaultAsc = false },
    { key = 'classFile', numeric = false, defaultAsc = true },
    { key = 'name', numeric = false, defaultAsc = true },
    { key = 'zone', numeric = false, defaultAsc = true },
    { key = 'guild', numeric = false, defaultAsc = true },
    { key = 'online', numeric = true, defaultAsc = false },
    { key = 'linkedMain', numeric = false, defaultAsc = true },
    { key = 'marker', numeric = false, defaultAsc = true },
}
local sortColumn = 1
local sortAsc = false

local function ValueOf(entry, idx)
    local f = sortFields[idx]
    if f.key == 'online' then return entry.online and 1 or 0 end
    local v = entry[f.key]
    if f.numeric then return v or 0 end
    return v or ''
end

local headerRow = CreateFrame('Frame', nil, frame)
headerRow:SetPoint('TOPLEFT', 16, -52)
headerRow:SetSize(CONTENT_WIDTH, 16)

-- Divider under the header, same look as the native guild frame's line
-- between column captions and the member list.
local headerDivider = frame:CreateTexture(nil, 'ARTWORK')
headerDivider:SetTexture('Interface\\Common\\UI-TooltipDivider-Transparent')
headerDivider:SetHeight(8)
headerDivider:SetPoint('TOPLEFT', headerRow, 'BOTTOMLEFT', -2, 2)
headerDivider:SetPoint('TOPRIGHT', headerRow, 'BOTTOMRIGHT', 2, 2)

local headerFS = {}
for i, h in ipairs(headers) do
    local fs = headerRow:CreateFontString(nil, 'OVERLAY', 'GameFontNormal')
    fs:SetPoint('LEFT', colX[i], 0)
    fs:SetText(h)
    headerFS[i] = fs

    local btn = CreateFrame('Button', nil, headerRow)
    btn:SetPoint('TOPLEFT', colX[i], 0)
    btn:SetSize((colX[i + 1] or CONTENT_WIDTH) - colX[i], 16)
    btn:SetScript('OnClick', function()
        if sortColumn == i then
            sortAsc = not sortAsc
        else
            sortColumn = i
            sortAsc = sortFields[i].defaultAsc
        end
        if ns.RefreshFrame then ns.RefreshFrame() end
    end)
end

local function UpdateHeaderText()
    for i, h in ipairs(headers) do
        -- Column 8 ("#") only actually shows a header once the real
        -- SavedVariables value is known safe to read (see the comment
        -- where headers/colX are built) - blank otherwise, same as its
        -- body text in Refresh below.
        if i == 8 and not GreenWallGuildRosterDB.showSourceColumn then
            headerFS[i]:SetText('')
        else
            headerFS[i]:SetText(h .. (i == sortColumn and (sortAsc and ' ^' or ' v') or ''))
        end
    end
end

local scrollFrame = CreateFrame('ScrollFrame', 'GreenWallGuildRosterScroll', frame, 'UIPanelScrollFrameTemplate')
scrollFrame:SetPoint('TOPLEFT', 16, -72)
scrollFrame:SetPoint('BOTTOMRIGHT', -34, 40)

local content = CreateFrame('Frame', 'GreenWallGuildRosterScrollContent', scrollFrame)
content:SetSize(CONTENT_WIDTH, 10)
scrollFrame:SetScrollChild(content)

-- Extra pixels between lines, applied identically to every column so they
-- all grow in lockstep - this is also what makes room for a class icon
-- bigger than the bare text line height without repeating the earlier
-- column-drift bug.
local LINE_SPACING = 6

local columnFS = {}
for i in ipairs(headers) do
    local fs = content:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    fs:SetPoint('TOPLEFT', colX[i], 0)
    fs:SetJustifyH('LEFT')
    fs:SetJustifyV('TOP')
    local width = (colX[i + 1] or CONTENT_WIDTH) - colX[i] - 6
    fs:SetWidth(width)
    fs:SetSpacing(LINE_SPACING)
    fs:SetText('')
    columnFS[i] = fs
end

-- Word wrap has to stay on so the \n-joined multi-line column text keeps
-- working (SetWordWrap(false) turns out to truncate the whole block after
-- the first line instead of per-line). To stop long fields from wrapping
-- to a second line and throwing off row alignment between columns, clip
-- the raw value ourselves before it ever reaches the FontString.
-- Byte-length based (names/zones here can contain multi-byte UTF-8 like
-- umlauts), so back off from the cut point until it doesn't land in the
-- middle of a multi-byte sequence.
local function Clip(s, maxChars)
    s = s or ''
    if #s <= maxChars then return s end
    local cut = maxChars - 2
    while cut > 1 and s:byte(cut) >= 0x80 and s:byte(cut) < 0xC0 do
        cut = cut - 1
    end
    return s:sub(1, cut) .. '..'
end

-- One invisible click-catcher Button per row, parented to the scroll
-- content so it scrolls along with the text, sized over just the Name
-- column. A pool reused/resized across refreshes rather than recreated,
-- since a big guild can mean hundreds of rows.
local ROW_HEIGHT = (columnFS[3]:GetLineHeight() or 10) + LINE_SPACING
local rowButtons = {}

local rowMenuFrame = CreateFrame('Frame', 'GreenWallGuildRosterRowMenu', UIParent, 'UIDropDownMenuTemplate')

local function InvitePlayer(name)
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(name)
    elseif InviteUnit then
        InviteUnit(name)
    end
end

local function WhisperPlayer(name)
    ChatFrame_SendTell(name)
end

-- A plain popup with a pre-filled, highlighted editbox is the standard
-- way addons offer "copy this text" without clipboard API access (WoW
-- addons can't touch the system clipboard directly) - the player just
-- hits Ctrl+C themselves once it's focused/highlighted.
StaticPopupDialogs['GREENWALLGUILDROSTER_COPY_NAME'] = {
    text = ns.L['Copy character name (Ctrl+C)'],
    button1 = CLOSE,
    hasEditBox = true,
    editBoxWidth = 220,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnShow = function(self)
        local editBox = self.editBox or (self.GetEditBox and self:GetEditBox())
        if editBox then
            editBox:SetText(self.data or '')
            editBox:SetFocus()
            editBox:HighlightText()
        end
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
}

-- StaticPopup_Show's 4th argument is "data" - it gets stashed on the
-- dialog BEFORE OnShow fires. Setting popup.data on the frame returned
-- by StaticPopup_Show happens AFTER OnShow already ran (that fires
-- synchronously inside the call), so the editbox picked up "" every time.
local function CopyPlayerName(name)
    StaticPopup_Show('GREENWALLGUILDROSTER_COPY_NAME', nil, nil, name)
end

-- Diagnostic for the rank-badge heuristic (RankBadge in Core.lua), which
-- has already been wrong once (rankIndex 0/1 only, but Saftladen's native
-- frame shows the hollow "officer" crown on rankIndex 2 as well) - rather
-- than guess a new rule blind a third time, this prints the raw inputs
-- for one member at a time so they can be compared against a native-frame
-- screenshot. Only meaningful for own-guild rows: GetGuildRosterInfo/
-- GuildControlGetRankFlags ground truth is only available locally for
-- your own guild, not for a peer whose badge just arrived over the wire.
local function ShowRankInfo(name)
    local total = GetNumGuildMembers() or 0
    for i = 1, total do
        local rosterName, _, rankIndex = GetGuildRosterInfo(i)
        if rosterName then
            local shortName = rosterName:match('^[^-]+') or rosterName
            if shortName == name then
                local badge = ns.RankBadge and ns.RankBadge(rankIndex, C_GuildInfo.GuildControlGetRankFlags)
                local ok, flags = pcall(C_GuildInfo.GuildControlGetRankFlags, rankIndex)
                local flagStr = 'n/a'
                if ok and flags then
                    local parts = {}
                    for idx, v in ipairs(flags) do parts[idx] = idx .. '=' .. tostring(v) end
                    flagStr = table.concat(parts, ', ')
                end
                print(('|cff33ff99GreenWallGuildRoster|r: %s: rankIndex=%s badge=%s flags=[%s]'):format(
                    name, tostring(rankIndex), tostring(badge), flagStr))
                return
            end
        end
    end
    print(('|cff33ff99GreenWallGuildRoster|r: %s is not in your own guild - only the synced badge value is known here (rankIndex/flags aren\'t available for peers).'):format(name))
end

-- EasyMenu isn't available in this client build (ADDON_ACTION_BLOCKED-style
-- surprise, but a plain nil-function error this time), so this goes
-- straight to the lower-level dropdown API EasyMenu itself wraps -
-- UIDropDownMenu_Initialize/AddButton and ToggleDropDownMenu are core
-- FrameXML functions the default UI depends on everywhere (chat menus,
-- unit frames, ...), so they're a much safer bet to still exist.
UIDropDownMenu_Initialize(rowMenuFrame, function(self, level)
    local name = rowMenuFrame.targetName
    if not name then return end

    local info = UIDropDownMenu_CreateInfo()
    info.text = name
    info.isTitle = true
    info.notCheckable = true
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = ns.L['Whisper']
    info.notCheckable = true
    info.func = function() WhisperPlayer(name) end
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = ns.L['Invite']
    info.notCheckable = true
    info.func = function() InvitePlayer(name) end
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = ns.L['Copy Name']
    info.notCheckable = true
    info.func = function() CopyPlayerName(name) end
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = 'Show Rank Info'
    info.notCheckable = true
    info.func = function() ShowRankInfo(name) end
    UIDropDownMenu_AddButton(info, level)
end, 'MENU')

local function ShowRowMenu(rowBtn)
    local name = rowBtn.targetName
    if not name then return end
    rowMenuFrame.targetName = name
    ToggleDropDownMenu(1, nil, rowMenuFrame, 'cursor', 0, 0)
end

-- Alternating row stripe, same idea as the native guild frame's zebra
-- background - a plain white texture at very low alpha behind every other
-- row, drawn in the 'BACKGROUND' layer so it sits behind the text/icons/
-- click-catcher regardless of creation order.
local rowBGs = {}
local function GetRowBG(i)
    local tex = rowBGs[i]
    if not tex then
        tex = content:CreateTexture(nil, 'BACKGROUND')
        tex:SetColorTexture(1, 1, 1, 1)
        rowBGs[i] = tex
    end
    tex:SetWidth(CONTENT_WIDTH)
    tex:SetHeight(ROW_HEIGHT)
    -- Shifted up by half the trailing line-spacing gap so the stripe is
    -- centered on the text line instead of flush with its top - the text
    -- itself sits at the top of each ROW_HEIGHT pitch with the gap
    -- trailing below it, so a stripe matching that pitch exactly looks
    -- like the text (and icons, which are centered on the text - see
    -- GetClassIcon) are riding high in their own row.
    tex:SetPoint('TOPLEFT', 0, -(i - 1) * ROW_HEIGHT + LINE_SPACING / 2)
    tex:SetAlpha(i % 2 == 0 and 0.05 or 0)
    return tex
end

local function GetRowButton(i)
    local btn = rowButtons[i]
    if not btn then
        btn = CreateFrame('Button', nil, content)
        btn:SetHeight(ROW_HEIGHT)
        btn:SetPoint('TOPLEFT', 0, -(i - 1) * ROW_HEIGHT + LINE_SPACING / 2)
        btn:SetPoint('TOPRIGHT', content, 'TOPLEFT', CONTENT_WIDTH, -(i - 1) * ROW_HEIGHT + LINE_SPACING / 2)
        btn:RegisterForClicks('RightButtonUp')
        btn:SetScript('OnClick', ShowRowMenu)
        -- Same texture the native guild/quest list rows use for their
        -- mouseover highlight, now spanning the full row width instead of
        -- just the Name column.
        btn:SetHighlightTexture('Interface\\QuestFrame\\UI-QuestTitleHighlight', 'ADD')
        rowButtons[i] = btn
    end
    return btn
end

local broadcastBtn = CreateFrame('Button', nil, frame, 'UIPanelButtonTemplate')
broadcastBtn:SetSize(90, 22)
broadcastBtn:SetPoint('BOTTOMLEFT', 14, 10)
broadcastBtn:SetText('Broadcast')
broadcastBtn:SetScript('OnClick', function()
    if ns.Broadcast then ns.Broadcast() end
end)

local lastBroadcastFS = frame:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
lastBroadcastFS:SetPoint('LEFT', broadcastBtn, 'RIGHT', 10, 0)

-- Only meaningful (and only shown) when the source-marker column itself is
-- on - explaining symbols nobody can currently see would just be clutter.
-- Always created (same reasoning as the "#" column itself - reading the
-- saved toggle this early would only ever see a not-yet-loaded value);
-- shown/hidden later from UpdateLastBroadcastLabel, which only ever runs
-- from Refresh, always safely after data has loaded.
local legendFS = frame:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
legendFS:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -16, 17)
legendFS:SetText(ns.L['^ broadcast   ~ whisper   * /who only (no addon)'])

-- No auto-broadcast (see Core.lua), so this is a passive nudge: color goes
-- from green to red the staler your last broadcast gets, as a reminder to
-- click the button yourself rather than anything sending on its own.
local function UpdateLastBroadcastLabel()
    if GreenWallGuildRosterDB.showSourceColumn then legendFS:Show() else legendFS:Hide() end

    local last = GreenWallGuildRosterDB and GreenWallGuildRosterDB.lastBroadcast
    if not last then
        lastBroadcastFS:SetText('|cffff3333' .. ns.L['Never broadcast'] .. '|r')
        return
    end
    local mins = math.floor((time() - last) / 60)
    local hex = 'cff33ff33'
    if mins >= 15 then
        hex = 'cffff3333'
    elseif mins >= 5 then
        hex = 'cffffcc00'
    end
    local ago = mins < 1 and ns.L['just now'] or (ns.L['%d min ago']):format(mins)
    lastBroadcastFS:SetText(('|%s' .. ns.L['Last broadcast: %s'] .. '|r'):format(hex, ago))
end

-- Class icons as real Texture regions, not inline |T markup in the text -
-- an inline icon taller than the font's natural line grows just that
-- line in just that column, and the drift compounds over many rows until
-- columns stop lining up (happened twice already). A separate texture
-- pool sidesteps the text-flow line-height math entirely.
local ICON_SIZE = math.max(10, ROW_HEIGHT - 2)
local classIcons = {}
local function GetClassIcon(i)
    local tex = classIcons[i]
    if not tex then
        tex = content:CreateTexture(nil, 'ARTWORK')
        tex:SetSize(ICON_SIZE, ICON_SIZE)
        tex:SetTexture(CLASS_ICON_TEXTURE)
        classIcons[i] = tex
    end
    -- Repositioned every call, not just on first creation - same as the
    -- row click-buttons below, which never had this drift because they
    -- already did this. Centered on the actual text line (ROW_HEIGHT minus
    -- the trailing LINE_SPACING gap), not the full row pitch - the text
    -- itself is top-justified within that pitch with the gap trailing
    -- below it, so centering against the full pitch pushed icons visibly
    -- lower than the text they're meant to sit next to.
    local lineHeight = ROW_HEIGHT - LINE_SPACING
    tex:SetPoint('TOPLEFT', colX[2] + 2, -(i - 1) * ROW_HEIGHT - (lineHeight - ICON_SIZE) / 2)
    return tex
end

-- Rank badge (Guild Master / officer crown), same atlas textures the
-- native Guild & Communities roster uses next to a member's name. Fixed
-- position near the right edge of the Name column rather than truly
-- "immediately after the name text" - the Name column is one shared
-- multi-line FontString for the whole list (see the column-drift history
-- above), so there's no per-row text width to hook an exact offset to
-- without reintroducing that class of bug.
local BADGE_SIZE = math.max(10, ROW_HEIGHT - 4)
local badgeIcons = {}
local function GetBadgeIcon(i)
    local tex = badgeIcons[i]
    if not tex then
        tex = content:CreateTexture(nil, 'OVERLAY')
        tex:SetSize(BADGE_SIZE, BADGE_SIZE)
        badgeIcons[i] = tex
    end
    local lineHeight = ROW_HEIGHT - LINE_SPACING
    tex:SetPoint('TOPLEFT', colX[4] - BADGE_SIZE - 4, -(i - 1) * ROW_HEIGHT - (lineHeight - BADGE_SIZE) / 2)
    return tex
end

local guildOnlineCounts = {}
local guildOrder = {}

-- Own guild is always gold; each *other* co-guild gets its own color instead
-- of sharing one flat blue, so a 3-plus-guild confederation stays visually
-- distinguishable. Palette-cycling logic lives in Logic.lua
-- (ns.NewPaletteAssigner), shared with Core.lua's Prat tag coloring so both
-- stay visually consistent instead of each hand-rolling their own cache.
local nextPeerGuildColor = ns.NewPaletteAssigner()
local function GuildHexFor(guildName)
    if ns.ownGuild and guildName == ns.ownGuild then return 'ffd200' end
    if not guildName then return ns.PEER_COLOR_PALETTE[1] end
    return nextPeerGuildColor(guildName)
end

local function BuildEntries()
    local list = {}

    local ownGuild = GetGuildInfo('player')
    if ownGuild then
        local total = GetNumGuildMembers() or 0
        for i = 1, total do
            local name, _, rankIndex, level, _, zone, note, _, online, _, classFile = GetGuildRosterInfo(i)
            if name then
                local shortName = name:match('^[^-]+') or name
                list[#list + 1] = {
                    guild = ownGuild, name = shortName, level = level,
                    classFile = classFile, zone = zone, note = note, online = online,
                    linkedMain = GreenWallGuildRosterDB.mainLinks and GreenWallGuildRosterDB.mainLinks[shortName],
                    badge = ns.RankBadge and ns.RankBadge(rankIndex, C_GuildInfo.GuildControlGetRankFlags),
                }
            end
        end
    end

    local db = GreenWallGuildRosterDB and GreenWallGuildRosterDB.peers or {}
    for tag, members in pairs(db) do
      if tag ~= ns.ownTag then
        local gname = ns.peerNames and ns.peerNames[tag] or tag
        for name, info in pairs(members) do
            local zone = info.zone
            if ns.FromCanonicalZone then zone = ns.FromCanonicalZone(zone) end
            list[#list + 1] = {
                guild = gname, name = name, level = info.level, classFile = info.class,
                zone = zone, note = info.note, online = info.online,
                -- Must stay safely longer than Core.lua's FULL_SYNC_INTERVAL
                -- (600s): someone who's continuously online never appears in
                -- a delta (only online/offline *transitions* get reported),
                -- so their ts only advances on a full sync - a threshold
                -- shorter than that interval would flip a perfectly-online
                -- member to "stale" every cycle just before their next
                -- refresh, the same class of bug as when this and
                -- FULL_SYNC_INTERVAL briefly drifted out of proportion
                -- earlier in this addon's history. 900s (1.5x) matches the
                -- margin used back then.
                stale = (time() - (info.ts or 0)) > 900,
                linkedMain = info.linkedMain,
                badge = info.badge,
                -- '^' broadcast, '~' whisper - defaults to '~' for entries
                -- saved before the source field existed, rather than nil.
                marker = info.source == 'broadcast' and '^' or '~',
            }
        end
      end
    end

    -- /who-only members: seen online via /who discovery but never
    -- confirmed via the addon protocol (no reply means either they don't
    -- have the addon, or their reply just hasn't arrived yet) - only added
    -- for names not already covered by confirmed peer data above, which is
    -- always more complete and reliable. No badge/alt-link/note: /who
    -- doesn't provide those, and fabricating them would be misleading.
    -- Shown regardless of showSourceColumn - that toggle only controls the
    -- marker column's own visibility (see UpdateHeaderText/Refresh), not
    -- whether these members exist in the list at all. Gated on
    -- whoDiscoveryEnabled instead: the whole /who scanning + display
    -- subsystem is opt-in, off by default (see Core.lua's RequestWhoQuery).
    if GreenWallGuildRosterDB.whoDiscoveryEnabled then
        local whoDb = GreenWallGuildRosterDB and GreenWallGuildRosterDB.whoSeen or {}
        for tag, seen in pairs(whoDb) do
          if tag ~= ns.ownTag then
            local gname = ns.peerNames and ns.peerNames[tag] or tag
            local confirmed = db[tag]
            for name, info in pairs(seen) do
                if not (confirmed and confirmed[name]) then
                    -- /who only ever reflects who was online at the moment
                    -- of that scan, and scans aren't continuous (30s timer,
                    -- gated on the next hardware event) - without this a
                    -- name would stay listed as "Online" forever after
                    -- being seen once. Same stale/online rendering
                    -- convention as confirmed peer entries below, just a
                    -- shorter window matching /who's own faster cadence.
                    list[#list + 1] = {
                        guild = gname, name = name, level = info.level, classFile = info.classFile,
                        zone = info.zone, online = true, marker = '*',
                        stale = (time() - (info.ts or 0)) > 300,
                    }
                end
            end
          end
        end
    end

    -- Counted here, before the showOffline filter below would otherwise
    -- discard offline entries outright - this needs every entry regardless
    -- of that toggle, it's always "how many are online right now".
    guildOnlineCounts = {}
    guildOrder = {}
    for _, entry in ipairs(list) do
        if entry.online and not entry.stale then
            if not guildOnlineCounts[entry.guild] then
                guildOrder[#guildOrder + 1] = entry.guild
            end
            guildOnlineCounts[entry.guild] = (guildOnlineCounts[entry.guild] or 0) + 1
        end
    end

    if not GreenWallGuildRosterDB.showOffline then
        local filtered = {}
        for _, entry in ipairs(list) do
            -- Stale-online now displays as "Offline" (see below), so it
            -- has to be excluded here too, or "show offline: off" would
            -- still list entries that visibly say Offline.
            if entry.online and not entry.stale then filtered[#filtered + 1] = entry end
        end
        list = filtered
    end

    -- Mixed view like the native guild frame: sorted by whichever column
    -- was last clicked (default: level, descending), not grouped by guild
    -- - the guild each member belongs to is just another column.
    table.sort(list, function(a, b)
        local av, bv = ValueOf(a, sortColumn), ValueOf(b, sortColumn)
        if av == bv then
            return (a.name or '') < (b.name or '')
        end
        if sortAsc then return av < bv else return av > bv end
    end)
    return list
end

local function Refresh()
    UpdateHeaderText()
    UpdateLastBroadcastLabel()
    local list = BuildEntries()
    local col = { {}, {}, {}, {}, {}, {}, {}, {} }

    -- Own guild first, then peers in whatever order they were first seen -
    -- own-guild gold/peer light-blue matches the Guild column's coloring.
    local countParts = {}
    for _, gname in ipairs(guildOrder) do
        local guildHex = GuildHexFor(gname)
        countParts[#countParts + 1] = ('|cff%s%s|r: %d'):format(guildHex, gname, guildOnlineCounts[gname])
    end
    onlineCountFS:SetText(table.concat(countParts, '   '))

    -- Pass 1: just the text. Buttons/icons are positioned in pass 2, after
    -- the real row pitch is measured from the rendered text - guessing it
    -- up front (font metrics + manual spacing) kept coming out a fraction
    -- of a pixel off, which compounds into a visible drift over 15-20 rows.
    for _, entry in ipairs(list) do
        local color = (CLASS_COLORS and entry.classFile and CLASS_COLORS[entry.classFile]) or NORMAL_FONT_COLOR
        local hex = ('%02x%02x%02x'):format((color.r or 1) * 255, (color.g or 1) * 255, (color.b or 1) * 255)
        -- A full sync only ever mentions who's currently online, so someone
        -- who went offline (and wasn't caught by the one-shot "just went
        -- offline" delta - e.g. we weren't around to receive it) never
        -- gets an explicit correction; their entry just stays frozen at
        -- online=true forever, no matter how many future syncs arrive.
        -- After the stale window, "haven't heard they're online in 20
        -- minutes" is in practice almost always "offline by now" - showing
        -- that plainly beats leaving it in "unbekannt" limbo permanently.
        local status
        if entry.online then
            status = entry.stale and '|cffff3333Offline|r' or '|cff33ff33Online|r'
        else
            status = '|cffff3333Offline|r'
        end

        col[1][#col[1] + 1] = tostring(entry.level or '?')
        col[3][#col[3] + 1] = ('|cff%s%s|r'):format(hex, Clip(entry.name or '?', 22))
        col[4][#col[4] + 1] = Clip(entry.zone or '', 30)
        local guildHex = GuildHexFor(entry.guild)
        col[5][#col[5] + 1] = ('|cff%s%s|r'):format(guildHex, Clip(entry.guild or '?', 15))
        col[6][#col[6] + 1] = status
        if entry.linkedMain and entry.linkedMain ~= '' then
            col[7][#col[7] + 1] = ('|cff888888%s|r'):format(Clip(entry.linkedMain, 22))
        else
            col[7][#col[7] + 1] = ''
        end
        if GreenWallGuildRosterDB.showSourceColumn then
            col[8][#col[8] + 1] = entry.marker and ('|cff888888%s|r'):format(entry.marker) or ''
        end
    end

    for i = #list + 1, #rowButtons do
        rowButtons[i]:Hide()
    end
    for i = #list + 1, #classIcons do
        classIcons[i]:Hide()
    end
    for i = #list + 1, #rowBGs do
        rowBGs[i]:Hide()
    end
    for i = #list + 1, #badgeIcons do
        badgeIcons[i]:Hide()
    end

    if #list == 0 then
        columnFS[3]:SetText('|cff888888' .. ns.L['No data yet - waiting for guild roster / broadcast from the other co-guild.'] .. '|r')
        for i = 1, #columnFS do
            if i ~= 3 then columnFS[i]:SetText('') end
        end
    else
        for i = 1, #columnFS do
            if i ~= 2 then
                columnFS[i]:SetText(table.concat(col[i], '\n'))
            end
        end

        -- Pass 2: measure the real, rendered pitch between lines and place
        -- the icon/button pool against that, instead of a precomputed
        -- constant that never quite matched it. GetStringHeight() only
        -- counts LINE_SPACING *between* lines (n*lineHeight + (n-1)*spacing),
        -- not after the last one - dividing that raw total by n alone
        -- under-measures the true per-line pitch by spacing/n, an error
        -- that grows with row index (each row a little further off than
        -- the last) until it's visibly a few pixels by the bottom of a
        -- long list. Adding one extra LINE_SPACING back before dividing
        -- corrects the average to the true constant per-line pitch.
        ROW_HEIGHT = (columnFS[3]:GetStringHeight() + LINE_SPACING) / #list
        for i, entry in ipairs(list) do
            local bg = GetRowBG(i)
            bg:Show()

            local btn = GetRowButton(i)
            btn:SetPoint('TOPLEFT', 0, -(i - 1) * ROW_HEIGHT + LINE_SPACING / 2)
            btn.targetName = entry.name
            btn:Show()

            local iconTex = GetClassIcon(i)
            local coords = entry.classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[entry.classFile]
            if coords then
                iconTex:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                iconTex:Show()
            else
                iconTex:Hide()
            end

            local badgeTex = GetBadgeIcon(i)
            -- Party/raid leader and assistant icons instead of the
            -- Communities-frame crown atlas - those atlas names are a
            -- guess at whether Classic Era's client even ships them,
            -- while these plain textures have existed since vanilla and
            -- are guaranteed present.
            if entry.badge == '2' then
                badgeTex:SetTexture('Interface\\GroupFrame\\UI-Group-LeaderIcon')
                badgeTex:Show()
            elseif entry.badge == '1' then
                badgeTex:SetTexture('Interface\\GroupFrame\\UI-Group-AssistantIcon')
                badgeTex:Show()
            else
                badgeTex:Hide()
            end
        end
    end

    content:SetHeight(math.max(10, columnFS[3]:GetStringHeight() + 10))
end

frame:SetScript('OnShow', function()
    frame:Raise()
    Refresh()
end)

-- Used to be an OnUpdate poller re-running the full Refresh() every 2
-- seconds. With a 900+ member combined roster, that meant rebuilding
-- hundreds of throwaway Lua tables every couple of seconds for as long as
-- the window stayed open - real contributor to the addon's memory/CPU
-- footprint. This is the cheap replacement: while the window is open,
-- just ask the server for a roster refresh every 15s. That alone doesn't
-- touch our UI at all - it only matters if Blizzard actually has new
-- data, in which case GUILD_ROSTER_UPDATE fires and Core.lua's own
-- (throttled) RequestRefresh handles it. Own-guild online/offline status
-- would otherwise only update whenever Blizzard happens to fire that
-- event on its own, which isn't reliably often in a busy guild.
local elapsedSincePoll = 0
frame:SetScript('OnUpdate', function(self, elapsed)
    elapsedSincePoll = elapsedSincePoll + elapsed
    if elapsedSincePoll >= 15 then
        elapsedSincePoll = 0
        C_GuildInfo.GuildRoster()
    end
end)

ns.RefreshFrame = Refresh
ns.ToggleFrame = function()
    if frame:IsShown() then frame:Hide() else frame:Show() end
end
