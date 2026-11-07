import AppKit
import SwiftUI
import Testing
import TaDaCore
@testable import TaDa

/// Renders the main window on the design's data (TaDaCore's DesignVault fixture, frozen from SampleVault)
/// for every scheme and domain, as PNGs to compare with the design canvas. Off by default. It reads the
/// fixture from the repo, so run it without the sandbox:
///
///     TEST_RUNNER_TADA_RENDER_DIR=/path/to/output xcodebuild -workspace TaDa.xcworkspace -scheme TaDa \
///       -destination 'platform=macOS' test -only-testing:TaDaTests/DesignRenderTests ENABLE_APP_SANDBOX=NO
@MainActor
struct DesignRenderTests {
    nonisolated static let output = ProcessInfo.processInfo.environment["TADA_RENDER_DIR"]

    @Test(.enabled(if: output != nil))
    func renderEveryThemeAndDomain() async throws {
        let output = URL(filePath: try #require(Self.output), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let sampleVault = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../Packages/TaDaCore/Tests/TaDaCoreTests/Fixtures/DesignVault").standardized
        let defaults = TestSettings()

        let empty = AppModel(defaults: defaults)
        try await render(empty, to: output.appending(path: "onboarding.png"))

        // The fixtures count as logged that day, so opening them moves nothing to `Ta Da/logbook/`.
        AppModel.setLastLogged(sampleVault, to: LocalDate("2026-10-02")!, in: defaults)
        let model = AppModel(defaults: defaults)
        model.today = LocalDate("2026-10-02")!
        await model.choose(sampleVault)
        #expect(model.state == .ready)
        let project = "Ta Da/projects/Ta Da MVP.md"
        // Artboard name → domain and selection.
        let screens: [(String, AppModel.Domain, String?)] = [
            ("agenda-day", .agenda, nil),
            ("agenda-week", .agenda, nil),
            ("upcoming-task", .agenda, "Ta Da/tasks/Live preview editor on swift-markdown-engine.md"),
            ("project", .project(project), project),
            ("project-task", .project(project), "Ta Da/tasks/Live preview editor on swift-markdown-engine.md"),
            ("loose", .loose, nil),
            ("source", .agenda, "Ta Da/tasks/Update my claude.md files.md"),
            ("search", .agenda, "Ta Da/tasks/Update my claude.md files.md"),
        ]
        model.usesSchemePerAppearance = true
        for theme in Theme.all {
            model.appearance = theme.isDark ? .dark : .light
            if theme.isDark { model.darkScheme = theme } else { model.lightScheme = theme }
            for (name, domain, selection) in screens where name == "agenda-day" || theme == ThemeSet.standard.dark {
                model.domain = domain
                model.agendaSelection = name == "agenda-week" ? .week(ISOWeek(year: 2026, week: 40)!) : .day(model.today)
                model.agendaMonthOpen = name == "agenda-week"
                model.selection = selection
                model.isSourceMode = name == "source"
                model.searchText = name == "search" ? "update" : ""
                try await render(model, to: output.appending(path: "\(theme.name)-\(name).png"))
            }
        }

        // Areas, on TaDaCore's AreaVault fixture, in the default dark scheme.
        let areaVault = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../Packages/TaDaCore/Tests/TaDaCoreTests/Fixtures/AreaVault").standardized
        AppModel.setLastLogged(areaVault, to: LocalDate("2026-10-02")!, in: defaults)
        let areas = AppModel(defaults: defaults)
        areas.today = LocalDate("2026-10-02")!
        await areas.choose(areaVault)
        areas.appearance = .dark
        let areaScreens: [(String, AppModel.Domain, String?)] = [
            ("area", .area("areas/Personal.md"), "tasks/Pay rent.md"),
            ("area-file", .area("areas/Personal.md"), "areas/Personal.md"),
            ("area-today", .agenda, "tasks/Build the sidebar.md"),
            ("area-project", .project("projects/Ta Da.md"), "projects/Ta Da.md"),
        ]
        for (name, domain, selection) in areaScreens {
            areas.domain = domain
            areas.selection = selection
            try await render(areas, to: output.appending(path: "\(name).png"))
        }
        // Tags, on TaDaCore's TagVault fixture, in the default dark scheme.
        let tagVault = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../Packages/TaDaCore/Tests/TaDaCoreTests/Fixtures/TagVault").standardized
        AppModel.setLastLogged(tagVault, to: LocalDate("2026-10-02")!, in: defaults)
        let tags = AppModel(defaults: defaults)
        tags.today = LocalDate("2026-10-02")!
        await tags.choose(tagVault)
        tags.appearance = .dark
        tags.domain = .project("projects/Garden.md")
        tags.selection = "tasks/Prune the lemon tree.md"
        try await render(tags, to: output.appending(path: "tag-task.png"))
        tags.domain = .area("areas/Home.md")
        try await render(tags, to: output.appending(path: "tag-area.png"))
        // Group and Filter: Loose tasks by Status, filtered to one tag.
        tags.domain = .loose
        tags.setGrouping(.status, of: .loose)
        tags.toggleFilterTag("errands", on: .loose)
        try await render(tags, to: output.appending(path: "group-loose-filtered.png"))
        tags.clearTagFilter(on: .loose)
        tags.domain = .area("areas/Home.md")
        tags.toggleFilterTag("home/garden", on: .area("areas/Home.md"))
        try await render(tags, to: output.appending(path: "group-area-filtered.png"))
        tags.clearTagFilter(on: .area("areas/Home.md"))
        tags.domain = .tag("errands")
        tags.selection = "tasks/Message Max.md"
        try await render(tags, to: output.appending(path: "tag-browser.png"))
        tags.domain = .tag("people")
        try await render(tags, to: output.appending(path: "tag-browser-parent.png"))
        tags.domain = .tag(nil)
        try await render(tags, to: output.appending(path: "tag-untagged.png"))
        tags.sidebarMode = .tags
        tags.domain = .tag("work/clients")
        try await render(SidebarView(model: tags).themed(by: tags), width: 240, to: output.appending(path: "tag-sidebar.png"))
        tags.sidebarMode = .projects
        try await render(SidebarView(model: tags).themed(by: tags), width: 240, to: output.appending(path: "tag-sidebar-projects.png"))

        // Notes, on TaDaCore's NoteVault fixture, in the default dark scheme.
        let noteVault = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../Packages/TaDaCore/Tests/TaDaCoreTests/Fixtures/NoteVault").standardized
        AppModel.setLastLogged(noteVault, to: LocalDate("2026-10-02")!, in: defaults)
        let notes = AppModel(defaults: defaults)
        notes.today = LocalDate("2026-10-02")!
        await notes.choose(noteVault)
        notes.appearance = .dark
        notes.domain = .folder("Meetings")
        notes.selection = "Meetings/Ark planning call.md"
        try await render(notes, to: output.appending(path: "notes-folder.png"))
        notes.domain = .folder("")
        try await render(notes, to: output.appending(path: "notes-loose.png"))
        notes.domain = .tag("work")
        try await render(notes, to: output.appending(path: "notes-tag.png"))
        notes.domain = .folder("Meetings/2026")
        try await render(SidebarView(model: notes).themed(by: notes), width: 240, to: output.appending(path: "notes-sidebar.png"))
        let request = AppModel.ConvertRequest(path: "Meetings/Ark planning call.md", kind: .task)
        try await render(ConvertSheet(model: notes, request: request).themed(by: notes), width: 480,
                         to: output.appending(path: "notes-convert.png"))
        notes.appearance = .light
        notes.domain = .folder("Meetings")
        notes.selection = "Meetings/Ark planning call.md"
        try await render(notes, to: output.appending(path: "notes-folder-light.png"))

        // The Logbook, on a copy of the design's data with its completed files logged, one completed and one cancelled
        // today, in the default dark scheme.
        let copy = FileManager.default.temporaryDirectory.appending(path: "DesignVault-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: sampleVault, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        let logbook = AppModel(defaults: TestSettings())
        logbook.today = LocalDate("2026-10-02")!
        await logbook.choose(copy)
        await logbook.setStatus(.done, in: "Ta Da/tasks/Update my claude.md files.md")
        await logbook.setStatus(.cancelled, in: "Ta Da/tasks/Submit timesheet.md")
        logbook.appearance = .dark
        logbook.show(.logbook)
        logbook.selection = "Ta Da/logbook/2026-09/Frontmatter schema for tasks and projects.md"
        try await render(logbook, to: output.appending(path: "logbook.png"))
        logbook.completionConfirmation = AppModel.CompletionConfirmation(
            project: try #require(logbook.index[project]), status: .done, tasks: logbook.index.openTasks(in: try #require(logbook.index[project])))
        try await render(CompletionDialog(model: logbook, request: try #require(logbook.completionConfirmation)).themed(by: logbook),
                         width: 480, to: output.appending(path: "logbook-confirm.png"))

        // Settings ▸ Hotkeys with the default taken by macOS, in the default dark scheme.
        let hotkeys = AppModel(defaults: TestSettings())
        hotkeys.appearance = .dark
        hotkeys.quickEntryHotkeyTaken = true
        try await render(HotkeysSettingsView(model: hotkeys).themed(by: hotkeys).frame(height: 1180, alignment: .top), width: 700,
                         to: output.appending(path: "settings-hotkeys.png"))

        // Quick Entry on the design's data, in the default dark scheme: empty, typed, an area, and a taken name.
        model.usesSchemePerAppearance = false
        model.appearance = .dark
        var typed = QuickEntryDraft()
        typed.title = "Call Bea about the venue"
        typed.parent = .project("Ta Da MVP")
        typed.dueDate = LocalDate("2026-10-03")
        typed.tags = [Tag("gamejams")!, Tag("people/bea")!]
        var area = typed.changingKind(to: .area)
        area.title = "Wellbeing"
        var taken = typed.changingKind(to: .project)
        taken.title = "Ta Da MVP"
        for (name, draft) in [("empty", QuickEntryDraft()), ("typed", typed), ("area", area), ("taken", taken)] {
            model.quickEntryDraft = draft
            let view = QuickEntryView(model: model, taken: model.quickEntryTakenNames(), create: { _ in }, close: {})
                .themed(by: model).padding(20).frame(height: 300, alignment: .top)
            try await render(view, width: 600, to: output.appending(path: "quick-entry-\(name).png"))
        }

        // The window's sidebar is glass, which doesn't draw here, so the sidebar also renders on its own.
        areas.domain = .area("areas/Personal.md")
        try await render(SidebarView(model: areas).themed(by: areas), width: 240, to: output.appending(path: "area-sidebar.png"))
    }

    /// The tocPanel's rail and open panel on a task with headings, links and backlinks, in the standard light and dark schemes.
    @Test(.enabled(if: output != nil))
    func renderTocRailAndPanel() async throws {
        let output = URL(filePath: try #require(Self.output), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let folder = try TestFolder([
            "areas/Megagames.md": "---\ntype: area\n---\n",
            "notes/Release notes template.md": "Template.\n",
            "notes/Swift conventions.md": "Conventions.\n",
            "projects/Obsidian plugin.md": "---\ntype: project\n---\n",
            "tasks/Ship the beta.md": "---\ntype: task\nstatus: Doing\n---\nSee [[Plan the beta]].\n",
            "tasks/Plan the beta.md": """
            ---
            type: task
            ---
            ## Scope
            ### Must ship
            Uses [[Release notes template]], [[Megagames]], [[Swift conventions]] and [[Crash reporting]].
            ### Can wait
            ## Testers
            ## Risks
            """,
        ])
        let model = await folder.model(selecting: "tasks/Plan the beta.md")
        let item = try #require(model.index["tasks/Plan the beta.md"])
        let content = TocContent(item: item, index: model.index)
        #expect(content.headings.count == 5 && content.links.count == 4 && content.backlinks.count == 1)
        for theme in [ThemeSet.standard.light, ThemeSet.standard.dark] {
            model.appearance = theme.isDark ? .dark : .light
            let rail = TocRail(content: content, current: 1).padding(20).background(Color(theme.bg))
            try await render(rail.themed(by: model), width: 120, to: output.appending(path: "toc-rail-\(theme.name).png"))
            let panel = TocPanel(content: content, current: 1, maxHeight: 700, scroll: { _ in }, open: { _ in })
                .padding(20).background(Color(theme.bg))
            try await render(panel.themed(by: model), width: 320, to: output.appending(path: "toc-panel-\(theme.name).png"))
        }
    }

    private func render(_ model: AppModel, to url: URL) async throws {
        try await render(ContentView(model: model), width: 1280, to: url)
    }

    private func render(_ view: some View, width: CGFloat, to url: URL) async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 800),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(600))
        let view = try #require(window.contentView?.superview ?? window.contentView)
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
        window.orderOut(nil)
    }
}
