# TaskRow

One task file as a row in a browser list: checkbox, title, and a meta line drawn from its frontmatter.

## Anatomy

- `td-row` — flex row, `radius-md`, padding 7px × 10px, gap 10px. `is-selected` fills it with `surface` when the file is open in the editor, or when it's one of several picked rows. `is-target` rings it with a 2px `accent` inset while its file menu is open.
- A `td-checkbox` (its own button) and a second button holding the title and meta, which opens the file. Never nest one inside the other.
- `td-row-title` — `task` style, up to two lines. Selected: `strong`. Done or cancelled: `muted`, struck through.
- `td-meta` — `meta` style in `muted`, one line, gap 12px. Order: the task's project or area (where the list's groups don't show it), subtask count `2/5`, repeat rule, due ("Due Tue 6 Oct", calendar in `due`), deadline ("Deadline today", flag in `deadline`), then the tag count (`tag` in `accent`). An overdue date's text is `deadline`. A done task shows no dates. It never repeats status: the checkbox is the only place a row shows it.

## Selection

- A click opens the file. Shift-click picks a range from the last task clicked on its own or ⌘-clicked; ⌘-click adds or removes one task. Every picked row shows `is-selected`, and the editor shows "N tasks selected" instead of a file.
- Picked tasks that a filter or search hides drop out of the selection, so nothing unseen is deleted.
- Escape clears the selection; ⌫ moves the picked tasks to the trash; ⌘P opens the project menu, and ⌘S and ⌘D the due date's and deadline's calendar, under the first picked row.
- Rows drag onto the sidebar's projects, areas, Loose tasks and Agenda, and into other apps as their files; dragging a picked row takes every picked task.

## Rules

- Show only what the view does not already say: an Agenda day shows only an overdue due date; a project hides its own name; a project's or area's task list shows date icons without the words.
- Dates are short and relative where possible: "Today", "Tue 6 Oct", "Deadline Fri 16".
- Let the title wrap to a second line rather than truncate in the browser pane.
