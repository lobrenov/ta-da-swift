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
    #expect(Vault.logbookFolder(for: LocalDate("2026-09-30")!) == ".logbook/2026-09")
}

@Test func filesToLogAreClosedBeforeTheDayAndWaitForOpenTasks() {
    let index = VaultIndex([
        makeItem("tasks/Done yesterday.md", "type: task\nstatus: Done\ncompletedDate: 2026-10-01"),
        makeItem("tasks/Cancelled yesterday.md", "type: task\nstatus: Cancelled\ncompletedDate: 2026-10-01"),
        makeItem("tasks/Done today.md", "type: task\nstatus: Done\ncompletedDate: 2026-10-02"),
        makeItem("tasks/Done undated.md", "type: task\nstatus: Done"),
        makeItem("tasks/Open.md", "type: task\nstatus: Doing\ncompletedDate: 2026-09-01"),
        makeItem("areas/Home.md", "type: area"),
        makeItem("projects/Shipped.md", "type: project\nstatus: Done\ncompletedDate: 2026-09-30"),
        makeItem("tasks/Shipped task.md", "type: task\nstatus: Done\ncompletedDate: 2026-09-29\nproject: \"[[Shipped]]\""),
        makeItem("projects/Waiting.md", "type: project\nstatus: Done\ncompletedDate: 2026-09-30"),
        makeItem("tasks/Waiting open.md", "type: task\nstatus: Doing\nproject: \"[[Waiting]]\""),
        makeItem("tasks/Waiting done.md", "type: task\nstatus: Done\ncompletedDate: 2026-09-29\nproject: \"[[Waiting]]\""),
        makeItem(".logbook/2026-09/Logged.md", "type: task\nstatus: Done\ncompletedDate: 2026-09-01"),
        makeItem(".logbook/2026-09/Reopened.md", "type: task\nstatus: Not Started"),
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
        try writeFile(project("Done", completed: "2026-09-30"), "projects/Kombi.md", in: folder)
        try writeFile(task("Cancelled", completed: "2026-10-01", project: "Kombi"), "tasks/List it.md", in: folder)
        try writeFile(task("Done"), "deep/Undated.md", in: folder)
        try writeFile(task("Done", completed: "2026-10-01"), ".logbook/2026-10/Undated.md", in: folder)
        let index = await vault.loadIndex()
        #expect(index[".logbook/2026-10/Undated.md"]?.isLogged == true, "a scan reads .logbook/")
        let moved = try vault.log(["projects/Kombi.md", "tasks/List it.md", "deep/Undated.md"], index: index, today: today)
        #expect(moved == ["projects/Kombi.md": ".logbook/2026-09/Kombi.md", "tasks/List it.md": ".logbook/2026-10/List it.md",
                          "deep/Undated.md": ".logbook/2026-10/Undated 2.md"])
        let reloaded = await vault.loadIndex()
        #expect(Set(reloaded.logged.map(\.path)) == Set(moved.values).union([".logbook/2026-10/Undated.md"]))
        #expect(reloaded.items.count == 4)
        #expect(reloaded.parent(of: reloaded[".logbook/2026-10/List it.md"]!)?.path == ".logbook/2026-09/Kombi.md")
        #expect(vault.path(of: folder.appending(path: ".logbook/2026-09/Kombi.md")) == ".logbook/2026-09/Kombi.md")
        #expect(vault.path(of: folder.appending(path: ".trash/Kombi.md")) == nil)
    }
}

@Test func loggingAProjectUnderATakenNameRelinksItsTasks() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(project("Done", completed: "2026-10-01"), "projects/Timesheet.md", in: folder)
        try writeFile(task("Done", completed: "2026-10-01", project: "Timesheet"), "tasks/Fill it in.md", in: folder)
        try writeFile(project("Done", completed: "2026-10-01"), ".logbook/2026-10/Timesheet.md", in: folder)
        let index = await vault.loadIndex()
        let moved = try vault.log(["projects/Timesheet.md", "tasks/Fill it in.md"], index: index, today: today)
        #expect(moved["projects/Timesheet.md"] == ".logbook/2026-10/Timesheet 2.md")
        let text = try vault.read(".logbook/2026-10/Fill it in.md")
        #expect(text.contains("project: \"[[Timesheet 2]]\""))
    }
}

