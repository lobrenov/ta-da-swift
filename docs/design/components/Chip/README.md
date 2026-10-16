# Chip

Capsule controls 26px tall: `td-chip` shows and edits one frontmatter key, `td-tag` one tag, `td-filter` the tag filter and Group, and `td-meta` chips sit in a row's meta line.

## Property chip

- `td-chip` — `size-chip` (26px), `radius-full`, padding 0 10px, 12.5px `fg`, 5–7px from its glyph. `code` fill inside a 1px `border` ring; `surface` under the pointer.
- One per key under a file's title, 6px apart, wrapping: status (its 7px dot, the name, a `muted` chevron), the parent (a task's project with its ring or area with its cube, a project's area) in `link` (`is-link`), then due date (calendar in `due`) and deadline (flag in `deadline`). A date that has passed is `deadline`; a done file's dates are all `muted`.
- `is-missing` — a key the file doesn't have: no fill, a dashed 1px `surface` ring (`muted` under the pointer), a `plus` and the key's name in `muted`.
- `is-open` — while its menu is open: `surface`, `strong` text and a 2px `accent` ring outside the chip.
- `is-unresolved` — a parent no file has: struck through in `muted`.
- A click opens the chip's menu (status, move, area or date) under it; ⌘-click on a parent opens it. Keys stay ISO in the file; chips show "Today", "Tue 6 Oct".

## Tag chip

- `td-tag` — 26px capsule, a `tag` glyph in `accent`, the tag's name in `strong` with a parent's path in `muted`. Fill `accent` at 10% (14% on dark schemes, 18% and 24% under the pointer), ring `accent` at 28% (32%).
- A file's `tags:` are filled chips; a × appears on hover to remove one. `is-text` — a tag only in the body: outlined in `border`, no fill, after an "In text" label in `muted`; it can't be removed here.
- + Tag ends the file's chips: a `td-filter` pill that opens tagMenu. A chip's click opens the tag's page.

## Filter and Group pills

- `td-filter` — 26px capsule, `muted` label, a dashed 1px `surface` ring; `surface` under the pointer or while its menu is open. `is-on` (tags picked): the tag chip's fill and ring, label `strong`, the filter glyph in `accent`, and when more than one tag is picked their count in a `bg` badge on `accent`.
- The filter row sits under a list's title: Filter, a tag chip per picked tag (× unpicks it), "n of m shown" in `muted` and Clear in `accent`. It hides on a page where no file carries a tag.
- `td-group` — Group on the title's right: `code` fill, `border` ring, "Group" in `muted` then the choice in `fg` and a chevron; `surface` while lit.

## Meta chips

- In `td-meta` (11.5px `muted`), a 10px semibold glyph 4px from its text: subtasks `checklist` `n/m`, `repeat` and the rule, due and deadline dates, and last the tag count, its `tag` glyph in `accent` (`td-ic-tag`); hovering lists the tags.
