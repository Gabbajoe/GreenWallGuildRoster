# Repository and release layout

## Runtime files shipped in addon releases

- `GreenWallGuildRoster.toc`
- `Assets/` — compact minimap artwork and the addon-list icon
- `Core/` — synchronization, data normalization, zone data, diagnostics
- `Localization/` — localized UI strings
- `UI/` — roster window and minimap button
- `Libs/` — embedded runtime dependencies
- `LICENSE` — retained through `.pkgmeta`'s `license-output`

The TOC is the authoritative load order. Moving a runtime Lua file therefore
requires updating `GreenWallGuildRoster.toc` in the same change.

## Repository-only files excluded from releases

- `.github/`
- `docs/`
- `tests/`
- `.gitignore`
- `README.md`
- `CHANGELOG.md`
- the generated `CHANGELOG-release.md`

`CHANGELOG-release.md` is generated temporarily by the release workflow. The
packager reads its first release section as release notes, but `.pkgmeta`
prevents the temporary file itself from entering the addon archive.

## Release checks

For every tag and manual workflow run, CI:

1. checks the syntax of all runtime Lua files;
2. runs the dependency-free Lua tests;
3. invokes the BigWigs packager for GitHub, CurseForge, and Wago.
