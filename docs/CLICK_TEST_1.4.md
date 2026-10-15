# 1.4.0 — optional input-path tests

Version 1.4.0 includes opt-in experimental input paths. Their hardware permission
still requires live verification; they are disabled again after login/reload.

## Sync button

- `/gwgr syncbutton on` shows it; `off` hides it. There is also an AddOns Options checkbox.
- Left-click sends at most one prepared frame; right-drag moves the button even while sending is unavailable. Position is
  saved per character; clicking raises it like a normal window.
- Remaining clicks exclude an already submitted frame awaiting its echo. The
  last frame can therefore show zero further clicks while still awaiting
  confirmation. Retries can increase the count. Only the final matching echo
  completes the transaction; it is not a delivery acknowledgement from every peer.
- The button pauses while waiting for an echo, during combat, when disabled or
  when no transaction is available. The label shows capability/channel waits.
- `/gwgr syncrestart` discards current work and prepares a fresh snapshot for
  testing without sending. Use it to avoid the normal ten-minute cooldown.
- Every configured remote guild still needs a present TX1-capable client.
  Transactions still expire 120 seconds after preparation and have size limits.

## Extra input sources

1. Disable the old standalone GreenWallHardwareProbe addon if still enabled.
2. `/gwgr passthrough on`, `/gwgr syncbutton on`, `/gwgr syncrestart`.
3. Check `/gwgr status`: a transaction must be queued before testing an input.
4. `/gwgr clicktest action`: test an ordinary mouse click on a populated standard
   Blizzard action button outside combat. Also record whether an action keybind
   invokes that button's PostClick on your client. Custom action-bar addons and
   macro-generated clicks are not validated input paths.
5. `/gwgr clicktest world`: test left/right/middle/extra mouse-button releases
   over the 3D world. This hooks WorldFrame only, not arbitrary UI windows.
   Confirm targeting, camera movement and mouse-look continue normally.
6. `/gwgr clicktest all` enables both; `off` disables both. This does not disable
   normal chat or the explicit sync button. Tests reset to off after reload.
7. `/gwgr clicktest status` reports hooked objects and submitted/echoed/failed
   counts per source, plus observed eligible callbacks (`observed`). A submission without an echo is NOT success. Inspect
   BugGrabber for protected-action errors even when failed=0 (pcall success
   does not establish hardware permission). Capture `/gwgr status` too.
8. Verify no sends during combat or from idle timers, no more than one frame
   for overlapping callbacks, and complete remote roster arrival after the
   final confirmation. Repeat with channel loss and reload mid-transaction.

Hooks only observe existing scripts; they do not replace secure action
attributes, capture keyboard input globally or cover the screen with an
input-intercepting frame. They submit synchronously and use a shared 200 ms
submission gap. Action tests use the release-side PostClick callback; some
client/button combinations might only expose a different path. A zero hook
count or no counter change should be recorded, not treated as proof of success.
On a caught send error or a protected-action error attributed to GreenWall or
GuildRoster, the extra input sources stop for the session until explicitly rearmed.

The [Blizzard action-button source](https://github.com/Gethe/wow-ui-source/blob/classic_era/Interface/AddOns/Blizzard_ActionBar/Shared/ActionButton.lua)
is the reference for action callback behavior. It cannot establish that a
third-party protected send is permitted; this build exists to test that live.

## Verification

Run `lua tests/run_tests.lua`, every `tests/*_test.lua`, and the runtime suite
with `--namespaced` and `--mixed`. Parse runtime Lua with `luac -p`.
Mocks validate queue/display behavior, not live protected-action permission.
