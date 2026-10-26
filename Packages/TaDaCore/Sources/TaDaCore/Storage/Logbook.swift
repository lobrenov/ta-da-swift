import Foundation

/// Logging moves completed (Done or Cancelled) tasks and projects into `Ta Da/logbook/<yyyy-MM>/` by their
/// `completedDate`.
/// Reopening a logged file moves it back to `tasks/` or `projects/`, and a task brings back its logged project as Doing.
/// A project moved either way is numbered when another project, live or logged, has its title. Areas are never logged.
extension Vault {
    /// Logged files: completed tasks and projects, in a folder per month.
    public static let logbookFolder = home + "/logbook"

    /// `Ta Da/logbook/2026-10` for a file completed in October 2026.
    public static func logbookFolder(for date: LocalDate) -> String {
        "\(logbookFolder)/" + String(format: "%04d-%02d", date.year, date.month)
    }

    /// Moves files into their month's folder in the Logbook, creating it if needed and numbering names that are taken
    /// there, or by another project for a project. A file without a `completedDate` goes in `today`'s month. A file no
    /// longer at its path (another device logged it) is skipped. A completed repeating task with a next date moves
    /// forward in place instead (`Recurrence`), so it isn't in the result; one whose file no longer moves forward is
    /// logged. A file that can't be moved doesn't stop the
    /// rest; the first error is thrown only when nothing moved. When a project's
    /// name had to change, its tasks' links follow it. Returns each moved file's new path by its old one.
    public func log(_ paths: [String], index: VaultIndex, today: LocalDate) throws -> [String: String] {
        var moved: [String: String] = [:]
        var firstError: (any Error)?
        var named: Set<String> = []
        var rolled = false
        let items = paths.compactMap { index[$0] }.filter { !$0.isLogged && [.task, .project].contains($0.properties.kind) }
        for item in items where moved[item.path] == nil {
            do {
                let closed = index.project(of: item)?.properties.status.isClosed == true
                if Recurrence.next(for: item, today: today, projectClosed: closed) != nil {
                    let now = try update(item.path) { Recurrence.moveForward($0, path: item.path, today: today, projectClosed: closed) }
                    if let now, !now.properties.status.isClosed {
                        rolled = true
                        continue
                    }
                }
                moved[item.path] = try moveFile(item, into: Self.logbookFolder(for: item.properties.completedDate ?? today),
                                                index: index, named: &named)
            } catch where FileManager.default.fileExists(atPath: url(for: item.path).path) {
                firstError = firstError ?? error
            } catch {}
        }
        if let firstError, moved.isEmpty, !rolled { throw firstError }
        try relinkTasks(of: items, moved: moved, index: index)
        return moved
    }

    /// Moves logged files back to `tasks/` or `projects/`, numbering names that are taken there, or by another project
    /// for a project. A task whose project is
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
        var named: Set<String> = []
        for item in parents + items where moved[item.path] == nil {
            moved[item.path] = try moveFile(item, into: item.properties.kind == .project ? Self.projectFolder : Self.taskFolder,
                                            index: index, named: &named)
        }
        for parent in parents {
            _ = try update(moved[parent.path]!) { Completion.setStatus(.doing, in: $0, today: today) }
        }
        try relinkTasks(of: parents + items, moved: moved, index: index)
        return moved
    }

    /// Moves a file into `folder`. A project's filename also avoids every other project's title and `named`, the
    /// projects' filenames chosen so far in this move, which it joins.
    private func moveFile(_ item: Item, into folder: String, index: VaultIndex, named: inout Set<String>) throws -> String {
        guard item.properties.kind == .project else { return try moveFile(item.path, into: folder) }
        let path = try moveFile(item.path, into: folder, taken: named.union(index.projectFilenames(excluding: item.path)))
        named.insert(String(path.split(separator: "/").last ?? ""))
        return path
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
    /// The filenames of every project's title, live or logged, except the project at `path`: the names a project's file
    /// avoids when it's created, renamed or moved.
    public func projectFilenames(excluding path: String? = nil) -> Set<String> {
        Set(items.values.filter { $0.properties.kind == .project && $0.path != path }.map { $0.title + ".md" })
    }

    /// The tasks and projects to log: Done or Cancelled and not logged yet, completed before `before` (any day when it's
    /// nil; a file without a `completedDate` counts as completed before it), sorted by title. A Done or Cancelled
    /// project that still has open tasks waits, and so do its tasks. `log` moves a completed repeating task forward
    /// rather than logging it.
    public func filesToLog(completedBefore before: LocalDate?) -> [Item] {
        liveItems.filter { item in
            let p = item.properties
            guard p.kind == .task || p.kind == .project, p.status.isClosed, !waitsForOpenTasks(item) else { return false }
            guard let before, let completed = p.completedDate else { return true }
            return completed < before
        }.sorted(by: Self.byTitle)
    }

    /// Whether a file waits to be logged: a live Done or Cancelled project that still has open tasks, or one of its tasks.
    public func waitsForOpenTasks(_ item: Item) -> Bool {
        guard let project = item.properties.kind == .project ? item : project(of: item),
              !project.isLogged, project.properties.status.isClosed else { return false }
        return !openTasks(in: project).isEmpty
    }

    /// Logged files that aren't Done or Cancelled any more, as when reopened in another app: logging moves them back.
    public var reopenedLogged: [Item] {
        logged.filter { !$0.properties.status.isClosed }.sorted(by: Self.byTitle)
    }

    /// Logged projects that have live open tasks, as when a task was reopened in another app: they go back as Doing.
    public var loggedProjectsWithOpenTasks: [Item] {
        var seen: Set<String> = []
        return tasks.filter { !$0.properties.status.isClosed }.compactMap { project(of: $0) }
            .filter { $0.isLogged && seen.insert($0.path).inserted }.sorted(by: Self.byTitle)
    }
}
