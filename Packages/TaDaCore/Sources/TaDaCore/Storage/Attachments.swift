import Foundation

/// Attachments are image files that files embed with `![[name.png]]`. Ta Da saves them in `attachments/`; an embed
/// resolves by filename, so they can live anywhere in the folder.
extension Vault {
    public static let attachmentFolder = "attachments"
    public static let imageExtensions: Set<String> = ["avif", "bmp", "gif", "heic", "jpeg", "jpg", "png", "svg", "tif", "tiff", "webp"]

    /// Writes `data` as `attachments/<filename>`, numbering the name if it's taken. Returns the new path.
    public func saveAttachment(_ data: Data, as filename: String) throws -> String {
        let (base, ext) = FileNaming.split(filename)
        let path = Self.attachmentFolder + "/" + FileNaming.filename(for: base, extension: ext, existing: filenames(in: Self.attachmentFolder))
        try CoordinatedFileIO.create(data, at: url(for: path))
        return path
    }

    /// Every image in the folder, most recently changed first. Hidden folders, including `.trash`, are skipped.
    public func attachmentPaths() -> [String] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        guard let files = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        let rootComponents = root.pathComponents.count
        var dated: [(path: String, date: Date)] = []
        for case let url as URL in files where Self.imageExtensions.contains(url.pathExtension.lowercased()) {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.pathComponents.dropFirst(rootComponents).joined(separator: "/")
            dated.append((path, values.contentModificationDate ?? .distantPast))
        }
        return dated.sorted { $0.date != $1.date ? $0.date > $1.date : $0.path < $1.path }.map(\.path)
    }

    /// The image an embed shows: the target as a path, else `attachments/<filename>`, else the first file with that
    /// filename by path, ignoring case. Hidden folders, including `.trash`, are skipped. Nil when there's none.
    public func attachmentPath(for embed: WikiLink) -> String? {
        Self.attachmentPath(for: embed, in: attachmentPaths())
    }

    /// What `![[ ]]` names an image by: its filename, or its path when the filename finds another image first.
    public static func embedTarget(for path: String, in paths: [String]) -> String {
        let name = String(path.split(separator: "/").last ?? "")
        guard let link = WikiLink(inner: name), attachmentPath(for: link, in: paths) != path else { return name }
        return path
    }

    /// The path an image takes when renamed to `name` (sanitised as a title) in its folder, keeping its extension.
    public static func renamedAttachment(_ path: String, to name: String) -> String {
        let folder = folder(of: path)
        let ext = FileNaming.split(String(path.split(separator: "/").last ?? "")).ext
        return (folder.isEmpty ? "" : folder + "/") + FileNaming.sanitise(name) + (ext.isEmpty ? "" : "." + ext)
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
        return matches.first { $0.lowercased() == attachmentFolder + "/" + name } ?? matches.min()
    }
}
