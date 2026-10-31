# Ta Da for Obsidian — Logging and File Actions

## Context
The plugin shows the Logbook but doesn't log: completed files stay where they are, and a completed repeating task stays Done, until Ta Da runs. It acts on one file at a time, and its file menu has only Status… and Convert to project…. This plan brings Ta Da's logging (`docs/file-format.md`, Logging and Reopening a logged file; `Logbook.swift`, `AppModel.logIfDue`/`logNow`) to the plugin, and Ta Da's picking, Move, Schedule, Set Deadline… and Tags… (`docs/architecture.md`, Window), on Obsidian's own menus, commands and dragging.

## Decisions

### Logging
- **The plugin logs as Ta Da does, as one more app on the folder.** Ta Da's Mac and iPhone apps already log the same folder independently, each once a day per device; the plugin joins them under the same rules. No shared lock or owner.
- Every step is conditional on the file as it is when the step runs, so a second logger finds nothing to do: a file no longer at its path, or no longer Done or Cancelled, is skipped; moving a repeating task forward reopens it; putting back a reopened file needs it logged and open.
- **Daily run**: on layout ready (once the index is built) and at day change (a plugin-level `registerInterval`, as `NavigatorView.rollOver`), when the vault's last logged day isn't today. It logs `filesToLog(completedBefore: today)`, puts back reopened logged files, and puts back logged projects with open tasks as Doing, as `logIfDue`. The day is kept in `data.json` (`lastLogged`) only when the run succeeds; a failure tries again at the next open or day change.
- **Log now** in the Logbook's header logs every completed file; a completed project with open tasks asks first through `CompletionModal`, as Ta Da's Log Now.
- The core ports as `src/core/writing/log.ts` (`planLog`, the counterpart of `planUnlog`: each file's destination in `Ta Da/logbook/<yyyy-MM>/`, numbered names, project numbering against every project's title, the tasks' relinks, and the repeating tasks that move forward instead) and the queries `filesToLog`, `reopenedLogged` and `loggedProjectsWithOpenTasks`. Moves are `FileManager.renameFile`; relinks and forward moves are spliced through `Writer`.
- The Recurrence plan's "↻ moves to <date>" rows and status notes stay; they now describe the plugin's own next run too.

### File actions
- **Picking**: in the Agenda, Tasks and Tags views' lists, ⌘-click (Ctrl-click) adds or removes a row and Shift-click picks a range, as in Obsidian's file explorer. Esc or a plain click clears it. Desktop only; on a phone the file menu acts on one file.
- **Files menu**: right-clicking a picked row opens Obsidian's multi-file menu, `workspace.trigger("files-menu", menu, files, "ta-da", leaf)`, so Obsidian's own items (Delete, Move to…) show as in the file explorer. The plugin's `files-menu` handler adds Status…, Move…, Schedule… and Set deadline… when every file is a task or project; Move… when they're all tasks (project or area) or all projects (area). The file explorer's multi-select gets the same items.
- **File menu** (`file-menu`, one file) gains Move…, Schedule…, Set deadline… and Tags… beside Status…. Tags… stays one file, as in Ta Da.
- Move… opens `ParentModal`; Schedule… and Set deadline… open `DateModal`. For several files the date fills only when they all agree, and the Repeat section shows only for one task.
- **Commands**: Schedule and Set deadline, alongside Move to project or area. All three act on the picked rows when a Ta Da view is active and has picks, else on the active file.
- **Drag to move**: task and project rows drag (all the picks when the row is picked) through Obsidian's `app.dragManager` (`dragFiles`, `onDragStart`; at runtime, not in its typings, guarded like `setSubmenu`), so a drag into the editor links the files as a file explorer drag does. Project and area rows in the Tasks view are drop targets, and read `dragManager.draggable`, so files dragged from the file explorer move too: a task onto a project or area, a project onto an area. Desktop only.
- Writes go through `Writer`, one queue per file, with the apps' status rules. No default hotkeys, sentence-case text.

## Delegation
Each of steps 1 to 6 is one stage, run by subagents:
1. The builder builds the stage: swift-dev in Ta Da (step 1), typescript-dev in the plugin (steps 2 to 6). Commit.
2. code-reviewer reviews the stage's commit, returning at most 5 fixes.
3. The builder applies the fixes. Commit.
4. The stage's by-hand checks, in Obsidian on SampleVault.

The main session runs step 7, briefs each stage with its step and Decisions, and reviews each result against its Check before the next stage starts.

## Sequencing
- Steps 1 and 2 run in parallel: step 1 writes only Ta Da (`Packages/TaDaCore`), step 2 only the plugin.
- Steps 3 to 6 run one at a time in the plugin, in order, after steps 1 and 2. Step 3 needs step 1's fixtures and step 4 needs step 3. Steps 4 to 6 each touch `NavigatorView.ts` or `main.ts`, and steps 5 and 6 build on step 2's picking.
- Step 7 runs once steps 1 to 6 have passed their checks.

## Steps
1. **Fixtures** (Ta Da): logging cases in `ConformanceExportTests.swift` on a `LoggingVault` fixture: `filesToLog` (before a day and any day, waiting projects), `Vault.log`'s moved paths and written texts (month folders, numbering, project numbering, relinks, repeating tasks moving forward and one ending at `until`), `reopenedLogged`, `loggedProjectsWithOpenTasks`, and `unlog` from those; regenerate with `swift test --package-path Packages/TaDaCore --filter writeConformance`. Check: core tests pass.
2. **Menus**: picking, the `files-menu` handler, and Move…, Schedule…, Set deadline… and Tags… in both menus. Check: unit tests for which items show for a set of files and for the agreed date; by hand from the views and the file explorer, one and several files, desktop and iPhone.
3. **Core port**: `log.ts` and the queries, with their conformance runs. Check: `npm test` passes, the new cases included.
4. **Logging**: the daily run, `lastLogged`, Log now and its question. Check: unit tests for when the run is due and that a failed run keeps the old day; by hand in SampleVault with Ta Da closed (files log, a repeating task moves forward, a reopened logged file comes back), then with Ta Da and Obsidian both open across a day change (each file logged once, no numbered duplicates).
5. **Commands**: Schedule, Set deadline, and Move to project or area on picks. Check: by hand with picks and with only an active file.
6. **Drag to move**. Check: by hand, rows and file explorer files onto project and area rows, a picked set, a project onto an area, a drag into the editor.
7. **Docs and version**: the plugin's `README.md` (Logging, picking, menus, commands) and `CLAUDE.md` layout; Ta Da's `docs/architecture.md` (Obsidian section), `docs/file-format.md` (Logging: Ta Da and the plugin log); the canvas's Obsidian pages get Log now and the menus. The plugin's next `y` version, tagged, with its row in `docs/versioning.md`'s pairing table. Check: `npm test` and `npm run build` pass; the plugin in SampleVault matches the apps on the same files.

## Risks
- Two devices logging before their sync meets can both move a file, leaving a numbered copy or a sync conflict in the Logbook. Ta Da's Mac and iPhone already share this.
- `app.dragManager` isn't public API and can change with Obsidian; dragging then does nothing.
- Obsidian's Delete in the files menu doesn't apply Ta Da's rules (a project takes its tasks, an area asks first).
