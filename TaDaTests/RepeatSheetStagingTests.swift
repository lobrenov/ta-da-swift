import Foundation
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct RepeatSheetStagingTests {
    private typealias Repeating = CalendarPickerModel.Repeating

    private func task(_ extra: String = "", path: String = "tasks/Water.md") -> Item {
        Item(parsing: "---\ntype: task\nstatus: Not Started\n\(extra)---\n", path: path)!
    }

    private func rule(_ text: String) -> RepeatRule { RepeatRule.parse(text)! }

    @Test func stagingSetsOnlyTheChangedKindsDates() {
        let item = task("dueDate: 2026-11-02\ndeadline: 2026-11-09\n")
        let days: [AgendaEntry.Kind: LocalDate?] = [.due: LocalDate("2026-11-20")!, .deadline: nil]
        let due = Repeating.staged([item], days: days, changed: [.due])[0].properties
        #expect(due.dueDate == LocalDate("2026-11-20")! && due.deadline == LocalDate("2026-11-09")!)
        let deadline = Repeating.staged([item], days: days, changed: [.deadline])[0].properties
        #expect(deadline.dueDate == LocalDate("2026-11-02")! && deadline.deadline == nil)
    }

    @Test func aMovedDeadlineAnchorsThePreviewOfADeadlineOnlyTask() {
        let item = task("deadline: 2026-11-02\n")
        let staged = Repeating.staged([item], days: [.due: nil, .deadline: LocalDate("2026-11-04")!], changed: [.deadline])
        let picker = CalendarPickerModel()
        picker.today = LocalDate("2026-11-01")!
        picker.other = LocalDate("2026-11-04")!
        picker.configure(Repeating(items: staged, index: VaultIndex(), rule: rule("every week")) { _, _ in })
        let days = picker.occurrenceDays(in: LocalDate("2026-11-01")!)
        #expect(days.contains(LocalDate("2026-11-11")!))
        #expect(!days.contains(LocalDate("2026-11-09")!), "not the old deadline's weeks")
    }

    @Test func theSharedRuleIsTheOneEveryFileHas() {
        let weekly = task("repeat: every week\ndueDate: 2026-11-02\n")
        let other = task("repeat: every day\ndueDate: 2026-11-02\n", path: "tasks/Other.md")
        #expect(Repeating.sharedRule(of: [weekly, weekly]) == weekly.properties.repeatRule?.rule)
        #expect(Repeating.sharedRule(of: [weekly, other]) == nil)
        #expect(Repeating.sharedRule(of: [task()]) == nil)
    }

    @Test func aHeldRuleLosesAnEndBeforeTheNewStart() {
        let ending = rule("every week").ending(on: LocalDate("2026-11-10")!)
        let moved = Repeating.staged([task("dueDate: 2026-11-02\n")], days: [.due: LocalDate("2026-11-20")!], changed: [.due])
        let kept = Repeating.staged([task("dueDate: 2026-11-02\n")], days: [.due: LocalDate("2026-11-05")!], changed: [.due])
        #expect(Repeating.held(.some(ending), staged: moved) == .some(ending.ending(on: nil)))
        #expect(Repeating.held(.some(ending), staged: kept) == .some(ending))
        #expect(Repeating.held(.some(ending), staged: Repeating.staged([task()], days: [.due: nil], changed: [.due])) == .some(ending))
    }

    @Test func aHeldRuleWithNoEndOrNoChangeIsLeftAlone() {
        let moved = Repeating.staged([task()], days: [.due: LocalDate("2026-11-20")!], changed: [.due])
        let open = rule("every week")
        #expect(Repeating.held(.some(open), staged: moved) == .some(open))
        #expect(Repeating.held(.some(nil), staged: moved) == .some(nil), "a stopped repeat stays stopped")
        #expect(Repeating.held(nil, staged: moved) == nil, "an untouched rule stays untouched")
    }

    @Test func theEndChoicesAreNeverFourWeeksAndYearEnd() {
        let picker = CalendarPickerModel()
        picker.today = LocalDate("2026-11-01")!
        let choices = picker.endChoices
        #expect(choices.map(\.title) == ["Never", "In 4 weeks", "End of year"])
        #expect(choices.map(\.day) == [nil, LocalDate("2026-11-29")!, LocalDate("2026-12-31")!])
    }
}
