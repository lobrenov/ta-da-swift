// Tasks, projects and areas as App Entities, for Shortcuts, Siri and Spotlight. An entity's id is its vault-relative path
// in the open folder.
import AppIntents
import Foundation
import TaDaCore

nonisolated struct TaskEntity: IndexedEntity, Hashable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Task"
    static let defaultQuery = TaskQuery()

    let id: String
    let title: String
    /// The task's project or area.
    let parent: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: parent.map { "\($0)" })
    }
}

/// A project or an area: what a task is filed under.
nonisolated struct ParentEntity: IndexedEntity, Hashable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Project or Area"
    static let defaultQuery = ParentQuery()

    let id: String
    let title: String
    let isArea: Bool

    var parent: Parent { isArea ? .area(title) : .project(title) }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: isArea ? "Area" : "Project",
                              image: .init(systemName: isArea ? "square.stack" : "folder"))
    }
}

struct TaskQuery: EntityStringQuery {
    @Dependency private var model: AppModel

    func entities(for identifiers: [String]) async throws -> [TaskEntity] {
        await model.taskEntities(identifiers)
    }

    func entities(matching string: String) async throws -> [TaskEntity] {
        await model.taskEntities(matching: string)
    }

    func suggestedEntities() async throws -> [TaskEntity] {
        await model.taskEntities(matching: nil)
    }
}

struct ParentQuery: EntityStringQuery {
    @Dependency private var model: AppModel

    func entities(for identifiers: [String]) async throws -> [ParentEntity] {
        await model.parentEntities(identifiers)
    }

    func entities(matching string: String) async throws -> [ParentEntity] {
        await model.parentEntities(matching: string)
    }

    func suggestedEntities() async throws -> [ParentEntity] {
        await model.parentEntities(matching: nil)
    }
}

extension AppModel {
    func taskEntity(_ item: Item) -> TaskEntity {
        TaskEntity(id: item.path, title: item.title, parent: index.parent(of: item)?.title)
    }

    func parentEntity(_ item: Item) -> ParentEntity {
        ParentEntity(id: item.path, title: item.title, isArea: item.properties.kind == .area)
    }

    func taskEntities(_ paths: [String]) async -> [TaskEntity] {
        guard await ready() else { return [] }
        return paths.compactMap { index[$0] }.filter { $0.properties.kind == .task }.map(taskEntity)
    }

    /// Open tasks whose title contains `text`, or all open tasks, by title.
    func taskEntities(matching text: String?) async -> [TaskEntity] {
        guard await ready() else { return [] }
        return openTaskEntities.filter { text.map($0.title.localizedStandardContains) ?? true }
    }

    /// The tasks that aren't Done or Cancelled, by title: what Shortcuts suggests and Spotlight finds.
    var openTaskEntities: [TaskEntity] {
        index.tasks.filter { !$0.properties.status.isClosed }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .map(taskEntity)
    }

    func parentEntities(_ paths: [String]) async -> [ParentEntity] {
        guard await ready() else { return [] }
        return paths.compactMap { index[$0] }.filter { $0.properties.kind == .project || $0.properties.kind == .area }
            .map(parentEntity)
    }

    /// `openParentEntities` whose title contains `text`, or all of them.
    func parentEntities(matching text: String?) async -> [ParentEntity] {
        guard await ready() else { return [] }
        return openParentEntities.filter { text.map($0.title.localizedStandardContains) ?? true }
    }

    /// Areas, then projects that aren't Done or Cancelled, each by title.
    var openParentEntities: [ParentEntity] {
        let byTitle: (Item, Item) -> Bool = { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return (index.areas.sorted(by: byTitle) + index.projects.filter { !$0.properties.status.isClosed }.sorted(by: byTitle))
            .map(parentEntity)
    }
}
