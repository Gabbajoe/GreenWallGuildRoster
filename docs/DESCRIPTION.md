# GreenWall GuildRoster

A companion addon for **GreenWall** that shows a combined roster window for all co-guilds in your confederation — like the native guild roster, but with every alt guild's members mixed into one list.

![GreenWall GuildRoster](https://raw.githubusercontent.com/Gabbajoe/GreenWallGuildRoster/main/docs/project-icon.png)

## Why

GreenWall bridges your guild *chat*, but each co-guild's roster still only shows its own members. If your confederation is split across multiple guilds for the member cap, you have no easy way to see who's online, what level/class they are, or find someone across the whole confederation. This addon fixes that.

## Features

- **Native-style roster window** — Level, Class icon, Name, Zone, Guild, Status, Alt, just like the built-in guild frame
- **All co-guilds mixed into one sortable list** — click any column header to sort, click again to reverse
- **Guild column** color-codes your own guild vs. the other co-guild(s) at a glance
- **Guild Master / Officer crowns** next to names, same as the native frame
- **Show/hide offline members** toggle
- **Right-click a name** to whisper, invite, or copy their name — even across guilds
- **Self-declared alt links** (`/gwgr setmain <name>`) so a twink in another co-guild shows as "Alt of X"
- **Minimap button** — drag to reposition, left-click opens the window, right-click sends a broadcast
- Tracks and shows how long ago you last shared your roster, so you know when it's getting stale
- Zone names are translated for the reader's own client language, not the sender's
- **Traffic-aware background sync** — own-guild targets are excluded, duplicate transfers are suppressed, and all automatic chunks are paced through ChatThrottleLib
- **Update reminder** learned from other GuildRoster clients, without web requests or an automatic downloader

## Setup

1. Have GreenWall (v1.12+) already set up and working between your co-guilds.
2. That's it — `/reload`. No extra channel or password to configure; this addon rides GreenWall's own confederation channel via its public `GreenWallAPI`.

## Usage

- `/gwgr` — open/close the roster window
- `/gwgr broadcast` — share a fresh online-roster snapshot with the other co-guilds and establish first contact
- `/gwgr setmain <name>` — mark the character you're on as an alt of `<name>`
- `/gwgr status` — check GreenWallAPI, peer, queue, transfer, failure, fan-out, and suppression state
- `/gwgr minimap` — show or hide the minimap button
- `/gwgr passthrough on|off` — enable or disable optional chat pass-through
- `/gwgr debug` — toggle addon-message logging for troubleshooting

Version 1.3.0 can share roster transactions while you type ordinary chat: each
eligible Enter sends at most one queued frame, after your own message. This
option defaults on and requires a currently present, transaction-capable
GuildRoster client in each co-guild. The snapshot is confirmed only when all
frames have been echoed. Manual Broadcast (button, minimap right-click, or
`/gwgr broadcast`) remains available for immediate sharing and older peers.
Presence-confirmed background whisper sync continues independently.

## How it works

Two transports: a manual one over GreenWall's own confederation channel for first contact (a snapshot of members currently reported online), and a presence-confirmed background exchange between reachable GuildRoster clients for ongoing updates. Own-guild players are never treated as cross-guild whisper targets. HELLO messages are paced, one successful exchange is shared locally, fresh peer-guild data suppresses redundant acknowledgements, and duplicate fan-outs are discarded. See the [README](https://github.com/Gabbajoe/GreenWallGuildRoster) for the full technical breakdown.

## Current limitation

Remote snapshots contain up to 200 members currently reported online. Previously known members remain visible when they later go offline, but the addon cannot export every remote character that has never been observed online.

## Contributing a translation

Play on a language other than English/German and want zone names translated correctly? See [TRANSLATING.md](https://github.com/Gabbajoe/GreenWallGuildRoster/blob/main/docs/TRANSLATING.md) - a two-minute in-game export for outdoor zones, plus automatic background collection of dungeon names as you play. No research needed either way.

## Source

https://github.com/Gabbajoe/GreenWallGuildRoster
