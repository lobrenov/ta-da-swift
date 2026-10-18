# Ta Da — Daily Agenda build plan

## Context
Daily and week notes, and one Agenda that shows a single day or week at a time in place of Today and Upcoming. On the iPhone the tab bar becomes Agenda, Tasks, Tags, Notes and Other. Design source: the canvas's **Agenda & daily notes** page at https://claude.ai/artifact/A7c33hg9HUKz41u3wbki3V.
- **Mac:** `AgendaMacAgendaB2` (a day), `AgendaMacAgendaB2Week` (a week picked, month open) and `AgendaMacSettings`.
- **iPhone:** `AgendaIosDay`, `AgendaIosDayWeek`, `AgendaIosDayMonth`, `AgendaIosNote`, `AgendaIosTasks`, `AgendaIosTags`, `AgendaIosNotes` and `AgendaIosOtherB`.
- **Not built:** the page's other boards (B as one continuous list, C1, and the first iPhone row's continuous Agenda).

Starting point, as checked on 2026-10-18:
- **Notes.** Any untyped `.md` file outside `areas/`, `projects/`, `tasks/`, `attachments/` and hidden folders is a note (`Item.isNotePath`), so `Periodic Notes/Daily Notes/2026-10-02.md` is already one.
  - Every item's checkboxes are indexed (`Item.checkboxes`, `BodyScanner`), so a note's unchecked boxes can be counted without reading files.
  - Nothing names or finds notes by date. There are no note templates.
  - `Vault.create` numbers a taken name.
- **Mac.** `AppModel.Domain` has `.today` and `.upcoming`.
  - Today is `TaskListView(.today)`. Upcoming is `AgendaView` beside `MonthCalendarView`, which has no week numbers.
  - `updateLists()` builds `todayTasks` and `upcoming`. `todayCount` drives the badge.
  - ⌘1 and ⌘2 show Today and Upcoming.
- **Integrations.** Events and reminders are fetched from today forward only (`IntegrationsStore.update(today:through:)`), into `todayEvents` and `upcomingEvents` by date.
- **iPhone.** `PhoneTab` is Today, Upcoming, Loose, Projects and Other.
  - `PhoneUpcomingScreen` has a fixed seven-day `WeekStrip` with no week number and no swiping.
  - Tags are reached through Other. Notes are reached only from a tag's page; there is no folder screen.
- **Dates.** `LocalDate` has no ISO week. `MonthGrid` starts on the locale's first weekday.

## Decisions
- **Names.** A daily note is `<daily folder>/YYYY-MM-DD.md` and a week note is `<week folder>/GGGG-[W]WW.md` (ISO year and week).
  - The two folders are set separately in Settings ▸ Daily notes. They default to `Periodic Notes/Daily Notes` and `Periodic Notes/Weekly Notes`, e.g. `Periodic Notes/Daily Notes/2026-10-02.md` and `Periodic Notes/Weekly Notes/2026-W40.md`.
  - Creating the first note creates its folders.
  - The name patterns are fixed. Custom formats go to the backlog.
- **Plain notes.** Daily and week notes are ordinary notes with no `type`. They sit in the notes tree as any folder does, and the format doesn't change. A daily note renamed away from its date name is just a note.
- **Finding a note.** A day's note is the note at its exact path, looked up in the index. It is created only when asked for (Start this day's note, Create in the editor, or typing into the empty editor), never by opening a day.
  - Creating looks the path up first, so a name is never numbered.
  - The new file is `NewFile.note` plus the template's body, if one is set.
- **Templates.** Settings picks a note for daily notes and one for week notes, or none. The template's body is copied as it is; its frontmatter is not copied.
- **Week notes switch.** It is in Settings and on by default. When off, week numbers still pick a week, but no week note row or editor is shown.
- **ISO weeks.**
  - The Agenda's week strip and month start on Monday, and every row shows its ISO week number on the left.
  - The date pickers keep the locale's first weekday.
- **Agenda replaces Today and Upcoming.** It shows one period: a day (`today` by default) or a week.
  - It opens on today, and a new day moves it to the new today if it was on the old one.
  - The Mac's ⌘1 shows Agenda, and ⌘2 to ⌘4 become Loose tasks, Trash and Logbook.
  - The badge still counts Today's open tasks. Dropping a task on Agenda makes it due on the selected day.
