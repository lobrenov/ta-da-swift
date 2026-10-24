# Menu

A themed list of actions in a floating panel. Two densities share one look: the full menu for the slash, link, checkbox and callout menus in the editor and the property chips' status, move, area, tag and date menus, and the compact file menu for a right-clicked area, project, task or note and the compact rightClickMenu.

## Anatomy

- `td-menu` — `size-menu` (288px) wide, padding 6px, `radius-lg`, 1px `surface` border, on `side` in dark schemes and `bg` in light ones. A soft drop shadow: the one shadow in the app, since the menu floats above the window.
- `td-menu-item` — `size-menu-item` (34px), padding 0 10px, `radius-md`, `task` text in `fg`, a 16px glyph in `muted` on the left and its syntax or shortcut on the right in `muted`.
- `td-menu-label` — an uppercase group label (`label` style, `muted`): Blocks, Subtasks, Icons, Type, Fold.
- `td-menu-search` — the move, area and tag menus' field above the list (the date menu's above its month): 30px, `surface`, `radius-md`, a `muted` glyph (`magnifyingglass`, `calendar`), 13px `strong` text and an optional `muted` note on the right. It has the keyboard.
- `td-menu-foot` — the key hints under a hairline: each key on a `td-key` cap (10.5px 500 `fg` on `surface`, 4px corners) and what it does: ↑↓ Navigate, ↵ Insert or Set, esc Close.
- `td-menu-sep` — a 1px `border` line with 3px above and below, before destructive items.

`td-menu.is-compact` is the file menu: `size-menu-compact` (196px), padding 4px, items `size-menu-item-compact` (26px) with padding 0 8px, `radius-sm`, `body` text and 14px glyphs. No group labels and no footer; shortcuts sit on the right.

## States

- `is-active` — the highlighted item: `surface` fill, `strong` label, glyph in `accent`. The arrow keys and the pointer move it.
- `is-danger` — Delete Forever: label and glyph in `deadline`; highlighted, a `deadline` tint (14% on light schemes, 22% on dark).
- The slash, link, checkbox and callout menus open with an item highlighted (the first, the current marker or the current type). The file menu opens with none, as macOS context menus do.

## File menu

- Opens at the pointer on a right-click or control-click; the right-clicked row gets a 2px `accent` inset ring (`td-row.is-target`, `td-nav-item.is-target`) while it's open.
- A task's or project's menu starts with its status boxes in a row spread across its width: Not Started, Doing, Ongoing (projects only), Blocked, Done and Cancelled, each 16px in a 28px square (`radius-sm`), then a separator. The current status has an `accent` tint (14% light, 22% dark), the hovered box `surface`; each says its status in a tooltip. A click sets it and closes the menu. On picked rows the boxes set every picked file; Ongoing shows only when they're all projects, and the tint only when they share a status.
- Items for a task or project: Move (⌘P; the area menu for a project), Schedule (⌘S), Set Deadline… (⌘D), Tags… (⌘T, one file only), Reveal in Finder (no shortcut) and Delete (⌘⌫). For an area: New Task in and New Project in it, Open Area File, Tags…, Reveal in Finder and Delete. For a note: Task…, Project… and Area… (converting it, the folder each goes to on the right), Tags…, Move to Folder…, Reveal in Finder and Move to Trash. In Trash: Restore (⌘⌫), Reveal in Finder and, after a separator, Delete Forever (⌥⌘⌫).
- A right-click on a picked row acts on every picked row, and Move, Schedule and Delete name the count: "Move 3 Tasks", "Schedule 3 Tasks", "Delete 3 Tasks". Reveal in Finder selects every picked file in one Finder window. A right-click on any other row acts on that row only.
- Move opens the project menu, Schedule and Set Deadline… the date menu, and Tags… tagMenu, at the pointer in the file menu's place; the row stays ringed until it closes. For several files the date menu fills a date only when they all share it.

## Link menu

- Opens under the `[[` (files to link) or `![[` (images to embed) as it's typed, or after the slash menu's Wikilink or Image; the text typed after it is the query. The footer's ↵ says Link or Embed.
- `[[` rows: a task's status box with its project or area (or Loose task) on the right, a project's ring with Project, an area's cube with Area. An empty query lists up to 8 recently opened files under Recent, leaving out the open file, or every file when none has been opened; a query ranks recent files first, then the rest by title.
- `![[` rows: each image's thumbnail and filename, newest first, under Attachments while the query is empty.
- Up to 50 rows. With no matches it says "No matching files" and ↵ goes to the editor. A click elsewhere or a scroll closes it and keeps the typed text.
- On iPhone the choices are a list above the keyboard bar; a tap picks one.

## Embed menu

- Opens at the pointer on a right-click on a drawn image, which is selected and gets a 2px `accent` ring while the menu is open. A click selects an image the same way.
- Items: Copy (⌘C), Cut (⌘X), then Rename…, Reveal in Finder and Delete (⌘⌫). The shortcuts work on a selected image without the menu; ⌫ removes only the `![[ ]]`.
- On iPhone a press and hold opens Copy, Cut, Edit Markdown, Rename… and Show in Files, then Delete in `deadline`.

## Delete dialogs

- **Delete image** (the embed menu's Delete): a 500px sheet with a 64px thumbnail, “Delete “name”?”, what happens to the embeds, and the path and size in mono `muted`. Under an EMBEDDED IN label, each file that embeds it: its icon, title, project or area, a This file badge for the open file and the embed count when it's more than one. Then Cancel and Delete (`danger`). On iPhone, a sheet ending in Move to Trash.
- **Delete with attachments** (deleting files that embed images): a 540px sheet listing each file's images, under a header per file when there are several. Each row is a tick (a 16px rounded square; a 24px circle on iPhone), a thumbnail (34px; 44px on iPhone), the name and a note of the other files that embed it. An image another file still embeds starts unticked. A summary counts the files and ticked images; Cancel and Delete (`danger`), or Move to Trash in `deadline` on iPhone. Files without images ask with an alert, or not at all.

## rightClickMenu

- A compact menu in sections with a divider between, opened under what was right-clicked: on a table's row or column grip, which gets the 2px `accent` ring while it's open. Items have a title, an optional glyph, an optional shortcut hint on the right and a tick for the current choice. Later uses add items, not menus.
- Row grip (the header's too): Insert above, Insert below, Delete row. Deleting the header makes the next row the header.
- Column grip: Insert left, Insert right, Delete column, then Align left, Align centre, Align right (the current one ticked).
- Deleting a table's last row or only column deletes the table.

## Callout menu

- Opens under a callout's icon on a right-click or control-click on its title line; the callout gets the same 2px `accent` inset ring (`td-callout.is-target`).
- Groups: Type (the thirteen callout types, icons in their colours, `[!type]` on the right) and Fold (Always open, Foldable, open, Foldable, folded). Ticks mark the current type and fold. Rules are in `components/Callout/README.md`.
