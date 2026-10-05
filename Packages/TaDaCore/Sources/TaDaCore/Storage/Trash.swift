import Foundation

/// A Ta Da file in the vault's `.trash/` folder.
public struct TrashedItem: Hashable, Sendable, Identifiable {
    /// The trashed file, parsed; its path is in `.trash/`.
    public var item: Item
    /// When the file was moved into `.trash/`; nil when the file system doesn't record it.
    public var deleted: Date?

    public var id: String { item.path }

    /// Trashed tasks whose `project` link names this trashed project, sorted by title.
    public static func tasks(of project: Item, in trashed: [TrashedItem]) -> [TrashedItem] {
        let title = project.title.lowercased()
        return trashed
            .filter { $0.item.properties.kind == .task && $0.item.properties.project?.title.lowercased() == title }
            .sorted { VaultIndex.byTitle($0.item, $1.item) }
    }
}

/// Deleting moves a file into `.trash/` (the folder Obsidian also uses), restoring moves it to `tasks/` or
/// `projects/`, and discarding moves it to the system Trash. A project takes its linked tasks each way.
extension Vault {
    public static let trashFolder = ".trash"

    /// Moves a file into `.trash/`, creating the folder if needed. A project takes the tasks linked to it.
    /// Returns the paths that were moved, the file first.
    public func moveToTrash(_ path: String, index: VaultIndex) throws -> [String] {
        var paths = [path]
        if let project = index[path], project.properties.kind == .project {
            paths += index.tasks(in: project).map(\.path)
        }
        for path in paths { _ = try moveFile(path, into: Self.trashFolder) }
        return paths
    }

    /// The Ta Da files in `.trash/`, most recently deleted first. Other notes there are left out.
    public func trashedItems() -> [TrashedItem] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .addedToDirectoryDateKey]
        guard let files = FileManager.default.enumerator(
            at: url(for: Self.trashFolder), includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        let rootComponents = root.pathComponents.count
        var trashed: [TrashedItem] = []
        for case let url as URL in files where url.pathExtension.lowercased() == "md" {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.pathComponents.dropFirst(rootComponents).joined(separator: "/")
            guard let item = try? load(path) else { continue }
            trashed.append(TrashedItem(item: item, deleted: values.addedToDirectoryDate))
        }
        return trashed.sorted { a, b in
            let (dateA, dateB) = (a.deleted ?? .distantPast, b.deleted ?? .distantPast)
            return dateA != dateB ? dateA > dateB : VaultIndex.byTitle(a.item, b.item)
        }
    }

    /// Moves trashed files back to `tasks/` or `projects/`, numbering names that are taken. A project brings
    /// its trashed tasks back; if its name had to change, their `project` links follow it.
    /// Returns the restored files' new paths.
    public func restore(_ paths: [String]) throws -> [String] {
        let trashed = trashedItems()
        let requested = trashed.filter { paths.contains($0.item.path) }
        let projects = requested.filter { $0.item.properties.kind == .project }
        var handled = Set<String>()
        var restored: [String] = []
        for entry in projects + requested.filter({ $0.item.properties.kind != .project }) {
            guard handled.insert(entry.item.path).inserted else { continue }
            let isProject = entry.item.properties.kind == .project
            let newPath = try moveFile(entry.item.path, into: isProject ? Self.projectFolder : Self.taskFolder)
            restored.append(newPath)
            guard isProject else { continue }
            let newTitle = Item.title(ofPath: newPath)
            for task in TrashedItem.tasks(of: entry.item, in: trashed) where handled.insert(task.item.path).inserted {
                let taskPath = try moveFile(task.item.path, into: Self.taskFolder)
                if newTitle != entry.item.title {
                    try write(FrontmatterEditor.set("project", to: .link(title: newTitle), in: read(taskPath)), to: taskPath)
                }
                restored.append(taskPath)
            }
        }
        return restored
    }

    /// Removes trashed files with `remove` (by default, a move to the system Trash). A project takes its
    /// trashed tasks.
    public func discard(_ paths: [String], remove: (URL) throws -> Void = CoordinatedFileIO.moveToSystemTrash) throws {
        let trashed = trashedItems()
        var all = Set(paths)
        for entry in trashed where paths.contains(entry.item.path) && entry.item.properties.kind == .project {
            all.formUnion(TrashedItem.tasks(of: entry.item, in: trashed).map(\.item.path))
        }
        for path in all.sorted() { try remove(url(for: path)) }
    }

    /// Moves a file into `folder`, creating it if needed, keeping its filename unless that's taken.
    /// Returns the new path.
    private func moveFile(_ path: String, into folder: String) throws -> String {
        let current = String(path.split(separator: "/").last ?? "")
        let existing = filenames(in: folder)
        let isTaken = existing.contains { $0.lowercased() == current.lowercased() }
        let filename = isTaken ? FileNaming.filename(for: Item.title(ofPath: path), existing: existing) : current
        let newPath = folder + "/" + filename
        try FileManager.default.createDirectory(at: root.appending(path: folder, directoryHint: .isDirectory),
                                                withIntermediateDirectories: true)
        try CoordinatedFileIO.move(url(for: path), to: url(for: newPath))
        return newPath
    }
}
