# Ta Da — Recurrence v1

## Context
A task with a `repeat` rule comes back after it's completed, in the same file. Its dates move to the next occurrence and it reopens; no file is made per occurrence and none is logged per completion. Both kinds of repetition are covered: a regular schedule (`every Monday`) and after completion (`every week when done`).

Starting point, as checked on 2026-10-26:
- `repeat` is read as text (`Properties.repeatRule`, `PropertyReader`) and shown in task rows only (`TaskRow`). The Obsidian plugin reads it the same way.
- `Completion.setStatus` writes `status` and `completedDate`. `Logbook.filesToLog(completedBefore:)` and `log(_:index:today:)` run once a day and from Log Now.
- `ChecklistEditor.setMarker` splices one checkbox. `Queries.upcomingEntries(of:after:)` and `dayMarks` give the Agenda's entries and marks.
- SampleVault and DesignVault hold `repeat: Weekly · Fri`, which isn't a rule under this plan.

## Decisions
- **Tasks only.** A project's `repeat` stays text, shown as now.
- **Rule**: `repeat:` holds an English phrase, read case-insensitively, day names full or three letters:
  - `every day` | `every N days` | `every weekday`
  - `every week` | `every N weeks`, optionally `on Mon, Thu`
  - `every month` | `every N months`, optionally `on the 15th` | `on the last day` | `on the 2nd Tuesday` | `on the last Friday`
  - `every year` | `every N years`, optionally `on Oct 26`
  - then optionally `until YYYY-MM-DD` and `when done`, read in either order, written in that order.
- **Unreadable rules** (e.g. `Weekly · Fri`) show as text, with a warning, and aren't acted on.
- **Writing**: Ta Da writes the canonical phrase by splicing `repeat:`. A month or year rule is always written with its day (`every month on the 31st`).
- **Completing** is unchanged: `Done` or `Cancelled` with `completedDate`. Cancelling skips an occurrence. Clearing `repeat` ends the series.
- **Rollover**: the daily logging run and Log Now move a completed repeating task forward instead of logging it, in one write:
  - `status: Not Started`, `completedDate` emptied;
  - `dueDate` to the next date; `deadline` moved by the same number of days;
  - subtasks `[x]`, `[/]` and `[-]` reset to `[ ]`; icon markers untouched.
- **Next date**:
  - Regular schedule: the first rule date after the current `dueDate` and on or after the rollover day.
  - When done: `completedDate` plus the interval. With a weekday, the first matching weekday after `completedDate`, then the interval from there.
  - A rule without `on …` takes its day from the current `dueDate`. A missing day clamps to the month's last day.
  - Only a `deadline`: the rule applies to the deadline. Neither date: rollover sets `dueDate`.
- **End date**: `until` is inclusive. When the next date would pass it, the task isn't moved forward; it logs as any completed task.
- **Occurrences**: a TaDaCore query gives a task's occurrences in a date range, with an injected `today`. When-done occurrences are estimates (each assumed done on its due date). A completed task not yet moved forward projects from the date it will move to. Occurrences stop at `until`.
- No counts, no completion history, no repeating projects.
- **Obsidian plugin**: ports the rule, the next date, rollover in its logging, and the occurrences query, against the conformance fixtures.
- **Versions**: each stage is a `z`; the plan ships as the next `y` once completed. The plugin's port is its next `y`, paired per `docs/versioning.md`.

## Stages
Each stage: swift-expert builds it, commit, code-reviewer reviews the commit (up to 5 fixes), swift-expert fixes them, commit. TaDaCore checks run on macOS and the iOS Simulator.

### R1 — Spec
- `docs/file-format.md`: the `repeat` row (tasks: a rule; projects: text), a Repeating tasks section (grammar, next date, rollover, `until`, occurrences), and the Logging rule's exception for repeating tasks.
- Check: the user signs off the section.

### R2 — Rule (TaDaCore)
- `Model/RepeatRule.swift`: the rule value (frequency, interval, weekdays, month day or ordinal weekday, year date, `until`, `whenDone`), `parse(_:)` and `phrase` (canonical writer).
- `Properties.repeatRule` becomes the parsed rule plus its text; an unreadable rule keeps its text and gets a warning.
- Check: Swift Testing cases for every grammar form, both suffix orders, case and three-letter days, round trip parse → phrase → parse, and invalid input (`Weekly · Fri`, `every 0 days`, `every week on Funday`, `on the 32nd`, a bad `until`, empty) warning with no rule.

### R3 — Next date (TaDaCore)
- `RepeatRule.next(dueDate:deadline:completedDate:rolloverDay:)` giving the new `dueDate` and `deadline`, or none when `until` ends the series.
- Check: tests for a regular schedule done early, on time and late; a daily task after two weeks closed; when done with and without a weekday; `every N` intervals; month ends (31st in February, leap years) without drift; ordinal and last weekdays; year rules; no `on …` anchoring on `dueDate`; only a deadline; no dates; deadline offset kept; `until` on, before and after the next date.

### R4 — Rollover (TaDaCore)
- `Writing/Recurrence.swift`: one spliced write of `status`, `completedDate`, `dueDate`, `deadline` and the subtask resets.
- `Logbook`: the daily run and Log Now roll forward repeating completed tasks with a rule and next date, and log the rest as now.
- Check: tests on the written text (only those lines and characters change, CRLF kept, icon markers untouched, missing keys added as writes do now); a Cancelled task rolls; `until` passed logs it; an unreadable rule logs it; a project with `repeat` logs; `git diff SampleVault` after a manual run.

