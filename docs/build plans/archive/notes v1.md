# Ta Da — Notes plan (macOS)

## Context
Notes add a third sidebar domain beside Tasks and Tags. Notes are the vault's plain markdown files, browsed by folder and edited in the Live editor. Design source: the canvas's **Notes** page at https://claude.ai/artifact/A7c33hg9HUKz41u3wbki3V, rows **Notes — macOS** (`NotesBrowser`, `NotesSidebar`, `NoteConvert`) and **Notes — rows, properties and files** (`NoteRow`, `NoteProperties`, and the rules sticky). This plan covers the Mac only; the iPhone comes in a later plan.

Starting point, as checked on 2026-10-12:
- `Item(parsing:path:)` returns nil without `type: task|project|area` (`PropertyReader`), so untyped files are never indexed. `Item.Kind` is `task`, `project` and `area`.
- `Vault.markdownPaths()` scans recursively, skipping hidden folders (except `.logbook/`) and packages. It knows nothing about folders as such; `Vault.create(_:in:title:taken:)` writes a file into a folder.
- `AppModel.SidebarMode` is `projects | tags`; `AppModel.Domain` has `loose`, `project`, `area` and `tag`.
- `TagQueries` counts areas, projects and tasks; Untagged is the same three kinds. `Queries.search` and `LinkSearch` cover Ta Da files only.
- `FrontmatterEditor.set` appends a missing key before the closing `---`. `NewFile` makes tasks, projects and areas.
- File operations have no app-level undo; the editors have their own text undo.
- `DesignVault` and `SampleVault` each hold one untyped file, `notes/Not a task.md`.

