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

        // The fixtures count as logged that day, so opening them moves nothing to `.logbook/`.
        AppModel.setLastLogged(sampleVault, to: LocalDate("2026-10-02")!, in: defaults)
        let model = AppModel(defaults: defaults)
        model.today = LocalDate("2026-10-02")!
        await model.choose(sampleVault)
        #expect(model.state == .ready)
        let project = "projects/Ta Da MVP.md"
        // Artboard name → domain and selection.
        let screens: [(String, AppModel.Domain, String?)] = [
            ("today", .today, "tasks/Update my claude.md files.md"),
            ("upcoming", .upcoming, nil),
            ("upcoming-task", .upcoming, "tasks/Live preview editor on swift-markdown-engine.md"),
            ("project", .project(project), project),
            ("project-task", .project(project), "tasks/Live preview editor on swift-markdown-engine.md"),
            ("loose", .loose, nil),
            ("source", .today, "tasks/Update my claude.md files.md"),
            ("search", .today, "tasks/Update my claude.md files.md"),
        ]
        model.usesSchemePerAppearance = true
        for theme in Theme.all {
            model.appearance = theme.isDark ? .dark : .light
            if theme.isDark { model.darkScheme = theme } else { model.lightScheme = theme }
            for (name, domain, selection) in screens where name == "today" || theme == ThemeSet.standard.dark {
                model.domain = domain
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
            ("area-today", .today, "tasks/Build the sidebar.md"),
            ("area-project", .project("projects/Ta Da.md"), "projects/Ta Da.md"),
        ]
        for (name, domain, selection) in areaScreens {
            areas.domain = domain
            areas.selection = selection
            try await render(areas, to: output.appending(path: "\(name).png"))
        }
        // The Logbook, on a copy of the design's data with its completed files logged, one completed and one cancelled
        // today, in the default dark scheme.
        let copy = FileManager.default.temporaryDirectory.appending(path: "DesignVault-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.copyItem(at: sampleVault, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        let logbook = AppModel(defaults: TestSettings())
        logbook.today = LocalDate("2026-10-02")!
        await logbook.choose(copy)
        await logbook.setStatus(.done, in: "tasks/Update my claude.md files.md")
        await logbook.setStatus(.cancelled, in: "tasks/Submit timesheet.md")
        logbook.appearance = .dark
        logbook.show(.logbook)
        logbook.selection = ".logbook/2026-09/Frontmatter schema for tasks and projects.md"
        try await render(logbook, to: output.appending(path: "logbook.png"))
        logbook.completionConfirmation = AppModel.CompletionConfirmation(
            project: try #require(logbook.index[project]), status: .done, tasks: logbook.index.openTasks(in: try #require(logbook.index[project])))
        try await render(CompletionDialog(model: logbook, request: try #require(logbook.completionConfirmation)).themed(by: logbook),
                         width: 480, to: output.appending(path: "logbook-confirm.png"))

        // The window's sidebar is glass, which doesn't draw here, so the sidebar also renders on its own.
        areas.domain = .area("areas/Personal.md")
        try await render(SidebarView(model: areas).themed(by: areas), width: 240, to: output.appending(path: "area-sidebar.png"))
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
