local ADDON_NAME, ns = ...

local CLASS_COLORS = RAID_CLASS_COLORS
local CLASS_ICON_TEXTURE = 'Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes'

local frame = CreateFrame('Frame', 'GreenWallGuildRosterFrame', UIParent, 'BasicFrameTemplateWithInset')
frame:SetSize(580, 520)
frame:SetPoint('CENTER')
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag('LeftButton')
frame:SetScript('OnDragStart', frame.StartMoving)
frame:SetScript('OnDragStop', frame.StopMovingOrSizing)
frame:SetClampedToScreen(true)
frame:Hide()
frame.TitleText:SetText('GreenWall Gildenroster')

-- Column layout shared by the header and the body. Each column is one
-- FontString spanning every row (see below) rather than a grid of
-- per-row frames, so this reuses the exact CreateFontString-in-a-Frame
-- pattern already proven to render reliably in this client. Class icons
-- are embedded as inline |T texture markup inside the text itself, for
-- the same reason - no separate per-row Texture regions needed.
local headers = { 'Lvl', 'Klasse', 'Name', 'Zone', 'Gilde', 'Status' }
local colX =    { 0,     36,       80,     220,    360,     460 }
local CONTENT_WIDTH = 530

GreenWallGuildRosterDB = GreenWallGuildRosterDB or {}
if GreenWallGuildRosterDB.showOffline == nil then
    GreenWallGuildRosterDB.showOffline = false
end

local offlineCheck = CreateFrame('CheckButton', nil, frame, 'UICheckButtonTemplate')
offlineCheck:SetSize(22, 22)
offlineCheck:SetPoint('TOPLEFT', 14, -30)
offlineCheck:SetChecked(GreenWallGuildRosterDB.showOffline)
local offlineLabel = offlineCheck:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
offlineLabel:SetPoint('LEFT', offlineCheck, 'RIGHT', 2, 1)
offlineLabel:SetText('Offline anzeigen')
offlineCheck:SetScript('OnClick', function(self)
    GreenWallGuildRosterDB.showOffline = self:GetChecked() and true or false
    if ns.RefreshFrame then ns.RefreshFrame() end
end)

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

local headerFS = {}
for i, h in ipairs(headers) do
    local fs = headerRow:CreateFontString(nil, 'OVERLAY', 'GameFontNormalSmall')
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
        headerFS[i]:SetText(h .. (i == sortColumn and (sortAsc and ' ^' or ' v') or ''))
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
    info.text = 'Anflüstern'
    info.notCheckable = true
    info.func = function() WhisperPlayer(name) end
    UIDropDownMenu_AddButton(info, level)

    info = UIDropDownMenu_CreateInfo()
    info.text = 'Einladen'
    info.notCheckable = true
    info.func = function() InvitePlayer(name) end
    UIDropDownMenu_AddButton(info, level)
end, 'MENU')

local function ShowRowMenu(rowBtn)
    local name = rowBtn.targetName
    if not name then return end
    rowMenuFrame.targetName = name
    ToggleDropDownMenu(1, nil, rowMenuFrame, 'cursor', 0, 0)
end

local function GetRowButton(i)
    local btn = rowButtons[i]
    if not btn then
        btn = CreateFrame('Button', nil, content)
        btn:SetHeight(ROW_HEIGHT)
        btn:SetPoint('TOPLEFT', colX[3], -(i - 1) * ROW_HEIGHT)
        btn:SetPoint('TOPRIGHT', content, 'TOPLEFT', colX[4] - 6, -(i - 1) * ROW_HEIGHT)
        btn:RegisterForClicks('RightButtonUp')
        btn:SetScript('OnClick', ShowRowMenu)
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

-- No auto-broadcast (see Core.lua), so this is a passive nudge: color goes
-- from green to red the staler your last broadcast gets, as a reminder to
-- click the button yourself rather than anything sending on its own.
local function UpdateLastBroadcastLabel()
    local last = GreenWallGuildRosterDB and GreenWallGuildRosterDB.lastBroadcast
    if not last then
        lastBroadcastFS:SetText('|cffff3333Noch nie gesendet|r')
        return
    end
    local mins = math.floor((time() - last) / 60)
    local hex = 'cff33ff33'
    if mins >= 15 then
        hex = 'cffff3333'
    elseif mins >= 5 then
        hex = 'cffffcc00'
    end
    local ago = mins < 1 and 'gerade eben' or (mins .. ' min her')
    lastBroadcastFS:SetText(('|%sLetzter Broadcast: %s|r'):format(hex, ago))
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
    -- already did this.
    tex:SetPoint('TOPLEFT', colX[2] + 2, -(i - 1) * ROW_HEIGHT - (ROW_HEIGHT - ICON_SIZE) / 2)
    return tex
