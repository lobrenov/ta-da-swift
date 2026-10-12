import Foundation

/// The result of a write that moved files: the new path, the files whose links were rewritten as they now are, and the
/// files whose links couldn't be rewritten.
public typealias Relinked = (path: String, relinked: [Item], failed: [String])

/// Notes' folders, moving notes, and converting a note to a task, project or area. Body links written with a moved
/// file's or folder's path (`[[Meetings/Ark]]`) follow it; links by title alone follow only a title that changed.
extension Vault {
    /// Creates the folder `<parent>/<name>` (`parent` `""` for the top level), numbering the name if the parent holds it.
    /// Returns its path.
    public func createFolder(named name: String, in parent: String) throws -> String {
        let path = Self.join(parent, FileNaming.folderName(for: name, existing: filenames(in: parent)))
        try FileManager.default.createDirectory(at: root.appending(path: path, directoryHint: .isDirectory),
                                                withIntermediateDirectories: true)
        return path
    }

    /// Renames a folder in place, numbering the name if the parent holds it, and rewrites links written with its path.
    /// Returns the folder's new path (unchanged if the name is the same).
    public func renameFolder(_ path: String, to name: String, index: VaultIndex) throws -> Relinked {
        let parent = Self.folder(of: path), current = String(path.split(separator: "/").last ?? "")
        let name = FileNaming.folderName(for: name, existing: filenames(in: parent).subtracting([current]))
        guard name != current else { return (path, [], []) }
        let newPath = Self.join(parent, name)
        try CoordinatedFileIO.move(root.appending(path: path, directoryHint: .isDirectory),
                                   to: root.appending(path: newPath, directoryHint: .isDirectory))
        let moved = { (file: String) in file.hasPrefix(path + "/") ? newPath + file.dropFirst(path.count) : file }
        let (relinked, failed) = rewriteLinks(in: index, moved: moved) { target in
            target.range(of: path + "/", options: [.anchored, .caseInsensitive]).map { newPath + "/" + target[$0.upperBound...] }
        }
        return (newPath, relinked, failed)
    }

    /// Moves a folder whole into `.trash/`, keeping its parent folders there and numbering its name if it's taken.
    /// Returns its path in `.trash/`.
    public func trashFolder(_ path: String) throws -> String {
        let parent = Self.join(Self.trashFolder, Self.folder(of: path))
        let name = FileNaming.folderName(for: String(path.split(separator: "/").last ?? ""), existing: filenames(in: parent))
        let newPath = Self.join(parent, name)
        try FileManager.default.createDirectory(at: root.appending(path: parent, directoryHint: .isDirectory),
                                                withIntermediateDirectories: true)
        try CoordinatedFileIO.move(root.appending(path: path, directoryHint: .isDirectory),
                                   to: root.appending(path: newPath, directoryHint: .isDirectory))
        return newPath
    }

    /// Moves a note into `folder` (`""` for the top level), numbering its name if it's taken there, and rewrites links
    /// to it. Returns its new path.
    public func moveNote(_ path: String, to folder: String, index: VaultIndex) throws -> Relinked {
        guard folder != Self.folder(of: path) else { return (path, [], []) }
        return try move(path, into: folder, index: index)
    }

    /// Converts a note to a task, project or area: splices the keys in (`NoteConversion.text`), then moves the file to
    /// `tasks/`, `projects/` or `areas/`, numbering a name that's taken there or, for a project, by another project, logged
    /// or not; links to it follow. Returns its new path.
    public func convert(_ path: String, to kind: Item.Kind, status: Status = .notStarted, parent: Parent? = nil,
                        index: VaultIndex, today: LocalDate) throws -> Relinked {
        guard kind != .note, index[path]?.properties.kind == .note else { return (path, [], []) }
        _ = try update(path) { NoteConversion.text($0, to: kind, status: status, parent: parent, today: today) }
        let folder = kind == .area ? Self.areaFolder : kind == .project ? Self.projectFolder : Self.taskFolder
        return try move(path, into: folder, taken: kind == .project ? index.projectFilenames() : [], index: index)
    }

    /// Moves a file and points the links to it at its new path, and at its new title if that changed and its old title
    /// found it.
    private func move(_ path: String, into folder: String, taken: Set<String> = [], index: VaultIndex) throws -> Relinked {
        let newPath = try moveFile(path, into: folder, taken: taken)
        let (old, new) = (Self.bare(path), Self.bare(newPath))
        let oldTitle = Item.title(ofPath: path), newTitle = Item.title(ofPath: newPath)
        let titleFollows = oldTitle != newTitle && index.items(titled: oldTitle).first?.path == path
        let (relinked, failed) = rewriteLinks(in: index, moved: { $0 == path ? newPath : $0 }) { target in
            let ext = target.lowercased().hasSuffix(".md") ? String(target.suffix(3)) : ""
            let bare = target.dropLast(ext.count)
            if bare.contains("/") {
                return bare.compare(old, options: .caseInsensitive) == .orderedSame ? new + ext : nil
            }
            return titleFollows && bare.compare(oldTitle, options: .caseInsensitive) == .orderedSame ? newTitle + ext : nil
        }
        return (newPath, relinked, failed)
    }

    /// Rewrites the body links that `transform` gives a new target, in every file in `index` that has one; `moved` gives
    /// a file's path now. A file that can't be rewritten doesn't stop the rest.
    private func rewriteLinks(in index: VaultIndex, moved: (String) -> String,
                              _ transform: (Substring) -> String?) -> (relinked: [Item], failed: [String]) {
        var relinked: [Item] = [], failed: [String] = []
        for item in index.items.values.sorted(by: { $0.path < $1.path })
        where item.links.contains(where: { transform(Substring($0.target)) != nil }) {
            let path = moved(item.path)
            do {
                if let item = try update(path, { Self.rewriteLinkTargets(in: $0, transform) }) { relinked.append(item) }
            } catch {
                failed.append(path)
            }
        }
        return (relinked, failed)
    }

    /// Replaces the target of each `[[ ]]` link in the body that `transform` gives a new one, keeping its heading and
    /// alias. Embeds, links in code and the frontmatter are untouched.
    static func rewriteLinkTargets(in text: String, _ transform: (Substring) -> String?) -> String {
        let split = FrontmatterSplitter.split(text)
        let body = split.body
        var result = split.block, copied = body.startIndex
        for (range, _) in BodyScanner.linkTargets(in: body) {
            guard let target = transform(body[range]) else { continue }
            result += body[copied..<range.lowerBound] + target
            copied = range.upperBound
        }
        return result + body[copied...]
    }

    /// A path without `.md`.
    private static func bare(_ path: String) -> String {
        path.lowercased().hasSuffix(".md") ? String(path.dropLast(3)) : path
    }
}
