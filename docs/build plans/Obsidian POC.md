# Ta Da — Obsidian POC plan

## Context
Ta Da as an Obsidian plugin, over the same vault as the Mac and iPhone apps, with a Ta Da navigator in the left sidebar, as Notebook Navigator does. Design source: the canvas's **Obsidian POC** page at https://claude.ai/artifact/A7c33hg9HUKz41u3wbki3V (`ObsL2Today`, `ObsL2Task`, `ObsL2Capture`, `ObsL2Phone`), and the Mac's Agenda boards.

Starting point, as checked on 2026-10-18 and updated on 2026-10-19 after the vault structure plan (Build 28):
- Obsidian 1.14.4. Plugins are TypeScript.
- Obsidian's property editors (Properties panel, Bases table cells, `FileManager.processFrontMatter`) rewrite the whole frontmatter: comments go, flow lists become block lists, unneeded quotes go, number-like strings become numbers. Dates, `"[[links]]"`, empty keys and key order survive. Ta Da reads the result correctly.
- The apps keep what they create in `Ta Da/` at the vault's top level: `Ta Da/tasks/`, `projects/`, `areas/`, `attachments/` and a visible `Ta Da/Logbook/<yyyy-MM>/`, so Obsidian indexes logged files and links to them resolve. A vault in the old layout (top-level `tasks/`, `projects/`, `areas/`, `attachments/`, hidden `.logbook/`) still reads, and the apps ask once to move it into `Ta Da/`. `.trash/` stays at the top level; it's also Obsidian's own trash folder.
- TaskNotes (MIT) is the closest prior art. Configuring or forking it doesn't fit Ta Da's format; it's a reference for an index over `metadataCache` (`TaskManager.ts`) and a per-file write queue (`VaultMutationService.ts`).

## Decisions
- **Ta Da's folder**: the plugin creates files where the apps do (`Ta Da/tasks/`, `Ta Da/projects/`, `Ta Da/areas/`, `Ta Da/attachments/`) and reads both layouts as `docs/file-format.md` says (logged files in `Ta Da/Logbook/`, ignoring case; `Ta Da/` and the old top-level folders reserved from notes), except the old `.logbook/`, which Obsidian can't see. A vault is moved into `Ta Da/` by the apps before the plugin is used on it.
- **Logging and moving the old layout stay with the Mac and iPhone apps.** The plugin never logs or moves an old layout into `Ta Da/`. Reopening a logged file moves it back, as the apps do (`AppModel.reopenParent`).
- **Trash**: the plugin deletes tasks and notes only, one file at a time, into `.trash/` (`Vault.trash(file, false)`). Projects and areas, with their cascades, restore and Empty Trash, stay in the apps.
- **Format port**: TaDaCore's reading, writing and query rules are ported to TypeScript, not compiled from Swift. Conformance fixtures keep the two in step: a Swift test exports DesignVault's parse results, query results (fixed `today`) and write cases (input text, operation, expected text) as JSON into `Packages/TaDaCore/Tests/TaDaCoreTests/Fixtures/Conformance/`; the TypeScript tests read them there through the relative path `../Ta Da/Packages/TaDaCore/Tests/TaDaCoreTests/Fixtures/Conformance/`.
- **Writes** splice lines with the ported writers, never `processFrontMatter`. The open file goes through its `Editor` (one transaction, so undo and the cursor hold); other files through `Vault.process`, guarded on the text last read. Renames go through `FileManager.renameFile`, so Obsidian updates links; the name comes from the ported `FileNaming`.
- **Ta Da header** on task, project and area files: status, parent, dates and tags as chips with their menus, in Live Preview and Reading view. It hides Obsidian's Properties block on those files by default; a Properties button shows it.
- **Look** follows the Obsidian theme through its CSS variables (status colours from `--color-*`, accent from `--interactive-accent`). Ta Da's row, checkbox and chip shapes are kept.
- **Code** lives in its own repo, `ta-da-obsidian`, cloned beside this one (`~/Projects/ta-da-obsidian`): plugin id `ta-da`, name Ta Da, built from obsidianmd/obsidian-sample-plugin with esbuild, plain DOM, `isDesktopOnly: false`, `minAppVersion` 1.14.0. Tests use Vitest.
- **Distribution**: installed by hand (or BRAT) for the POC, written to the community store's rules from the start (no default hotkeys, sentence-case UI text, no `innerHTML` with file content, README with a licence).

