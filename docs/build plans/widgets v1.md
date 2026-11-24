# Ta Da — Widgets v1

## Context
Widgets and controls for Ta Da on iPhone and Mac: Today and Agenda on the Home Screen and the Mac desktop, a count, the ring and the next task on the iPhone Lock Screen, and Add Task and Agenda controls for Control Centre, the Lock Screen, the Action Button and the Mac menu bar. Design: the canvas's Widgets & Controls page.

The extension shares data with the app through an App Group. App Groups need a provisioning profile on iPhone, which the free account's profile doesn't have, so the paid Apple Developer Program (auto-update v1, Part 3) comes first.

## Decisions
- **Target**: one widget extension, `TaDaWidgets`, for iOS and macOS, with a synchronised `TaDaWidgets/` folder. It's embedded in every app target, including `TaDa GitHub` if tip jar v1 has landed. It links no TaDaCore and never reads the folder.
- **App Group**: `group.com.lobrenov.TaDa`, on the app and the extension, on both platforms, with the provisioning profiles the paid account gives. On the Mac this also needs the profile embedded in Developer ID builds; `make-release.sh` and `docs/releases.md` change with it.
- **Snapshot**: `WidgetSnapshot` (Codable), a JSON file in the group container:
  - whether a folder is open
  - Today: open tasks due today or overdue, in the Agenda's order (title, path, due date, overdue), and the counts (open, overdue, done today)
  - the next days for the large widget: each day's open tasks, through the next 7 days
  - the next task after today, for the empty state
  - the theme's colours for the current theme set, light and dark (`accent`, `due`, `deadline`, `done`, `muted`, text and background)
  - `today`, so the extension knows when the snapshot is stale
- **Writing it**: `WidgetSync` in `TaDa/Widgets/`, like `SpotlightSync`: it watches the index, state and theme, writes the snapshot a second after a change, if it changed, then calls `WidgetCenter.shared.reloadAllTimelines()`. The snapshot is built by an `AppModel` extension from the Agenda's own queries.
- **Timeline**: one entry now and one at the next midnight. After midnight, before the app writes a new snapshot, the extension moves Today on itself: tasks of the new day join Today, and yesterday's open ones count as overdue.
- **Widgets**, as designed:
  - Small: Today count ("6 today", "4 overdue"); Add Task (a link to the app).
  - Medium: Today, a header with the count and +, then the first 4 rows with checkboxes and date chips.
  - Large: Agenda, today then the following days.
  - Lock Screen (iPhone): inline "6 today · 4 overdue", circular ring of today's tasks done, rectangular next task.
  - Empty: "All clear · 3 tomorrow" (small), "Nothing due today · Next: <title> · <day>" (medium). No folder: "Open Ta Da".
  - Theme colours from the snapshot; the system's tinted and clear renderings use `widgetAccentable` on the accent parts.
  - Tapping a row opens the task (`taDa://file/<path>`, handled with `openRequest`); tapping elsewhere opens the Agenda.
- **Completing from a widget**: `CompleteWidgetTaskIntent` (path parameter), in a file shared by both targets. It conforms to `LiveActivityIntent`, so it runs in the app's process: the app opens its folder (`model.ready()`), sets the task Done with `setStatus` (so undo, repeating tasks and the logbook work as in the app), and the snapshot is written again. The widget shows the box ticked straight away (`invalidatableContent`).
- **Controls**: `ControlWidgetButton`s whose intents are shared by both targets and open the app:
  - Add Task: Quick Entry on the Mac; on iPhone, a new task as the iPhone's + makes one. `OpenRequest` gains `.newTask`.
  - Agenda: the Agenda on today; its label shows today's count from the snapshot.
  - Available in Control Centre, the Lock Screen and the Action Button on iPhone, and Control Centre and the menu bar on the Mac.
- **Version**: 0.46.0 (tag `feature`).
- **Not in v1**: a widget for one project or area; configurable widgets; completing from the Lock Screen (accessory widgets can't hold buttons); a Mac-only design; iPad.

## Steps
1. **Target and App Group** (me). Add `TaDaWidgets` to the project (synchronised folder, iOS and macOS, embedded in the app), its Info.plist and entitlements, and the App Group on both targets. A placeholder widget. Check: the app builds for Mac, the iPhone simulator and the iPhone; `codesign -d --entitlements -` shows the group on the app and the appex; the placeholder appears in the widget gallery.
2. **Snapshot and sync** (me). `WidgetSnapshot` (in a folder both targets build), the `AppModel` extension that builds it, `WidgetSync` started beside `SpotlightSync`, and a store protocol so tests record writes. Check: `TaDaTests/WidgetTests.swift`, written first: Today's rows and order, overdue, counts, the next days, the next task, the no-folder snapshot, the theme colours; a sync writes only on change; moving Today on at midnight.
3. **Widget views** (Home Screen, Lock Screen, empty and no-folder states). Check: `#Preview(as:)` for each family and state; the iPhone simulator's Home Screen and Lock Screen, screenshots compared with the canvas, light and dark, two theme sets.
   *Delegate: `swift-dev`, with this file, the canvas boards and the snapshot type. After step 2. Runs in parallel with step 4.*
4. **Intents and controls** (me). `CompleteWidgetTaskIntent`, the two control intents, `OpenRequest.newTask` on Mac and iPhone, the `taDa://file/` URL. Check: tests that the complete intent's model call sets Done and rewrites the snapshot, and that `.newTask` opens Quick Entry (Mac) and a new task (iPhone); in the simulator, ticking a task in the medium widget writes `status: Done` (`git diff SampleVault`), and each control opens the right place.
5. **Review**. The diff against this plan's decisions.
   *Delegate: `code-reviewer`, given the diff and this file, not my conclusions.*
6. **Docs and release** (me). `docs/architecture.md` (Targets, Widgets), the design framework's In the app table, the canvas's iOS and macOS reference pages updated from the Widgets & Controls page and that page deleted, `docs/releases.md` for the profiles; 0.45.0 with release notes. Check: `xcodebuild … test -skip-testing:TaDaUITests` passes; the release's Mac app shows the widgets after install; the iPhone build has them on the device.

## Risks
- `LiveActivityIntent` running in the app is how the intent reaches the folder; if the app can't open the folder in the background (iCloud not downloaded), the intent fails and the widget's tick reverts. The snapshot holds only what's in the index, so it never shows a task the app can't find.
- The extension's memory limit: the snapshot stays small (Today and 7 days, titles only).
- Developer ID builds with an embedded profile change how Sparkle updates are signed; check an update from the last release keeps the folder and the widgets.
