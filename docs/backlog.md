# Ta Da backlog

Work not yet built.

## Code review (2026-10-05)

Issues from the review, most severe first. Fixed ones are removed; the rest keep their numbers. Items 10 and 11 are copies of the same logic that have already drifted apart. Line references are to commit `136b4c6`.

6. **The open file has no `NSFilePresenter`** *(Apple)*: Ta Da coordinates its writes but never registers as presenter of the file being edited. iCloud and other coordinated writers therefore can't ask it to save pending edits first (`savePresentedItemChanges`). A rename made outside Ta Da shows as "deleted or renamed" instead of being followed (`presentedItemDidMove(to:)`). Also, `isInICloud` (`AppModel.swift:604`) looks for "Mobile Documents" in the path. Use `FileManager.default.isUbiquitousItem(at:)` instead; it returns true for iCloud and Obsidian folders and false for local ones.

7. **Dark mode is detected through undocumented APIs** *(Apple)*: the app reads the `AppleInterfaceStyle` default (`Theme.swift:44`) and listens for `AppleInterfaceThemeChangedNotification` (`Themed.swift:23`). It needs these only because a view modifier overrides `NSApp.appearance` for the whole app. Set the appearance per window instead (`.preferredColorScheme` or `window.appearance`) and observe `NSApp.effectiveAppearance` with KVO, which then keeps following the system. Trade-off: menus in the menu bar would follow the system appearance rather than the theme.

