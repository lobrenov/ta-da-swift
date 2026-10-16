# SidebarItem

A 32px navigation row in the sidebar: a coloured 16px icon, a label and an optional count.

## Anatomy

- `td-nav` — the 240px sidebar on `side`.
- `td-nav-item` — `size-row` tall (30px for projects), `radius-md`, padding 0 10px, gap 10px, 13px 500 `fg`. `is-active` fills with `surface`, label `strong` 600, and the link carries `aria-current="page"`.
- `td-count` — right-aligned, 12px 500 `muted`; hidden at zero.
- `is-target` — a 2px `accent` inset ring while the row's file menu is open, or while rows are dragged over it: task rows onto a project, an area, Loose tasks or Today (linking them, emptying their project or making them due today), projects onto an area, note rows onto Loose or a notes folder.
- `td-nav-switch` — Tasks | Tags | Notes: a `surface` track (`radius-lg` less 2, padding 2px) of three 26px segments, 12px 500 `fg` with their icons (the area cube, `tag` in `accent`, `doc.text` in `link`); the picked one on `bg` in 600 `strong`. Swiping sideways over the sidebar switches too.
- `td-nav-label` — an uppercase section label (`label` style).

## Domain icons

Each domain owns one icon colour, and it never changes with selection:

| Domain | Icon | Token |
| --- | --- | --- |
| Today | filled star | `due` |
| Upcoming | calendar | `deadline` |
| Loose tasks | tray | `accent` |
| Logbook | book with tick | `done` |
| Trash | bin | `muted` |
| A project | progress ring with a pie (a checklist when Ongoing) | `accent` |
| An area | cube, two-tone | `doing` |
| A tag | tag | `accent` |
| A notes folder | folder | `link` |
| A note (in lists) | page | `muted` |

## Order

Search, Today, Upcoming, a gap, Logbook, Trash, then the switch. Under Tasks: Loose tasks, loose projects, and each area with its active projects under it. Under Tags: Untagged and the tag tree. Under Notes: Loose and the folder tree. At the foot: the folder line ("Watching · <folder>", its icon in `done` while watched), Settings and the New buttons for the list shown.
