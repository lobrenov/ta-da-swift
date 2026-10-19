# Ta Da

Native SwiftUI task manager over a folder of markdown files (one file per task/project, YAML frontmatter). macOS app, and an iPhone app (POC) on the same code; iPad later.

- Repo: https://github.com/lobrenov/ta-da-app (private; `origin`)
- Brief: `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Personal/Projects/Ta Da - a to-do list app.md`
- Design system: `docs/design/design-framework.md`. Follow it for UI work; its In the app table names the Swift view for each component, and its As built section lists where the app differs from the guidance. Component guidelines are in `docs/design/components/`, values in `docs/design/tokens.json`. Colour changes go in both `tokens.json` and `TaDa/Theme/BundledThemes.swift`.
- Design canvas: https://claude.ai/artifact/A7c33hg9HUKz41u3wbki3V. Its reference pages show the app as built: macOS and iOS (each view), Menus (menus and components), Editors (markdown as the editor draws it), App (icon, themes). A feature is mocked up on a new page, built, then its boards are updated into the reference pages and the feature page is deleted. Docs name designs, not canvas pages or boards.
- Architecture (layers, files, runtime, window, editors, shortcuts): `docs/architecture.md`. Schema: `docs/file-format.md` (the source of truth; update it with any format change).
- Backlog: `docs/backlog.md`. Finished build plans are in `docs/archive/build plans/`, listed in its `completed plans.md`. To complete or archive a plan, move it there and add its line to `completed plans.md`.

## Commands
- Core tests: `swift test --package-path Packages/TaDaCore`. On iOS, from `Packages/TaDaCore`: `xcodebuild -scheme TaDaCore -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test`.
- Editor tests run in the fork (`~/Projects/swift-markdown-engine-extended`); its `CLAUDE.md` has the commands.
- App build: `xcodebuild -workspace TaDa.xcworkspace -scheme TaDa -destination 'platform=macOS' build`. For iOS: `-destination 'generic/platform=iOS Simulator'`.
- iPhone: `xcodebuild -workspace TaDa.xcworkspace -scheme TaDa -destination 'id=<UDID>' -allowProvisioningUpdates build`, then `xcrun devicectl device install app --device <UDID> <DerivedData>/Build/Products/Debug-iphoneos/TaDa.app` (`xcrun devicectl list devices` gives the UDID). The phone needs Developer Mode, must be unlocked, and must trust the developer once (Settings ▸ General ▸ VPN & Device Management). Builds signed by the Personal Team expire after 7 days.
- App + core tests: `xcodebuild -workspace TaDa.xcworkspace -scheme TaDa -destination 'platform=macOS' test`. This runs `TaDa.xctestplan`: TaDaTests, TaDaCoreTests and TaDaUITests. Always ask for user permission before running UI tests that take control of the screen/mouse/keyboard. The UI tests need the Accessibility permission for Xcode's test runner and fail if Ta Da is already running (stop it in Xcode first). They launch with `-uiTesting`, which uses throwaway settings and a small folder in the app's container (`TaDa/UITestingLaunch.swift`). Skip them with `-skip-testing:TaDaUITests`.
- 1,000-file test folder (to open in the app): `TADA_GENERATE_VAULT=<dir> swift test --package-path Packages/TaDaCore --filter writeGeneratedVault`. `LargeVaultTests` and `LargeVaultUITimingTests` print the scale timings.
- Design renders (PNG per theme/domain on the DesignVault fixture, to compare with the canvas): `TEST_RUNNER_TADA_RENDER_DIR=<dir> xcodebuild -workspace TaDa.xcworkspace -scheme TaDa -destination 'platform=macOS' test -only-testing:TaDaTests/DesignRenderTests ENABLE_APP_SANDBOX=NO`. Check glass and the title bar in the running app.
- Beta .dmg: `scripts/make-beta-dmg.sh` (writes `build/TaDa-<version>-<build>.dmg`; bump Build first). Sharing and tester steps: `docs/beta-builds.md`.
- Always open `TaDa.xcworkspace`, not the `.xcodeproj`.

## Layout
- `Packages/TaDaCore/`: all non-UI logic (model, parsing, surgical writes, index, queries, storage). Foundation + swift-markdown + Yams only, never SwiftUI/AppKit.
- `TaDa/`: SwiftUI app target. Folders are synchronised, so new files join the target automatically.
- `SampleVault/`: dev vault, started from the design's data and edited freely in manual testing; commit its changes with the work. Point the app at it. `git diff SampleVault` audits what the app wrote since the last commit.
- `Packages/TaDaCore/Tests/TaDaCoreTests/Fixtures/DesignVault/`: the design's data, frozen. The design-count, golden and render tests read it; don't edit it to match a test.
- The Live editor is the package `swift-markdown-engine-extended` (product `MarkdownEngine`), pinned in the project to an exact `-live.<n>` tag. It's a fork of swift-markdown-engine under Apache-2.0: https://github.com/lobrenov/swift-markdown-engine-extended, cloned at `~/Projects/swift-markdown-engine-extended`; its `FORK.md` lists the changes from upstream. For an editor change, drag that folder into `TaDa.xcworkspace` (Xcode uses it instead of the pin), make, test and tag the change in the fork, then remove the folder and bump the pin here. Don't commit `TaDa.xcworkspace/contents.xcworkspacedata` or `TaDa.xcworkspace/xcshareddata/swiftpm/Package.resolved` while the folder is in it.

## Conventions
- Swift 6 language mode. The app target defaults to MainActor isolation; TaDaCore is nonisolated and does file IO off the main actor.
- Never re-serialise YAML or markdown. Edit files by splicing lines (see Writing rules in `docs/file-format.md`).
- `dueDate`/`deadline`/`createdDate`/`completedDate` are `LocalDate` (from `YYYY-MM-DD` strings), never `Date`. Queries take an injected `today`.
- Dependencies are pinned with `exact:`. `MarkdownEngine` is imported only in `TaDa/Editor/LiveEditor.swift`. Adding or bumping a linked package updates its section of `TaDa/Acknowledgements.txt` from the package's own licence and notice files.
- Use `#Preview` only (`PreviewProvider` is deprecated in Xcode 27). Xcode 27 makes `@State` a macro: don't assign an `@State` property in `init` if it has an initial value.
- Tests use Swift Testing (`@Test`, `#expect`). XCTest is only for UI tests.
