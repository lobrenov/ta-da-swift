# Ta Da architecture

How the app is built. The file format and writing rules are in `docs/file-format.md`; the design system is in `docs/design/design-framework.md`.

## Layers

- **TaDaCore** (`Packages/TaDaCore`, local package): the model, parsing, surgical writes, the index, queries and storage. Foundation, swift-markdown 0.9.0 and Yams 6.2.2 only; no UI.
- **TaDa** (`TaDa/`, app target): SwiftUI views over an `@Observable` `AppModel`. macOS 26 and iOS 26 minimum; on the Mac, App Sandbox with user-selected read/write. The model, theme, live editor, folder handling and the document's title, body, banner and footer build for both; the Mac's views are behind `#if os(macOS)` and the iPhone's are in `TaDa/iOS/`.
- **TaDaMarkdown** (`Packages/TaDaMarkdown`, local package): the Live editor, from swift-markdown-engine 0.13.0 under Apache-2.0, for macOS and iOS. Parsing, styling, layout, input and the text-delegate path are shared; `Platform/Platform.swift` names the AppKit and UIKit types, and `TextView/iOS/` holds the iOS editor. Its `ORIGIN.md` lists the changes.

The workspace `TaDa.xcworkspace` holds the project, TaDaCore and TaDaMarkdown; the test plan `TaDa.xctestplan` runs TaDaTests, TaDaCoreTests and TaDaUITests.

## Files

```
TaDa/
├── TaDaApp.swift              one main window plus Settings, sharing one AppModel; AppDelegate owns it and handles activation, quitting and day changes.
│                              On iOS, one window group that refreshes when the scene becomes active and saves when it leaves
├── ContentView.swift          folder picker until a folder is open, then sidebar + workspace (on iOS, PhoneRootView); applies the theme
├── AppModel.swift             root state: folder, index, domain, selection, open document, theme set and appearance; refresh, save, outside-change handling
├── OpenDocument.swift         the selected file's whole text; edits reparse it
├── SettingsStore.swift        where AppModel keeps its settings: UserDefaults, or a test's in-memory store
├── Commands.swift             menu commands and shortcuts
├── UITestingLaunch.swift      the `-uiTesting` launch: throwaway settings and folder
├── Theme/                     Theme (15 colour tokens + isDark, as `PlatformColor`: NSColor or UIColor), ThemeSet, Appearance, the 15 bundled
│                              schemes and 8 sets; themed(by:) sets \.theme and the colour scheme and follows the system appearance
├── Onboarding/                FolderPickerView
├── Settings/                  SettingsView (nav and shared parts), VaultSettingsView, ThemeSettingsView, EditorSettingsView
├── Sidebar/                   SidebarView: search, domains, projects, folder line, Settings, New buttons
├── Browser/
│   ├── WorkspaceView.swift    the area right of the sidebar, per domain
│   ├── TaskListView.swift     Today and Loose tasks
│   ├── AgendaView.swift       Upcoming
│   ├── MonthCalendarView.swift
│   ├── ProjectBrowserView.swift
│   ├── SearchResultsView.swift
│   ├── TrashView.swift        the files in `.trash/`: pick, restore, empty
│   ├── TaskRow.swift          TaskRow and SelectableRow, status checkbox and chips
│   ├── BrowserChrome.swift    the browser column, headers, context filter, empty states, hairline
│   └── ArrowKeySelection.swift
├── Document/
│   ├── DocumentPane.swift     breadcrumb bar and Live/Source toggle over the document
│   ├── LiveDocumentView.swift a task in Live mode: title, properties, body, footer
│   ├── ProjectDocumentView.swift  a project's page with its linked-tasks table (status, dates and title edited in place)
│   ├── PropertyChips.swift    the properties as chips (PropertyChipRow), and the line under them
│   ├── PropertyPickers.swift  the status and project menus the chips open
│   ├── CalendarPicker.swift   the date chips' calendar
│   ├── FileInspector.swift    beside the Source editor
│   └── DocumentBanner.swift   outside-change choices
├── Editor/
│   ├── LiveEditor.swift       the only file that imports TaDaMarkdown
│   ├── Autocomplete.swift     the Live editor's Autocomplete switches
│   ├── InlineCheckbox.swift   checkbox drawing for the editor and task rows
│   ├── SourceTextView.swift   Source mode (NSTextView, line numbers)
│   ├── SlashMenu.swift
│   ├── CheckboxMenu.swift
│   ├── CalloutMenu.swift
│   ├── CalloutIcon.swift      callout icons and tints
│   └── AddSubtask.swift
├── iOS/                       the iPhone app (see iPhone below)
└── Shared/                    LocalDate display formats and month grids; PopupMenu (the panel and list the slash, checkbox, callout, file and property menus share); FileMenu (right-click on a project or task); TaskDrag (task rows dragged as files onto the sidebar or into other apps, and ⇧⌘M's, ⌘S's and ⌘D's menus under a row); Buttons (the text button style and segmented control); InlineTitleField (a title renamed in place)

Packages/TaDaCore/Sources/TaDaCore/
├── Model/      Item, Status, LocalDate, WikiLink, Checkbox, CalloutType
├── Parsing/    FrontmatterSplitter, PropertyReader, BodyScanner, CheckboxSyntax, SourceHighlighter
├── Writing/    Lines, FrontmatterEditor, ChecklistEditor, Completion, NewFile, FileNaming, SubtaskLine, SlashCommand
├── Index/      VaultIndex, Queries
└── Storage/    Vault, Trash, CoordinatedFileIO, FilePresenter, VaultWatcher, Conflicts

Packages/TaDaCore/Sources/TaDaCoreTesting/   GeneratedVault: test data for TaDaCoreTests; TaDaTests compiles the file too
```

