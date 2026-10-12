import Foundation

/// A folder in the Notes tree, with the number of notes in it and its subfolders, and its subfolders by name.
public struct FolderNode: Hashable, Sendable, Identifiable {
    /// Relative to the vault, e.g. `Meetings/2026`.
    public var path: String
    /// The last path segment.
    public var name: String
    public var count: Int
    public var children: [FolderNode]

    public var id: String { path }
}

/// The Notes queries. Loose is the vault's top level, written as the folder `""`.
extension VaultIndex {
    /// The folders that hold a note at any depth, plus `folders` (those known to be on disk, such as
    /// `Vault.emptyFolders()` and the folders that held notes at the last scan) and their parents, as a tree. Each level
    /// is sorted by name, ignoring case.
    public func folderTree(folders: Set<String> = []) -> [FolderNode] {
        var counts: [String: Int] = [:]
        func addParents(of folder: String, count: Int) {
            var folder = folder
            while !folder.isEmpty {
                counts[folder, default: 0] += count
                folder = Vault.folder(of: folder)
            }
        }
        for folder in folders { addParents(of: folder, count: 0) }
        for (folder, paths) in notePathsByFolder { addParents(of: folder, count: paths.count) }
        let byParent = Dictionary(grouping: counts.keys) { Vault.folder(of: $0) }
        func nodes(under parent: String) -> [FolderNode] {
            (byParent[parent] ?? []).map { path in
                FolderNode(path: path, name: String(path.split(separator: "/").last ?? ""), count: counts[path] ?? 0,
                           children: nodes(under: path))
            }.sorted(by: Self.byName)
        }
        return nodes(under: "")
    }

    /// The notes straight in `folder` (`""` for Loose), not its subfolders, sorted by title.
    public func notes(in folder: String) -> [Item] {
        (notePathsByFolder[folder] ?? []).compactMap { items[$0] }.sorted(by: Self.byTitle)
    }

    /// The notes at the vault's top level, sorted by title.
    public func looseNotes() -> [Item] { notes(in: "") }

    private static func byName(_ a: FolderNode, _ b: FolderNode) -> Bool {
        let order = a.name.localizedStandardCompare(b.name)
        return order == .orderedSame ? a.path < b.path : order == .orderedAscending
    }
}
