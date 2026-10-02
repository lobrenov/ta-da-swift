# Ta Da

Native SwiftUI task manager over a folder of markdown files (one file per task/project, YAML frontmatter). macOS MVP; iOS/iPad later on the same code.

- Brief: `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Personal/Projects/Ta Da - a to-do list app.md`
- Design: Claude Design canvas https://claude.ai/artifact/A7c33hg9HUKz41u3wbki3V (artboards: Today, Project, Upcoming, Editor·source, Themes, Project·browser+editor, Agenda·browser+editor)
- Plan and milestones: `docs/mvp-plan.md`. Schema: `docs/file-format.md` (the source of truth; update it with any format change).

## Commands
- Core tests: `swift test --package-path Packages/TaDaCore`
- Editor engine tests: `swift test --package-path libs/swift-markdown-engine` (one known upstream failure, see `libs/swift-markdown-engine/FORK.md`)
- App build: `xcodebuild -workspace TaDa.xcworkspace -scheme TaDa -destination 'platform=macOS' build`
- App + core tests: `xcodebuild -workspace TaDa.xcworkspace -scheme TaDa -destination 'platform=macOS' test`. This runs `TaDa.xctestplan`, which covers TaDaTests and TaDaCoreTests; TaDaUITests is disabled until M10 because it needs the Accessibility permission.
- Always open `TaDa.xcworkspace`, not the `.xcodeproj`. Xcode 27 only shows a local package's tests in app test plans when the package is a workspace member.

## Layout
- `Packages/TaDaCore/`: all non-UI logic (model, parsing, surgical writes, index, queries, storage). Foundation + swift-markdown + Yams only, never SwiftUI/AppKit.
- `TaDa/`: SwiftUI app target. Folders are synchronised, so new files join the target automatically.
- `SampleVault/`: dev vault recreating the design's data. Point the app at it. `git diff SampleVault` audits what the app wrote; `git checkout SampleVault` resets it.
- `libs/swift-markdown-engine/`: the forked editor engine (see `FORK.md` there).

## Conventions
- Swift 6 language mode. The app target defaults to MainActor isolation; TaDaCore is nonisolated and does file IO off the main actor.
- Never re-serialise YAML or markdown. Edit files by splicing lines (see Writing rules in `docs/file-format.md`).
- `dueDate`/`deadline`/`createdDate`/`completedDate` are `LocalDate` (from `YYYY-MM-DD` strings), never `Date`. Queries take an injected `today`.
- Dependencies are pinned with `exact:`. `MarkdownEngine` is our fork of swift-markdown-engine 0.13.0 in `libs/swift-markdown-engine` (changes listed in its `FORK.md`). It is imported only in `TaDa/Editor/LiveEditor.swift`.
- Use `#Preview` only (`PreviewProvider` is deprecated in Xcode 27). Xcode 27 makes `@State` a macro: don't assign an `@State` property in `init` if it has an initial value.
- Tests use Swift Testing (`@Test`, `#expect`). XCTest is only for UI tests.
