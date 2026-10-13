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
        let menu = ProjectChoice.menu(index: index, tasks: [index[task]!], query: query, naming: naming,
                                      existing: Set(index.projects.map { String($0.path.split(separator: "/").last!) }))
        return (titles(menu.sections), menu.highlight)
    }

    /// A nil title marks the divider between sections, as the menu draws it.
    private func titles<Choice: PopupMenuItem>(_ sections: [PopupMenuSection<Choice>]) -> [String?] {
        sections.filter { !$0.items.isEmpty }.enumerated()
            .flatMap { i, section in (i > 0 && section.label == nil ? [nil] : []) + section.items.map { $0.title as String? } }
    }

    @Test func theMoveMenuListsLooseTasksThenActiveProjectsAndNewProject() {
        let index = index()
        let plan = menu(index, task: "tasks/Plan.md")
        #expect(plan.titles == ["Loose tasks", nil, "Game Jam - Starfall", "Ta Da MVP", nil, "New project…"])
        #expect(plan.highlight == 2, "opens on the current project")

        let old = menu(index, task: "tasks/Old.md")
        #expect(old.titles == ["Loose tasks", nil, "Game Jam - Starfall", "Shipped", "Ta Da MVP", nil, "New project…"],
                "a done project is listed when it's the task's own")
        #expect(old.highlight == 2)
    }

    private func areaIndex() -> VaultIndex {
        let files = [
            ("areas/Home.md", "---\ntype: area\n---\n"),
            ("areas/Work.md", "---\ntype: area\n---\n"),
            ("projects/Garden.md", "---\ntype: project\nstatus: Doing\narea: \"[[Home]]\"\n---\n"),
            ("projects/Side.md", "---\ntype: project\nstatus: Doing\n---\n"),
            ("projects/Lost.md", "---\ntype: project\nstatus: Doing\narea: TTRPGs\n---\n"),
            ("tasks/Rent.md", "---\ntype: task\nstatus: Doing\narea: \"[[Home]]\"\n---\n"),
            ("tasks/2DS.md", "---\ntype: task\nstatus: Doing\narea: TTRPGs\n---\n"),
        ]
        return VaultIndex(files.compactMap { Item(parsing: $0.1, path: $0.0) })
    }

    @Test func theMoveMenuListsEachAreaWithItsProjects() {
        let index = areaIndex()
        let rent = menu(index, task: "tasks/Rent.md")
        #expect(rent.titles == ["Loose tasks", nil, "Lost", "Side", nil, "Home", "Garden", nil, "Work", nil, "New project…"])
        #expect(rent.highlight == 3, "opens on the current area")
        #expect(menu(index, task: "tasks/Rent.md", query: "gard").titles == ["Garden", nil, "New project “gard”"])

        let unresolved = menu(index, task: "tasks/2DS.md")
        #expect(unresolved.titles.first == "Create Area “TTRPGs”")
        #expect(unresolved.highlight == nil, "a task whose area has no file has no current row")
    }

    @Test func theAreaMenuListsAreasThenNoAreaAndNewArea() {
        let index = areaIndex()
        func titles(_ project: String, query: String = "") -> ([String?], Int?) {
            let menu = AreaChoice.menu(index: index, projects: [index[project]!], query: query, naming: false, existing: [])
            return (self.titles(menu.sections), menu.highlight)
        }
        #expect(titles("projects/Garden.md").0 == ["Home", "Work", nil, "No area", "New Area…"])
        #expect(titles("projects/Garden.md").1 == 0)
        #expect(titles("projects/Side.md").1 == 2, "No area is current")
        #expect(titles("projects/Lost.md").0.first == "Create Area “TTRPGs”")
        #expect(titles("projects/Garden.md", query: "wo").0 == ["Work", nil, "New Area “wo”"])
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
        let menu = ProjectChoice.menu(index: index, tasks: [task], query: "Ta Da MVP", naming: false, existing: existing)
        #expect(menu.sections.last?.items.last?.accessibilityValue == "projects/Ta Da MVP 2.md")
        let colon = ProjectChoice.menu(index: index, tasks: [task], query: "Q4: Launch", naming: false, existing: existing)
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

    // MARK: tagMenu

    private func tagMenu(_ query: String = "", keeping: String? = nil) -> (titles: [String?], labels: [String?], highlight: Int?) {
        let files = [
            ("tasks/Weed.md", "---\ntype: task\nstatus: Doing\ntags: [home/garden]\n---\nAsk #people/max\n"),
            ("tasks/Rent.md", "---\ntype: task\nstatus: Doing\ntags: [money, errands]\n---\n#people/dan\n"),
            ("areas/Home.md", "---\ntype: area\ntags: [errands]\n---\n"),
        ]
        let index = VaultIndex(files.compactMap { Item(parsing: $0.1, path: $0.0) })
        let menu = TagChoice.menu(item: index["tasks/Weed.md"]!, tree: index.tagTree(), query: query, keeping: keeping)
        let values = menu.sections.flatMap(\.items).map { $0.accessibilityValue as String? }
        return (titles(menu.sections), values, menu.highlight)
    }

    @Test func tagMenuListsTheFilesTagsThenEveryOtherTagWithCounts() {
        let menu = tagMenu()
        #expect(menu.titles == ["home/garden", "people/max", "errands", "home", "money", "people", "people/dan"])
        #expect(menu.labels == ["In this file", "In the text", "2 files", "1 file", "1 file", "2 files", "1 file"])
        #expect(menu.highlight == 0)
    }

    @Test func typingInTagMenuMatchesSegmentStartsAndOffersCreate() {
        #expect(tagMenu("gar").titles == ["Create #gar", "home/garden"])
        #expect(tagMenu("peo").titles == ["Create #peo", "people/max", "people", "people/dan"])
        #expect(tagMenu("people").titles == ["people/max", "people", "people/dan"], "no Create for a tag in use")
        #expect(tagMenu("home/garden").titles == ["home/garden"])
        #expect(tagMenu("#New Tag").titles == ["Create #New Tag"])
        #expect(tagMenu("people/max").titles == ["people/max"] && tagMenu("people/max").highlight == nil,
                "a tag only in the text can't be picked")
    }

    @Test func tagMenuKeepsTheToggledTagHighlighted() {
        #expect(tagMenu(keeping: "money").highlight == 4, "the tag just toggled stays highlighted after the menu refreshes")
        #expect(tagMenu(keeping: "gone").highlight == 0)
    }
}
