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

@MainActor
struct RemindersSchemaTests {
    let folder: TestFolder

    init() throws {
        folder = try TestFolder([
            "Ta Da/areas/Home.md": "---\ntype: area\n---\n",
            "Ta Da/projects/Garden.md": "---\ntype: project\nstatus: Doing\narea: \"[[Home]]\"\n---\n",
            "Ta Da/tasks/Water plants.md": "---\ntype: task\nstatus: Doing\nproject: \"[[Garden]]\"\ntags: [outside]\n---\nEvery evening.\n",
            "Ta Da/tasks/Buy milk.md": "---\ntype: task\nstatus: Done\ncompletedDate: 2026-10-01\n---\n",
        ])
    }

    @Test func aTaskIsAReminderInItsParentsListOrLoose() async throws {
        guard #available(macOS 27, iOS 27, *) else { return }
        let model = await folder.model()
        let water = model.reminder(try #require(model.index["Ta Da/tasks/Water plants.md"]))
        #expect(water.title == "Water plants")
        #expect(water.list.id == "Ta Da/projects/Garden.md")
        #expect(water.tags == ["outside"])
        #expect(water.note.map { String($0.characters) } == "Every evening.")
        #expect(!water.isCompleted)
        let milk = model.reminder(try #require(model.index["Ta Da/tasks/Buy milk.md"]))
        #expect(milk.list.id == "" && milk.list.name == "Loose")
        #expect(milk.isCompleted)
        #expect(await model.reminderLists().map(\.name) == ["Loose", "Home", "Garden"])
    }

    @Test func searchingFindsDoneTasksToo() async {
        guard #available(macOS 27, iOS 27, *) else { return }
        let model = await folder.model()
        #expect(await model.reminders(matching: "milk").map(\.title) == ["Buy milk"])
        #expect(await model.reminders(matching: nil).map(\.title) == ["Water plants"])
    }

    @Test func addingWritesTheNoteRepeatAndList() async throws {
        guard #available(macOS 27, iOS 27, *) else { return }
        let model = await folder.model()
        let rule = try #require(RepeatRule(frequency: .week, weekdays: [2]))
        let item = try await model.addTask("Mow", in: model.parent(ofList: "Ta Da/projects/Garden.md"),
                                           due: LocalDate("2026-10-05"), tags: [], repeating: rule, note: "Front and back")
        let text = try folder.read(item.path)
        #expect(text.contains("project: \"[[Garden]]\""))
        #expect(text.contains("repeat: every week on Mon"))
        #expect(text.hasSuffix("---\nFront and back\n"))
        #expect(model.parent(ofList: "") == nil)
    }

    @Test func tagsAreSetAndATaskIsRenamed() async throws {
        guard #available(macOS 27, iOS 27, *) else { return }
        let model = await folder.model()
        await model.setTags(["inside", "garden"], of: "Ta Da/tasks/Water plants.md")
        #expect(Set(model.index["Ta Da/tasks/Water plants.md"]?.tags.map(\.tag.path) ?? []) == ["inside", "garden"])
        let path = try await model.renameTask("Ta Da/tasks/Water plants.md", to: "Water the plants")
        #expect(path == "Ta Da/tasks/Water the plants.md")
        #expect(model.index[path] != nil)
    }

    @Test func repeatRulesConvertBothWays() throws {
        guard #available(macOS 27, iOS 27, *) else { return }
        let weekly = try #require(RepeatRule(frequency: .week, interval: 2, weekdays: [2, 6], until: LocalDate("2026-12-31")))
        let recurrence = try #require(Calendar.RecurrenceRule(weekly))
        #expect(recurrence.frequency == .weekly && recurrence.interval == 2)
        #expect(RepeatRule(recurrence) == weekly)
        let daily = try #require(RepeatRule(frequency: .day, interval: 3))
        #expect(RepeatRule(try #require(Calendar.RecurrenceRule(daily))) == daily)
        #expect(RepeatRule(Calendar.RecurrenceRule(calendar: .current, frequency: .hourly)) == nil)
    }
}
