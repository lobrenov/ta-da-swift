import Foundation
import Testing
@testable import TaDaCore

private let today = LocalDate("2026-10-02")!
private func task(_ status: String, completed: String? = nil, project: String? = nil) -> String {
    "---\ntype: task\nstatus: \(status)\n" + (completed.map { "completedDate: \($0)\n" } ?? "")
        + (project.map { "project: \"[[\($0)]]\"\n" } ?? "") + "---\n"
}
private func project(_ status: String, completed: String? = nil) -> String {
    "---\ntype: project\nstatus: \(status)\n" + (completed.map { "completedDate: \($0)\n" } ?? "") + "---\n"
}

@Test func logbookFoldersAreByMonth() {
    #expect(Vault.logbookFolder(for: LocalDate("2026-09-30")!) == "Ta Da/Logbook/2026-09")
}

@Test func filesToLogAreClosedBeforeTheDayAndWaitForOpenTasks() {
    let index = VaultIndex([
        makeItem("Ta Da/tasks/Done yesterday.md", "type: task\nstatus: Done\ncompletedDate: 2026-10-01"),
        makeItem("Ta Da/tasks/Cancelled yesterday.md", "type: task\nstatus: Cancelled\ncompletedDate: 2026-10-01"),
        makeItem("Ta Da/tasks/Done today.md", "type: task\nstatus: Done\ncompletedDate: 2026-10-02"),
        makeItem("Ta Da/tasks/Done undated.md", "type: task\nstatus: Done"),
        makeItem("Ta Da/tasks/Open.md", "type: task\nstatus: Doing\ncompletedDate: 2026-09-01"),
        makeItem("Ta Da/areas/Home.md", "type: area"),
        makeItem("Ta Da/projects/Shipped.md", "type: project\nstatus: Done\ncompletedDate: 2026-09-30"),
        makeItem("Ta Da/tasks/Shipped task.md", "type: task\nstatus: Done\ncompletedDate: 2026-09-29\nproject: \"[[Shipped]]\""),
        makeItem("Ta Da/projects/Waiting.md", "type: project\nstatus: Done\ncompletedDate: 2026-09-30"),
        makeItem("Ta Da/tasks/Waiting open.md", "type: task\nstatus: Doing\nproject: \"[[Waiting]]\""),
        makeItem("Ta Da/tasks/Waiting done.md", "type: task\nstatus: Done\ncompletedDate: 2026-09-29\nproject: \"[[Waiting]]\""),
        makeItem("Ta Da/Logbook/2026-09/Logged.md", "type: task\nstatus: Done\ncompletedDate: 2026-09-01"),
        makeItem("Ta Da/Logbook/2026-09/Reopened.md", "type: task\nstatus: Not Started"),
    ])
    #expect(index.filesToLog(completedBefore: today).map(\.title)
        == ["Cancelled yesterday", "Done undated", "Done yesterday", "Shipped", "Shipped task"])
    #expect(index.filesToLog(completedBefore: nil).map(\.title)
        == ["Cancelled yesterday", "Done today", "Done undated", "Done yesterday", "Shipped", "Shipped task"])
    #expect(index.reopenedLogged.map(\.title) == ["Reopened"])
}

@Test func loggingMovesFilesIntoTheirMonthAndTheyStillLoad() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(project("Done", completed: "2026-09-30"), "Ta Da/projects/Kombi.md", in: folder)
        try writeFile(task("Cancelled", completed: "2026-10-01", project: "Kombi"), "Ta Da/tasks/List it.md", in: folder)
        try writeFile(task("Done"), "deep/Undated.md", in: folder)
        try writeFile(task("Done", completed: "2026-10-01"), "Ta Da/Logbook/2026-10/Undated.md", in: folder)
        let index = await vault.loadIndex()
        #expect(index["Ta Da/Logbook/2026-10/Undated.md"]?.isLogged == true, "a scan reads the Logbook")
        let moved = try vault.log(["Ta Da/projects/Kombi.md", "Ta Da/tasks/List it.md", "deep/Undated.md"], index: index, today: today)
        #expect(moved == ["Ta Da/projects/Kombi.md": "Ta Da/Logbook/2026-09/Kombi.md", "Ta Da/tasks/List it.md": "Ta Da/Logbook/2026-10/List it.md",
                          "deep/Undated.md": "Ta Da/Logbook/2026-10/Undated 2.md"])
        let reloaded = await vault.loadIndex()
        #expect(Set(reloaded.logged.map(\.path)) == Set(moved.values).union(["Ta Da/Logbook/2026-10/Undated.md"]))
        #expect(reloaded.items.count == 4)
        #expect(reloaded.parent(of: reloaded["Ta Da/Logbook/2026-10/List it.md"]!)?.path == "Ta Da/Logbook/2026-09/Kombi.md")
        #expect(vault.path(of: folder.appending(path: "Ta Da/Logbook/2026-09/Kombi.md")) == "Ta Da/Logbook/2026-09/Kombi.md")
        #expect(vault.path(of: folder.appending(path: ".trash/Kombi.md")) == nil)
    }
}

