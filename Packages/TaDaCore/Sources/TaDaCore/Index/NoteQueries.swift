import Foundation

/// A folder in the Notes tree, with the number of notes in it and its subfolders, and its subfolders by name.
public struct FolderNode: Hashable, Sendable, Identifiable {
    /// Relative to the vault, e.g. `Meetings/2026`.
    public var path: String
    public var count: Int
    public var children: [FolderNode]

    public var id: String { path }
    /// The last path segment.
    public var name: String { path.split(separator: "/").last.map(String.init) ?? path }
}

/// The Notes queries. Loose is the vault's top level, written as the folder `""`.
extension VaultIndex {
    /// The folders that hold a note, at any depth, plus `emptyFolders` (from `Vault.emptyFolders()`), as a tree.
    /// Each level is sorted by name, ignoring case.
    public func folderTree(emptyFolders: Set<String> = []) -> [FolderNode] {
        var counts: [String: Int] = [:]
        for folder in emptyFolders { counts[folder] = counts[folder] ?? 0 }
        for note in notes {
            var folder = Vault.folder(of: note.path)
            while !folder.isEmpty {
                counts[folder, default: 0] += 1
                folder = Vault.folder(of: folder)
            }
        }
        for folder in counts.keys {
            var parent = Vault.folder(of: folder)
            while !parent.isEmpty, counts[parent] == nil {
                counts[parent] = 0
                parent = Vault.folder(of: parent)
            }
        }
        let byParent = Dictionary(grouping: counts.keys) { Vault.folder(of: $0) }
        func nodes(under parent: String) -> [FolderNode] {
            (byParent[parent] ?? []).map { FolderNode(path: $0, count: counts[$0] ?? 0, children: nodes(under: $0)) }
                .sorted(by: Self.byName)
        }
        return nodes(under: "")
    }

    /// The notes straight in `folder` (`""` for Loose), not its subfolders, sorted by title.
    public func notes(in folder: String) -> [Item] {
        notes.filter { Vault.folder(of: $0.path) == folder }.sorted(by: Self.byTitle)
    }

    /// The notes at the vault's top level, sorted by title.
    public func looseNotes() -> [Item] { notes(in: "") }

    private static func byName(_ a: FolderNode, _ b: FolderNode) -> Bool {
        let order = a.name.localizedStandardCompare(b.name)
        return order == .orderedSame ? a.path < b.path : order == .orderedAscending
    }
}
