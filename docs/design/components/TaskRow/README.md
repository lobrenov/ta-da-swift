# TaskRow

One task file as a one-line row in a browser list: checkbox, one date, title and quiet glyphs drawn from its frontmatter.

## Anatomy

- `td-row` — flex row 32px tall, `radius-md`, padding 0 × 10px, gap 10px, centred. `is-selected` fills it with `surface` when the file is open in the editor, or when it's one of several picked rows. `is-target` rings it with a 2px `accent` inset while its file menu is open.
- A `td-checkbox` (its own button) and a second button holding the date, title and glyphs, which opens the file. Never nest one inside the other.
- `td-row-title` — `task` style, one line, truncated at the end; the full title is its tooltip and accessibility label. Selected: `strong`. Done or cancelled: `muted`, struck through.
- `td-row-glyphs` — icons only, 6px apart, in `muted`, after the title: a note (`doc.text`, when the file has body text), subtasks (`checklist`), repeat (`repeat`), then tags (`tag` in `accent`, `td-ic-tag`). Counts, the rule and the tag names are in each glyph's tooltip and accessibility label. A done or skipped repeating task's `repeat` is followed by the day it moves to ("Tomorrow") or "Ended". Contexts aren't shown.
- `td-row-place` — the task's project or area in `muted`, where the list's groups don't show it.
- `td-row-date` — one date before the title, a pill (`radius-full`, padding 2px × 7px, 12px, no icon): the deadline when set, else the due date. `accent` at 14% (22% dark) with `fg` text; `is-overdue` (a past date, or a deadline today) is `deadline` at the same strength with `deadline` text. The kind and full date are its tooltip and accessibility label. A done or cancelled task shows none. It never repeats status: the checkbox is the only place a row shows it.

## Selection

- A click opens the file. Shift-click picks a range from the last task clicked on its own or ⌘-clicked; ⌘-click adds or removes one task. Every picked row shows `is-selected`, and the editor shows "N tasks selected" instead of a file.
- Picked tasks that a filter or search hides drop out of the selection, so nothing unseen is deleted.
- Escape clears the selection; ⌫ moves the picked tasks to the trash; ⌘P opens the project menu, and ⌘S and ⌘D the due date's and deadline's calendar, under the first picked row.
- Rows drag onto the sidebar's projects, areas, Loose tasks and Agenda, and into other apps as their files; dragging a picked row takes every picked task.

## Rules

- Show only what the view does not already say: the place shows only where the groups don't name it; in the Agenda a due date shows only when overdue, and a deadline reads "Today", "3 days left" or "1 day late"; an Agenda week's row shows the date it's listed for.
- Elsewhere the date is short: "Today", the weekday for the next six days ("Thu"), else "29 Oct" ("29 Oct 2027" in another year).
- The title keeps its line: the place truncates first, then the glyphs drop (their labels stay for VoiceOver).
