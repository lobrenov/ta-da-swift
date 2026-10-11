# Ta Da — Tags plan

## Context
Tags add a second way to browse files, beside the area and project hierarchy. Design source: the canvas's **Tags** page at https://claude.ai/artifact/A7c33hg9HUKz41u3wbki3V, rows **Tags — macOS** (`TagBrowser`, `TagSidebar`, `TagMenu`), **Tags — editor, rows and data** (`TagBubbles`, `TagRow`, `TagModel`, `TagAutocomplete`) and **Tags — iOS** (`IosTagsOther`, `IosTags`, `IosTagBrowser`, `IosTagMenu`, `IosTagKeyboard`, `IosTagAutocomplete`). Brief: the vault task `tasks/Tags.md`.

Starting point, as checked on 2026-10-12:
- `tags:` in frontmatter and `#tags` in bodies are read nowhere and drawn as plain text.
- `Properties` (`Model/Item.swift`) has no tags. `BodyScanner` walks the body with swift-markdown and collects links and embeds, skipping code and HTML.
- `VaultIndex` keeps maps from titles to tasks and projects; `Queries.grouped` builds Today's area ▸ project order.
- The sidebar lists Today, Upcoming, Loose, Logbook, Trash, then loose projects and the areas. The iPhone keyboard bar has a Heading button that cycles heading levels.
- The link menu (`Editor/LinkMenu.swift`) completes `[[` and `![[`; Settings ▸ Editor ▸ Autocomplete has Brackets, Text formatting, and Wikilinks and embeds.

## Decisions
- **Sources**: a file's tags are its frontmatter `tags:` and its inline `#tags`, merged and deduplicated.
- **Inline syntax**: `#` at a line start or after whitespace, then letters, digits, `_`, `-` and `/`, with at least one non-digit. A tag ends at whitespace, a comma or other punctuation. Not read in code spans, code blocks, headings' `# `, URLs or `[[…#…]]` links. Inline tags hold no spaces, as in Obsidian.
- **Frontmatter syntax**: `tags:` as a flow list, a block list, or one string split on commas. Items may hold spaces. A leading `#` is dropped.
- **Identity**: tags match case-insensitively and show as first written in the vault. `home/` is read as `home`.
- **Nesting**: `/` nests. A parent tag shows its children's files too, and its counts include them. Parents exist whether or not any file carries them alone.
- **No inheritance**: a tagged area or project doesn't tag its tasks.
- **Counts**: files carrying the tag or a child: areas, projects and tasks, done or not. Files in `.trash/` and `.logbook/` aren't counted. **Untagged** is every area, project and task with no tag.
- **Writing**: Ta Da writes only `tags:`, by splicing that key. A file without it gets `tags: [name]` after `createdDate`. An existing list keeps its style (flow stays flow, block stays block). Removing the last tag leaves `tags:` with no value. Body tags are never rewritten.
- **Tint**: one theme token, `accent`, for bubbles, chips, the row glyph, the sidebar and menus. Bubble fill 14% (10% on light schemes), ring 32% (28%).
- **Sidebar**: a Projects | Tags switch under Trash. Projects shows Loose, then the hierarchy as today; Loose leaves the top group. Tags shows Untagged, then the tag tree (16pt per level, last segment only, folds remembered, alphabetical). A sideways two-finger swipe or the mouse's back and forward buttons over the sidebar switch views. The choice is remembered per window.
- **tagBrowser**: the tag's icon and name (parent path muted), a count line, and its child tags as chips. Then Tagged areas and projects, then Tasks grouped by area ▸ project as on Today, with Loose last, then a folded Completed group. No properties.
- **Tags row and tagMenu**: a row under the property chips on task, project and area pages. Filled chips are `tags:` (× on hover removes). + Tag opens tagMenu. "In text" chips list body tags, read-only. tagMenu: search, In this file (`tags:` ticked, body tags greyed "in text"), All tags with counts, Create #name. A pick toggles and the menu stays open. A chip click opens that tag's tagBrowser.
- **taskRow**: the tag glyph and the file's tag count, last on the meta line, after the deadline. Hover lists the tags and where each is written.
- **Editor**: a tag is a bubble with inline code's shape, in the tag tint, `#` at 65%. Plain source on the caret's line. A click opens tagBrowser.
- **tagAutocompleteMenu**: `#` and a first character where a tag can start opens it (never on `#` alone, since `# ` is a heading). The query matches the start of any segment. First-segment matches come first, then by use, then A–Z, up to 50 rows. Return or Tab writes the full path and a space. Space, comma or esc closes the menu and keeps the text, which is how new tags are made. With no match it shows "New tag". Mac: the link menu's compact panel under the caret. iPhone: the link menu's list above the keyboard bar. Settings ▸ Editor ▸ Autocomplete gains a Tags switch, on by default.
- **iPhone**: Tags is the first row in Other (count of tags in use). The Tags screen lists Untagged and the tag tree. The tag screen follows tagBrowser, and its + creates a task with that tag. The file screen gets the Tags row, and + Tag opens a sheet version of tagMenu. The keyboard bar's Heading button becomes a `#` button that inserts `#` at the caret.
- **Contexts**: stay unread. They aren't migrated to tags.

