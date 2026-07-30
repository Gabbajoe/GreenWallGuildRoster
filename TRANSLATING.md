# Contributing a zone-name translation

GreenWall GuildRoster shows everyone's current zone, translated into your own client's language. Right now only English and German are covered - if you play on a different language client and want to help add it (or you're just double-checking German), here's how.

## Why this is needed

The game only ever hands an addon a zone's name as plain, already-translated text - there's no simple "zone ID" available for a guildmate's location the way there is for your own. To translate between languages reliably (instead of guessing from a wiki and getting it wrong), this addon can export every zone name it can find, tagged with WoW's own internal numeric map ID. Two exports from two different language clients, matched up by that shared ID, give a translation table that's guaranteed correct - no research, no guesswork.

## Steps

1. Make sure you're running the latest version of **GreenWall GuildRoster**.
2. Log into any character, type:
   ```
   /gwgr exportzones
   ```
   You'll see a confirmation in chat like "Exported 180 zone names for locale ... into SavedVariables."
3. **`/reload` or fully log out** - this is important, the export only gets written to disk on a reload/logout, not immediately.
4. Find this file (adjust the path for your account/realm):
   ```
   World of Warcraft/_classic_era_/WTF/Account/<YOUR ACCOUNT>/SavedVariables/GreenWallGuildRoster.lua
   ```
   Open it with any text editor (Notepad is fine).
5. Look for the `zoneExport` section near the top - it looks like:
   ```lua
   ["zoneExport"] = {
       ["locale"] = "frFR",
       ["map"] = {
           [12] = "Kalimdor",
           [13] = "Royaumes de l'Est",
           ...
       },
   },
   ```
6. Copy that whole `["zoneExport"] = { ... }` block and send it over (Discord, pastebin, whatever's easiest).

That's it for outdoor zones/cities/battlegrounds - no need to visit every one, the export covers everything the client knows about in one go.

## Dungeons and other instances

Instances (The Deadmines, Scholomance, ...) aren't covered by the export above - Classic Era's client doesn't register them the same way outdoor zones are. Instead, the addon quietly records the dungeon's name (and its own stable numeric ID, same idea as the zone export) into that same `zoneExport` table every time you zone into one. No command needed - if you've run a few dungeons since installing the addon, some may already be in there when you export. Otherwise, just running a dungeon or two before doing the steps above picks up a few more each time.

## Source

https://github.com/Gabbajoe/GreenWallGuildRoster