@Test func loggingAProjectUnderATakenNameRelinksItsTasks() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(project("Done", completed: "2026-10-01"), "Ta Da/projects/Timesheet.md", in: folder)
        try writeFile(task("Done", completed: "2026-10-01", project: "Timesheet"), "Ta Da/tasks/Fill it in.md", in: folder)
        try writeFile(project("Done", completed: "2026-10-01"), "Ta Da/Logbook/2026-10/Timesheet.md", in: folder)
        let index = await vault.loadIndex()
        let moved = try vault.log(["Ta Da/projects/Timesheet.md", "Ta Da/tasks/Fill it in.md"], index: index, today: today)
        #expect(moved["Ta Da/projects/Timesheet.md"] == "Ta Da/Logbook/2026-10/Timesheet 2.md")
        let text = try vault.read("Ta Da/Logbook/2026-10/Fill it in.md")
        #expect(text.contains("project: \"[[Timesheet 2]]\""))
    }
}

@Test func reopeningATaskBringsBackItsLoggedProjectAsDoing() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(project("Done", completed: "2026-09-30"), "Ta Da/Logbook/2026-09/Kombi.md", in: folder)
        try writeFile(task("Not Started", project: "Kombi"), "Ta Da/Logbook/2026-09/Photos.md", in: folder)
        try writeFile(task("Done", completed: "2026-09-30", project: "Kombi"), "Ta Da/Logbook/2026-09/Listing.md", in: folder)
        try writeFile(task("Doing"), "Ta Da/tasks/Photos.md", in: folder)
        let index = await vault.loadIndex()
        let moved = try vault.unlog(["Ta Da/Logbook/2026-09/Photos.md"], index: index, today: today)
        #expect(moved == ["Ta Da/Logbook/2026-09/Kombi.md": "Ta Da/projects/Kombi.md", "Ta Da/Logbook/2026-09/Photos.md": "Ta Da/tasks/Photos 2.md"])
        let reloaded = await vault.loadIndex()
        let kombi = try #require(reloaded["Ta Da/projects/Kombi.md"])
        #expect(kombi.properties.status == .doing && kombi.properties.completedDate == nil)
        #expect(reloaded.tasks(in: kombi).map(\.title) == ["Photos 2"])
        #expect(reloaded.tasks(in: kombi, includingLogged: true).map(\.title) == ["Listing", "Photos 2"], "its other tasks stay logged")
    }
}

@Test func reopeningAProjectLeavesItsTasksLogged() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(project("Doing"), "Ta Da/Logbook/2026-09/Kombi.md", in: folder)
        try writeFile(task("Done", completed: "2026-09-30", project: "Kombi"), "Ta Da/Logbook/2026-09/Listing.md", in: folder)
        let index = await vault.loadIndex()
        #expect(try vault.unlog(["Ta Da/Logbook/2026-09/Kombi.md"], index: index, today: today) == ["Ta Da/Logbook/2026-09/Kombi.md": "Ta Da/projects/Kombi.md"])
        #expect(try vault.read("Ta Da/projects/Kombi.md") == project("Doing"), "its own status is the caller's")
    }
}

