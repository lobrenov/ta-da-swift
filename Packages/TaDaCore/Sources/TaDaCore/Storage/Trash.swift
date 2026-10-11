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

    /// Trashed projects whose `area` link names this trashed area, and trashed tasks filed under the area or those
    /// projects, each sorted by title.
    public static func contents(of area: Item, in trashed: [TrashedItem]) -> (projects: [TrashedItem], tasks: [TrashedItem]) {
        let title = area.title.lowercased()
        let filed = trashed.filter { $0.item.properties.area?.title.lowercased() == title }
            .sorted { VaultIndex.byTitle($0.item, $1.item) }
        let projects = filed.filter { $0.item.properties.kind == .project }
        let tasks = filed.filter { $0.item.properties.kind == .task } + projects.flatMap { Self.tasks(of: $0.item, in: trashed) }
        return (projects, tasks)
    }
}

/// An image in `.trash/attachments/`.
public struct TrashedAttachment: Hashable, Sendable, Identifiable {
    /// Its path in `.trash/attachments/`.
    public var path: String
    /// When the image was moved into `.trash/attachments/`; nil when the file system doesn't record it.
    public var deleted: Date?

    public var id: String { path }
    public var name: String { String(path.split(separator: "/").last ?? "") }

    /// The trashed image an embed of `name` in a file trashed at `deleted` went with: the image named `name`, or that name
    /// numbered (`front 2.jpg`, when `front.jpg` was taken in `.trash/attachments/`), whichever was trashed nearest
    /// `deleted`; the exact name wins a tie. Nil when there's none.
    public static func attachment(named name: String, trashedAt deleted: Date?, in trashed: [TrashedAttachment]) -> TrashedAttachment? {
        let name = name.lowercased(), (base, ext) = FileNaming.split(name)
        let candidates = trashed.filter { image in
            let (candidateBase, candidateExt) = FileNaming.split(image.name.lowercased())
            return image.name.lowercased() == name
                || candidateExt == ext && candidateBase.hasPrefix(base + " ") && Int(candidateBase.dropFirst(base.count + 1)) != nil
        }.sorted { ($0.name.lowercased() == name ? 0 : 1, $0.name) < ($1.name.lowercased() == name ? 0 : 1, $1.name) }
        let distance = { (image: TrashedAttachment) in
            guard let deleted, let date = image.deleted else { return Double.infinity }
            return abs(date.timeIntervalSince(deleted))
        }
        return candidates.min { distance($0) < distance($1) }
    }

