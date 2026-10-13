# Ta Da — Integrations build plan

## Context
Ta Da shows the device's Calendar events and Reminders beside its tasks in Today and Upcoming, on macOS and iPhone. Design source: the canvas's **Integrations** page at https://claude.ai/artifact/A7c33hg9HUKz41u3wbki3V: `IntegrationsToday`, `IntegrationsUpcoming` and `IntegrationsSettings` (Mac), `IosIntegrationsToday`, `IosIntegrationsUpcoming` and `IosIntegrationsSettings` (iPhone).

Starting point, as checked on 2026-10-12:
- `AppModel` builds Today (`grouped`) and Upcoming (`upcoming`, from `Queries.upcoming(after:)`) once per change and when `today` changes. Upcoming has no end date: it lists every open task dated after today.
- Mac: Today is `TaskListView`, Upcoming is `AgendaView` beside `MonthCalendarView`. iPhone: both are in `PhoneScreens.swift` (Upcoming with its week strip).
- Settings live in `UserDefaults` through `SettingsStore`. Mac Settings is `SettingsView` with Vault, Themes and Editor; iPhone Settings is reached from Other.
- The app is sandboxed. TaDaCore uses Foundation, swift-markdown and Yams only.

## Decisions
- **Read-only**: Ta Da never writes to Calendar or Reminders.
- **Switches**: Settings ▸ Integrations has **Show events** and **Show reminders** at the top, then the Calendars list, then the Reminders lists, each with tick boxes grouped by account. Both switches start off.
- **Access**: turning a switch on asks for full access to that store (events and reminders are asked separately). Granted: every calendar or list is shown. Denied: the switch goes back off and its panel says how to turn access on (System Settings ▸ Privacy & Security on the Mac, Settings ▸ Apps ▸ Ta Da on iPhone), with a button that opens the settings.
- **Ticks**: saved per device in `SettingsStore` as the hidden calendar and list identifiers, so a calendar or list added later shows by default.
- **Access lost later**: the events or reminders quietly disappear from Today and Upcoming. Settings shows the denied state.
- **Order**: on every day, events, then reminders, then tasks. Today has no Calendar or Reminders header.
- **Rows**: one line each, shorter than a task row. The calendar's or list's own colour identifies it; no calendar or list name is shown.
  - Event: a colour bar, the start time, the title. No end time.
  - Reminder: a circle in the list's colour, the title. No time. An overdue reminder in Today shows its due date in `deadline`.
- **Multi-day events**: the start time on the first day, All day on the days in between, "until <end time>" on the last day. An all-day event that spans days shows All day on each, with "Day n of m" after the title. A timed event ending exactly at midnight doesn't reach the next day, and its last day shows All day.
- **Past events**: an event that has ended today is dimmed (45% opacity).
- **Reminders shown**: incomplete reminders with a due date. Today: due today or overdue. Upcoming: on their due date. Reminders without a due date never show.
- **Links**: clicking or tapping an event opens Calendar. On iPhone it opens on the event's day (`calshow:` with the day's start in seconds since 2001-01-01). On the Mac it opens Calendar on whatever day it shows. Reminders aren't links.
- **Upcoming window**: events and reminders are fetched from tomorrow to the later of the last date Upcoming lists and the end of next month, so the month calendar is covered, and no more than a year ahead.
- **Calendar marks**: the month calendar (Mac) and week strip (iPhone) get a third, `muted` dot on days with events.
- **Colours**: event and reminder colours come from the user's calendars and lists; everything else uses the theme. Nothing is added to `tokens.json`.

## Milestones
The milestones run in order. Each ends with its check passing. TaDaCore checks run on macOS and the iOS Simulator.

### I1 — Day placement (TaDaCore)
- Value types with no EventKit: `ExternalEvent` (identifier, title, start, end, isAllDay, colour as hex) and `ExternalReminder` (identifier, title, due `LocalDate`, colour).
- `EventPlacement`: for a `LocalDate`, an event's row on that day: `.time(start)`, `.allDay(day:of:)` or `.until(end)`; and `hasEnded(now:)`.
- Reminder rules: `isInToday(today:)` (due today or before), `upcomingDate(after:)`.
- Sorting within a day: all-day first, then by start time, then title.
- Check: Swift Testing cases for single-day, timed multi-day, all-day multi-day, crossing midnight, an event ending exactly at midnight, the time-zone and daylight-saving edges, ended and not ended, overdue and undated reminders.

### I2 — Store and settings (app)
- `TaDa/Integrations/IntegrationsStore.swift` (`@Observable`): one `EKEventStore`; `requestFullAccessToEvents()` and `requestFullAccessToReminders()`; authorisation status per store; the calendars and lists grouped by source; fetches for the Today and Upcoming window; refetch on `EKEventStoreChanged`, on `today` changing and when the app becomes active.
- Switches and hidden identifiers in `SettingsStore`.
- `AppModel` exposes today's events and reminders and the Upcoming ones by date, next to `grouped` and `upcoming`.
- `INFOPLIST_KEY_NSCalendarsFullAccessUsageDescription` and `INFOPLIST_KEY_NSRemindersFullAccessUsageDescription`; the Mac's `com.apple.security.personal-information.calendars` entitlement.
- Check: the app builds for macOS and iOS; core and app tests pass.

### I3 — Settings ▸ Integrations
- Mac: `TaDa/Settings/IntegrationsSettingsView.swift`, a tab in `SettingsView` after Editor: the switches panel, then Calendars and Reminders side by side, with their Off, Asking, Granted and Denied states.
- iPhone: an Integrations route in `PhoneNavigation`, listed in Settings: the switches, then the Calendars and Reminders sections with checkmark rows.
- Denied: Open System Settings (Mac, the Privacy & Security pane) and Open Settings (iPhone, `UIApplication.openSettingsURLString`).
- Check: manual: turn each switch on, allow, deny, untick a calendar, turn off and on again.

### I4 — Today and Upcoming
- `TaDa/Shared/EventRow.swift` and `ReminderRow.swift`, with Mac and iPhone sizes from the canvas.
- Mac: `TaskListView`'s Today and `AgendaView` show events, then reminders, before each day's tasks; `MonthCalendarView` gets the event dot. A hovered event row shows the ↗ and the "Open Calendar" tooltip.
- iPhone: Today and Upcoming in `PhoneScreens.swift` show the same; the week strip gets the event dot.
- Event rows open Calendar (see Links). Rows take no part in selection, arrow keys, the file menu or drag and drop.
- Check: manual against the canvas with a real calendar: a timed multi-day event, an all-day multi-day event, an ended event, an overdue reminder, access revoked in System Settings while the app is open.

### I5 — Docs
- `docs/architecture.md`: the Integrations layer and the files above.
- `docs/design-framework.md`: In the app rows for the event and reminder rows and Settings ▸ Integrations; As built notes where the app differs from the canvas.
- `docs/backlog.md`: Reminders links, completing reminders from Ta Da, iPad.
- Move this plan to `docs/archive/build plans/` when done, and list it in `completed plans.md`.
