import CoreGraphics
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
        let lines = NoteBoxLine.lines(in: text, boxes: item.checkboxes)
        #expect(lines == [NoteBoxLine(text: "Call the bank", state: .done), NoteBoxLine(text: "Draft the Starfall rules", state: .doing),
                          NoteBoxLine(text: "Book the Kombi’s roadworthy", state: .open), NoteBoxLine(text: "Nested", state: .open)])
        #expect(NoteBoxLine.count(of: item.checkboxes) == 4, "the cancelled box takes no room")
        #expect(NoteBoxLine.lines(in: "", boxes: item.checkboxes).isEmpty)

        let many = (1...9).map { "- [ ] Box \($0)\n" }.joined()
        let long = try #require(Item(parsing: many, path: "Daily/2026-10-03.md"))
        #expect(NoteBoxLine.count(of: long.checkboxes) == NoteBoxLine.limit)
        #expect(NoteBoxLine.lines(in: many, boxes: long.checkboxes).count == NoteBoxLine.limit)
    }

    @Test func swipingByWeekMovesSevenDaysOrAWeek() {
        #expect(AgendaPaging.selection(stepping: 1, byMonth: false, from: day("2026-10-02")) == day("2026-10-09"))
        #expect(AgendaPaging.selection(stepping: -1, byMonth: false, from: day("2026-01-02")) == day("2025-12-26"), "across a year")
        let week = AppModel.AgendaSelection.week(LocalDate("2026-10-02")!.isoWeek)
        #expect(AgendaPaging.selection(stepping: 1, byMonth: false, from: week) == .week(LocalDate("2026-10-05")!.isoWeek))
    }

    @Test func swipingByMonthClampsAndCrossesYears() {
        #expect(AgendaPaging.selection(stepping: 1, byMonth: true, from: day("2026-01-31")) == day("2026-02-28"))
        #expect(AgendaPaging.selection(stepping: 1, byMonth: true, from: day("2026-12-15")) == day("2027-01-15"))
        #expect(AgendaPaging.selection(stepping: -1, byMonth: true, from: day("2026-01-15")) == day("2025-12-15"))
        #expect(AgendaPaging.selection(stepping: 1, byMonth: true, from: day("2026-10-02")) == day("2026-11-02"))
        // Thursday 2026-10-01 moves to 2026-11-01, a Sunday, in week 2026-10-26.
        let week = AppModel.AgendaSelection.week(LocalDate("2026-09-28")!.isoWeek)
        #expect(AgendaPaging.selection(stepping: 1, byMonth: true, from: week) == .week(LocalDate("2026-10-26")!.isoWeek))
        #expect(AgendaPaging.selection(stepping: -1, byMonth: true, from: .week(LocalDate("2026-12-28")!.isoWeek))
                == .week(LocalDate("2026-11-30")!.isoWeek), "Thursday 2026-12-31 to 2026-11-30")
    }

    @Test func swipesNeedDistanceAndAClearDirection() {
        let far = AgendaSwipe.threshold
        #expect(AgendaSwipe.decide(dx: -far, dy: 0, monthOpen: false) == .step(1))
        #expect(AgendaSwipe.decide(dx: far, dy: 5, monthOpen: true) == .step(-1))
        #expect(AgendaSwipe.decide(dx: -far + 1, dy: 0, monthOpen: false) == nil)
        #expect(AgendaSwipe.decide(dx: -far, dy: far, monthOpen: false) == nil, "diagonal")
        #expect(AgendaSwipe.decide(dx: 0, dy: far, monthOpen: false) == .openMonth)
        #expect(AgendaSwipe.decide(dx: 0, dy: -far, monthOpen: true) == .closeMonth)
        #expect(AgendaSwipe.decide(dx: 0, dy: -far, monthOpen: false) == nil, "nothing above the week")
        #expect(AgendaSwipe.decide(dx: 0, dy: far, monthOpen: true) == nil)
    }

    @Test func aGestureFiresOnce() {
        var tracker = AgendaSwipeTracker()
        #expect(tracker.add(dx: -30, dy: 0, monthOpen: false) == nil)
        #expect(tracker.add(dx: -30, dy: 0, monthOpen: false) == .step(1))
        #expect(tracker.add(dx: -30, dy: 0, monthOpen: false) == nil)
        tracker.reset()
        #expect(tracker.add(dx: 50, dy: 0, monthOpen: false) == .step(-1))
    }

    @Test func monthDragFollowsTheFingerWithinTheRange() {
        let range = AgendaMonthDrag.range(weeks: 5, rowHeight: 46)
        #expect(range == 192)
        #expect(AgendaMonthDrag.progress(start: 0, translation: range / 2, range: range) == 0.5)
        #expect(AgendaMonthDrag.progress(start: 0, translation: -50, range: range) == 0)
        #expect(AgendaMonthDrag.progress(start: 1, translation: 500, range: range) == 1)
        #expect(AgendaMonthDrag.progress(start: 1, translation: -range / 4, range: range) == 0.75)
        #expect(AgendaMonthDrag.isVertical(dx: 3, dy: -12))
        #expect(!AgendaMonthDrag.isVertical(dx: 12, dy: 3))
    }

    @Test func monthDragSettlesByPositionAndVelocity() {
        let range: CGFloat = 192
        #expect(AgendaMonthDrag.settlesOpen(progress: 0.6, velocity: 0, range: range))
        #expect(!AgendaMonthDrag.settlesOpen(progress: 0.4, velocity: 0, range: range))
        #expect(AgendaMonthDrag.settlesOpen(progress: 0.2, velocity: 800, range: range), "a flick down opens")
        #expect(!AgendaMonthDrag.settlesOpen(progress: 0.8, velocity: -800, range: range), "a flick up closes")
    }
}
