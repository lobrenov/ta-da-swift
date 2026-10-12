# Ta Da — Quick Entry plan

## Context
A global hotkey opens a small Quick Entry panel over any app, for making a task, project or area without switching to Ta Da. Design source: the canvas's **Quick Entry** page at https://claude.ai/artifact/A7c33hg9HUKz41u3wbki3V: `QuickEntryDesktop` (the panel over another app), `QuickEntry` (states, menus and the ⌘↵ destinations), `QuickEntryPanel` (the panel component), `SettingsHotkeys` (Settings ▸ Hotkeys) and the rules note. Brief: the vault task `tasks/macOS global hotkey.md`. Mac only.

Starting point, as checked on 2026-10-12:
- `TaDaApp` has one `Window` and `Settings`; `AppDelegate` owns the `AppModel`. Closing the window quits the app.
- `SettingsView.Page` is `vault`, `themes`, `editor`. `SettingsStore` wraps UserDefaults, or a test's in-memory store.
- `AppModel.create(_:in:title:taken:)` (private) writes a file through `Vault.create`, which numbers a taken name (" 2"), and adds it to the index. `newTask()`, `newProject()` and `newArea()` build the text with `NewFile` and set extra keys with `FrontmatterEditor.set`.
- `NewFile.task(project:area:tags:today:)` takes tags; `NewFile.project` and `NewFile.area` don't.
- `PropertyPicker` opens the status, project, area and tag menus and the calendar under a chip, for a file's `path`, and writes each pick through `AppModel`. Its menus are built from an `Item` (`StatusChoice`, `ProjectChoice.menu`, `AreaChoice.menu`, `TagChoice.menu`). `PopupPanel` is a borderless `.nonactivatingPanel` child window.
- ⇧⌘M, ⌘S and ⌘D are menu commands in `Commands.swift`, which set `AppModel.propertyMenuRequest`. Menu key equivalents don't fire while Ta Da isn't the active app.
- `AppModel.openLink(to:)` opens a task in its project's page, its area's page or Loose tasks, and a project or area as its own page.

