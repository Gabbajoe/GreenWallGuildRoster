local ADDON_NAME, ns = ...

-- English string is the lookup key itself, so English needs zero entries
-- below - only other locales need explicit overrides. Any string with no
-- entry for the current locale just falls through to the key (English) via
-- the metatable, so a missing translation degrades to English rather than
-- erroring or showing a blank.
local L = setmetatable({}, { __index = function(t, k) return k end })
ns.L = L

if GetLocale() == 'deDE' then
    -- Window / headers
    L['GreenWall GuildRoster'] = 'GreenWall Gildenroster'
    L['Class'] = 'Klasse'
    L['Guild'] = 'Gilde'
    L['Alt'] = 'Twink'
    -- 'Name', 'Zone', 'Status' deliberately left untranslated (English) per
    -- explicit user preference - routed through L like every other header
    -- so a future locale isn't blocked from translating them, they just
    -- fall through to English here same as any other missing key.
    L['Show Offline'] = 'Offline anzeigen'
    L['No data yet - waiting for guild roster / broadcast from the other co-guild.'] = 'Noch keine Daten - warte auf Gildenroster / Broadcast der anderen Co-Gilde.'
    L['Never broadcast'] = 'Noch nie gesendet'
    L['Last broadcast: %s'] = 'Letzter Broadcast: %s'
    L['just now'] = 'gerade eben'
    L['%d min ago'] = '%d min her'

    -- Row context menu
    L['Whisper'] = 'Anflüstern'
    L['Invite'] = 'Einladen'
    L['Copy Name'] = 'Namen kopieren'
    L['Copy character name (Ctrl+C)'] = 'Charakternamen kopieren (Strg+C)'

    -- Minimap tooltip
    L['Left-click: open/close window'] = 'Linksklick: Fenster öffnen/schließen'
    L['Right-click: send broadcast'] = 'Rechtsklick: Broadcast senden'

    -- Options panel
    L['Show minimap button'] = 'Minimap-Button anzeigen'
    L['Show data-source column (requires /reload)'] = 'Datenquellen-Spalte anzeigen (erfordert /reload)'
    L['Show co-guild member levels in Prat-3.0 chat (if installed)'] = 'Level von Co-Gilden-Mitgliedern im Prat-3.0-Chat anzeigen (falls installiert)'
    L['Example:'] = 'Beispiel:'
    L['To avoid seeing the tag twice, also turn off GreenWall\'s own co-guild tag: |cffffd200/gw tag off|r'] = 'Damit der Tag nicht doppelt erscheint, zusätzlich GreenWalls eigenen Co-Gilden-Tag abschalten: |cffffd200/gw tag off|r'
    L['^ broadcast   ~ whisper'] = '^ Broadcast   ~ Flüster'

    -- Slash command output
    L['GreenWallGuildRoster commands:'] = 'GreenWallGuildRoster Befehle:'
    L['/gwgr - open/close the roster window'] = '/gwgr - Roster-Fenster öffnen/schließen'
    L["/gwgr broadcast - send a full roster snapshot over GreenWall's confederation channel (GreenWallAPI)"] = '/gwgr broadcast - vollen Roster-Stand über GreenWalls Konföderations-Kanal senden (GreenWallAPI)'
    L["/gwgr setmain <name> - mark the character you're on as an alt of <name>; no name clears it"] = '/gwgr setmain <Name> - diesen Charakter als Alt von <Name> markieren; ohne Namen wird es entfernt'
    L['/gwgr status - show GreenWallAPI availability, own tag, and known confederation tags'] = '/gwgr status - zeigt GreenWallAPI-Verfügbarkeit, eigenes Tag und bekannte Konföderations-Tags'
    L['/gwgr debug - toggle addon-message RX/TX logging'] = '/gwgr debug - Addon-Message RX/TX-Logging umschalten'
    L['/gwgr minimap - toggle the minimap button (also in Options > AddOns > GreenWall GuildRoster)'] = '/gwgr minimap - Minimap-Button umschalten (auch unter Optionen > AddOns > GreenWall GuildRoster)'
    L['/gwgr exportzones - export all known zone names for your client language, for building translation tables'] = '/gwgr exportzones - exportiert alle bekannten Zonennamen für deine Client-Sprache, zum Aufbau von Übersetzungstabellen'
    L['/gwgr help - this list'] = '/gwgr help - diese Liste'
    L['Exported %d zone names for locale "%s" into SavedVariables.'] = '%d Zonennamen für Sprache "%s" in die SavedVariables exportiert.'
    L['/reload or log out to flush to disk, then find GreenWallGuildRosterDB.zoneExport in your SavedVariables/GreenWallGuildRoster.lua and send it over.'] = '/reload oder ausloggen zum Speichern, dann GreenWallGuildRosterDB.zoneExport in deiner SavedVariables/GreenWallGuildRoster.lua suchen und rüberschicken.'

    L['Broadcast sent.'] = 'Broadcast gesendet.'
    L['GreenWallAPI=%s, own tag=%s'] = 'GreenWallAPI=%s, eigenes Tag=%s'
    L['Known confederation tags: %s'] = 'Bekannte Konföderations-Tags: %s'
    L['Addon message debug=%s'] = 'Addon-Message-Debug=%s'
    L['Minimap button %s.'] = 'Minimap-Button %s.'
    L['hidden'] = 'ausgeblendet'
    L['shown'] = 'eingeblendet'
    L['Main link removed for this character.'] = 'Alt-Verknüpfung für diesen Charakter entfernt.'
    L["You can't set yourself as your own main."] = 'Du kannst dich nicht selbst als eigenes Main setzen.'
    L['%s is now marked as an alt of %s.'] = '%s ist jetzt als Alt von %s markiert.'
    L['GreenWall is not installed or not enabled - this addon needs it (get "GreenWall" from CurseForge) to bridge with your co-guilds.'] = 'GreenWall ist nicht installiert oder nicht aktiviert - dieses Addon braucht es ("GreenWall" von CurseForge), um mit euren Co-Gilden zu verbinden.'
end
