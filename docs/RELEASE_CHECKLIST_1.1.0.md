# GreenWallGuildRoster 1.1.0 release checklist

## Build

- [x] TOC version is `1.1.0`.
- [x] Public changelog starts with `1.1.0` release notes.
- [x] Development long-term monitoring is absent from the runtime build.
- [x] `/gwgr status` and `/gwgr debug` remain available.
- [x] Old diagnostics samples are removed from SavedVariables on next load.
- [x] Minimap, addon-list, README and project-page icons are present.
- [x] Repository-only documentation, tests and workflows are excluded by `.pkgmeta`.

## Verification

- [x] Lua syntax validation passes for all shipped source files.
- [x] Unit tests pass (`23 passed, 0 failed`).
- [x] Every TOC runtime path exists.
- [x] Long-session performance and synchronization evaluation passed.
- [x] Live dev.2 smoke test passed without a Lua error.
- [x] Combined roster, minimap button, hover highlight and broadcast were confirmed in game.
- [x] `/gwgr status` showed an empty queue and zero send failures.

## Publication

- [ ] Review the final Git diff.
- [ ] Commit the 1.1.0 release.
- [ ] Create and push tag `v1.1.0` (matching the existing release-tag convention).
- [ ] Confirm GitHub, CurseForge and Wago workflow results.
- [ ] Upload `docs/curseforge-project-icon.png` as the CurseForge/Wago project icon where required.
