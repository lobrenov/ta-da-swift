# Ta Da design framework

Mirrored by the Claude Design System artifact https://claude.ai/artifact/GkKXeVHXv9XMGMWWacPppz (last synced 2026-10-05, version 1791177167-fca9; it shows one colour scheme per theme set). This folder is the copy the repo follows: `tokens.json` holds the values, `components/<Name>/README.md` the component guidelines and `components/bundle.css` their reference CSS. [In the app](#in-the-app) maps each part to its Swift code, and [As built](#as-built) lists where the app differs from the guidance.

The app's screens, menus and states are mocked up on the Claude Design canvas https://claude.ai/artifact/A7c33hg9HUKz41u3wbki3V.

The design system for Ta Da, a Swift-native task manager where every task and project is a plain markdown file in iCloud Drive. The interface is quiet chrome around the files: neutral panes, one accent, and colour reserved for meaning. Every colour comes from an iTerm2 colour scheme, so the whole app rethemes from one file.

## Principles

1. **The file is the truth.** The UI shows what is in the markdown and frontmatter and nothing it cannot write back. YAML keys appear exactly as written (`dueDate`, `deadline`) in the `mono` family.
2. **Colour means something.** Neutrals carry the layout. Hue appears only as a signal: a status, a date kind, a link. If a colour is decorative, remove it.
3. **Signals live on glyphs, not text.** Status and date colours sit on checkboxes, dots and 12px icons; text stays `fg` or `muted`. This keeps every theme readable, light ones included.
4. **One accent per view.** `accent` marks the primary button, the caret and project progress. Nothing else competes with it.
5. **Calm density.** 32px rows, 13px UI text, hairline borders. No shadows inside the window (menus float above it and carry the only one), no cards for content that is already a list.

## Colour

Fifteen semantic tokens, defined for fifteen bundled iTerm2 schemes (values from iterm2colorschemes.com). The schemes pair into eight theme sets, each a light and a dark scheme: Ayu (Ayu Light, Ayu Mirage), Tomorrow (Tomorrow, Tomorrow Night), Solarized (Light, Dark), Dracula (Dracula for both), Nord (Nord Light, Nord), Gruvbox (Light, Dark), TokyoNight (TokyoNight Day, TokyoNight) and Catppuccin (Latte, Mocha). Ta Da shows the set's light or dark scheme with the macOS appearance, or always one of them when the appearance is set to Light or Dark. Tomorrow is the default set.

| Token | Role | iTerm2 source |
| --- | --- | --- |
| `bg` | Window and editor ground | Background Color |
| `side` | Sidebar, title bars, panel headers | Background, darker |
| `surface` | Selection, active item, pressed chip | Selection Color, else Background + 16% Foreground |
| `border` | 1px hairlines | Background + 10% Foreground |
| `code` | Raw markdown lines, inputs | Background + 5% Foreground |
| `fg` | Body text | Foreground Color, lifted to 5.5:1 |
| `strong` | Headings, selected titles | Foreground, 45% toward black or white |
| `muted` | Meta, keys, done titles | Ansi 8, lifted to 4.5:1 |
| `accent` | Primary action, progress, caret | Ansi 4 Blue |
| `due` | dueDate glyphs, Today star | Ansi 3 Yellow |
| `deadline` | deadline glyphs, destructive | Ansi 1 Red |
| `done` | Done status, Logbook | Ansi 2 Green |
| `doing` | Doing status | Ansi 6 Cyan |
| `blocked` | Blocked status | Red → Yellow, 50% |
| `link` | [[wikilinks]], project values | Ansi 5 Magenta |

Importing a new `.itermcolors` file fills these by the same mapping. When a scheme's Ansi 8 is too dim, `muted` is lifted until it passes 4.5:1 on `bg`; `fg` is lifted to 5.5:1 the same way (Solarized Light, Solarized Dark, TokyoNight Day).

