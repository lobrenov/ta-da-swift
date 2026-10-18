import Foundation

/// Moving a vault from the old layout: the top-level `tasks/`, `projects/`, `areas/`, `attachments/` and `.logbook/` go
/// into their folders in `Ta Da/`. Body links and embeds written with a moved file's path follow it.
extension Vault {
    /// The result of `moveIntoHome(index:)`: each moved file's new path by its old one, the files whose links or embeds
    /// were rewritten as they now are, and the files whose links couldn't be rewritten.
    public typealias MovedIntoHome = (moved: [String: String], relinked: [Item], failed: [String])

    /// The old layout's top-level folders that hold a file (iCloud Drive placeholders count), each with the folder in
    /// `Ta Da/` it moves to, sorted by name.
    public func oldLayoutFolders() -> [(from: String, to: String)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))) ?? []
        return names.sorted().compactMap { name -> (from: String, to: String)? in
            let to: String
            if name == Self.legacyLogbookFolder {
                to = Self.logbookFolder
            } else if Self.legacyFolders.contains(name.lowercased()) {
                to = Self.join(Self.home, name.lowercased())
            } else {
                return nil
            }
            guard folderExists(name), !files(under: name).isEmpty else { return nil }
            return (name, to)
        }
    }

    /// Moves each of `oldLayoutFolders()` into `Ta Da/`: the whole folder when its destination doesn't exist, else file by
    /// file, numbering names taken there. A file already gone (another device moved it) is skipped, and old folders left
    /// with no files are removed. Then body links and embeds written with an old path point at the new one, links by
    /// title follow a numbered file whose old title found it, and embeds by filename follow a numbered image.
    public func moveIntoHome(index: VaultIndex) throws -> MovedIntoHome {
        let images = attachmentPaths()
        var moved: [String: String] = [:]
        var firstError: (any Error)?
        for (from, to) in oldLayoutFolders() {
            let paths = files(under: from)
            if !folderExists(to), (try? moveFolder(from, to: to)) != nil {
                for path in paths { moved[path] = to + path.dropFirst(from.count) }
                continue
            }
            for path in paths {
                let subfolder = String(Self.folder(of: path).dropFirst(from.count).drop { $0 == "/" })
                let folder = subfolder.isEmpty ? to : Self.join(to, subfolder)
                do {
                    moved[path] = try moveFile(path, into: folder)
                } catch where FileManager.default.fileExists(atPath: url(for: path).path(percentEncoded: false)) {
                    firstError = firstError ?? error
                } catch {}
            }
            removeIfEmpty(from)
        }
        if let firstError, moved.isEmpty { throw firstError }
        let (relinked, failed) = relinkMoved(moved, index: index, images: images)
        return (moved, relinked, failed)
    }

    /// Moves the folder `from` to `to`, which doesn't exist, creating `to`'s parent.
    private func moveFolder(_ from: String, to: String) throws {
        try FileManager.default.createDirectory(at: folderURL(Self.folder(of: to)), withIntermediateDirectories: true)
        try CoordinatedFileIO.move(folderURL(from), to: folderURL(to))
    }

    /// The files under `folder` at any depth, iCloud Drive placeholders by the path they'll have. Other hidden files and
    /// folders are left out.
    private func files(under folder: String) -> [String] {
        guard let entries = FileManager.default.enumerator(
            at: folderURL(folder), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsPackageDescendants]
        ) else { return [] }
        let rootComponents = root.pathComponents.count
        var paths: [String] = []
        for case let url as URL in entries {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            var name = url.lastPathComponent
            if name.hasPrefix(".") {
                if isDirectory { entries.skipDescendants() }
                guard !isDirectory, let original = Self.placeholderOriginal(name) else { continue }
                name = original
            } else if isDirectory {
                continue
            }
            let parent = url.deletingLastPathComponent().standardizedFileURL.pathComponents.dropFirst(rootComponents)
            paths.append((parent + [name]).joined(separator: "/"))
        }
        return paths.sorted()
    }

    /// Removes `folder` when nothing but `.DS_Store` files and folders holding nothing else are left in it.
    private func removeIfEmpty(_ folder: String) {
        let manager = FileManager.default
        guard let entries = manager.enumerator(at: folderURL(folder), includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for case let url as URL in entries
        where url.lastPathComponent != ".DS_Store" && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
            return
        }
        try? manager.removeItem(at: folderURL(folder))
    }

    /// Rewrites the body links and embeds that named a moved file, in every file of `index` (at its path now). `images`
    /// are the image paths before the move. A file that can't be rewritten doesn't stop the rest.
    private func relinkMoved(_ moved: [String: String], index: VaultIndex, images: [String]) -> (relinked: [Item], failed: [String]) {
        var notes: [String: String] = [:], titles: [String: String] = [:]
        for (old, new) in moved where old.lowercased().hasSuffix(".md") {
            notes[String(old.dropLast(3)).lowercased()] = String(new.dropLast(3))
            let title = Item.title(ofPath: old)
            if Item.title(ofPath: new) != title, index.items(titled: title).first?.path == old {
                titles[title.lowercased()] = Item.title(ofPath: new)
            }
        }
        let movedImages = Dictionary(moved.filter { Self.isImage($0.key) }.map { ($0.key.lowercased(), $0.value) }) { a, _ in a }
        let link = { (target: Substring) -> String? in
            let ext = target.lowercased().hasSuffix(".md") ? String(target.suffix(3)) : ""
            let bare = target.dropLast(ext.count).lowercased()
            return (bare.contains("/") ? notes[bare] : titles[bare]).map { $0 + ext }
        }
        let embed = { (target: Substring, image: WikiLink) -> String? in
            if target.contains("/") { return movedImages[target.lowercased()] }
            guard let old = Self.attachmentPath(for: image, in: images), let new = moved[old],
                  new.split(separator: "/").last != old.split(separator: "/").last else { return nil }
            return String(new.split(separator: "/").last ?? "")
        }
        var relinked: [Item] = [], failed: [String] = []
        for item in index.items.values.sorted(by: { $0.path < $1.path })
        where item.links.contains(where: { link(Substring($0.target)) != nil })
            || item.embeds.contains(where: { embed(Substring($0.target), $0) != nil }) {
            let path = moved[item.path] ?? item.path
            do {
                if let item = try update(path, { Self.rewriteEmbedTargets(in: Self.rewriteLinkTargets(in: $0, link), embed) }) {
                    relinked.append(item)
                }
            } catch {
                failed.append(path)
            }
        }
        return (relinked, failed)
    }

    /// Replaces the target of each `![[ ]]` in the body that `transform` gives a new one, keeping anything after `|`.
    /// Links, embeds in code and the frontmatter are untouched.
    static func rewriteEmbedTargets(in text: String, _ transform: (Substring, WikiLink) -> String?) -> String {
        let split = FrontmatterSplitter.split(text)
        let body = split.body
        var result = split.block, copied = body.startIndex
        for (range, link) in BodyScanner.embedTargets(in: body) {
            guard let target = transform(body[range], link) else { continue }
            result += body[copied..<range.lowerBound] + target
            copied = range.upperBound
        }
        return result + body[copied...]
    }
}
