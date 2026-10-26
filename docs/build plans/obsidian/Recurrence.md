# Ta Da for Obsidian — Recurrence

## Context
Ta Da's recurrence (`docs/build plans/recurrence v1.md`) gives a task a `repeat` rule; Ta Da's daily logging moves a completed repeating task forward instead of logging it. Its R6 ports the rule, the next date, the occurrences query and `dayMarks` to the plugin's core. This plan brings the app's recurrence UI to the plugin, as designed on the canvas's Repeating tasks page, and pairs with the Ta Da version that ships recurrence.

## Decisions
- **No rollover in the plugin.** A repeating task completed in Obsidian stays Done until Ta Da's next logging run moves it forward. The plugin shows where it will move.
- **Same design as the app**, in Obsidian's own controls where the app uses native ones: the status menu is Obsidian's `Menu`, the date picker is `DateModal`.
- **Writes**: `repeat` is spliced through `Writer` with the ported frontmatter editor, as dates are now. Status writes are unchanged.
- No default hotkeys, sentence-case text.

## Surfaces
- **Date modal** (`DateModal`, `src/ui/header/modals.ts`), for the due date only:
  - the field reads a phrase starting with `every` as a rule as it's typed (prompt "Type a date or rule: fri, every mon"); ↵ sets it, and the due date to the first occurrence when there's none;
  - the month (`monthGrid`) shows coming occurrences on a faint `due` fill, stopping at `until`;
  - a Repeat section under the month: Stop when set; the rule spelled out, muted while previewed; "Type repetition rules naturally. They're recognised as you type."; once set, a When done toggle and an Ends row;
  - Ends swaps the modal to the end date: "‹ Repeat ends", the field ("Type an end date: 20 dec, 8w"), Never, In 4 weeks, End of year, and the month.
  - The New task modal opens the same modal from its due chip.
- **Header chips** (`headerModel.ts`, `buildChip`): after the due date, `·`, the repeat icon and the rule's frequency in muted, with the rule, end and next date as its tooltip; on the deadline chip when there's no due date, on the dashed due chip when there's no date. An unreadable rule shows as written after a warning icon.
- **Rows** (`rows.ts`): the repeat glyph in muted with the rule as its tooltip; a done or skipped repeating task shows "↻ <date it moves to>" instead of its date, or "↻ Ended" when `until` ends it.
- **Status menu** (`openStatusMenu`, `src/ui/header/pickers.ts`) on a repeating task: Cancelled reads "Skip this time"; Done and Skip show "moves to <date>" (Done: "ends the repeat" on the last occurrence). The Set status commands keep their names.
- **Agenda** (`agenda.ts`, `listModel.ts`): days after a task's current date list its occurrences in a Repeats group under the day's tasks: muted titles, the repeat glyph, a box that can't be ticked, a click opening the task, "≈" on a when-done estimate, a Deadline pill on a deadline occurrence. A week counts its repeats ("2 tasks · 4 repeats"). The strip's marks come from the ported `dayMarks`.
- **Logbook** (`logbook.ts`): Completed today leaves out repeating tasks that will move forward; one whose `until` ends it stays.

## Steps
Each depends on Ta Da's R6 (the core port) being in the plugin.
1. **Date modal**: the rule field, preview, Repeat section and Ends view, and the `repeat` write. Check: jsdom tests for the modal's states (date vs rule phrase, ↵ with and without a due date, Stop, When done, Ends) and the written line; by hand in SampleVault, desktop and iPhone.
2. **Chips, rows, status menu and Logbook**. Check: unit tests for the chip label and tooltip, the rows' "↻" text, the menu titles and the Logbook groups; by hand.
3. **Agenda**: the Repeats group, week counts and marks. Check: unit tests for the day and week models with occurrences; by hand on a vault with daily, weekly and when-done rules.
4. **Docs and version**: `CLAUDE.md` in the plugin; Ta Da's `docs/architecture.md` (Obsidian section); the canvas's Obsidian pages get the modal, chips and Agenda. The plugin's next `y` version (`manifest.json`, `package.json`, `versions.json`), tagged, with its row in `docs/versioning.md`'s pairing table. Check: `npm test` and `npm run build` pass; the plugin in SampleVault matches the apps on the same files.

## Risks
- A vault opened only in Obsidian never rolls repeating tasks forward; they stay Done, showing where they'd move. Step 4 adds a line to the plugin's README saying recurrence needs Ta Da.
- Obsidian's Properties panel shows `repeat` as plain text; edits there are read like any other.