Contrast rules: text uses only `fg`, `strong` and `muted`. `due`, `deadline`, `done`, `doing`, `blocked` are for icons, dots, borders and fills; on light themes several fall below 4.5:1 as text. `accent` and `deadline` fills carry `bg`-coloured labels at 600 weight or more.

## Typography

Two families. `sans` is the system face (SF Pro on macOS), because Ta Da is a native app. `mono` is JetBrains Mono (Google Fonts) with SF Mono and Menlo as fallbacks, used for everything that is literally in the file: YAML keys, paths, checkbox syntax and Source mode.

- View titles (`title-view`, 26/32 bold) sit 44px below the window top with their domain icon at 24px.
- Task titles use `task` (13.5px); the meta line under them uses `meta` (11.5px, `muted`).
- The editor renders markdown at `body-editor` (14/23) and source at `source` (13.5/23), so toggling Live and Source does not reflow lines.
- Uppercase is only for `label` (11px, 600, 0.06em tracking): PROJECTS, TOKENS.

## Layout

- **Window.** Sidebar `size-sidebar` (240px) on `side`, then the browser pane `size-browser` (460px), then the editor filling the rest. Logbook, Trash and other archive views are single-pane: sidebar plus one pane with a 760px max content width and `space-10` (64px) padding.
- **Sidebar order.** Search, Today, Upcoming, Loose tasks, a 10px gap, Logbook, Trash, PROJECTS, then sync status, Settings (⌘,) and New task / New project at the bottom.
- **Settings window.** 900×640 on `bg` with a 46px `side` title bar. A 200px `side` nav (Vault in `accent`, Themes in `link`) beside the page: a `title-dialog` title, a `muted` line under it, then label-and-control rows (labels `muted`, 84–92px wide), bordered 10px panels and uppercase section labels.
- **Editor.** 46px toolbar (`size-titlebar`) with the file path as a mono breadcrumb and the Live/Source switch on the right. Then title, properties, a hairline, and the body.
- **Rhythm.** Rows 32px; gaps from the spacing scale (4, 6, 8, 10, 12, 16, 20, 28, 44, 64). Groups of rows are separated by a group header with a 1px `border` underline, not by cards.
- **Radius.** 4px checkboxes, 7px rows and controls, 10px panels and menus, 12px windows.
- **Scrollbars.** Thin, transparent track, `surface` thumb, `muted` on hover.

## Iconography

- 16px line icons on a 16-unit grid, 1.6 stroke, round caps and joins, `currentColor`. 12px in meta lines, 24px next to view titles. No emoji anywhere.
- Each domain has a fixed icon colour: Today `due` (filled star), Upcoming `deadline` (calendar), Loose tasks `accent` (tray), Logbook `done` (book with tick), Trash `muted` (bin). Projects use a progress pie in `accent`.
- Dates: calendar glyph in `due` for `dueDate`, flag in `deadline` for `deadline`. A task appears on both dates in Upcoming, tagged with the other one.

### Inline checkboxes

All checkbox states share the 16px box. 23 states follow the Alternative Checkboxes reference set plus Ta Da's own `[B]`:

| Syntax | Name | Token | Syntax | Name | Token |
| --- | --- | --- | --- | --- | --- |
| `[ ]` | To do | `muted` | `[l]` | Location | `link` |
| `[x]` | Done (filled) | `done` | `[b]` | Bookmark | `blocked` |
| `[/]` | Incomplete / Doing | `doing` | `[i]` | Information | `accent` |
| `[-]` | Cancelled | `muted` | `[S]` | Savings | `done` |
| `[B]` | Blocked (Ta Da) | `blocked` | `[I]` | Idea | `due` |
| `[>]` | Forwarded | `accent` | `[p]` | Pros | `done` |
| `[<]` | Scheduling | `due` | `[c]` | Cons | `deadline` |
| `[?]` | Question | `doing` | `[f]` | Fire | `blocked` |
| `[!]` | Important (filled) | `deadline` | `[k]` | Key | `due` |
| `[*]` | Star | `due` | `[w]` | Win | `due` |
| `["]` | Quote | `muted` | `[u]` / `[d]` | Up / Down | `done` / `deadline` |

