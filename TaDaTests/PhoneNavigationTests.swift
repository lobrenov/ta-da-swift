import Testing
import TaDaCore
@testable import TaDa

/// The iPhone's picking, date-sheet, move-sheet and route rules. They don't touch UIKit, so they run with the Mac's
/// tests.
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

    // MARK: Move and area sheets

    private static let index = VaultIndex([
        ("areas/Home.md", "---\ntype: area\n---\n"),
        ("areas/Work.md", "---\ntype: area\n---\n"),
        ("projects/Garden.md", "---\ntype: project\nstatus: Doing\narea: \"[[Home]]\"\n---\n"),
        ("projects/Old.md", "---\ntype: project\nstatus: Done\narea: \"[[Home]]\"\n---\n"),
        ("projects/Side.md", "---\ntype: project\nstatus: Doing\n---\n"),
        ("projects/Lost.md", "---\ntype: project\nstatus: Doing\narea: \"[[Nowhere]]\"\n---\n"),
        ("tasks/Weed.md", "---\ntype: task\nproject: \"[[Garden]]\"\n---\n"),
        ("tasks/Tidy.md", "---\ntype: task\nproject: \"[[Old]]\"\n---\n"),
        ("tasks/Rent.md", "---\ntype: task\narea: \"[[Home]]\"\n---\n"),
        ("tasks/Loose.md", "---\ntype: task\n---\n"),
        ("tasks/Call.md", "---\ntype: task\narea: \"[[Nowhere]]\"\n---\n"),
    ].compactMap { Item(parsing: $1, path: $0) })

    private func names(_ groups: [[PhoneMoveRow]]) -> [[String]] {
        groups.map { $0.map { row in
            switch row {
            case .none: "none"
            case let .project(progress): progress.project.title
            case let .area(area): "[\(area.title)]"
            case let .createArea(name): "create \(name)"
            }
        } }
    }

    private func items(_ paths: String...) -> [Item] { paths.compactMap { Self.index[$0] } }

    @Test func theMoveSheetListsLooseThenEachAreaWithItsProjects() {
        let groups = PhoneMoveRow.moveGroups(index: Self.index, tasks: items("tasks/Weed.md"), query: "")
        #expect(names(groups) == [["none", "Lost", "Side"], ["[Home]", "Garden"], ["[Work]"]])
        #expect(PhoneMoveRow.currentParent(index: Self.index, files: items("tasks/Weed.md"))??.title == "Garden")
    }

    @Test func theMoveSheetListsTheTasksDoneProjectAndCreatesTheirMissingArea() {
        #expect(names(PhoneMoveRow.moveGroups(index: Self.index, tasks: items("tasks/Tidy.md"), query: ""))[1] == ["[Home]", "Garden", "Old"])
        let groups = PhoneMoveRow.moveGroups(index: Self.index, tasks: items("tasks/Call.md"), query: "")
        #expect(names(groups).first == ["create Nowhere"])
        #expect(PhoneMoveRow.currentParent(index: Self.index, files: items("tasks/Call.md")) == nil)
    }

    @Test func typingKeepsMatchingTitlesAndDropsLooseAndCreate() {
        #expect(names(PhoneMoveRow.moveGroups(index: Self.index, tasks: items("tasks/Call.md"), query: "o")) == [["Lost"], ["[Home]"], ["[Work]"]])
        #expect(names(PhoneMoveRow.moveGroups(index: Self.index, tasks: items("tasks/Weed.md"), query: "gar")) == [["Garden"]])
    }

    @Test func theCurrentParentIsSharedOrLoose() {
        #expect(PhoneMoveRow.currentParent(index: Self.index, files: items("tasks/Loose.md")) == .some(nil))
        #expect(PhoneMoveRow.currentParent(index: Self.index, files: items("tasks/Rent.md"))??.title == "Home")
        #expect(PhoneMoveRow.currentParent(index: Self.index, files: items("tasks/Rent.md", "tasks/Weed.md")) == nil)
    }

    @Test func theAreaSheetListsAreasThenNoArea() {
        #expect(names(PhoneMoveRow.areaGroups(index: Self.index, projects: items("projects/Side.md"), query: "")) == [["[Home]", "[Work]"], ["none"]])
        #expect(names(PhoneMoveRow.areaGroups(index: Self.index, projects: items("projects/Lost.md"), query: "")).first == ["create Nowhere"])
        #expect(names(PhoneMoveRow.areaGroups(index: Self.index, projects: items("projects/Side.md"), query: "wo")) == [["[Work]"]])
    }

    // MARK: Routes

    @Test func aRenameAndADeleteUpdateEveryTabsScreens() {
        let nav = PhoneNavigation()
        nav.stacks = [.projects: [.area("areas/Home.md"), .file("tasks/Rent.md")], .today: [.file("tasks/Weed.md"), .trash]]
        nav.replace(.area("areas/Home.md"), with: .area("areas/House.md"))
        #expect(nav.stacks[.projects] == [.area("areas/House.md"), .file("tasks/Rent.md")])
        nav.dropScreens { $0 != "tasks/Weed.md" }
        #expect(nav.stacks[.projects] == [] && nav.stacks[.today] == [.file("tasks/Weed.md"), .trash])
    }

    @Test func tagScreensShowNoFileAndTheTagSheetIsPerFile() {
        #expect(PhoneRoute.tags.path == nil && PhoneRoute.tag("home").path == nil && PhoneRoute.tag(nil).path == nil)
        #expect(PhoneRoute.tag("home") != PhoneRoute.tag(nil))
        #expect(PhoneSheet.tags(path: "a.md").id != PhoneSheet.tags(path: "b.md").id)
        #expect(PhoneSheet.tags(path: "a.md").id != PhoneSheet.move(paths: ["a.md"]).id)
    }

    @Test func aDeletedFilesScreensGoButTagScreensStay() {
        let nav = PhoneNavigation()
        nav.tab = .other
        nav.push(.tags)
        nav.push(.tag("home"))
        nav.push(.file("tasks/a.md"))
        nav.dropScreens { $0 == "tasks/a.md" }
        #expect(nav.stacks[.other] == [.tags, .tag("home")])
    }
}
