import Testing
import TaDaCore
@testable import TaDa

@MainActor @Suite struct RepeatWordingTests {
    // Friday 2 Oct 2026
    private let today = LocalDate("2026-10-02")!

    private func day(_ text: String) -> String { LocalDate(text)!.formatted(.weekdayDayMonth) }

    private func item(_ frontmatter: String, in parent: String? = nil) -> (Item, VaultIndex) {
        let link = parent == nil ? "" : "\nproject: \"[[P]]\""
        let task = Item(parsing: "---\ntype: task\n\(frontmatter)\(link)\n---\n", path: "Ta Da/tasks/T.md")!
        let project = parent.map { Item(parsing: "---\ntype: project\nstatus: \($0)\n---\n", path: "Ta Da/projects/P.md")! }
        return (task, VaultIndex([task] + [project].compactMap { $0 }))
    }

    @Test func theRuleRidesOnTheDueChipElseTheDeadlineChip() {
        func kind(_ frontmatter: String) -> AgendaEntry.Kind? { RepeatWording.chipKind(of: item(frontmatter).0.properties) }
        #expect(kind("dueDate: 2026-10-05\nrepeat: every week") == .due)
        #expect(kind("dueDate: 2026-10-05\ndeadline: 2026-10-09\nrepeat: every week") == .due)
        #expect(kind("deadline: 2026-10-09\nrepeat: every week") == .deadline)
        #expect(kind("repeat: every week") == .due)
        #expect(kind("dueDate: 2026-10-05") == nil)
    }

    @Test func theChipTooltipSpellsTheRuleItsEndAndTheNextDate() {
        let (task, index) = item("status: Doing\ndueDate: 2026-10-05\nrepeat: every week on Mon until 2026-12-20")
        let rule = task.properties.repeatRule!
        #expect(rule.rule?.frequencyLabel == "Weekly")
        let tip = RepeatWording.chipHelp(rule, next: index.repeatMove(of: task, today: today, completing: true), today: today)
        #expect(tip == "Repeats every week on Monday until \(day("2026-12-20")) · next \(day("2026-10-12"))")
    }

    @Test func aRuleOnItsLastOccurrenceHasNoNextDate() {
        let (task, index) = item("status: Doing\ndueDate: 2026-10-05\nrepeat: every week until 2026-10-05")
        let tip = RepeatWording.chipHelp(task.properties.repeatRule!, next: index.repeatMove(of: task, today: today, completing: true), today: today)
        #expect(tip == "Repeats every week until \(day("2026-10-05"))")
    }

    @Test func anUnreadableRuleSaysSoAndShowsAsWritten() {
        let (task, _) = item("dueDate: 2026-10-05\nrepeat: Weekly · Fri")
        let rule = task.properties.repeatRule!
        #expect(RepeatWording.chipHelp(rule, next: nil, today: today) == "Ta Da can't read this rule, so the task doesn't repeat")
        #expect(rule.rule == nil && rule.text == "Weekly · Fri")
        #expect(RepeatWording.rowHelp(rule, move: nil, today: today) == "Repeats Weekly · Fri")
    }