## Milestones
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
- Menus: status, project or area (`SuggestModal`), dates (typed phrase plus a month grid), tags.
- A `ta-da-file` class on the leaf hides `.metadata-container`; the Properties button and a setting turn it off.
- Check: by hand on SampleVault (`ObsL2Task`): each chip writes one line; Properties shows and hides; Dark and Light themes.

### B1 — More of the core
- Port `TagQueries`, `NoteQueries`, `Grouping` (`ListSection`, `TagFilter`), and `Trash` listing (read only).
- Swift: those queries added to `queries.json`.
- Check: Vitest conformance.

### B2 — Navigator
- A left-sidebar `ItemView` with two panes side by side when the sidebar is wide enough, and one at a time (with back) when it's narrower. Navigation: search, Agenda, Loose tasks, Logbook, Trash; Tasks | Tags | Notes; areas with their projects, the tag tree, the folder tree. List: the Agenda (the Mac's strip and a day's or a week's tasks, without daily notes or Calendar), Loose, a project's or area's page, a tag's page, a folder's notes, Logbook and Trash (read only), each with Group and the tag filter.
- The list's selection follows the active file (`file-open`); arrow keys move it, Return opens it.
- Settings: open the navigator on startup; collapse the list pane. The file explorer stays as a tab beside it.
- Check: by hand (`ObsL2Today`; the Agenda as the Mac's Agenda boards): each domain matches the Mac on SampleVault.

### B3 — Agenda notes, New task and commands
- The Agenda's daily and week notes, as the Mac: a day's or week's note row (Create when missing, through `NewFile.dailyNote`), and the strip's ring for a daily note's open boxes. Ta Da's own settings, as the Mac's Settings ▸ Daily notes: folder and template for daily notes, and for week notes, which can be switched off.
- Calendar events and reminders are left out: Obsidian has no source a plugin can read for them.
- New task modal (`ObsL2Capture`), as the Mac's Quick Entry (`QuickEntryDraft`): type switch, title, the header's chips and Tags row; writes the new file through `NewFile`, in the shown project, area or tag, or due on the Agenda's selected day.
- Commands: New task, Complete, Move to project or area. A ribbon icon opens the navigator.
- Status changes as in the apps (`AppModel.setStatus`): closing a project with open tasks asks first; reopening a task reopens its Done or Cancelled project; reopening a logged file moves it, and its logged project, out of the Logbook.
- Check: by hand; the created file matches the Mac's Quick Entry output for the same input.

### B4 — iPhone and docs
- In Obsidian's drawer, the navigator's one-pane mode, and a bottom bar for Agenda, Projects and Files (`ObsL2Phone`).
- Here: `docs/architecture.md` (an Obsidian section), `CLAUDE.md` (the plugin repo and its commands), `docs/backlog.md`; archive this plan. In `ta-da-obsidian`: `CLAUDE.md` and README.
- Check: by hand on Obsidian for iPhone against the iCloud vault; nothing uses Node or Electron.

## Risks
The navigator's size; keeping the navigator, file explorer and active file in step; the phone drawer layout. Obsidian's editor saves with LF, so editing a CRLF file in Obsidian converts it, as any edit there does; the header widget replaces Obsidian's Properties widget through CodeMirror, with no official API for it; two implementations of the format to keep in step (the conformance fixtures are the guard); Obsidian's link updater may rewrite frontmatter wholesale on rename, which Ta Da accepts.
