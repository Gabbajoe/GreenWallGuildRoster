# GreenWallGuildRoster 1.1.0-dev.2 smoke test

## Environment

- Date: 2026-08-23
- Realm: Soulseeker
- Local guild: Milchbar
- Partner guild: Saftladen
- Build: `1.1.0-dev.2`

## Confirmed live

- [x] Addon loads without a Lua error.
- [x] `/gwgr status` works after removal of long-term monitoring.
- [x] No GuildRoster long-term monitor starts at login.
- [x] Combined roster window opens and is populated from Milchbar and Saftladen.
- [x] Guild counts, class icons, names, zones, guild colors, status and crowns render correctly.
- [x] Minimap shield is recognizable inside Blizzard's tracking border.
- [x] Hover highlight follows the transparent shield without square artifacts.
- [x] Tooltip shows left-click, right-click and last-broadcast information.
- [x] Left-click opens/closes the roster window.
- [x] Broadcast succeeds and updates the last-broadcast timestamp.
- [x] Live status reports zero send failures and an empty queue.
- [x] Freshness suppression increases while redundant HELLO acknowledgements arrive.

## Observed status

```text
GreenWallGuildRoster: GreenWallAPI=true, own tag=M
GreenWallGuildRoster: Known confederation tags: S, M
GreenWallGuildRoster: Sync presence=1 local=1 remote=0 queue=0 hello=0 ack=1 suppressed=3
GreenWallGuildRoster: Sync full=0 chunks=0 failed=0 guild-fanout=5 duplicate-fanout=0
```

Result: **PASS**
