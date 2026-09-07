# GreenWallGuildRoster 1.2.0 phase-1 release checklist

Status: release authorized by Nils on 2026-09-07; publication initiated via tag

Nils confirmed that the addon loads and the displayed zones are correct, then
explicitly requested the commit and release. The individual multiplayer and
synthetic in-game checks below have not been separately confirmed and remain
open; release authorization does not imply they were performed.

## Build

- [x] TOC version is `1.2.0`.
- [x] Public changelog starts with `1.2.0` release notes.
- [x] `Core/TransactionProtocol.lua` loads before `Core/Core.lua`.
- [x] Phase 2 automatic pass-through sending remains disabled.
- [x] Legacy manual broadcast, whisper sync and local guild fan-out remain.

## Automated verification

- [x] Pure Lua suite passes.
- [x] Every runtime Lua file passes `luac -p`.
- [x] `git diff --check` passes.
- [x] Incomplete, out-of-order, duplicate, conflicting, expired and oversized
  transaction cases are covered by tests.

## In-game phase-1 acceptance

- [x] Nils confirmed loading and correct zone display on 2026-09-07.
- [ ] `/reload` and login produce no Lua or protected-action error.
- [ ] `/gwgr status` shows transaction counters and phase-1 send-disabled state.
- [ ] Manual Broadcast still updates an older client.
- [ ] An older sender still updates the 1.2.0 receiver.
- [ ] Presence-confirmed whisper sync still converges in both directions.
- [ ] Local `GUILD` fan-out still updates another 1.2.0 client.
- [ ] Reload discards staged transactions without changing cached peer rows.
- [ ] A synthetic incomplete transaction changes no visible roster data.
- [ ] A complete out-of-order transaction commits once.
- [ ] BugGrabber reports zero attributable `ADDON_ACTION_BLOCKED` errors.

## Release

- [ ] Record tester, characters, old/new peer versions and results.
- [ ] Commit the reviewed 1.2.0 phase-1 changes.
- [ ] Create and push tag `v1.2.0`.
- [ ] Confirm GitHub, CurseForge and Wago packages contain the transaction module.
- [ ] Observe adoption and fallback use for approximately two weeks before the
  phase-2 go/no-go decision.
