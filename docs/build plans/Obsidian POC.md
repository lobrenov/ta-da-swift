# Ta Da — Obsidian POC plan

## Context
Ta Da as an Obsidian plugin, over the same vault as the Mac and iPhone apps. Two build options, compared at the end: **Level 1** puts Ta Da inside Obsidian's own layout; **Level 2** adds a Ta Da navigator in the left sidebar, as Notebook Navigator does. Design source: the canvas's **Obsidian POC** page at https://claude.ai/artifact/A7c33hg9HUKz41u3wbki3V (Level 1: `ObsL1Today`, `ObsL1Task`, `ObsL1Project`, `ObsL1Capture`; Level 2: `ObsL2Today`, `ObsL2Upcoming`, `ObsL2Phone`).

Starting point, as checked on 2026-10-18 and updated on 2026-10-19 after the vault structure plan (Build 28):
- Obsidian 1.14.4. Plugins are TypeScript; custom Bases views exist since 1.10 (`registerBasesView`); Bases has Table, Cards, List, Map and Kanban, no calendar.
- Obsidian's property editors (Properties panel, Bases table cells, `FileManager.processFrontMatter`) rewrite the whole frontmatter: comments go, flow lists become block lists, unneeded quotes go, number-like strings become numbers. Dates, `"[[links]]"`, empty keys and key order survive. Ta Da reads the result correctly.
- The apps keep what they create in `Ta Da/` at the vault's top level: `Ta Da/tasks/`, `projects/`, `areas/`, `attachments/` and a visible `Ta Da/Logbook/<yyyy-MM>/`, so Obsidian indexes logged files and links to them resolve. A vault in the old layout (top-level `tasks/`, `projects/`, `areas/`, `attachments/`, hidden `.logbook/`) still reads, and the apps ask once to move it into `Ta Da/`. `.trash/` stays at the top level; it's also Obsidian's own trash folder.
- TaskNotes (MIT) is the closest prior art. Configuring or forking it doesn't fit Ta Da's format; it's a reference for Bases views (`src/bases/`), an index over `metadataCache` (`TaskManager.ts`) and a per-file write queue (`VaultMutationService.ts`).

## Decisions (both options)
- **Ta Da's folder**: the plugin creates files where the apps do (`Ta Da/tasks/`, `Ta Da/projects/`, `Ta Da/areas/`, `Ta Da/attachments/`) and reads both layouts as `docs/file-format.md` says (logged files in `Ta Da/Logbook/`, ignoring case; `Ta Da/` and the old top-level folders reserved from notes), except the old `.logbook/`, which Obsidian can't see. A vault is moved into `Ta Da/` by the apps before the plugin is used on it.
- **Logging and moving the old layout stay with the Mac and iPhone apps.** The plugin never logs, unlogs or moves an old layout into `Ta Da/`. Setting a logged file's status in Obsidian is picked up by the app's next daily logging, as for any other app.
- **Trash**: the plugin deletes tasks and notes only, one file at a time, into `.trash/` (`Vault.trash(file, false)`). Projects and areas, with their cascades, restore and Empty Trash, stay in the apps.
- **Format port**: TaDaCore's reading, writing and query rules are ported to TypeScript, not compiled from Swift. Conformance fixtures keep the two in step: a Swift test exports DesignVault's parse results, query results (fixed `today`) and write cases (input text, operation, expected text) as JSON into `Packages/TaDaCore/Tests/TaDaCoreTests/Fixtures/Conformance/`; the TypeScript tests read them there through the relative path `../Ta Da/Packages/TaDaCore/Tests/TaDaCoreTests/Fixtures/Conformance/`.
- **Writes** splice lines with the ported writers, never `processFrontMatter`. The open file goes through its `Editor` (one transaction, so undo and the cursor hold); other files through `Vault.process`, guarded on the text last read. Renames go through `FileManager.renameFile`, so Obsidian updates links; the name comes from the ported `FileNaming`.
- **Ta Da header** on task, project and area files: status, parent, dates, repeat and tags as chips with their menus, in Live Preview and Reading view. It hides Obsidian's Properties block on those files by default; a Properties button shows it.
- **Look** follows the Obsidian theme through its CSS variables (status colours from `--color-*`, accent from `--interactive-accent`). Ta Da's row, checkbox and chip shapes are kept.
- **Code** lives in its own repo, `ta-da-obsidian`, cloned beside this one (`~/Projects/ta-da-obsidian`): plugin id `ta-da`, name Ta Da, built from obsidianmd/obsidian-sample-plugin with esbuild, plain DOM, `isDesktopOnly: false`, `minAppVersion` 1.14.0. Tests use Vitest.
- **Distribution**: installed by hand (or BRAT) for the POC, written to the community store's rules from the start (no default hotkeys, sentence-case UI text, no `innerHTML` with file content, README with a licence).

