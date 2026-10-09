# Ta Da — Areas plan

## Context
Areas add one level above projects. Contexts are deprecated. Design source: the canvas's **Domains** page, rows **Areas · Mac** (`AreaBrowser`, `AreaIcons`, `AreaMenus`, `AreaToday`) and **Areas · iPhone** (`AreaIosProjects`, `AreaIosArea`, `AreaIosMove`, `AreaIosTrash`, `AreaIosToday`) at https://claude.ai/artifact/A7c33hg9HUKz41u3wbki3V.

Starting point, as checked on 2026-10-09:
- `Properties.area` is free text, read for tasks and projects and shown nowhere except Trash and search. `contexts` drives the Today/Loose filter pills (Mac `ContextFilter`, iPhone `PhoneContextPills`), row meta and the project table's contexts column.
- `Item.Kind` is `task | project`. `VaultIndex` maps tasks to projects by lowercased link title (`tasksByProjectTitle`); `Queries.isLoose`, `grouped` and `activeProjects` build on it.
- `Vault.moveToTrash` takes a project's tasks; `restore` brings a project's trashed tasks back and relinks them; `discard` takes a project's trashed tasks. `renameProject` relinks tasks through `relink`.
- Every SampleVault task carries `area:` beside `project:`, and no area files exist.

## Decisions
- **Format**: an area is a `.md` file with `type: area`, created in `areas/`. Its frontmatter is `type` and `createdDate`, with no status or dates; the body is free markdown.
- **One parent per file**: a project names its area (`area: "[[Personal]]"`). A task names either its project or its area, never both. A task's area is its project's area; it isn't written into the task. Changing a project's area writes the project only.
- **Values**: `area` is written as a wikilink, like `project`. A plain `area: Personal` reads as the title `Personal`.
- **Both keys on a task**: `project` wins when it has a value; `area` is ignored, with a warning. Ta Da doesn't rewrite the file.
- **Unresolved area**: the file counts as having no parent (Loose tasks, or a loose project at the top of the sidebar) and gets a warning. Its chip is struck through, and its menu offers **Create Area "Name"**, which creates `areas/Name.md` and so resolves every file naming it.
- **Loose**: a task is loose when it has no resolved project and no resolved area. A project is loose when it has no resolved area.
- **Sidebar**: no section headers. Loose projects first, then each area (title order) with its active projects indented under it. No folding. Areas have no ring and no count. Bottom buttons: Task, Project, Area.
- **Area page**: icon and title (renames in place), Open area file, then Projects, Tasks (filed straight to the area) and a folded Completed group, folds remembered per area. New task in Personal at the end.
- **Today**: tasks with no parent first (no header), then loose projects' groups, then each area: its own tasks, then its projects' groups. No indentation.
- **Chips**: the parent chip follows status. A project's opens the area menu (areas, No area, New Area…). A task's opens the move menu: Loose tasks, loose projects, then each area followed by its projects. Picking sets one key and clears the other.
- **Delete**: deleting an area asks first ("Delete 20 Files"), then moves the area, its projects, their tasks and its own tasks to `.trash/`.
- **Discard**: Delete Forever on an area also removes its trashed projects and tasks, as a project's removes its trashed tasks.
- **Restore**: only upward. A task brings back its project and that project's area, or its area. A project brings back its area. An area comes back alone. A parent deleted forever is recreated by name. Restoring a project no longer brings its tasks.
- **Icon**: the Cube, two-tone (top face filled at 30%), tinted `doing`. Sidebar 16, title 24, chip 13, iPhone row 28.
- **Contexts**: no longer read or shown. The keys stay in files untouched, as any unknown key does.
- **Shortcut**: ⌥⌘N New Area.

## Milestones
The milestones run in order in one worktree. Each ends with its check passing. TaDaCore checks run on macOS and the iOS Simulator.

### C1 — Model and parsing
- `Item.Kind.area`; `Vault.areaFolder = "areas"`.
- `Properties.area: WikiLink?`, read for tasks and projects (ignored on areas). A plain value reads as a title. Remove `Properties.contexts` and its reading.
- Warnings: `.unresolvedArea(String)` (index-level, like `.unresolvedProject`) and `.areaIgnored(String)` for a task with both keys.
- `NewFile.area(today:)`; `NewFile.task(project:area:today:)` writing `project:` or else `area:`; `NewFile.project(area:today:)`.
- App: drop contexts so it builds: Mac `ContextFilter` and the project table's contexts column, iPhone `PhoneContextPills`, row meta; warning messages for the two new cases.
- Check: `PropertyReaderTests`, `ItemTests`, `NewFileTests` cover the new kind, both value shapes, both keys, and contexts ignored.