@Test func trashingAProjectLeavesItsLoggedTasks() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(project("Doing"), "Ta Da/projects/Kombi.md", in: folder)
        try writeFile(task("Doing", project: "Kombi"), "Ta Da/tasks/Open.md", in: folder)
        try writeFile(task("Done", completed: "2026-09-30", project: "Kombi"), "Ta Da/Logbook/2026-09/Listing.md", in: folder)
        let index = await vault.loadIndex()
        #expect(try vault.moveToTrash("Ta Da/projects/Kombi.md", index: index) == ["Ta Da/projects/Kombi.md", "Ta Da/tasks/Open.md"])
        #expect(vault.markdownPaths() == ["Ta Da/Logbook/2026-09/Listing.md"])
    }
}

@Test func loggingGoesOnPastAFileThatCantMove() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(project("Done", completed: "2026-10-01"), "Ta Da/projects/Timesheet.md", in: folder)
        try writeFile(task("Done", completed: "2026-10-01", project: "Timesheet"), "Ta Da/tasks/Fill it in.md", in: folder)
        try writeFile(task("Done", completed: "2026-10-01"), "Ta Da/tasks/Gone.md", in: folder)
        try writeFile(project("Done", completed: "2026-10-01"), "Ta Da/Logbook/2026-10/Timesheet.md", in: folder)
        let index = await vault.loadIndex()
        try FileManager.default.removeItem(at: folder.appending(path: "Ta Da/tasks/Gone.md"))
        let moved = try vault.log(["Ta Da/tasks/Fill it in.md", "Ta Da/tasks/Gone.md", "Ta Da/projects/Timesheet.md"], index: index, today: today)
        #expect(moved == ["Ta Da/tasks/Fill it in.md": "Ta Da/Logbook/2026-10/Fill it in.md",
                          "Ta Da/projects/Timesheet.md": "Ta Da/Logbook/2026-10/Timesheet 2.md"])
        #expect(try vault.read("Ta Da/Logbook/2026-10/Fill it in.md").contains("project: \"[[Timesheet 2]]\""))
    }
}

@Test func loggingSkipsFilesAlreadyMovedByAnotherDevice() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(task("Done", completed: "2026-10-01"), "Ta Da/tasks/Clean the house.md", in: folder)
        let index = await vault.loadIndex()
        try FileManager.default.createDirectory(at: folder.appending(path: "Ta Da/Logbook/2026-10"), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: folder.appending(path: "Ta Da/tasks/Clean the house.md"),
                                         to: folder.appending(path: "Ta Da/Logbook/2026-10/Clean the house.md"))
        let moved = try vault.log(["Ta Da/tasks/Clean the house.md"], index: index, today: today)
        #expect(moved.isEmpty)
        #expect(try vault.read("Ta Da/Logbook/2026-10/Clean the house.md").contains("status: Done"))
    }
}

@Test func renamingAProjectOrAreaRelinksItsLoggedFiles() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile("---\ntype: area\n---\n", "Ta Da/areas/Home.md", in: folder)
        try writeFile("---\ntype: project\nstatus: Done\ncompletedDate: 2026-09-30\narea: \"[[Home]]\"\n---\n",
                      "Ta Da/Logbook/2026-09/Kombi.md", in: folder)
        try writeFile(task("Done", completed: "2026-09-30", project: "Kombi"), "Ta Da/Logbook/2026-09/Listing.md", in: folder)
        _ = try vault.renameProject(at: "Ta Da/Logbook/2026-09/Kombi.md", to: "Sell Kombi", index: await vault.loadIndex())
        #expect(try vault.read("Ta Da/Logbook/2026-09/Listing.md").contains("project: \"[[Sell Kombi]]\""))
        _ = try vault.renameArea(at: "Ta Da/areas/Home.md", to: "House", index: await vault.loadIndex())
        #expect(try vault.read("Ta Da/Logbook/2026-09/Sell Kombi.md").contains("area: \"[[House]]\""))
    }
}

@Test func aProjectIsLoggedUnderATitleNoOtherProjectHas() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(project("Done", completed: "2026-08-31"), "Ta Da/Logbook/2026-08/Accounts.md", in: folder)
        try writeFile(project("Done", completed: "2026-10-01"), "Ta Da/projects/Accounts.md", in: folder)
        try writeFile(task("Done", completed: "2026-10-01", project: "Accounts"), "Ta Da/tasks/File them.md", in: folder)
        try writeFile(project("Done", completed: "2026-09-30"), "work/Accounts.md", in: folder)
        let index = await vault.loadIndex()
        let moved = try vault.log(["Ta Da/projects/Accounts.md", "Ta Da/tasks/File them.md", "work/Accounts.md"], index: index, today: today)
        #expect(moved["Ta Da/projects/Accounts.md"] == "Ta Da/Logbook/2026-10/Accounts 2.md")
        #expect(moved["work/Accounts.md"] == "Ta Da/Logbook/2026-09/Accounts 3.md")
        #expect(try vault.read("Ta Da/Logbook/2026-10/File them.md").contains("project: \"[[Accounts 2]]\""))
    }
}

