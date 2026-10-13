# Ta Da — Date phrases build plan

## Context
Typing in the Mac's date calendar (dateMenu: ⌘S, ⌘D, the date chips, the file menu's Schedule and Set Deadline…) picks a date from a phrase such as `fri`, `3d` or `25/12`, the way Things and Todoist do. Task: `tasks/scheduleMenu natural language on open.md`.

Starting point, as checked on 2026-10-13:
- `CalendarPicker` (`TaDa/Document/CalendarPicker.swift`) shows `CalendarPickerView` in a `PopupPanel`. Its `onKey` takes the arrow keys and ↵ and swallows every other key. `PopupPanel` closes on esc before `onKey` sees it.
- `CalendarPickerModel` has `cursor` (the day ↵ sets), `move(days:)`, `move(months:)`, `onMonthChange` (the panel's height follows the month's weeks), and `thisWeekend(after:)` and `nextWeek(after:calendar:)`.
- TaDaCore's `LocalDate` has `adding(days:)`, `days(to:)` and `weekday`; `startOfMonth` and `addingMonths(_:)` are in the app (`TaDa/Shared/LocalDate+Formatting.swift`).

## Decisions
- **Parser**: our own, in TaDaCore, with no dependencies. English words only.
- **Live**: every keystroke parses the phrase; the cursor (and month) moves to the match. ↵ sets the cursor. With no match the cursor stays where it was. Deleting or clearing the phrase returns the cursor to the date set, or today.
- **Forward only**: a phrase without a year never gives a day before today. A weekday is its soonest coming day; `next` changes nothing (`next fri` = `fri`). A day number is its soonest coming day of that number. A date with no year is its soonest coming one.
- **Today's weekday**: `fri` on a Friday is today.
- **Numeric dates**: the day/month order follows the system's short date format (Settings ▸ General ▸ Language & Region), read in the app and passed to the parser.
- **Times**: ignored (`fri 3pm` = `fri`), also while typed (`fri 3`, `tomorrow 15:`).
- **Scope**: the Mac's dateMenu only. Not Quick Entry's title, not the iPhone date sheet.

### Phrases
| Phrase | Gives |
|---|---|
| `today`, `tod`; `tomorrow`, `tmr`, `tom` | today; tomorrow |
| `mon` … `sunday`, with or without `next`/`this` | the soonest coming weekday (today included) |
| `weekend` | `thisWeekend(after:)` |
| `next week` | `nextWeek(after:)` |
| `next month`; `end of month`, `eom` | the 1st of next month; this month's last day |
| `3d`, `2w`, `1m`, `1y`, `+3`, `in 3 days`, `in 2 weeks`, `in 1 month` | today plus that many days, weeks, months, years |
| `25`, `25th` | the soonest coming 25th (skipping months without it) |
| `25 dec`, `dec 25`, `december 25th`, `25/12`, `25.12`, `25-12` | the soonest coming 25 December |
| `25/12/27`, `25/12/2027`, `25 dec 2027`, `2027-12-25` | that date |

Prefixes count while typing, in this order: `t` and `to` → today, `tom` → tomorrow, `tu` → Tuesday, `th` → Thursday, `s` and `sa` → Saturday, `su` → Sunday, `m`, `w`, `f` → their weekdays, `n`/`ne`/`nex`/`next` → next week. Case and surrounding spaces are ignored. An impossible date (`31/2`) is no match.

### Calendar
- The header row shows the typed phrase in place of DUE DATE or DEADLINE, with a caret, and on the right the day ↵ sets in muted text ("Fri 16 Oct"), or "No match · Fri 16 Oct". The panel keeps its height.
- ASCII letters, digits, space, `/`, `.`, `-`, `+`, `:` and `,` type (40 at most); ⌫ deletes; ←↑↓→ still move the cursor, and keep the phrase. ⌘ and ⌃ shortcuts go on to the window.
- esc with a phrase clears it; esc again closes.
- Footer hints: Move, Type a date, Close before the first key; Set, Delete, Clear after.
- VoiceOver announces each match ("Friday 16 Oct"), or "No match" and the cursor's day.

## Milestones
The milestones run in order. Each ends with its check passing.

### P1 — Parser (TaDaCore)
- `Packages/TaDaCore/Sources/TaDaCore/Model/DatePhrase.swift`: `DatePhrase.parse(_ text: String, today: LocalDate, order: DayOrder, firstWeekday: Int) -> LocalDate?`; `DayOrder` (`.dayMonth`, `.monthDay`).
- `startOfMonth` and `addingMonths(_:)` move from `LocalDate+Formatting.swift`, and `thisWeekend(after:)` and `nextWeek(after:)` from `CalendarPickerModel`, to `LocalDate` in TaDaCore, so the parser and the calendar share them.
- Check: Swift Testing cases for each table row and prefix, both orders, a Friday `today`, month ends (`31` from 30 April, `1m` from 31 January), leap days, year roll-over (`dec 25` on 26 December, `jan 3` on 31 December), and no-match input (`xyz`, `31/2`, `0`, empty). Core tests pass on macOS and the iOS Simulator.

### P2 — Typing in the calendar (app)
- `CalendarPickerModel`: `phrase` and `match`; setting `phrase` parses it and moves the cursor.
- `DayOrder.system` (app side): from `DateFormatter` `.short` style's format, whichever of `d` and `M` comes first.
- `CalendarPicker.handleKey`: typed characters and ⌫ edit the phrase. `PopupPanel` gets a way for `onKey` to see esc first (e.g. `onEscape` returning whether it was handled), so esc can clear the phrase.
- `CalendarPickerView`: the header row and footer hint above; `show` clears the phrase.
- Check: manual: ⌘S on a task, type `fri` ↵; `3d`, `25/12`, `dec 25` ↵; `xyz` then ↵ keeps the cursor's day; esc clears then closes; ⌘D; several picked rows; the file menu's Schedule; the month changes size while typing. App builds for macOS and iOS; app and core tests pass.

### P3 — Docs
- `docs/architecture.md`: `DatePhrase` in TaDaCore, and typing in the calendar under Setting dates.
- `docs/design/design-framework.md`: As built note for the calendar's typed phrase.
- `docs/backlog.md`: phrases in Quick Entry's title and the iPhone date sheet; other languages.
- Move this plan to `docs/archive/build plans/` when done, and list it in `completed plans.md`.
