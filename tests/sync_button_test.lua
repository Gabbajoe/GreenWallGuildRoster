local root = (arg[0]:match('(.*[/\\])') or './') .. '../'
local frames, combat = {}, false
local progress = { state = 'queued', remaining = 7, total = 7, waiting = false, seconds = 120 }
GetLocale = function() return 'deDE' end
InCombatLockdown = function() return combat end
GreenWallGuildRosterDB = { safePassThrough = true }
UIParent = { GetCenter = function() return 500, 400 end }
CreateFrame = function(_, name)
    local f = { scripts = {} }
    for _, method in ipairs({ 'SetSize', 'SetPoint', 'SetClampedToScreen', 'SetMovable',
        'RegisterForDrag', 'RegisterEvent', 'SetFrameStrata', 'SetToplevel',
        'SetNormalFontObject', 'ClearAllPoints' }) do f[method] = function() end end
    function f:Raise() self.raised = true end
    function f:StartMoving() self.moving = true end
    function f:StopMovingOrSizing() self.moving = false end
    function f:GetCenter() return 700, 300 end
    function f:SetPoint(...) self.point = {...} end
    function f:SetScript(event, fn) self.scripts[event] = fn end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:SetText(text) self.text = text end
    function f:SetEnabled(enabled) self.enabled = enabled end
    frames[name or 'events'] = f
    return f
end
local ns = { BindSyncButton = function() end, GetSyncProgress = function() return progress end,
    HardwareAPI = { IsReady = function() return true end } }
assert(loadfile(root .. 'UI/SyncButton.lua'))('GreenWallGuildRoster', ns)
local b = frames.GreenWallGuildRosterSyncButton
assert(not b.shown)
ns.SetSyncButtonShown(true)
assert(b.shown and b.enabled and b.syncCanSend and b.text:find('7 Klicks'))
progress.waiting, progress.remaining = true, 6
b.scripts.OnUpdate(b, 0.2)
assert(b.enabled and not b.syncCanSend and b.text:find('Bestätigung') and b.text:find('6 Klicks'))
progress.remaining = 0
b.scripts.OnUpdate(b, 0.2)
assert(b.enabled and not b.syncCanSend and b.text:find('Bestätigung'))
progress = { state = 'complete', remaining = 0, total = 0, seconds = 0 }
b.scripts.OnUpdate(b, 0.2)
assert(b.enabled and not b.syncCanSend and b.text:find('abgeschlossen'))
combat = true; b.scripts.OnUpdate(b, 0.2)
assert(b.enabled and not b.syncCanSend and b.text:find('Kampf'))
combat = false; GreenWallGuildRosterDB.safePassThrough = false
b.scripts.OnUpdate(b, 0.2)
assert(b.enabled and not b.syncCanSend and b.text:find('ausgeschaltet'))
ns.SetSyncButtonShown(false)
assert(not b.shown and not GreenWallGuildRosterDB.showSyncButton)
print('Sync button: visibility, remaining clicks, pending final echo, combat and disabled states passed.')

GameTooltip = { Hide = function() end }
-- Disabled sending must leave drag and click-to-raise available.
b.scripts.OnMouseDown(b)
assert(b.raised)
b.scripts.OnDragStart(b)
assert(b.moving and b.dragging)
b.scripts.OnDragStop(b)
assert(not b.moving and not b.dragging)
assert(GreenWallGuildRosterDB.syncButtonPosition.x == 200)
assert(GreenWallGuildRosterDB.syncButtonPosition.y == -100)
frames.events.scripts.OnEvent()
assert(b.point[1] == 'CENTER' and b.point[4] == 200 and b.point[5] == -100)
print('Sync button: idle dragging, raise and saved-position restoration passed.')
