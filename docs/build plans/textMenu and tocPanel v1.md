# Ta Da — textMenu and tocPanel v1

## Context
Two additions to the Live editor. Design source: the canvas's **textMenu** page (`TextMenuMac`, `TextMenuSpec`, `TextMenuAddLink`) and **tocPanel** page (`TocMac`, `TocSpec`, `TocIos`) at https://claude.ai/artifact/A7c33hg9HUKz41u3wbki3V. Briefs: the vault tasks `tasks/textMenu.md` and `tasks/On Hover ToC and links.md`.
- textMenu: a right-click menu on text in the Mac's Live editor, with clipboard, link and formatting commands.
- tocPanel: a file's headings, the files it links to and the files linking to it, from a rail at the editor's right edge on the Mac and a drawer on iPhone.

Starting point, as checked on 2026-11-07:
- A right-click on text falls through the engine's `NativeTextView.menu(for:)` to the system menu. Checkboxes, callout title lines, table grips and images have their own menus.
- `PopupMenu` has no submenus. The Format menu has Bold ⌘B, Italic ⌘I, Highlight ⇧⌘H and Strikethrough ⇧⌘S (`InlineFormat`); ⌘L is Add Subtask.
- `Item.links` holds a body's links; `VaultIndex.backlinks(to:)` lists files whose body links here. Frontmatter links aren't in either. Headings aren't read.

## Decisions
- **textMenu** is the compact `PopupMenu` at the pointer, Mac only, Live mode only. Source mode keeps the system menu; the existing menus keep their targets.
- Rows: Cut ⌘X, Copy ⌘C, Paste ⌘V, Paste as Plain Text ⌥⇧⌘V, Select All ⌘A; on a selection, Add Link and Extract to Task ⌥⌘E; then Format ▸, Paragraph ▸, Insert ▸. With no selection Cut and Copy are off. On a link, Open Link and Copy Link lead.
- Format ▸: Bold, Italic, Strikethrough, Highlight, Inline code. Paragraph ▸: Heading 1–3, Body, Bulleted list, Numbered list, Task, Quote. Insert ▸: Wikilink, Link, Image, Table, Callout, Code block, Divider. Rows use the slash menu's names and icons and run its commands. Format and Paragraph tick what the selection or line already is; a ticked row removes it. With no selection, Format acts on the word under the caret.
- Submenus open beside their row on hover or →; ← or moving off closes them.
- **Add Link** opens the link menu under the selection with a search field (`PopupField`) holding the selected text, selected. A pick writes `[[Title|selection]]`, or `[[Title]]` when they match ignoring case. The last row, Link “selection”, writes `[[selection]]`. esc leaves the text.
- **Extract to Task** on a selection makes a task named by the selection and replaces it with its `[[link]]`, as the checkbox menu's does.
- Copy Link copies the `[[wikilink]]` as written; Open Link opens the file as a click does.
- **tocPanel** lists Contents (body headings H2–H6, indented by level), Links (resolved and unresolved body links, once each, in first-appearance order; embeds aren't links) and Backlinks (`backlinks(to:)`). Frontmatter links are on neither side, so a project or area doesn't list its children. An empty section is left out; a file with no headings and no links has no rail.
- Mac: a rail 18pt in from the editor's right edge, a dash per heading (H3 and deeper shorter), the section in view in `accent`, then a link mark when there are links. It hides while typing and returns on pointer movement. Hovering it 150ms fades the panel in (120ms); it fades out 300ms after the pointer leaves both. The panel is the popup panel's chrome, 260pt wide, scrolling when taller than the editor.
- A heading row scrolls its line to the top; a file row opens the file. An unresolved link is struck through in `muted`.
- iPhone: a swipe in from the right edge of a file screen opens a drawer (318pt, `side` on dark schemes, a scrim over the file) with the same sections as an inset list; swiping right or tapping the scrim closes it. No rail.
- Every file type has it: tasks, notes, projects and areas. The meta line's "N backlinks" menu stays.
- No file format change; the Obsidian plugin is unchanged.
- Versions: each step is a `z` release from 0.37.5; the finished plan is 0.38.0.
- Not in v1: textMenu on iPhone, unlinked mentions, heading levels beyond the slash menu's in Paragraph ▸.

## Steps
1. TaDaCore: `BodyScan.headings` (level, text, line), skipping code, front matter and callout titles; `Item.headings`; `VaultIndex.links(from:)` returning each body link once as a resolved item or an unresolved title. Check: `BodyScannerTests` and `VaultIndexTests`, written first, pass on macOS and the iOS Simulator; `LargeVaultTests` timings no worse.
2. Fork (`-live.11`): `onTextMenu` for a right-click on text that no other menu takes, carrying the selection or caret, the link under the pointer, the selection's inline formats, the line's block kind and the anchor, with actions to run an inline format, a slash command, paste as plain text and replace the selection. `onVisibleTopLine` while scrolling and `scroll(toLine:)`. Check: fork tests; tag; the pin bumped here.
3. `PopupMenu` submenus: a row with children opens a compact panel beside it, by pointer or arrow keys. Check: `PopupMenuTests` cover open, close and key routing; the table grip menu is unchanged.
4. textMenu: `TextMenu` in `TaDa/Editor/TextMenu.swift`, its rows per target and ticks, wired in `LiveEditor`. Check: `TextMenuTests` cover rows for a caret, a selection and a link, and the ticks; each row works in the app on SampleVault; `git diff SampleVault` shows only the intended edits.
5. Add Link: the link menu with a `PopupField`, the alias rule and Link “selection”. Check: `LinkMenuTests` cover `[[Title|selection]]`, `[[Title]]` on a case-only difference and the unresolved row.
6. tocPanel on the Mac: `TocRail` and `TocPanel` in `TaDa/Document/TocPanel.swift` over the Live editor, with the hover, typing and current-heading rules. Check: `TocPanelTests` cover the sections and what's left out (frontmatter links, embeds, empty sections); `DesignRenderTests` gain the rail and the open panel.
7. tocPanel on iPhone: `PhoneTocDrawer` in `TaDa/iOS/PhoneTocDrawer.swift` on `PhoneFileScreen`. Check: the swipe opens and closes it in the simulator without catching the back swipe or the editor's horizontal scrolling.
8. Docs and canvas: the design framework (In the app: Menu, tocPanel; As built), the Menu guideline for submenus, `docs/architecture.md` (editor menus, tocPanel), the reference pages updated from the feature pages and the feature pages deleted. Check: app and core tests, UI tests (with permission), and a pass on SampleVault on Mac and iPhone.