@Test func reopeningATaskBringsBackItsLoggedProjectAsDoing() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(project("Done", completed: "2026-09-30"), ".logbook/2026-09/Kombi.md", in: folder)
        try writeFile(task("Not Started", project: "Kombi"), ".logbook/2026-09/Photos.md", in: folder)
        try writeFile(task("Done", completed: "2026-09-30", project: "Kombi"), ".logbook/2026-09/Listing.md", in: folder)
        try writeFile(task("Doing"), "tasks/Photos.md", in: folder)
        let index = await vault.loadIndex()
        let moved = try vault.unlog([".logbook/2026-09/Photos.md"], index: index, today: today)
        #expect(moved == [".logbook/2026-09/Kombi.md": "projects/Kombi.md", ".logbook/2026-09/Photos.md": "tasks/Photos 2.md"])
        let reloaded = await vault.loadIndex()
        let kombi = try #require(reloaded["projects/Kombi.md"])
        #expect(kombi.properties.status == .doing && kombi.properties.completedDate == nil)
        #expect(reloaded.tasks(in: kombi).map(\.title) == ["Photos 2"])
        #expect(reloaded.tasks(in: kombi, includingLogged: true).map(\.title) == ["Listing", "Photos 2"], "its other tasks stay logged")
    }
}

@Test func reopeningAProjectLeavesItsTasksLogged() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(project("Doing"), ".logbook/2026-09/Kombi.md", in: folder)
        try writeFile(task("Done", completed: "2026-09-30", project: "Kombi"), ".logbook/2026-09/Listing.md", in: folder)
        let index = await vault.loadIndex()
        #expect(try vault.unlog([".logbook/2026-09/Kombi.md"], index: index, today: today) == [".logbook/2026-09/Kombi.md": "projects/Kombi.md"])
        #expect(try vault.read("projects/Kombi.md") == project("Doing"), "its own status is the caller's")
    }
}

@Test func trashingAProjectLeavesItsLoggedTasks() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(project("Doing"), "projects/Kombi.md", in: folder)
        try writeFile(task("Doing", project: "Kombi"), "tasks/Open.md", in: folder)
        try writeFile(task("Done", completed: "2026-09-30", project: "Kombi"), ".logbook/2026-09/Listing.md", in: folder)
        let index = await vault.loadIndex()
        #expect(try vault.moveToTrash("projects/Kombi.md", index: index) == ["projects/Kombi.md", "tasks/Open.md"])
        #expect(vault.markdownPaths() == [".logbook/2026-09/Listing.md"])
    }
}

@Test func loggingGoesOnPastAFileThatCantMove() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile(project("Done", completed: "2026-10-01"), "projects/Timesheet.md", in: folder)
        try writeFile(task("Done", completed: "2026-10-01", project: "Timesheet"), "tasks/Fill it in.md", in: folder)
        try writeFile(task("Done", completed: "2026-10-01"), "tasks/Gone.md", in: folder)
        try writeFile(project("Done", completed: "2026-10-01"), ".logbook/2026-10/Timesheet.md", in: folder)
        let index = await vault.loadIndex()
        try FileManager.default.removeItem(at: folder.appending(path: "tasks/Gone.md"))
        let moved = try vault.log(["tasks/Fill it in.md", "tasks/Gone.md", "projects/Timesheet.md"], index: index, today: today)
        #expect(moved == ["tasks/Fill it in.md": ".logbook/2026-10/Fill it in.md",
                          "projects/Timesheet.md": ".logbook/2026-10/Timesheet 2.md"])
        #expect(try vault.read(".logbook/2026-10/Fill it in.md").contains("project: \"[[Timesheet 2]]\""))
    }
}

@Test func renamingAProjectOrAreaRelinksItsLoggedFiles() async throws {
    try await withTemporaryFolder { folder in
        let vault = Vault(root: folder)
        try writeFile("---\ntype: area\n---\n", "areas/Home.md", in: folder)
        try writeFile("---\ntype: project\nstatus: Done\ncompletedDate: 2026-09-30\narea: \"[[Home]]\"\n---\n",
                      ".logbook/2026-09/Kombi.md", in: folder)
        try writeFile(task("Done", completed: "2026-09-30", project: "Kombi"), ".logbook/2026-09/Listing.md", in: folder)
        _ = try vault.renameProject(at: ".logbook/2026-09/Kombi.md", to: "Sell Kombi", index: await vault.loadIndex())
        #expect(try vault.read(".logbook/2026-09/Listing.md").contains("project: \"[[Sell Kombi]]\""))
        _ = try vault.renameArea(at: "areas/Home.md", to: "House", index: await vault.loadIndex())
        #expect(try vault.read(".logbook/2026-09/Sell Kombi.md").contains("area: \"[[House]]\""))
    }
}
