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

@Test func parentWritesOneKeyAndEmptiesTheOther() {
    let both = "---\ntype: task\nstatus: Doing\narea: Personal\nproject: \"[[Old]]\"\n---\n"
    #expect(Parent.set(.area("Work"), in: both) == "---\ntype: task\nstatus: Doing\narea: \"[[Work]]\"\nproject:\n---\n")
    #expect(Parent.set(.project("New"), in: both) == "---\ntype: task\nstatus: Doing\narea:\nproject: \"[[New]]\"\n---\n")
    #expect(Parent.set(nil, in: both) == "---\ntype: task\nstatus: Doing\narea:\nproject:\n---\n")
    let project = "---\ntype: project\nstatus: Doing\n---\n"
    #expect(Parent.set(.area("Work"), in: project) == "---\ntype: project\nstatus: Doing\narea: \"[[Work]]\"\n---\n")
}

@Test func renamingAnAreaRelinksItsProjectsAndTasks() async throws {
    try await withTemporaryFolder { folder in
        try writeFile("---\ntype: area\n---\n", "areas/Home.md", in: folder)
        try writeFile("---\ntype: project\nstatus: Doing\narea: Home\n---\n", "projects/P.md", in: folder)
        try writeFile("---\ntype: task\nstatus: Doing\narea: \"[[home]]\"\n---\n", "tasks/Filed.md", in: folder)
        let other = "---\ntype: task\nstatus: Doing\nproject: \"[[P]]\"\n---\n"
        try writeFile(other, "tasks/In P.md", in: folder)
        let vault = Vault(root: folder)
        let result = try vault.renameArea(at: "areas/Home.md", to: "House", index: await vault.loadIndex())
        #expect(result.path == "areas/House.md" && result.failed.isEmpty)
        #expect(result.relinked.map(\.path) == ["projects/P.md", "tasks/Filed.md"])
        #expect(try vault.read("projects/P.md") == "---\ntype: project\nstatus: Doing\narea: \"[[House]]\"\n---\n")
        #expect(try vault.read("tasks/In P.md") == other)
        let index = await vault.loadIndex()
        #expect(index.allTasks(in: try #require(index["areas/House.md"])).map(\.title) == ["Filed", "In P"])
    }
}
