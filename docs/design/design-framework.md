# Ta Da design framework

Mirrored by the Claude Design System artifact https://claude.ai/artifact/GkKXeVHXv9XMGMWWacPppz (last synced 2026-10-08, version 1791418156-8ae6; it shows one colour scheme per theme set). This folder is the copy the repo follows: `tokens.json` holds the values, `components/<Name>/README.md` the component guidelines and `components/bundle.css` their reference CSS. [In the app](#in-the-app) maps each part to its Swift code, and [As built](#as-built) lists where the app differs from the guidance.

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
- **Settings window.** 900×640 on `bg` with a 46px `side` title bar. A 200px `side` nav (Vault in `accent`, Themes in `link`, Editor in `doing`) beside the page: a `title-dialog` title, a `muted` line under it, then label-and-control rows (labels `muted`, 84–92px wide), bordered 10px panels and uppercase section labels.
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
| `[ ]` | Not started | `muted` | `[l]` | Location | `link` |
| `[x]` | Done (filled) | `done` | `[b]` | Bookmark | `blocked` |
| `[/]` | Doing | `doing` | `[i]` | Information | `accent` |
| `[-]` | Cancelled | `muted` | `[S]` | Savings | `done` |
| `[B]` | Blocked (Ta Da) | `blocked` | `[I]` | Idea | `due` |
| `[>]` | Forwarded | `accent` | `[p]` | Pros | `done` |
| `[<]` | Scheduling | `due` | `[c]` | Cons | `deadline` |
| `[?]` | Question | `doing` | `[f]` | Fire | `blocked` |
| `[!]` | Important (filled) | `deadline` | `[k]` | Key | `due` |
| `[*]` | Star | `due` | `[w]` | Win | `due` |
| `["]` | Quote | `muted` | `[u]` / `[d]` | Up / Down | `done` / `deadline` |

Only Done and Important are filled boxes. Done and Cancelled strike their text through in `muted`.

## Editor markdown

The Live editor draws the file's markdown at `body-editor` (14/23) and keeps every marker in the file. The canvas's Live editor · markdown row shows each format beside the markdown that makes it, in every theme. Guidelines: `components/Markdown/README.md` and `components/Callout/README.md`.

- **Headings** step down from `heading-1` (20/28) to `heading-6` (13/20, `muted`); all sit below the file title (`title-file`, 23px).
- **Bubbles.** Inline code and highlights are rounded spans: `radius-sm` corners, 2px above and below, rounded again on each line they wrap onto, text in `strong`. Code sits on `code` with a 1px `border` ring, in `code-text` (12.5px mono). A highlight is `due` at 30% (26% on dark schemes), the one place `due` fills behind text.
- **Blocks** use `radius-lg`: code blocks (`code` with a `border` ring and the language top right in `muted`), tables (a `border` frame, header row on `code`), images and callouts.
- **Links**: `[[wikilinks]]` in `link`; markdown links in `link` with a 45% underline; unresolved wikilinks in `muted` with a dashed underline.
- **Lists** indent 27.5px a level, with `muted` bullets that change by depth (filled circle, circle, filled square, diamond) and `muted` numbers. Task lines draw the inline checkboxes above.
- **Quotes** are `muted` text beside a 3px rounded `surface` bar.
- **The caret's line** shows its markdown in mono 13px on `code`, `radius-sm`, markers in `muted`; every other line stays drawn.

### Callouts

Obsidian's callouts: `> [!type] Title` opens one, and the following `>` lines are its body. The icon carries the type's colour; the panel is that colour at 9% (14% on dark schemes) with a 24% ring (30%), so text keeps `strong` titles and `fg` bodies. `+` or `-` after `]` makes it foldable, open or folded, with a `muted` chevron on the right. A right-click on the title line opens the callout menu.

