# Menu

A themed list of actions in a floating panel. Two densities share one look: the full menu for the slash, link, checkbox and callout menus in the editor, and the compact file menu for a right-clicked project or task.

## Anatomy

- `td-menu` — `size-menu` (288px) wide, padding 6px, `radius-lg`, 1px `surface` border, on `side` in dark schemes and `bg` in light ones. A soft drop shadow: the one shadow in the app, since the menu floats above the window.
- `td-menu-item` — `size-menu-item` (34px), padding 0 10px, `radius-md`, `task` text in `fg`, a 16px glyph in `muted` on the left and its syntax or shortcut on the right in `muted`.
- `td-menu-label` — an uppercase group label (`label` style, `muted`): Blocks, Subtasks, Icons, Type, Fold.
- `td-menu-foot` — the key hints under a hairline: ↑↓ Navigate, ↵ Insert or Set, esc Close.
- `td-menu-sep` — a 1px `border` line with 3px above and below, before destructive items.

`td-menu.is-compact` is the file menu: `size-menu-compact` (196px), padding 4px, items `size-menu-item-compact` (26px) with padding 0 8px, `radius-sm`, `body` text and 14px glyphs. No group labels and no footer; shortcuts sit on the right.

## States

- `is-active` — the highlighted item: `surface` fill, `strong` label, glyph in `accent`. The arrow keys and the pointer move it.
- `is-danger` — Delete Forever: label and glyph in `deadline`; highlighted, a `deadline` tint (14% on light schemes, 22% on dark).
- The slash, link, checkbox and callout menus open with an item highlighted (the first, the current marker or the current type). The file menu opens with none, as macOS context menus do.

## File menu

- Opens at the pointer on a right-click or control-click; the right-clicked row gets a 2px `accent` inset ring (`td-row.is-target`, `td-nav-item.is-target`) while it's open.
- Items: Move (⇧⌘M; the area menu for a project), Schedule (⌘S), Set Deadline… (⌘D), Reveal in Finder (no shortcut) and Delete (⌘⌫) for a file in the folder; Restore (⌘⌫), Reveal in Finder and, after a separator, Delete Forever (⌥⌘⌫) in Trash.
- A right-click on a picked row acts on every picked row, and Move, Schedule and Delete name the count: "Move 3 Tasks", "Schedule 3 Tasks", "Delete 3 Tasks". Reveal in Finder selects every picked file in one Finder window. A right-click on any other row acts on that row only.
- Move opens the project menu, and Schedule and Set Deadline… the date menu, at the pointer in the file menu's place; the row stays ringed until it closes. For several files the date menu fills a date only when they all share it.

## Embed menu

- Opens at the pointer on a right-click on a drawn image, which is selected and gets a 2px `accent` ring while the menu is open. A click selects an image the same way.
- Items: Copy (⌘C), Cut (⌘X), then Rename…, Reveal in Finder and Delete (⌘⌫). The shortcuts work on a selected image without the menu; ⌫ removes only the `![[ ]]`.
- On iPhone a press and hold opens Copy, Cut, Edit Markdown, Rename… and Show in Files, then Delete in `deadline`.

## Callout menu

- Opens under a callout's icon on a right-click or control-click on its title line; the callout gets the same 2px `accent` inset ring (`td-callout.is-target`).
- Groups: Type (the thirteen callout types, icons in their colours, `[!type]` on the right) and Fold (Always open, Foldable, open, Foldable, folded). Ticks mark the current type and fold. Rules are in `components/Callout/README.md`.
