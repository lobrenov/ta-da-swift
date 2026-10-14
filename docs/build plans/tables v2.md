# Ta Da — Tables v2 build plan

## Context
In Live, a table edits as a grid instead of showing its `|` source, its cells show markdown, Tab moves between cells, and grab handles move rows and columns. Task: `tasks/Tables v2.md`.

Starting point, as checked on 2026-10-14:
- `MarkdownStyler+Tables.swift` (TaDaMarkdown) parses a GFM table (`ParsedTable`: header, alignments, rows), renders it to one image (`renderTable`, cached by source and theme) and emits it through the `collapsedSource` path block LaTeX uses. A caret inside the table's lines reveals the source.
- Cells already expand `<br>` to a line break and draw inline emphasis (`formattedCellString`); no block markdown.
- `WideTableOverlay` (macOS) hosts a table wider than the text column in a horizontal `NSScrollView` over the text view.
- Right-click menus: the engine reports a request (`TaskMarkerMenuRequest`, `CalloutMenuRequest` in `MenuRequests.swift`); `LiveEditor` shows `CheckboxMenu` or `CalloutMenu`, built on `PopupMenu`.
- The slash menu has a Table entry.

## Decisions
- **Scope**: the Mac's Live editor. iPhone keeps today's rendered image and revealed source. Source mode shows the raw markdown.
- **No source in Live**: the caret never enters a table's source lines. The table is a grid over them; the text view treats its range as one block the caret steps over (as images do with `revealsSourceAtCaret` off).
- **Cells**: one live cell editor at a time, the cell being edited, running the engine with the document's configuration minus tables and embeds (no `![[` query; the slash menu without Table and image entries). Other cells are drawn from the same styler, syntax hidden. Cells show everything the editor does except embeds and tables: emphasis, highlight, code, links, wikilinks, tags, lists, checkboxes, quotes and callouts, with their click and right-click behaviour (checkboxMenu, calloutMenu, link clicks).
- **Line breaks**: a line break in a cell is `<br>` in the file; `|` in a cell is `\|`. Return adds a line break; list continuation works as outside tables.
- **Writes**: every edit rewrites the table's lines with columns padded to line up (`| a   | b |`), keeping each column's alignment marker. It is one splice of the table's line range, never the rest of the body. Padding counts characters.
- **Undo**: one history, the document's. Typing in a cell coalesces as typing does; each structural change (row or column added, removed or moved) is one undo step.
- **Keys** (in a cell):
  - Tab: next cell; on the last cell, a new row with the caret in its first cell. Shift-Tab: previous cell; nothing on the first cell.
  - On a list line, Tab and Shift-Tab indent and outdent instead.
  - ↑ on a cell's first line and ↓ on its last move to the cell above or below; from the header row ↑, and from the last row ↓, leave the table to the line above or below.
  - ← at a cell's start and → at its end move to the previous or next cell, and leave the table past the first or last cell.
  - From the line above or below the table, ↓ or ↑ enter its first or last row; a click puts the caret at the click point in that cell.
