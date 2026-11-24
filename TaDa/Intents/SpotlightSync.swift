// Keeps Spotlight's copy of the open folder's tasks, projects and areas in step with the index: a second after it
// changes, the entities that changed are indexed again and those that went are deleted.
import AppIntents
import CoreSpotlight
import Foundation

/// Where the entities go: Spotlight, or a test's record.
protocol EntityStore {
    func deleteAll() async throws
    func index(_ tasks: [TaskEntity], _ parents: [ParentEntity]) async throws
    func delete(tasks: [String], parents: [String]) async throws
    /// Projects or areas changed, so the App Shortcuts that name one have new values.
    func parentsChanged()
}

final class SpotlightSync {
    private let model: AppModel
    private let store: any EntityStore
    private var tasks: [String: TaskEntity]?
    private var parents: [String: ParentEntity] = [:]
    private var pending: Task<Void, Never>?

    init(model: AppModel, store: any EntityStore = SpotlightStore()) {
        self.model = model
        self.store = store
    }

    /// Syncs now and after every change to the index.
    func start() {
        observe()
        pending = Task { await sync() }
    }

    private func observe() {
        withObservationTracking { _ = (model.index, model.state) } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observe()
                self.pending?.cancel()
                self.pending = Task {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    await self.sync()
                }
            }
        }
    }

    /// The first sync replaces everything Spotlight had; each one after sends only what changed.
    func sync() async {
        guard model.state == .ready else { return }
        let newTasks = Dictionary(model.openTaskEntities.map { ($0.id, $0) }) { first, _ in first }
        let newParents = Dictionary(model.openParentEntities.map { ($0.id, $0) }) { first, _ in first }
        let isFirst = tasks == nil, oldTasks = tasks ?? [:], oldParents = parents
        tasks = newTasks
        parents = newParents
        do {
            if isFirst { try await store.deleteAll() }
            let changedTasks = newTasks.values.filter { oldTasks[$0.id] != $0 }
            let changedParents = newParents.values.filter { oldParents[$0.id] != $0 }
            if !changedTasks.isEmpty || !changedParents.isEmpty { try await store.index(changedTasks, changedParents) }
            let goneTasks = oldTasks.keys.filter { newTasks[$0] == nil }
            let goneParents = oldParents.keys.filter { newParents[$0] == nil }
            if !goneTasks.isEmpty || !goneParents.isEmpty { try await store.delete(tasks: goneTasks, parents: goneParents) }
            if !changedParents.isEmpty || !goneParents.isEmpty { store.parentsChanged() }
        } catch {
            // Spotlight is a convenience: the next sync starts over.
            tasks = nil
            parents = [:]
        }
    }
}

nonisolated struct SpotlightStore: EntityStore {
    private var index: CSSearchableIndex { .default() }

    func deleteAll() async throws {
        try await index.deleteAllSearchableItems()
    }

    func index(_ tasks: [TaskEntity], _ parents: [ParentEntity]) async throws {
        if !tasks.isEmpty { try await index.indexAppEntities(tasks) }
        if !parents.isEmpty { try await index.indexAppEntities(parents) }
    }

    func delete(tasks: [String], parents: [String]) async throws {
        if !tasks.isEmpty { try await index.deleteAppEntities(identifiedBy: tasks, ofType: TaskEntity.self) }
        if !parents.isEmpty { try await index.deleteAppEntities(identifiedBy: parents, ofType: ParentEntity.self) }
    }

    func parentsChanged() {
        TaDaShortcuts.updateAppShortcutParameters()
    }
}
