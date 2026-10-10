import Foundation

/// The user's chosen folder. Paths are relative to it, e.g. `tasks/Pick a test framework.md`.
/// File work is synchronous apart from `loadIndex()`: call it off the main actor.
public struct Vault: Sendable {
    public let root: URL

    /// New files go here; existing files can live anywhere.
    public static let taskFolder = "tasks"
    public static let projectFolder = "projects"
    public static let areaFolder = "areas"

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    public func url(for path: String) -> URL {
        root.appending(path: path, directoryHint: .notDirectory)
    }

    /// The path of `url` when it's a Markdown file outside hidden folders, as `markdownPaths()` lists them.
    public func path(of url: URL) -> String? {
        let root = root.resolvingSymlinksInPath().pathComponents
        let components = url.resolvingSymlinksInPath().pathComponents
        guard components.count > root.count, components.starts(with: root), url.pathExtension.lowercased() == "md" else { return nil }
        let relative = components.dropFirst(root.count)
        return relative.contains { $0.hasPrefix(".") } ? nil : relative.joined(separator: "/")
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
        modificationDates().keys.sorted()
    }

    /// Every `.md` file (as `markdownPaths()` finds them) and when its contents last changed.
    public func modificationDates() -> [String: Date] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        guard let files = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [:] }
        let rootComponents = root.pathComponents.count
        var dates: [String: Date] = [:]
        for case let url as URL in files where url.pathExtension.lowercased() == "md" {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.pathComponents.dropFirst(rootComponents).joined(separator: "/")
            dates[path] = values.contentModificationDate ?? .distantPast
        }
        return dates
    }

    /// Markdown files and images that iCloud Drive hasn't downloaded yet, by the path they'll have. On iOS they show
    /// as hidden `.Name.md.icloud` placeholders, which the scans skip. Hidden folders are skipped.
    public func placeholderPaths() -> [String] {
        guard let files = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsPackageDescendants]
        ) else { return [] }
        let rootComponents = root.pathComponents.count
        var paths: [String] = []
        for case let url as URL in files where url.lastPathComponent.hasPrefix(".") {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                files.skipDescendants()
                continue
            }
            guard let original = Self.placeholderOriginal(url.lastPathComponent),
                  original.lowercased().hasSuffix(".md") || Self.isImage(original) else { continue }
            let folder = url.deletingLastPathComponent().standardizedFileURL.pathComponents.dropFirst(rootComponents)
            paths.append((folder + [original]).joined(separator: "/"))
        }
        return paths.sorted()
    }

    /// `Name.png` for the placeholder file `.Name.png.icloud`; nil for any other name.
    static func placeholderOriginal(_ name: String) -> String? {
        name.hasPrefix(".") && name.hasSuffix(".icloud") ? String(name.dropFirst().dropLast(".icloud".count)) : nil
    }

    /// Asks iCloud Drive to download each placeholder. Each file joins the scans once it arrives.
    public func downloadPlaceholders() {
        for path in placeholderPaths() {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url(for: path))
        }
    }

    /// Reads and parses every Ta Da file. Unreadable files and other notes are left out.
    @concurrent public func loadIndex() async -> VaultIndex {
        VaultIndex(markdownPaths().compactMap { try? load($0) })
    }

    /// What changed on disk since `known` (from an earlier `changes` or `modificationDates()`).
    /// Changed and new files are reparsed; a file that can't be read right now keeps its old date,
    /// so the next call tries it again. `presenter` is the open file's `FilePresenter`, if one is open.
    public func changes(since known: [String: Date], presenter: FilePresenter? = nil) -> VaultChanges {
        var dates = modificationDates()
        var changed: [String: Item?] = [:]
        for (path, date) in dates where known[path] != date {
            do {
                changed[path] = .some(try load(path, presenter: presenter))
            } catch {
                dates[path] = known[path]
            }
        }
        let removed = known.keys.filter { dates[$0] == nil }.sorted()
        return VaultChanges(dates: dates, changed: changed, removed: removed)
    }

    /// Reads and parses one file; nil when it isn't a Ta Da file. `presenter` is the file's own
    /// `FilePresenter`, if it's open.
    public func load(_ path: String, presenter: FilePresenter? = nil) throws -> Item? {
        Item(parsing: try read(path, presenter: presenter), path: path)
    }

    // MARK: Reading and writing

    /// `presenter` is the file's own `FilePresenter`, if it's open.
    public func read(_ path: String, presenter: FilePresenter? = nil) throws -> String {
        try CoordinatedFileIO.read(url(for: path), presenter: presenter)
    }

    public func write(_ text: String, to path: String) throws {
        try CoordinatedFileIO.write(text, to: url(for: path))
    }

    /// Writes `text` only if the file still holds `expected`, in one coordinated access, so a change made
    /// by another app since Ta Da last read the file is never overwritten.
    /// Returns nil when it wrote, or the file's current text when it didn't. `presenter` is the file's own
    /// `FilePresenter`, if it's open.
    public func write(_ text: String, to path: String, ifUnchangedFrom expected: String,
                      presenter: FilePresenter? = nil) throws -> String? {
        var found: String?
        try CoordinatedFileIO.update(url(for: path), presenter: presenter) { current in
            guard current == expected else {
                found = current
                return current
            }
            return text
        }
        return found
    }

    /// When the file's contents last changed; nil when it can't be read.
    public func modificationDate(of path: String) -> Date? {
        try? url(for: path).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
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

    /// Renames a project's file and relinks each of its tasks; a task that can't be relinked doesn't stop the rest.
    /// Returns the project's new path, its tasks as they now are and the paths of the tasks that couldn't be relinked.
    public func renameProject(at path: String, to title: String, index: VaultIndex) throws
        -> (path: String, relinked: [Item], failed: [String]) {
        guard let project = index[path], project.properties.kind == .project else { return (path, [], []) }
        return try rename(project, to: title, relinking: index.tasks(in: project), key: "project")
    }

    /// Renames an area's file and relinks its projects and its own tasks, as `renameProject` does.
    public func renameArea(at path: String, to title: String, index: VaultIndex) throws
        -> (path: String, relinked: [Item], failed: [String]) {
        guard let area = index[path], area.properties.kind == .area else { return (path, [], []) }
        return try rename(area, to: title, relinking: index.projects(in: area) + index.tasks(in: area), key: "area")
    }

    private func rename(_ parent: Item, to title: String, relinking files: [Item], key: String) throws
        -> (path: String, relinked: [Item], failed: [String]) {
        let newPath = try rename(parent.path, to: title)
        let newTitle = Item.title(ofPath: newPath)
        guard newTitle != parent.title else { return (newPath, [], []) }
        var relinked: [Item] = [], failed: [String] = []
        for file in files {
            do {
                if let item = try relink(file.path, key: key, from: parent.title, to: newTitle) { relinked.append(item) }
            } catch {
                failed.append(file.path)
            }
        }
        return (newPath, relinked, failed)
    }

    /// Points a file's `key` link (`project` or `area`) at `new` if it still links to `old`, in one coordinated read
    /// and write. Returns the file as it now is (nil when it's no longer a Ta Da file).
    @discardableResult
    func relink(_ path: String, key: String, from old: String, to new: String) throws -> Item? {
        try update(path) { text in
            let properties = Item(parsing: text, path: path)?.properties
            let link = key == "area" ? properties?.area : properties?.project
            guard link?.title.lowercased() == old.lowercased() else { return text }
            return FrontmatterEditor.set(key, to: .link(title: new), in: text)
        }
    }

    /// Points the `[[ ]]` links in a file's body that name `old` (ignoring case) at `new`, keeping each link's folder,
    /// `.md`, heading and alias. Embeds, links in code and the frontmatter are untouched.
    public static func retargetLinks(in text: String, from old: String, to new: String) -> String {
        let split = FrontmatterSplitter.split(text)
        let body = split.body
        var result = split.block, copied = body.startIndex
        for (range, link) in BodyScanner.linkTargets(in: body) where link.title.lowercased() == old.lowercased() {
            let target = body[range]
            let folder = target.lastIndex(of: "/").map { target[...$0] } ?? ""
            let ext = target.lowercased().hasSuffix(".md") ? target.suffix(3) : ""
            result += body[copied..<range.lowerBound] + folder + new + ext
            copied = range.upperBound
        }
        return result + body[copied...]
    }

    /// `tasks/Name.md` → `tasks`; `Name.md` → empty.
    public static func folder(of path: String) -> String {
        path.split(separator: "/").dropLast().joined(separator: "/")
    }

    func filenames(in folder: String) -> Set<String> {
        let names = try? FileManager.default.contentsOfDirectory(atPath: url(for: folder).path(percentEncoded: false))
        return Set(names ?? [])
    }
}

/// The result of `Vault.changes(since:)`.
public struct VaultChanges: Sendable {
    /// Modification dates to pass to the next call.
    public var dates: [String: Date]
    /// New or changed files, parsed; nil for files that aren't Ta Da files (any more).
    public var changed: [String: Item?]
    /// Files that are gone.
    public var removed: [String]

    public var isEmpty: Bool { changed.isEmpty && removed.isEmpty }
}
