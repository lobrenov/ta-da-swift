# Ta Da for Obsidian — Type Promotion

## Context
Ta Da 0.34.5 and 0.34.6 promote items up the task hierarchy: Extract to Task makes a subtask a task, and Convert to Project makes a task a project, its subtasks optionally the project's tasks. The rules are in `docs/file-format.md` (Extracting a subtask, Converting); the core is `SubtaskExtraction`, `NoteConversion` and `Vault.convert`/`Vault.extractSubtasks(ofProject:)`. The plugin (`ta-da-obsidian`) ports them, kept in step by the conformance fixtures, and pairs with Ta Da 0.34.6.

## Decisions
- The core ports as written: `src/core/writing/subtaskExtraction.ts` (`extract`, `extractAll`, `taskText`) and `src/core/writing/noteConversion.ts` (`keys`, `text`), on the ported `checkboxSyntax`, `taskMarker`, `frontmatterEditor` (`insertAtTop`, `hasValue`, `clearProperty`), `completion` and `newFile`.
- Note conversion ports only as Convert to Project needs it (a task source). Converting notes stays app-only.
- Writes go through `Writer`: the subtask lines leave the open file through its `Editor` as one transaction (Obsidian's undo brings them back); a closed file through `Vault.process`. New task files are created with the ported `FileNaming` numbering, like New task.
- The move into `Ta Da/projects/` is `FileManager.renameFile`, numbering the name against every project's title, live or logged. Links follow by Obsidian's own link updating, as other plugin renames do.
- Subtasks become tasks only once the project's file has moved; the lines leave its file only once every task is made. A failure leaves the project in place with its subtasks and says so in a `Notice`.
- No default hotkeys, sentence-case text.

## Entry points
- **Extract to task**: the editor's right-click menu (`editor-menu`) on a subtask line, and the command "Extract subtask to task" for the caret's line. Afterwards a `Notice`: "Extracted to a task in <parent>", clicking it opens the task.
- **Convert to project…**: a task's file menu (`file-menu`), a task row's right-click menu in the Tasks and Agenda views (beside the status menu), and the command "Convert task to project" for the active file. It opens a modal, like `NewTaskModal`: status (the task's), area (the task's, or its project's), a "Make its N subtasks tasks under the project" toggle (on) when it has any, where the file moves and Convert to project.

## Steps
1. **Fixtures** (Ta Da): add write cases to `ConformanceExportTests.swift` for `SubtaskExtraction.extract` (each box, icon, quote, callout, fence, nested and tab-indented children, CRLF, last line), `extractAll`, `taskText`, and `NoteConversion.text` from a task to a project; regenerate with `swift test --package-path Packages/TaDaCore --filter writeConformance` and commit. Check: core tests pass.
2. **Core port**: the two writing modules and their conformance runs in `tests/`. Check: `npm test` passes, the new fixture cases included.
3. **Extract to task**: the menu item, command and `Notice` through `Writer`, filed by `VaultIndex.parent`. Check: unit tests for the edit; by hand in SampleVault, Live Preview and Source mode, desktop and iPhone.
4. **Convert to project**: the modal, the three entry points, the rename, then the subtasks' tasks. Check: unit tests for the order of writes and the failure case; by hand in SampleVault, with and without the toggle, a task in a project and one in an area.
5. **Docs and version**: `CLAUDE.md`'s layout and commands lines in the plugin; Ta Da's `docs/architecture.md` (Obsidian section); the canvas's Obsidian page gets the modal and menus. Version 0.3.0 (`manifest.json`, `package.json`, `versions.json`), tagged, and its row in `docs/versioning.md`'s pairing table (0.3.0 | 0.34.6). Check: `npm run build` passes; the plugin installed in SampleVault matches the apps on the same files.

## Risks
- Obsidian's link updating is a user setting: with it off, links to a converted task keep its old path until fixed by hand. The modal says so when it's off.
- An `editor-menu` right-click lands on the caret's line, not necessarily the box clicked; the item acts on the line the menu was opened on.
