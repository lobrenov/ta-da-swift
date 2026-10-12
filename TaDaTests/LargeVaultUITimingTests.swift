import AppKit
import SwiftUI
import Testing
import TaDaCore
@testable import TaDa

/// The window on a generated folder of 1,000 tasks and projects: how long one keystroke in the editor
/// and one arrow-key step in a list take, including SwiftUI's update of every visible view.
@MainActor @Suite(.keyWindow)
struct LargeVaultUITimingTests {
    let folder: TestFolder
    static let today = LocalDate("2026-10-03")!

    init() throws {
        folder = try TestFolder()
        try GeneratedVault.write(to: folder.url, today: Self.today)
    }

    /// Milliseconds per run of `step`, each followed by the window's layout and display.
    private func average(_ runs: Int, in window: NSWindow, _ step: (Int) -> Void) async throws -> Double {
        let view = try #require(window.contentView)
        let clock = ContinuousClock()
        var total = Duration.zero
        for i in 0..<runs {
            total += clock.measure {
                step(i)
                view.layoutSubtreeIfNeeded()
                view.displayIfNeeded()
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        return Double(total.components.attoseconds) / 1e15 / Double(runs) + Double(total.components.seconds) * 1000 / Double(runs)
    }

    @Test func typingAndArrowKeysStayQuick() async throws {
        let model = await folder.model(today: Self.today)
        #expect(model.index.items.count == 1000)
        let today = model.index.grouped(model.index.today(Self.today)).flatMap(\.tasks).map(\.path)
        model.selection = today[0]
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(600))
        let document = try #require(model.document)

        let typing = try await average(30, in: window) { _ in document.body += "x" }
        let selecting = try await average(20, in: window) { i in model.selection = today[i % today.count] }
        print(String(format: "LargeVault window: %.1f ms per keystroke, %.1f ms per list step (Today has %d tasks)",
                     typing, selecting, today.count))
        #expect(typing < 50)
        #expect(selecting < 100)
    }
}
