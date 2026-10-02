# Ta Da — MVP plan

## Context
Greenfield native SwiftUI app: one markdown file per task/project, YAML frontmatter as structured data, files raw in a user-chosen folder (iCloud Drive or inside the Obsidian vault). Mac MVP first, iOS/iPad later on the same codebase. Design source: Claude Design canvas "Ta Da" (7 artboards: Today, Project, Upcoming, Editor·source, Themes, Project·browser+editor, Agenda·browser+editor). `~/Projects/Ta Da` holds only an empty `libs/` and isn't a git repo. Toolchain: Xcode 27.0, Swift 6.4, macOS 27.2, iOS 27 SDK installed. Your vault has no existing task/project frontmatter and no clashing Obsidian property types → greenfield schema.

## Decisions taken (from Q&A)
- **Storage**: user-picked folder, security-scoped bookmark. Needs only App Sandbox + user-selected read/write — free Personal Team is fine (an app-owned iCloud container would need the paid Developer Program).
- **Title = filename** (`projects/Ta Da MVP.md`); `project: "[[Ta Da MVP]]"` resolves in Obsidian too.
- **Today** = dueDate or deadline ≤ today and not Done (overdue rolls in, flagged).
- **repeat** = parsed + displayed only.

## Brief review — challenges & resolved assumptions
1. **"Different renderers for Mac, iOS, iPad"** → one SwiftUI view layer that adapts. Platform code only where it must differ: text editors, folder picker, change watching, menus. Three renderers = 3× UI maintenance.
2. **"iCloud powered synchronisation"** → the app implements *no* sync. iCloud Drive syncs the folder; the app does coordinated reads/writes, watches for external changes, handles conflict versions (and iCloud's occasional `Name 2.md` duplicates just show as separate items). No CloudKit, no database — files are the only truth; the index is rebuilt in memory at launch.
3. **Libraries** → of the four listed, keep two: **swift-markdown 0.9.0** (parse) + **swift-markdown-engine 0.13.0** (Mac editor), plus **Yams 6.2.2** (read YAML). Drop **Textual** (display-only, no task lists, open crash bugs) and **SwiftStreamingMarkdown** (display-only for streaming chat; hard-pins swift-markdown 0.7.3, which would *break the build* beside 0.9.0).
4. **The Mac editor is Mac-only** → swift-markdown-engine is AppKit/TextKit 2; its maintainer says iOS would be a separate repo. The iOS editor is an open decision for that phase.
5. **Folder vs `type`** → the mock has `tasks/`/`projects/` folders *and* `type:`. `type` is the sole truth; folders are only where *new* files go. Scan recursively; ignore files without `type: task|project`, so Ta Da can share your vault.
6. **Project membership** → only frontmatter `project: "[[Name]]"`. Body `[[links]]` are just links (the Editor artboard already shows a file linking `[[Ta Da MVP]]` yet listed as loose). One project per task.
7. **"Backlink rendered in a structured UX"** → a query over the index, never written into the project file (generated lists in markdown = sync conflicts + Obsidian noise).
8. **Status vs completedDate vs checkbox** → `status` is the truth. Completing sets `status: Done` + `completedDate: today`; reopening sets `Not Started`, clears `completedDate`. Ticking all subtasks doesn't auto-complete.
9. **Dates** → date-only `YYYY-MM-DD`, read as strings into `LocalDate` — never YAML timestamp → `Date` (UTC off-by-one; Yams is YAML 1.1, so it also turns `yes/no/on/off` into Bools). No times/reminders in MVP.
10. **Writes must be surgical** → neither Yams nor swift-markdown round-trips losslessly (comments, order, formatting lost), so the app never re-serialises: property changes splice only the affected frontmatter line(s); checkbox toggles splice `[ ]`↔`[x]`. Golden-file tests enforce byte-for-byte preservation.
11. **Theme "iTerm CSS keys"** → no CSS natively: the 15 tokens become a Swift `Theme` in the environment; 5 schemes hard-coded from the Themes artboard; light themes switch `NSApp.appearance` to `.aqua` so system controls match. `.itermcolors` import is post-MVP.
12. **Fully themed chrome vs Liquid Glass** → Liquid Glass can't be disabled with the 27 SDK and Apple discourages custom sidebar backgrounds; there is no supported "replace the sidebar material" API on macOS. macOS 27's edge-to-edge sidebar takes a solid fill better than 26's floating one — hence macOS 27 minimum, and the themed sidebar is proven in the M1 spike (fallback: glass sidebar with themed content).
13. **YAML** → `@computer` must be quoted; parser accepts flow and block lists; writer always quotes.
14. **Filename = title** → sanitise `/ : \ * ? " < > |` plus Obsidian link-breakers `[ ] # ^ |`; collisions get ` 2`. Renaming a project rewrites `project:` in its linked tasks.
15. **In the design, not the brief's MVP list** → search, context chips, month calendar, file inspector, New task/project/linked task: included (cheap on an in-memory index). Sync line = folder + watch state only. Fonts: SF Pro + **SF Mono** (the design's fallback); bundling JetBrains Mono is a 10-minute add.

