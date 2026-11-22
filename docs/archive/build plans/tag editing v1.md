# Tag editing v1

## Context
Ta Da indexes every file's tags, logged files included, so stale tags pile up in the tag tree. Tags are written only in `tags:` today and inline tags are never rewritten (`docs/file-format.md`, Writing rules). This plan adds renaming and deleting a tag across every file that carries it, in `tags:` and in the body, in Ta Da (Mac and iPhone) and the Obsidian plugin.

## Decisions
- **Scope**: every file the index reads tags from (live and logged areas, projects, tasks and notes), the same files that fill the tag tree and tagMenu. `.trash/` is left alone.
- **Nesting**: renaming or deleting a tag acts on its children too: renaming `home` to `house` makes `home/garden` `house/garden`; deleting `home` deletes `home/garden`.
- **Rename**: matches ignoring case, so a rename that changes only case rewrites every spelling. The new name must be a valid inline tag (letters, digits, `_`, `-`, `/`, at least one character that isn't a digit or `/`). Renaming to a tag that exists merges them: a `tags:` list that would hold both keeps one.
- **Delete**: removes the item from `tags:` (as `removeTag`), and removes the full `#tag` text from the body with one space next to it (the one before it, or after it at a line's start). A line left blank stays as a blank line.
- **Entry point**: the tag tree's right-click only: Rename… and Delete…, on Mac (sidebar), iPhone (Tags tab, long press) and Obsidian (navigator's tag tree).
- **Confirmation, no undo**: each asks first, naming the file count and child tags, and saying it can't be undone.
- **Failures**: a file whose `tags:` value can't be spliced (as `addTag` leaves alone) keeps that value, the rest of it is written, and the error gives only the count: `n files still have “work”`.
- State kept by tag path follows a rename and drops a deleted tag: `tagFilters`, `expandedTags`, `foldedGroups` (`tag:<path>`), the tag page on screen (`tagPage`, `phoneTagPages`), and the plugin's equivalents.

## Steps
1. **Inline tag ranges** (editor fork). `MarkdownFacts.Tag` gains `column` and `length` (UTF-16, in its line), `TagEdit.rename`/`TagEdit.delete` edit a text's inline tags, and the spec documents them (`spec/edits/tags.json`; the grammar fixtures carry the positions). Tag `0.16.0-live.4`, bump the pin here. Check: fork tests cover ranges in emphasis, after NBSP, nested paths and the non-tag cases in `spec/data/tags.json`.
   *Delegate: `swift-dev` in `~/Projects/swift-markdown-engine-extended`. Blocks every later step.*
2. **Core** (TaDaCore). `FrontmatterEditor.renameTag(_:to:in:)` and `removeTag` extended to children; a body editor that renames or deletes inline tags by the ranges from step 1, skipping what the parser skips; `Vault.renameTag` / `Vault.deleteTag` writing each carrier once (coordinated), returning the items as they now are and the files that failed; a `VaultIndex` query for every carrier of a tag or a child, logged included. Conformance write cases for both editors; regenerate the fixtures. Check: core tests for flow, block, string and unspliceable `tags:`, merge, case-only rename, children, body tags in code/links (untouched), CRLF, the delete spacing rule; `swift test --package-path Packages/TaDaCore` passes.
   *Delegate: `swift-dev`. After step 1.*
3. **Design**. A feature page on the canvas: the tag row's right-click menu, rename in place in the tree, and the confirmation on Mac, iPhone and Obsidian.
   *Me, in this session (needs the Artifact tool and your review). Can run alongside steps 1–2.*
4. **Ta Da app**. `AppModel.renameTag` / `deleteTag` (save the open document first, as `rename` does; reload it if relinked; follow the state above). Mac: the tag tree row's right-click menu, rename in place (`InlineTitleField`, as a folder's), the confirmation alert. iPhone: `PhoneTreeRow`'s context menu on the Tags tab, a rename alert with a field, the confirmation. Check: `TaDaTests` for the model and state following; app builds for macOS and iOS; by hand in SampleVault (`git diff SampleVault` audits every write).
   *Delegate: `swift-dev`. After steps 2 and 3. Runs in parallel with step 5.*
5. **Obsidian plugin**. Port the two editors and the carrier query to `src/core/`, with conformance runs on step 2's fixtures; `renameTag` / `deleteTag` through `Writer` (open files through their `Editor`, closed through `Vault.process`); the navigator tag tree's right-click `Menu` with Rename… and Delete…, a rename modal and a confirmation modal; navigator state follows. Check: `npm test` (fixtures included) and `npm run build` pass; by hand in SampleVault, desktop and iPhone.
   *Delegate: `typescript-dev` in `~/Projects/ta-da-obsidian`. After steps 2 and 3. Runs in parallel with step 4.*
6. **Review**. Review both diffs for correctness against this plan's decisions.
   *Delegate: `code-reviewer`, given the diffs and this file, not my conclusions.*
7. **Docs and version** (me). `docs/file-format.md` (Tags; Writing rules: inline tags are now rewritten by rename and delete), `docs/architecture.md` (Tags, sidebar, iPhone, Obsidian), the canvas reference pages updated and the feature page deleted. Ta Da 0.40.0 with release notes; the plugin's next minor version; the pairing row in `docs/versioning.md`. Check: full `xcodebuild … test -skip-testing:TaDaUITests` passes; UI tests only with your go-ahead.

## Risks
- A rename that leaves a body with `#home` and `#house` both is fine (inline tags may repeat); `tags:` dedupes.
- Writing many files in one action: a large logbook may take a moment; the index is patched per file as it goes.
- Obsidian caches tags in its own metadata cache; the navigator must read the plugin's index, not Obsidian's, after the write.
