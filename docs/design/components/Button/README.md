# Button

Text buttons for view actions and dialogs, plus the Live/Source segmented control.

## Variants

| Class | Use | Look |
| --- | --- | --- |
| `td-btn` | Secondary actions: New task, Reveal in Finder, Restore Items, Cancel | 30px, 1px `border`, `fg` |
| `td-btn td-btn-primary` | The one main action of a view: Log Now, Empty Trash | `accent` fill, `bg` text, 700 |
| `td-btn td-btn-danger` | Confirming a permanent delete | `deadline` fill, `bg` text |
| `td-seg` | Live / Source switch in the editor toolbar | `surface` track, `is-on` option on `bg` |

## Rules

- At most one primary button per view, placed directly under the view title.
- Labels say what happens, in title case as macOS does: "Log Now", "Empty Trash", "Restore 2 Items".
- Disabled buttons use `surface` and `muted`; they keep their label.
- Destructive actions confirm inline on the page, never with a system alert.
