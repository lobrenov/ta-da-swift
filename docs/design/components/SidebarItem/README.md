# SidebarItem

A 32px navigation row in the sidebar: a coloured 16px icon, a label and an optional count.

## Anatomy

- `td-nav` — the 240px sidebar on `side`.
- `td-nav-item` — `size-row` tall, `radius-md`, padding 0 10px, gap 10px. `is-active` fills with `surface`, label `strong` 600, and the link carries `aria-current="page"`.
- `td-count` — right-aligned, 12px `muted`.
- `is-target` — a 2px `accent` inset ring while a project row's file menu is open.
- `td-nav-label` — the uppercase PROJECTS label (`label` style).

## Domain icons

Each domain owns one icon colour, and it never changes with selection:

| Domain | Icon | Token |
| --- | --- | --- |
| Today | filled star | `due` |
| Upcoming | calendar | `deadline` |
| Loose tasks | tray | `accent` |
| Logbook | book with tick | `done` |
| Trash | bin | `muted` |
| A project | progress pie | `accent` |

Order: Today, Upcoming, Loose tasks, a 10px gap, Logbook, Trash, then Projects.
