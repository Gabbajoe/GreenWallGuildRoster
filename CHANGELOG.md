# Changelog

## 1.0.2

**Sync**
- New automatic first-contact discovery: periodically checks each co-guild via a guild-filtered `/who` and sends newly-seen names a full roster snapshot directly - no more needing someone to click Broadcast before the automatic sync has anyone to talk to. Capped per cycle (a handful of new contacts every 30s) for the same flood-safety reason whisper sync targets are capped.
  - Works against any version of this addon, old or new - deliberately not gated behind a "prove you have the addon first" handshake, since that would only work once everyone's updated already. This side does recognize and answer a handshake ping from a future version that sends one, though.
  - `/who`/`SendWho` turned out to be a protected function too (same class of restriction as chat messages) - the actual query now waits for your next mouse click or key press to fire, same technique the installed DeathNotificationLib/Deathlog addons use for the same reason.
- First contact with a co-guild is now immediately reciprocal: whoever receives the first-ever data from a given co-guild replies with their own roster right back, instead of waiting up to 2 minutes for their own next scheduled cycle to notice the new contact.
- Leave-detection (added in 1.0.1) tuned after a real false-positive: raised from 2 to 3 consecutive missing scans before declaring someone gone, and receivers now ignore an implausibly large batch of "left" signals in one payload (more likely a bad read on the sender's end than an actual mass departure) as a second layer of protection.
- Roster window now shows an online-member count per guild.

## 1.0.1

**Sync**
- Manual broadcast now rides GreenWall's own confederation channel via its public `GreenWallAPI` instead of a self-managed channel/password - no `GWGRoster:` guild-info directive needed anymore, just GreenWall itself configured. Added as a hard TOC dependency, with a chat warning if it's missing/disabled.
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