    /// Trashed images that go with `files`, sorted by name: those their embeds went with, less any that a file in
    /// `others` (all the trashed files) not in `files` embeds, or that `live` names (the lowercased image filenames
    /// that files outside `.trash/` embed).
    public static func attachments(of files: [TrashedItem], in trashed: [TrashedAttachment], others: [TrashedItem],
                                   live: Set<String>) -> [TrashedAttachment] {
        func embedded(by files: [TrashedItem]) -> Set<TrashedAttachment> {
            Set(files.flatMap { file in
                file.item.embeds.compactMap { $0.attachmentName }.compactMap { attachment(named: $0, trashedAt: file.deleted, in: trashed) }
            })
        }
        let going = Set(files.map(\.id))
        let kept = embedded(by: others.filter { !going.contains($0.id) })
        return embedded(by: files).subtracting(kept).filter { !live.contains($0.name.lowercased()) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Some trashed files couldn't be removed; the rest were.
public struct DiscardError: LocalizedError {
    public let failed: [String]
    public let firstError: any Error

    public var errorDescription: String? {
        "\(failed.count) \(failed.count == 1 ? "file wasn’t" : "files weren’t") removed: \(firstError.localizedDescription)"
    }
}

/// Deleting moves a file into `.trash/` (the folder Obsidian also uses), restoring moves it to `tasks/`, `projects/` or
/// `areas/`, and discarding moves it to the system Trash (or deletes it where that isn't supported). Deleting and
/// discarding take a project's tasks, and an area's projects and tasks; restoring brings back a file's parents.
/// Images go to `.trash/attachments/` and back to `attachments/`; a trashed file's embedded images that are in
/// `.trash/attachments/` are restored with it, and discarded with it unless another file embeds them.
extension Vault {
    public static let trashFolder = ".trash"
    public static let trashedAttachmentFolder = ".trash/attachments"

    /// Moves a file into `.trash/`, creating the folder if needed. A project takes the tasks linked to it; an area
    /// takes its projects, their tasks and its own tasks. Returns the paths that were moved, the file first.
    public func moveToTrash(_ path: String, index: VaultIndex) throws -> [String] {
        var paths = [path]
        if let item = index[path] {
            switch item.properties.kind {
            case .project: paths += index.tasks(in: item).map(\.path)
            case .area: paths += index.projects(in: item).map(\.path) + index.allTasks(in: item).map(\.path)
            case .task: break
            }
        }
        for path in paths { _ = try moveFile(path, into: Self.trashFolder) }
        return paths
    }

    /// Moves images into `.trash/attachments/`, creating the folder if needed and numbering names that are taken there.
    /// Returns their new paths.
    public func moveAttachmentsToTrash(_ paths: [String]) throws -> [String] {
        try paths.map { try moveFile($0, into: Self.trashedAttachmentFolder) }
    }

    /// The images in `.trash/attachments/`, most recently deleted first. Other files are left out.
    public func trashedAttachments() -> [TrashedAttachment] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .addedToDirectoryDateKey]
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url(for: Self.trashedAttachmentFolder).path(percentEncoded: false))) ?? []
        var trashed: [TrashedAttachment] = []
        for name in names where !name.hasPrefix(".") && Self.imageExtensions.contains(FileNaming.split(name).ext.lowercased()) {
            let path = Self.trashedAttachmentFolder + "/" + name
            guard let values = try? url(for: path).resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            trashed.append(TrashedAttachment(path: path, deleted: values.addedToDirectoryDate))
        }
        return trashed.sorted { a, b in
            let (dateA, dateB) = (a.deleted ?? .distantPast, b.deleted ?? .distantPast)
            return dateA != dateB ? dateA > dateB : a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// The Ta Da files in `.trash/`, most recently deleted first. Other notes and hidden files are left out.
    public func trashedItems() -> [TrashedItem] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .addedToDirectoryDateKey]
        // Not `.skipsHiddenFiles`: in iCloud Drive it finds nothing inside `.trash`. Hidden files are skipped below.
        guard let files = FileManager.default.enumerator(
            at: url(for: Self.trashFolder), includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants]
        ) else { return [] }
        let rootComponents = root.pathComponents.count
        var trashed: [TrashedItem] = []
        for case let url as URL in files where url.pathExtension.lowercased() == "md" {
            let path = url.standardizedFileURL.pathComponents.dropFirst(rootComponents)
            guard !path.dropFirst().contains(where: { $0.hasPrefix(".") }) else { continue }
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true,
                  let item = try? load(path.joined(separator: "/")) else { continue }
            trashed.append(TrashedItem(item: item, deleted: values.addedToDirectoryDate))
        }
        return trashed.sorted { a, b in
            let (dateA, dateB) = (a.deleted ?? .distantPast, b.deleted ?? .distantPast)
            return dateA != dateB ? dateA > dateB : VaultIndex.byTitle(a.item, b.item)
        }
    }

    /// Moves trashed files back to `tasks/`, `projects/` or `areas/`, numbering names that are taken. Each brings back
    /// its parents: a task its project and that project's area, or its area; a project its area. A parent that isn't
    /// in the vault (outside `.logbook/`) or `.trash/` is created by name. When a parent's name had to change, the link follows it.
    /// Created files get `today` as their `createdDate`. `paths` can name trashed images too; each restored file brings
    /// back the trashed images it embeds, to `attachments/`, and its embeds follow an image whose name or folder
    /// changed. Returns the paths of the restored and created files, parents first, then the images.
    public func restore(_ paths: [String], index: VaultIndex, today: LocalDate) throws -> [String] {
        let trashed = trashedItems()
        var restored: [String] = []
        // The restored files, with their trashed entries.
        var brought: [(path: String, entry: TrashedItem)] = []
        // Trashed path → the title it was restored under.
        var titles: [String: String] = [:]

        /// Restores a trashed file after its parent; returns its title in the vault.
        func bringBack(_ entry: TrashedItem) throws -> String {
            if let title = titles[entry.item.path] { return title }
            let properties = entry.item.properties
            let parent: Parent? = properties.project.map { .project($0.title) } ?? properties.area.map { .area($0.title) }
            let parentTitle = try parent.map { try bringBack($0) }
            let kind = properties.kind
            let path = try moveFile(entry.item.path, into: kind == .area ? Self.areaFolder : kind == .project ? Self.projectFolder : Self.taskFolder)
            if let parent, let parentTitle, parentTitle != parent.title {
                try relink(path, key: parent.key, from: parent.title, to: parentTitle)
            }
            restored.append(path)
            brought.append((path, entry))
            titles[entry.item.path] = Item.title(ofPath: path)
            return Item.title(ofPath: path)
        }

        /// The title of `parent` in the vault: as it is, restored from `.trash/`, or created.
        func bringBack(_ parent: Parent) throws -> String {
            let kind: Item.Kind = if case .project = parent { .project } else { .area }
            let matches = { (item: Item) in item.properties.kind == kind && item.title.lowercased() == parent.title.lowercased() }
            if index.items(titled: parent.title).contains(where: { matches($0) && !$0.isLogged }) { return parent.title }
            if let entry = trashed.first(where: { matches($0.item) }) { return try bringBack(entry) }
            let folder = kind == .project ? Self.projectFolder : Self.areaFolder
            let text = kind == .project ? NewFile.project(today: today) : NewFile.area(today: today)
            let path = try create(text, in: folder, title: parent.title)
            restored.append(path)
            return Item.title(ofPath: path)
        }

        for entry in trashed where paths.contains(entry.item.path) { _ = try bringBack(entry) }
        let images = trashedAttachments()
        // Trashed image path → restored path.
        var movedImages: [String: String] = [:]
        func bringBack(_ image: TrashedAttachment) throws {
            guard movedImages[image.path] == nil else { return }
            let path = try moveFile(image.path, into: Self.attachmentFolder)
            movedImages[image.path] = path
            restored.append(path)
        }
        func trashedImage(for embed: WikiLink, in entry: TrashedItem) -> TrashedAttachment? {
            embed.attachmentName.flatMap { TrashedAttachment.attachment(named: $0, trashedAt: entry.deleted, in: images) }
        }
        for (_, entry) in brought {
            for embed in entry.item.embeds {
                if let image = trashedImage(for: embed, in: entry) { try bringBack(image) }
            }
        }
        for image in images where paths.contains(image.path) { try bringBack(image) }
        let live = attachmentPaths()
        for (path, entry) in brought where !movedImages.isEmpty {
            try update(path) { text in
                let split = FrontmatterSplitter.split(text)
                let body = split.body
                var result = split.block, copied = body.startIndex
                for (range, link) in BodyScanner.embedTargets(in: body) {
                    guard let moved = trashedImage(for: link, in: entry).flatMap({ movedImages[$0.path] }),
                          Self.attachmentPath(for: link, in: live) != moved else { continue }
                    result += body[copied..<range.lowerBound] + Self.embedTarget(for: moved, in: live)
                    copied = range.upperBound
                }
                return result + body[copied...]
            }
        }
        return restored
    }

    /// Removes trashed files with `remove` (by default, a move to the system Trash, or a delete where that isn't
    /// supported). A project takes its trashed tasks; an area its trashed projects, their tasks and its own tasks. `paths`
    /// can name trashed images too, and the files take the trashed images they embed, except those that a file staying
    /// in `.trash/` or one in `index` (the files outside it) embeds. A file that can't be removed doesn't stop the others; afterwards it throws `DiscardError` naming the ones that failed.
    public func discard(_ paths: [String], index: VaultIndex,
                        remove: (URL) throws -> Void = CoordinatedFileIO.moveToSystemTrash) throws {
        let trashed = trashedItems()
        var all = Set(paths)
        for entry in trashed where paths.contains(entry.item.path) {
            switch entry.item.properties.kind {
            case .project: all.formUnion(TrashedItem.tasks(of: entry.item, in: trashed).map(\.item.path))
            case .area:
                let contents = TrashedItem.contents(of: entry.item, in: trashed)
                all.formUnion((contents.projects + contents.tasks).map(\.item.path))
            case .task: break
            }
        }
        let live = Set(index.items.values.flatMap(\.embeds).compactMap { $0.attachmentName?.lowercased() })
        for image in TrashedAttachment.attachments(of: trashed.filter { all.contains($0.item.path) }, in: trashedAttachments(),
                                                   others: trashed, live: live) {
            all.insert(image.path)
        }
        var failed: [String] = []
        var firstError: (any Error)?
        for path in all.sorted() {
            do { try remove(url(for: path)) } catch {
                failed.append(path)
                firstError = firstError ?? error
            }
        }
        if let firstError { throw DiscardError(failed: failed, firstError: firstError) }
    }

    /// Moves a file into `folder`, creating it if needed, keeping its filename unless that's taken there or among
    /// `taken`. Returns the new path.
    func moveFile(_ path: String, into folder: String, taken: Set<String> = []) throws -> String {
        let current = String(path.split(separator: "/").last ?? "")
        let existing = filenames(in: folder).union(taken)
        let isTaken = existing.contains { $0.lowercased() == current.lowercased() }
        let (base, ext) = FileNaming.split(current)
        let filename = isTaken ? FileNaming.filename(for: base, extension: ext, existing: existing) : current
        let newPath = folder + "/" + filename
        try FileManager.default.createDirectory(at: root.appending(path: folder, directoryHint: .isDirectory),
                                                withIntermediateDirectories: true)
        try CoordinatedFileIO.move(url(for: path), to: url(for: newPath))
        return newPath
    }
}
