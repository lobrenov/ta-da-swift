# Versioning

The Ta Da app (Mac and iPhone) is versioned `x.y.z (n)`. The Obsidian plugin is versioned `x.y.z`.

## Version x.y.z
- `x`: major version, bumped by decision. `y` and `z` reset to 0.
- `y`: feature, bumped when a build plan is completed (moved to `docs/archive/build plans/`) or by decision. `z` resets to 0.
- `z`: increment: a build plan stage, a logical group of commits, or a fix.

## Build n (app only)
- Goes up by one when a build from a changed codebase goes out (a beta DMG or an install on a device). Building the same code again, on any Mac, keeps its number. Runs from Xcode during development don't count.
- Never resets, independent of the version. A new version always goes out with a new build.
- The Mac and iPhone apps share the version and build (one target).

## Where they're set
- App: TaDa target › General › Identity › Version and Build (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`). The test targets stay at 1.0 (1).
- Plugin: `version` in `manifest.json` and `package.json`, plus a `versions.json` entry (plugin version → Obsidian `minAppVersion`).

## Tags
Each new version is tagged `v<x.y.z>`, in its own repo, on the commit that sets it. A version's builds are the build numbers between its tag and the next.

## Plugin pairing
Each plugin version is paired with the Ta Da version whose TaDaCore it ports, meaning the version whose conformance fixtures its tests pass. A TaDaCore or file format change in Ta Da is ported to the plugin, and the plugin version that ships it is paired with that Ta Da version.

| Plugin | Ta Da |
|---|---|
| 0.1.0 | 0.33.0 |
| 0.1.1 | 0.33.0 |
| 0.2.0 | 0.34.0 |
| 0.2.1 | 0.34.1 |
| 0.3.0 | 0.34.10 |
| 0.3.1 | 0.34.12 |
| 0.3.2 | 0.34.15 |
| 0.3.3 | 0.35.1 |
| 0.3.4 | 0.35.2 |
| 0.4.0 | 0.36.0 |
| 0.4.1 | 0.36.0 |
| 0.4.2 | 0.36.3 |