Only Done and Important are filled boxes. Done and Cancelled strike their text through in `muted`.

## Writing

- Sentence case for labels and menus; title case only on buttons, as macOS does ("Log Now", "Empty Trash").
- Name things by what people see: "Loose tasks", "Logbook", "Trash", never "orphan files" or "archive directory". Folder names (`logbook/`, `.trash/`) appear in mono where the file location matters.
- Dates: "Today", "Tomorrow", "Tue 6 Oct" in rows; ISO `2026-10-06` in properties and source.
- Buttons state the result and counts update live: "Restore 2 Items". Confirmations say what is permanent and where: "Permanently delete 4 files from iCloud Drive?"

## Components

Plain CSS classes in `components/bundle.css`, prefixed `td-`, built on these tokens: Checkbox, TaskRow, SidebarItem, PropertyRow, Chip, Button, Menu. Each has guidelines in `components/<Name>/README.md`. In the Swift app they map to SwiftUI views; the classes here are the reference for spacing, states and colour roles.

## In the app

| Design | Swift |
| --- | --- |
| Colour tokens and themes | `Theme` (`TaDa/Theme/Theme.swift`), one `NSColor` property per token, read from the `\.theme` environment value. The fifteen schemes are `Theme.all` and the eight sets `ThemeSet.all` in `TaDa/Theme/BundledThemes.swift`, with the same values and order as `tokens.json`. `AppModel` picks the scheme from the set, the `Appearance` setting and the Mac's appearance; `themed(by:)` (`TaDa/Theme/Themed.swift`) applies it to a window. |
| Type, spacing, radius, size | Literal values in each view (`.font(.system(size: 13.5))`, `cornerRadius: 7`); there are no Swift constants for them. |
| Checkbox | `InlineCheckbox` in `TaDa/Editor/InlineCheckbox.swift` draws every box from the artboard's paths. `StatusCheckbox` in `TaDa/Browser/TaskRow.swift` uses it for task rows; `TaskCheckboxStyle` in `TaDa/Editor/LiveEditor.swift` for the editor (tints, strikes, clicks). |
| TaskRow | `TaskRow`, `TaskTitle`, `StatusLabel`, `Chip` and `DateChip` in `TaDa/Browser/TaskRow.swift`. Selection (click, shift- and ⌘-click, `is-selected`) is shared by every list through `model.click(_:)` and `model.isSelected(_:)` in `TaDa/Browser/ArrowKeySelection.swift` and `TaDa/AppModel.swift`. |
| SidebarItem | `SidebarRow` and `ProgressRing` in `TaDa/Sidebar/SidebarView.swift`. |
| PropertyRow | `PropertyTable` in `TaDa/Document/PropertyTable.swift`. |
| Chip (filter) | `ContextFilter` in `TaDa/Browser/BrowserChrome.swift`. |
| Button | `newButton` in `TaDa/Sidebar/SidebarView.swift`; `NewLinkedTaskButton` in `TaDa/Document/ProjectDocumentView.swift`. |
| Button (`td-seg`) | `ModeToggle` in `TaDa/Document/DocumentPane.swift`; `AppearancePicker` in `TaDa/Settings/ThemeSettingsView.swift`. |
| Menu | `PopupMenu` in `TaDa/Shared/PopupMenu.swift` draws both densities (`PopupMenuStyle.full` and `.compact`): the panel, labels, dividers, highlight, footer key hints. Each menu supplies its rows: `SlashMenu` in `TaDa/Editor/SlashMenu.swift`; `CheckboxMenu` (right-click on an inline checkbox) in `TaDa/Editor/CheckboxMenu.swift`; the compact `FileMenu` in `TaDa/Shared/FileMenu.swift`, which rows add with `.fileMenu(model, path:)`. |
| Settings window | `SettingsView` (nav, `SettingsPage`, `SettingsSectionLabel`, `SettingsButton`) in `TaDa/Settings/SettingsView.swift`; `VaultSettingsView` and `ThemeSettingsView` beside it. |
| Trash | `TrashView` in `TaDa/Browser/TrashView.swift`. |
| View title, group headers | `DomainHeader`, `ProjectGroupHeader` and `CountGroupHeader` in `TaDa/Browser/BrowserChrome.swift`. |