| Type | Aliases | Token | Icon |
| --- | --- | --- | --- |
| `note` | | `accent` | pencil |
| `abstract` | `summary`, `tldr` | `doing` | clipboard |
| `info` | | `accent` | info circle |
| `todo` | | `accent` | tick circle |
| `tip` | `hint`, `important` | `doing` | flame |
| `success` | `check`, `done` | `done` | tick |
| `question` | `help`, `faq` | `due` | question circle |
| `warning` | `caution`, `attention` | `blocked` | triangle |
| `failure` | `fail`, `missing` | `deadline` | cross |
| `danger` | `error` | `deadline` | bolt |
| `bug` | | `deadline` | bug |
| `example` | | `link` | list |
| `quote` | `cite` | `muted` | quote marks (filled) |

Types are read case-insensitively. An unknown type draws as `note`. Without a title, the type's name is the title.

## Writing

- Sentence case for labels and menus; title case only on buttons, as macOS does ("Log Now", "Empty Trash").
- Name things by what people see: "Loose tasks", "Logbook", "Trash", never "orphan files" or "archive directory". Folder names (`.logbook/`, `.trash/`) appear in mono where the file location matters.
- Dates: "Today", "Tomorrow", "Tue 6 Oct" in rows and property chips; ISO `2026-10-06` in source.
- Buttons state the result and counts update live: "Restore 2 Items". Confirmations say what is permanent and where: "Permanently delete 4 files from iCloud Drive?"

## Components

Plain CSS classes in `components/bundle.css`, prefixed `td-`, built on these tokens: Checkbox, TaskRow, SidebarItem, PropertyRow, Chip, Button, Menu, Markdown, Callout. Each has guidelines in `components/<Name>/README.md`. In the Swift app they map to SwiftUI views; the classes here are the reference for spacing, states and colour roles.

## In the app

