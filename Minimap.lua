local ADDON_NAME, ns = ...

GreenWallGuildRosterDB = GreenWallGuildRosterDB or {}
if not GreenWallGuildRosterDB.minimapAngle then
    GreenWallGuildRosterDB.minimapAngle = 220
end
if GreenWallGuildRosterDB.minimapHidden == nil then
    GreenWallGuildRosterDB.minimapHidden = false
end

local button = CreateFrame('Button', 'GreenWallGuildRosterMinimapButton', Minimap)
button:SetSize(31, 31)
button:SetFrameStrata('MEDIUM')
button:SetFrameLevel(8)
button:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
button:RegisterForDrag('LeftButton')

local icon = button:CreateTexture(nil, 'BACKGROUND')
icon:SetTexture('Interface\\AddOns\\GreenWallGuildRoster\\icon.png')
icon:SetSize(20, 20)
icon:SetPoint('CENTER', 0, 0)

local border = button:CreateTexture(nil, 'OVERLAY')
border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
border:SetSize(54, 54)
border:SetPoint('TOPLEFT', 0, 0)

-- Subtle brighten-on-hover instead of the flashy zoom-button flare - this
-- is the standard soft highlight most minimap addon buttons use.
button:SetHighlightTexture('Interface\\Buttons\\UI-Common-MouseHilight', 'ADD')

local function UpdatePosition()
    local angle = math.rad(GreenWallGuildRosterDB.minimapAngle or 220)
    local radius = 105
    button:ClearAllPoints()
    button:SetPoint('CENTER', Minimap, 'CENTER', math.cos(angle) * radius, math.sin(angle) * radius)
end
UpdatePosition()

local function SetMinimapButtonShown(shown)
    GreenWallGuildRosterDB.minimapHidden = not shown
    if shown then button:Show() else button:Hide() end
end
ns.SetMinimapButtonShown = SetMinimapButtonShown

