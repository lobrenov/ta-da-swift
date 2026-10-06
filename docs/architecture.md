# Ta Da architecture

How the app is built. The file format and writing rules are in `docs/file-format.md`; the design system is in `docs/design/design-framework.md`.

## Layers

- **TaDaCore** (`Packages/TaDaCore`, local package): the model, parsing, surgical writes, the index, queries and storage. Foundation, swift-markdown 0.9.0 and Yams 6.2.2 only; no UI.
- **TaDa** (`TaDa/`, app target): SwiftUI views over an `@Observable` `AppModel`. macOS 26 minimum, App Sandbox with user-selected read/write.
- **MarkdownEngine** (`libs/swift-markdown-engine`): our fork of swift-markdown-engine 0.13.0, the Live editor. Changes are listed in its `FORK.md`.

The workspace `TaDa.xcworkspace` holds the project and TaDaCore; the test plan `TaDa.xctestplan` runs TaDaTests, TaDaCoreTests and TaDaUITests.

## Files

```
TaDa/
├── TaDaApp.swift              one main window plus Settings, sharing one AppModel; AppDelegate owns it and handles activation, quitting and day changes
├── ContentView.swift          folder picker until a folder is open, then sidebar + workspace; applies the theme
├── AppModel.swift             root state: folder, index, domain, selection, open document, theme set and appearance; refresh, save, outside-change handling
├── OpenDocument.swift         the selected file's whole text; edits reparse it
├── Commands.swift             menu commands and shortcuts
├── UITestingLaunch.swift      the `-uiTesting` launch: throwaway settings and folder
├── Theme/                     Theme (15 colour tokens + isDark), ThemeSet, Appearance, the 15 bundled schemes and 8 sets;
│                              themed(by:) sets \.theme and NSApp.appearance and follows the Mac's appearance
├── Onboarding/                FolderPickerView
├── Settings/                  SettingsView (nav and shared parts), VaultSettingsView, ThemeSettingsView
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
│   ├── ProjectDocumentView.swift  a project's page with its linked-tasks table
│   ├── PropertyChips.swift    the properties as chips, and the line under them
│   ├── PropertyPickers.swift  the status and project menus the chips open
│   ├── CalendarPicker.swift   the date chips' calendar
│   ├── FileInspector.swift    beside the Source editor
│   └── DocumentBanner.swift   outside-change choices
├── Editor/
│   ├── LiveEditor.swift       the only file that imports MarkdownEngine
│   ├── InlineCheckbox.swift   checkbox drawing for the editor and task rows
│   ├── SourceTextView.swift   Source mode (NSTextView, line numbers)
│   ├── SlashMenu.swift
│   ├── CheckboxMenu.swift
│   └── AddSubtask.swift
└── Shared/                    LocalDate display formats and month grids; PopupMenu (the panel and list the slash, checkbox, file and property menus share); FileMenu (right-click on a project or task); Buttons (the text button style and segmented control)

Packages/TaDaCore/Sources/TaDaCore/
├── Model/      Item, Status, LocalDate, WikiLink, Checkbox
├── Parsing/    FrontmatterSplitter, PropertyReader, BodyScanner, CheckboxSyntax, SourceHighlighter
├── Writing/    Lines, FrontmatterEditor, ChecklistEditor, Completion, NewFile, FileNaming, SubtaskLine, SlashCommand
├── Index/      VaultIndex, Queries
├── Storage/    Vault, Trash, CoordinatedFileIO, FilePresenter, VaultWatcher, Conflicts
└── Testing/    GeneratedVault
```

