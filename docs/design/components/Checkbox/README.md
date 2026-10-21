# Checkbox

The 16px status box that leads every task row and renders every `- [ ]` line in a file.

## States

The box maps the frontmatter statuses (a project's Ongoing too), and the same box carries the full inline set from the editor (see the Iconography section of `docs/design/design-framework.md`).

| Class | Markdown | Status | Look |
| --- | --- | --- | --- |
| `td-checkbox` | `- [ ]` | Not Started | `muted` border, empty |
| `td-checkbox is-doing` | `- [/]` | Doing | `doing` border, 6px inner square |
| `td-checkbox is-blocked` | `- [B]` | Blocked | `blocked` border, 8px bar |
| `td-checkbox is-done` | `- [x]` | Done | filled `done`, tick in `bg` |
| `td-checkbox is-ongoing` | `- [>]` | Ongoing (projects) | `doing` border, `[>]` arrow |
| `td-checkbox is-cancelled` | `- [-]` | Cancelled | `muted` border, dash |

## Rules

- Always 16px, 1.5px border, `radius-xs`. Never scale it up inside a row; 32px is for documentation only.
- Clicking the box completes the task, or reopens a done or cancelled one. It is a real `<button>` with an `aria-label` that names the task ("Complete: Submit timesheet").
- A done or cancelled task's title turns `muted` and is struck through.
- Status colour lives on the box and a 6px dot beside the status name, never on the title text.
