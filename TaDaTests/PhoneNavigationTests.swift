import Testing
import TaDaCore
@testable import TaDa

/// The iPhone's picking and date-sheet rules. They don't touch UIKit, so they run with the Mac's tests.
@MainActor
struct PhoneNavigationTests {
    @Test func swipingPicksInOrderAndUnpickingTheLastEndsPicking() {
        let nav = PhoneNavigation()
        nav.startPicking("a")
        #expect(nav.isPicking && nav.picked == ["a"])
        nav.togglePicked("c")
        nav.togglePicked("b")
        #expect(nav.picked == ["a", "c", "b"])
        nav.togglePicked("c")
        #expect(nav.picked == ["a", "b"] && nav.isPicking)
        nav.togglePicked("a")
        nav.togglePicked("b")
        #expect(nav.picked.isEmpty && !nav.isPicking)
    }

    @Test func selectStartsPickingWithNothingPicked() {
        let nav = PhoneNavigation()
        nav.startPicking()
        #expect(nav.isPicking && nav.picked.isEmpty)
    }

    @Test func pickAllPicksTheListOnScreen() {
        let nav = PhoneNavigation()
        nav.setPickable(["a", "b", "c"])
        nav.startPicking("b")
        nav.pickAll()
        #expect(nav.picked == ["a", "b", "c"])
    }

    @Test func endingPickingClearsThePickedRows() {
        let nav = PhoneNavigation()
        nav.setPickable(["a", "b"])
        nav.startPicking("a")
        nav.endPicking()
        #expect(!nav.isPicking && nav.picked.isEmpty)
        #expect(nav.pickable == ["a", "b"])
    }

    @Test func rowsTheListStopsShowingAreUnpicked() {
        let nav = PhoneNavigation()
        nav.setPickable(["a", "b", "c"])
        nav.startPicking("a")
        nav.togglePicked("b")
        nav.setPickable(["b", "c"])
        #expect(nav.picked == ["b"] && nav.isPicking, "keeps the rows still shown, in pick order")
        nav.setPickable(["c"])
        #expect(nav.picked.isEmpty && !nav.isPicking, "picking ends when none is left")
    }

    @Test func aListThatKeepsAllPickedRowsChangesNothing() {
        let nav = PhoneNavigation()
        nav.setPickable(["a", "b"])
        nav.startPicking("a")
        nav.setPickable(["b", "a", "c"])
        #expect(nav.picked == ["a"] && nav.isPicking)
    }

    @Test func theDateSheetWritesOnlyTheKindsItChanged() {
        let due = LocalDate("2026-10-02")!
        let deadline = LocalDate("2026-10-09")!
        let days: [AgendaEntry.Kind: LocalDate?] = [.due: due, .deadline: deadline]
        #expect(AgendaEntry.Kind.changes([], in: days).isEmpty)
        #expect(AgendaEntry.Kind.changes([.deadline], in: days).map(\.0) == [.deadline])
        #expect(AgendaEntry.Kind.changes([.deadline], in: days).map(\.1) == [deadline])
        #expect(AgendaEntry.Kind.changes([.deadline, .due], in: days).map(\.0) == [.due, .deadline], "due date first")
    }

    @Test func aClearedKindIsWrittenAsNil() {
        let days: [AgendaEntry.Kind: LocalDate?] = [.due: nil, .deadline: LocalDate("2026-10-09")]
        let changes = AgendaEntry.Kind.changes([.due], in: days)
        #expect(changes.count == 1 && changes[0].0 == .due && changes[0].1 == nil)
    }
}
