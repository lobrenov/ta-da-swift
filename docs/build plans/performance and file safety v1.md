# Ta Da — Performance and file safety v1

## Context
Before a broader release: close the paths where Ta Da or the Obsidian plugin can lose, overwrite or duplicate a user's files, and make large vaults (1k–10k files) open and edit without stalls. The findings come from a review of 2026-11-24 on 0.44.1 and plugin 0.8.1.

Baseline (debug, 1,200 generated files, `LargeVaultTests`):
- load index: 1,294 ms
- refresh, nothing changed: 33 ms
- sidebar and lists: 52 ms

Scratch benchmark (release, same files), reading only:
- one coordinated read per file: 1,200 ms
- the same inside one `prepare(forReadingItemsAt:)`: 197 ms
- plain reads: 18 ms

## Decisions
- **Deletes are never recursive.** Ta Da removes a folder only with `rmdir(2)`, which fails when it isn't empty. Everything else goes to `.trash/` (`merge`).
- **Names taken by iCloud placeholders count as taken.** `filenames(in:)` adds the original name of each `.<name>.icloud` entry.
- **Unsaved edits are always kept.** Any path that replaces the open document's text while it's dirty writes an "(unsaved edits)" copy first.
- **Multi-file operations undo their own partial work.** Extracting subtasks removes only the lines whose tasks were created; on failure, it deletes the tasks it created.
- **New files are written atomically.** A temporary file in the same folder, then `renamex_np(…, RENAME_EXCL)`.
- **Settings that don't parse are not overwritten.** Loading uses defaults; writing throws and the app shows the error.
- **Initial load:** one `prepare(forReadingItemsAt:)` around the scan, with the coordinated reads inside it, parsed in parallel (task group, chunks). On macOS, files that aren't downloaded (`ubiquitousItemDownloadingStatusKey` not current) are skipped and requested, as iOS placeholders are, and the watcher adds them as they arrive.
- **Time to content:** `state = .ready` once the index is in. Trash, attachments and folders load after it, in parallel, kept only if no refresh ran meanwhile; the watcher starts after them.
- **Refresh:** the watcher passes the files and folders that changed (FSEvents file events; on iOS, the presenter's URLs). The trash is scanned again only for a change under `.trash/`; folders and attachments only for a change to something that isn't Markdown, or when the Markdown files changed; a path it can't place scans everything. On iOS placeholders are asked for on every pass. App activation, opening the folder and Ta Da's own refreshes scan everything.
- **Derived data is stored, not computed in `body`.** `titles`, `taskStatuses`, `tasks` and `liveItems` are kept by `VaultIndex` and updated by `update`/`remove`. The logbook groups and the Trash view's attachment data are stored on `AppModel`, computed in `updateLists` and `refresh`.
- **Obsidian deletes:**

  | Option | Pros | Cons |
  |---|---|---|
  | a. `vault.trash(file, false)` (as the plugin's `CLAUDE.md` says) | Always `.trash/`, so always recoverable and shown in the Tasks Trash | Ignores the user's "Deleted files" setting; Obsidian's review lint flags it (why `0ac261c` moved to `trashFile`) |
  | b. Keep `fileManager.trashFile` | Follows the user's setting; passes the lint | "Permanently delete" makes Delete area unrecoverable; "System trash" files never show in the Tasks Trash |

  Decided: b.
- **Version:** each Part is the next `z` version of the app (tag `bug` for Parts 1–2, `patch` for 3–4) or a plugin patch version (Parts 2 and 5), paired as `docs/versioning.md` says. Completing the plan is the next free `y` version.
- **Not in v1:** a persisted index cache; FSEvents per-path updates; off-main-actor list queries; virtualised lists in the plugin; async image decoding in the editor fork; the TOC panel, iOS agenda pages and `BodyScanner.isNested` costs; repeated "(unsaved edits)" copies while a conflict is open; log and unlog with a dirty document.

## Part 1 — File safety (app, TaDaCore)
Each step's tests are written first and fail before the fix.

1. **Folder deletes.** `trashFolder` (`Storage/Notes.swift`) removes with `rmdir(2)` and falls back to `merge` when that fails. `merge`'s last removal and `pruneTrash` (`Storage/Trash.swift`) use `rmdir(2)` too. Check: TaDaCore tests: a folder holding only `.gitkeep`, or only `.git/`, ends up in `.trash/` with its contents; a file written into a folder after it was listed survives `merge` and `pruneTrash`.
2. **Placeholders reserve names.** `filenames(in:)` (`Storage/Vault.swift`). Check: tests: with `.Call mum.md.icloud` in a folder, create, rename, move, logging and the daily note pick `Call mum 2.md` (or don't create the daily note).
3. **Use the other version.** `AppModel.adopt` calls `keepUnsavedEdits` first when the document is dirty. Check: a `TaDaTests` test: a dirty document adopting a version leaves an "(unsaved edits)" file with the typed text.
4. **Extract subtasks.** `extractSubtasks` (`Storage/Notes.swift`) removes, inside the coordinated update, only the lines matching created tasks, and deletes the created tasks if one fails. Check: tests: a failure on the third task leaves no task files and every line; a subtask line added between read and update stays.
5. **New files and quitting.** `CoordinatedFileIO.create` writes a temporary file and renames it exclusively. `saveBeforeQuitting` and `enterBackground` await `savingImage`. Save again (`AppModel.swift`, after a removal) uses `create` and a numbered name when the path is taken. Check: tests: `create` on a taken path throws and leaves the file unchanged; Save again with a file back at the path writes `<name> 2.md`.
6. **Settings.** `VaultSettings`: an existing file that doesn't parse loads as defaults and makes `writeSettings` throw. Check: test: a truncated `settings.json` with an unknown key is unchanged after a settings change, and the change reports an error.

Check for the Part: `swift test --package-path Packages/TaDaCore` and `xcodebuild … test -skip-testing:TaDaUITests` pass; `git diff SampleVault` after manual testing shows only intended writes.

## Part 2 — File safety (Obsidian plugin)
In `~/Projects/ta-da-obsidian`.

7. **Deletes.** Keep `trashFile`; the delete modals say when the setting deletes permanently; the Trash view says it lists only `.trash/`; fix `CLAUDE.md`. Check: tests for the modal text per setting; `CLAUDE.md` matches the code.
8. **Convert with extracted subtasks.** `convertTask.ts`: on a failed `createTask`, remove only the lines of tasks already created and show one notice with the count. Check: test: a failure on the third task leaves two tasks and only their lines removed.
9. **Status changes.** `statusActions.ts`: catch per change, carry on, one notice with a count of failures. Check: test: one failing write still applies the others and reports 1.
10. **Byte-order mark.** The fence check on the first line allows a leading U+FEFF, which stays in the frontmatter block, in TaDaCore and the plugin. A file with an unclosed opening fence still gets a new block put in front, keeping its text; refusing the write would leave conversions half done. Check: `npm test` and `swift test … --filter writeConformance` pass; a "byte-order mark" conformance input.

Check for the Part: `npm test` and `npm run build` pass.

## Part 3 — Load and refresh (TaDaCore and `AppModel`)
11. **Initial load.** `loadIndex` as decided (one `prepare`, parallel parse, skip non-downloaded files on macOS). `open()` sets `.ready` after the index; trash, attachments and folders load after it with `async let`. Check: `LargeVaultTests` load index ≤ 300 ms at 1,200 files (from 1,294); a test that a not-downloaded file is left out and requested.
12. **Refresh.** Scope the scans as decided (`Vault.refreshScope(for:)`). Add a refresh timing to `LargeVaultUITimingTests`. Check: a refresh after a save is ≤ 40 ms at 1,200 files; tests: the scope for each kind of path, a file trashed by another app appears in Trash, a new image appears in Attachments.
13. **iOS background refresh.** `refreshBadgeInBackground` uses `changes(since:)` against the index in memory when the folder is open. Check: the iOS build.

## Part 4 — Rendering (app)
14. **Index-derived data.** `titles`, `taskStatuses`, `tasks`, `liveItems` stored in `VaultIndex`; `LiveEditor`'s link fingerprint uses an index generation number. Views that need only "has items" or one item stop reading `model.index`. Check: TaDaCore tests that each stays equal to a full recomputation after update and remove; `LargeVaultTests` "index update, one keystroke" stays ≤ 0.2 ms.
15. **Mac lists.** `TaskSections`, `ProjectGroups`, `LogbookView` and `AttachmentsBrowser` hold each section's rows in a `LazyVStack`, so only visible rows are built and the sections keep their spacing. Check: `LargeVaultUITimingTests` list step doesn't get worse.
16. **Logbook.** Groups built once in `updateLists` by appending in place; `hasFilesToLog` reads them. Check: `TaDaTests` test of the groups unchanged; a 2,000-item month groups in ≤ 5 ms.
17. **Per-keystroke search.** The link menu and Quick Switcher rank before sorting and sort only the matches; search waits 150 ms after typing and `Queries.search` computes each item's match once. Check: tests of the same results as before; a timing test: link menu ranking over 10k items ≤ 10 ms.
18. **Trash view.** Attachment data computed once in `refresh`. Check: the Trash tests unchanged.

Check for Parts 3–4: `xcodebuild … test -skip-testing:TaDaUITests` passes; the 1,000-file vault opened on the Mac and the iPhone, timed to first list.

## Part 5 — Performance (Obsidian plugin)
19. **Change notifications.** `apply` calls `changed()` only when the item differs from the one indexed; `VaultIndex` keeps per-kind arrays; `recentEdits` entries go after `autosaveWindow`; the Trash re-reads only when a deleted file was a Ta Da item. Check: tests: typing in a note with no Ta Da change fires no listener; per-kind arrays equal a full filter.
20. **Index build.** Yield between batches; no `changed()` until the build ends. Check: test that listeners fire once after the build; a 10k-note generated vault builds without blocking input (manual, desktop and iPhone).

Check for the Part: `npm test` and `npm run build` pass.

## Part 6 — Review and release
21. **Review.** The diff of each Part against this plan's decisions. Check: findings fixed or noted here.
22. **Docs and release.** `docs/architecture.md` (Runtime: load and refresh), `docs/file-format.md` if the frontmatter guard changes writing rules, the plugin's `CLAUDE.md`; release notes; move this plan to the archive. Check: docs match the code; the release installs over 0.44.x on Mac and iPhone and keeps the folder.

## Delegation
- Part 1 (me): touches `Vault.swift`, `Notes.swift`, `Trash.swift` and `AppModel.swift`, which Part 3 also touches, so Part 3 follows it.
- Parts 2 and 5: `typescript-dev`, given this file and the plugin's `CLAUDE.md`. They run in parallel with Parts 1, 3 and 4. Step 10's TaDaCore port waits for Part 1.
- Part 4: `swift-dev`, given this file, after Part 3 (both touch `AppModel.updateLists` and `refresh`).
- Step 21: `code-reviewer`, given each Part's diff and this file, not my conclusions.

## Risks
- `prepare(forReadingItemsAt:)` with thousands of URLs on iCloud Drive is untested; step 11 measures it in an iCloud vault before the default changes.
- Skipping non-downloaded files on macOS means a first open with Optimize Mac Storage shows fewer files until they arrive.
