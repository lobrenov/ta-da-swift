# Ta Da backlog

Work not yet built.

## Code review (2026-10-05)

Issues from the review, most severe first. Fixed ones are removed; the rest keep their numbers. Line references are to commit `136b4c6`.

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
