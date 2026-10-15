local _, ns = ...
local de = GetLocale() == 'deDE'
local button = CreateFrame('Button', 'GreenWallGuildRosterSyncButton', UIParent, 'UIPanelButtonTemplate')
button:SetSize(290, 48)
button:SetPoint('CENTER', UIParent, 'CENTER', 0, -180)
button:SetClampedToScreen(true)
button:SetMovable(true)
button:SetFrameStrata('MEDIUM')
button:SetToplevel(true)
button:SetScript('OnMouseDown', function(self) self:Raise() end)
button:RegisterForDrag('RightButton')
local function StopDragging(self)
    if not self.dragging then return end
    self:StopMovingOrSizing()
    self.dragging = false
    local x, y = self:GetCenter()
    local px, py = UIParent:GetCenter()
    if x and y and px and py then
        GreenWallGuildRosterDB.syncButtonPosition = { x = x - px, y = y - py }
    end
end
button:SetScript('OnDragStart', function(self)
    self.dragging = true
    self:Raise()
    self:StartMoving()
    GameTooltip:Hide()
end)
button:SetScript('OnDragStop', StopDragging)
button:SetScript('OnHide', StopDragging)
ns.BindSyncButton(button)
local states = {
    ['disabled'] = de and 'Pass-through ausgeschaltet' or 'Pass-through disabled',
    ['waiting-capability'] = de and 'Warte auf Partnergilden' or 'Waiting for peer guilds',
    ['waiting-channel-or-broker'] = de and 'Warte auf Kanal / Kampfende' or 'Waiting for channel / combat end',
    ['waiting-roster'] = de and 'Warte auf Gildenliste' or 'Waiting for guild roster',
    ['complete'] = de and 'Übertragung abgeschlossen' or 'Transfer complete',
    ['snapshot-bounds'] = de and 'Roster zu groß – Broadcast nutzen' or 'Roster too large – use Broadcast',
    ['oversized-row'] = de and 'Eintrag zu groß – Broadcast nutzen' or 'Row too large – use Broadcast',
}
local function Refresh()
    if not GreenWallGuildRosterDB or not GreenWallGuildRosterDB.showSyncButton then button:Hide(); return end
    button:Show()
    local p = ns.GetSyncProgress()
    local enabled = GreenWallGuildRosterDB.safePassThrough ~= false
    local combat = InCombatLockdown and InCombatLockdown()
    if not enabled then
        button:SetText(states.disabled)
    elseif combat then
        button:SetText(de and 'Sync: Pause im Kampf' or 'Sync: paused in combat')
    elseif p.waiting then
        button:SetText((de and 'Warte auf Bestätigung · danach %d Klicks\n%ds verbleibend' or
            'Waiting for echo · then %d clicks\n%ds remaining'):format(p.remaining, p.seconds))
    elseif p.total > 0 then
        button:SetText((de and 'Sync: noch %d Klicks · %ds\nEin Paket pro Klick' or
            'Sync: %d clicks left · %ds\nOne frame per click'):format(p.remaining, p.seconds))
    else
        button:SetText(states[p.state] or ('Sync: ' .. p.state))
    end
    -- Keep mouse/drag handling alive even when there is nothing to send.
    button.syncCanSend = enabled and not combat and not p.waiting and p.total > 0
        and ns.HardwareAPI.IsReady()
    button:SetEnabled(true)
    button:SetNormalFontObject(button.syncCanSend and 'GameFontNormal' or 'GameFontDisable')
end
function ns.SetSyncButtonShown(shown)
    GreenWallGuildRosterDB.showSyncButton = shown and true or false
    Refresh()
end
button:SetScript('OnEnter', function(self)
    GameTooltip:SetOwner(self, 'ANCHOR_TOP')
    GameTooltip:SetText('GreenWall GuildRoster Sync')
    GameTooltip:AddLine(de and 'Linksklick: ein Paket senden. Rechts ziehen: verschieben.' or
        'Left-click: send one frame. Right-drag: move.', 1, 1, 1, true)
    GameTooltip:AddLine(de and 'Klickzahl ohne Wiederholungen. Erst die Bestätigung schließt die Übertragung ab.' or
        'Click count excludes retries. Completion requires the final echo.', 1, 0.8, 0, true)
    GameTooltip:Show()
end)
button:SetScript('OnLeave', function() GameTooltip:Hide() end)
-- This timer only displays progress; it never prepares or submits a frame.
local elapsed = 0
button:SetScript('OnUpdate', function(_, dt)
    elapsed = elapsed + dt
    if elapsed >= 0.1 then elapsed = 0; Refresh() end
end)
local events = CreateFrame('Frame')
events:RegisterEvent('PLAYER_LOGIN')
events:SetScript('OnEvent', function()
    local position = GreenWallGuildRosterDB and GreenWallGuildRosterDB.syncButtonPosition
    if type(position) == 'table' and type(position.x) == 'number' and type(position.y) == 'number' then
        button:ClearAllPoints()
        button:SetPoint('CENTER', UIParent, 'CENTER', position.x, position.y)
    end
    Refresh()
end)
button:Hide()
