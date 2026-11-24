import Foundation
import Testing
import TaDaCore
@testable import TaDa

/// The work behind a keystroke or a render on a large folder: ranking link-menu matches and building the Logbook's groups.
@MainActor
struct ListBuildTimingTests {
    private static let words = ["call", "review", "kombi", "plan", "gate", "invoice", "photo", "service", "draft", "sign-off"]

    private static func items(_ count: Int, folder: String = "Ta Da/tasks", frontmatter: (Int) -> String) -> [Item] {
        (0..<count).map { i in
            let title = "Task \(i) \(words[i % words.count]) \(words[(i / 7) % words.count])"
            return Item(parsing: "---\n\(frontmatter(i))\n---\n", path: "\(folder)/\(title).md")!
        }
    }

    @Test func linkMenuRankingKeepsTheOldOrderAndIsQuickOver10kItems() {
        let items = Self.items(10_000) { _ in "type: task\nstatus: Doing" }
        let recent = [items[40], items[9_000], items[5]]
        let others = items.filter { !recent.contains($0) }
        for query in ["kombi", "re", "sign", "task 12", "zzz"] {
            let old = LinkSearch.rank(recent + others.sorted(by: VaultIndex.byTitle), query: query, name: \.title)
            #expect(LinkMenuSearch.rank(recent: recent, others: others, query: query, limit: 50).map(\.path) == old.prefix(50).map(\.path), "\(query)")
        }
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = LinkMenuSearch.rank(recent: recent, others: others, query: "re", limit: 50) }
        print("link menu ranking over 10k items: \(elapsed)")
        #expect(elapsed < .milliseconds(100))
    }

    @Test func aMonthOf2000LoggedItemsGroupsQuickly() {
        let today = LocalDate("2026-10-03")!
        let items = Self.items(2_000, folder: "Ta Da/logbook/2026-09") { i in
            "type: task\nstatus: Done\ncompletedDate: 2026-09-\(String(format: "%02d", 1 + i % 20))"
        }
        let index = VaultIndex(items)
        let clock = ContinuousClock()
        var groups: [LogbookGroup] = []
        let elapsed = clock.measure { groups = LogbookGroup.groups(items, index: index, today: today) }
        print("logbook groups for 2,000 items: \(elapsed)")
        #expect(groups.count == 1 && groups[0].items.count == 2_000)
        #expect(elapsed < .milliseconds(50))
    }
}
