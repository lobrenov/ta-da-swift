# Ta Da backlog

Work not yet built.

## Features

- `.itermcolors` import into a theme.
- Developer ID signing and notarisation, or TestFlight for Mac, if Ta Da joins the paid Apple Developer Program: testers would no longer unblock each beta build (`docs/beta-builds.md`).
- Per-file iCloud sync state.
- Attachments: check on a device that an undownloaded iCloud image shows its placeholder size and added date, and that Clean Up's unticked-while-downloading rule holds against a real sync.
- JetBrains Mono as the mono font.
- A better design for a project's linked-tasks table (its columns have fixed widths).
- Tables on iPhone: the live grid (iPhone keeps the rendered image and revealed source).
- Moving a table's header row.
- Embeds and tables in table cells.
- rightClickMenu formatting items (on selected text).
- Lazy cell editors for large tables: a 100×6 table opens in about 0.4 s and a keystroke in a cell takes about 76 ms (debug build).
- iPad: the canvas's iPad POC page, on the iPhone app's code, with events and reminders, and the Agenda.
- iPhone: Remove Callout in the callout menu (the editor's `CalloutMenuRequest` has no remove), Create a New Folder in onboarding, and the domain's icon in list titles.
- iOS UI tests.
- Notes on iPhone: Move to Folder and Convert.
- Daily notes: custom name formats for daily and week notes (the patterns are fixed).
- TestFlight for iPhone, with the paid Apple Developer Program: Personal Team builds expire after 7 days.
- Alias display in the Live editor: `[[Target|Alias]]` shows the target name.
- Renaming and deleting a tag across files.
- Integrations: reminders as links that open Reminders, and completing a reminder from Ta Da (Ta Da only reads Calendar and Reminders).
- Typed dates (`DatePhrase`) in Quick Entry's title and the iPhone date sheet, and in languages other than English.
- Editor markdown as designed (Editor markdown in `docs/design/design-framework.md`; the canvas's Live editor · markdown row): the heading scale, code blocks, and the caret's line in mono on `code`.

## Obsidian

- Restoring and emptying the Trash from the plugin: its Trash list is read only.
- The attachments question in the plugin's Delete project and Delete area: embedded images stay where they are.
- The community plugin store: the plugin is installed by hand.

## Fork Features

- Markdown-style links follow their file: `MarkdownFacts.markdownLinks` (from `0.14.0-live.8`) gives each relative `[text](path)` link and `![alt](path)` image, reference uses included, with its path and range, so a move or rename can rewrite them as it does wiki links and embeds (`docs/file-format.md` says they aren't rewritten).
