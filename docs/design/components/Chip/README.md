# Chip

Small pills: `td-chip` filters a list by context, `td-tag` labels a row.

## Filter chip

- 24px tall, `radius-xl`, 12px 600. Off: transparent, `muted`. On (`is-on`, `aria-pressed="true"`): `surface`, `strong`.
- Sits in a row under the view title with a 6px gap. "All" comes first and is on by default.
- Labels are the context exactly as written: `@computer`, `@phone`.

## Tag

- `td-tag` — 1px `border` outline, 11px `muted`, at the end of a row's meta line. For free-form tags only; dates, status and projects have their own glyphs.