## Decisions
- **Hotkey**: one global hotkey, ⌃Space by default, registered with Carbon `RegisterEventHotKey` (no Accessibility permission, works in the sandbox, no new dependency). It works while Ta Da is running, with or without its window in front; it stops when Ta Da quits. Pressing it while the panel is open closes the panel.
- **Settings ▸ Hotkeys**: a new page after Editor. GLOBAL has the Quick Entry recorder: click to record, the next chord with at least one of ⌃⌥⌘ replaces it, esc cancels. Restore Default and Clear. If registration fails (the chord is taken, e.g. by macOS's input-source switch on ⌃Space), the recorder shows the warning and an Open Keyboard Settings button, and keeps the chord so it registers once freed. IN QUICK ENTRY is fixed text: Create the file ↵, Create and open the file ⌘↵, Close esc. Stored in `SettingsStore` as key code and modifiers; Clear stores none.
- **Panel**: 560 wide, centred on the screen with the pointer, above other apps' windows and on every Space, including over full-screen apps. It takes the keyboard without bringing Ta Da forward: the app behind keeps its menu bar and stays in front once the panel closes. The caret is in the title. It closes on esc, on a click anywhere outside it or its menus, and when another window takes the keyboard. Each opening starts fresh.
- **Fields**: a Task | Project | Area switch (Task first; mouse only, no shortcut). Then the title, "New task/project/area" as placeholder. Then chips as the canvas draws them:
  - Task: status (Not Started), project or area (+ Project), due date, deadline.
  - Project: status (Not Started), area (+ Area), due date, deadline.
  - Area: none, and the note "An area has only its name and tags: no status, parent or dates."
  - Every type: the Tags row, filled chips and + Tag opening tagMenu (Added, All tags with counts, Create #name; a pick toggles and the menu stays open). No "In text" chips.
  Switching type keeps the title and tags and drops the fields the new type lacks.
- **Menus**: the app's own status, project, area and tag menus and calendar, in the panel. ⇧⌘M opens the project menu (task) or area menu (project), ⌘S the due date calendar and ⌘D the deadline calendar; off for an area. The footer shows those keys (only esc for an area).
- **Under the chips**: the file to be written, e.g. `tasks/Call Bea.md`. When the name is taken it shows the numbered name (`projects/Ta Da MVP 2.md`) and a warning, and still creates.
- **Creating**: ↵ creates and closes; ⌘↵ creates, closes, brings Ta Da forward and opens the file (`openLink(to:)`): a task in its project's page, its area's page or Loose tasks, selected; a project or area as its own page. Both are off while the title is empty. Text is `NewFile` for the type with the picked keys; a new task with no parent is loose (not due today). A menu that's open takes ↵ for itself.
- **No folder open**: the hotkey brings Ta Da forward to the folder picker instead of opening the panel.

## Milestones
The milestones run in order in one worktree. Each ends with its check passing.

### C1 — Core
- `NewFile.project(area:tags:today:)` and `NewFile.area(tags:today:)`, writing `tags:` as `task` does.
- `QuickEntryDraft` (`Writing/QuickEntryDraft.swift`): kind, title, status, parent title, due date, deadline, tags. `text(today:)` builds the file with `NewFile` and `FrontmatterEditor.set` for the rest; `folder` gives `tasks`, `projects` or `areas`; `changingKind(to:)` keeps the title and tags and drops what the kind lacks.
- Check: `NewFileTests` for project and area tags; `QuickEntryDraftTests` for every kind's text, the kind switch, and a draft parsing back (`Item(parsing:)`) to the same properties.

### A1 — App model and hotkey
- `AppModel.create(_ draft: QuickEntryDraft) async -> String?` through the existing `create`, with `index.projectFilenames()` as `taken` for a project. `quickEntryTakenNames()` (read once per opening) and `quickEntryPath(for:taken:)` for the line under the chips, numbered as `Vault.create` numbers it.
- `Hotkey` (`QuickEntry/Hotkey.swift`): key code, modifiers and key name, the display string (⌃Space), kept in `SettingsStore` as `AppModel.quickEntryHotkey`.
- `HotkeyService` (`QuickEntry/HotkeyService.swift`): registers one hotkey with Carbon, reports success or failure, calls back on the main actor; a turned-on macOS shortcut on the same keys counts as taken (`CopySymbolicHotKeys`). `AppDelegate` owns it and re-registers when the setting changes.
- Check: `QuickEntryTests` create each kind with every field and with a taken name, and cover `Hotkey` storage and display; macOS and iOS builds.

### M1 — Settings ▸ Hotkeys
- `SettingsView.Page.hotkeys` and `HotkeysSettingsView`: the recorder (`HotkeyRecorder`, a key-taking view while recording), Restore Default, Clear, the taken warning with Open Keyboard Settings (`x-apple.systempreferences:com.apple.Keyboard-Settings.extension`), and the IN QUICK ENTRY list.
- Check: macOS build; record a chord, quit and relaunch, the chord holds; with ⌃Space on for input sources, the warning shows; a `DesignRenderTests` render compared with `SettingsHotkeys`.

### M2 — Panel
- `QuickEntryPanel` (`QuickEntry/QuickEntryPanel.swift`): an `NSPanel` with `.nonactivatingPanel`, floating level, `canJoinAllSpaces` and `fullScreenAuxiliary`, that becomes key; centred on the pointer's screen; closes on `windowDidResignKey` and esc. Opening makes a new `QuickEntryDraft` and view.
- `QuickEntryView` (`QuickEntry/QuickEntryView.swift`): the switch, the title field, the area note, the path line and warning, the footer and its buttons, themed by `AppModel.theme`.
- The Create and Create and Open buttons take ↵ and ⌘↵ as keyboard shortcuts, and a hidden cancel button esc; M3 adds ⇧⌘M, ⌘S and ⌘D.
- ⌘↵ calls `NSApp.activate()`, brings the main window forward (un-minimising it) and `openLink(to:)`.
- Check: from Safari, ⌃Space and type at once: the title fills and Safari keeps its menu bar; click away closes; reopen is empty; ↵ writes the file and Safari is in front; ⌘↵ shows each destination in the canvas's table; works in a full-screen app and on a second display.

### M3 — Chips, menus and tags in the panel
- `AppModel.quickEntryDraft` holds the draft, and `quickEntryItem` gives it as an `Item` at `AppModel.quickEntryDraftPath`, which isn't a file. The pickers' writers (`setStatus`, `setParent`, `setDate`, `addTag`, `removeTag`) edit the draft for that path instead of writing; `item(at:)` gives tagMenu the draft. Chip, picker, anchor and dismissal code stay as they are.
- `QuickEntryView`: `PropertyChipRow` and `TagChipRow` on the draft's item. Hidden buttons take ⇧⌘M, ⌘S and ⌘D and set `propertyMenuRequest` for the draft's chips.
- tagMenu for a draft: Added in place of In this file; Create #name adds the tag to the draft only. The project and area menus' New project… and New Area… create that file, as elsewhere, and file the draft under it.
- The panel stays open while one of its menus has the keyboard, and closes when neither has it.
- Check: `QuickEntryTests` for each draft pick (status, parent, area, dates, add, remove and create a tag) and that a draft pick writes no file; ⇧⌘M and ⌘S open their menus in the panel; renders compared with the canvas's `QuickEntry` states.

### D1 — Docs
- `docs/architecture.md`: the `QuickEntry/` folder, the hotkey service, the panel and its keys, Settings ▸ Hotkeys; the hotkey row in Shortcuts.
- `docs/design/design-framework.md`: In the app rows for the Quick Entry panel and the hotkey recorder; As built differences.
- `docs/archive/`: move this plan there when done.
- `SampleVault`: unchanged unless manual testing writes to it; commit what it wrote.
- Check: all tests (`TaDa.xctestplan`, UI tests with permission), both package suites, macOS and iOS builds; `git diff SampleVault` shows only the intended edits.

## Out of scope
- Shortcuts for switching type.
- A hotkey while Ta Da isn't running: login item or menu-bar mode.
- A body field in the panel.
- iPhone and iPad.
