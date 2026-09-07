# GreenWall GuildRoster

[![Release](https://github.com/Gabbajoe/GreenWallGuildRoster/actions/workflows/release.yml/badge.svg)](https://github.com/Gabbajoe/GreenWallGuildRoster/actions/workflows/release.yml)
[![Latest Release](https://img.shields.io/github/v/release/Gabbajoe/GreenWallGuildRoster)](https://github.com/Gabbajoe/GreenWallGuildRoster/releases/latest)
[![License: MIT](https://img.shields.io/github/license/Gabbajoe/GreenWallGuildRoster)](LICENSE)

A companion addon for [GreenWall](https://github.com/AIE-Guild/GreenWall) that shows a combined roster window for all co-guilds in a GreenWall confederation — like the native guild roster, but with everyone's alt guilds mixed into one list.

<p align="center">
  <img src="docs/project-icon.png" alt="GreenWall GuildRoster crest" width="320">
</p>

## What it does

GreenWall bridges guild chat between co-guilds, but each guild's roster is still only visible to its own members. This addon rides GreenWall's own confederation channel (via its public `GreenWallAPI`) and uses a presence-confirmed whisper exchange for roster data: it merges each participating guild's roster (name, level, class, zone, online status, rank) into one combined window.

- Native-style roster window: Level, Class icon, Name, Zone, Guild, Status, Alt
- All co-guilds mixed together, sortable by any column (click the header, click again to reverse)
- Guild column color-codes your own guild vs. the other co-guild(s)
- Guild Master / Officer crowns next to names, same as the native frame
- "Show offline" toggle
- Right-click a name to whisper, invite, or copy their name
- Minimap button (drag to reposition, left-click toggles the window, right-click broadcasts) - can be hidden via Options > AddOns > GreenWall GuildRoster or `/gwgr minimap`
- Tracks and displays how long ago you last broadcast your own roster
- Self-declared cross-guild alt links (`/gwgr setmain <name>`) show under Alt for a twink in another co-guild
- Presence-confirmed, paced background sync without `/who` discovery or stale cache-based whisper targets
- Shared freshness leases and payload deduplication prevent every local client from repeating the same cross-guild transfer
- Automatic update notification learned from other GuildRoster clients; no web request or background downloader
- A departed co-guild member (kicked, left, character deleted) gets explicitly cleared out instead of lingering as a stale entry forever
- Atomic transaction receiving prepared for the optional safe-chat transport: incomplete or malformed multi-frame snapshots never alter the visible roster
- English/German UI, auto-detected from your client language - see [TRANSLATING.md](docs/TRANSLATING.md) to help add another

## Requirements

- [GreenWall](https://www.curseforge.com/wow/addons/greenwall) (v1.12+) already set up and working between your co-guilds. It's a hard dependency, not optional - this addon uses GreenWall's own `GreenWallAPI` to ride its already-established confederation channel, so there's no extra channel/password to configure. The "GreenWall - Revived" fork's changes were merged back into the official GreenWall as of v1.12.0, so there's no longer a reason to use the fork specifically.

## Installation

1. Copy the `GreenWallGuildRoster` folder into your `Interface/AddOns/` directory.
2. `/reload`. No guild-info configuration needed beyond GreenWall's own setup.

## Usage

- `/gwgr` — open/close the roster window
- `/gwgr broadcast` — send your guild's current roster to the other co-guilds (via GreenWall's confederation channel, manual)
- `/gwgr status` — show GreenWallAPI availability and your own tag
- `/gwgr setmain <name>` — mark the character you're on as an alt of `<name>` (run this on the twink); leave the name off to clear it
- `/gwgr minimap` — show or hide the minimap button
- `/gwgr debug` — toggle explicit addon-message logging for troubleshooting

## How it works

There are two transports, because Classic's client restricts what's available for each:

1. **Manual channel broadcast** (`Broadcast`): each client reads a full snapshot of its guild members currently reported online and sends it, chunked to fit message limits, via `GreenWallAPI.SendMessage` - GreenWall's own third-party API, which rides its already-joined confederation channel framed distinctly from GreenWall's own chat/notice/bridge traffic. This only ever runs from a direct click (button, minimap right-click, or `/gwgr broadcast`) — under the hood it still ends up at `SendChatMessage`, a protected function in this client build that gets silently blocked if called from a timer or event handler. This is how you make first contact with the other co-guild(s).
2. **Presence-confirmed whisper sync**: GuildRoster reads the members currently present in GreenWall's normal guild bridge after login and observes later joins/leaves. Own-guild members are excluded because their roster is already available locally. It sends a small HELLO through a paced queue; only a client that answers is eligible for a full roster exchange. Each client releases at most one HELLO every 30 seconds and retries only clients that are still present after a cooldown. One confirmed exchange is fanned out at `BULK` priority to other GuildRoster users in that sender's own guild. That fan-out establishes a short shared freshness lease, so other local clients suppress redundant acknowledgements for the same peer guild. `/who` is not used at all: it neither discovers targets nor creates roster rows.

Version 1.2.0 is phase 1 of the safe pass-through rollout. It can receive a
bounded `BEGIN`/`DATA`/`COMMIT` transaction atomically and advertises that
capability, but it does not automatically send one. Manual Broadcast retains
the established legacy format and remains compatible with older clients. See
the [two-phase plan](docs/HARDWARE_EVENT_PASSTHROUGH_PLAN.md).

So: click Broadcast once to introduce your guild to the other co-guild(s). After that, clients that appear on the GreenWall bridge can exchange a roster only after confirming that GuildRoster is present and reachable. The window shows how long ago your last manual broadcast was as a useful freshness indicator.

### Keeping whisper traffic small

- Members of your own guild are never queued as cross-guild whisper targets.
- HELLO attempts are paced to at most one target per 30-second service pass.
- A confirmed exchange is shared locally at `BULK` priority, giving every
  GuildRoster client in that guild the same fresh data.
- A ten-minute peer-guild freshness lease suppresses redundant ACKs and the
  full roster transfers they would trigger.
- Identical local fan-out payloads are deduplicated during bursts.
- Full roster chunks are chained through ChatThrottleLib and stop immediately
  after the first failed delivery.

The 1.1 development long-session test recorded 200 suppressed ACKs versus only
five ACKs sent, a normally empty queue, and zero send failures. See the
[full evaluation](docs/LONG_SESSION_EVALUATION_1.1.0-dev.1.md).

**Relationship to GreenWall's code:** the broadcast/receive logic here is a from-scratch implementation on top of GreenWall's public `GreenWallAPI`, not code reused from GreenWall's internals. This addon also reads the `GWp:guildname:tag` lines already present in your Guild Information page, purely to map a tag back to a guild name for display — that's read-only and doesn't touch any of GreenWall's own Lua state.

## Known limitations

- Initial discovery still needs one user-triggered broadcast. After first contact, freshness depends on at least one reachable, current GuildRoster client in the source guild.
- Remote full snapshots contain up to 200 members currently reported online. An offline remote row is retained after a previously known online member goes offline; this is not a complete export of every never-seen offline character in that guild.
- A manual channel broadcast is synchronous and user-triggered. Automatic whisper and local-guild synchronization use ChatThrottleLib pacing.
- Safe chat pass-through sending is deliberately disabled in 1.2.0 phase 1.
- Built and tested against Classic Era (Interface 11509).

## License

MIT, see [LICENSE](LICENSE). The icon is AI-generated artwork made for this project.

## Contributing a translation

Play on a non-English/German client and want zone names translated correctly for your language? See [TRANSLATING.md](docs/TRANSLATING.md) - a two-minute in-game export for outdoor zones/cities/battlegrounds, plus automatic background collection of dungeon/instance names as you play. No research needed either way.
