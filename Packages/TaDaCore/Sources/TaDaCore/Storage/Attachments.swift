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

    /// The image an embed shows: the target as a path, else `attachments/<filename>`, else the first file with that
    /// filename by path, ignoring case. Hidden folders, including `.trash`, are skipped. Nil when there's none.
    public func attachmentPath(for embed: WikiLink) -> String? {
        guard let name = embed.attachmentName else { return nil }
        let exists = { (path: String) in FileManager.default.fileExists(atPath: self.url(for: path).path(percentEncoded: false)) }
        if embed.target.contains("/"), exists(embed.target) { return embed.target }
        if let match = filenames(in: Self.attachmentFolder).first(where: { $0.lowercased() == name.lowercased() }) {
            return Self.attachmentFolder + "/" + match
        }
        guard let files = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }
        let rootComponents = root.pathComponents.count
        var paths: [String] = []
        for case let url as URL in files where url.lastPathComponent.lowercased() == name.lowercased() {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            paths.append(url.standardizedFileURL.pathComponents.dropFirst(rootComponents).joined(separator: "/"))
        }
        return paths.min()
    }
}