### C2 — Index and queries
- `VaultIndex`: `projectsByAreaTitle` and `tasksByAreaTitle` maps beside `tasksByProjectTitle`, patched per item.
- `area(titled:)`, `area(of:)` (a project's own; a task's through its project when `project` has a value, else its own), `parent(of:)`, `projects(in area:)`, `tasks(in area:)` (filed straight), `allTasks(in area:)` (own plus its projects').
- `warnings(for:)` adds unresolved area and area-ignored.
- `Queries`: `isLoose` and `loose()` per the rule above; `looseProjects()`; `areas()` for the sidebar (each with its active projects); `grouped(_:)` returns Today's order (no parent, loose projects, then per area: area group then its project groups) as a flat list whose groups carry their kind. `search` matches title, summary and area title; contexts drop out.
- New fixture `Fixtures/AreaVault/`: areas with and without projects, a loose project, area-only tasks, both-keys and unresolved cases. `DesignVault` stays frozen; its unresolved `area:` values keep its counts as they are.
- Check: `VaultIndexTests`, `QueriesTests` on `AreaVault`; design-count and golden tests unchanged.

### C3 — Writing, rename and trash
- `Vault.renameArea(at:to:index:)` relinks projects and area tasks; `relink` takes the key (`project` or `area`).
- Setting a parent writes one key and clears the other in one coordinated update.
- `moveToTrash` on an area: the area, its projects, their tasks and its own tasks, the area first.
- `restore`: upward only. For each restored file, restore its trashed parent chain; if a parent isn't in `.trash/` or the vault, create it by name in `projects/` or `areas/`. Relink when a restored parent's name had to change. A project no longer brings its tasks.
- `discard`: an area takes its trashed projects and tasks, as a project takes its tasks today.
- Check: `TrashTests` and `VaultTests` cover area delete, each restore path (task → project → area, project → area, area alone, parent recreated, renamed parent relinked) and discard; existing project-restore tests updated to the upward rule.

### A1 — App model
- `Domain.area(String)`; lists gain `looseProjects` and `areas` (with their projects); `todayGroups` from `grouped`.
- `setParent(_:of:)` replaces `setProject(_:of:)` (project, area or none); `setArea(_:of:)` for projects. `newArea()` (⌥⌘N, opens its page with the title ready), `newArea(named:)` for Create Area, `newTask()` and `newProject()` in an area domain file into it.
- `rename` routes areas through `renameArea`. `moveToTrash` sets a confirmation request when an area is among the files; confirming trashes. `restore`'s note names `areas/` too.
- Drops: tasks and projects dropped on an area row set their parent.
- Check: `AppModelTests` cover parent changes, area create/rename/trash/restore, drops and the lists.

### M1 — Mac
- `AreaIcon` view (Shared) drawing the Cube in `doing`.
- `SidebarView`: remove the Projects `SectionLabel`; rows per the design; area rows take `.taskDrop` and `.fileMenu`.
- `AreaBrowserView` (from `ProjectBrowserView`), shown by `WorkspaceView` for `.area`; Open area file opens the area's page in `DocumentPane`.
- `TaskListView`: Today's groups with an area group header.
- `PropertyChips`: the parent chip (struck through when unresolved); areas show title, createdDate and their counts only. `PropertyPickers`: the move menu grouped by area (`ProjectChoice` gains `.area`), the area menu, Create Area.
- `FileMenu` on an area: New Task in, New Project in, Open Area File, Reveal in Finder, Delete. The delete confirmation follows the canvas's `AreaMenus` dialog.
- `TrashView`: area rows with the icon and "Area · deleted with N projects and M tasks".
- `Commands`: File ▸ New Area (⌥⌘N).
- Check: macOS build; `PropertyPickerTests`, `FileMenuTests`, `KeyboardTests`; a `DesignRenderTests` render of the area page and sidebar compared with `AreaBrowser`; UI tests (with permission).

### M2 — iPhone
- `PhoneProjectsScreen`: loose projects, then area rows with their projects indented (`AreaIosProjects`).
- `PhoneAreaScreen` on a new `PhoneRoute.area`; its More menu (New Task, New Project, Area File, Rename, Share…, Move to Trash) and the confirmation (`AreaIosArea`, `AreaIosTrash`).
- `PhoneProjectSheet` becomes the move sheet grouped by area (`AreaIosMove`); a project's area chip opens an area sheet.
- `PhoneFileScreen`: the parent chip. `PhoneTaskListScreen`: Today's groups (`AreaIosToday`). `PhoneTrashScreen`: area rows.
- Check: iOS Simulator build; `PhoneNavigationTests`; the screens checked against the canvas in the Simulator.

### D1 — Docs and data
- `docs/file-format.md`: `type: area`, `area` as a link and one parent per file, both-keys rule, unresolved areas, loose rules, Today order, delete and restore rules; contexts deprecated.
- `docs/architecture.md`: areas in the index, trash, window and iPhone sections; ⌥⌘N in Shortcuts.
- `docs/design/design-framework.md`: In the app rows for `AreaIcon`, `AreaBrowserView` and the menus; As built differences. `docs/backlog.md`: drop "Areas in Live mode".
- `SampleVault`: add `areas/Personal.md`, `Work.md`, `Game Jams.md`, `TTRPGs.md`; remove `area:` from tasks that have a project; write `area` values as links.
- Check: all tests (`TaDa.xctestplan`), both package suites, macOS and iOS builds; `git diff SampleVault` shows only the intended edits.

## Out of scope
- The Logbook board shows Completed across areas; it isn't built, so it's out of scope here.
