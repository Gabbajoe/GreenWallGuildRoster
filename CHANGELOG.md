# Changelog

## 1.0.1

**Sync**
- Manual broadcast now rides GreenWall's own confederation channel via its public `GreenWallAPI` instead of a self-managed channel/password - no `GWGRoster:` guild-info directive needed anymore, just GreenWall itself configured. Added as a hard TOC dependency, with a chat warning if it's missing/disabled.
- New automatic first-contact discovery: periodically checks each co-guild via a guild-filtered `/who`, pings any newly-seen name once, and only exchanges full roster data with names that actually reply (i.e. also run this addon) - no more needing someone to click Broadcast before the automatic sync has anyone to talk to.
- Whisper sync now picks targets from a rotating random pool sized to a per-cycle message budget, instead of a fixed count always hitting the same few names.
- A confederation member who actually leaves their guild (kick, quit, character deletion) is now explicitly removed from everyone's cached roster instead of sitting there stale forever - debounced across two consecutive scans so a momentary roster-fetch glitch can't wipe out a whole guild's entries.
- Auto-sync interval shortened from 5 minutes to 2.

**Roster window**
- Guild Master / Officer rank badges next to names, matching the native guild frame.
- Zebra row striping, full-row hover highlight, and a header divider, closer to the native guild frame's look.
- Fixed a row-height rounding bug that made rows drift progressively out of alignment with their background further down a long list.
- "Copy Name" added to the right-click menu, alongside Whisper/Invite.
- Native Options > AddOns panel and `/gwgr minimap` to toggle the minimap button.

**Zone translation**
- Zone name table rebuilt from two real in-game `/gwgr exportzones` exports (English + German) matched by WoW's own internal map ID, replacing the old wiki-researched version. Fixes several names that were simply wrong, including all four capital cities, which turn out not to be translated in-game at all.
- Dungeon/instance names (not covered by the zone export) are now collected automatically in the background whenever you zone into one.
- `TRANSLATING.md` added for anyone who wants to contribute a translation for another language.

**Localization**
- English/German UI text, auto-detected from your client's language (`GetLocale()`).

## 1.0.0

Initial release.
