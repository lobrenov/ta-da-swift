# Ta Da — Vault structure plan

## Context
Ta Da shares a folder with Obsidian. Today it creates `tasks/`, `projects/`, `areas/`, `attachments/` and `.logbook/` at the folder's top level. This plan moves everything Ta Da creates into one folder, `Ta Da/`, and offers once to move an existing vault into it. Brief: the vault task `tasks/Vault data structure.md`.

Starting point, as checked on 2026-10-19:
- The scan already covers the whole folder; a typed file is found wherever it sits (`Vault.modificationDates`).
- The folders are constants: `Vault.taskFolder`, `projectFolder`, `areaFolder` (`Storage/Vault.swift`), `attachmentFolder` (`Storage/Attachments.swift`), `logbookFolder` (`Storage/Logbook.swift`), `trashFolder` (`Storage/Trash.swift`). App code uses the constants.
- `Item.reservedFolders` hides the top-level `tasks/`, `projects/`, `areas/` and `attachments/` from notes and the Notes tree (`Item.isNotePath`, `Vault.emptyFolders`).
- `.logbook/` is hidden, so Obsidian can't see logged files or resolve links to them. The scan reads it with its own enumerator (iCloud Drive's hidden-folder workaround).
- Embeds resolve to the target as a path, then `attachments/<filename>`, then the first file with that filename.

## Decisions
- **Ta Da's folder** is `Ta Da/` at the top level, fixed (not a setting).
- **Layout**: `Ta Da/tasks/`, `Ta Da/projects/`, `Ta Da/areas/`, `Ta Da/attachments/`, `Ta Da/Logbook/<yyyy-MM>/`. Files stay flat in each; there are no per-parent subfolders.
- **Trash** stays `.trash/` at the top level, shared with Obsidian.
- **Daily and weekly notes** keep the folders set in Settings.
- **Scanning** is unchanged: the whole folder. Files outside `Ta Da/` are read and edited in place; only creating, converting, restoring, logging and un-logging put files in `Ta Da/`.
- **Notes**: the top-level `Ta Da/` is reserved like the old folders: untyped files in it aren't notes, and the Notes tree leaves it out. The old top-level folders stay reserved.
- **Old layout**: logged files in `.logbook/` stay logged, and embeds still resolve to `attachments/<filename>` after `Ta Da/attachments/<filename>`, so a vault that isn't moved keeps working.
- **Moving an existing vault**: when a folder with the old layout opens, Ta Da asks once whether to move its files into `Ta Da/`. Either answer is kept for that folder on that device; after Not Now new files still go to `Ta Da/`, and Settings ▸ Vault offers the move again.
- **Tags**: unchanged.

## Stages
The stages run in order on `main`. Each stage: build → commit → swift-expert review (up to 5 fixes) → fix → commit. TaDaCore checks run on macOS; the app builds for macOS and the iOS Simulator.

### S1 — New paths
- `Vault.home = "Ta Da"`. The task, project, area, attachment and logbook folders become `Ta Da/tasks`, `Ta Da/projects`, `Ta Da/areas`, `Ta Da/attachments` and `Ta Da/Logbook`. `Vault.legacyLogbookFolder = ".logbook"`.
- `Item.isLogged` is true in `Ta Da/Logbook/` and `.logbook/`.
- `Item.reservedFolders` adds `ta da` beside the old four; `isNotePath` and `emptyFolders` use it.
- `Vault.path(of:)`, `modificationDates()` and `placeholderPaths()` keep reading `.logbook/`; the visible Logbook needs nothing special.
- `attachmentPath(for:in:)`: the target as a path, then `Ta Da/attachments/<filename>`, then `attachments/<filename>`, then the first by path.
- App copy that names a folder (Logbook header and empty state, Trash's "from …/", iPhone Logbook subtitle) follows the constants.
- Check: core tests updated for the new paths; new tests read a vault mixing both layouts (logged files in both Logbooks, an embed found in each attachments folder, untyped files in `Ta Da/` aren't notes). App tests pass; the DesignVault fixture is untouched.

### S2 — Moving an existing vault (core)
- `Vault.legacyFolders()`: the top-level `tasks/`, `projects/`, `areas/`, `attachments/` (any case) and `.logbook/` that hold a file, iCloud Drive placeholders included.
- `Vault.moveIntoHome(index:)` moves each into its `Ta Da/` folder: the whole folder when the destination doesn't exist, else file by file, numbering names that are taken. Then:
  - body links written with an old path (`[[tasks/X]]`, `[[.logbook/2026-10/X]]`) and embeds written with one (`![[attachments/front.jpg]]`) point at the new path;
  - a numbered file's links by title follow its new title where the old title found it, and a numbered image's embeds by filename follow its new filename;
  - files that are already gone (another device moved them) are skipped, and old folders left with no files are removed.
  - Returns each moved file's new path by its old one, with the files relinked and those that couldn't be.
- Check: `MoveIntoHomeTests`: a full move; a move into a partly filled `Ta Da/` with numbering; path links and embeds rewritten; title links follow a numbered file; a second run finds nothing; a missing file is skipped.

### S3 — Asking once (Mac and iPhone)
- `AppModel.oldLayoutFolders`, worked out when the folder opens and after each refresh.
- `AppModel.offersMove`: true when the old layout holds files and the question wasn't answered for this folder on this device (`Keys.moveDeclined`, by folder path like `lastLogged`), and not while logging, moving or showing an error.
- An alert on the Mac's and iPhone's `ContentView` (`moveIntoHomeAlert`), "Move Ta Da's files into “Ta Da”?", with the folders it found, Move and Not Now.
- `moveIntoHome()` saves the open file, runs the core move, follows moved paths (the open file stays open), refreshes, and shows a failure as an error.
- Settings ▸ Vault (Mac and iPhone): Move into “Ta Da” while `oldLayoutFolders` isn't empty.
- UI-test and render folders don't prompt: `UITestingLaunch` writes the new layout; `DesignRenderTests` marks the fixture as declined.
- Check: `AppModelTests` for offering, Not Now, moving with an open file, and no offer after the move. App builds for macOS and iOS.

### S4 — Docs and SampleVault
- `docs/file-format.md`: Identity (reserved folders, Location), Notes folders, Attachments, Deleting, Restoring, Logging, Reopening a logged file, Tags counts.
- `docs/architecture.md` and `docs/design/design-framework.md` where they name the folders.
- `SampleVault` moved to the new layout.
- Check: no doc names the old folders except as the old layout.

### S5 — Beta
- Bump Build, `scripts/make-beta-dmg.sh`.
