local ADDON_NAME, ns = ...

GreenWallGuildRosterDB = GreenWallGuildRosterDB or {}
if not GreenWallGuildRosterDB.minimapAngle then
    GreenWallGuildRosterDB.minimapAngle = 220
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
end)

button:SetScript('OnClick', function(self, mouseButton)
    if mouseButton == 'RightButton' then
        if ns.Broadcast then
            ns.Broadcast()
            print('|cff33ff99GreenWallGuildRoster|r: Broadcast gesendet.')
        end
    elseif ns.ToggleFrame then
        ns.ToggleFrame()
    end
end)

button:SetScript('OnEnter', function(self)
    GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
    GameTooltip:SetText('GreenWall Gildenroster')
    GameTooltip:AddLine('Linksklick: Fenster öffnen/schließen', 1, 1, 1)
    GameTooltip:AddLine('Rechtsklick: Broadcast senden', 1, 1, 1)
    local last = GreenWallGuildRosterDB.lastBroadcast
    if last then
        local mins = math.floor((time() - last) / 60)
        GameTooltip:AddLine(('Letzter Broadcast: %s'):format(mins < 1 and 'gerade eben' or (mins .. ' min her')), 0.6, 0.6, 0.6)
    else
        GameTooltip:AddLine('Noch nie gesendet', 1, 0.3, 0.3)
    end
    GameTooltip:Show()
end)
button:SetScript('OnLeave', function() GameTooltip:Hide() end)
