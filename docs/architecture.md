# Ta Da architecture

How the app is built. The file format and writing rules are in `docs/file-format.md`; the design system is in `docs/design/design-framework.md`.

## Layers

- **TaDaCore** (`Packages/TaDaCore`, local package): the model, parsing, surgical writes, the index, queries and storage. Foundation, swift-markdown 0.9.0 and Yams 6.2.2 only; no UI.
- **TaDa** (`TaDa/`, app target): SwiftUI views over an `@Observable` `AppModel`. macOS 27 minimum, App Sandbox with user-selected read/write.
- **MarkdownEngine** (`libs/swift-markdown-engine`): our fork of swift-markdown-engine 0.13.0, the Live editor. Changes are listed in its `FORK.md`.

The workspace `TaDa.xcworkspace` holds the project and TaDaCore; the test plan `TaDa.xctestplan` runs TaDaTests, TaDaCoreTests and TaDaUITests.

## Files

```
TaDa/
├── TaDaApp.swift              one main window plus Settings, sharing one AppModel
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
│   ├── TaskRow.swift          the row, status checkbox and chips
│   ├── BrowserChrome.swift    headers, context filter, empty states, hairline
│   └── ArrowKeySelection.swift
├── Document/
│   ├── DocumentPane.swift     breadcrumb bar and Live/Source toggle over the document
│   ├── LiveDocumentView.swift a task in Live mode: title, properties, body, footer
│   ├── ProjectDocumentView.swift  a project's page with its linked-tasks table
│   ├── PropertyTable.swift
│   ├── FileInspector.swift    beside the Source editor
│   └── DocumentBanner.swift   outside-change choices
├── Editor/
│   ├── LiveEditor.swift       the only file that imports MarkdownEngine
│   ├── InlineCheckbox.swift   checkbox drawing for the editor and task rows
│   ├── SourceTextView.swift   Source mode (NSTextView, line numbers)
│   ├── SourceHighlighter.swift
│   ├── SlashMenu.swift
│   ├── CheckboxMenu.swift
│   └── AddSubtask.swift
└── Shared/                    LocalDate display formats

Packages/TaDaCore/Sources/TaDaCore/
├── Model/      Item, Status, LocalDate, WikiLink, Checkbox
├── Parsing/    FrontmatterSplitter, PropertyReader, BodyScanner
├── Writing/    Lines, FrontmatterEditor, ChecklistEditor, Completion, NewFile, FileNaming, SubtaskLine, SlashCommand
├── Index/      VaultIndex, Queries
├── Storage/    Vault, CoordinatedFileIO, VaultWatcher, Conflicts
└── Testing/    GeneratedVault
```

TaDaCore has one test file per source file in `Tests/TaDaCoreTests`, with fixtures in `Fixtures/` (`DesignVault/` is the design's data). TaDaTests covers AppModel, OpenDocument, outside changes, the Source editor, keyboard handling, design renders and UI timings. TaDaUITests holds keyboard smoke tests.

## Runtime

- **Launch**: resolve the folder's security-scoped bookmark, scan it recursively off the main actor, parse every file into a `VaultIndex`. Views are functions of the index's `Queries`, which take an injected `today`.
- **Editing**: `OpenDocument` holds the selected file's whole text. Typing, property edits and checkbox clicks change that text, which is reparsed into the index. It saves 600 ms after the last change, and also before switching files, when the app deactivates and on quit. A checkbox click in a row whose file isn't open does a coordinated read, a surgical edit and an atomic write.
- **Saving** is guarded: Ta Da writes only if the file still holds the text it last read or wrote.
- **Outside changes**: `VaultWatcher` (FSEvents) and app activation both trigger `refresh()`, which compares modification dates with the last scan and reparses only changed files. The open document reloads if it has no unsaved edits. With unsaved edits, `DocumentBanner` offers keep mine / use the file on disk, save again / discard after a deletion, or keep this / use the other iCloud version. Leaving the file or quitting with a choice still open writes the edits to `<title> (unsaved edits).md` beside it.

## Themes

A theme set pairs a light and a dark scheme. `AppModel.theme` is the set's dark scheme when the appearance is Dark, or System while macOS is dark (`systemIsDark`, read from the global `AppleInterfaceStyle` default and updated on `AppleInterfaceThemeChangedNotification`), otherwise its light scheme. With a scheme per appearance on, `lightScheme` and `darkScheme` replace the set's pair. `NSApp.appearance` follows the shown scheme, so a dark scheme in light mode (Dracula) still gets dark menus. All five settings persist in `UserDefaults`.

## Window

`NavigationSplitView { SidebarView } detail: { WorkspaceView }`. Settings (⌘, or the sidebar's Settings row) is the `Settings` scene: `SettingsView`, 900×640, with Vault and Themes pages. The workspace shows:

- Today, Loose tasks and a project's tasks: the browser list beside `DocumentPane`.
- Upcoming: the agenda beside the month calendar when nothing is selected, otherwise the agenda beside `DocumentPane`.
- A project's own file: `DocumentPane` (with `ProjectDocumentView`) across the workspace.
- Search: `SearchResultsView` beside `DocumentPane`.
- Source mode: `DocumentPane` with the Source editor and `FileInspector` across the workspace, until the selection clears.

## Editors

- **Live**: `LiveEditor` runs the engine with `.fitsContent` height inside a SwiftUI `ScrollView`, between the title and properties above and the footer (and a project's linked-tasks table) below. The engine's binding reads and writes only the body; it is spliced back after the frontmatter block. Theme tokens map to `MarkdownEditorTheme`; `TaskCheckboxStyle` sets checkbox tints and click transitions, and `InlineCheckbox` draws the boxes; wikilinks resolve by title.
- **Source**: `SourceTextView`, a TextKit 1 `NSTextView` with a line-number ruler and a current-line highlight. It edits the whole file, frontmatter included. `SourceHighlighter` colours it by role (key `accent`, value `fg`, string `done`, date `due`, heading `strong`, punctuation and checkbox `muted`, done checkbox `done`, link `link`) and reruns over the whole file after each edit.
- **Slash menu**: `/` in the Live editor opens `SlashMenu`, a themed list of `SlashCommand` formats in a borderless panel.
- **Checkbox menu**: a right-click on a Live editor checkbox opens `CheckboxMenu`, the same kind of panel listing every marker (subtasks, then icons) with its box drawn by `InlineCheckbox`. While open it takes ↑↓, ↵ and esc.

## Shortcuts

| Keys | Action |
| --- | --- |
| ⌘N / ⇧⌘N | New task / New project |
| ⌥⌘F | Search files |
| ⌘1 / ⌘2 / ⌘3 | Today / Upcoming / Loose tasks |
| ⌘E | Live / Source |
| ⌘, | Settings |
| ⌘K | Complete or reopen the selected task |
| ⌘L | Make the caret's line a subtask, or complete (reopen) the subtask it's on, as one undo step |
| ↑ / ↓, Escape | Move through the list, clear the selection, while no text view has the keyboard (a key monitor on the main window) |
