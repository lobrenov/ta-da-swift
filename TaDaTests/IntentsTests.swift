import Foundation
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct IntentsTests {
    let folder: TestFolder

    init() throws {
        folder = try TestFolder([
            "Ta Da/areas/Home.md": "---\ntype: area\n---\n",
            "Ta Da/projects/Garden.md": "---\ntype: project\nstatus: Doing\narea: \"[[Home]]\"\n---\n",
            "Ta Da/projects/Shed.md": "---\ntype: project\nstatus: Done\n---\n",
            "Ta Da/tasks/Water plants.md": "---\ntype: task\nstatus: Doing\nproject: \"[[Garden]]\"\n---\n",
            "Ta Da/tasks/Buy milk.md": "---\ntype: task\nstatus: Not Started\n---\n",
            "Ta Da/tasks/Paint fence.md": "---\ntype: task\nstatus: Done\n---\n",
        ])
    }

    @Test func taskEntitiesAreOpenTasksByTitleWithTheirParent() async {
        let model = await folder.model()
        let all = await model.taskEntities(matching: nil)
        #expect(all.map(\.title) == ["Buy milk", "Water plants"])
        #expect(all.map(\.parent) == [nil, "Garden"])
        #expect(await model.taskEntities(matching: "water").map(\.id) == ["Ta Da/tasks/Water plants.md"])
    }

    @Test func taskEntitiesByIDSkipOtherKindsAndMissingFiles() async {
        let model = await folder.model()
        let ids = ["Ta Da/tasks/Paint fence.md", "Ta Da/projects/Garden.md", "Ta Da/tasks/Gone.md"]
        #expect(await model.taskEntities(ids).map(\.title) == ["Paint fence"])
    }

    @Test func parentEntitiesAreAreasThenOpenProjects() async {
        let model = await folder.model()
        let all = await model.parentEntities(matching: nil)
        #expect(all.map(\.title) == ["Home", "Garden"])
        #expect(all.map(\.parent) == [.area("Home"), .project("Garden")])
        #expect(await model.parentEntities(["Ta Da/projects/Shed.md"]).map(\.title) == ["Shed"])
    }

    @Test func addTaskWritesItUnderItsParentWithDueDateAndTags() async throws {
        let model = await folder.model()
        let item = try await model.addTask("Rake leaves", in: .project("Garden"), due: LocalDate("2026-10-05"),
                                          tags: ["outside", "not a tag!"])
        #expect(item.path == "Ta Da/tasks/Rake leaves.md")
        #expect(model.index.parent(of: item)?.title == "Garden")
        #expect(item.properties.dueDate == LocalDate("2026-10-05"))
        #expect(item.properties.tags.map(\.path) == ["outside"])
    }

    @Test func intentsWithNoFolderSayToOpenOne() async {
        let model = AppModel(defaults: TestSettings())
        await #expect(throws: IntentError.self) { try await model.addTask("A", in: nil, due: nil, tags: []) }
        #expect(await model.taskEntities(matching: nil).isEmpty)
    }

    @Test func aMissingItemIsNotFound() async {
        let model = await folder.model()
        await #expect(throws: IntentError.self) { try await model.intentItem("Ta Da/tasks/Gone.md", title: "Gone") }
    }

    @Test func revealOpensATaskInItsProjectAndAProjectAsItsPage() async {
        let model = await folder.model()
        model.reveal(.file("Ta Da/tasks/Water plants.md"))
        #expect(model.domain == .project("Ta Da/projects/Garden.md"))
        #expect(model.selection == "Ta Da/tasks/Water plants.md")
        model.reveal(.file("Ta Da/areas/Home.md"))
        #expect(model.domain == .area("Ta Da/areas/Home.md"))
        model.reveal(.domain(.logbook))
        #expect(model.domain == .logbook)
    }

    @Test func phoneShowsATaskUnderItsParentAndViewsInTheirTabs() async {
        let model = await folder.model()
        let nav = PhoneNavigation()
        nav.show(.file("Ta Da/tasks/Water plants.md"), in: model.index)
        #expect(nav.tab == .tasks)
        #expect(nav.stacks[.tasks] == [.project("Ta Da/projects/Garden.md"), .file("Ta Da/tasks/Water plants.md")])
        nav.show(.file("Ta Da/tasks/Buy milk.md"), in: model.index)
        #expect(nav.stacks[.tasks] == [.loose, .file("Ta Da/tasks/Buy milk.md")])
        nav.show(.file("Ta Da/areas/Home.md"), in: model.index)
        #expect(nav.stacks[.tasks] == [.area("Ta Da/areas/Home.md")])
        nav.show(.domain(.logbook), in: model.index)
        #expect(nav.tab == .other)
        #expect(nav.stacks[.other] == [.logbook])
        nav.show(.domain(.agenda), in: model.index)
        #expect(nav.tab == .agenda)
    }
}

@MainActor
struct SpotlightSyncTests {
    let folder: TestFolder

    init() throws {
        folder = try TestFolder([
            "Ta Da/projects/Garden.md": "---\ntype: project\nstatus: Doing\n---\n",
            "Ta Da/tasks/Water plants.md": "---\ntype: task\nstatus: Doing\nproject: \"[[Garden]]\"\n---\n",
            "Ta Da/tasks/Buy milk.md": "---\ntype: task\nstatus: Not Started\n---\n",
        ])
    }

    final class Record: EntityStore {
        var calls: [String] = []
        func deleteAll() async throws { calls.append("deleteAll") }
        func index(_ tasks: [TaskEntity], _ parents: [ParentEntity]) async throws {
            calls.append("index " + (tasks.map(\.title) + parents.map(\.title)).sorted().joined(separator: ", "))
        }
        func delete(tasks: [String], parents: [String]) async throws {
            calls.append("delete " + (tasks + parents).sorted().joined(separator: ", "))
        }
        func parentsChanged() { calls.append("parentsChanged") }
    }

    @Test func theFirstSyncReplacesEverythingThenOnlyChangesAreSent() async throws {
        let model = await folder.model()
        let record = Record()
        let sync = SpotlightSync(model: model, store: record)
        await sync.sync()
        #expect(record.calls == ["deleteAll", "index Buy milk, Garden, Water plants", "parentsChanged"])

        record.calls = []
        await sync.sync()
        #expect(record.calls.isEmpty)

        await model.setStatus(.done, in: "Ta Da/tasks/Buy milk.md")
        _ = try await model.addTask("Rake leaves", in: .project("Garden"), due: nil, tags: [])
        await sync.sync()
        #expect(record.calls == ["index Rake leaves", "delete Ta Da/tasks/Buy milk.md"])
    }
}
