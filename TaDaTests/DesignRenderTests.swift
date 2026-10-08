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
    }

    private func render(_ model: AppModel, to url: URL) async throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(600))
        let view = try #require(window.contentView?.superview ?? window.contentView)
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
        window.orderOut(nil)
    }
}