- **A day lists:**
  - its note row (or Start this day's note);
  - events, then reminders;
  - then tasks.
  - Today keeps Today's task rule (overdue, due or at deadline today, done today), its Group menu and its tag filter.
  - Any other day lists tasks due or with a deadline that day, open or done, grouped the same way.
- **A week lists:**
  - its week note row;
  - a row per day: its note's first line, event and task counts, and its dots. Picking a row goes to that day;
  - then Due this week.
- **From earlier notes** is dropped. Open checkboxes in past notes show only as the hollow dot and the note row's "n open" badge.
- **Dots,** on the week strip, the month and the week's day rows:
  - grey: an event or reminder that day;
  - yellow (`due`): an open task due or with a deadline that day;
  - hollow yellow: unchecked boxes in that day's daily note.
  - A week number is drawn in `link` when its week note exists. Week numbers have no dots.
- **Integrations window.** The fetch covers the shown month, or the selected week if it crosses into another month, through today's existing Upcoming window. It refetches when the selection leaves the covered range.
  - Past days show their events. Reminders stay incomplete-only, so a past day shows only its overdue ones.
- **Mac layout (B2).** Agenda is a browser list beside `DocumentPane`.
  - The header has Week | Month and ‹ Today ›.
  - The list shows the period. The editor shows the period's note by default, or the task or event row clicked.
  - With no note, the editor shows Create `<name>`.
  - ← → step a day, or a week when a week is picked, while the list has focus. ↑ ↓ keep moving the selection.
- **iPhone Agenda.**
  - The week strip has the week number on the left. Tapping a day picks it; tapping the week number picks the week.
  - Swiping the strip moves a week. Swiping the page moves a day, or a week when a week is picked.
  - Tapping the month title or pulling the handle opens the month, and picking in it folds it back.
  - A Today button shows when the Agenda isn't on today.
  - Today's note is drawn inline (its checkboxes, then its first lines), and tapping it opens the file screen. Other days show a note row.
- **iPhone tabs.**
  - Agenda.
  - Tasks: Loose tasks first, then loose projects, then areas with their projects.
  - Tags: today's Other ▸ Tags.
  - Notes: the folder tree, Loose, and a folder's notes.
  - Other: Logbook, Trash and Settings.
  - Move to Folder and Convert on iPhone stay in the backlog.

## Milestones
The milestones run in order. Each ends with its check passing. TaDaCore checks run on macOS and the iOS Simulator.

### D1 — Dates and daily notes (TaDaCore)
- `LocalDate`: `isoWeek` (`ISOWeek`: year and week), `ISOWeek.days` (Monday to Sunday), `ISOWeek.adding(weeks:)`, the ISO week's first day, and the month's weeks as `ISOWeek`s.
- `Index/DailyNotes.swift`:
  - `DailyNoteNames(dailyFolder:weekFolder:)` gives a date's path and a week's path, and reads a path back to its date or week.
  - Lookups on `VaultIndex`: `dailyNote(for:)`, `weekNote(for:)` and `openCheckboxCount(_:)`.
- `Queries`:
  - `agendaDay(_:today:)`: Today's rule for `today`, dated entries for any other day.
  - `agendaWeek(_:today:)`.
  - `dayMarks(from:through:today:)`: per date, whether it has open tasks and whether its daily note has unchecked boxes.
- `NewFile.dailyNote(template:today:)`: the note's frontmatter, then the template's body.
- Check: Swift Testing cases.
  - ISO weeks across a year boundary (2026-W53 and 2027-W01, 2020-12-31 in W53), on both sides of daylight saving, and Monday starts.
  - Names round-trip. Other folders, and both kinds in one folder. A renamed note isn't found.
  - The day and week queries on DesignVault with `today` = 2026-10-02.
  - Marks for a note with " ", "/", "x" and "-" boxes.

### D2 — Model and settings (app)
- `AppModel.Domain`: `.agenda` replaces `.today` and `.upcoming`.
  - `agendaSelection` is `.day(LocalDate)` or `.week(ISOWeek)`. `agendaMonthOpen` is a Bool.
  - `updateLists()` builds the selected period's entries and the shown range's marks. `todayCount` is unchanged.
  - Every switch over `Domain` is updated, including `filterItems`, `newTask` (a new task in Agenda is due on the selected day), `show(_:)`, `BrowserChrome` and `FileInspector`'s places.
- Settings keys in `AppModel.Keys`: `dailyFolder`, `weekFolder`, `weekNotes`, `dailyTemplate` and `weekTemplate`.
- `openOrCreateNote(for:)`: selects the existing note, or creates it with the template and selects it.
- `IntegrationsStore`: a fetch window from the shown range's first day. `AppModel` exposes events and reminders for any fetched date, and `hasEvents(on:)` covers past days.
- Check: the app builds for macOS and iOS.
  - `AppModelTests`, `AreaModelTests`, `IntegrationsStoreTests` and `PhoneNavigationTests` are updated and new cases added:
    - stepping days and weeks;
    - a new day moving the selection;
    - creating a note when the name is taken by another case;
    - the window for a past month.
  - Core and app tests pass.

### D3 — Settings ▸ Daily notes
- Mac: `Settings/DailyNotesSettingsView.swift`, a page after Editor (`AgendaMacSettings`).
  - Daily: the folder (a field, plus a menu of the vault's folders) and a template menu of notes, or None, with the name pattern shown.
  - Week notes: the switch, the folder and a template menu.
- `VaultSettingsView`'s "Folders in the vault" list adds the daily and week folders.
- iPhone: a `dailyNotes` `SettingsSection` in `PhoneSettingsScreen`, linked from Other.
- Check: by hand. Change each folder, pick and clear templates, turn week notes off. The SampleVault diff shows only the notes the app was asked to create.

### D4 — Mac Agenda (B2)
- Sidebar: one Agenda row (with the today count) in place of Today and Upcoming. ⌘1 to ⌘4 in `Commands.swift`.
- `Browser/AgendaStrip.swift`: the week row or the month, with ISO week numbers and the dots, plus Week | Month and ‹ Today ›.
- `Browser/AgendaDayList.swift` and `AgendaWeekList.swift`:
  - The note row and the create row.
  - Events and reminders, reusing `EventRow` and `ReminderRow`.
  - Task rows through `.arrowKeySelection`, with today's Group menu and tag filter.
  - ← → step the period.
- `WorkspaceView`: `.agenda` is `split { … }`. With nothing selected, `DocumentPane` shows the period's note, or Create `<name>`.
- Remove `AgendaView`, `MonthCalendarView` and `TaskListView`'s `.today` kind, with whatever else becomes unused.
- `DesignRenderTests`:
  - The "today" and "upcoming" screens become "agenda-day" and "agenda-week". The "upcoming-task", "source", "search" and "area-today" screens use `.agenda`.
  - DesignVault gets `Periodic Notes/Daily Notes/2026-10-02.md` and `2026-10-01.md`, and `Periodic Notes/Weekly Notes/2026-W40.md`, from the canvas's data, and the design-count tests are updated.
- UI tests: `testDeletingAndRestoringFiles`, `testArrowKeysMoveThroughTodayButNotWhileEditing` and `testDraggingATaskOntoASidebarProject` move to Agenda. Ask before running them.
- Check: renders compared with the boards; by hand on SampleVault.
  - Step through a week with ← →.
  - Pick a week, then a day in the month.
  - Create a day's note from the editor.
  - Drop a task on Agenda.
  - A past day with events.

### D5 — iPhone tab bar
- `PhoneTab`: `agenda`, `tasks`, `tags`, `notes`, `other`, with `PhoneRootView`'s tabs and icons from `AgendaIosTasks`.
- Tasks: `PhoneTasksScreen` (Loose tasks, loose projects, then areas), built from `PhoneTaskListScreen(.loose)` and `PhoneProjectsScreen`.
- Tags: `PhoneTagsScreen` as the tab's root.
- Notes:
  - `PhoneNotesScreen`: the folder tree with folds, then Loose.
  - A `folder(String)` route and `PhoneFolderScreen`: the folder's notes, plus New note and New folder.
  - Rows use `PhoneNoteRow`.
- Other: the Tags row is removed.
- `PhoneNavigationTests`: the rename and delete case covers every tab's stack.
- Check: by hand on a device against the boards. Each tab's stack survives switching tabs. A rename and a delete update every tab.

### D6 — iPhone Agenda
- `iOS/PhoneAgenda.swift`:
  - The header: Agenda, the month title button, and the Today button.
  - `AgendaWeekStrip`: a paged row of weeks, with the week number on the left and the dots.
  - `AgendaMonth`: ISO weeks, with the handle.
  - The day and week pages in a paged horizontal `ScrollView` (`.scrollTargetBehavior(.paging)`) keyed by period, so a swipe moves one period and the strip follows.
- Day page:
  - Today's inline note panel, or the note row, or Start this day's note. Each opens the file screen.
  - Events and reminders.
  - Tasks with today's Group menu and tag filter.
- Week page: the week note panel, the day rows and Due this week.
- New task (+) is due on the selected day.
- Remove `PhoneUpcomingScreen`, `WeekStrip` and the Today tab's screen.
- Check: by hand on a device.
  - Swipe across a week and a month boundary.
  - Swipe the strip.
  - Open the month and pick a week.
  - Start today's note and tick a box in it, then check the hollow dot clears.
  - Dynamic Type at the largest size.

### D7 — Docs and canvas
- `docs/file-format.md`: a Daily notes part under Notes (the two folders and their defaults, names, templates; they're plain notes).
- `docs/architecture.md`:
  - Agenda in Files, Runtime, Window and Shortcuts.
  - The iPhone tabs.
  - The integrations window.
- `docs/design/design-framework.md`: In the app rows for the Agenda strip, month and day lists; As built notes.
- `docs/backlog.md`:
  - custom name formats;
  - iPhone Move to Folder and Convert;
  - iPad;
  - removed: "Notes on iPhone: the Notes tree and folder screens".
- `CLAUDE.md`: nothing, unless commands change.
- Canvas: the built boards replace Today and Upcoming on the macOS and iOS reference pages, and the Agenda & daily notes page is deleted.
- Move this plan to `docs/archive/build plans/` and list it in `completed plans.md`.