## Milestones
The milestones run in order in one worktree. Each ends with its check passing. TaDaCore checks run on macOS and the iOS Simulator.

### C1 — Model and parsing
- `Tag` value type (`Model/Tag.swift`): normalised path, display spelling, segments, `parent`, `isAncestor(of:)`.
- `Properties.tags: [Tag]` from `PropertyReader` (flow, block, string; `#` dropped).
- `BodyScan.tags: [Tag]` from `BodyScanner`, by the inline rules, skipping code, HTML, headings, URLs and wikilinks.
- `Item.tags`: frontmatter and body merged, each marked with where it's written.
- Check: `TagTests`, `PropertyReaderTests` and `BodyScannerTests` cover every row of the canvas's `TagModel` edge-case table.

### C2 — Index and queries
- `VaultIndex`: a tag → items map patched per item, display spelling by first seen, logged and trashed files left out.
- `Queries`: `tagTree()` (nodes with rolled-up counts), `items(tagged:)` including children, `untagged()`, `tagBrowser(_:)` returning Tagged areas and projects, task groups in Today's order with Loose last, and Completed. `tagSuggestions(_:)` for autocomplete, ordered as decided.
- New fixture `Fixtures/TagVault/` with nested, frontmatter-only, body-only, both, untagged, logged and trashed files. `DesignVault` stays frozen.
- Check: `VaultIndexTests`, `QueriesTests` on `TagVault`; `LargeVaultTests` timings no worse than now.

### C3 — Writing
- `FrontmatterEditor`: add and remove a tag in `tags:`, keeping the list's style; insert the key after `createdDate`; leave an empty key on the last removal.
- `NewFile.task(…, tags:)` for tasks created from a tag.
- Check: `FrontmatterEditorTests`, `NewFileTests` on flow, block, string and missing keys.

### A1 — App model
- `Domain.tag(Tag?)` (nil for Untagged); sidebar view mode per window; tag tree folds remembered.
- `addTag(_:to:)`, `removeTag(_:from:)`, `newTask()` in a tag domain tagging it.
- Check: `AppModelTests` cover the domain, the mode, folds and tag writes.

### M1 — Mac rows, properties and tagMenu
- `TaskRow`: the tag glyph and count with its hover list.
- `PropertyChips`: the Tags row; `tagMenu` beside `PropertyPickers` on the shared `PopupMenu`. Also in `ProjectBrowserView` and `AreaBrowserView` headers.
- Check: macOS build; `PropertyPickerTests`; `DesignRenderTests` renders compared with `TagRow` and `TagMenu`.

### M2 — Mac sidebar and tagBrowser
- `SidebarView`: the Projects | Tags switch, Loose moved, the tag tree, Untagged; swipe and back/forward over the sidebar.
- `TagBrowserView` (from `AreaBrowserView`), shown by `WorkspaceView` for `.tag`.
- Check: `KeyboardTests`; a `DesignRenderTests` render of the sidebar and tagBrowser compared with `TagSidebar` and `TagBrowser`; UI tests (with permission).

### E1 — Editor
- `TaDaMarkdown`: a tag span styled as a bubble in the tag tint, plain on the caret's line; a click handler routed through `LiveEditor` to open tagBrowser.
- tagAutocompleteMenu: the engine tracks the `#` query as it does `[[`; `LiveEditor` shows it in the compact popup on the Mac and the list above the keyboard bar on iPhone. `Autocomplete.tags` and its Settings ▸ Editor switch.
- iPhone keyboard bar: the Heading button becomes `#`, inserting `#` at the caret.
- Check: `swift test --package-path Packages/TaDaMarkdown` (bar the known failure); the editor render compared with `TagBubbles` and `TagAutocomplete`.

### M3 — iPhone
- `PhoneOther`: the Tags row. `PhoneTagsScreen` (tree and Untagged) and `PhoneTagScreen` on new `PhoneRoute` cases, with the + creating a tagged task.
- `PhoneFileScreen`: the Tags row; the tagMenu sheet in `PhoneSheets`.
- `PhoneRows`: the tag count on task rows.
- Check: iOS Simulator build; `PhoneNavigationTests`; the screens checked against the canvas's iOS row in the Simulator.

### D1 — Docs and data
- `docs/file-format.md`: `tags:`, inline tags, identity, nesting, counts and writing rules.
- `docs/architecture.md`: the tag index, the sidebar modes, tagBrowser, the editor's tag spans and autocomplete.
- `docs/design/design-framework.md`: In the app rows for the Tags row, tagMenu, tagBrowser, the sidebar switch, bubbles and tagAutocompleteMenu; As built differences. `tokens.json` and `BundledThemes.swift` only if the tint leaves `accent`.
- `docs/backlog.md`: drop tags; add renaming and deleting tags.
- `SampleVault`: add `tags:` and inline tags to a spread of files.
- Check: all tests (`TaDa.xctestplan`), both package suites, macOS and iOS builds; `git diff SampleVault` shows only the intended edits.

## Out of scope
- Renaming or deleting a tag across files.
- Migrating `contexts:` to tags.
- iPad.
