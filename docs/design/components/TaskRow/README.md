# TaskRow

One task file as a row in a browser list: checkbox, title, and a meta line drawn from its frontmatter.

## Anatomy

- `td-row` — flex row, `radius-md`, padding 7px × 10px. `is-selected` fills it with `surface` when the file is open in the editor, or when it's one of several picked rows. `is-target` rings it with a 2px `accent` inset while its file menu is open.
- A `td-checkbox` (its own button) and a second button holding the title and meta, which opens the file. Never nest one inside the other.
- `td-row-title` — `task` style. Selected: `strong`. Done: `muted`, struck through.
- `td-meta` — `meta` style in `muted`, gap 12px. Order: subtask count `2/5`, repeat rule, due (calendar in `due`), deadline (flag in `deadline`), context, tags as `td-tag`. It never repeats status: the checkbox is the only place a row shows it.

## Selection

- A click opens the file. Shift-click picks a range from the last task clicked on its own or ⌘-clicked; ⌘-click adds or removes one task. Every picked row shows `is-selected`, and the editor shows "N tasks selected" instead of a file.
- Picked tasks that a filter or search hides drop out of the selection, so nothing unseen is deleted.
- Escape clears the selection; ⌫ moves the picked tasks to the trash; ⌘P opens the project menu, and ⌘S and ⌘D the due date's and deadline's calendar, under the first picked row.
- Rows drag onto the sidebar's projects, Loose tasks and Today, and into other apps as their files; dragging a picked row takes every picked task.

## Rules

- Show only what the view does not already say: Today hides "Due today"; a project hides its own name.
- Dates are short and relative where possible: "Today", "Tue 6 Oct", "Deadline Fri 16".
- One line of title; let it wrap rather than truncate in the browser pane.
