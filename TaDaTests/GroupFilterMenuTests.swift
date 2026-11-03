import Foundation
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct GroupFilterMenuTests {
    private let items = [
        ("Ta Da/tasks/A.md", "---\ntype: task\nstatus: Doing\ntags: [bug, ux]\n---\n"),
        ("Ta Da/tasks/B.md", "---\ntype: task\nstatus: Doing\ntags: [dev]\n---\n"),
    ].compactMap { Item(parsing: $0.1, path: $0.0) }

    private func menu(grouped: Bool = true, picked: Set<String> = [], query: String = "", keeping: String? = nil)
        -> (titles: [[String]], labels: [String?], highlight: Int?) {
        let list = GroupedList.project
        let menu = GroupFilterChoice.menu(groupings: grouped ? (list.defaultGrouping, list) : nil, items: items, picked: picked,
                                          query: query, keeping: keeping)
        return (menu.sections.map { $0.items.map(\.title) }, menu.sections.map(\.label), menu.highlight)
    }

    @Test func listsGroupByThenTheTagsWithTheCurrentGroupingHighlighted() {
        let list = GroupedList.project
        let shown = menu()
        #expect(shown.labels == ["Group by", "Filter by tag"])
        #expect(shown.titles == [list.groupings.map(\.rawValue), ["bug", "dev", "ux"]])
        #expect(shown.highlight == list.groupings.firstIndex(of: list.defaultGrouping))
    }

    @Test func aPageWithNoGroupingListsOnlyTheTags() {
        let shown = menu(grouped: false)
        #expect(shown.labels == ["Filter by tag"])
        #expect(shown.highlight == 0)
    }

    @Test func aSearchHidesGroupByAndHighlightsTheFirstMatch() {
        let shown = menu(query: "d")
        #expect(shown.titles == [["dev"]])
        #expect(shown.highlight == 0)
        #expect(menu(query: "zzz").titles.isEmpty, "no sections, so the menu says No tags match")
    }

    @Test func theTagJustToggledStaysHighlightedAfterTheGroupings() {
        let groupings = GroupedList.project.groupings.count
        #expect(menu(picked: ["ux"], keeping: "ux").highlight == groupings + 2)
    }
}