### R5 — Occurrences (TaDaCore)
- `Queries.occurrences(of:from:through:today:)`, each with its date, kind (due or deadline) and an estimated flag.
- Check: tests for regular and when-done rules, a completed task before rollover, `until`, ranges before `today`, and `LargeVaultTests` timings no worse than now.

### R6 — Obsidian plugin
- `writeConformance` fixtures for rules, next dates, rollover output and occurrences; the plugin's core port of R2–R5; rollover in its logging.
- Check: plugin `npm test` against the new fixtures, `npm run build`.

### R7 — Date menu (Mac)
The design is the canvas's Repeating tasks page (Date menu · Repeat).
- **Field**: the due date's menu (due chip, ⌘S, Schedule) reads a phrase starting with `every` as a rule, as it's typed; the prompt is "Type a date or rule: fri, every mon". ↵ sets it, and the due date to the first occurrence when there's none. The note says where it starts ("From Mon 2 Nov").
- **Month**: coming occurrences on a faint `due` fill (`due` at 30%, 26% on dark schemes), stopping at `until`.
- **Repeat section** under the month, after a hairline: a REPEAT label with Stop (clears `repeat`) when set; the rule spelled out ("Every week on Monday"), muted while previewed; the helper text "Type repetition rules naturally. They're recognised as you type."; then, once a rule is set, a When done switch and an Ends row ("Never" or the date).
- **Ends** swaps the menu to the end date: a "‹ Repeat ends" label, the field ("Type an end date: 20 dec, 8w"), Never, In 4 weeks and End of year, and the month; a line under it gives the rule with its end.
- Set Deadline… (⌘D) has no Repeat section. On picked files, the rule shows only when they all share it, and setting one sets it on all.
- `CalendarPicker` and `CalendarPickerModel` (`TaDa/Document/CalendarPicker.swift`); `PopupMenuStyle` sizes follow the section.
- Check: tests for the model (date vs rule phrases, preview, ↵ with and without a due date, Stop, When done, Ends, picked files); the menu in the running app, Quick Entry included.

### R8 — Chips, rows and the status menu
- **Due chip** (`DatePropertyChip`, `TaDa/Document/PropertyChips.swift`): after the date, `·`, the repeat glyph and the rule's frequency ("Weekly", "Every 2 weeks when done") in `muted`; the tooltip gives the rule, its end and the next date. On the deadline chip when there's no due date; on the dashed due chip when there's no date. An unreadable rule shows as written after a `blocked` warning glyph, with "Ta Da can't read this rule, so the task doesn't repeat". The iPhone chips match.
- **Rows** (`RowGlyphs`, `TaDa/Browser/TaskRow.swift`, and `PhoneTaskRow`): the repeat glyph stays `muted`; its tooltip and spoken label give the rule. A done or skipped repeating task waiting to move shows "↻ <date it moves to>" instead of the date pill, or "↻ Ended" when `until` ends it.
- **Status menu** (`StatusChoiceRow`, `TaDa/Document/PropertyPickers.swift`) on a repeating task: Cancelled reads "Skip this time"; Done and Skip say "moves to <date>" (Done: "ends the repeat" on the last occurrence) instead of "sets completedDate". The file menu's Cancelled box (`TaDa/Shared/FileMenu.swift`) and the iPhone status menu use the same wording.
- Check: tests for the chip label, tooltip and the rows' next-date text; the views in the running app on Mac and iPhone.

### R9 — Agenda
- **Day list** (`AgendaDayList`): days after a task's current date list its occurrences in a Repeats group (repeat glyph, `muted` heading) under the day's tasks: `muted` titles, the repeat glyph, a dashed box that can't be ticked, a click opening the task. "≈" marks a when-done estimate; a deadline occurrence has a Deadline pill. Today, Loose tasks, project and area pages and Search are unchanged.
- **Week list** (`AgendaWeekList`): a day counts its repeats ("2 tasks · 4 repeats"); a day with only repeats shows the first in `muted` with the glyph.
- **Marks** (`Queries.dayMarks`, `AgendaStrip`): an occurrence marks its day with the solid due dot, except every day and every weekday rules, which mark none.
- iPhone's Agenda pages match.
- Check: tests for `dayMarks` with occurrences; `LargeVaultUITimingTests` no worse than now; the views in the running app.

### R10 — iPhone date sheet
- `PhoneDateSheet` (`TaDa/iOS/PhoneSheets.swift`): the due date's month shows occurrences on the faint `due` fill; a Repeat row (glyph, "Repeat", the frequency, chevron) over Clear Due Date pushes a Repeat page in the sheet.
- **Repeat page**: back to the date sheet; the rule field (the current rule, placeholder "every 2 weeks on mon"), the rule spelled out, the helper text; a When done switch and an Ends row (a date page like the date sheet's); Stop Repeating in `deadline`.
- Check: the sheet and page in the Simulator and on the phone.

### R11 — Docs and wrap-up
- `docs/architecture.md`, the design framework (In the app and As built), `docs/backlog.md`'s recurrence line removed.
- Canvas: the Repeating tasks boards updated into the macOS, iOS and Menus reference pages, then the page deleted.
- Check: app, core and UI tests (with permission), and a pass on SampleVault on Mac and iPhone.