TaDaCore has one test file per source file in `Tests/TaDaCoreTests`, with fixtures in `Fixtures/` (`DesignVault/` is the design's data). TaDaTests covers AppModel, OpenDocument, outside changes, the Source editor, keyboard handling, design renders and UI timings. Its suites set up their files with `TestFolder`, which removes them when each test ends, and their settings in memory with `TestSettings`, so tests write no settings files. TaDaUITests holds keyboard smoke tests.

## Runtime

- **Launch**: resolve the folder's security-scoped bookmark, scan it recursively off the main actor, parse every file into a `VaultIndex`. A change to a file patches only that item's entries in the index's title and link maps. `AppModel` works out the Today, Loose and Upcoming lists and the active projects from the index's `Queries` (which take an injected `today`) once per change, and views read those; a refresh applies all its changed files as one change. Each query applies a per-item test (`isInToday`, `upcomingEntries(of:after:)`, `isLoose`), which `FileInspector` uses for one file, and `progress(of:)` counts any project's tasks.
- **Editing**: `OpenDocument` holds the selected file's whole text. Typing, property edits and checkbox clicks change that text, which is reparsed into the index. It saves 600 ms after the last change, and also before switching files, when the app deactivates and on quit (on iOS, on entering the background, under a background task, with the same unsaved-edits copy). Files load one at a time: each selection waits for the previous load, which is skipped if it hasn't started. `AppModel` does its file work off the main actor through `run`. Quitting, including by closing the window, waits for the save: `AppDelegate.applicationShouldTerminate` returns `.terminateLater`. A checkbox click in a row whose file isn't open does a coordinated read, a surgical edit and an atomic write.
- **Saving** is guarded: Ta Da writes only if the file still holds the text it last read or wrote.
- **Trash**: deleting moves a file into `.trash/` in the folder (created when needed); a project takes its linked tasks. `AppModel.trash` lists the Ta Da files there, reloaded on each refresh. Restoring moves files to `tasks/` or `projects/` (a project brings its trashed tasks, relinked if its name changed); Delete Forever and Empty Trash move them to the Mac's Trash. The rules are in `docs/file-format.md`.
- **Outside changes**: `VaultWatcher` (FSEvents on the Mac; on iOS, file coordination on the folder) and app activation both trigger `refresh()`, which compares modification dates with the last scan and reparses only changed files. The open document reloads if it has no unsaved edits. With unsaved edits, `DocumentBanner` offers keep mine / use the file on disk, save again / discard after a deletion, or keep this / use the other iCloud version (`Conflicts` writes the file, marks the conflict resolved and removes the other versions in one coordinated write). Leaving the file or quitting with a choice still open writes the edits to `<title> (unsaved edits).md` beside it. The open file is presented to file coordination (`FilePresenter`): another app's coordinated read or merge, iCloud Drive's uploads among them, first saves the edits, and a coordinated move or rename (Finder, iCloud) is followed. A rename without coordination (Obsidian, Terminal, git) shows as a deletion. On iOS, files iCloud Drive hasn't downloaded are hidden `.Name.md.icloud` placeholders; opening the folder and each refresh ask for them (`Vault.downloadPlaceholders()`), and each joins the index once it arrives.

## Themes

A theme set pairs a light and a dark scheme. `AppModel.theme` is the set's dark scheme when the appearance is Dark, or System while macOS is dark (`systemIsDark`, from `NSApp.effectiveAppearance`, observed with KVO), otherwise its light scheme. With a scheme per appearance on, `lightScheme` and `darkScheme` replace the set's pair. Each window's appearance follows the shown scheme (`preferredColorScheme`), so a dark scheme in light mode (Dracula) still gets dark controls, context menus, alerts and popup menus; menus in the menu bar follow macOS. All five settings persist in `UserDefaults`.

## Window

`NavigationSplitView { SidebarView } detail: { WorkspaceView }`. Settings (⌘, or the sidebar's Settings row) is the `Settings` scene: `SettingsView`, 900×640, with Vault, Themes and Editor pages. The workspace shows:

- Today, Loose tasks and a project's tasks: the browser list beside `DocumentPane`.
- Upcoming: the agenda beside the month calendar when nothing is selected, otherwise the agenda beside `DocumentPane`.
- A project's own file: `DocumentPane` (with `ProjectDocumentView`) across the workspace.
- Search: `SearchResultsView` beside `DocumentPane`.
- Trash: `TrashView` across the workspace.
- Source mode: `DocumentPane` with the Source editor and `FileInspector` across the workspace, until the selection clears.

A right-click (or control-click) on a sidebar project or a task row in any list opens `FileMenu`: a compact themed panel at the pointer, with the row ringed in `accent`. It offers Move (tasks), Schedule, Set Deadline…, Reveal in Finder and Delete, or Restore, Reveal in Finder and Delete Forever in Trash. A right-click on a picked file acts on every picked file. Move opens the project menu, and Schedule and Set Deadline… the due date's or deadline's calendar, at the pointer in its place, with the row still ringed. While open it takes ↑↓, ↵ and esc.

Moving tasks to a project: the file menu's Move, ⇧⌘M and dragging all act on `AppModel.moveTargets(for:)`, the right-clicked or dragged row (every picked task when it's one of them) or, for ⇧⌘M, the picked tasks or the open one, in list order and without projects. ⇧⌘M sets `AppModel.propertyMenuRequest`, and the open task's project chip, or else the first picked row (`.taskDrag`), opens the project menu under itself. Task rows in every list but Trash are draggable (`.taskDrag`) as `TaskFile`s, their file URLs, in `WorkspaceView`'s drag container (`.taskDragContainer`), which drags every picked task when a picked row is dragged and lets other apps only copy; the sidebar's projects, Loose tasks and Today take them (`.taskDrop`), finding the tasks with `Vault.path(of:)`, linking them to the project with `AppModel.setProject(_:of:)`, emptying their project, or making them due today with `AppModel.makeDueToday(_:)`. Tasks already there aren't written.

Setting dates: the file menu's Schedule and Set Deadline…, ⌘S and ⌘D act on `AppModel.dateTargets(for:)`, the same files as a move but with projects. ⌘S and ⌘D set `AppModel.propertyMenuRequest`, and the open file's due date or deadline chip, or else the first picked row, opens the calendar under itself. For several files the calendar fills a date, and shows the other date's dot, only when they all agree; `AppModel.setDate(_:to:of:)` writes the files whose date changes.

Browser lists share their selection: each registers its rows with `.arrowKeySelection(model, paths:, allowsMultipleSelection:)` (the lists beside the document through `BrowserColumn`, which also sets their header and padding), and rows show `model.isSelected(_:)`, call `model.click(_:)` and add `.fileMenu`. Every list allows several (Search picks tasks only, since a project opens its page): shift-click picks a range and ⌘-click adds or removes a row (`AppModel.multiSelection`, or `trashSelection` in Trash). The document pane shows "N tasks selected", and Upcoming keeps its agenda column while tasks are picked. In Trash a plain click picks one file. The list keys go to a `ListKeyView` behind each list, an AppKit responder that takes the keyboard when the list appears, when nothing has it and when a row is picked, but never from a text view, or for a new file whose title is about to take it.

A project's browser folds its Open and Completed groups from their headers. `AppModel.foldedGroups` keeps the folded ones per project path in the settings and follows a rename; a folded group's rows leave the arrow-key list. Its header shows the project's chips through `PropertyChipRow`, and its title and the project page table's titles are `InlineTitleField`s, which rename with `AppModel.rename(_:to:)`. The table's New linked task calls `AppModel.newLinkedTask(in:)`, which sets `titleFocus` so the new row's title starts editing without opening the task.

## iPhone

`PhoneRootView` is a `TabView` of Today, Upcoming, Loose, Projects and Other, each a `NavigationStack` whose path lives in `PhoneNavigation` (`@Observable`, in the environment), with the date and project sheets over them.

- `PhoneNavigation.swift`: tabs, routes (file, project, settings section, trash), the sheet, picked rows and `Haptic`, played through `.sensoryFeedback` when Settings ▸ Haptics is on (`AppModel.haptics`).
- `PhoneList.swift`: what every list shares: the title and subtitle at the top of the list (the navigation bar shows the title once it scrolls away), pull to search, the floating + and the "…" menu with Select. A tap on the list with the search field open and empty closes search; a screen pushed over the list keeps its search, and switching tab resets it. Only the list on screen sets `PhoneNavigation.pickable`, and picked rows it stops showing are unpicked.
- `PhoneSearchField.swift`: pull to search. `ListSearch` is a list's state (pull distance, open, query); each tab's `PhoneSearchStack` draws the field of the list on screen (registered through `SearchHost`) above the navigation bar, so it takes taps. Past 60 pt the pull's grey pill snaps into an accent dot with a tap; letting go there grows the dot into the field in the bar's row, with a close button in place of the "…", and the keyboard comes when the field lands. It searches every file.
- `PhoneScreens.swift`: Today and Loose (context pills, grouped by project), Upcoming (a week strip over day headers), Projects (Completed folds) and a project's tasks (Open and Completed fold, with `AppModel.isFolded`).
- `PhoneRows.swift`: task and project rows. Press and hold opens `PhoneFileMenu`: Complete, Today and Tomorrow, Status, Schedule…, Set Deadline…, Move to Project…, Share…, Select and Move to Trash.
- `PhoneFileScreen.swift`: a file pushed from any list. Title (`TitleField`), chips that open the sheets, the body in `BodyEditor` or the whole file in a Source `TextEditor`, and a project's linked tasks. The top bar has the Live/Source toggle and a More menu (Done while the keyboard is up); the bottom toolbar has Complete, Schedule, Deadline, Move, Share and Trash. It sets `model.selection` while shown.
- `PhoneSheets.swift`: `PhoneDateSheet` (due date or deadline, quick days and a month grid) and `PhoneProjectSheet` (search, No project, New Project…), for one file or the picked ones. Each writes on ✓.
- `PhonePicking.swift`: swipe to pick. A `UIPanGestureRecognizer` that begins only for a leftward, mostly horizontal pan slides the row over a tick; letting go past 64 pt picks the row, or unpicks it while picking (unpicking the last row ends picking), and the row springs back. While picking, Select All, the count and Done replace the navigation bar, and the action bar (Complete, Schedule, Move, More, Delete), a glass capsule in the tab bar's place, replaces the tab bar.
- `PhoneOther.swift`: Other (Trash and Settings rows, the sync line), Settings (Vault, Themes, Editor Autocomplete, Haptics), Trash (pick, restore, empty) and onboarding.

On iOS the live editor (`LiveEditor`) uses 17 pt text; press and hold on a checkbox or callout title opens `CheckboxMenu` or `CalloutMenu` as popovers, with a medium tap. A typed `/` stays text: there is no slash menu. Its keyboard bar (`EditorKeyboardBar`, the editor's `inputAccessoryView`) has subtask, heading, bold, italic, code, wikilink, callout, outdent, indent and hide keyboard (with a light tap). The wikilink button types `[[` through `SlashCommandProxy.type(_:)`, so Autocomplete's switches apply as they do to typing; with Wikilinks on it wraps a selection, and right before `]]` it steps over it. The editor scrolls the caret (and the scroll view it sits in) to stay 12 pt above the keyboard bar as it moves or the text changes.

## Editors

- **Live**: `LiveEditor` runs the engine with `.fitsContent` height inside a SwiftUI `ScrollView`, between the title and properties above and the footer (and a project's linked-tasks table) below. The engine's binding reads and writes only the body; it is spliced back after the frontmatter block. Theme tokens map to `MarkdownEditorTheme`; `TaskCheckboxStyle` takes its strikes and click transitions from `Checkbox.State` and its tints from `Theme.checkboxTint`, and `InlineCheckbox` draws the boxes; wikilinks resolve by `WikiLink.title` against the index's `titles`.
- **Source**: `SourceTextView`, a TextKit 1 `NSTextView` with a line-number ruler and a current-line highlight. It edits the whole file, frontmatter included. `SourceHighlighter` (in TaDaCore, on `FrontmatterSplitter`, `WikiLink` and `LocalDate`) colours it by role (key `accent`, value `fg`, string `done`, date `due`, heading `strong`, punctuation and checkbox `muted`, done checkbox `done`, link `link`) and reruns over the whole file after each edit.
- **Autocomplete**: `AppModel.autocomplete` holds Settings ▸ Editor's switches (Brackets, Text formatting, Wikilinks and embeds, all on by default), kept in the settings as one dictionary. `LiveEditor` passes them to the engine's `ListStyle`. A typed `(`, `[` or `{`, a formatting marker (`*`, `**`, `_`, `__`, `~~`, `==`, `` ` ``) or `[[` adds its closer, and typing that closer steps over it while the caret stays between the pair. Markers pair only between words and outside code; a single `*` at a line's start stays a bullet, a space straight after a marker removes its closer, and a run past the longest marker (`***`, ```` ``` ````, `~~~`, `===`) stays unpaired.
- **Slash menu**: `/` in the Live editor opens `SlashMenu`, a themed list of `SlashCommand` formats in a `PopupMenu`: a borderless panel that places itself under its anchor and closes on a click elsewhere or a scroll. The checkbox, file and property menus use it too.
- **Checkbox menu**: a right-click on a Live editor checkbox opens `CheckboxMenu`, the same kind of panel listing every marker (subtasks, then icons) with its box drawn by `InlineCheckbox`. While open it takes ↑↓, ↵ and esc.
- **Callouts**: `LiveEditor` gives the engine a `CalloutStyle`, so `> [!type]` quotes draw as panels (types and aliases from `CalloutType`, icons from `CalloutIcon`). A click on a foldable callout's icon, chevron or the row past its title folds or opens it on screen only; the file keeps its `+` or `-`, and a folded body shows while the caret is in it. A right-click on a title line opens `CalloutMenu` under the icon, with the callout ringed: picking a type or fold edits only the text between `[!` and `]` or the character after it, as one undo step. While open it takes ↑↓, ↵ and esc.
- **Properties**: `PropertyChips` shows status, project (tasks only), dueDate and deadline as chips under the title, and the type, createdDate and completedDate in a line below. A chip opens its picker under it through `PropertyPicker`. Status and project are `PopupMenu`s: they take ↑↓, ↵, esc and typed letters, and the project menu's search field takes the keyboard. For several tasks the project menu ticks a row only when they all agree. New project creates the file and links the tasks with `AppModel.newProject(named:linking:)`. A date opens `CalendarPicker`, a month in a `PopupPanel` that takes ←↑↓→, ↵ and esc. VoiceOver gets each chip's choices as actions on the chip.

## Shortcuts

| Keys | Action |
| --- | --- |
| ⌘N / ⇧⌘N | New task / New project |
| File ▸ Reveal in Finder (no keys) | Select the picked or open files in Finder (`AppModel.picked`); the file menu has it too |
| ⌥⌘F | Search files |
| ⌘1 / ⌘2 / ⌘3 / ⌘4 | Today / Upcoming / Loose tasks / Trash |
| ⌘E | Live / Source |
| ⌘, | Settings |
| ⌘K | Complete or reopen the selected task |
| ⇧⌘M | Move the open task (project menu under its project chip) or the picked tasks (under the first) to a project. Off in Source mode |
| ⌘S / ⌘D | Set the due date / deadline of the open file (calendar under its chip) or the picked tasks (under the first). Off in Source mode |
| ⌘L | Make the caret's line a subtask, or complete (reopen) the subtask it's on, as one undo step. Off unless the Live or Source editor has the keyboard (its `editor` focused value) |
| ↑ / ↓, Escape | Move through the list, clear the selection, while the list has the keyboard |
| ⌫ or ⌘⌫ | Move the selected file, or the picked tasks, to the trash, while the list has the keyboard |
| ⌘⌫ / ⌥⌘⌫ in Trash | Restore / delete forever the picked files |