## As built

Where the app differs from the guidance above:

- **Mono type** is the system monospaced font (SF Mono): `.monospaced` in SwiftUI, `NSFont.monospacedSystemFont` in the editors. JetBrains Mono is not bundled.
- **Icons** are SF Symbols: Today `star.fill`, Upcoming `calendar`, Loose tasks `tray`, Trash `trash`, due `calendar`, deadline `flag`, subtasks `checklist`, repeat `repeat`. A project's icon is `ProgressRing`, a 14pt ring with a pie. The file menu uses `trash` (Delete), `arrow.counterclockwise` (Restore) and `xmark.bin` (Delete Forever).
- **Sidebar** order: Search, Today, Upcoming, Loose tasks, an 8pt gap, Trash, PROJECTS, then the folder line ("Watching · <folder>", its icon in `done` while the folder is watched), Settings and New task / New project. Logbook is not built. Project rows are 30pt tall. The sidebar is 200–340pt wide, 240pt by default.
- **Panes**: the browser pane is 320–460pt wide. Upcoming with nothing selected shows the agenda beside a 300pt month calendar. Source mode takes the whole workspace, with text up to 760pt wide and a 300pt file inspector.
- **TaskRow meta line**: Doing and Blocked show a dot and the status name; then subtasks `n/m`, the repeat rule, due and deadline chips ("Due Tue 6 Oct", "Deadline today"; icons only in a project's task list) and contexts as plain text. An overdue date's text is `deadline`. Titles wrap to two lines. There are no free-form tags (`td-tag`); the schema has no tags key.
- **Inline checkboxes** draw the Inline markdown checkboxes artboard's glyphs with its tints, in a 16pt box (1.5pt stroke, 4pt outer radius), 10pt from the text. Task rows draw the same boxes: Blocked uses the artboard's `[B]` bar. `[X]` draws as `[x]`. `[x]`, `[X]` and `[-]` strike their text in `muted`. `[B]` is not a body marker; Blocked is a frontmatter status only.
- **Buttons**: Empty Trash is the only primary button; its confirmation's Empty Trash is filled with `deadline`. Log Now is not built. The folder picker uses the system `.borderedProminent` style.
- **Trash**: Restore returns files to `tasks/` and `projects/` (the artboard says their original folder). Empty Trash and Delete Forever move files to the Mac's Trash, so the confirmation asks “Move N files to the Mac’s Trash?”. Delete Forever doesn't confirm.
- **File menu** items are in title case, as macOS menu commands are: Delete Forever, Delete 3 Tasks.
- **PropertyRow**: values are 12.5pt. `status` (menu), `dueDate` and `deadline` (calendar popover) are editable; the other keys are read-only. `project` shows as `[[Title]]` in `link`, or struck through in `muted` when no project has that title.
- **Settings ▸ Vault**: Location (Change…, Reveal in Finder), Sync (iCloud Drive or local, and whether the folder is watched), Contents (task and project counts) and the `tasks/` and `projects/` folders. There is no Open another vault or Create new vault; Change… picks the folder.
- **Settings ▸ Themes**: no Import .itermcolors button. The theme set and scheme pickers are menus drawn as `code` fields. The window title bar is the system's, on `side`.