- **Handles**: on hover, a row (the header too) shows a grip (`muted`, six dots) in the gutter left of it, and a column a grip centred above its header cell. A click on a grip selects the row or column: a 2pt `accent` ring around it. While one is selected, ⌘C and ⌘X copy it as a markdown table (the header and delimiter rows with it), ⌫ deletes it, and esc or a click elsewhere clears it.
- **Dragging**: dragging a grip moves the row or column, with a 2pt `accent` line at the drop place. The header row can't be dragged and stays first; body rows can't move above it.
- **rightClickMenu**: a reusable Live editor right-click menu, `RightClickMenu` in `TaDa/Editor/RightClickMenu.swift`, built on `PopupMenu`'s compact style: sections of items (title, optional SF Symbol, optional shortcut hint, action). The engine reports a generic request (anchor, a ring to show while open, `close`); the table supplies its items. Later uses (formatting on selected text) add items, not menus.
  - Row grip: Insert above, Insert below, Delete row. The header row's grip (menu only, no drag) has the same items; deleting the header makes the next row the header.
  - Column grip: Insert left, Insert right, Delete column, then Align left, Align centre, Align right (the delimiter row's `:---`, `:---:`, `---:`; the current one checked).
  - Deleting the table's last row (header included) or its only column deletes the whole table, as does ⌫ on such a selection.
- **Widths**: unchanged (columns sized to content; wide tables scroll sideways).

## Milestones
The milestones run in order on `feat/tables-v2`. Each ends with its check passing, then commits, is reviewed and fixed per the stage loop.

### T1 — Table model (TaDaMarkdown)
- `Parser/MarkdownTable.swift`: `MarkdownTable` (header, alignments, rows of cell strings with `\n` for `<br>` and `|` unescaped). `parse(_ source:)` (ragged rows padded, as today), `markdown` (padded lines, `\n` → `<br>`, `|` → `\|`, alignment markers kept), and `setCell`, `insertRow`, `deleteRow` (the header too: the next row becomes it), `moveRow`, `insertColumn`, `deleteColumn`, `moveColumn`, `setAlignment`. `ParsedTable` and the styler's parsing move onto it.
- Check: Swift Testing cases for round trips (padding, alignments, escaped pipes, `<br>`, ragged and empty cells, leading/trailing pipes optional), each operation, and header fixity. Editor tests pass on macOS and the iOS Simulator.

### T2 — The live grid (TaDaMarkdown, macOS)
- `TableGridView` replaces the image for Live on the Mac: it draws cells from the styler, sits where the table's fragment is (inside the wide-table scroll view when wider than the column), and reserves the fragment's height.
- The text view steps the caret over the table range; a click in a cell opens the cell editor there.
- The cell editor writes each change through `MarkdownTable.setCell` and one splice of the table's lines; the grid relayouts as the cell grows.
- Undo and redo restore the table and the cell's caret.
- Check: editor tests drive the text view: click a cell, type (including `**b**`, `- [ ] x`, a wikilink), Return makes `<br>`, the file's lines stay padded, undo/redo; a checkbox in a cell toggles and opens checkboxMenu. Manual: SampleVault tables, a wide table, dark and light themes. App builds for macOS and iOS.

### T3 — Keys
- Tab, Shift-Tab, new row on the last cell, list indent in cells; arrows within, between, into and out of the table, per Decisions.
- Check: editor tests for each key path, including Tab on a list line and ↑/↓ at the table's edges.

### T4 — Handles
- Hover grips, row and column selection ring, ⌘C, ⌘X, ⌫, esc; dragging rows and columns with the drop line, header fixed.
- Check: editor tests for selection, copy (pasteboard holds a valid table), delete and move (one undo step each). Manual: hover and drag feel.

### T5 — rightClickMenu
- Engine: a generic right-click request in `MenuRequests.swift` and `NativeTextViewWrapper.onRightClickMenu`; the table's grips send it with their items.
- App: `RightClickMenu` and its controller in `LiveEditor`, the grip ring kept while it's open.
- Check: manual: each item on a row, the header and a column grip; alignment items; Delete row on the header and on a one-row table; Delete column on a one-column table. App builds; app and core tests pass.

### T6 — Docs and beta
- `Packages/TaDaMarkdown/ORIGIN.md`: change 23 (live tables) and the tests.
- `docs/file-format.md`: tables (padded on write, `<br>` and `\|` in cells).
- `docs/architecture.md`: tables under Live; `docs/design/design-framework.md`: rightClickMenu and the table grid in the In the app table, and As built notes; `docs/design/components/Menu/README.md`: rightClickMenu.
- `docs/backlog.md`: tables on iPhone, column widths, moving the header row, embeds and tables in cells, rightClickMenu formatting items.
- Build bump and beta. Move this plan to `docs/archive/build plans/` and list it in `completed plans.md`.
