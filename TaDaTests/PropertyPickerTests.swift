import Foundation
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct PropertyPickerTests {
    private let statuses = ["Not Started", "Doing", "Blocked", "Done"]

    @Test func typingPicksTheItemItsLettersStart() {
        #expect(TypeSelect.match("d", in: statuses, from: 0) == 1)
        #expect(TypeSelect.match("dd", in: statuses, from: 1) == 3, "the same letter again steps to the next match")
        #expect(TypeSelect.match("do", in: statuses, from: 0) == 1)
        #expect(TypeSelect.match("don", in: statuses, from: 1) == 3)
        #expect(TypeSelect.match("N", in: statuses, from: 3) == 0, "ignores case and wraps round")
        #expect(TypeSelect.match("b", in: statuses, from: nil) == 2)
        #expect(TypeSelect.match("x", in: statuses, from: 0) == nil)
        #expect(TypeSelect.match("d", in: [], from: nil) == nil)
    }

    private func index() -> VaultIndex {
        let files = [
            ("projects/Ta Da MVP.md", "---\ntype: project\nstatus: Doing\n---\n"),
            ("projects/Game Jam - Starfall.md", "---\ntype: project\nstatus: Not Started\n---\n"),
            ("projects/Shipped.md", "---\ntype: project\nstatus: Done\n---\n"),
            ("tasks/Plan.md", "---\ntype: task\nstatus: Doing\nproject: \"[[Ta Da MVP]]\"\n---\n"),
            ("tasks/Old.md", "---\ntype: task\nstatus: Done\nproject: \"[[Shipped]]\"\n---\n"),
        ]
        return VaultIndex(files.compactMap { Item(parsing: $0.1, path: $0.0) })
    }

    private func menu(_ index: VaultIndex, task: String, query: String = "", naming: Bool = false)
        -> (titles: [String?], highlight: Int?) {
        let task = index[task]!
        let menu = ProjectChoice.menu(projects: index.activeProjects(), current: index.project(of: task).map { index.progress(of: $0) },
                                      isLoose: task.properties.project == nil, query: query, naming: naming,
                                      existing: Set(index.projects.map { String($0.path.split(separator: "/").last!) }))
        // A nil title marks the divider between sections, as the menu draws it.
        let titles = menu.sections.filter { !$0.items.isEmpty }.enumerated()
            .flatMap { i, section in (i > 0 && section.label == nil ? [nil] : []) + section.items.map { $0.title as String? } }
        return (titles, menu.highlight)
    }

    @Test func theProjectMenuListsActiveProjectsThenNoProjectAndNewProject() {
        let index = index()
        let plan = menu(index, task: "tasks/Plan.md")
        #expect(plan.titles == ["Game Jam - Starfall", "Ta Da MVP", nil, "No project", "New project…"])
        #expect(plan.highlight == 1, "opens on the current project")

        let old = menu(index, task: "tasks/Old.md")
        #expect(old.titles == ["Game Jam - Starfall", "Shipped", "Ta Da MVP", nil, "No project", "New project…"],
                "a done project is listed when it's the task's own")
        #expect(old.highlight == 1)
    }

    @Test func typingFiltersTheProjectsAndOffersOneByThatName() {
        let index = index()
        let meg = menu(index, task: "tasks/Plan.md", query: " meg ")
        #expect(meg.titles == ["Game Jam - Starfall", nil, "New project “meg”"])
        #expect(meg.highlight == 0, "the first match, as the current project doesn't match")

        let ta = menu(index, task: "tasks/Plan.md", query: "ta")
        #expect(ta.titles == ["Ta Da MVP", nil, "New project “ta”"])
        #expect(ta.highlight == 0, "the current project, which matches")

        let none = menu(index, task: "tasks/Plan.md", query: "launch")
        #expect(none.titles == ["New project “launch”"])
        #expect(none.highlight == 0)
    }

    @Test func newProjectShowsTheFileItWouldMake() {
        let index = index()
        let task = index["tasks/Plan.md"]!
        let existing = Set(index.projects.map { String($0.path.split(separator: "/").last!) })
        let menu = ProjectChoice.menu(projects: index.activeProjects(), current: nil, isLoose: task.properties.project == nil,
                                      query: "Ta Da MVP", naming: false, existing: existing)
        #expect(menu.sections.last?.items.last?.accessibilityValue == "projects/Ta Da MVP 2.md")
        let colon = ProjectChoice.menu(projects: [], current: nil, isLoose: true, query: "Q4: Launch", naming: false, existing: existing)
        #expect(colon.sections.last?.items.last?.accessibilityValue == "projects/Q4 - Launch.md")
    }

    @Test func namingANewProjectLeavesOnlyTheNewProjectRow() {
        let index = index()
        #expect(menu(index, task: "tasks/Plan.md", naming: true).titles == ["New project…"])
        let named = menu(index, task: "tasks/Plan.md", query: "Ta", naming: true)
        #expect(named.titles == ["New project “Ta”"])
        #expect(named.highlight == 0)
    }

    private var mondayFirst: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_AU")
        calendar.firstWeekday = 2
        return calendar
    }

    @Test func aMonthStartsOnTheLocalesFirstWeekday() {
        let october = MonthGrid(LocalDate("2026-10-14")!, calendar: mondayFirst)
        #expect(october.weekdaySymbols.first == "M")
        #expect(october.days.prefix(4) == [nil, nil, nil, LocalDate("2026-10-01")!], "1 October 2026 is a Thursday")
        #expect(october.days.last == LocalDate("2026-10-31")!)
        #expect(october.weeks == 5)

        var sundayFirst = mondayFirst
        sundayFirst.firstWeekday = 1
        #expect(MonthGrid(LocalDate("2026-10-01")!, calendar: sundayFirst).days.firstIndex(of: LocalDate("2026-10-01")!) == 4)
        #expect(MonthGrid(LocalDate("2027-02-01")!, calendar: mondayFirst).weeks == 4, "February 2027 starts on a Monday")
    }

    @Test func thisWeekendIsTheComingSaturdayOrToday() {
        #expect(CalendarPickerModel.thisWeekend(after: LocalDate("2026-10-02")!) == LocalDate("2026-10-03")!)
        #expect(CalendarPickerModel.thisWeekend(after: LocalDate("2026-10-03")!) == LocalDate("2026-10-03")!)
        #expect(CalendarPickerModel.thisWeekend(after: LocalDate("2026-10-04")!) == LocalDate("2026-10-04")!)
        #expect(CalendarPickerModel.thisWeekend(after: LocalDate("2026-10-05")!) == LocalDate("2026-10-10")!)
    }

    @Test func nextWeekIsTheFirstDayOfTheFollowingWeek() {
        #expect(CalendarPickerModel.nextWeek(after: LocalDate("2026-10-02")!, calendar: mondayFirst) == LocalDate("2026-10-05")!)
        #expect(CalendarPickerModel.nextWeek(after: LocalDate("2026-10-05")!, calendar: mondayFirst) == LocalDate("2026-10-12")!)
        #expect(CalendarPickerModel.nextWeek(after: LocalDate("2026-10-04")!, calendar: mondayFirst) == LocalDate("2026-10-05")!)
        var sundayFirst = mondayFirst
        sundayFirst.firstWeekday = 1
        #expect(CalendarPickerModel.nextWeek(after: LocalDate("2026-10-02")!, calendar: sundayFirst) == LocalDate("2026-10-04")!)
    }

    @Test func theCursorMovesByDayWeekAndMonth() {
        let model = CalendarPickerModel()
        var monthChanges = 0
        model.onMonthChange = { monthChanges += 1 }
        model.cursor = LocalDate("2026-10-29")!
        model.move(days: 1)
        model.move(days: -7)
        #expect(model.cursor == LocalDate("2026-10-23")! && monthChanges == 0)
        model.move(days: 9)
        #expect(model.cursor == LocalDate("2026-11-01")! && model.month == LocalDate("2026-11-01")! && monthChanges == 1)

        model.cursor = LocalDate("2027-01-31")!
        model.move(months: 1)
        #expect(model.cursor == LocalDate("2027-02-28")!, "keeps the day, or the month's last")
        model.move(months: -2)
        #expect(model.cursor == LocalDate("2026-12-28")! && monthChanges == 3)
    }
}
