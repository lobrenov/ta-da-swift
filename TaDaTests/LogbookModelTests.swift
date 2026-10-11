import Foundation
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct LogbookModelTests {
    let folder: TestFolder

    init() throws {
        folder = try TestFolder([
            "projects/Kombi.md": "---\ntype: project\nstatus: Doing\n---\n",
            "tasks/Photos.md": "---\ntype: task\nstatus: Doing\nproject: \"[[Kombi]]\"\n---\n",
            "tasks/Listing.md": "---\ntype: task\nstatus: Not Started\nproject: \"[[Kombi]]\"\n---\n",
            "tasks/Old.md": "---\ntype: task\nstatus: Done\ncompletedDate: 2026-09-20\n---\n",
            "tasks/Today.md": "---\ntype: task\nstatus: Cancelled\ncompletedDate: 2026-10-03\n---\n",
        ])
    }

    @Test func openingTheFolderLogsWhatWasCompletedBeforeTodayOncePerDay() async throws {
        let model = await folder.model(logging: true)
        #expect(model.index[".logbook/2026-09/Old.md"] != nil && model.index["tasks/Old.md"] == nil)
        #expect(model.index["tasks/Today.md"] != nil, "today's stay until tomorrow")
        #expect(Set(model.logbook.map(\.title)) == ["Old", "Today"])
        #expect(model.hasFilesToLog)

        try folder.write("---\ntype: task\nstatus: Done\ncompletedDate: 2026-09-21\n---\n", "tasks/Later.md")
        await model.refresh()
        await model.logIfDue()
        #expect(model.index["tasks/Later.md"] != nil, "logged once a day")
    }

    @Test func logNowLogsTodaysToo() async throws {
        let model = await folder.model(logging: true)
        await model.logNow()
        #expect(model.index[".logbook/2026-10/Today.md"] != nil)
        #expect(!model.hasFilesToLog)
    }

    @Test func completingAProjectWithOpenTasksAsksFirst() async throws {
        let model = await folder.model(logging: true)
        await model.setStatus(.done, in: "projects/Kombi.md")
        let request = try #require(model.completionConfirmation)
        #expect(request.tasks.map(\.title) == ["Listing", "Photos"] && request.status == .done)
        #expect(model.index["projects/Kombi.md"]?.properties.status == .doing, "nothing changes until it's answered")

        await model.answerCompletion(request, tasksAs: .cancelled)
        #expect(model.completionConfirmation == nil)
        #expect(model.index["projects/Kombi.md"]?.properties.status == .done)
        #expect(model.index["tasks/Photos.md"]?.properties.status == .cancelled)
        #expect(model.index["tasks/Listing.md"]?.properties.completedDate == LocalDate("2026-10-03"))
    }

    @Test func leavingTheQuestionChangesNothing() async throws {
        let model = await folder.model(logging: true)
        await model.setStatus(.cancelled, in: "projects/Kombi.md")
        await model.answerCompletion(try #require(model.completionConfirmation), tasksAs: nil)
        #expect(model.index["projects/Kombi.md"]?.properties.status == .doing)
    }

    @Test func logNowAsksAboutACompletedProjectWithOpenTasksThenLogsIt() async throws {
        try folder.write("---\ntype: project\nstatus: Done\ncompletedDate: 2026-10-03\n---\n", "projects/Kombi.md")
        let model = await folder.model(logging: true)
        await model.logNow()
        let request = try #require(model.completionConfirmation)
        #expect(request.logsAfter && request.project.title == "Kombi")
        await model.answerCompletion(request, tasksAs: .done)
        #expect(Set(model.index.logged.map(\.title)) == ["Kombi", "Photos", "Listing", "Old", "Today"])
    }

    @Test func reopeningALoggedTaskBringsItAndItsProjectBack() async throws {
        try folder.write("---\ntype: project\nstatus: Done\ncompletedDate: 2026-09-30\n---\n", "projects/Kombi.md")
        try folder.write("---\ntype: task\nstatus: Done\ncompletedDate: 2026-09-30\nproject: \"[[Kombi]]\"\n---\n", "tasks/Photos.md")
        try folder.write("---\ntype: task\nstatus: Done\ncompletedDate: 2026-09-30\nproject: \"[[Kombi]]\"\n---\n", "tasks/Listing.md")
        let model = await folder.model(logging: true)
        #expect(model.index[".logbook/2026-09/Photos.md"] != nil)
        model.show(.logbook)
        model.selection = ".logbook/2026-09/Photos.md"
        await model.loading?.value
        await model.toggleCompletion(try #require(model.index[".logbook/2026-09/Photos.md"]))
        #expect(model.index["tasks/Photos.md"]?.properties.status == .notStarted)
        #expect(model.index["projects/Kombi.md"]?.properties.status == .doing)
        #expect(model.index[".logbook/2026-09/Listing.md"] != nil)
        #expect(model.selection == "tasks/Photos.md" && model.document?.path == "tasks/Photos.md")
    }

    @Test func reopeningACancelledTaskSetsItsCompletedProjectToDoing() async throws {
        try folder.write("---\ntype: project\nstatus: Done\ncompletedDate: 2026-10-03\n---\n", "projects/Kombi.md")
        try folder.write("---\ntype: task\nstatus: Cancelled\ncompletedDate: 2026-10-03\nproject: \"[[Kombi]]\"\n---\n", "tasks/Photos.md")
        let model = await folder.model(logging: true)
        await model.setStatus(.notStarted, in: "tasks/Photos.md")
        #expect(model.index["projects/Kombi.md"]?.properties.status == .doing)
        #expect(model.index["projects/Kombi.md"]?.properties.completedDate == nil)
    }

    @Test func movingAnOpenTaskLeavesItsCompletedProject() async throws {
        try folder.write("---\ntype: project\nstatus: Done\ncompletedDate: 2026-10-03\n---\n", "projects/Kombi.md")
        let model = await folder.model(logging: true)
        await model.setStatus(.blocked, in: "tasks/Photos.md")
        #expect(model.index["projects/Kombi.md"]?.properties.status == .done)
    }

    @Test func loggingATaskBeforeItsRenamedProjectRelinksIt() async throws {
        try folder.write("---\ntype: project\nstatus: Done\ncompletedDate: 2026-10-01\n---\n", ".logbook/2026-10/Timesheet.md")
        try folder.write("---\ntype: project\nstatus: Done\ncompletedDate: 2026-10-01\n---\n", "projects/Timesheet.md")
        try folder.write("---\ntype: task\nstatus: Done\ncompletedDate: 2026-10-01\nproject: \"[[Timesheet]]\"\n---\n",
                         "tasks/Fill it in.md")
        let model = await folder.model(logging: true)
        #expect(model.index[".logbook/2026-10/Timesheet 2.md"] != nil)
        #expect(model.index[".logbook/2026-10/Fill it in.md"]?.properties.project?.title == "Timesheet 2")
    }

    @Test func reopeningALoggedTaskSetsItsLiveCompletedProjectToDoing() async throws {
        try folder.write("---\ntype: project\nstatus: Done\ncompletedDate: 2026-10-03\n---\n", "projects/Kombi.md")
        try folder.write("---\ntype: task\nstatus: Done\ncompletedDate: 2026-09-30\nproject: \"[[Kombi]]\"\n---\n", ".logbook/2026-09/Tyres.md")
        try folder.write("---\ntype: task\nstatus: Done\ncompletedDate: 2026-10-03\nproject: \"[[Kombi]]\"\n---\n", "tasks/Listing.md")
        let model = await folder.model(logging: true)
        await model.setStatus(.notStarted, in: ".logbook/2026-09/Tyres.md")
        #expect(model.index["tasks/Tyres.md"]?.properties.status == .notStarted)
        #expect(model.index["projects/Kombi.md"]?.properties.status == .doing)
    }

    @Test func aLinkToALoggedFileOpensInTheLogbook() async throws {
        let model = await folder.model(logging: true)
        model.openLink(to: ".logbook/2026-09/Old.md")
        #expect(model.domain == .logbook && model.selection == ".logbook/2026-09/Old.md")
    }
}
