import Foundation
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct LogbookModelTests {
    let folder: TestFolder

    init() throws {
        folder = try TestFolder([
            "Ta Da/projects/Kombi.md": "---\ntype: project\nstatus: Doing\n---\n",
            "Ta Da/tasks/Photos.md": "---\ntype: task\nstatus: Doing\nproject: \"[[Kombi]]\"\n---\n",
            "Ta Da/tasks/Listing.md": "---\ntype: task\nstatus: Not Started\nproject: \"[[Kombi]]\"\n---\n",
            "Ta Da/tasks/Old.md": "---\ntype: task\nstatus: Done\ncompletedDate: 2026-09-20\n---\n",
            "Ta Da/tasks/Today.md": "---\ntype: task\nstatus: Cancelled\ncompletedDate: 2026-10-03\n---\n",
        ])
    }

    @Test func openingTheFolderLogsWhatWasCompletedBeforeTodayOncePerDay() async throws {
        let model = await folder.model(logging: true)
        #expect(model.index["Ta Da/logbook/2026-09/Old.md"] != nil && model.index["Ta Da/tasks/Old.md"] == nil)
        #expect(model.index["Ta Da/tasks/Today.md"] != nil, "today's stay until tomorrow")
        #expect(Set(model.logbook.map(\.title)) == ["Old", "Today"])
        #expect(model.hasFilesToLog)

        try folder.write("---\ntype: task\nstatus: Done\ncompletedDate: 2026-09-21\n---\n", "Ta Da/tasks/Later.md")
        await model.refresh()
        await model.logIfDue()
        #expect(model.index["Ta Da/tasks/Later.md"] != nil, "logged once a day")
    }

    @Test func logNowLogsTodaysToo() async throws {
        let model = await folder.model(logging: true)
        await model.logNow()
        #expect(model.index["Ta Da/logbook/2026-10/Today.md"] != nil)
        #expect(!model.hasFilesToLog)
    }

    @Test func completingAProjectWithOpenTasksAsksFirst() async throws {
        let model = await folder.model(logging: true)
        await model.setStatus(.done, in: "Ta Da/projects/Kombi.md")
        let request = try #require(model.completionConfirmation)
        #expect(request.tasks.map(\.title) == ["Listing", "Photos"] && request.status == .done)
        #expect(model.index["Ta Da/projects/Kombi.md"]?.properties.status == .doing, "nothing changes until it's answered")

        await model.answerCompletion(request, tasksAs: .cancelled)
        #expect(model.completionConfirmation == nil)
        #expect(model.index["Ta Da/projects/Kombi.md"]?.properties.status == .done)
        #expect(model.index["Ta Da/tasks/Photos.md"]?.properties.status == .cancelled)
        #expect(model.index["Ta Da/tasks/Listing.md"]?.properties.completedDate == LocalDate("2026-10-03"))
    }

    @Test func completingSeveralProjectsAsksAboutEachInTurn() async throws {
        try folder.write("---\ntype: project\nstatus: Doing\n---\n", "Ta Da/projects/Boat.md")
        try folder.write("---\ntype: task\nstatus: Doing\nproject: \"[[Boat]]\"\n---\n", "Ta Da/tasks/Sail.md")
        let model = await folder.model(logging: true)
        for path in ["Ta Da/projects/Boat.md", "Ta Da/projects/Kombi.md"] { await model.setStatus(.done, in: path) }
        let first = try #require(model.completionConfirmation)
        #expect(first.project.title == "Boat")

        await model.answerCompletion(first, tasksAs: .done)
        let second = try #require(model.completionConfirmation)
        #expect(second.project.title == "Kombi")
        #expect(model.index["Ta Da/projects/Boat.md"]?.properties.status == .done)

        await model.answerCompletion(second, tasksAs: nil)
        #expect(model.completionConfirmation == nil)
        #expect(model.index["Ta Da/projects/Kombi.md"]?.properties.status == .doing)
    }

    @Test func leavingTheQuestionChangesNothing() async throws {
        let model = await folder.model(logging: true)
        await model.setStatus(.cancelled, in: "Ta Da/projects/Kombi.md")
        await model.answerCompletion(try #require(model.completionConfirmation), tasksAs: nil)
        #expect(model.index["Ta Da/projects/Kombi.md"]?.properties.status == .doing)
    }

    @Test func logNowAsksAboutACompletedProjectWithOpenTasksThenLogsIt() async throws {
        try folder.write("---\ntype: project\nstatus: Done\ncompletedDate: 2026-10-03\n---\n", "Ta Da/projects/Kombi.md")
        let model = await folder.model(logging: true)
        await model.logNow()
        let request = try #require(model.completionConfirmation)
        #expect(request.logsAfter && request.project.title == "Kombi")
        await model.answerCompletion(request, tasksAs: .done)
        #expect(Set(model.index.logged.map(\.title)) == ["Kombi", "Photos", "Listing", "Old", "Today"])
    }

    @Test func reopeningALoggedTaskBringsItAndItsProjectBack() async throws {
        try folder.write("---\ntype: project\nstatus: Done\ncompletedDate: 2026-09-30\n---\n", "Ta Da/projects/Kombi.md")
        try folder.write("---\ntype: task\nstatus: Done\ncompletedDate: 2026-09-30\nproject: \"[[Kombi]]\"\n---\n", "Ta Da/tasks/Photos.md")
        try folder.write("---\ntype: task\nstatus: Done\ncompletedDate: 2026-09-30\nproject: \"[[Kombi]]\"\n---\n", "Ta Da/tasks/Listing.md")
        let model = await folder.model(logging: true)
        #expect(model.index["Ta Da/logbook/2026-09/Photos.md"] != nil)
        model.show(.logbook)
        model.selection = "Ta Da/logbook/2026-09/Photos.md"
        await model.loading?.value
        await model.toggleCompletion(try #require(model.index["Ta Da/logbook/2026-09/Photos.md"]))
        #expect(model.index["Ta Da/tasks/Photos.md"]?.properties.status == .notStarted)
        #expect(model.index["Ta Da/projects/Kombi.md"]?.properties.status == .doing)
        #expect(model.index["Ta Da/logbook/2026-09/Listing.md"] != nil)
        #expect(model.selection == "Ta Da/tasks/Photos.md" && model.document?.path == "Ta Da/tasks/Photos.md")
    }

    @Test func reopeningACancelledTaskSetsItsCompletedProjectToDoing() async throws {
        try folder.write("---\ntype: project\nstatus: Done\ncompletedDate: 2026-10-03\n---\n", "Ta Da/projects/Kombi.md")
        try folder.write("---\ntype: task\nstatus: Cancelled\ncompletedDate: 2026-10-03\nproject: \"[[Kombi]]\"\n---\n", "Ta Da/tasks/Photos.md")
        let model = await folder.model(logging: true)
        await model.setStatus(.notStarted, in: "Ta Da/tasks/Photos.md")
        #expect(model.index["Ta Da/projects/Kombi.md"]?.properties.status == .doing)
        #expect(model.index["Ta Da/projects/Kombi.md"]?.properties.completedDate == nil)
    }

    @Test func movingAnOpenTaskLeavesItsCompletedProject() async throws {
        try folder.write("---\ntype: project\nstatus: Done\ncompletedDate: 2026-10-03\n---\n", "Ta Da/projects/Kombi.md")
        let model = await folder.model(logging: true)
        await model.setStatus(.blocked, in: "Ta Da/tasks/Photos.md")
        #expect(model.index["Ta Da/projects/Kombi.md"]?.properties.status == .done)
    }

    @Test func loggingATaskBeforeItsRenamedProjectRelinksIt() async throws {
        try folder.write("---\ntype: project\nstatus: Done\ncompletedDate: 2026-10-01\n---\n", "Ta Da/logbook/2026-10/Timesheet.md")
        try folder.write("---\ntype: project\nstatus: Done\ncompletedDate: 2026-10-01\n---\n", "Ta Da/projects/Timesheet.md")
        try folder.write("---\ntype: task\nstatus: Done\ncompletedDate: 2026-10-01\nproject: \"[[Timesheet]]\"\n---\n",
                         "Ta Da/tasks/Fill it in.md")
        let model = await folder.model(logging: true)
        #expect(model.index["Ta Da/logbook/2026-10/Timesheet 2.md"] != nil)
        #expect(model.index["Ta Da/logbook/2026-10/Fill it in.md"]?.properties.project?.title == "Timesheet 2")
    }

    @Test func reopeningALoggedTaskSetsItsLiveCompletedProjectToDoing() async throws {
        try folder.write("---\ntype: project\nstatus: Done\ncompletedDate: 2026-10-03\n---\n", "Ta Da/projects/Kombi.md")
        try folder.write("---\ntype: task\nstatus: Done\ncompletedDate: 2026-09-30\nproject: \"[[Kombi]]\"\n---\n", "Ta Da/logbook/2026-09/Tyres.md")
        try folder.write("---\ntype: task\nstatus: Done\ncompletedDate: 2026-10-03\nproject: \"[[Kombi]]\"\n---\n", "Ta Da/tasks/Listing.md")
        let model = await folder.model(logging: true)
        await model.setStatus(.notStarted, in: "Ta Da/logbook/2026-09/Tyres.md")
        #expect(model.index["Ta Da/tasks/Tyres.md"]?.properties.status == .notStarted)
        #expect(model.index["Ta Da/projects/Kombi.md"]?.properties.status == .doing)
    }

    @Test func reopeningATaskWhoseProjectIsLoggedBringsTheProjectBack() async throws {
        try folder.write("---\ntype: project\nstatus: Done\ncompletedDate: 2026-09-30\n---\n", "Ta Da/logbook/2026-09/Boat.md")
        try folder.write("---\ntype: task\nstatus: Done\ncompletedDate: 2026-10-03\nproject: \"[[Boat]]\"\n---\n", "Ta Da/tasks/Sail.md")
        let model = await folder.model(logging: true)
        #expect(model.index["Ta Da/logbook/2026-09/Boat.md"] != nil)
        await model.toggleCompletion(try #require(model.index["Ta Da/tasks/Sail.md"]))
        #expect(model.index["Ta Da/tasks/Sail.md"]?.properties.status == .notStarted)
        #expect(model.index["Ta Da/projects/Boat.md"]?.properties.status == .doing)
        #expect(model.index["Ta Da/projects/Boat.md"]?.properties.completedDate == nil)
        #expect(model.index["Ta Da/logbook/2026-09/Boat.md"] == nil)
    }

    @Test func loggingBringsBackALoggedProjectThatHasOpenTasks() async throws {
        try folder.write("---\ntype: project\nstatus: Done\ncompletedDate: 2026-09-30\n---\n", "Ta Da/logbook/2026-09/Boat.md")
        try folder.write("---\ntype: task\nstatus: Doing\nproject: \"[[Boat]]\"\n---\n", "Ta Da/tasks/Sail.md")
        try folder.write("---\ntype: task\nstatus: Done\ncompletedDate: 2026-09-30\nproject: \"[[Boat]]\"\n---\n",
                         "Ta Da/logbook/2026-09/Tyres.md")
        let model = await folder.model(logging: true)
        #expect(model.index["Ta Da/projects/Boat.md"]?.properties.status == .doing)
        #expect(model.index["Ta Da/projects/Boat.md"]?.properties.completedDate == nil)
        #expect(model.index["Ta Da/logbook/2026-09/Tyres.md"] != nil, "its logged tasks stay")
        #expect(model.index.loggedProjectsWithOpenTasks.isEmpty)
    }

    @Test func eachFolderLogsOnceADay() async throws {
        let other = try TestFolder(["Ta Da/tasks/Old.md": "---\ntype: task\nstatus: Done\ncompletedDate: 2026-09-20\n---\n"])
        let model = await folder.model(logging: true)
        #expect(model.index["Ta Da/logbook/2026-09/Old.md"] != nil)
        await model.choose(other.url)
        #expect(model.index["Ta Da/logbook/2026-09/Old.md"] != nil && model.index["Ta Da/tasks/Old.md"] == nil, "another folder logs that day too")
        #expect(AppModel.lastLogged(folder.url, in: folder.defaults) == model.today)
        #expect(AppModel.lastLogged(other.url, in: folder.defaults) == model.today)
    }

    @Test func answeringTheQuestionClosesTheOpenTasksTheProjectHasThen() async throws {
        let model = await folder.model(logging: true)
        await model.setStatus(.done, in: "Ta Da/projects/Kombi.md")
        let request = try #require(model.completionConfirmation)
        try folder.write("---\ntype: task\nstatus: Doing\nproject: \"[[Kombi]]\"\n---\n", "Ta Da/tasks/Tyres.md")
        await model.refresh()
        await model.answerCompletion(request, tasksAs: .done)
        #expect(model.index["Ta Da/tasks/Tyres.md"]?.properties.status == .done)
        #expect(model.index.openTasks(in: try #require(model.index["Ta Da/projects/Kombi.md"])).isEmpty)
    }

    @Test func aCompletedProjectWithOpenTasksWaitsInItsOwnGroup() async throws {
        try folder.write("---\ntype: project\nstatus: Done\ncompletedDate: 2026-09-01\n---\n", "Ta Da/projects/Kombi.md")
        try folder.write("---\ntype: task\nstatus: Done\ncompletedDate: 2026-10-03\nproject: \"[[Kombi]]\"\n---\n", "Ta Da/tasks/Photos.md")
        let model = await folder.model(logging: true)
        let groups = LogbookGroup.groups(model.logbook, index: model.index, today: model.today)
        #expect(groups.map(\.kind) == [.logsTonight, .waitsForOpenTasks, .logged])
        #expect(groups[0].items.map(\.title) == ["Today"])
        #expect(groups[1].items.map(\.title) == ["Photos", "Kombi"])
    }

    @Test func aLinkToALoggedFileOpensInTheLogbook() async throws {
        let model = await folder.model(logging: true)
        model.openLink(to: "Ta Da/logbook/2026-09/Old.md")
        #expect(model.domain == .logbook && model.selection == "Ta Da/logbook/2026-09/Old.md")
    }
}
