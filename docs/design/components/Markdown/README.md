# Markdown

How the Live editor draws a file's markdown. Every marker stays in the file; the editor hides it except on the caret's line.

## Text

- `td-md` — the body: `body-editor` (14/23) in `fg`.
- `td-h1` … `td-h6` — headings `heading-1` (20/28) to `heading-6` (13/20). H1 to H4 are `strong`, H5 `fg`, H6 `muted`; H4 to H6 are 600 weight. Space above: 14, 12, 10, 8, 6, 6px.
- Bold is `strong` at 700, italic is the system italic, `~~struck~~` text is `muted` and struck through.

## Bubbles

- `td-code` — inline code: `code-text` (12.5px mono) in `strong` on `code`, a 1px `border` ring, `radius-sm`, padding 2px 6px.
- `td-mark` — `==highlight==`: `due` at 30% (26% on dark schemes) behind `strong` text, `radius-sm`, padding 2px 4px.
- Both repeat their corners and padding on each line they wrap onto (`box-decoration-break: clone`).

## Links

- `td-wiki` — a resolved `[[wikilink]]` or `[[Title|alias]]`, in `link`. `td-wiki.is-missing` — no such file: `muted`, dashed underline.
- `td-link` — `[text](url)`, in `link` with a 45% underline 3px below the text.

## Blocks

- Lists indent 27.5px a level. Bullets are 6px `muted` glyphs by depth: filled circle, circle, filled square, diamond, then again. Numbers are `muted` and tabular. Task lines use the inline checkboxes (see Checkbox).
- `td-quote` — `muted` text beside a 3px `surface` bar with round ends; each `>` adds a bar.
- `td-codeblock` — `code-text` at 20px line height on `code`, a 1px `border` ring, `radius-lg`, padding 10px 14px. The fence's language sits top right in `muted` 11px. No syntax colours.
- `td-md-table` — a 1px `border` frame with `radius-lg`, the header row on `code` in `strong` 600, `border` hairlines between rows, cells 6px 14px. Columns aligned with `--:` right-align, with tabular numbers.
- `---` is a 1px `border` line.
- Images and `![[embeds]]` fill the text width at their own height, with `radius-lg` corners.
- Callouts: see Callout.

## Editing

The caret's line shows its markdown: mono 13px on `code`, `radius-sm`, extended 10px each side, markers in `muted` and text in `fg`. Inside a callout it keeps the callout's panel.
