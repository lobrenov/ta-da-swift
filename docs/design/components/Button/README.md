# Button

Text buttons for view actions and dialogs, the icon-only file button, and the segmented control.

## Variants

| Class | Use | Look |
| --- | --- | --- |
| `td-btn` | Secondary actions: New task, Reveal in Finder, Cancel | 30px, 1px `border`, 12px `fg` |
| `td-btn td-btn-strong` | A secondary action beside a primary one: Restore Items | 1px `border`, 12.5px 600 `strong` |
| `td-btn td-btn-primary` | The one main action of a view: Log Now, Empty Trash | `accent` fill, 12.5px 700 `bg` |
| `td-btn td-btn-danger` | Confirming a permanent delete | `deadline` fill, 12px 700 `bg` |
| `td-btn td-btn-icon` | Open project file, Open area file: an icon with a tooltip | 28px square, 1px `border`, 12px glyph |
| `td-seg` | Live / Source in the editor toolbar, Appearance in Settings | `surface` track, `is-on` option on `bg` in 600 `strong` |

Heights: 30px by default, 28px in panels and confirmations, 32px in the sidebar.

## Rules

- At most one primary button per view, in its header.
- Labels say what happens, in title case as macOS does: "Log Now", "Empty Trash", "Restore 2 Items".
- Disabled buttons keep their label at half opacity: an outlined one in `muted`, a filled one on `surface`.
- Permanent deletes confirm before they happen, naming what goes and where; the confirming button is `td-btn-danger`.
