import Testing
@testable import TaDaCore

private let today = LocalDate("2026-10-02")!

private func load() async -> VaultIndex {
    await Vault(root: areaVault).loadIndex()
}

private extension VaultIndex {
    func titled(_ title: String) -> Item { items(titled: title).first! }
}

@Test func areasResolveParents() async {
    let index = await load()
    #expect(index.areas.map(\.title).sorted() == ["Empty", "Personal", "Work"])
    #expect(index.parent(of: index.titled("Pay rent"))?.title == "Personal")
    #expect(index.parent(of: index.titled("Both keys"))?.title == "Ta Da")
    #expect(index.area(of: index.titled("Both keys"))?.title == "Personal", "through its project")
    #expect(index.area(of: index.titled("Run payroll"))?.title == "Work", "plain area value on the project")
    #expect(index.parent(of: index.titled("Call Nowhere")) == nil)
    #expect(index.parent(of: index.titled("Lost")) == nil)
    #expect(index.parent(of: index.titled("Personal")) == nil)
}

@Test func areasListTheirFiles() async {
    let index = await load()
    let personal = index.titled("Personal")
    #expect(index.tasks(in: personal).map(\.title) == ["Book a dentist", "Pay rent"])
    #expect(index.projects(in: personal).map(\.title) == ["Garden", "Ta Da"])
    #expect(index.allTasks(in: personal).map(\.title) == ["Book a dentist", "Pay rent", "Water the beds", "Both keys", "Build the sidebar"])
    #expect(index.tasks(in: index.titled("Work")).isEmpty, "Both keys names Work but its project wins")
}

@Test func areasWarnOnBothKeysAndUnresolvedLinks() async {
    let index = await load()
    #expect(index.warnings(for: index.titled("Both keys")) == [.areaIgnored("Work")])
    #expect(index.warnings(for: index.titled("Lost")) == [.unresolvedArea("Nowhere")])
    #expect(index.warnings(for: index.titled("Call Nowhere")) == [.unresolvedArea("Nowhere")])
    let others = index.items.values.filter { !["Both keys", "Lost", "Call Nowhere"].contains($0.title) }
    for item in others { #expect(index.warnings(for: item).isEmpty, "\(item.path)") }
}

@Test func areasSetLooseAndTheSidebar() async {
    let index = await load()
    #expect(index.loose().map(\.title) == ["Buy milk", "Call Nowhere"])
    #expect(index.looseProjects().map(\.project.title) == ["Lost", "Side quest"])
    #expect(index.areaProjects().map { "\($0.area.title): \($0.projects.map(\.project.title))" } == [
        "Empty: []", "Personal: [\"Ta Da\"]", "Work: [\"Payroll\"]",
    ])
}

@Test func todayGroupsByArea() async {
    let index = await load()
    let groups = index.grouped(index.today(today))
    #expect(groups.map { "\($0.parent?.title ?? "-"): \($0.tasks.map(\.title).joined(separator: ", "))" } == [
        "-: Buy milk, Call Nowhere",
        "Lost: Find the map",
        "Side quest: Plan the quest",
        "Personal: Pay rent",
        "Garden: Water the beds",
        "Ta Da: Both keys, Build the sidebar",
        "Work: ",
        "Payroll: Run payroll",
    ])
}

@Test func searchMatchesAreaTitles() async {
    let index = await load()
    #expect(index.search("payroll work").map(\.title) == ["Payroll", "Run payroll"])
    #expect(index.search("personal").first?.title == "Personal")
    #expect(index.search("personal").map(\.title).contains("Both keys"))
    #expect(index.search("nowhere").map(\.title) == ["Call Nowhere", "Lost"])
}

@Test func areaIndexPatches() async {
    var index = await load()
    let personal = index.titled("Personal")
    index.update(makeItem("tasks/Pay rent.md", "type: task\nstatus: Not Started\narea: \"[[Work]]\""))
    #expect(index.tasks(in: personal).map(\.title) == ["Book a dentist"])
    #expect(index.tasks(in: index.titled("Work")).map(\.title) == ["Pay rent"])
    index.remove("areas/Work.md")
    #expect(index.isLoose(index.titled("Pay rent")))
    #expect(index.looseProjects().map(\.project.title) == ["Lost", "Payroll", "Side quest"])
}
