import Foundation

/// The user's chosen folder. Paths are relative to it, e.g. `tasks/Pick a test framework.md`.
/// File work is synchronous apart from `loadIndex()`: call it off the main actor.
public struct Vault: Sendable {
    public let root: URL

    /// New files go here; existing files can live anywhere.
    public static let taskFolder = "tasks"
    public static let projectFolder = "projects"

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    public func url(for path: String) -> URL {
        root.appending(path: path, directoryHint: .notDirectory)
    }

    // MARK: Bookmarks

    /// A bookmark that keeps access to a user-picked folder across launches.
    public static func bookmark(for folder: URL) throws -> Data {
        try folder.bookmarkData(options: bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// The folder a bookmark points at, plus a fresh bookmark to save when the old one went stale
    /// (the folder was moved or renamed). The caller starts and stops security-scoped access.
    public static func resolve(_ bookmark: Data) throws -> (folder: URL, refreshed: Data?) {
        var isStale = false
        let folder = try URL(resolvingBookmarkData: bookmark, options: resolveOptions, relativeTo: nil, bookmarkDataIsStale: &isStale)
        guard isStale else { return (folder, nil) }
        let didStart = folder.startAccessingSecurityScopedResource()
        defer { if didStart { folder.stopAccessingSecurityScopedResource() } }
        return (folder, try self.bookmark(for: folder))
    }

    #if os(macOS)
    private static let bookmarkOptions: URL.BookmarkCreationOptions = .withSecurityScope
    private static let resolveOptions: URL.BookmarkResolutionOptions = .withSecurityScope
    #else
    private static let bookmarkOptions: URL.BookmarkCreationOptions = []
    private static let resolveOptions: URL.BookmarkResolutionOptions = []
    #endif

    // MARK: Scanning

    /// Every `.md` file, recursively. Hidden files and folders (including `.obsidian` and `.trash`)
    /// and packages are skipped. Sorted for a stable order.
    public func markdownPaths() -> [String] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let files = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        let rootComponents = root.pathComponents.count
        var paths: [String] = []
        for case let url as URL in files where url.pathExtension.lowercased() == "md" {
            guard (try? url.resourceValues(forKeys: Set(keys)))?.isRegularFile == true else { continue }
            paths.append(url.standardizedFileURL.pathComponents.dropFirst(rootComponents).joined(separator: "/"))
        }
        return paths.sorted()
    }

    /// Reads and parses every Ta Da file. Unreadable files and other notes are left out.
    @concurrent public func loadIndex() async -> VaultIndex {
        VaultIndex(markdownPaths().compactMap { try? load($0) })
    }

    /// Reads and parses one file; nil when it isn't a Ta Da file.
    public func load(_ path: String) throws -> Item? {
        Item(parsing: try read(path), path: path)
    }

    // MARK: Reading and writing

    public func read(_ path: String) throws -> String {
        try CoordinatedFileIO.read(url(for: path))
    }

    public func write(_ text: String, to path: String) throws {
        try CoordinatedFileIO.write(text, to: url(for: path))
    }

    /// Changes one file in a single coordinated read and write, and returns it reparsed
    /// (nil when it's no longer a Ta Da file).
    public func update(_ path: String, _ transform: (String) throws -> String) throws -> Item? {
        Item(parsing: try CoordinatedFileIO.update(url(for: path), transform), path: path)
    }

    /// Creates `<folder>/<title>.md`, numbering the name if it's taken. Returns the new path.
    public func create(_ text: String, in folder: String, title: String) throws -> String {
        let path = (folder.isEmpty ? "" : folder + "/") + FileNaming.filename(for: title, existing: filenames(in: folder))
        try CoordinatedFileIO.create(text, at: url(for: path))
        return path
    }

    /// Renames a file in place from a new title. Returns the new path (unchanged if the name is the same).
    public func rename(_ path: String, to title: String) throws -> String {
        let folder = Self.folder(of: path)
        let current = String(path.split(separator: "/").last ?? "")
        let filename = FileNaming.filename(for: title, existing: filenames(in: folder).subtracting([current]))
        guard filename != current else { return path }
        let newPath = (folder.isEmpty ? "" : folder + "/") + filename
        try CoordinatedFileIO.move(url(for: path), to: url(for: newPath))
        return newPath
    }

    /// Renames a project's file and rewrites the `project:` link in each of its tasks.
    /// Returns the project's new path and the paths of the tasks that were rewritten.
    public func renameProject(at path: String, to title: String, index: VaultIndex) throws -> (path: String, relinked: [String]) {
        guard let project = index[path], project.properties.kind == .project else { return (path, []) }
        let tasks = index.tasks(in: project)
        let newPath = try rename(path, to: title)
        let newTitle = Item.title(ofPath: newPath)
        guard newTitle != project.title else { return (newPath, []) }
        for task in tasks {
            let text = try read(task.path)
            try write(FrontmatterEditor.set("project", to: .link(title: newTitle), in: text), to: task.path)
        }
        return (newPath, tasks.map(\.path))
    }

    private static func folder(of path: String) -> String {
        path.split(separator: "/").dropLast().joined(separator: "/")
    }

    private func filenames(in folder: String) -> Set<String> {
        let names = try? FileManager.default.contentsOfDirectory(atPath: url(for: folder).path(percentEncoded: false))
        return Set(names ?? [])
    }
}