end

local function BuildEntries()
    local list = {}

    local ownGuild = GetGuildInfo('player')
    if ownGuild then
        local total = GetNumGuildMembers() or 0
        for i = 1, total do
            local name, _, _, level, _, zone, note, _, online, _, classFile = GetGuildRosterInfo(i)
            if name then
                list[#list + 1] = {
                    guild = ownGuild, name = name:match('^[^-]+') or name, level = level,
                    classFile = classFile, zone = zone, note = note, online = online,
                }
            end
        end
    end

    local db = GreenWallGuildRosterDB and GreenWallGuildRosterDB.peers or {}
    for tag, members in pairs(db) do
        local gname = ns.peerNames and ns.peerNames[tag] or tag
        for name, info in pairs(members) do
            list[#list + 1] = {
                guild = gname, name = name, level = info.level, classFile = info.class,
                zone = info.zone, note = info.note, online = info.online,
                stale = (time() - (info.ts or 0)) > 900,
            }
        end
    end

    if not GreenWallGuildRosterDB.showOffline then
        local filtered = {}
        for _, entry in ipairs(list) do
            if entry.online then filtered[#filtered + 1] = entry end
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
    local col = { {}, {}, {}, {}, {}, {} }

    -- Pass 1: just the text. Buttons/icons are positioned in pass 2, after
    -- the real row pitch is measured from the rendered text - guessing it
    -- up front (font metrics + manual spacing) kept coming out a fraction
    -- of a pixel off, which compounds into a visible drift over 15-20 rows.
    for _, entry in ipairs(list) do
        local color = (CLASS_COLORS and entry.classFile and CLASS_COLORS[entry.classFile]) or NORMAL_FONT_COLOR
        local hex = ('%02x%02x%02x'):format((color.r or 1) * 255, (color.g or 1) * 255, (color.b or 1) * 255)
        local status = entry.online and '|cff33ff33Online|r' or (entry.stale and '|cff888888unbekannt|r' or '|cffff3333Offline|r')

        col[1][#col[1] + 1] = tostring(entry.level or '?')
        col[3][#col[3] + 1] = ('|cff%s%s|r'):format(hex, Clip(entry.name or '?', 22))
        col[4][#col[4] + 1] = Clip(entry.zone or '', 22)
        local guildHex = (ns.ownGuild and entry.guild == ns.ownGuild) and 'ffd200' or '5ec4ff'
        col[5][#col[5] + 1] = ('|cff%s%s|r'):format(guildHex, Clip(entry.guild or '?', 15))
        col[6][#col[6] + 1] = status
    end

    for i = #list + 1, #rowButtons do
        rowButtons[i]:Hide()
    end
    for i = #list + 1, #classIcons do
        classIcons[i]:Hide()
    end

    if #list == 0 then
        columnFS[3]:SetText('|cff888888Keine Daten - warte auf Gildenroster / Broadcast der anderen Co-Gilde.|r')
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
        -- constant that never quite matched it.
        ROW_HEIGHT = columnFS[3]:GetStringHeight() / #list
        for i, entry in ipairs(list) do
            local btn = GetRowButton(i)
            btn:SetPoint('TOPLEFT', colX[3], -(i - 1) * ROW_HEIGHT)
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
        end
    end

    content:SetHeight(math.max(10, columnFS[3]:GetStringHeight() + 10))
end

frame:SetScript('OnShow', Refresh)

-- Belt-and-suspenders: keep the window current while it's open, in case it
-- was first shown before the guild roster had finished loading.
local elapsedSinceRefresh = 0
frame:SetScript('OnUpdate', function(self, elapsed)
    elapsedSinceRefresh = elapsedSinceRefresh + elapsed
    if elapsedSinceRefresh >= 2 then
        elapsedSinceRefresh = 0
        Refresh()
    end
end)

ns.RefreshFrame = Refresh
ns.ToggleFrame = function()
    if frame:IsShown() then frame:Hide() else frame:Show() end
end
