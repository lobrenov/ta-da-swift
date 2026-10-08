# Ta Da — iOS POC plan

## Context
Ta Da is macOS-only. The POC brings it to iPhone on the same code, working towards one build workflow for new features on both platforms. Design source: the Claude Design canvas's **iOS POC** and **iPad POC** pages (https://claude.ai/artifact/A7c33hg9HUKz41u3wbki3V). Once the iOS design settles, the canvas is reorganised so each Mac artboard has its iOS one beside it.

Starting point, as checked on 2026-10-08:
- `TaDaCore` builds for the iOS Simulator unchanged. `VaultWatcher`'s FSEvents is macOS-only; elsewhere it falls back to rescanning when the app becomes active.
- `libs/swift-markdown-engine` declares `platforms: [.macOS(.v14)]`; 71 of its 91 source files import AppKit. Its TextKit 2 layout and rendering (`NSTextLayoutManager`, `NSTextLayoutFragment`) exist on iOS too; the `NSTextView` subclass, input handling and menus don't.
- The `TaDa` target is `SUPPORTED_PLATFORMS = macosx`; 21 of its 49 Swift files use AppKit (`Theme`'s `NSColor`s, `PopupMenu` panels, `FileMenu`, `SourceTextView`, `InlineTitleField`, `ArrowKeySelection`, the pickers).
- `Vault` bookmarks use `.withSecurityScope`, a macOS bookmark option.

## Decisions
- **Scope**: iPhone first. iPad is designed and comes largely from the same views; building it is optional for the POC. No notifications, widgets, Shortcuts or share extension.
- **Minimum iOS 26** (Liquid Glass tab bar, sheets and toolbars). Swift 6, one multiplatform `TaDa` target.
- **Navigation**: one `TabView` with five tabs: Today, Upcoming, Loose, Projects, Other (Settings and Trash). `.sidebarAdaptable` gives bottom tabs on iPhone, a sidebar on iPad in landscape and tabs on top in portrait. Each tab is a `NavigationStack` on iPhone; iPad columns sit in a `NavigationSplitView`.
- **Search**: pull down on a list to reveal its search field (`.searchable`); it searches that list first, Everywhere widens it. On iPad the field sits at the top of the sidebar.
- **New task**: a floating + at each list's bottom right, with haptic feedback.
- **Rows**: tap pushes the file; swipe from the left edge returns. Swipe right to pick rows (Things style); the tab bar becomes an action bar (Complete, Schedule, Move, More, Delete; More holds Status, Set Deadline… and Share). Press and hold for the row menu.
- **Files**: no tab bar on task and project files; a bottom glass toolbar holds Complete, Schedule, Set Deadline, Move, Share and Trash. Live/Source sits in the navigation bar.
- **Menus**: press and hold replaces right-click (row, checkbox and callout menus); pickers are sheets with detents.
- **Haptics** (`.sensoryFeedback`): task complete `.success`; subtask toggled `.impact(weight: .light)`; + pressed and swipe thresholds `.impact(weight: .medium)`; each row picked, status, date or project picked `.selection`; Move to Trash `.impact(weight: .rigid)`; Empty Trash confirmed `.warning`. A Settings switch turns them off.
- **Folder**: any iCloud Drive folder, picked with `.fileImporter` for folders. No iCloud entitlement is needed, so the free Personal Team works; device builds expire after 7 days.
- **Editor**: the POC ships the live editor. The engine becomes our own package, **TaDaMarkdown**, under Apache-2.0. The licence of the rest of Ta Da is decided later.
- **Testing**: iOS Simulator (iPhone 18 Pro) first, then your iPhone on the Personal Team.

## TaDaMarkdown licensing
Apache-2.0 allows renaming, modifying and redistributing, provided we:
- keep `LICENSE` (Apache-2.0) in the package;
- add a `NOTICE` crediting nodes-app/swift-markdown-engine 0.13.0 (commit `d1421012`) as the origin;
- keep upstream's copyright and attribution notices in the files that carry them;
- mark files we changed (a header line, as the fork's `Ta Da fork` markers do now);
- don't use the upstream project's name to imply endorsement, which the rename covers.

## Milestones
The milestones run in order in one worktree. Each ends with its check passing.

### M0 — Platforms
- Branch `ios-poc`. Add iOS (iPhone; iPad later) to the `TaDa` target; set `IPHONEOS_DEPLOYMENT_TARGET` to 26.0.
- Check: macOS build and all tests unchanged. The iOS build's errors are the AppKit list for A and B.

### A1 — Repackage the engine as TaDaMarkdown
- Move `libs/swift-markdown-engine` to `Packages/TaDaMarkdown`; rename the package, product and module to `TaDaMarkdown`; update `TaDa/Editor/LiveEditor.swift`'s import and the workspace.
- Licensing as above. `FORK.md` becomes `ORIGIN.md`: where it came from and what we changed; upstream is no longer tracked.
- Resolve the known `MarkdownHTMLRendererTests` failure (fix it or drop the HTML renderer the app doesn't use).
- Check: `swift test --package-path Packages/TaDaMarkdown` passes; the Mac app's editor behaves as before.

### A2 — TaDaMarkdown on iOS
- Platform layer: typealiases for colour, font, image and bezier path; shared theme types.
- Keep the TextKit 2 parser, styler and layout fragments shared; add a `UITextView` (TextKit 2) editor beside the `NSTextView` one, with a SwiftUI wrapper of the same shape.
- Input on iOS: list continuation, Tab/Shift-Tab (hardware keyboard and the formatting bar), auto-pairs, slash commands, checkbox taps.
- Press and hold on a checkbox or callout title raises the existing `TaskMarkerMenuRequest` and `CalloutMenuRequest`.
- Check: the tests run on the iOS Simulator and macOS; an iOS test screen edits a sample file with checkboxes, callouts and bubbles.

### B1 — Shared app layer
- `Theme` on a `PlatformColor` typealias (`NSColor` or `UIColor`), same tokens and `BundledThemes`; `themed(by:)` follows the system appearance on both.
- The Mac's views behind `#if os(macOS)`. Shared: `AppModel`, theme, onboarding, the live editor (without its menus on iOS), checkbox and callout drawing, task-row helpers. The iOS root is the folder picker, then a placeholder Today list.
- `Vault` bookmarks: no security-scope options on iOS. Access survives relaunch (checked in the Simulator with a folder in On My iPhone).
- Change detection on iOS: `VaultWatcher` presents the folder to file coordination; the scene becoming active rescans and saving happens as it leaves. Files iCloud hasn't downloaded (`.Name.md.icloud`) are asked to download.
- Check: macOS build and tests unchanged; TaDaCore tests pass on the iOS Simulator; the iOS app opens a picked folder and lists Today.

### B2 — iPhone app
- `TaDa/iOS/` (see `docs/architecture.md`, iPhone): onboarding, the five tabs, lists with the floating +, pull-down search with scopes, project browser and file, task file with the bottom toolbar, press-and-hold row menus, date and project sheets, Settings (Vault, Themes, Editor autocomplete, Haptics), Trash.
- Shared with the Mac: `BodyEditor`, `TitleField`, `DocumentBanner`, `DocumentFooter`, `ProgressRing`, `WrappingHStack`, `CalendarPickerModel` (with `thisWeekend(after:)`).
- The live editor on iOS: checkbox and callout menus as popovers, and a keyboard formatting bar with slash suggestions. TaDaMarkdown gained `SlashCommandProxy.apply(_:)`, the `keyboardBar` parameter and `.fitsContent` sizing on iOS.
- Checked on the iPhone 18 Pro Simulator against a copy of `SampleVault` in On My iPhone: each screen against its artboard, and the files after each write.

### B3 — Swipe to pick
- `PhonePicking.swift`: a left swipe (in from the right) picks the row on release, alongside scrolling and the back swipe; the canvas shows the pick on the leading side. The action bar (Complete, Schedule, Move, More, Delete) replaces the tab bar until Done; More holds Status, Set Deadline… and Share N Files…. The row menu's Select starts picking too.
- Checked on the Simulator; on device in M1.

### M1 — On device and docs
- Install on your iPhone with the Personal Team. Check folder access after relaunch, edits made on the Mac appearing, and files iCloud hasn't downloaded yet.
- Update `docs/architecture.md` (platform layers), `docs/design/design-framework.md` (iOS in In the app and As built), `CLAUDE.md` (iOS build and test commands, TaDaMarkdown), `docs/backlog.md`.
- Check: build, tests and docs agree; this plan moves to `docs/archive/`.

### Later (outside the POC)
- iPad: verify the iPad POC page in the iPad Simulator.
- Canvas reorganisation: iOS artboards beside their Mac ones on each page.
- iOS UI tests.

## Risks
- **Engine port size**: A2 is the long pole. B2 isn't blocked by it.
- **Swipe to pick**: no system control; gesture conflicts are likely (B3 has a fallback).
- **iCloud on iOS**: files may be placeholders until read; coordinated reads and download progress need handling.
- **Free Personal Team**: device builds expire after 7 days and need reinstalling from Xcode.
