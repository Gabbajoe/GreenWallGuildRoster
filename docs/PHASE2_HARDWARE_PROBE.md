# Phase 2: live hardware-permission spike

Status: first live guild-chat spike passed on 2026-09-29; broader live matrix pending.

Phase 1 is committed as `6c1f1e4` (1.2.0). Before implementing the internal
chat sender, verify the planned `OnEnterPressed` post-hook on the actual Classic
client. Lua mocks cannot establish protected-action permission.

## Recorded live result — 2026-09-29

Tester: Nils, character Gabbaophant, Classic Era installation. Installed
GreenWall TOC reports `1.12.1+classic-era`; exact client build not recorded.

- 09:15:24: `ready=false`, all counters zero.
- 09:15:28: arming refused while the guild channel was unavailable.
- 09:15:41: `ready=true`, all counters still zero.
- 09:15:47: explicitly armed after channel join.
- 09:15:52: one Enter post-hook submission and matching own echo.
- 09:15:53: ordinary guild message `test` visible in the supplied chat log.
- 09:15:56: `submitted=1 echoed=1 failed=0 pendingEcho=false ready=true`.
- Nils explicitly confirmed no BugGrabber error during this test.

This passes the initial hardware-permission prerequisite for developing the
broker's guild-chat path. Display timestamps alone do not establish the order
of outgoing network calls. Party/say, expiry, unrelated UI/addon activity,
channel loss/recovery, and production message eligibility still need live
coverage. This result does not establish phase-1 multiplayer compatibility or
authorize a production rollout by itself.

## Installation and test

1. Copy `tests/GreenWallHardwareProbe` into WoW's `Interface/AddOns` directory
   as its own addon. Enable it alongside GreenWall. It is excluded from normal
   GuildRoster releases, has no saved state, and sends no roster data.
2. Log in, wait for GreenWall's guild channel to join, and run `/gwprobe status`.
   Expect `ready=true`, `submitted=0`, `echoed=0`, `failed=0`.
3. Run `/gwprobe arm`. That command's Enter must not send a probe.
4. Within 60 seconds, type one ordinary chat message and press Enter. Check
   that the original message arrives unchanged and the probe reports exactly
   one submission followed by a matching own echo.
5. Repeat separately with guild, party (while grouped), and say chat. Record
   client version, GreenWall version, chat type, counters, and BugGrabber errors.
6. Arm again and remain silent or click unrelated UI controls. No probe may
   submit. After 60 seconds, the next Enter must report expiry without sending.
7. Verify `/gwprobe off` cancels the arm; `/reload` resets all counters and arms.
   A channel loss before Enter must disarm without sending.

This diagnostic deliberately tests the **next Enter**, including an empty
Enter or an unrelated slash command. Only use ordinary typed chat for step 4.
It does not yet implement the production broker's eligible-message detection,
queue, capability checks, retries, or roster producer. Status and off commands
disarm it. Each arm permits at most one attempt; it never automatically retries.

## Go/no-go

Proceed to the broker only when real chat reaches its destination unchanged,
the probe receives its matching own echo, and BugGrabber shows no attributable
protected-action errors. A successful `pcall` alone is insufficient evidence.
If the hook loses hardware permission, stop this design and retain the current
manual broadcast and whisper paths.

After passing, implement the bounded chat queue directly in GuildRoster and
connect its capability-gated producer with one frame per chat action and
echo-confirmed snapshot commit. Separately confirm phase-1 multiplayer
compatibility and deployed peer versions before enabling production sending.

Remove or disable the probe addon after testing.
