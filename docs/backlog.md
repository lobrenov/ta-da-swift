# Ta Da backlog

Work not yet built.

## Code review (2026-10-05)

Issues from the review, most severe first. Fixed ones are removed; the rest keep their numbers. Line references are to commit `136b4c6`.

15. **⌘L finds its editor through `NSApp.keyWindow?.firstResponder`** *(Apple)*: see `AddSubtask.swift:8-12` and `Commands.swift:51-55`. The menu item stays enabled whenever a document is open, and beeps when no editor has focus. Pass editor focus to the command, for example with `@FocusedValue`, so the item disables itself; the HIG asks for unavailable commands to be disabled.

16. **Names, icons and colours for domains and date kinds are repeated** *(duplication)*:
    - The titles, SF Symbols and tints for Today, Upcoming and Loose appear in `SidebarView.swift:20-22`, `TaskListView.swift:35-39`, `WorkspaceView.swift:77`, `FileInspector.swift:126-135` and `Commands.swift:25-30`.
    - `kind == .due ? "Due" : "Deadline"` appears six times.
    - `AgendaView`'s private `KindIcon` is copied inline in `MonthCalendarView.swift:55` and `ProjectDocumentView.swift:123`.

    Give `AppModel.Domain` a title, symbol and tint, add a `label` next to `AgendaEntry.Kind.systemImage`, and share `KindIcon`.

17. **Each view rebuilds its own rows and list layout** *(duplication)*: `TaskRow`, `ColumnAgendaRow` (nearly identical to it), `WideAgendaRow` and the search view's `projectRow` each assemble the checkbox, plain button, selection background and `.isSelected` trait (`TaskRow.swift:27-45`, `AgendaView.swift:147-216`, `SearchResultsView.swift:43-69`). The list views also repeat the same header and list padding and the `arrowKeySelection` call. A shared `SelectableRow(meta:)` and `BrowserColumn(header:content:)` would cover both.

18. **Existing shared styles are re-implemented instead of reused** *(duplication)*:
    - `SettingsSectionLabel` is copied inline in `SidebarView.swift:24-32` and `FileInspector.swift:88-98`.
    - `Hairline` is redrawn as `Rectangle().fill(border)` four times, twice in its own file (`BrowserChrome.swift:57`).
    - `ModeToggle` (`DocumentPane.swift:79`) and `AppearancePicker` (`ThemeSettingsView.swift:78`) are the same segmented control.
    - Three bordered-button variants style their labels by hand inside `.buttonStyle(.plain)`. Make them a `ButtonStyle`, as `PropertyChipStyle` already is.
    - There are 101 `.font(.system(size:))` literals in 12 sizes, against 13 named type tokens. A `Font` extension would stop them drifting; the design doc currently chooses literals on purpose.

19. **AppModel's async plumbing repeats itself** *(duplication, concurrency)*:
    - Nine one-off `@concurrent nonisolated static` wrappers (`AppModel.swift:313`, plus lines 188, 466-481, 545, 587 and 591) sit next to a generic `run` that could replace them.
    - About a dozen "Ta Da couldn’t …" messages are formatted by hand.
    - `selection.didSet` starts a new unstructured `Task` on every change (`AppModel.swift:28-34`), so overlapping loads can each call `keepUnsavedEdits` on the same document.

    Fix: use `Self.run`, or give `Vault` async APIs; add one error-reporting helper; and use a single load task that each new selection cancels.

20. **Test fixtures are copy-pasted** *(duplication, tests)*: six TaDaTests suites each rebuild the UserDefaults suite, temp folder, file seeding, `cleanUp()` and `model(selecting:)` (for example `OpenDocumentTests.swift:10-48` and `OutsideChangesTests.swift:10-49`). Every test needs `defer { cleanUp() }`, and fixed sleeps of up to 1.2 s wait out the hard-coded 600 ms debounce. Use one shared fixture (a `final class` with `deinit`, or a `TestScoping` trait) and make the debounce injectable. `GeneratedVault` (`Packages/TaDaCore/Sources/TaDaCore/Testing/GeneratedVault.swift`), test-data code, also ships in the production TaDaCore target; move it to a test-support target.

## Features

- Recurrence: acting on `repeat` (it is parsed and shown in task rows only), and showing it in Live mode.
- `.itermcolors` import into a theme.
- Developer ID signing and notarisation, or TestFlight for Mac, if Ta Da joins the paid Apple Developer Program: testers would no longer unblock each beta build (`docs/beta-builds.md`).
- Per-file iCloud sync state.
- JetBrains Mono as the mono font.
- Areas in Live mode: the property chips leave `area` out until it's reconsidered.
- A better design for a project's linked-tasks table (its columns have fixed widths).
- iOS/iPad, including the choice of editor.
- Upstream fix for alias display: `[[Target|Alias]]` shows the target name.
- Editor markdown as designed (Editor markdown in `docs/design/design-framework.md`; the canvas's Live editor · markdown row): the heading scale, rounded inline code, highlights and code blocks, and Obsidian callouts with folding and the callout menu.
