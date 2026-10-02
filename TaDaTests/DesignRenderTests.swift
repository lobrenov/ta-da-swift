import AppKit
import SwiftUI
import Testing
import TaDaCore
@testable import TaDa

/// Renders the main window on SampleVault for every theme and domain, as PNGs to compare with the
/// design canvas. Off by default. It reads the repo's SampleVault, so run it without the sandbox:
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
            .appending(path: "../SampleVault").standardized
        let suite = "TaDaRender-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let empty = AppModel(defaults: defaults)
        try await render(empty, to: output.appending(path: "onboarding.png"))

        let model = AppModel(defaults: defaults)
        model.today = LocalDate("2026-10-02")!
        await model.choose(sampleVault)
        #expect(model.state == .ready)
        let project = try #require(model.projects.first { $0.project.title == "Ta Da MVP" })
        let domains: [(String, AppModel.Domain)] = [
            ("today", .today), ("upcoming", .upcoming), ("loose", .loose), ("project", .project(project.project.path)),
        ]
        for theme in Theme.all {
            model.themeName = theme.name
            for (name, domain) in domains where name == "today" || theme.name == Theme.all[0].name {
                model.domain = domain
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
