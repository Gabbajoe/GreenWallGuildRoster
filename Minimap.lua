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
if GreenWallGuildRosterDB.minimapHidden then
    button:Hide()
end

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
-- API GreenWall itself uses (verified working in this client). Just the one
-- checkbox - not worth a scroll frame or multiple sections for that.
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
optionsFrame:SetScript('OnShow', function()
    minimapCB:SetChecked(not GreenWallGuildRosterDB.minimapHidden)
end)

local category = Settings.RegisterCanvasLayoutCategory(optionsFrame, optionsFrame.name)
Settings.RegisterAddOnCategory(category)
