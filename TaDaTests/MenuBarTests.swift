import AppKit
import Testing
@testable import TaDa

/// The app's menu bar, as the test host builds it from `AppCommands`.
@MainActor
struct MenuBarTests {
    @Test func theViewMenuShowsEachDomainWithItsKey() async throws {
        var titles: [String] = []
        for _ in 0..<100 {
            titles = NSApp.mainMenu?.items.first { $0.title == "View" }?.submenu?.items
                .filter { $0.keyEquivalentModifierMask == .command && "1234".contains($0.keyEquivalent) }
                .map { "\($0.title) ⌘\($0.keyEquivalent)" } ?? []
            if !titles.isEmpty { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(titles == ["Agenda ⌘1", "Loose Tasks ⌘2", "Trash ⌘3", "Logbook ⌘4"])
    }
}
