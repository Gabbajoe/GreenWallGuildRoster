# GreenWall GuildRoster

A companion addon for **GreenWall** that shows a combined roster window for all co-guilds in your confederation — like the native guild roster, but with every alt guild's members mixed into one list.

## Why

GreenWall bridges your guild *chat*, but each co-guild's roster still only shows its own members. If your confederation is split across multiple guilds for the member cap, you have no easy way to see who's online, what level/class they are, or find someone across the whole confederation. This addon fixes that.

## Features

- **Native-style roster window** — Level, Class icon, Name, Zone, Guild, Status, just like the built-in guild frame
- **All co-guilds mixed into one sortable list** — click any column header to sort, click again to reverse
- **Guild column** color-codes your own guild vs. the other co-guild(s) at a glance
- **Show/hide offline members** toggle
- **Right-click a name** to whisper or invite them, even across guilds
- **Minimap button** — drag to reposition, left-click opens the window, right-click sends a broadcast
- Tracks and shows how long ago you last shared your roster, so you know when it's getting stale

## Setup

1. Have GreenWall already set up and working between your co-guilds.
2. Add one line to the **Guild Information** page of *every* co-guild (in addition to GreenWall's own lines):
   ```
   GWGRoster:YourUniqueChannelName:YourPassword
   ```
   Same name/password in every guild. Pick something unique — it's a separate channel from GreenWall's own bridge, created automatically the first time anyone joins it.
3. `/reload`.

## Usage

- `/gwgr` — open/close the roster window
- `/gwgr broadcast` — share your current guild roster with the other co-guilds
- `/gwgr status` — check your channel/connection status

Broadcasting is a manual click (button or `/gwgr broadcast`) rather than automatic — recent WoW clients block addons from silently automating chat messages, so a deliberate click is required. The window shows how long ago you last sent one.

## How it works

Every member with the addon periodically shares their own guild's full roster (including offline members) over a dedicated channel. Everyone else merges what they receive into one combined view, so you can see the whole confederation even when the other guild's members aren't online.

## Source

https://github.com/Gabbajoe/GreenWallGuildRoster
