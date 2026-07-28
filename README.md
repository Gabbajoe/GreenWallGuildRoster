# GreenWall GuildRoster

A companion addon for [GreenWall](https://github.com/AIE-Guild/GreenWall) that shows a combined roster window for all co-guilds in a GreenWall confederation — like the native guild roster, but with everyone's alt guilds mixed into one list.

![icon](icon.png)

## What it does

GreenWall bridges guild chat between co-guilds, but each guild's roster is still only visible to its own members. This addon adds a second, independent channel just for roster data: every member with the addon periodically shares their own guild's roster (name, level, class, zone, online status), and everyone else's addon merges that into one combined window.

- Native-style roster window: Level, Class icon, Name, Zone, Guild, Status
- All co-guilds mixed together, sortable by any column (click the header, click again to reverse)
- Guild column color-codes your own guild vs. the other co-guild(s)
- "Show offline" toggle
- Right-click a name to whisper or invite
- Minimap button (drag to reposition, left-click toggles the window, right-click broadcasts)
- Tracks and displays how long ago you last broadcast your own roster

## Requirements

- [GreenWall](https://www.curseforge.com/wow/addons/greenwall) already set up and working between your co-guilds
- One additional line in the **Guild Information** page of **every** co-guild, in addition to GreenWall's own `GWc`/`GWp` lines:

  ```
  GWGRoster:SomeUniqueChannelName:SomePassword
  ```

  Pick a channel name that isn't likely to collide with anything else on your realm, and make sure it's **identical** in every co-guild's guild info. This must be a different channel than GreenWall's own `GWc` bridge channel — sharing it trips GreenWall's own message-corruption detection.

  You don't need to create the channel yourself. Custom chat channels in WoW are realm-wide and first-come-first-served: whoever's addon joins it first automatically creates it with the name/password you configured, and everyone else's addon just joins the existing one. If the name you picked happens to already be in use by something unrelated, you'll get stuck on a password prompt — if that happens, just pick a more unique name and try again.

## Installation

1. Copy the `GreenWallGuildRoster` folder into your `Interface/AddOns/` directory.
2. Add the `GWGRoster:` line above to the Guild Information page of every co-guild.
3. `/reload`.

## Usage

- `/gwgr` — open/close the roster window
- `/gwgr broadcast` — send your guild's current roster to the other co-guilds
- `/gwgr status` — show the current channel/tag your addon is using

Broadcasting only happens when you explicitly ask for it (button, minimap right-click, or the slash command) — there is no automatic background sending. This isn't a corner we cut; recent WoW client builds treat `SendChatMessage` as a protected function that can only be called from a direct user action, specifically to prevent addons from silently automating chat. Click **Broadcast** (or right-click the minimap button) every so often so the other guild sees a reasonably fresh roster. The window shows how long ago your last broadcast was as a reminder.

## How it works

Each client reads its own guild's full roster (including offline members, which is normally only visible within your own guild) and sends it, chunked to fit chat message limits, as hidden (not shown in any chat window) messages on the shared `GWGRoster` channel. Every other client listening on that channel merges what it receives into a SavedVariables cache, so peer-guild members show up even when nobody from that guild is currently online — the data is just as fresh as the last broadcast.

**Relationship to GreenWall's code:** the channel-join and broadcast/receive logic here is a from-scratch implementation, not code reused from GreenWall. The only thing this addon reads from GreenWall's setup is the `GWp:guildname:tag` lines already present in your Guild Information page, purely to map a tag back to a guild name for display — that's read-only and doesn't touch any of GreenWall's own Lua state. Everything else (joining its own channel, chunking, sending, parsing incoming messages) is independent, specifically so this addon keeps working even if GreenWall's internals change.

## Known limitations

- Roster data for the other co-guild(s) is only as fresh as the last time someone there broadcasted.
- Very large guilds mean a lot of chunked messages per broadcast; there's no batching/throttling beyond keeping each message under the chat length limit.
- Built and tested against Classic Era (Interface 11509).

## License

MIT, see [LICENSE](LICENSE). The icon is AI-generated artwork made for this project.