8. **List navigation bypasses the focus system** *(Apple, accessibility)*: `ArrowKeySelection.swift:37-78` installs an app-wide `keyDown` monitor that matches raw key codes (125/126/53, plus 36/76 in the menus' `PopupMenu.handleKey`). It also calls `makeFirstResponder(nil)` to take focus away from the editor.
   - Preferred: `List(selection:)`, styled with `.listRowBackground`, `.listRowInsets` and `.scrollContentBackground(.hidden)`. It provides arrow keys, type-to-select and VoiceOver row semantics.
   - Otherwise: `focusable(interactions:)` with `onMoveCommand` and `onExitCommand`, and `NSEvent.specialKey` instead of raw key codes.

9. **Every change rebuilds the whole index, and views re-run their queries** *(performance)*: `update` and `remove` re-sort all paths and re-resolve every task's project (`VaultIndex.swift:68`). This runs on each keystroke that changes the item (`AppModel.swift:384`) and once per changed file in `refresh`. Each change also makes view bodies re-run `today()`, `loose()`, `activeProjects()` and `backlinks()`, and rebuild a set of every title (`LiveDocumentView.swift:49`). Fix: update the title and membership maps incrementally, batch the updates in `refresh`, and cache derived lists in the model.

10. **The editor re-implements wikilink resolution and disagrees with the core** *(duplication, drift)*: `TitleResolver.title(of:)` (`LiveEditor.swift:123`) strips `#heading` and folders but not `.md`, unlike `WikiLink.title`. So `[[Note.md]]` is drawn as unresolved, yet clicking it (`LiveDocumentView.swift:58`) opens the note. Resolve links with `WikiLink(inner:)` against the index's existing title map, made public.

11. **`SourceHighlighter` duplicates core parsing in the app target** *(duplication, layering)*: it re-implements frontmatter and code fences, YAML keys, dates and wikilinks (`SourceHighlighter.swift:40-65`), and the copies differ from the core:
    - a `---` with no closing fence colours the whole file as YAML, while `FrontmatterSplitter` treats it as body;
    - its fence check trims leading whitespace, which the splitter doesn't.

    It uses only Foundation, so by the CLAUDE.md layering it belongs in TaDaCore, built on `FrontmatterSplitter`, `WikiLink` and `LocalDate`.

12. **Views recompute list membership and project progress** *(duplication)*: `FileInspector.swift:116-138` re-derives why a task appears in Today, Upcoming or Loose, running the full `today()` and `upcoming()` queries to test one item. Progress is computed four ways: `ProjectProgress`, `VaultIndex.progress(of:)` in the app (`BrowserChrome.swift:158`), and inline counts in `ProjectBrowserView.swift:11-16` and `ProjectDocumentView.swift:22`. Add per-item predicates and a `progress(of:) -> ProjectProgress` to `Queries`.

13. **A custom popover stands in for a menu, and a stack of rows for a table** *(Apple, accessibility)*: `StatusMenu` (`PropertyTable.swift:84-126`) has no arrow keys, type-to-select or menu semantics; a `Menu` or `Picker` would, as `ThemeMenu` already shows. `LinkedTasksTable` (`ProjectDocumentView.swift:52-148`) has fixed column widths and hides its header row from VoiceOver (line 87). SwiftUI `Table` gives resizable, sortable, selectable columns with proper headers.

14. **Beta builds aren't Developer ID–signed or notarised** *(Apple distribution)*: `scripts/make-beta-dmg.sh` ships the app as signed in the archive, with the Apple Development certificate, and tells testers to remove `com.apple.quarantine`. Either export with `-exportArchive` for Developer ID and then run `notarytool submit --wait` and `stapler staple`, or use TestFlight for Mac. Both keep the same signing identity across builds, and both need the paid developer program. The Read Me also says macOS 27, but the deployment target is 26.0.

15. **⌘L finds its editor through `NSApp.keyWindow?.firstResponder`** *(Apple)*: see `AddSubtask.swift:8-12` and `Commands.swift:51-55`. The menu item stays enabled whenever a document is open, and beeps when no editor has focus. Pass editor focus to the command, for example with `@FocusedValue`, so the item disables itself; the HIG asks for unavailable commands to be disabled.

16. **Names, icons and colours for domains and date kinds are repeated** *(duplication)*:
    - The titles, SF Symbols and tints for Today, Upcoming and Loose appear in `SidebarView.swift:20-22`, `TaskListView.swift:35-39`, `WorkspaceView.swift:77`, `FileInspector.swift:126-135` and `Commands.swift:25-30`.
    - `kind == .due ? "Due" : "Deadline"` appears six times.
    - `AgendaView`'s private `KindIcon` is copied inline in `MonthCalendarView.swift:55` and `ProjectDocumentView.swift:123`.

    Give `AppModel.Domain` a title, symbol and tint, add a `label` next to `AgendaEntry.Kind.systemImage`, and share `KindIcon`.

17. **Each view rebuilds its own rows and list layout** *(duplication)*: `TaskRow`, `ColumnAgendaRow` (nearly identical to it), `WideAgendaRow` and the search view's `projectRow` each assemble the checkbox, plain button, selection background and `.isSelected` trait (`TaskRow.swift:27-45`, `AgendaView.swift:147-216`, `SearchResultsView.swift:43-69`). The list views also repeat the same header and list padding and the `arrowKeySelection` call. A shared `SelectableRow(meta:)` and `BrowserColumn(header:content:)` would cover both, or `List` if you take up item 8.

18. **Existing shared styles are re-implemented instead of reused** *(duplication)*:
    - `SettingsSectionLabel` is copied inline in `SidebarView.swift:24-32` and `FileInspector.swift:88-98`.
    - `Hairline` is redrawn as `Rectangle().fill(border)` four times, twice in its own file (`BrowserChrome.swift:57`).
    - `ModeToggle` (`DocumentPane.swift:79`) and `AppearancePicker` (`ThemeSettingsView.swift:78`) are the same segmented control.
    - Three bordered-button variants style their labels by hand inside `.buttonStyle(.plain)`. Make them a `ButtonStyle`, as `PropertyButtonStyle` already is.
    - There are 101 `.font(.system(size:))` literals in 12 sizes, against 13 named type tokens. A `Font` extension would stop them drifting; the design doc currently chooses literals on purpose.

19. **AppModel's async plumbing repeats itself** *(duplication, concurrency)*:
    - Nine one-off `@concurrent nonisolated static` wrappers (`AppModel.swift:313`, plus lines 188, 466-481, 545, 587 and 591) sit next to a generic `run` that could replace them.
    - About a dozen "Ta Da couldn’t …" messages are formatted by hand.
    - `selection.didSet` starts a new unstructured `Task` on every change (`AppModel.swift:28-34`), so overlapping loads can each call `keepUnsavedEdits` on the same document.

    Fix: use `Self.run`, or give `Vault` async APIs; add one error-reporting helper; and use a single load task that each new selection cancels.

20. **Test fixtures are copy-pasted** *(duplication, tests)*: six TaDaTests suites each rebuild the UserDefaults suite, temp folder, file seeding, `cleanUp()` and `model(selecting:)` (for example `OpenDocumentTests.swift:10-48` and `OutsideChangesTests.swift:10-49`). Every test needs `defer { cleanUp() }`, and fixed sleeps of up to 1.2 s wait out the hard-coded 600 ms debounce. Use one shared fixture (a `final class` with `deinit`, or a `TestScoping` trait) and make the debounce injectable. `GeneratedVault` (`Packages/TaDaCore/Sources/TaDaCore/Testing/GeneratedVault.swift`), test-data code, also ships in the production TaDaCore target; move it to a test-support target.

## Features

- Recurrence: acting on `repeat` (it is parsed and displayed only).
- `.itermcolors` import into a theme.
- Per-file iCloud sync state.
- JetBrains Mono as the mono font.
- Editing UI for `area`, `contexts` and `project`.
- iOS/iPad, including the choice of editor.
- Upstream fix for alias display: `[[Target|Alias]]` shows the target name.
