import CoreGraphics
import Testing
@testable import TaDa

@MainActor @Suite struct TocDrawerRulesTests {
    @Test func progressFollowsTheFingerAndClamps() {
        #expect(TocDrawerRules.progress(start: 0, translation: 0) == 0)
        #expect(TocDrawerRules.progress(start: 0, translation: 50) == 0)
        #expect(TocDrawerRules.progress(start: 0, translation: -159) == 0.5)
        #expect(TocDrawerRules.progress(start: 0, translation: -1000) == 1)
        #expect(TocDrawerRules.progress(start: 1, translation: 159) == 0.5)
        #expect(TocDrawerRules.progress(start: 1, translation: -40) == 1)
    }

    @Test func settlesByFlickThenByHalf() {
        #expect(TocDrawerRules.settlesOpen(progress: 0.2, velocity: -800))
        #expect(!TocDrawerRules.settlesOpen(progress: 0.8, velocity: 800))
        #expect(TocDrawerRules.settlesOpen(progress: 0.6, velocity: 100))
        #expect(!TocDrawerRules.settlesOpen(progress: 0.4, velocity: -100))
    }

    @Test func nothingToShowMeansNoDrawer() {
        let empty = TocContent(headings: [], links: [], backlinks: [])
        let some = TocContent(headings: [], links: [TocFile(title: "A", path: "a.md", icon: .note, hint: "")], backlinks: [])
        #expect(!TocDrawerRules.isAvailable(nil, isSource: false, isSearching: false))
        #expect(!TocDrawerRules.isAvailable(empty, isSource: false, isSearching: false))
        #expect(TocDrawerRules.isAvailable(some, isSource: false, isSearching: false))
        #expect(!TocDrawerRules.isAvailable(some, isSource: true, isSearching: false))
        #expect(!TocDrawerRules.isAvailable(some, isSource: false, isSearching: true))
    }

    @Test func swipeStartsAtTheRightEdgeMovingLeft() {
        let left = CGPoint(x: -500, y: 40)
        #expect(TocDrawerRules.startsOpening(startX: 397, windowWidth: 402, velocity: left))
        #expect(TocDrawerRules.startsOpening(startX: 378, windowWidth: 402, velocity: left))
        #expect(!TocDrawerRules.startsOpening(startX: 377, windowWidth: 402, velocity: left))
        #expect(!TocDrawerRules.startsOpening(startX: 5, windowWidth: 402, velocity: left))
        #expect(!TocDrawerRules.startsOpening(startX: 397, windowWidth: 402, velocity: CGPoint(x: 500, y: 0)))
        #expect(!TocDrawerRules.startsOpening(startX: 397, windowWidth: 402, velocity: CGPoint(x: -100, y: 400)))
    }
}
