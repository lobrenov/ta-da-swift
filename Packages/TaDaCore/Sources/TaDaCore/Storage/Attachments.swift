import Foundation
import MarkdownEngineSyntax

/// Attachments are image files that files embed with `![[name.png]]`. Ta Da saves them in `Ta Da/attachments/`; an embed
/// resolves by filename, so they can live anywhere in the folder.
extension Vault {
    public static let attachmentFolder = home + "/attachments"
    /// The old layout's attachments folder, which new images' names also avoid.
    public static let legacyAttachmentFolder = "attachments"
    /// The old layout's top-level folders, lowercased: Ta Da made them before `Ta Da/`.
    public static let legacyFolders: Set<String> = ["tasks", "projects", "areas", "attachments"]
    /// The spec's image extensions (`EmbedSyntax`), lowercase.
    public static let imageExtensions = Set(EmbedSyntax.imageExtensions)

    /// Writes `data` as `Ta Da/attachments/<filename>`, numbering the name if it's taken there or in the old
    /// `attachments/`. Returns the new path.
    public func saveAttachment(_ data: Data, as filename: String) throws -> String {
        let taken = filenames(in: Self.attachmentFolder).union(filenames(in: Self.legacyAttachmentFolder))
        let path = Self.attachmentPath(named: filename, avoiding: taken)
        try saveAttachment(data, at: path)
        return path
    }

    /// Writes `data` at `path` (from `attachmentPath(named:avoiding:)`), failing if a file is already there.
    public func saveAttachment(_ data: Data, at path: String) throws {
        try CoordinatedFileIO.create(data, at: url(for: path))
    }

    /// `Ta Da/attachments/<filename>`, numbered if the name is among `taken`, the filenames in `Ta Da/attachments/`.
    public static func attachmentPath(named filename: String, avoiding taken: Set<String>) -> String {
        let (base, ext) = FileNaming.split(filename)
        return attachmentFolder + "/" + FileNaming.filename(for: base, extension: ext, existing: taken)
    }

    /// Every image in the folder, most recently changed first. Hidden folders, including `.trash`, are skipped. An
    /// image iCloud Drive hasn't downloaded yet is listed under its real name, last.
    public func attachmentPaths() -> [String] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey]
        guard let files = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants]
        ) else { return [] }
        let rootComponents = root.pathComponents.count
        var dated: [(path: String, date: Date)] = []
        for case let url as URL in files {
            let values = try? url.resourceValues(forKeys: keys)
            let name = url.lastPathComponent
            if name.hasPrefix(".") {
                if values?.isDirectory == true { files.skipDescendants() }
                guard values?.isRegularFile == true, let original = Self.placeholderOriginal(name), Self.isImage(original) else { continue }
                let folder = url.deletingLastPathComponent().standardizedFileURL.pathComponents.dropFirst(rootComponents)
                dated.append(((folder + [original]).joined(separator: "/"), .distantPast))
            } else if Self.isImage(name), values?.isRegularFile == true {
                let path = url.standardizedFileURL.pathComponents.dropFirst(rootComponents).joined(separator: "/")
                dated.append((path, values?.contentModificationDate ?? .distantPast))
            }
        }
        return dated.sorted { $0.date != $1.date ? $0.date > $1.date : $0.path < $1.path }.map(\.path)
    }

    static func isImage(_ filename: String) -> Bool {
        imageExtensions.contains(FileNaming.split(filename).ext.lowercased())
    }

    /// The image an embed shows: the target as a path, else `Ta Da/attachments/<filename>`, else the old
    /// `attachments/<filename>`, else the first file with that filename by path, ignoring case. Hidden folders, including `.trash`, are skipped. Nil when there's none.
    public func attachmentPath(for embed: WikiLink) -> String? {
        Self.attachmentPath(for: embed, in: attachmentPaths())
    }

    /// What `![[ ]]` names an image by: its filename, or its path when the filename finds another image first.
    public static func embedTarget(for path: String, in paths: [String]) -> String {
        let name = String(path.split(separator: "/").last ?? "")
        guard let link = WikiLink(inner: name), attachmentPath(for: link, in: paths) != path else { return name }
        return path
    }

    /// The path an image takes when renamed to `name` (sanitised as a title, without its extension if typed) in its
    /// folder, keeping its extension.
    public static func renamedAttachment(_ path: String, to name: String) -> String {
        let folder = folder(of: path)
        let ext = FileNaming.split(String(path.split(separator: "/").last ?? "")).ext
        var title = FileNaming.sanitise(name)
        if !ext.isEmpty, title.lowercased().hasSuffix("." + ext.lowercased()) { title = FileNaming.sanitise(String(title.dropLast(ext.count + 1))) }
        return (folder.isEmpty ? "" : folder + "/") + title + (ext.isEmpty ? "" : "." + ext)
    }

    /// Whether another image among `paths` already has `newPath`'s filename, ignoring case and folders.
    public static func attachmentName(of newPath: String, isTakenBesides path: String, in paths: [String]) -> Bool {
        let name = newPath.split(separator: "/").last?.lowercased()
        return paths.contains { $0 != path && $0.split(separator: "/").last?.lowercased() == name }
    }

    /// Moves an image to `newPath` (from `renamedAttachment`). A case-only change is allowed; another existing file
    /// at `newPath` is not.
    public func renameAttachment(_ path: String, to newPath: String) throws {
        guard newPath != path else { return }
        let destination = url(for: newPath)
        if newPath.lowercased() != path.lowercased(),
           FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: destination.path(percentEncoded: false)])
        }
        try CoordinatedFileIO.move(url(for: path), to: destination)
    }

    /// Points each `![[ ]]` in a file's body that shows the image at `path` (as `attachmentPath(for:in:)` finds it
    /// among `paths`) at `newPath`: by filename, or by path where it was written as a path. Anything after `|` stays.
    public static func retargetEmbeds(in text: String, from path: String, to newPath: String, paths: [String]) -> String {
        let split = FrontmatterSplitter.split(text)
        let body = split.body
        let filename = String(newPath.split(separator: "/").last ?? "")
        var result = split.block, copied = body.startIndex
        for (range, link) in BodyScanner.embedTargets(in: body) where attachmentPath(for: link, in: paths) == path {
            result += body[copied..<range.lowerBound] + (link.target.contains("/") ? newPath : filename)
            copied = range.upperBound
        }
        return result + body[copied...]
    }

    /// The image an embed shows, as `attachmentPath(for:)` finds it, among `paths` (from `attachmentPaths()`).
    public static func attachmentPath(for embed: WikiLink, in paths: [String]) -> String? {
        guard let name = embed.attachmentName?.lowercased() else { return nil }
        if embed.target.contains("/"), let path = paths.first(where: { $0.lowercased() == embed.target.lowercased() }) {
            return path
        }
        let matches = paths.filter { $0.split(separator: "/").last?.lowercased() == name }
        return matches.first { $0.lowercased() == attachmentFolder.lowercased() + "/" + name }
            ?? matches.first { $0.lowercased() == legacyAttachmentFolder + "/" + name } ?? matches.min()
    }
}
