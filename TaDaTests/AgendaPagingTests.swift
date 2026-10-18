import Testing
import TaDaCore
@testable import TaDa

/// The iPhone Agenda's page and strip keys, and the checkbox lines of its note card.
@MainActor
struct AgendaPagingTests {
    private func day(_ text: String) -> AppModel.AgendaSelection { .day(LocalDate(text)!) }

    @Test func keysRoundTripAndStepByOne() {
        let friday = day("2026-10-02")
        let key = AgendaPaging.key(of: friday)
        #expect(AgendaPaging.selection(forKey: key, like: friday) == friday)
        #expect(AgendaPaging.selection(forKey: key + 1, like: friday) == day("2026-10-03"))

        let week = AppModel.AgendaSelection.week(LocalDate("2026-10-02")!.isoWeek)
        let weekKey = AgendaPaging.key(of: week)
        #expect(AgendaPaging.selection(forKey: weekKey, like: week) == week)
        #expect(AgendaPaging.selection(forKey: weekKey + 1, like: week) == .week(LocalDate("2026-10-05")!.isoWeek))
        #expect(AgendaPaging.selection(forKey: weekKey - 39, like: week) == .week(LocalDate("2025-12-29")!.isoWeek), "2026-W01 starts in 2025")
    }

    @Test func weeksAcrossAYearEndAreConsecutive() {
        let last = AgendaPaging.key(of: .week(LocalDate("2020-12-31")!.isoWeek))
        let first = AgendaPaging.key(of: .week(LocalDate("2021-01-04")!.isoWeek))
        #expect(first == last + 1)
        #expect(AgendaPaging.week(forKey: last).description == "2020-W53")
    }

    @Test func aDayAndItsWeekShareTheStripKey() {
        let key = AgendaPaging.weekKey(of: day("2026-10-04"))
        #expect(key == AgendaPaging.weekKey(of: day("2026-09-28")))
        #expect(key == AgendaPaging.weekKey(of: .week(LocalDate("2026-10-01")!.isoWeek)))
        #expect(key == AgendaPaging.key(of: .week(LocalDate("2026-10-01")!.isoWeek)))
        #expect(AgendaPaging.weekKey(of: day("2026-10-05")) == key + 1)
    }

    @Test func swipingTheStripMovesWholeWeeks() {
        let key = AgendaPaging.weekKey(of: day("2026-10-02"))
        #expect(AgendaPaging.selection(movingToWeek: key + 1, from: day("2026-10-02")) == day("2026-10-09"), "a day keeps its weekday")
        #expect(AgendaPaging.selection(movingToWeek: key - 1, from: day("2026-10-02")) == day("2026-09-25"))
        #expect(AgendaPaging.selection(movingToWeek: key + 2, from: .week(LocalDate("2026-10-02")!.isoWeek))
                == .week(LocalDate("2026-10-12")!.isoWeek))
        #expect(AgendaPaging.selection(movingToWeek: key, from: day("2026-10-02")) == day("2026-10-02"))
    }

    @Test func pagesCoverARangeAroundToday() {
        let today = LocalDate("2026-10-02")!
        let days = AgendaPaging.keys(like: .day(today), today: today)
        #expect(days.contains(AgendaPaging.key(of: .day(today))) && days.count == 2 * AgendaPaging.dayReach + 1)
        let weeks = AgendaPaging.keys(like: .week(today.isoWeek), today: today)
        #expect(weeks == AgendaPaging.weeks(today: today) && weeks.count == 2 * AgendaPaging.weekReach + 1)
    }

    @Test func boxLinesTakeOpenAndDoneBoxesInOrder() throws {
        let text = "---\ntags: []\n---\n## Plan\n\n- [x] Call the bank\n- [/] Draft the Starfall rules\n- [-] Dropped\n- [ ] Book the Kombi’s roadworthy\n  - [ ] Nested\n"
        let item = try #require(Item(parsing: text, path: "Daily/2026-10-02.md"))
        let lines = NoteBoxLine.lines(in: text, boxes: item.checkboxes, limit: 4)
        #expect(lines == [NoteBoxLine(text: "Call the bank", state: .done), NoteBoxLine(text: "Draft the Starfall rules", state: .doing),
                          NoteBoxLine(text: "Book the Kombi’s roadworthy", state: .open), NoteBoxLine(text: "Nested", state: .open)])
        #expect(NoteBoxLine.lines(in: text, boxes: item.checkboxes, limit: 2).count == 2)
        #expect(NoteBoxLine.lines(in: "", boxes: item.checkboxes, limit: 4).isEmpty)
    }
}