## Decisions
- **What a note is**: a `.md` file with no `type: task|project|area` (any case), outside `areas/`, `projects/`, `tasks/` and `attachments/` at the vault's top level. Hidden folders, `.trash/` and `.logbook/` stay out. A typed file is never a note, wherever it sits. A file whose YAML doesn't parse and has no `type:` line is a note too, with the usual warning.
- **Kind**: `Item.Kind.note`. A note reads `createdDate` and `tags:` (frontmatter and inline, as other files do). It has no status, parent or dates; any other keys stay untouched and unread.
- **Subtasks**: a note's checkboxes count as subtasks under the same rules as a task's (`[-]` left out of the total). Ticking and the checkbox menu work as in a task.
- **Links**: notes take part in links both ways. `[[Title]]` resolves to notes, the link menu lists them, and backlinks count them. Today, Upcoming, Loose tasks, the project and area pages, and the Logbook never list them.
- **Folders**: the Notes tree is the folders that hold a note, or hold nothing at all (so a new folder shows), excluding the ones above. Folders are named by their last path segment, sorted alphabetically (case-insensitive), 16pt per level. Their folds are remembered.
- **Loose**: the vault's top level. It leads the tree in the place Tasks' Loose and Tags' Untagged take, uses the inbox icon in `link`, counts and lists only the top-level notes, and shows no folder chips. Root folders line up with its icon, with a parent's chevron in the leading padding, as tag rows do.
- **Counts**: a folder counts the notes in it and in its subfolders; Loose counts only its own.
- **Sidebar**: the switch becomes Tasks | Tags | Notes, three equal segments: the cube, the tag in the tag tint, and a page in `link`. "Projects" is renamed "Tasks" in the switch (the stored `SidebarMode` value stays `projects`). Swipes and back/forward cycle To Do → Tags → Notes. In Notes the foot's buttons are + Note and + Folder.
- **folderBrowser**: the folder icon (24pt, `link`) and name, with the parent path muted, and a count line ("3 notes · 2 folders"). Child folders appear as chips like tagBrowser's child tags, followed by the folder's own noteRows sorted by title, then "New note in <folder>". With no notes of its own, it reads "No notes in <folder> itself." The title renames the folder in place, as an area page does.
- **noteRow**: taskRow's layout with a 16pt muted page icon (not a control) in place of the checkbox. The meta line shows subtasks done/total, then the tag count with its hover list. In lists that mix folders (tagBrowser, search) the folder comes last, with a folder icon in `link`.
- **Note page**: the Live editor with the Tags row only (filled `tags:` chips, + Tag, In text). The quiet line holds Note ▾ (the note menu), the folder, subtasks, and "Created <date>". A note without `createdDate` shows "Edited <date>" from the file's modification date instead. The path bar shows the folder path.
- **Making**: + Note, the folder menu's New Note and ⌘N on a folder's page (File ▸ New Task/Note) write `Untitled.md` with `createdDate: <today>` and `tags: []` into the picked folder (Loose: the top level), then open it with the title selected. + Folder and New Folder add "Untitled folder" under the picked folder, its name ready to type. Folder names follow the filename rules, numbering a taken name.
- **Folder menu** (right-click a folder): New Note, New Folder, Rename, Reveal in Finder, Move to Trash. Renaming a folder rewrites body links written with its path (`[[Old/Title]]`). Move to Trash asks first, naming how many notes go, then moves the folder whole into `.trash/`.
- **Note menu** (Note ▾, a noteRow's right-click, File ▸ Convert to): Convert to Task…, Project…, Area… (each naming its folder), then Reveal in Finder and Move to Trash. A noteRow's menu also has Tags… and Move to Folder….
- **Convert**: a window sheet (`NoteConvert`) with a Task | Project | Area switch. It shows status and parent chips (not for an area), the move from → to, the frontmatter lines added, a subtasks line and a links line. Convert splices `type`, `status` (not for an area) and `createdDate` (only when missing) directly after the opening `---`, ahead of the note's keys. A note with no frontmatter gets the block. Picked chips are written in the same splice. The file then moves to `tasks/`, `projects/` or `areas/`, numbering a taken name; a project's title is also checked against other projects, live or logged. Links written with the old folder path are rewritten. The body is untouched. Ta Da then switches to Tasks and opens the file.
- **Tags**: notes count in the tag tree and in Untagged. tagBrowser gets a Notes group after Completed. tagMenu and tag autocomplete work in notes as in other files.
- **Search**: results include notes, shown as noteRows with their folder.
- **Trash**: a trashed note is listed in Trash with the page icon. Restoring puts it back in its folder when that folder still exists, otherwise at the vault's top level, numbering a taken name. A trashed folder restores whole.
- **iPhone (until its plan)**: the iOS build keeps compiling. The iPhone gets no Notes navigation, but where shared queries return notes (tag screens, search) they open in the file screen with the Tags row only.

## Milestones
The milestones run in order on `feat/notes`. Each follows the build stage loop (build, commit, review, fix, commit) and ends with its check passing. TaDaCore checks run on macOS and the iOS Simulator.

### C1 — Model and parsing
- `Item.Kind.note`; `Item(parsing:path:)` returns a note for untyped files at qualifying paths (`Item.isNotePath(_:)`).
- `PropertyReader`: a note reads `createdDate` and `tags:` only.
- Every switch and filter on `kind` is checked: `VaultIndex.tasks/projects/areas` stay as they are, and `notes` is added.
- Check: `ItemTests` and `PropertyReaderTests` cover typed vs untyped files, excluded folders, typed files in other folders, no frontmatter, and bad YAML.

### C2 — Folders, index and queries
- `Vault.noteFolders()`: folder paths by the rules above, empty folders included. Folder creation and deletion outside Ta Da are picked up at the next full scan.
- `VaultIndex`: notes by folder; folder counts rolled up.
- `NoteQueries` (beside `TagQueries`): `folderTree()`, `notes(in:)` sorted by title, `looseNotes()`.
- `TagQueries`: counts, Untagged and `tagBrowser` include notes (a Notes group). `Queries.search` and `LinkSearch` include notes. Backlinks include them.
- New fixture `Fixtures/NoteVault/`: notes at the top level and nested, empty folders, typed files outside the task folders, untyped files inside `tasks/` and `attachments/`, hidden folders, and trashed and logged files. `DesignVault` stays frozen. Expectations that change because its `notes/Not a task.md` now counts (Untagged, search) are updated in the tests, each with the reason.
- Check: `VaultIndexTests`, `QueriesTests` and `TagQueriesTests` on `NoteVault`; `LargeVaultTests` timings no worse than now.

### C3 — Writing
- `NewFile.note(today:)`: `createdDate` and `tags: []`.
- `Vault`: `createFolder(named:in:)`, `renameFolder(_:to:)` (rewriting folder-path links), `trashFolder(_:)` and its restore, and `moveNote(_:to:)`.
- `NoteConversion.convert(_:to:status:parent:today:)`: a splice after the opening `---` (a new `FrontmatterEditor.insertAtTop`), `createdDate` kept when present, then the move into the kind's folder with project-title numbering and link rewriting.
- `Trash`: restoring a note to its folder, else the top level.
- Check: `NewFileTests`, `NoteConversionTests` (with and without frontmatter, an existing `createdDate`, each kind, taken names), `VaultTests` for the folder operations, `TrashTests`.

### A1 — App model
- `SidebarMode.notes`; `Domain.folder(String)` ("" for Loose); folder folds remembered.
- `newNote()`, `newFolder()`, `renameFolder`, `trashFolder`, `moveNote`, `convert(_:to:…)` (switching to Tasks and opening the file).
- Check: `AppModelTests` cover the mode, the domain, folds, making, the folder operations and conversion.

### M1 — Sidebar and folderBrowser
- `SidebarView`: the three-segment switch (Projects renamed Tasks), the Notes tree led by Loose, the + Note / + Folder foot, the folder menu and the inline name field; swipe and back/forward cycling three views.
- `FolderBrowserView` (from `TagBrowserView`), shown by `WorkspaceView` for `.folder`, with folder chips, noteRows and renaming in place.
- `NoteRow` (beside `TaskRow`), also used by tagBrowser's Notes group and search results.
- Check: macOS build; `KeyboardTests`; `DesignRenderTests` renders compared with `NotesSidebar`, `NotesBrowser` and `NoteRow`; UI tests (with permission).

### M2 — The note page
- `LiveDocumentView` for a note: the Tags row alone and the quiet line (Note ▾, folder, subtasks, Created or Edited), with the path bar showing the folder.
- The note menu on the shared `PopupMenu`; `FileMenu` items for notes (Tags…, Move to Folder…, Convert to).
- Check: macOS build; `PropertyPickerTests`; the render compared with `NoteProperties`.

### M3 — Convert
- `ConvertSheet` (Shared): the type switch, the chips (using the editor's status and parent menus), the move, the frontmatter lines and the notes on subtasks and links; File ▸ Convert to in `Commands`.
- Check: macOS build; `AppModelTests` for the sheet's state; the render compared with `NoteConvert`.

### D1 — Docs and data
- `docs/file-format.md`: notes (identity, folders, `createdDate` and `tags:`), conversion's splice and move, folder operations, and Trash for notes and folders.
- `docs/architecture.md`: the note kind, folder scanning, the Notes domain, folderBrowser, the note page and conversion.
- `docs/design/design-framework.md`: In the app rows for notesSidebar, folderBrowser, noteRow, the note page and the convert sheet; As built differences.
- `docs/backlog.md`: add Notes on iPhone; drop anything this delivers.
- `SampleVault`: a few folders of notes with tags, checkboxes and links.
- Check: all tests (`TaDa.xctestplan`), both package suites, macOS and iOS builds; `git diff SampleVault` shows only the intended edits.

## Out of scope
- The iPhone's Notes screens.
- Dragging notes or folders between folders (Move to Folder… covers moving a note).
- Converting a task, project or area back to a note.
- Undo for conversion and folder operations.
- Templates, daily notes and note sorting other than by title.
