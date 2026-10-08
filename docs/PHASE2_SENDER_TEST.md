# Phase-2 sender: GreenWall GuildRoster 1.3.0

Status: implemented and covered by local Lua tests. Nils confirmed successful
in-game testing and requested a regular 1.3.0 release on 2026-10-09.
Individual results for the matrix below were not supplied.
The separate one-frame guild-chat probe passed on 2026-09-29 with an own echo
and no BugGrabber error. This does not substitute for the tests below.

## Setup

1. Install the current `GreenWallGuildRoster` runtime, including its new
   internal sender modules. Keep GreenWall installed. No GuildMap addon or
   separate sender addon is needed.
2. Disable `GreenWallHardwareProbe` for this test so its independent hook cannot
   submit a second diagnostic frame from the same Enter.
3. On other co-guilds, keep at least one present GuildRoster 1.2.0+ client per
   configured remote guild. TX1 capability must be learned this session through
   the existing presence/whisper exchange; saved capabilities do not qualify.
4. The sender option defaults on. `/gwgr passthrough on` or Options > GreenWall
   GuildRoster can restore it if disabled. The command itself must not send.
5. Wait for channel join and discovery, then inspect `/gwgr status`. `hooks` must be positive. GuildRoster should eventually
   report `state=queued frame=1/N`, with zero submissions before typed chat.
   Channel membership is refreshed every 25–35 seconds, including after late
   joins. If `presence=0` persists after that interval, record the status output
   separately from a missing TX1 capability; no remote members were discovered.

## Live checks

- Type an ordinary guild message. Expect one broker submission, one roster
  submission and matching echo. The original text must arrive unchanged.
- Continue typing ordinary messages. Each action submits at most one frame.
  The last-broadcast timestamp must stay unchanged until the final echo and
  successful snapshot commit (`state=complete`). Receiver rows must remain
  unchanged until complete. Finish within the 120-second transaction lifetime.
- Repeat on party (while grouped) and say; these were not covered by the
  original guild-chat probe. Check BugGrabber throughout.
- Empty Enter, `/gwgr status`, macros, addon-originated guild or
  death notifications, timers and unrelated clicks must not drain the queue.
- Leave work queued silently for more than 120 seconds. It must expire/abort
  without sending; later work can be prepared after the bounded cooldown.
- While in combat, queued frames must stay out of GreenWall's deferred send
  queue. After combat, sending resumes only on another eligible typed Enter.
- Disconnect/rejoin the GreenWall guild channel. Submission must pause while
  unavailable, then resume if the transaction and peer capabilities remain
  valid; otherwise the snapshot is aborted and prepared again later.
- Disable with `/gwgr passthrough off`. Pending work must
  not send. `/gwgr broadcast` must still send the established legacy snapshot,
  with the automatic sender disabled. Whisper sync must still converge.
- Reload mid-transaction: queued and staged work is not persisted. A guild
  change or concurrent whisper snapshot commit must invalidate outdated work.
- Test mixed old/new clients: unconfirmed guilds keep `waiting-capability`,
  with legacy manual and presence-confirmed whisper paths still available.

Record the status output, original chat behavior, remote roster results and
any BugGrabber error. Use this matrix for future regression checks; the release confirmation is
recorded above.

## Interpreting status

- `waiting-channel-or-broker`: supported chat hooks are absent, combat
  lockdown is active, or GreenWall has not joined its guild channel. The
  internal queue details appear in `/gwgr status`.
- `broker-absent`: the internal sender module failed to load. Check the
  installed GuildRoster files and BugGrabber; no extra addon is needed.
- `waiting-capability`: at least one configured remote guild lacks a present,
  session-confirmed TX1 representative. Compatibility sync continues.
- `queued` / `waiting-echo`: waiting for typed chat / the matching own echo.
- `complete`: all echoes arrived and the prepared snapshot committed.
- `invalidated`: guild, snapshot revision, peer capability or broker changed.
- `echo-timeout`: two retries of a frame have been exhausted. Retries are only
  submitted on later eligible chat actions; timers never submit.
- `oversized-row` / `snapshot-bounds`: the snapshot cannot fit the conservative
  transaction limits. Nothing is partially sent; manual/whisper remains available.

## Local verification

From `GreenWallGuildRoster`: `lua tests/run_tests.lua`,
`lua tests/pass_through_test.lua`,
`lua tests/pass_through_runtime_test.lua`.
Also run `lua tests/hardware_broker_test.lua` and
`lua tests/hardware_chat_test.lua` from the same GuildRoster directory.
All tests use the bundled queue without a sibling repository or addon.

The chat adapter observes user text and the edit box's `OnPreSendText` method,
then submits only in the `OnEnterPressed` post-hook. Unsupported edit boxes
remain ineligible. The implementation follows the ordering in the
[Blizzard Classic Era UI source](https://github.com/Gethe/wow-ui-source/blob/classic_era/Interface/AddOns/Blizzard_ChatFrameBase/Shared/ChatFrameEditBox.lua).

## Channel roster diagnosis

`channel-roster=ready` means a complete list of names was read. The status line
also reports the GreenWall chat `number`, its display-list `index`, and member
`count`. Number and index are different identifiers and need not match.
`channel-not-listed` means the chat number has no matching active display entry;
`count-pending` means no count was returned; `empty` means a zero count; `names-pending` means its
count is available but at least one member name is still loading.

The mapping follows Blizzard's
[ChannelList](https://github.com/Gethe/wow-ui-source/blob/classic_era/Interface/AddOns/Blizzard_Channels/ChannelList.lua)
and [ChannelRoster](https://github.com/Gethe/wow-ui-source/blob/classic_era/Interface/AddOns/Blizzard_Channels/ChannelRoster.lua)
code: display entries provide the chat number and member count; roster reads
use the display index. When the list is unloaded, GuildRoster selects its entry while the channel
window is closed to trigger acquisition, then re-reads four seconds later.
It restores the prior selection only if the UI remains closed, the selection
has not been changed, and the relevant display entries have not moved.
Requests are limited to one per 30 seconds. `requested` means an acquisition
is in flight; `request-deferred-ui` means the channel window is open.

The manual selection test on 2026-09-29 changed `count=nil` to `count=6`, with
six present members and one HELLO sent. Test automatic acquisition after a fresh
reload without the manual command, and verify that opening/changing the channel
window during acquisition does not cause it to jump to a different selection.
