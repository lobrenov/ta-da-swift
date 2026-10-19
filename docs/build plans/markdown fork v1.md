# Ta Da — Markdown fork build plan

## Context
Ta Da's live editor (`Packages/TaDaMarkdown`) is a hand-kept fork of [swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine) 0.13.0 (`d1421012`) with 23 numbered changes (`ORIGIN.md`). Saga-Swift holds an older copy (`Packages/TaDaMarkdown`, never updated). Upstream has moved on (0.14.0 is out, roughly monthly releases) and the copies don't track it.

The syntax is parsed four ways: the editor's own parser, swift-markdown in TaDaCore (`BodyScanner`) and SagaCore, Lezer in Saga (Tauri) and pulldown-cmark in Saga's Rust index. Wiki-link, tag, task-marker and callout grammar are copied by hand between TaDaCore (`WikiLink`, `InlineTags`, `CheckboxSyntax`, `CalloutType`) and the editor (`WikiLinkService`, `InlineParser`, `TaskMarker`, `Callout`). Background: `~/Projects/Saga/docs/build plans/editor-parity-comparison.md`.

This plan covers:
1. **The spec**: one markdown contract (fixtures and data) that the Swift fork and Saga (Tauri) both build towards.
2. **Consolidation**: a GitHub fork that tracks upstream and is the single owner of the syntax, a Foundation-only syntax target, Ta Da moved onto both, and `BodyScanner` moved onto the fork's parser.

Saga (Tauri) reaching parity with the spec is a separate plan in the Saga repo. Saga-Swift moving onto the fork is the last milestone here, run in the Saga-Swift repo.

Starting point, as checked on 2026-10-16:
- `TaDaMarkdown`: 112 source files, ~63 test files, swift-tools 5.9, no dependencies. Only `TaDa/Editor/LiveEditor.swift` imports it. The workspace and `TaDa.xcodeproj` reference it as a local package.
- Platform imports in the parser layer: `Parser/MarkdownToken.swift` (`NSAttributedString.Key` extensions), `Services/WikiLinkService.swift`, and `Extensions/*` (style attributes). The parser itself sees extensions only through the syntactic `ExtensionRegistry`.
- TaDaCore: swift-markdown 0.9.0 is used only in `Parsing/BodyScanner.swift` (161 lines) and `DependencyAssumptionTests`.
- Saga's golden data: `~/Projects/Saga/test/fixtures/{golden,markdown,parity-vault}`.