## Shared milestones
Each ends with its check passing, then a commit and a review.

### O1 — Plugin scaffold and reading
- `ta-da-obsidian`: manifest, esbuild, Vitest, a dev command that copies `main.js` into a test vault's `.obsidian/plugins/ta-da/`.
- Port: `Item` (with `isLogged`, `isNotePath` and `reservedFolders`), `Status`, `LocalDate`, `WikiLink`, `Checkbox`, `Tag` (`Model/`); the folder constants (`Vault.home` and the folders in it, the old layout's names); `FrontmatterSplitter`, `PropertyReader`, `BodyScanner` (`Parsing/`), and the part of the fork's `MarkdownFacts` they read; `VaultIndex`, `Queries`, and `DailyNotes` as far as day marks need (`Index/`).
- `TaDaIndex`: built from raw text (`Vault.cachedRead`) on layout ready, patched on `metadataCache` `changed` and `Vault` `rename`/`delete`.
- Swift: `ConformanceExportTests` writes `Fixtures/Conformance/read.json` and `queries.json` from DesignVault (the old layout) and from a small fixture in the new layout.
- Check: Vitest conformance passes on both files; the plugin loads in Obsidian with SampleVault and logs nothing.

### O2 — Writing
- Port: `CheckboxSyntax`, `Lines`, `FrontmatterEditor`, `ChecklistEditor`, `TagEditor`, `Completion`, `Parent`, `FileNaming`, `NewFile`, `DatePhrase`.
- `Writer`: the editor path and the `Vault.process` path, one queue per file. Each write updates `TaDaIndex` at once.
- Commands: Set status (one per status; Ongoing on projects only; not offered for the file's current status).
- Swift: `Fixtures/Conformance/writes.json`.
- Check: Vitest write cases match byte for byte (LF and CRLF); a status change in Obsidian shows as a one-line `git diff SampleVault`.

### O3 — Ta Da header
- Live Preview: a CodeMirror block widget in place of the frontmatter; Reading view: a markdown post-processor. Both draw the same chip row.
- Menus: status, project or area (`SuggestModal`), dates (typed phrase plus a month grid), repeat text, tags.
- A `ta-da-file` class on the leaf hides `.metadata-container`; the Properties button and a setting turn it off.
- Check: by hand on SampleVault (`ObsL1Task`): each chip writes one line; Properties shows and hides; Dark and Light themes.

## Option A — Level 1: inside Obsidian's layout
Boards `ObsL1Today`, `ObsL1Task`, `ObsL1Project`, `ObsL1Capture`. Obsidian's file explorer, tabs and sidebars stay; Ta Da adds views and the header.

### A1 — Bases views
- `registerBasesView`: `tada-list` (Ta Da's groups and rows; clicking the checkbox completes, right-click opens the status menu) and `tada-agenda` (Upcoming by day). Rows read the Base's entries, and subtasks, parents and groups from `TaDaIndex`.
- A command and a Settings button write `Ta Da/Today.base`, `Upcoming.base`, `Loose tasks.base`, `Logbook.base` and `Project tasks.base` (filtered to `this`, for embedding in a project file).
- Check: by hand (`ObsL1Today`, `ObsL1Project`): the views match the Mac's Today, Upcoming and Loose lists on SampleVault for the same day.

### A2 — Calendar, New task and commands
- Right-sidebar view: month grid with due and deadline dots, and the next 7 days.
- New task modal (`ObsL1Capture`): title with typed date, `+project` and `#tag`, chips, description; writes `Ta Da/tasks/<title>.md` through `NewFile`.
- Commands: New task, Complete, Move to project or area, Open in Ta Da's calendar. A ribbon icon opens Today.
- Status changes as in the apps (`AppModel.setStatus`): closing a project with open tasks asks first; reopening a task reopens its Done or Cancelled project.
- Check: by hand; the created file matches the Mac's Quick Entry output for the same input.

### A3 — iPhone and docs
- Obsidian on iPhone: Bases views, header and modal work; nothing uses Node or Electron.
- Here: `docs/architecture.md` (an Obsidian section), `CLAUDE.md` (the plugin repo and its commands), `docs/backlog.md`; archive this plan. In `ta-da-obsidian`: `CLAUDE.md` and README.
- Check: by hand on Obsidian for iPhone against the iCloud vault.

## Option B — Level 2: Ta Da navigator
Boards `ObsL2Today`, `ObsL2Upcoming`, `ObsL2Phone`. O1–O3, then the navigator in place of A1–A2. Bases isn't needed: the list pane draws from `TaDaIndex`.

### B1 — More of the core
- Port `TagQueries`, `NoteQueries`, `Grouping` (`ListSection`, `TagFilter`), and `Trash` listing (read only).
- Swift: those queries added to `queries.json`.
- Check: Vitest conformance.

### B2 — Navigator
- A left-sidebar `ItemView` with two panes. Navigation: search, Today, Upcoming, Loose tasks, Logbook, Trash; Tasks | Tags | Notes; areas with their projects, the tag tree, the folder tree. List: Today, Upcoming, Loose, a project's or area's page, a tag's page, a folder's notes, Logbook and Trash (read only), each with Group and the tag filter.
- The list's selection follows the active file (`file-open`); arrow keys move it, Return opens it.
- Settings: open the navigator on startup; collapse the list pane. The file explorer stays as a tab beside it.
- Check: by hand (`ObsL2Today`): each domain matches the Mac on SampleVault.

### B3 — Month view, New task and commands
- Main-area `ItemView`: the month with each day's tasks (`ObsL2Upcoming`), opened from Upcoming.
- New task modal and commands as in A2, creating in the shown project, area or tag.
- Check: by hand.

### B4 — iPhone and docs
- In Obsidian's drawer, one pane at a time with back, and a bottom bar for Today, Upcoming, Projects and Files (`ObsL2Phone`).
- Docs as in A3; archive this plan.
- Check: by hand on Obsidian for iPhone.

## Comparison

| | Level 1 | Level 2 |
|---|---|---|
| Milestones | O1–O3, A1–A3 (6) | O1–O3, B1–B4 (7) |
| TaDaCore ported | Model, Parsing, Writing, `VaultIndex`, `Queries` (about 2,100 of TaDaCore’s 4,300 Swift lines) | Level 1's, plus `TagQueries`, `NoteQueries`, `Grouping`, Trash listing (about 2,500) |
| New UI | Header, 2 Bases views, calendar panel, modal | Header, a two-pane navigator with 9 list kinds, Group and filter, month view, modal, phone layout |
| Relative UI size (estimate) | 1× | about 2.5× |
| Depends on | The Bases API (new, still changing) | Obsidian's sidebar and leaf APIs (stable) |
| User can reshape views | Yes: Bases filters, sorts and properties | No: Ta Da's lists only |
| Feels like | Obsidian with Ta Da views | The Ta Da app inside Obsidian |
| Main risks | Bases API changes; Bases can't read bodies, so views lean on `TaDaIndex` anyway | Size; keeping the navigator, file explorer and active file in step; phone drawer layout |

Shared risks: Obsidian's editor saves with LF, so editing a CRLF file in Obsidian converts it, as any edit there does; the header widget replaces Obsidian's Properties widget through CodeMirror, with no official API for it; two implementations of the format to keep in step (the conformance fixtures are the guard); Obsidian's link updater may rewrite frontmatter wholesale on rename, which Ta Da accepts.