TaDaCore has one test file per source file in `Tests/TaDaCoreTests`, with fixtures in `Fixtures/` (`DesignVault/` is the design's data). TaDaTests covers AppModel, OpenDocument, outside changes, the Source editor, keyboard handling, design renders and UI timings. TaDaUITests holds keyboard smoke tests.

## Runtime

- **Launch**: resolve the folder's security-scoped bookmark, scan it recursively off the main actor, parse every file into a `VaultIndex`. A change to a file patches only that item's entries in the index's title and link maps. `AppModel` works out the Today, Loose and Upcoming lists and the active projects from the index's `Queries` (which take an injected `today`) once per change, and views read those; a refresh applies all its changed files as one change. Each query applies a per-item test (`isInToday`, `upcomingEntries(of:after:)`, `isLoose`), which `FileInspector` uses for one file, and `progress(of:)` counts any project's tasks.
- **Editing**: `OpenDocument` holds the selected file's whole text. Typing, property edits and checkbox clicks change that text, which is reparsed into the index. It saves 600 ms after the last change, and also before switching files, when the app deactivates and on quit. Files load one at a time: each selection waits for the previous load, which is skipped if it hasn't started. `AppModel` does its file work off the main actor through `run`. Quitting, including by closing the window, waits for the save: `AppDelegate.applicationShouldTerminate` returns `.terminateLater`. A checkbox click in a row whose file isn't open does a coordinated read, a surgical edit and an atomic write.
- **Saving** is guarded: Ta Da writes only if the file still holds the text it last read or wrote.
- **Trash**: deleting moves a file into `.trash/` in the folder (created when needed); a project takes its linked tasks. `AppModel.trash` lists the Ta Da files there, reloaded on each refresh. Restoring moves files to `tasks/` or `projects/` (a project brings its trashed tasks, relinked if its name changed); Delete Forever and Empty Trash move them to the Mac's Trash. The rules are in `docs/file-format.md`.
- **Outside changes**: `VaultWatcher` (FSEvents) and app activation both trigger `refresh()`, which compares modification dates with the last scan and reparses only changed files. The open document reloads if it has no unsaved edits. With unsaved edits, `DocumentBanner` offers keep mine / use the file on disk, save again / discard after a deletion, or keep this / use the other iCloud version (`Conflicts` writes the file, marks the conflict resolved and removes the other versions in one coordinated write). Leaving the file or quitting with a choice still open writes the edits to `<title> (unsaved edits).md` beside it. The open file is presented to file coordination (`FilePresenter`): another app's coordinated read or merge, iCloud Drive's uploads among them, first saves the edits, and a coordinated move or rename (Finder, iCloud) is followed. A rename without coordination (Obsidian, Terminal, git) shows as a deletion.

## Themes

A theme set pairs a light and a dark scheme. `AppModel.theme` is the set's dark scheme when the appearance is Dark, or System while macOS is dark (`systemIsDark`, from `NSApp.effectiveAppearance`, observed with KVO), otherwise its light scheme. With a scheme per appearance on, `lightScheme` and `darkScheme` replace the set's pair. Each window's appearance follows the shown scheme (`preferredColorScheme`), so a dark scheme in light mode (Dracula) still gets dark controls, context menus, alerts and popup menus; menus in the menu bar follow macOS. All five settings persist in `UserDefaults`.

## Window

`NavigationSplitView { SidebarView } detail: { WorkspaceView }`. Settings (⌘, or the sidebar's Settings row) is the `Settings` scene: `SettingsView`, 900×640, with Vault and Themes pages. The workspace shows:

- Today, Loose tasks and a project's tasks: the browser list beside `DocumentPane`.
- Upcoming: the agenda beside the month calendar when nothing is selected, otherwise the agenda beside `DocumentPane`.
- A project's own file: `DocumentPane` (with `ProjectDocumentView`) across the workspace.
- Search: `SearchResultsView` beside `DocumentPane`.
- Trash: `TrashView` across the workspace.
- Source mode: `DocumentPane` with the Source editor and `FileInspector` across the workspace, until the selection clears.

A right-click (or control-click) on a sidebar project or a task row in any list opens `FileMenu`: a compact themed panel at the pointer, with the row ringed in `accent`. It offers Delete, or Restore and Delete Forever in Trash. A right-click on a picked file acts on every picked file. While open it takes ↑↓, ↵ and esc.

Browser lists share their selection: each registers its rows with `.arrowKeySelection(model, paths:, allowsMultipleSelection:)` (the lists beside the document through `BrowserColumn`, which also sets their header and padding), and rows show `model.isSelected(_:)`, call `model.click(_:)` and add `.fileMenu`. Every list allows several (Search picks tasks only, since a project opens its page): shift-click picks a range and ⌘-click adds or removes a row (`AppModel.multiSelection`, or `trashSelection` in Trash). The document pane shows "N tasks selected", and Upcoming keeps its agenda column while tasks are picked. In Trash a plain click picks one file. The list keys go to a `ListKeyView` behind each list, an AppKit responder that takes the keyboard when the list appears, when nothing has it and when a row is picked, but never from a text view, or for a new file whose title is about to take it.

## Editors

- **Live**: `LiveEditor` runs the engine with `.fitsContent` height inside a SwiftUI `ScrollView`, between the title and properties above and the footer (and a project's linked-tasks table) below. The engine's binding reads and writes only the body; it is spliced back after the frontmatter block. Theme tokens map to `MarkdownEditorTheme`; `TaskCheckboxStyle` takes its strikes and click transitions from `Checkbox.State` and its tints from `Theme.checkboxTint`, and `InlineCheckbox` draws the boxes; wikilinks resolve by `WikiLink.title` against the index's `titles`.
- **Source**: `SourceTextView`, a TextKit 1 `NSTextView` with a line-number ruler and a current-line highlight. It edits the whole file, frontmatter included. `SourceHighlighter` (in TaDaCore, on `FrontmatterSplitter`, `WikiLink` and `LocalDate`) colours it by role (key `accent`, value `fg`, string `done`, date `due`, heading `strong`, punctuation and checkbox `muted`, done checkbox `done`, link `link`) and reruns over the whole file after each edit.
- **Slash menu**: `/` in the Live editor opens `SlashMenu`, a themed list of `SlashCommand` formats in a `PopupMenu`: a borderless panel that places itself under its anchor and closes on a click elsewhere or a scroll. The checkbox, file and property menus use it too.
- **Checkbox menu**: a right-click on a Live editor checkbox opens `CheckboxMenu`, the same kind of panel listing every marker (subtasks, then icons) with its box drawn by `InlineCheckbox`. While open it takes ↑↓, ↵ and esc.
- **Properties**: `PropertyChips` shows status, project (tasks only), dueDate and deadline as chips under the title, and the type, createdDate and completedDate in a line below. A chip opens its picker under it through `PropertyPicker`. Status and project are `PopupMenu`s: they take ↑↓, ↵, esc and typed letters, and the project menu's search field takes the keyboard. New project creates the file and links the task with `AppModel.newProject(named:linking:)`. A date opens `CalendarPicker`, a month in a `PopupPanel` that takes ←↑↓→, ↵ and esc. VoiceOver gets each chip's choices as actions on the chip.

## Shortcuts

| Keys | Action |
| --- | --- |
| ⌘N / ⇧⌘N | New task / New project |
| ⌥⌘F | Search files |
| ⌘1 / ⌘2 / ⌘3 / ⌘4 | Today / Upcoming / Loose tasks / Trash |
| ⌘E | Live / Source |
| ⌘, | Settings |
| ⌘K | Complete or reopen the selected task |
| ⌘L | Make the caret's line a subtask, or complete (reopen) the subtask it's on, as one undo step. Off unless the Live or Source editor has the keyboard (its `editor` focused value) |
| ↑ / ↓, Escape | Move through the list, clear the selection, while the list has the keyboard |
| ⌫ or ⌘⌫ | Move the selected file, or the picked tasks, to the trash, while the list has the keyboard |
| ⌘⌫ / ⌥⌘⌫ in Trash | Restore / delete forever the picked files |