## File format (`docs/file-format.md`)
```markdown
---
type: task                 # task | project            (required — files without it are ignored)
status: Not Started        # Not Started | Doing | Done | Blocked (case-insensitive read, canonical write)
area: Personal             # optional
contexts:                  # optional list; Today shows them as filter chips
  - "@computer"
project: "[[Ta Da MVP]]"   # tasks only — the ONLY membership signal
createdDate: 2026-09-28
completedDate:             # set/cleared by completing/reopening
dueDate: 2026-10-02
deadline: 2026-10-06
repeat: weekly             # display-only in MVP
---
Description markdown (first paragraph = summary).

- [x] Every GFM checklist item in the body is a subtask (done/total)
- [ ] …
```
Title = filename without `.md`. Projects: same keys minus `project`. Unknown keys preserved. Checkboxes follow the Alternative Checkboxes Reference Set; which states count as subtasks is in `docs/file-format.md` (changed in M1).

## Editor design (the riskiest part)
- **Live mode** (right pane of Today / Project / Agenda artboards): `NativeTextViewWrapper(text: $body, configuration:, header: { title + PropertyTable })`. The engine gets **only the body**; frontmatter is rendered natively by `PropertyTable` and spliced back on save — sidestepping the engine's lack of frontmatter support. Its `header:` slot scrolls title/properties with the document, as designed. Wikilinks via a `WikiLinkResolver` backed by the index; `onLinkClick` navigates. Engine checkbox clicks edit text in place → reparse updates subtask counts.
- **As built (M7)**: the editor runs in `.fitsContent` inside a SwiftUI `ScrollView`, with title and properties above it and the footer (plus a project's linked-tasks table) below, so the `header:` slot is unused. `OpenDocument` holds the whole file; the editor's binding reads and writes only the body and splices it back after the frontmatter block. Edits save 0.6 s after the last change, before switching files, on deactivation and on quit.
- **Source mode** (Editor artboard): our own `SourceTextView` — `NSTextView` (TextKit 1) + line-number ruler + highlighting from the artboard's role table (key=accent, value=fg, string=done, date=due, heading=strong, punct/check=muted, checkDone=done, link=link). Whole file incl. frontmatter. Built ourselves because the engine's raw mode has no colouring/line numbers and drops undo on switch; it also doubles as the fallback editor and ports to `UITextView`. File inspector = SwiftUI `.inspector` panel.
- **As built (M8)**: Source mode takes the whole workspace (as on the Editor artboard) with the file inspector as a fixed 300pt panel rather than SwiftUI's `.inspector`; it ends when the selection clears, so picking another domain brings the lists back. Highlighting reruns over the whole file after each edit.
- **Engine risk** (pre-1.0, ~one maintainer, API may change): pin `exact: "0.13.0"`, import it in one file, fork into `libs/` if a patch is needed. Known quirks: `[[Target|Alias]]` displays backwards vs Obsidian (file text untouched); no selection/focus binding (external edits just reset text); no checkbox veto.
- **M1 outcome: go-with-fork.** `libs/swift-markdown-engine` is 0.13.0 plus alternative checkboxes, depth bullets, Tab/Shift-Tab rules, alias resolution by target, and theme-driven link/selection colours with in-place theme switching (`libs/swift-markdown-engine/FORK.md`). Aliased links still display the target name rather than the alias.
- **iOS later**: SwiftUI `TextEditor` + `AttributedString` (built-in, can't hide syntax), CodeMirror 6 in a web view (Obsidian's own approach; one bundle for all platforms), or STTextView (GPL-3.0/commercial).

## Xcode setup (I'll walk you through this live in M0, pausing after each step)
1. **New project** — File ▸ New ▸ Project ▸ **Choose Template…** (not the quick "App" item: it skips the options sheet, creates no test targets and a placeholder bundle ID) ▸ *Multiplatform* ▸ **App** ▸ Next.
   - Product Name `TaDa` (no space — it becomes the module/bundle name; "Ta Da" is set as Display Name in step 3)
   - Team: your Personal Team (the `obrenov.leon@icloud.com` Apple Development identity is already in your keychain)
   - Organization Identifier e.g. `com.leonobrenov` → `com.leonobrenov.TaDa`
   - Testing System **Swift Testing with XCTest UI Tests** · Storage **None**
   - Save in `~/Projects/Ta Da/`, **untick** "Create Git repository" (I'll init at the root).
2. **Flatten** (me, Xcode closed): move `Ta Da/TaDa/*` up one level so `TaDa.xcodeproj` is at the repo root; `git init`, `.gitignore`, first commit.
3. **Target ▸ General**: Supported Destinations → **Mac** only (re-add iPhone/iPad in the iOS phase); Minimum Deployment **macOS 27.0** (drop to 26.0 only if another Mac of yours runs Tahoe); Display Name **Ta Da**; App Category Productivity.
4. **Target ▸ Signing & Capabilities ▸ App Sandbox**: User Selected File → **Read/Write** (default is Read Only). Xcode 27 stores sandbox settings as build settings — no `.entitlements` file, no Info.plist file; nothing else to add.
5. **Target ▸ Build Settings**: Swift Language Version → **Swift 6** (default 5). Keep Default Actor Isolation = MainActor, Approachable Concurrency = Yes.
6. **Local package** (after I scaffold `Packages/TaDaCore`): File ▸ Add Package Dependencies… ▸ **Add Local…** (bottom-left) ▸ `Packages/TaDaCore` ▸ add `TaDaCore` to target TaDa. *(As built: Xcode 27 hides a dependency package's tests from app test plans, so the repo has `TaDa.xcworkspace` (project + TaDaCore as members) and `TaDa.xctestplan` (TaDaTests + TaDaCoreTests; TaDaUITests disabled until M10). Open the workspace.)*
7. **Editor engine**: File ▸ Add Package Dependencies… ▸ `https://github.com/nodes-app/swift-markdown-engine` ▸ Dependency Rule **Exact Version 0.13.0** ▸ product `MarkdownEngine` → TaDa. (swift-markdown and Yams are pinned in `Packages/TaDaCore/Package.swift`.) Commit `Package.resolved`.
8. **Verify**: ⌘R opens a window; ⌘U green. Headless (what I'll use): `xcodebuild -workspace TaDa.xcworkspace -scheme TaDa -destination 'platform=macOS' build` and `swift test --package-path Packages/TaDaCore`.
- Note: Xcode 27.2 (in beta) introduces the JSON `.xcproj` format; stay on `.pbxproj` for now — conversion is optional later.

## Technical structure
Two layers: **TaDaCore** (local package — pure logic: Foundation + swift-markdown + Yams, no UI, macOS + iOS; also keeps swift-markdown's `Text`/`Link` names away from SwiftUI) and the **TaDa app target** (SwiftUI; one multiplatform target, Mac destination only for MVP).

```
Ta Da/                                  repo root (git)
├── TaDa.xcodeproj                      synchronised folders → new files auto-join the target
├── TaDa/                               APP TARGET — UI layer
│   ├── TaDaApp.swift                   @main; WindowGroup + Settings scene; injects AppModel + Theme; sets NSApp.appearance per theme
│   ├── AppModel.swift                  @Observable root: vault, index, domain, selection, open doc, theme id
│   ├── OpenDocument.swift              selected file's text (frontmatter + body); applies edits; debounced coordinated autosave
│   ├── Commands.swift                  ⌘N task, ⇧⌘N project, ⌘E Live/Source, ⌘1–3 domains, Theme menu
│   ├── Theme/
│   │   ├── Theme.swift                 15 tokens (bg side surface border code fg strong muted accent due deadline done doing blocked link) + isDark; Environment key
│   │   └── BundledThemes.swift         Tomorrow Night, Solarized Light, Dracula, Nord, Gruvbox Light
│   ├── Onboarding/FolderPickerView.swift   first run: fileImporter/NSOpenPanel → bookmark
│   ├── Sidebar/SidebarView.swift       search; Today / Upcoming / Loose (+counts); Projects (progress ring + open count); sync line; New task / New project
│   ├── Browser/                        middle column
│   │   ├── TaskListView.swift          Today + Loose: loose group first, then per-project groups; context chips
│   │   ├── TaskRow.swift               status checkbox (done/doing/blocked glyphs) + title + chips (status, n/m, repeat, deadline/overdue, context)
│   │   ├── AgendaView.swift            Upcoming from tomorrow: next 7 days (empty days shown) + later by month; separate due and deadline entries
│   │   ├── MonthCalendarView.swift     month grid with due/deadline dots + "Later in <month>"
│   │   └── ProjectBrowserView.swift    project header + Open/Completed groups + New linked task
│   ├── Document/                       right column
│   │   ├── DocumentPane.swift          breadcrumb (Ta Da / folder / file.md) + Live/Source toggle
│   │   ├── LiveDocumentView.swift      engine + header (title w/ rename, PropertyTable) + footer (created/modified/backlinks)
│   │   ├── PropertyTable.swift         status menu + date pickers editable; other keys read-only in MVP
│   │   ├── ProjectDocumentView.swift   project file: 2-col properties, description, linked-tasks table
│   │   └── FileInspector.swift         `.inspector` in Source mode: path, size, modified, Reveal in Finder, Parsed as, Appears in, warnings
│   ├── Editor/
│   │   ├── LiveEditor.swift            the ONLY file importing MarkdownEngine: wrapper, tokens → MarkdownEditorTheme, WikiLinkResolver
│   │   └── SourceTextView.swift        NSTextView + line numbers + role-based highlighting
│   └── Assets.xcassets
├── TaDaTests/                          Swift Testing — AppModel / OpenDocument logic
├── TaDaUITests/                        template bundle; one launch smoke test later
├── Packages/TaDaCore/
│   ├── Package.swift                   swift-markdown exact 0.9.0, Yams exact 6.2.2
│   ├── Sources/TaDaCore/
│   │   ├── Model/    Item (kind, title, status, properties, subtasks, links, warnings) · Status · LocalDate · WikiLink
│   │   ├── Parsing/  FrontmatterSplitter (--- block ↔ body; offsets) · PropertyReader (Yams `compose` node tree → typed, no coercion) · BodyScanner (swift-markdown, `.disableSmartOpts`, frontmatter blanked so line numbers match; checklist items + lines; own `[[…]]` scanner skipping code)
│   │   ├── Writing/  FrontmatterEditor (set/remove one key) · ChecklistEditor (toggle line N) · Completion (Done ↔ completedDate) · NewFile (templates) · FileNaming (sanitise, collisions)
│   │   ├── Index/    VaultIndex (items by path, title→item resolution, backlinks) · Queries (today/overdue, upcoming entries, loose, projects+progress, search — injected `today`)
│   │   └── Storage/  Vault (bookmark create/resolve/refresh-if-stale, recursive scan skipping hidden/.obsidian/.trash) · CoordinatedFileIO (synchronous NSFileCoordinator read — downloads evicted iCloud files — + atomic write) · VaultWatcher (FSEvents on macOS; iOS later: presenter + rescan on foreground) · Conflicts (NSFileVersion)
│   └── Tests/TaDaCoreTests/   one test file per source file + Fixtures/ (small edge-case .md files)
├── SampleVault/                        the design's tasks & projects as real files; point the app here while developing. Git-tracked, so `git diff SampleVault` shows exactly what the app wrote
├── docs/file-format.md
├── libs/                               (existing, empty) vendored/forked packages if ever needed
└── CLAUDE.md                           build/test commands + conventions (Swift 6, `#Preview` only, Xcode 27 `@State`-macro init rule, MarkdownEngine imported only in LiveEditor.swift)
```

**Runtime flow**: launch → resolve bookmark → scan + parse off the main actor → `VaultIndex` → views are pure functions of `Queries`. Open file → `OpenDocument` owns the text; typing, property edits, checkboxes mutate it → reparse → index patch → debounced coordinated save (flushed on selection change / quit). Row checkbox on an unopened file → coordinated read → surgical edit → atomic write. FSEvents change → re-read that file → index patch; open doc reloads if clean, keeps yours and warns if dirty.

**As built (M9)**: the watcher doesn't say what changed. Every FSEvents callback (and every app activation, the sandbox fallback) compares the folder's modification dates with the last scan and reparses only changed files. Saves are guarded: Ta Da writes only if the file still holds the text it last read or wrote, so an outside change is never overwritten. With unsaved edits the document shows a banner (keep mine / use the file on disk; save again / discard after a deletion; keep this / use the other iCloud version). Leaving the file or quitting with that choice still open writes the edits to `<title> (unsaved edits).md` beside it.

**Layout**: `NavigationSplitView { Sidebar } detail: { Workspace }` — two columns, because the Project artboard (sidebar + full-width document) can't be expressed by a 3-column split. Workspace = `browser | DocumentPane` for Today / Loose / Agenda / Project-tasks; full-width `ProjectDocumentView` for a project file; agenda + `MonthCalendarView` when Upcoming has no selection. (On iPhone later, Workspace becomes a NavigationStack: list → document.)

**Testing**: Swift Testing (`@Test`, `#expect`) for TaDaCore (parsing, golden-file surgical writes, queries with fixed dates, temp-dir vault scans) and app logic; XCTest only for the UI smoke test.

## Build plan — first-pass MVP
Each milestone is small, ends green, and is verified before the next. Riskiest first.

| # | Milestone | Scope | Verify |
|---|---|---|---|
| M0 | Setup | Xcode steps 1–8; I add `.gitignore`, `CLAUDE.md`, `docs/file-format.md`, TaDaCore skeleton, `SampleVault/` (~20 files recreating the design's tasks + 5 projects) | ⌘R window, ⌘U green, both headless commands pass |
| M1 | **Spikes** (½-day timebox, throwaway branch) | *Editor*: marker hide/reveal; checkbox click round-trips via the binding; `header:` hosts SwiftUI; can SwiftUI sit *below* the editor (`heightBehavior`) for the linked-tasks table; tokens → `MarkdownEditorTheme` in 5 themes; open→save byte fidelity incl. `[[x\|alias]]`; resolver + link clicks; 2k-line perf. *Chrome*: themed sidebar (`scrollContentBackground(.hidden)` + `.background(theme.side)`), window/toolbar background, `NSApp.appearance` switching | Go / go-with-fork (`libs/`) / fallback (SourceTextView editing + read-only Live; glass sidebar) |
| M2 | Core read path | LocalDate, Status, Item, WikiLink, FrontmatterSplitter, PropertyReader, BodyScanner | `swift test`: every property, missing/malformed YAML, CRLF, unicode, `@contexts` flow+block, `[[x\|y]]`/`[[x#h]]`, checklists in code blocks ignored, nested lists |
| M3 | Core write path | FrontmatterEditor, ChecklistEditor, Completion, NewFile, FileNaming | Golden tests: diff is exactly the targeted line(s); add missing key; create frontmatter; CRLF kept |
| M4 | Vault, index, queries | Vault (bookmark), CoordinatedFileIO, VaultIndex, Queries, project-rename relink | Temp-dir scans; queries with injected dates: overdue, due+deadline same day, done today, unresolved project → loose + warning |
| M5 | App shell + theme | AppModel, folder onboarding, split view + Sidebar (counts, rings), Theme + 5 schemes + menu/Settings + appearance, empty states | Run on SampleVault; cycle all 5 themes; compare with artboards |
| M6 | Browser views | TaskListView (Today/Loose, chips, overdue), TaskRow checkbox → write, AgendaView, MonthCalendarView, ProjectBrowserView | Complete/reopen in every view → `git diff SampleVault` shows only `status`/`completedDate` |
| M7 | Live document | DocumentPane, LiveDocumentView (engine + header), PropertyTable editing, rename (+ project relink), footer, ProjectDocumentView + linked-tasks table + New linked task | Edit body + properties, relaunch → persisted; diff = intended changes only; links navigate |
| M8 | Source mode | SourceTextView (highlighting, line numbers), ⌘E toggle, FileInspector | Edit frontmatter in Source → Live reflects it; broken YAML → warning, not crash |
| M9 | Outside world | VaultWatcher (FSEvents), clean/dirty reload, conflict versions, sync line, search, ⌘N / ⇧⌘N | Edit a file in TextEdit and Obsidian while running → updates in ~2 s; dirty buffer warns and keeps your text. Fallback if FSEvents misbehaves under the sandbox: rescan on app activation |
| M10 | Hardening | Shortcuts, accessibility labels, 1,000-file generated vault, then a copy of a real folder, then the real one | MVP acceptance ↓ |

**MVP acceptance**: all 7 artboards reproducible on SampleVault; theme switch applies everywhere incl. both editors; completing / property edits / subtask toggles never touch bytes outside the targeted lines; external edits appear without restart and nothing is lost when both sides edit; `swift test`, ⌘U and `xcodebuild` green.

**Post-MVP backlog**: recurrence, `.itermcolors` import, per-file iCloud sync state, JetBrains Mono, editing UI for area/contexts/project, iOS/iPad (editor choice), upstream fix for alias display.

## Verification (every milestone)
- `swift test --package-path Packages/TaDaCore` and `xcodebuild -workspace TaDa.xcworkspace -scheme TaDa -destination 'platform=macOS' test` — run headless after each change.
- Manual run against `SampleVault/`; `git diff SampleVault` is the write-safety check, `git checkout SampleVault` resets it.
- Screenshot comparison with the canvas artboards for M5–M8.
