# Changelog

## 1.0.6

**Sync**
- Whisper-based sync (full roster replies, the periodic broadcast, and `/who` pings) now rides ChatThrottleLib instead of calling the raw API directly, the same library most other installed addons already use for this. Paces outgoing messages to avoid hitting the client's own throttle, and stops sending further chunks to a target the moment one fails instead of only after the fact.

## 1.0.5

**Roster window**
- `/who` discovery (the periodic background scan that finds new addon users in a co-guild) and the roster window's `/who`-only member display are now off by default - opt in via Options > AddOns > GreenWall GuildRoster if you want them.
- Fixed `/who` discovery permanently getting stuck for the rest of the session if a query never received a reply (server rate-limit, connection hiccup) - it now self-heals instead of silently no-oping every cycle from then on.

**Sync**
- Fixed a target that can't actually be reached getting spammed with every remaining chunk of a roster sync anyway, each one producing its own "no player named X" system error - now stops after the first failed chunk instead of sending the rest.

## 1.0.4

**Minimap button**
- Fixed the button not sitting flush against the minimap ring - the fixed pixel radius used for its orbit position didn't match the actual minimap size. Now computed from the minimap's real size instead of a hardcoded constant.
- Fixed the button snapping back to the default angle on every login instead of staying where you last dragged it (same class of SavedVariables-timing bug as an earlier fix to the button's visibility).

**Roster window**
- Fixed `/who`-only members (guild members seen online without the addon) never actually showing up in the window unless "Show data-source column" was also enabled - that checkbox was only ever meant to control the marker column's visibility, not whether those rows appeared at all. If a co-guild has no addon users, this is the only way any of them ever show up.
- `/who`-only entries now age out after 5 minutes instead of staying listed as "Online" forever after being seen once.

## 1.0.3

**Roster window**
- Guild Master / Officer crown badge detection fixed - was missing some ranks entirely (e.g. a guild's 3rd-highest rank with its own native crown). Now based on `GuildControlGetRankFlags`, re-verified against real data from two independently-configured guilds instead of guessing a rank-index cutoff.
- Window now closes on Escape, like every other native WoW window.
- New optional "data source" column (off by default, toggle in Options): marks each row as last confirmed via broadcast, whisper, or seen only via `/who` with no addon on the other end - with a legend next to the Broadcast button. `/who`-only members are now shown in the combined roster at all, not just addon-confirmed ones.
- Each co-guild beyond your own now gets its own distinct color in the Guild column and online-count line, instead of every peer guild sharing one flat blue.
- Status column narrowed and the source-marker legend moved to bottom-right, freeing up window width.

**Sync**
- Outbound `/who` discovery now pings a candidate first instead of immediately sending a full roster - cheaper for the common case of a stranger with no addon, with a 6-second timeout that falls back to a full send if there's no reply (also covers a peer running an older version that doesn't understand a ping).
- Fixed the combined roster flickering between fully-populated and nearly-empty for large/busy co-guilds: the per-cycle whisper-target floor was capable of dropping to a single random target for guilds needing many sync chunks. Full syncs are now also decoupled from the regular broadcast cadence (every ~10 minutes instead of every cycle) so most cycles are cheap deltas that reach closer to the per-cycle target cap.
- Online/offline staleness threshold raised to match the new full-sync cadence, so a continuously-online member no longer flickers to "stale" between full syncs.
- `AutoBroadcast` now fires on a jittered interval (~90-150s, averaging the same ~2 minutes as before) instead of a fixed one, to avoid many clients' cycles lining up around shared events like loading screens.

**Settings**
- All settings, including the peer/roster sync cache, are now stored per-character instead of shared across your whole account.
- Optional Prat-3.0 integration (off by default, toggle in Options): shows co-guild members' level and a guild-colored tag right in the `[Level:Name:Tag]` chat bracket for GreenWall-bridged guild/officer chat, with the realm suffix hidden automatically - matching how Prat already formats real guildmates. See the in-panel description for the one remaining manual step (turning off GreenWall's own `<Tag>` chat prefix via `/gw tag off`, to avoid seeing it twice).

**Zone translation**
- Fixed Wailing Caverns showing up untranslated for English clients viewing a German-client member's zone.

**Localization**
- Filled in remaining untranslated strings: the source-marker legend, both new Options checkboxes, and `/gwgr exportzones`' help text and output (previously English-only regardless of client language).

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
