import Foundation

/// Logging moves completed (Done or Cancelled) tasks and projects into `.logbook/<yyyy-MM>/` by their `completedDate`.
/// Reopening a logged file moves it back to `tasks/` or `projects/`, and a task brings back its logged project as Doing.
/// Areas are never logged.
extension Vault {
    /// Logged files: completed tasks and projects, in a folder per month.
    public static let logbookFolder = ".logbook"

    /// `.logbook/2026-10` for a file completed in October 2026.
    public static func logbookFolder(for date: LocalDate) -> String {
        "\(logbookFolder)/" + String(format: "%04d-%02d", date.year, date.month)
    }

    /// Moves files into their month's folder in `.logbook/`, creating it if needed and numbering names that are taken
    /// there. A file without a `completedDate` goes in `today`'s month. A file that can't be moved (as when another
    /// device already has) doesn't stop the rest; the first error is thrown only when nothing moved. When a project's
    /// name had to change, its tasks' links follow it. Returns each moved file's new path by its old one.
    public func log(_ paths: [String], index: VaultIndex, today: LocalDate) throws -> [String: String] {
        var moved: [String: String] = [:]
        var firstError: (any Error)?
        let items = paths.compactMap { index[$0] }.filter { !$0.isLogged && $0.properties.kind != .area }
        for item in items where moved[item.path] == nil {
            do {
                moved[item.path] = try moveFile(item.path, into: Self.logbookFolder(for: item.properties.completedDate ?? today))
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError, moved.isEmpty { throw firstError }
        try relinkTasks(of: items, moved: moved, index: index)
        return moved
    }

    /// Moves logged files back to `tasks/` or `projects/`, numbering names that are taken. A task whose project is
    /// logged brings it back too, set to Doing. When a project's name had to change, its tasks' links follow it.
    /// Returns each moved file's new path by its old one.
    public func unlog(_ paths: [String], index: VaultIndex, today: LocalDate) throws -> [String: String] {
        let items = paths.compactMap { index[$0] }.filter(\.isLogged)
        var parents: [Item] = []
        for item in items {
            guard let project = index.project(of: item), project.isLogged, !paths.contains(project.path),
                  !parents.contains(project) else { continue }
            parents.append(project)
        }
        var moved: [String: String] = [:]
        for item in parents + items where moved[item.path] == nil {
            moved[item.path] = try moveFile(item.path, into: item.properties.kind == .project ? Self.projectFolder : Self.taskFolder)
        }
        for parent in parents {
            _ = try update(moved[parent.path]!) { Completion.setStatus(.doing, in: $0, today: today) }
        }
        try relinkTasks(of: parents + items, moved: moved, index: index)
        return moved
    }

    /// Points the `project` link of each moved project's tasks at its new title, where moving it changed its name.
    private func relinkTasks(of items: [Item], moved: [String: String], index: VaultIndex) throws {
        for project in items where project.properties.kind == .project {
            guard let newPath = moved[project.path], Item.title(ofPath: newPath) != project.title else { continue }
            for task in index.tasks(in: project, includingLogged: true) {
                try relink(moved[task.path] ?? task.path, key: "project", from: project.title, to: Item.title(ofPath: newPath))
            }
        }
    }
}

extension VaultIndex {
    /// The tasks and projects to log: Done or Cancelled and not logged yet, completed before `before` (any day when it's
    /// nil; a file without a `completedDate` counts as completed before it), sorted by title. A Done or Cancelled
    /// project that still has open tasks waits, and so do its tasks.
    public func filesToLog(completedBefore before: LocalDate?) -> [Item] {
        let waiting = Set(projects.filter { $0.properties.status.isClosed && !openTasks(in: $0).isEmpty }.map(\.path))
        return liveItems.filter { item in
            let p = item.properties
            guard p.kind != .area, p.status.isClosed, !waiting.contains(item.path) else { return false }
            if let project = project(of: item), waiting.contains(project.path) { return false }
            guard let before, let completed = p.completedDate else { return true }
            return completed < before
        }.sorted(by: Self.byTitle)
    }

    /// Logged files that aren't Done or Cancelled any more, as when reopened in another app: logging moves them back.
    public var reopenedLogged: [Item] {
        logged.filter { !$0.properties.status.isClosed }.sorted(by: Self.byTitle)
    }
}
