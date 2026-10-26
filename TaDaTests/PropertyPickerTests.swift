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
            ("Ta Da/projects/Ta Da MVP.md", "---\ntype: project\nstatus: Doing\n---\n"),
            ("Ta Da/projects/Game Jam - Starfall.md", "---\ntype: project\nstatus: Not Started\n---\n"),
            ("Ta Da/projects/Shipped.md", "---\ntype: project\nstatus: Done\n---\n"),
            ("Ta Da/tasks/Plan.md", "---\ntype: task\nstatus: Doing\nproject: \"[[Ta Da MVP]]\"\n---\n"),
            ("Ta Da/tasks/Old.md", "---\ntype: task\nstatus: Done\nproject: \"[[Shipped]]\"\n---\n"),
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
        let plan = menu(index, task: "Ta Da/tasks/Plan.md")
        #expect(plan.titles == ["Loose tasks", nil, "Game Jam - Starfall", "Ta Da MVP", nil, "New project…"])
        #expect(plan.highlight == 2, "opens on the current project")

        let old = menu(index, task: "Ta Da/tasks/Old.md")
        #expect(old.titles == ["Loose tasks", nil, "Game Jam - Starfall", "Shipped", "Ta Da MVP", nil, "New project…"],
                "a done project is listed when it's the task's own")
        #expect(old.highlight == 2)
    }

    private func areaIndex() -> VaultIndex {
        let files = [
            ("Ta Da/areas/Home.md", "---\ntype: area\n---\n"),
            ("Ta Da/areas/Work.md", "---\ntype: area\n---\n"),
            ("Ta Da/projects/Garden.md", "---\ntype: project\nstatus: Doing\narea: \"[[Home]]\"\n---\n"),
            ("Ta Da/projects/Side.md", "---\ntype: project\nstatus: Doing\n---\n"),
            ("Ta Da/projects/Lost.md", "---\ntype: project\nstatus: Doing\narea: TTRPGs\n---\n"),
            ("Ta Da/tasks/Rent.md", "---\ntype: task\nstatus: Doing\narea: \"[[Home]]\"\n---\n"),
            ("Ta Da/tasks/2DS.md", "---\ntype: task\nstatus: Doing\narea: TTRPGs\n---\n"),
        ]
        return VaultIndex(files.compactMap { Item(parsing: $0.1, path: $0.0) })
    }

    @Test func theMoveMenuListsEachAreaWithItsProjects() {
        let index = areaIndex()
        let rent = menu(index, task: "Ta Da/tasks/Rent.md")
        #expect(rent.titles == ["Loose tasks", nil, "Lost", "Side", nil, "Home", "Garden", nil, "Work", nil, "New project…"])
        #expect(rent.highlight == 3, "opens on the current area")
        #expect(menu(index, task: "Ta Da/tasks/Rent.md", query: "gard").titles == ["Garden", nil, "New project “gard”"])

        let unresolved = menu(index, task: "Ta Da/tasks/2DS.md")
        #expect(unresolved.titles.first == "Create Area “TTRPGs”")
        #expect(unresolved.highlight == nil, "a task whose area has no file has no current row")
    }

    @Test func theAreaMenuListsAreasThenNoAreaAndNewArea() {
        let index = areaIndex()
        func titles(_ project: String, query: String = "") -> ([String?], Int?) {
            let menu = AreaChoice.menu(index: index, projects: [index[project]!], query: query, naming: false, existing: [])
            return (self.titles(menu.sections), menu.highlight)
        }
        #expect(titles("Ta Da/projects/Garden.md").0 == ["Home", "Work", nil, "No area", "New Area…"])
        #expect(titles("Ta Da/projects/Garden.md").1 == 0)
        #expect(titles("Ta Da/projects/Side.md").1 == 2, "No area is current")
        #expect(titles("Ta Da/projects/Lost.md").0.first == "Create Area “TTRPGs”")
        #expect(titles("Ta Da/projects/Garden.md", query: "wo").0 == ["Work", nil, "New Area “wo”"])
    }

    @Test func typingFiltersTheProjectsAndOffersOneByThatName() {
        let index = index()
        let meg = menu(index, task: "Ta Da/tasks/Plan.md", query: " meg ")
        #expect(meg.titles == ["Game Jam - Starfall", nil, "New project “meg”"])
        #expect(meg.highlight == 0, "the first match, as the current project doesn't match")

        let ta = menu(index, task: "Ta Da/tasks/Plan.md", query: "ta")
        #expect(ta.titles == ["Ta Da MVP", nil, "New project “ta”"])
        #expect(ta.highlight == 0, "the current project, which matches")

        let none = menu(index, task: "Ta Da/tasks/Plan.md", query: "launch")
        #expect(none.titles == ["New project “launch”"])
        #expect(none.highlight == 0)
    }

    @Test func newProjectShowsTheFileItWouldMake() {
        let index = index()
        let task = index["Ta Da/tasks/Plan.md"]!
        let existing = Set(index.projects.map { String($0.path.split(separator: "/").last!) })
        let menu = ProjectChoice.menu(index: index, tasks: [task], query: "Ta Da MVP", naming: false, existing: existing)
        #expect(menu.sections.last?.items.last?.accessibilityValue == "Ta Da/projects/Ta Da MVP 2.md")
        let colon = ProjectChoice.menu(index: index, tasks: [task], query: "Q4: Launch", naming: false, existing: existing)
        #expect(colon.sections.last?.items.last?.accessibilityValue == "Ta Da/projects/Q4 - Launch.md")
    }

    @Test func namingANewProjectLeavesOnlyTheNewProjectRow() {
        let index = index()
        #expect(menu(index, task: "Ta Da/tasks/Plan.md", naming: true).titles == ["New project…"])
        let named = menu(index, task: "Ta Da/tasks/Plan.md", query: "Ta", naming: true)
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

    @Test func theCursorMovesByMonth() {
        let model = CalendarPickerModel()
        var monthChanges = 0
        model.onMonthChange = { monthChanges += 1 }
        model.cursor = LocalDate("2027-01-31")!
        model.move(months: 1)
        #expect(model.cursor == LocalDate("2027-02-28")! && model.month == LocalDate("2027-02-01")!, "keeps the day, or the month's last")
        model.move(months: -2)
        #expect(model.cursor == LocalDate("2026-12-28")! && monthChanges == 2)
    }

    @Test func aTypedDateMovesTheCursorAndANonMatchKeepsIt() {
        let model = CalendarPickerModel()
        var monthChanges = 0
        model.onMonthChange = { monthChanges += 1 }
        model.today = LocalDate("2026-10-13")!
        model.cursor = model.today
        model.order = .dayMonth
        model.phrase = "25/12"
        #expect(model.match == LocalDate("2026-12-25")! && model.cursor == LocalDate("2026-12-25")! && monthChanges == 1)
        model.phrase = "25/12x"
        #expect(model.match == nil && model.cursor == LocalDate("2026-12-25")!, "no match keeps the cursor")
        model.phrase = "fri"
        #expect(model.cursor == LocalDate("2026-10-16")! && monthChanges == 2)
        model.order = .monthDay
        model.phrase = "5/12"
        #expect(model.cursor == LocalDate("2027-05-12")!)
        #expect(model.note == LocalDate("2027-05-12")!.formatted(.weekdayDayMonth))
        model.phrase = ""
        #expect(model.match == nil && model.note == nil && model.cursor == model.today, "back to today")
        model.selected = LocalDate("2026-11-02")!
        model.phrase = "xyz"
        #expect(model.note == "No match · \(model.today.formatted(.weekdayDayMonth))", "the day ↵ sets")
        model.phrase = ""
        #expect(model.cursor == LocalDate("2026-11-02")!, "back to the date set")
    }

    @Test func theMonthButtonsMoveTheTypedDay() {
        let model = CalendarPickerModel()
        model.today = LocalDate("2026-10-13")!
        model.phrase = "fri"
        model.move(months: 1)
        #expect(model.match == LocalDate("2026-11-16")! && model.cursor == LocalDate("2026-11-16")!)
        model.phrase = "xyz"
        model.move(months: 1)
        #expect(model.match == LocalDate("2026-12-16")!)
        model.phrase = ""
        model.move(months: 1)
        #expect(model.match == nil)
    }

    // MARK: Repeat

    private final class Writes {
        var rules: [RepeatRule?] = []
        var closing: [Bool] = []
        var dates: [LocalDate?] = []
    }

    /// A due date menu on tasks with `files`' text, today Monday 26 October 2026.
    private func repeatMenu(_ files: [String], today: String = "2026-10-26") -> (CalendarPickerModel, Writes) {
        let items = files.enumerated().compactMap { Item(parsing: $0.element, path: "Ta Da/tasks/T\($0.offset).md") }
        let writes = Writes()
        let model = CalendarPickerModel()
        model.today = LocalDate(today)!
        model.selected = Set(items.map(\.properties.dueDate)).count == 1 ? items[0].properties.dueDate : nil
        model.cursor = model.selected ?? model.today
        model.configure(CalendarPickerModel.Repeating(items: items, index: VaultIndex(items)) { rule, closing in
            writes.rules.append(rule)
            writes.closing.append(closing)
        })
        model.set = { writes.dates.append($0) }
        return (model, writes)
    }

    private let weekly = "---\ntype: task\ndueDate: 2026-11-02\nrepeat: every week on Mon\n---\n"
    private let plain = "---\ntype: task\ndueDate: 2026-11-02\n---\n"
    private let undated = "---\ntype: task\n---\n"

    @Test func aPhraseStartingWithEveryIsARuleAndLeavesTheCursor() throws {
        let (model, _) = repeatMenu([plain])
        model.phrase = "every 2 weeks on mon"
        #expect(model.typedRule?.phrase == "every 2 weeks on Mon" && model.match == nil)
        #expect(model.cursor == LocalDate("2026-11-02")!, "stays on the due date")
        #expect(model.note == "From \(LocalDate("2026-11-02")!.formatted(.weekdayDayMonth))")
        #expect(model.displayedRule == model.typedRule)
        model.phrase = "every 2 w"
        #expect(model.typedRule == nil && model.note == "No match")
        model.phrase = "fri"
        #expect(model.typedRule == nil && model.match == LocalDate("2026-10-30")! && model.cursor == LocalDate("2026-10-30")!, "a date still moves the cursor")
        model.phrase = ""
        #expect(model.cursor == LocalDate("2026-11-02")!)
    }

    @Test func aMenuWithoutARepeatSectionReadsEveryAsADate() {
        let model = CalendarPickerModel()
        model.today = LocalDate("2026-10-26")!
        model.cursor = model.today
        model.phrase = "every mon"
        #expect(model.typedRule == nil && model.match == nil && model.note == "No match · \(model.today.formatted(.weekdayDayMonth))")
        model.configure(nil)
        #expect(!model.showsRepeat)
    }

    @Test func enterSetsAReadableRuleAndNothingOtherwise() {
        let (model, writes) = repeatMenu([plain])
        model.phrase = "every 2 w"
        model.confirm()
        #expect(writes.rules.isEmpty && writes.dates.isEmpty)
        model.phrase = "Every 2 weeks on Mon"
        model.confirm()
        #expect(writes.rules == [RepeatRule.parse("every 2 weeks on Mon")] && writes.closing == [true] && writes.dates.isEmpty)
        model.phrase = ""
        model.confirm()
        #expect(writes.dates == [LocalDate("2026-11-02")!], "a date is set as before")
    }

    @Test func aRuleOnATaskWithNoDueDateStartsOnItsFirstDate() {
        let (model, writes) = repeatMenu([undated])
        model.phrase = "every week on wed"
        #expect(model.note == "From \(LocalDate("2026-10-28")!.formatted(.weekdayDayMonth))")
        #expect(model.occurrenceDays(in: LocalDate("2026-10-01")!).contains(LocalDate("2026-10-28")!), "the first date is marked")
        model.phrase = "every day until 2026-10-20"
        #expect(model.typedRule == nil && model.note == "No match", "ended before it starts")
        model.confirm()
        #expect(writes.rules.isEmpty)
    }

    @Test func theMonthPreviewsComingOccurrencesOfTheTypedOrSetRule() {
        let (model, _) = repeatMenu([plain])
        let november = LocalDate("2026-11-01")!
        #expect(model.occurrenceDays(in: november).isEmpty, "no rule")
        model.phrase = "every 2 weeks on mon"
        #expect(model.occurrenceDays(in: november) == [LocalDate("2026-11-16")!, LocalDate("2026-11-30")!] as Set)
        let (set, _) = repeatMenu([weekly])
        #expect(set.occurrenceDays(in: november) == Set(["2026-11-09", "2026-11-16", "2026-11-23", "2026-11-30"].map { LocalDate($0)! }))
        set.phrase = "every 2 weeks on mon"
        #expect(set.displayedRule?.interval == 2 && set.current?.interval == 1, "the typed rule previews over the set one")
        let (deadline, _) = repeatMenu([weekly])
        deadline.configure(nil)
        #expect(deadline.occurrenceDays(in: november).isEmpty)
    }

    @Test func stopAndWhenDoneWriteTheRule() throws {
        let (model, writes) = repeatMenu([weekly])
        model.setWhenDone(true)
        #expect(writes.rules == [RepeatRule.parse("every week on Mon when done")] && writes.closing == [false])
        #expect(model.current?.whenDone == true)
        model.setWhenDone(true)
        #expect(writes.rules.count == 1, "no change, no write")
        model.setWhenDone(false)
        #expect(writes.rules.last == RepeatRule.parse("every week on Mon") && model.current?.whenDone == false)
        model.stopRepeating()
        #expect(writes.rules.count == 3 && writes.rules[2] == nil && writes.closing[2])
        let (none, noWrites) = repeatMenu([plain])
        none.setWhenDone(true)
        none.showEnds()
        #expect(noWrites.rules.isEmpty && !none.isEnds, "nothing to change without a rule")
    }

    @Test func endsPicksTheLastDay() throws {
        let (model, writes) = repeatMenu([weekly])
        let december = LocalDate("2026-12-01")!
        model.showEnds()
        #expect(model.isEnds && model.shownDate == nil && model.cursor == model.today)
        model.phrase = "20 dec"
        #expect(model.match == LocalDate("2026-12-20")! && model.cursor == LocalDate("2026-12-20")!)
        #expect(model.note == LocalDate("2026-12-20")!.formatted(.weekdayDayMonth))
        #expect(model.occurrenceDays(in: december) == [LocalDate("2026-12-07")!, LocalDate("2026-12-14")!] as Set, "stops at the end typed")
        #expect(model.endsSummary == "Every week on Monday until \(LocalDate("2026-12-20")!.formatted(.weekdayDayMonth))")
        model.confirm()
        #expect(writes.rules == [RepeatRule.parse("every week on Mon until 2026-12-20")] && writes.closing == [true])
        model.pick(LocalDate("2026-12-31"))
        #expect(writes.rules.last == RepeatRule.parse("every week on Mon until 2026-12-31"))
        model.pick(nil)
        #expect(writes.rules.last == RepeatRule.parse("every week on Mon"), "Never")
        model.phrase = "every day"
        #expect(model.typedRule == nil, "a rule isn't read in the Ends view")
        model.hideEnds()
        #expect(!model.isEnds && model.cursor == LocalDate("2026-11-02")!)
    }

    @Test func endsShowsTheSetEndOnItsDay() {
        let (model, _) = repeatMenu(["---\ntype: task\ndueDate: 2026-11-02\nrepeat: every week on Mon until 2026-12-20\n---\n"])
        model.showEnds()
        #expect(model.shownDate == LocalDate("2026-12-20")! && model.cursor == LocalDate("2026-12-20")!)
        model.hideEnds()
        #expect(model.shownDate == LocalDate("2026-11-02")!)
    }

    @Test func pickedFilesShowARuleOnlyWhenTheyAllShareIt() {
        #expect(repeatMenu([weekly, weekly]).0.current == RepeatRule.parse("every week on Mon"))
        #expect(repeatMenu([weekly, plain]).0.current == nil)
        #expect(repeatMenu([weekly, "---\ntype: task\nrepeat: every day\n---\n"]).0.current == nil)
        let (model, writes) = repeatMenu([weekly, plain])
        model.phrase = "every month"
        #expect(model.typedRule != nil)
        model.confirm()
        #expect(writes.rules == [RepeatRule.parse("every month")], "one rule for every file")
    }

    // MARK: tagMenu

    private func tagMenu(_ query: String = "", keeping: String? = nil) -> (titles: [String?], labels: [String?], highlight: Int?) {
        let files = [
            ("Ta Da/tasks/Weed.md", "---\ntype: task\nstatus: Doing\ntags: [home/garden]\n---\nAsk #people/max\n"),
            ("Ta Da/tasks/Rent.md", "---\ntype: task\nstatus: Doing\ntags: [money, errands]\n---\n#people/dan\n"),
            ("Ta Da/areas/Home.md", "---\ntype: area\ntags: [errands]\n---\n"),
        ]
        let index = VaultIndex(files.compactMap { Item(parsing: $0.1, path: $0.0) })
        let menu = TagChoice.menu(item: index["Ta Da/tasks/Weed.md"]!, tree: index.tagTree(), query: query, keeping: keeping)
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