-- Real SavedVariables data isn't injected until right before ADDON_LOADED
-- fires (see Core.lua's ADDON_LOADED comment) - deciding the button's
-- initial visibility here at file-load time would always see the stale
-- default instead of the real saved value. ApplyMinimapButtonVisibility()
-- is called from Core.lua's ADDON_LOADED handler once the real value has
-- landed.
local function ApplyMinimapButtonVisibility()
    if GreenWallGuildRosterDB.minimapHidden then
        button:Hide()
    else
        button:Show()
    end
end
ns.ApplyMinimapButtonVisibility = ApplyMinimapButtonVisibility

button:SetScript('OnDragStart', function(self)
    self:SetScript('OnUpdate', function()
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        px, py = px / scale, py / scale
        GreenWallGuildRosterDB.minimapAngle = math.deg(math.atan2(py - my, px - mx))
        UpdatePosition()
    end)
end)
button:SetScript('OnDragStop', function(self)
    self:SetScript('OnUpdate', nil)
    -- The button moves out from under the cursor during a drag without a
    -- clean OnLeave firing, which could leave the tooltip showing stale
    -- content pointed at empty space after the drag ends.
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end)

button:SetScript('OnClick', function(self, mouseButton)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    if mouseButton == 'RightButton' then
        if ns.Broadcast then
            ns.Broadcast()
            print('|cff33ff99GreenWallGuildRoster|r: ' .. ns.L['Broadcast sent.'])
        end
    elseif ns.ToggleFrame then
        ns.ToggleFrame()
    end
end)

button:SetScript('OnEnter', function(self)
    GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
    GameTooltip:SetText(ns.L['GreenWall GuildRoster'])
    GameTooltip:AddLine(ns.L['Left-click: open/close window'], 1, 1, 1)
    GameTooltip:AddLine(ns.L['Right-click: send broadcast'], 1, 1, 1)
    local last = GreenWallGuildRosterDB.lastBroadcast
    if last then
        local mins = math.floor((time() - last) / 60)
        local ago = mins < 1 and ns.L['just now'] or (ns.L['%d min ago']):format(mins)
        GameTooltip:AddLine((ns.L['Last broadcast: %s']):format(ago), 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine(ns.L['Never broadcast'], 1, 0.3, 0.3)
    end
    GameTooltip:Show()
end)
button:SetScript('OnLeave', function() GameTooltip:Hide() end)

-- Native Blizzard Options > AddOns entry, same Settings.RegisterCanvasLayoutCategory
-- API GreenWall itself uses (verified working in this client).
local optionsFrame = CreateFrame('Frame', 'GreenWallGuildRosterOptions', UIParent)
optionsFrame.name = 'GreenWall GuildRoster'

local title = optionsFrame:CreateFontString(nil, 'OVERLAY', 'GameFontNormalLarge')
title:SetPoint('TOPLEFT', 16, -16)
title:SetText('GreenWall GuildRoster')

local minimapCB = CreateFrame('CheckButton', 'GreenWallGuildRosterMinimapCB', optionsFrame, 'UICheckButtonTemplate')
minimapCB:SetPoint('TOPLEFT', title, 'BOTTOMLEFT', -2, -16)
_G[minimapCB:GetName() .. 'Text']:SetText(ns.L['Show minimap button'])
minimapCB:SetScript('OnClick', function(self)
    SetMinimapButtonShown(self:GetChecked() and true or false)
end)

if GreenWallGuildRosterDB.showSourceColumn == nil then
    GreenWallGuildRosterDB.showSourceColumn = false
end
local sourceColumnCB = CreateFrame('CheckButton', 'GreenWallGuildRosterSourceColumnCB', optionsFrame, 'UICheckButtonTemplate')
sourceColumnCB:SetPoint('TOPLEFT', minimapCB, 'BOTTOMLEFT', 0, -8)
_G[sourceColumnCB:GetName() .. 'Text']:SetText(ns.L['Show data-source column (requires /reload)'])
sourceColumnCB:SetScript('OnClick', function(self)
    GreenWallGuildRosterDB.showSourceColumn = self:GetChecked() and true or false
end)

-- Off by default - this reaches into a third-party addon's (Prat-3.0) own
-- SavedVariables-backed cache, which not everyone running this addon wants
-- done automatically on their behalf. See the FeedPratNameCache comment in
-- Core.lua for what it actually does.
local pratIntegrationCB = CreateFrame('CheckButton', 'GreenWallGuildRosterPratCB', optionsFrame, 'UICheckButtonTemplate')
pratIntegrationCB:SetPoint('TOPLEFT', sourceColumnCB, 'BOTTOMLEFT', 0, -8)
_G[pratIntegrationCB:GetName() .. 'Text']:SetText(ns.L['Show co-guild member levels in Prat-3.0 chat (if installed)'])
pratIntegrationCB:SetScript('OnClick', function(self)
    GreenWallGuildRosterDB.pratIntegration = self:GetChecked() and true or false
end)

local pratIntegrationDesc = optionsFrame:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
pratIntegrationDesc:SetPoint('TOPLEFT', pratIntegrationCB, 'BOTTOMLEFT', 24, -2)
pratIntegrationDesc:SetWidth(520)
pratIntegrationDesc:SetJustifyH('LEFT')
pratIntegrationDesc:SetText(('%s |cff5ec4ff[60:Aruthra:S]|r: hi\n%s'):format(
    ns.L['Example:'],
    ns.L['To avoid seeing the tag twice, also turn off GreenWall\'s own co-guild tag: |cffffd200/gw tag off|r']
))

optionsFrame:SetScript('OnShow', function()
    minimapCB:SetChecked(not GreenWallGuildRosterDB.minimapHidden)
    sourceColumnCB:SetChecked(GreenWallGuildRosterDB.showSourceColumn)
    pratIntegrationCB:SetChecked(GreenWallGuildRosterDB.pratIntegration)
end)

local category = Settings.RegisterCanvasLayoutCategory(optionsFrame, optionsFrame.name)
Settings.RegisterAddOnCategory(category)
