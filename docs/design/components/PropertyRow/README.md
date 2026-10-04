# PropertyRow

One YAML frontmatter key and its value, rendered at the top of a file in Live mode.

## Anatomy

- `td-prop` — 28px row, gap 12px.
- `td-prop-key` — the key exactly as written in the file (`dueDate`, not "Due date"), `key` style, 120px column, `muted`.
- `td-prop-value` — `fg`. Modifiers: `is-empty` shows an em dash in `muted`; `is-link` colours a `[[wikilink]]` in `link`. Status values lead with a 7px dot in their status token.

## Rules

- Keep the schema order: `type`, `status`, `area`, `contexts`, `project`, `createdDate`, `completedDate`, `dueDate`, `deadline`, `repeat`.
- Show every key, including empty ones, so the file's shape is visible.
- Dates stay ISO (`2026-10-06`) here; friendly dates belong to rows and chips.