| Design | Swift |
| --- | --- |
| Colour tokens and themes | `Theme` (`TaDa/Theme/Theme.swift`), one `PlatformColor` (`NSColor` or `UIColor`) property per token, read from the `\.theme` environment value. The fifteen schemes are `Theme.all` and the eight sets `ThemeSet.all` in `TaDa/Theme/BundledThemes.swift`, with the same values and order as `tokens.json`. `AppModel` picks the scheme from the set, the `Appearance` setting and the system appearance; `themed(by:)` (`TaDa/Theme/Themed.swift`) applies it to a window. |
| Type, spacing, radius, size | Literal values in each view (`.font(.system(size: 13.5))`, `cornerRadius: 7`); there are no Swift constants for them. |
| Checkbox | `InlineCheckbox` in `TaDa/Editor/InlineCheckbox.swift` draws every box from the artboard's paths, and `Theme.checkboxTint` there gives each marker's tint. `StatusCheckbox` in `TaDa/Browser/TaskRow.swift` uses them for task rows, `CheckboxMenu` for its rows and `TaskCheckboxStyle` in `TaDa/Editor/LiveEditor.swift` for the editor. |
| TaskRow | `TaskRow`, `TaskTitle`, `StatusLabel`, `Chip` and `DateChip` in `TaDa/Browser/TaskRow.swift`. `SelectableRow` there draws the row (checkbox, title button, meta line, `is-selected`) for `TaskRow` and Upcoming's rows beside a document; `BrowserColumn` in `TaDa/Browser/BrowserChrome.swift` lays out each list beside the document. Selection (click, shift- and ⌘-click, `is-selected`) is shared by every list through `model.click(_:)` and `model.isSelected(_:)` in `TaDa/Browser/ArrowKeySelection.swift` and `TaDa/AppModel.swift`. |
| SidebarItem | `SidebarRow` and `ProgressRing` in `TaDa/Sidebar/SidebarView.swift`; area rows draw `AreaIcon`. |
| Area icon | `AreaIcon` in `TaDa/Shared/AreaIcon.swift`: the canvas's Cube (`AreaIcons`), two-tone in `doing`, at 16 (sidebar, menus), 24 (page title), 13 (chip) and 15 (iPhone chip). |
| Area page | `AreaBrowserView` in `TaDa/Browser/AreaBrowserView.swift` (the canvas's `AreaBrowser`); the delete question's text is `TrashConfirmationText` in `TaDa/Shared/TrashConfirmationText.swift`, shown by `ContentView` (Mac) and `PhoneRootView` (iPhone), which also show the canvas's Delete attachments dialog (`DeleteFilesDialog` in `TaDa/Shared/DeleteFilesDialog.swift`). |
| PropertyRow | Replaced by the canvas's Properties chips (Editors page) and status, move, area and date menus (Menus page): `PropertyChips` in `TaDa/Document/PropertyChips.swift` (its chips alone are `PropertyChipRow`, also in the project browser's header), with the pickers of `PropertyPicker` in `PropertyPickers.swift` and `CalendarPicker` in `CalendarPicker.swift` beside it. |
| Button | `ActionButtonStyle` in `TaDa/Shared/Buttons.swift`, in its outlined, outlined strong, primary and danger kinds: the sidebar's New buttons, `SettingsButton`, the project page's New linked task, the project browser's Open project file and Trash's buttons. |
| Button (`td-seg`) | `SegmentedControl` in `TaDa/Shared/Buttons.swift`: Live/Source in `TaDa/Document/DocumentPane.swift` and Appearance in `TaDa/Settings/ThemeSettingsView.swift`. |
| Menu | `PopupMenu` in `TaDa/Shared/PopupMenu.swift` draws both densities (`PopupMenuStyle.full` and `.compact`): the panel, labels, dividers, highlight, footer key hints. Each menu supplies its rows: `SlashMenu` in `TaDa/Editor/SlashMenu.swift`; the link menu (`[[` and `![[`) in `TaDa/Editor/LinkMenu.swift`, whose `LinkChoiceIcon` also draws the iPhone list's icons; `CheckboxMenu` (right-click on an inline checkbox) in `TaDa/Editor/CheckboxMenu.swift`; `CalloutMenu` (right-click on a callout's title line) in `TaDa/Editor/CalloutMenu.swift`; `RightClickMenu` (rightClickMenu: right-click on a table's row or column grip) in `TaDa/Editor/RightClickMenu.swift`; the compact `FileMenu` in `TaDa/Shared/FileMenu.swift`, which rows add with `.fileMenu(model, path:)`, and whose panel also shows the embed menu (`TaDa/Editor/EmbedMenu.swift`, with the image dialogs in `TaDa/Editor/ImageDialogs.swift`); the status, move and area menus of the property chips (move and area with a search field, `PopupField`), which the file menu's Move and ⇧⌘M also open. `PopupPanel` there is the panel alone, which `CalendarPicker` fills with a `PopupField` and a month for the date chips, the file menu's Schedule and Set Deadline…, ⌘S and ⌘D. |
| Markdown | `LiveEditor` in `TaDa/Editor/LiveEditor.swift` maps the colour tokens onto the engine's `MarkdownEditorTheme`; its `CodeBlockStyle` sets the code font and fill. Inline code and highlights are the engine's `InlineBubble`s (`config.inlineCode.bubble` and `HighlightBubble` there). |
| Table grid | On the Mac the engine draws a Live table as `TableGridView` (`Packages/TaDaMarkdown/Sources/TaDaMarkdown/Renderer/TableGridView.swift`), from the `td-md-table` frame, header row and cells, with its grips, ring and drop line in `accent`; `LiveEditor` sets `liveTables` and `tableAccent`. |
| Callout | The engine draws the panels from `CalloutStyle`, which `LiveEditor` fills: tints from `Theme.calloutTint` and icons from `CalloutIcon` (the artboard's paths) in `TaDa/Editor/CalloutIcon.swift`, types and aliases from `CalloutType` in TaDaCore. The callout menu is `CalloutMenu` in `TaDa/Editor/CalloutMenu.swift`. |
| Settings window | `SettingsView` (nav, `SettingsPage`, `SectionLabel`, `SettingsButton`) in `TaDa/Settings/SettingsView.swift`; `VaultSettingsView`, `ThemeSettingsView`, `EditorSettingsView`, `IntegrationsSettingsView`, `NotificationsSettingsView` and `HotkeysSettingsView` (with `HotkeyRecorder`) beside it. `SectionLabel` is the `label` style, also used in the sidebar and the file inspector. |
| Logbook | `LogbookView` in `TaDa/Browser/LogbookView.swift` (Mac) and `PhoneLogbookScreen` in `TaDa/iOS/PhoneLogbook.swift`, grouped by `LogbookGroup` in `TaDa/Shared/LogbookGroups.swift`; the canvas's Logbook · complete a project with open tasks is `CompletionDialog` in `TaDa/Shared/CompletionDialog.swift`. |
| Trash | `TrashView` in `TaDa/Browser/TrashView.swift`. |
| Tags (canvas's Tags page) | `TagSidebar`: `SidebarModeSwitch` and the tag tree in `TaDa/Sidebar/SidebarView.swift`. `TagBrowser`: `TagBrowserView` in `TaDa/Browser/TagBrowserView.swift`. `TagRow` and `TagMenu`: `TagChipRow` and `TagChoice` in `TaDa/Document/TagChips.swift`, with tagMenu in `PropertyPickers.swift`, and `TagCountChip` in `TaDa/Browser/TaskRow.swift`. `TagBubbles`: the engine's `TagStyle`, filled by `LiveEditor`. `TagAutocomplete`: `TagMenuController` and `PhoneTagList` in `TaDa/Editor/TagAutocomplete.swift`. iOS row: `TaDa/iOS/PhoneTags.swift`, the Tags row in `PhoneOther.swift` and the `#` key in `LiveEditor`'s keyboard bar. The tag tint is `accent`, through `Theme.tagFill` and `tagRing`. |
| Notes (canvas's Notes page) | `NotesSidebar`: `SidebarModeSwitch`, the folder tree, its folder menu (`actionMenu`) and the + Note / + Folder foot in `TaDa/Sidebar/SidebarView.swift`. `NotesBrowser`: `FolderBrowserView` in `TaDa/Browser/FolderBrowserView.swift`. `NoteRow`: `NoteRow` in `TaDa/Browser/NoteRow.swift`, with `NoteIcon` in `TaDa/Shared/NoteIcon.swift`; also in tagBrowser's Notes group and search results. `NoteProperties`: the note's Tags row and quiet line (`NoteMenuButton`) in `TaDa/Document/PropertyChips.swift`; the note menu is `FileMenuAction.noteActions` in `TaDa/Shared/FileMenu.swift`. `NoteConvert`: `ConvertSheet` and `ConvertPreview` in `TaDa/Shared/ConvertSheet.swift`, shown by `ContentView`. |
| Quick Entry (canvas's Quick Entry page) | `QuickEntryDesktop` and `QuickEntryPanel`: `QuickEntryPanel` (the window) in `TaDa/QuickEntry/QuickEntryPanel.swift` and `QuickEntryView` (its content) in `QuickEntryView.swift`. `QuickEntry`'s states and menus: `PropertyChipRow` and `TagChipRow` with their menus, in `QuickEntryView`. `SettingsHotkeys`: `HotkeysSettingsView` and `HotkeyRecorder` in `TaDa/Settings/HotkeysSettingsView.swift`. |
| Integrations (canvas's Integrations page) | `IntegrationsToday`, `IntegrationsUpcoming`, `IosIntegrationsToday` and `IosIntegrationsUpcoming`: `EventRow` in `TaDa/Shared/EventRow.swift` and `ReminderRow` in `TaDa/Shared/ReminderRow.swift`, placed by `TaskListView`, `AgendaView` and `PhoneScreens.swift`; the event dot in `MonthCalendarView` and the iPhone's week strip. `IntegrationsSettings`: `IntegrationsSettingsView` in `TaDa/Settings/IntegrationsSettingsView.swift`. `IosIntegrationsSettings`: `PhoneIntegrationsScreen` in `TaDa/iOS/PhoneIntegrations.swift`. Their words, the access state's dot and calendar colours are in `TaDa/Integrations/IntegrationsDisplay.swift`. |
| iOS POC page | `TaDa/iOS/` (the iPhone section of `docs/architecture.md`): lists, rows and their press-and-hold menu in `PhoneList.swift` and `PhoneRows.swift`; an area's page in `PhoneScreens.swift`; the task, project and area files in `PhoneFileScreen.swift`, with the shared `TitleField`, `BodyEditor` and `DocumentBanner`; the date sheet and the move and area sheet (`PhoneMoveSheet`) in `PhoneSheets.swift`; swipe to pick and the action bar in `PhonePicking.swift`; Other, Settings, Trash and onboarding in `PhoneOther.swift`. The editor's checkbox and callout menus and keyboard bar are in `TaDa/Editor/LiveEditor.swift`. |
| View title, group headers | `DomainHeader`, `ProjectGroupHeader` and `CountGroupHeader` (foldable with `isExpanded`) in `TaDa/Browser/BrowserChrome.swift`; a project browser's header is drawn in `ProjectBrowserView` and an area's in `AreaBrowserView`. Each domain's title, symbol and tint come from `AppModel.Domain` there, and each date kind's label, symbol and tint from `AgendaEntry.Kind` in `TaDa/Browser/TaskRow.swift`, beside `KindIcon`. |

## As built

Where the app differs from the guidance above:

- **Mono type** is the system monospaced font (SF Mono): `.monospaced` in SwiftUI, `NSFont.monospacedSystemFont` in the editors. JetBrains Mono is not bundled.
- **Icons** are SF Symbols: Today `star.fill`, Upcoming `calendar`, Loose tasks `tray`, Logbook `book.closed`, Trash `trash`, due `calendar`, deadline `flag`, subtasks `checklist`, repeat `repeat`, a note `doc.text`, a notes folder `folder`, Loose (notes) `tray`. A project's icon is `ProgressRing`, a 14pt ring with a pie, or `checklist` for an Ongoing project; an area's is `AreaIcon`. The file menu uses `folder` (Move), `calendar` (Schedule), `flag` (Set Deadline…), `tag` (Tags…), `arrow.up.forward.square` (Reveal in Finder), `trash` (Delete), `arrow.counterclockwise` (Restore) and `xmark.bin` (Delete Forever). The property chips use `chevron.down` (status) and `plus` (a missing key), the move menu `magnifyingglass`, `tray` (Loose tasks), `AreaIcon` (areas), `ProgressRing` (projects) and `plus` (New project, New area, Create Area), and the area menu `xmark` (No area).
- **Sidebar** order: Search, Today, Upcoming, an 8pt gap, Logbook, Trash, the Tasks | Tags | Notes switch, then Loose tasks, loose projects and each area (title order) with its active projects under it, not indented and with no section label (or Untagged and the tag tree, or Loose and the folder tree), then the folder line ("Watching · <folder>", its icon in `done` while the folder is watched), Settings and New task / New project / New area (New note / New folder in Notes). Area rows have no ring and no count, and don't fold. Project rows are 30pt tall. The sidebar is 200–340pt wide, 240pt by default.
- **Panes**: the browser pane is 320–460pt wide. Upcoming with nothing selected shows the agenda beside a 300pt month calendar. Source mode takes the whole workspace, with text up to 760pt wide and a 300pt file inspector.
- **TaskRow meta line**: subtasks `n/m`, the repeat rule, due and deadline chips ("Due Tue 6 Oct", "Deadline today"; icons only in a project's or area's task list). Contexts aren't shown. An overdue date's text is `deadline`. Titles wrap to two lines. Tags show as a count (`TagCountChip`), not as `td-tag` chips.
- **Inline checkboxes** draw the Inline markdown checkboxes artboard's glyphs with its tints, in a 16pt box (1.5pt stroke, 4pt outer radius), 10pt from the text. Task rows draw the same boxes: Blocked uses the artboard's `[B]` bar. `[X]` draws as `[x]`. `[x]`, `[X]` and `[-]` strike their text in `muted`. `[B]` is not a body marker; Blocked is a frontmatter status only.
- **Buttons**: Empty Trash, Log Now and the completion sheet's default are the primary buttons; Empty Trash's confirmation's Empty Trash is filled with `deadline`. The folder picker uses the system `.borderedProminent` style. Button sizes follow the canvas, not `td-btn`: 28pt in panels and confirmations (Settings' on `code`, New linked task on `bg`) and for Open project file, 32pt in the sidebar, and Restore Items has a 12.5pt semibold `strong` label. Disabled buttons are drawn at half opacity. Appearance's segments are 26pt, with medium-weight labels when not selected.
- **Logbook** follows the canvas's Logbook, in the browser pane beside the editor rather than single-pane: Log Now in the header, the line under it, then Completed today ("Still in place · logs tonight"), Waiting for open tasks (a completed project that still has open tasks, and its tasks), each day of the last week and each month. A task's box reopens it; a project shows a full ring in `done` (`muted` when cancelled). On iPhone it's pushed from Other, with Log Now and the line in the bottom bar. Completing a project with open tasks is a window sheet on the Mac and a confirmation dialog on iPhone, with Complete N Tasks and Cancel N Tasks, the project's own status the default.
- **Delete with attachments** follows the canvas's dialog and iPhone sheet. The Mac's is a window sheet. A project's tasks are listed by title. An area that embeds no images still asks with an alert.
- **Trash**: Restore returns files to `tasks/`, `projects/` and `areas/` (the artboard says their original folder). Images under a picked file show picked, but Restore's count is of the picked rows. An area's row is "Area · deleted with N projects and M tasks". Empty Trash and Delete Forever move files to the Mac's Trash, so the confirmation asks “Move N files to the Mac’s Trash?”. Delete Forever doesn't confirm.
- **File menu** items are in title case, as macOS menu commands are: Reveal in Finder, Delete Forever, Move 3 Tasks, Move 2 Projects, Schedule 3 Tasks, Delete 3 Tasks; Set Deadline… doesn't name the count, and Tags… (⌘T, after Set Deadline…) shows only for one file. The menu bar's File ▸ Reveal in Finder shows the picked or open files. Move opens the project menu (the area menu for a project) at the pointer in its place; ⇧⌘M opens it under the open task's project chip, or under the first picked row. Schedule and Set Deadline… open the date menu the same way, as do ⌘S and ⌘D under the open file's date chip, the editor included; Tags… opens tagMenu the same way, as does ⌘T under the open file's + Tag chip, on an area too. The canvas's Move menu and Date menu show both. The picked tasks pane shows only "N tasks selected".
- **Drag and drop**: task rows drag as their files, onto the sidebar's projects, areas, Loose tasks and Today (an area also takes dragged sidebar projects), and note rows onto the sidebar's Loose and notes folders, which take the `is-target` ring while a drag is over them, or into other apps as a drag from Finder would. Other apps get copies. A drag shows the dragged rows, stacked when several are picked.
- **Properties** follow the canvas's Properties · A · Chips and Properties · Chip states (Editors page) and its Status, Move, Area and Date menus (Menus page) instead of PropertyRow. Status, the parent (a task's project or area, a project's area), due date and deadline are 26pt chips, 12.5pt; a missing key is a dashed chip. An unresolved project or area is struck through in `muted`, and its menu offers Create Area for an area. An area's file has no chips, only its line. The type, createdDate and completedDate sit in an 11.5pt `muted` line below, with a project's ring and task count, so the project page's title has no ring. `contexts` and `repeat` aren't shown. Clear, Loose tasks and No area empty the key (`key:`) rather than remove it. A project's status menu adds Ongoing after Doing, drawn as the `[>]` box in `doing`, its dot's colour; a task's has no Ongoing.
- **Date menu** follows the canvas's Date menu with a field above it, the move menu's search field with `calendar` and "Type a date: fri, 3d, 25/12", which has the keyboard. Its right side shows, in `muted`, the day ↵ sets, or "No match · " and that day. The arrow keys don't move the day, and there are no footer key hints.
- **Project browser** follows the canvas's Project · browser + editor: the progress ring and 24pt title, which a click turns into a field on `code` (Return or a click away renames, esc cancels), with Open project file as an outlined button on the right. Under them the property chips, the project file's own subtasks `n/m` after them as in a task row's meta line, and an 11.5pt `muted` "n of m tasks done". An Ongoing project (canvas's projectBrowser - Ongoing) shows `checklist` in place of the ring and no "n of m tasks done"; in project rows elsewhere its status stands in for its progress, and the file's quiet line says only Project. There is no summary. Open and Completed fold from a `chevron.down`/`chevron.right` before their name; folded groups are remembered per project.
- **Area page** follows the canvas's `AreaBrowser`: the 24pt cube and title (renames in place), Open area file, and an 11.5pt `muted` count of projects and open tasks. Projects (each with its status and "n of m done", then its subtasks, due date and deadline as a task row's meta line), Tasks (filed straight to the area) and Completed fold, Completed folded at first; New task in <area> ends the page. Deleting an area asks first, with the count of files that go.
- **Project page's Tasks table** follows the canvas's Project · File: clicking a row opens the task beside the project's browser; its status, dueDate and deadline cells open the status and date menus under themselves, `surface` under the pointer, and its title renames in place. Rows are `code` under the pointer. New linked task adds an Untitled, Not Started row, scrolled into view with its title ready to type, and stays on the page.
- **Settings ▸ Vault**: Location (Change…, Reveal in Finder), Sync (iCloud Drive or local, and whether the folder is watched), Contents (task, project and area counts) and the `tasks/`, `projects/` and `areas/` folders. There is no Open another vault or Create new vault; Change… picks the folder.
- **Editor markdown** uses the engine's drawing: headings scale 2, 1.5, 1.17, 1, 0.83 and 0.67 times the 14pt body; code blocks are `code` line fills. Inline code is SF Mono at 12pt. A bubble that wraps reaches past the line's edge by its padding rather than pushing the text in.
- **Images** follow the canvas's Embeds · drawn, source and paste (Editors page): drawn, the `</>` button on hover with its tooltip, the source shown, a missing image, and the ring of a selected image. An image draws only on a line of its own; an embed beside other text stays as text. SVGs aren't drawn and show as missing. On iPhone a tap puts the caret beside an image; there's no selected state.
- **Embed menu** follows the canvas's Embed menu (Menus page); on iPhone Show in Files takes Reveal in Finder's place. On iPhone the menu opens at the press without lifting the image. Rename is a sheet in the delete dialog's layout, with the name field (its extension beside it) and the embeds it updates. The Mac's image dialogs are window sheets.
- **Table grid** keeps `td-md-table`'s frame, header row on `code` and hairlines, with cells editable in place. Each column is its widest cell's width, sharing the editor's width in proportion once the table is wider than it. A hovered row's grip (six `muted` dots) sits in the gutter left of it and a column's centred above its header; over a grip the pointer is an open hand (closed while dragging) and the row's or column's ring fades in. A selected row or column has a 2pt `accent` ring, a drag a 2pt `accent` line at the drop place. The header is bold; alignment doesn't change widths. iPhone shows the rendered image.
- **Link menu** follows the canvas's Link menu (Menus page). An empty `[[` lists every file by title, unlabelled, until one has been opened; `![[` lists images newest first, up to 50 rows, and shows SVGs with the `photo` symbol. An area shows its cube and Area on the right. On iPhone the list hides when nothing matches.
- **Document meta line** ends with “N backlinks”, a menu of the files that link here, when there are any. The Mac's footer under the body shows only when the file was modified.
- **Callouts**: the caret's title line shows `> [!type]` in `muted` in the body font, not mono on `code`. Callout lines are 17pt high, as quote lines are, and a blank `>` line in a body is a full line. The slash menu's Callout inserts `> [!note] ` with the SF Symbol `text.bubble`.
- **Settings ▸ Editor** follows the canvas's Settings · Editor: an Autocomplete panel with Brackets, Text formatting, Wikilinks and embeds, and Tags, each with its markers in `code` chips and a system switch tinted `accent`.
- **Settings ▸ Hotkeys** follows the canvas's Settings · Hotkeys, with `arrow.counterclockwise` (Restore) and `xmark` (Clear). A taken shortcut other than ⌃Space gets a general warning naming its keys. A key's name is what it types on the layout it was recorded on, kept as recorded.
- **Quick Entry** follows the canvas's Quick Entry page. Disabled Create buttons use the shared disabled look (`surface`, `muted` text, half opacity), not `accent` at half opacity. The type switch's icons are the task box, `ProgressRing` and `AreaIcon`. The panel's chips act as on a file, except that a tag chip's click and ⌘-click on a parent show that page in the main window behind the panel.
- **Settings ▸ Themes**: no Import .itermcolors button. The theme set and scheme pickers are menus drawn as `code` fields. The window title bar is the system's, on `side`.
- **Tags** follow the canvas's Tags page. A root tag lines up with Untagged, with a parent's chevron in the row's leading padding. tagAutocompleteMenu also lists parent tags carried by no file alone, as tagMenu does, and leaves out a tag only the open file's body carries once (the one being typed). A bubble that starts a visual line reaches past the text's edge by its 6pt padding. On iPhone the file's "In text" chips follow the body as it's typed.
- **Notes** follow the canvas's Notes page. The note menu's convert rows are Task…, Project… and Area… with `checkmark.square`, `checklist` and `cube`, the folder each goes to on the right, and no section label; Move to Folder… uses `tray` (Loose) and `folder`. The convert sheet's status and parent are system menus, not the editor's chip menus. File ▸ New Task/Note (⌘N) makes a note on a folder's page and a task elsewhere; File ▸ New Folder and File ▸ Convert to sit beside it. On iPhone, notes show in tag screens (a Notes group), search and Trash, and open in the file screen with the Tags row and no status chips or status toolbar; it has no Notes tree.
- **Integrations** follow the canvas's Integrations page. A timed event that ends exactly at midnight shows All day on its last day. Past Upcoming's seven days, reminders are listed with their date under their month (and in the Mac's "Later in" list) and events show only as dots; the dots cover today to the later of Upcoming's last date and the end of next month, at most a year ahead. A Show switch is disabled while its access is denied. Settings' icon is `calendar` in `deadline`. On iPhone, Settings ▸ Integrations lists each account as an uppercase `muted` label over its calendars or lists, and Today leaves a 20pt gap between the events and reminders and a first task that has no group header.
- **Notifications** has no canvas page. On the Mac it is one bordered switch row like Integrations', with the denied state under it; its Settings icon is `app.badge` in `blocked`. On iPhone it is a Notifications section in Settings with a Badges switch and the explanation, or the denied state, in its footer.
- **iPhone** follows the canvas's iOS POC page, with these differences: list titles have no domain icon. Onboarding has Choose Folder only, not Create a New Folder. The callout menu has no Remove Callout. Trash's Restore is a plain text button. Search always looks through every file, with no scope bar, and the editor has no slash menu. Pull to search follows treatment C; the open field sits in the navigation bar's row, with a close button in place of the "…". An area's More menu keeps Move to Trash above Search and Select, and area rows use a 24pt cube to line up with project rows.