@Test func aProjectReopenedFromTheLogbookTakesATitleNoOtherProjectHas() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(project("Done", completed: "2026-08-31"), "Ta Da/Logbook/2026-08/Accounts.md", in: folder)
        try writeFile(project("Done", completed: "2026-09-30"), "Ta Da/Logbook/2026-09/Accounts.md", in: folder)
        try writeFile(project("Doing"), "work/Accounts 2.md", in: folder)
        try writeFile(task("Done", completed: "2026-09-30", project: "Accounts"), "Ta Da/Logbook/2026-08/File them.md", in: folder)
        let index = await vault.loadIndex()
        #expect(try vault.unlog(["Ta Da/Logbook/2026-08/Accounts.md"], index: index, today: today)
            == ["Ta Da/Logbook/2026-08/Accounts.md": "Ta Da/projects/Accounts 3.md"])
        #expect(try vault.read("Ta Da/Logbook/2026-08/File them.md").contains("project: \"[[Accounts 3]]\""))
    }
}

@Test func loggedProjectsWithLiveOpenTasksAreListed() {
    let index = VaultIndex([
        makeItem("Ta Da/Logbook/2026-09/Shipped.md", "type: project\nstatus: Done\ncompletedDate: 2026-09-30"),
        makeItem("Ta Da/Logbook/2026-09/Quiet.md", "type: project\nstatus: Done\ncompletedDate: 2026-09-30"),
        makeItem("Ta Da/Logbook/2026-09/Closed task.md", "type: task\nstatus: Done\ncompletedDate: 2026-09-30\nproject: \"[[Quiet]]\""),
        makeItem("Ta Da/projects/Live.md", "type: project\nstatus: Doing"),
        makeItem("Ta Da/tasks/One.md", "type: task\nstatus: Doing\nproject: \"[[Shipped]]\""),
        makeItem("Ta Da/tasks/Two.md", "type: task\nstatus: Not Started\nproject: \"[[Shipped]]\""),
        makeItem("Ta Da/tasks/Three.md", "type: task\nstatus: Doing\nproject: \"[[Live]]\""),
        makeItem("Ta Da/tasks/Four.md", "type: task\nstatus: Done\ncompletedDate: 2026-10-01\nproject: \"[[Quiet]]\""),
    ])
    #expect(index.loggedProjectsWithOpenTasks.map(\.title) == ["Shipped"])
}

@Test func aNewRenamedOrRestoredProjectTakesATitleNoOtherProjectHas() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(project("Done", completed: "2026-08-31"), "Ta Da/Logbook/2026-08/Accounts.md", in: folder)
        try writeFile(project("Doing"), "work/Books.md", in: folder)
        try writeFile(task("Doing", project: "Books"), "Ta Da/tasks/Balance.md", in: folder)
        try writeFile(task("Not Started", project: "Gone"), ".trash/Restore me.md", in: folder)
        try writeFile(project("Done", completed: "2026-08-31"), "Ta Da/Logbook/2026-08/Gone.md", in: folder)
        let index = await vault.loadIndex()

        #expect(try vault.create(project("Doing"), in: Vault.projectFolder, title: "Accounts", taken: index.projectFilenames())
            == "Ta Da/projects/Accounts 2.md")

        let renamed = try vault.renameProject(at: "work/Books.md", to: "Accounts", index: index)
        #expect(renamed.path == "work/Accounts 2.md")
        #expect(try vault.read("Ta Da/tasks/Balance.md").contains("project: \"[[Accounts 2]]\""))

        #expect(try vault.restore([".trash/Restore me.md"], index: index, today: today)
            == ["Ta Da/projects/Gone 2.md", "Ta Da/tasks/Restore me.md"])
        #expect(try vault.read("Ta Da/tasks/Restore me.md").contains("project: \"[[Gone 2]]\""))
    }
}