## Decisions
- **Repo**: a GitHub fork, `lobrenov/swift-markdown-engine-extended`. A fork of a public repo is public. Ta Da stays private; nothing app-specific goes into the fork. Local clone: `~/Projects/swift-markdown-engine-extended`. The folder name must match the package identity for Xcode's local override to work.
- **Branches**: `main` mirrors upstream and is never committed to. `live` is the editor both apps pin, and the fork's default branch. Merge (never rebase) on `live`. Upstream contributions go on topic branches cut from `main`.
- **Names**: the package, product and module go back to upstream's `MarkdownEngine`, so upstream merges apply cleanly. The Foundation-only target is `MarkdownEngineSyntax`. Upstream's code-block and LaTeX products, `Demo/`, `.github/` and the rest that `ORIGIN.md` says were removed stay in, for the same reason; Ta Da doesn't link them.
- **Versions**: tags `<upstream version>-live.<n>` on `live` (`0.13.0-live.1`, then `0.14.0-live.1` after merging 0.14.0). Apps pin with `exact:`. A tag is never moved or deleted.
- **Fork ledger**: `ORIGIN.md` becomes `FORK.md` at the fork's root: the numbered list of differences from upstream, each marked `Fork:` in the source (was `Ta Da fork`). Each numbered change says which conflict rule applies when upstream touches it (below).
- **Conflict rules**: tables (#23), alias links (#5), alternative checkboxes (#1), callouts (#16) and slash/link queries (#10, #20) stay the fork's; upstream's change is re-applied on top only where it doesn't break the fork's tests. iOS shims (#19) are re-applied over any upstream AppKit change. Everything else takes upstream's version.
- **Spec location**: `spec/` in the fork. It's a new folder, so it never conflicts with upstream. Saga (Tauri) reads it as a git submodule pinned to the same `-live.<n>` tag. Contents:
  - `spec/data/*.json`: task states (marker, label, done, strike, next state), callout types (id, aliases, foldable), tag grammar (allowed characters, terminators, contexts where tags don't apply), wiki-link grammar (target, `#heading`, `#^block`, `|alias`, embed `!`).
  - `spec/grammar/<name>.md` + `<name>.facts.json`: a markdown input and the facts it yields (links with target, heading, block and alias; embeds; tags; tasks with line and marker; callouts with type, fold and line range; headings; tables; summary paragraph).
  - `spec/edits/*.json`: input text and selection, a command, and the expected text and selection (task toggle and set-state, callout set-type and fold, list indent and outdent, Enter continuation, table operations, auto-pairs).
  - `spec/host-api.md`: the shared host vocabulary (triggers, menu requests, services, events; §5.4 of the comparison).
- **Data in Swift**: Swift keeps hand-written tables for task states and callout types; a fork test checks them against `spec/data`. No code generation and no bundled resources.
- **Scope of the syntax target**: grammar and facts only: block and inline parsing, `DocumentParseState`, `MarkdownDetection`, `TaskMarker`, callout parsing, `MarkdownTable`, wiki-link and tag parsing, and a new `MarkdownFacts` scan. Types the editor target needs from it are `package` (SwiftPM 5.9) or `public`.
- **TaDaCore keeps its models**: `WikiLink`, `Tag`, `Checkbox` and `CalloutType` stay TaDaCore's public types (the app doesn't change); their parsing calls into `MarkdownEngineSyntax`. TaDaCore still never imports SwiftUI, AppKit or UIKit.
- **Gate for dropping swift-markdown**: a parity test that runs the old and new `BodyScanner` over DesignVault, the 1,000-file generated vault and `spec/grammar`, and expects identical `BodyScan`s. Each difference is fixed in the fork, recorded as a spec fixture, or accepted as a change to `docs/file-format.md`. `LargeVaultTests`' scan time mustn't get slower.
- **Not in this plan**: the slash catalogue and fuzzy ranking in the spec or fork (TaDaCore keeps `SlashCommand` and `LinkSearch`), a shared `MarkdownEngineUI` target for menus, and Saga (Tauri) work.

## GitHub steps (manual)
Do these before M1. Steps marked *later* belong to the milestone named.
1. Fork `nodes-app/swift-markdown-engine` to `lobrenov/swift-markdown-engine-extended` (github.com/nodes-app/swift-markdown-engine ▸ Fork), keeping the default **Copy the `main` branch only**.
2. *After M1 pushes `live`:* Settings ▸ General ▸ Default branch → `live`.
3. *After M1:* Settings ▸ Rules ▸ Rulesets ▸ New branch ruleset, "live": target `live`, enable **Restrict deletions** and **Block force pushes**. Same for `main`.
4. *After M1:* New tag ruleset, "live tags": target pattern `*-live.*`, enable **Restrict updates** and **Restrict deletions**.
5. Settings ▸ Actions: leave Actions disabled (GitHub's default for forks) unless you want upstream's CI to run on `live`. If you enable it, check the restored `.github/workflows` first.
6. Optional: Settings ▸ General ▸ Features, turn off Issues and Projects so bug reports go upstream or stay in Ta Da.
7. *Upstream contributions (any time after M1):* open the PR from a topic branch on the fork against `nodes-app/swift-markdown-engine:main` in GitHub's UI. For the syntax-target split (M4), open an issue upstream first asking whether they'd take it; if they do, most of the fork's diff from that milestone goes away.

No step is needed in `lobrenov/ta-da-app` or `lobrenov/saga-swift`: the fork is public, so Xcode and `swift` fetch it without credentials.

## Milestones
The Ta Da milestones run on `feat/markdown-fork`; fork milestones run on `live` (or a topic branch merged into `live`). Each ends with its check passing, then commits, is reviewed and fixed per the stage loop.

### M1 — Bootstrap the fork (fork repo)
- Clone the fork to `~/Projects/swift-markdown-engine-extended`, add `upstream`, `git fetch upstream --tags`, `git config rerere.enabled true`.
- `git switch -c live d1421012`.
- Copy Ta Da's `Packages/TaDaMarkdown/{Sources,Tests}` over upstream's `Sources/MarkdownEngine` and `Tests/MarkdownEngineTests`, renaming `TaDaMarkdown` → `MarkdownEngine` in paths, imports and `@testable import`. Keep upstream's `Package.swift` (with its code-block and LaTeX products) and add the fork's platform change (`.iOS("26.0")`). Keep upstream's removed files.
- `ORIGIN.md` → `FORK.md`: the 23 changes, renumbered only if needed, plus the conflict rule for each and the known macOS 27 test failure. `Ta Da fork` markers → `Fork:`. Doc comments that name Ta Da say what the embedder does instead.
- One commit, "Fork changes 1–23 from Ta Da", then `CLAUDE.md` (commands, conventions, the conflict rules, the workflow below).
- Tag `0.13.0-live.1`, push `live` and the tag. Do GitHub steps 2–4.
- Check: `swift test --no-parallel` passes on macOS except the known failure; the iOS Simulator run passes (`xcodebuild -scheme MarkdownEngine-Package -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:MarkdownEngineTests test`). A diff of `Sources/` against Ta Da's copy shows only the rename.

### M2 — Ta Da on the fork (Ta Da)
- Remove `Packages/TaDaMarkdown` from the workspace, the project's local package references and the repo.
- In Xcode: File ▸ Add Package Dependencies, `https://github.com/lobrenov/swift-markdown-engine-extended.git`, Exact `0.13.0-live.1`, product `MarkdownEngine` to the TaDa target only.
- `LiveEditor.swift`: `import MarkdownEngine`.
- Update `CLAUDE.md` (editor tests now run in the fork; the `TaDaMarkdown` conventions name `MarkdownEngine`; link to the fork's `FORK.md`), `docs/architecture.md`, `docs/backlog.md` and `docs/design/design-framework.md` where they name `TaDaMarkdown`. Record what `Package.resolved` now pulls in.
- Check: macOS and iOS app builds; app + core tests (`-skip-testing:TaDaUITests`); design renders match the previous build's; the Live editor behaves the same in a manual pass over SampleVault (tables, callouts, slash menu, images, tags).

### M3 — Take upstream 0.14.0 (fork, then Ta Da)
The first run of the merge workflow, in two steps.

**M3a — the merge.**
- `git merge 0.14.0` on `live`. Resolve conflicts by the rules in `FORK.md`; note any new rule there.
- Tag `0.14.0-live.1`. In Ta Da, bump the exact pin.
- Check: fork tests on macOS and iOS; Ta Da's M2 checks. `FORK.md` lists what 0.14.0 changed that a fork change overrides.

**M3b — completion keys.** 0.14.0 adds directive autocomplete (`onDirectiveCompletion`, `pendingDirectiveCompletion`), which works as the fork's slash, link, embed and tag queries (#10, #20, #24) do: the engine detects the trigger and routes ↑/↓/↵/esc, the embedder draws the list. The fork keeps its query reports and commits (`onSlashCommandChange`, `SlashCommandProxy`) and shares upstream's key path:
- `completionOwner` picks the picker that owns the keys (query, then the `[[…]]` preview, then the directive picker); one router serves `doCommandBy`, ⌘↵ and the iOS key commands, through upstream's `onInlinePreviewKey`. `onSlashCommandKey` is removed. An open query or preview holds back the directive picker.
- `FORK.md` (Completion keys) maps the fork's names to upstream's.
- Tag `0.14.0-live.2`. In Ta Da, `LiveEditor` passes its menu keys as `onInlinePreviewKey`; bump the pin.
- Check: fork tests on macOS and iOS; Ta Da's M2 checks.

### M4 — `MarkdownEngineSyntax` target (fork, then Ta Da)
- New target and product `MarkdownEngineSyntax`, Foundation only, no dependencies. `MarkdownEngine` depends on it.
- Move into it: `Parser/` (less `MarkdownToken`'s `NSAttributedString.Key` extensions, which move to `Styling/`), the `InlineSyntax`/`BlockSyntax`/`ExtensionRegistry` half of `Extensions/MarkdownExtension.swift`, `TaskMarker`, callout parsing from `Callout.swift`, `MarkdownTable`, and the parsing half of `WikiLinkService` (target, heading, block, alias). Tag parsing comes out of `InlineParser` into its own file.
- Mark what the editor uses `package`; keep upstream's public API unchanged (`MarkdownEngine` re-exports nothing new).
- New test target `MarkdownEngineSyntaxTests`; parser tests move there.
- Tag `0.14.0-live.3`; bump Ta Da's pin.
- Check: the syntax target builds with `swift build --target MarkdownEngineSyntax` and has no `import AppKit|UIKit|SwiftUI` (a test greps its sources). All fork tests pass on macOS and iOS. Ta Da builds unchanged.

### M5 — The spec (fork)
- `spec/` as in Decisions. Seed `spec/grammar` from Saga's `test/fixtures/markdown` and `parity-vault`, Ta Da's `TaDaForkTests`, `TagTests`, `MarkdownTableTests` and the DesignVault cases, and `spec/data` from Ta Da's `CheckboxSyntax`/`TaskMarker` and `CalloutType` and Saga's `kinds.ts`. Where Ta Da and Saga disagree, the fixture records the decision and `spec/README.md` lists it.
- `MarkdownFacts` in `MarkdownEngineSyntax`: `MarkdownFacts.scan(_ body:, firstLineIndex:)` → summary, tasks, links, embeds, tags, callouts, headings, built on the block and inline parsers.
- `SpecConformanceTests`: every `spec/grammar` case through `MarkdownFacts`; `spec/data` against the Swift tables; `spec/edits` against the list, auto-pair, task, callout and table functions that are pure today. Edit cases that need a text view are marked `swift: skip` with a reason.
- Tag `0.14.0-live.4`.
- Check: conformance tests pass; every skip has a reason; `spec/README.md` explains the fixture format well enough for a TS runner.

### M6 — TaDaCore on the syntax target (Ta Da)
- `Packages/TaDaCore/Package.swift`: `.package(url: "https://github.com/lobrenov/swift-markdown-engine-extended.git", exact: "0.14.0-live.4")`, product `MarkdownEngineSyntax` on `TaDaCore`. The Xcode project's pin is bumped in the same commit (SwiftPM refuses two different exact pins).
- `WikiLink(inner:)`, `InlineTags`, `CheckboxSyntax` and `CalloutType`'s markers call the syntax target; their duplicated grammar is removed. Public TaDaCore API is unchanged.
- Check: core tests on macOS and iOS; app + core tests; `docs/file-format.md` unchanged (or updated with any decision M5 recorded).

### M7 — `BodyScanner` on the fork's parser (Ta Da)
- `BodyScanner.scan` and the `embedTargets`/`linkTargets` ranges built on `MarkdownFacts`; the swift-markdown walker is kept as `LegacyBodyScanner` in TaDaCoreTests only.
- `BodyScannerParityTests`: the gate in Decisions. Differences go back to the fork (new `-live.<n>`), into `spec/grammar`, or into `docs/file-format.md`.
- Once it passes: remove swift-markdown from `Package.swift`, `LegacyBodyScanner` and the parity test's legacy half (the vault cases stay as `BodyScanner` golden tests), and `DependencyAssumptionTests`' swift-markdown cases. Remove the hard-break and alternative-checkbox workarounds.
- Check: parity test green before removal; after removal, core, app and `LargeVaultTests` pass with scan time no worse; a re-index of SampleVault leaves `git diff SampleVault` empty.

### M8 — Saga-Swift on the fork (Saga-Swift repo, own session)
- Replace `Packages/TaDaMarkdown` with the fork at the current tag; adapt `LiveEditor` to the newer API (menus, `onRightClickMenu`, slash and link queries as far as Saga wants them).
- SagaCore: M6 and M7 as in TaDaCore.
- Check: Saga-Swift's app and core tests; manual pass over its SampleVault.

## Development workflow after consolidation

### Where things live
| What | Where |
| --- | --- |
| Editor, parser, syntax target, spec | `~/Projects/swift-markdown-engine-extended`, branch `live` |
| Ta Da app, TaDaCore | `~/Projects/Ta Da` (pins a `-live.<n>` tag twice: Xcode project and `TaDaCore/Package.swift`) |
| Saga-Swift app, SagaCore | `~/Projects/Saga-Swift` (pins its own tag) |
| Saga (Tauri) | `~/Projects/Saga`, reads `spec/` as a submodule at a tag |

### An app-only change
Unchanged: work in the app repo, tests there.

### An editor or syntax change
1. Drag `~/Projects/swift-markdown-engine-extended` into `TaDa.xcworkspace`. Xcode uses the local folder instead of the pinned package while it's there. For CLI core tests, `swift package --package-path Packages/TaDaCore edit swift-markdown-engine-extended --path ~/Projects/swift-markdown-engine-extended` (undo with `unedit`).
2. Edit and test both. A grammar change starts as a `spec/` fixture; the fork's tests prove it.
3. In the fork: commit on `live` (or a topic branch merged in), update `FORK.md` if it's a new difference from upstream, tag the next `-live.<n>`, push the branch and tag.
4. In Ta Da: remove the local folder from the workspace, bump both pins to the tag, run app + core tests, commit.

Two commits per change; the second is where an app chooses to take the new editor. Saga-Swift bumps whenever it's ready.

### Taking upstream
About once per upstream release.
1. `git fetch upstream --tags`; `git switch main && git merge --ff-only upstream/main && git push` (or GitHub's **Sync fork** on `main`).
2. `git switch live && git merge <version>`. `rerere` replays earlier resolutions; apply `FORK.md`'s conflict rules to the rest.
3. `swift test --no-parallel` on macOS and the iOS Simulator run.
4. Tag `<version>-live.1`, push, bump the apps when ready.

For a single upstream fix between releases: `git cherry-pick -x <sha>` on `live`.

### Contributing upstream
1. `git switch -c fix/<name> main` (never from `live`, which carries the fork's changes).
2. Make the change against upstream's code, with its tests; follow upstream's `CONTRIBUTING.md`.
3. Push the branch to the fork and open a PR against `nodes-app/swift-markdown-engine:main`.
4. When it ships in a release, the next merge brings it into `live`; remove the matching `FORK.md` entry if it replaced a fork change.

### Tests
- Fork: parser, syntax, spec conformance and editor tests, macOS and iOS Simulator.
- Ta Da: app and TaDaCore tests, including the `BodyScanner` golden tests, design renders and UI tests.
- Saga (Tauri): its own runner over the `spec/` submodule (its parity plan).

### Claude sessions
Editor and syntax work runs in a session in the fork's folder, with its `CLAUDE.md` (commands, conventions, `FORK.md` rules, this workflow). Ta Da sessions treat the editor as a dependency; when a Ta Da task needs an editor change, it's done in the fork first and the pin bumped after.

## Follow-up Activities
- **Upstream PR: one completion seam.** Open a draft PR against `nodes-app/swift-markdown-engine:main` (upstream asks for a draft with the design for an architectural change) proposing a general trigger seam: the engine detects a trigger, reports a context and routes keys, and the embedder commits through a request; directive names, the `[[…]]` preview and app triggers (slash, link, embed, tag) become sources of the same seam, with candidates from the engine or the embedder. If upstream takes it, the fork moves #10, #20 and #24 onto it and drops its own query reports.