    @Test func aDoneRowShowsWhereItMovesOrThatItEnded() {
        let (done, index) = item("status: Done\ncompletedDate: 2026-10-02\ndueDate: 2026-10-02\nrepeat: every day")
        let move = index.repeatMove(of: done, today: today)!
        #expect(RepeatWording.rowNext(move, today: today) == "Tomorrow")
        #expect(RepeatWording.rowHelp(done.properties.repeatRule!, move: move, today: today)
                == "Repeats every day · moves to tomorrow when the day changes")
        let (skipped, skippedIndex) = item("status: Cancelled\ncompletedDate: 2026-10-02\ndueDate: 2026-10-02\nrepeat: every week")
        let later = skippedIndex.repeatMove(of: skipped, today: today)!
        #expect(RepeatWording.rowNext(later, today: today) == day("2026-10-09"))
        let (ended, endedIndex) = item("status: Done\ncompletedDate: 2026-10-02\ndueDate: 2026-10-02\nrepeat: every day until 2026-10-02")
        #expect(RepeatWording.rowNext(endedIndex.repeatMove(of: ended, today: today)!, today: today) == "Ended")
        let (inClosed, closedIndex) = item("status: Done\ncompletedDate: 2026-10-02\ndueDate: 2026-10-02\nrepeat: every day", in: "Done")
        #expect(RepeatWording.rowNext(closedIndex.repeatMove(of: inClosed, today: today)!, today: today) == "Ended")
    }

    @Test func theStatusMenuReadsSkipAndWhereTheTaskMoves() {
        let (task, index) = item("status: Doing\ndueDate: 2026-10-05\nrepeat: every week")
        let (repeating, move) = RepeatWording.statusContext(of: [task], index: index, today: today)
        #expect(repeating && move == .moves(to: LocalDate("2026-10-12")!))
        #expect(RepeatWording.title(of: .cancelled, repeating: repeating) == "Skip this time")
        #expect(RepeatWording.title(of: .done, repeating: repeating) == "Done")
        #expect(RepeatWording.note(move!, today: today) == "moves to \(day("2026-10-12"))")
        #expect(RepeatWording.statusHelp(.cancelled, repeating: repeating, move: move, today: today) == "Skip this time · moves to \(day("2026-10-12"))")
        #expect(RepeatWording.statusHelp(.done, repeating: repeating, move: move, today: today) == "Done · moves to \(day("2026-10-12"))")
        #expect(RepeatWording.statusHelp(.doing, repeating: repeating, move: move, today: today) == "Doing")
        #expect(RepeatWording.statusHelp(.done, repeating: repeating, move: move, current: .done, today: today) == "Done")
        #expect(RepeatWording.statusHelp(.cancelled, repeating: repeating, move: move, current: .done, today: today)
                == "Skip this time · moves to \(day("2026-10-12"))")
        #expect(RepeatWording.note(.ends, today: today) == "ends the repeat")
    }

    @Test func aPlainTaskKeepsItsWording() {
        let (task, index) = item("status: Doing\ndueDate: 2026-10-05")
        let (repeating, move) = RepeatWording.statusContext(of: [task], index: index, today: today)
        #expect(!repeating && move == nil)
        #expect(RepeatWording.statusHelp(.cancelled, repeating: repeating, move: move, today: today) == "Cancelled")
    }

    @Test func pickedFilesUseTheWordingOnlyWhenItIsTrueForAll() {
        let a = Item(parsing: "---\ntype: task\nstatus: Doing\ndueDate: 2026-10-05\nrepeat: every week\n---\n", path: "Ta Da/tasks/A.md")!
        let b = Item(parsing: "---\ntype: task\nstatus: Doing\ndueDate: 2026-10-06\nrepeat: every week\n---\n", path: "Ta Da/tasks/B.md")!
        let plain = Item(parsing: "---\ntype: task\nstatus: Doing\n---\n", path: "Ta Da/tasks/C.md")!
        let index = VaultIndex([a, b, plain])
        let differing = RepeatWording.statusContext(of: [a, b], index: index, today: today)
        #expect(differing.repeating && differing.move == nil)
        let mixed = RepeatWording.statusContext(of: [a, plain], index: index, today: today)
        #expect(!mixed.repeating && mixed.move == nil)
    }

    @Test func theLogbooksCompletedTodayLeavesOutTasksThatMoveForward() {
        let moving = Item(parsing: "---\ntype: task\nstatus: Done\ncompletedDate: 2026-10-02\ndueDate: 2026-10-02\nrepeat: every day\n---\n", path: "Ta Da/tasks/Moving.md")!
        let ending = Item(parsing: "---\ntype: task\nstatus: Done\ncompletedDate: 2026-10-02\ndueDate: 2026-10-02\nrepeat: every day until 2026-10-02\n---\n", path: "Ta Da/tasks/Ending.md")!
        let plain = Item(parsing: "---\ntype: task\nstatus: Done\ncompletedDate: 2026-10-02\n---\n", path: "Ta Da/tasks/Plain.md")!
        let unreadable = Item(parsing: "---\ntype: task\nstatus: Done\ncompletedDate: 2026-10-02\nrepeat: Weekly · Fri\n---\n", path: "Ta Da/tasks/Unreadable.md")!
        let items = [moving, ending, plain, unreadable]
        let groups = LogbookGroup.groups(items, index: VaultIndex(items), today: today)
        #expect(groups.map(\.kind) == [.logsTonight])
        #expect(groups[0].items.map(\.title) == ["Ending", "Plain", "Unreadable"])
    }
}
