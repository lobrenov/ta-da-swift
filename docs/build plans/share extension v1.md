# Ta Da — Share extension v1

## Context
Share a web page or some text to Ta Da from any app, on iPhone and Mac, and it becomes a task in Loose tasks: the title from what was shared, the link in the body. No text parsing, no project, date or tags.

The extension can't open the folder (on the Mac, the folder's access belongs to the app alone), so it leaves the share in an inbox in the App Group's container and the app writes the task. The App Group needs the paid Apple Developer Program (auto-update v1, Part 3); it's the same group as widgets v1, which comes first.

## Decisions
- **Target**: one share extension, `TaDaShare`, for iOS and macOS, with a synchronised `TaDaShare/` folder, embedded in every app target (including `TaDa GitHub` if tip jar v1 has landed). It links no TaDaCore.
- **Accepts**: one web URL (`NSExtensionActivationSupportsWebURLWithMaxCount` 1) or plain text (`NSExtensionActivationSupportsText`). Images and files aren't offered.
- **Sheet**: "Add to Ta Da", a one-line title field (focused, text selected), the link below it in `link` and truncated in the middle, and Cancel and Add (↵). Add is off while the title is empty. The theme's accent; system sheet chrome.
- **Title**: what the sharing app gives: the item's `attributedContentText` (Safari's page title) for a URL, else the URL's host; for text, the text with its line breaks as spaces. Nothing else is taken from the text.
- **Inbox**: `Inbox/` in the group container, one JSON file per share (`<UUID>.json`: `title`, `url?`, `sharedAt`), so the extension and the app never write the same file. The type and the folder's location are in `ShareInbox.swift`, built by both targets. After writing, the extension posts the Darwin notification `com.lobrenov.TaDa.share`.
- **Intake**: `ShareIntake` in `TaDa/Share/` takes the inbox when the folder is ready, when the app becomes active, and on the notification. For each file, oldest first: `addTask(title, in: nil, due: nil, tags: [], note: url)`, then the file is deleted. A file whose task wasn't written stays for the next intake; with no folder open, the inbox waits.
- **The task**: written by `addTask`, as Siri's Add Task is: Loose tasks, `status: Not Started`, `createdDate` today, the file named from the title with the app's collision rules, the URL on its own line under the frontmatter. It goes through undo like any other new task, without the toast.
- **Version**: 0.46.0 (tag `feature`).
- **Not in v1**: choosing a project or area, a due date, tags; page metadata (LinkPresentation); images and files; opening the task after sharing; Share… from inside Ta Da (its own item on the task note).

## Steps
1. **Target** (me). Add `TaDaShare` to the project (synchronised folder, iOS and macOS, embedded in the app), its Info.plist (activation rule above) and entitlements with the App Group from widgets v1. A placeholder sheet. Check: the app builds for Mac, the iPhone simulator and the iPhone; `codesign -d --entitlements -` shows the group on the appex; Ta Da is in Safari's share sheet on both.
2. **Inbox and intake** (me). `ShareInbox` (entry type, write, read in order, delete) and `ShareIntake`, started beside `SpotlightSync` on Mac and iPhone, with the Darwin notification observer. Check: `TaDaTests/ShareTests.swift`, written first: a URL share writes the title and the link in the body; a text share has no body; a second share of the same title gets the next free name; each entry is written once and deleted; with no folder, entries stay until one opens.
3. **Sheet** (iOS `UIViewController` and macOS `NSViewController`, each hosting one SwiftUI view). Reads the item, fills the title, writes the inbox entry, posts the notification, completes the request. Check: in the iPhone simulator, Safari ▸ Share ▸ Ta Da adds the task when Ta Da next opens (`git diff SampleVault`); on the Mac, from Safari with Ta Da running (the task appears at once) and quit (it appears at launch); sharing selected text from Notes.
   *Delegate: `swift-dev`, with this file and `ShareInbox.swift`. After `ShareInbox` exists in step 2; runs in parallel with the rest of step 2.*
4. **Review**. The diff against this plan's decisions.
   *Delegate: `code-reviewer`, given the diff and this file, not my conclusions.*
5. **Docs and release** (me). `docs/architecture.md` (Targets, Share extension), the design framework's In the app table; 0.46.0 with release notes. Check: `xcodebuild … test -skip-testing:TaDaUITests` passes; the release's Mac app and the iPhone build show Ta Da in the share sheet.

## Risks
- On iPhone the task is written only when Ta Da next opens, so it isn't in the folder (or Obsidian) before then.
- The Darwin notification reaches the Mac app only while it runs; the launch and activation intakes cover the rest.
