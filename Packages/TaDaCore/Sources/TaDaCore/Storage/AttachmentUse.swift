import Foundation

/// An image in `Ta Da/attachments/`.
public struct Attachment: Hashable, Sendable, Identifiable {
    /// Its vault-relative path, under its real name even when iCloud Drive hasn't downloaded it.
    public var path: String
    /// Its size in bytes; nil for an image that isn't downloaded when the placeholder doesn't record it.
    public var size: Int64?
    /// When it was added to the folder, else created, else last changed; nil when the file system records none.
    public var added: Date?
    /// False while the file is an iCloud Drive placeholder.
    public var isDownloaded: Bool

    public var id: String { path }
    public var name: String { String(path.split(separator: "/").last ?? "") }

    public init(path: String, size: Int64? = nil, added: Date? = nil, isDownloaded: Bool = true) {
        self.path = path
        self.size = size
        self.added = added
        self.isDownloaded = isDownloaded
    }

    /// The bytes `attachments` take, counting an unknown size as 0.
    public static func totalSize(of attachments: [Attachment]) -> Int64 {
        attachments.reduce(0) { $0 + ($1.size ?? 0) }
    }

    /// `attachments` by filename in Finder order: numbers by value, ignoring case.
    public static func byName(_ a: Attachment, _ b: Attachment) -> Bool {
        let order = a.name.localizedStandardCompare(b.name)
        return order == .orderedSame ? a.path < b.path : order == .orderedAscending
    }
}

/// Why an image that no live file embeds can be cleaned up.
public enum CleanUpReason: Hashable, Sendable {
    /// Only logged files embed it.
    case loggedOnly
    /// Only trashed files embed it.
    case trashedOnly
    /// Logged and trashed files embed it.
    case loggedAndTrashed
    /// Nothing embeds it.
    case unused
}

/// Which files embed one image, by state.
public struct AttachmentUse: Hashable, Sendable, Identifiable {
    public var attachment: Attachment
    /// Files outside the Logbook and `.trash/` that embed it, sorted by title.
    public var live: [Item]
    /// Logbook files that embed it, sorted by title.
    public var logged: [Item]
    /// Trashed files that embed it, sorted by title.
    public var trashed: [TrashedItem]

    public var id: String { attachment.path }

    public init(attachment: Attachment, live: [Item] = [], logged: [Item] = [], trashed: [TrashedItem] = []) {
        self.attachment = attachment
        self.live = live
        self.logged = logged
        self.trashed = trashed
    }

    /// Whether a live file embeds it.
    public var isInUse: Bool { !live.isEmpty }

    /// Why it can be cleaned up; nil while it's in use.
    public var cleanUpReason: CleanUpReason? {
        guard live.isEmpty else { return nil }
        switch (logged.isEmpty, trashed.isEmpty) {
        case (false, true): return .loggedOnly
        case (true, false): return .trashedOnly
        case (false, false): return .loggedAndTrashed
        case (true, true): return .unused
        }
    }

    /// The use of each of `attachments`. An embed counts for the image it resolves to among `imagePaths` (from
    /// `Vault.attachmentPaths()`), as `Vault.attachmentPath(for:in:)` finds it.
    public static func uses(of attachments: [Attachment], index: VaultIndex, trashed: [TrashedItem],
                            imagePaths: [String]) -> [AttachmentUse] {
        var pathsByName: [String: [String]] = [:]
        for path in imagePaths { pathsByName[String(path.split(separator: "/").last ?? "").lowercased(), default: []].append(path) }
        // Lowercased embed target → the image it resolves to. Only images with the embed's filename can match.
        var resolved: [String: String?] = [:]
        func images(embedded embeds: [WikiLink]) -> Set<String> {
            Set(embeds.compactMap { embed in
                let key = embed.target.lowercased()
                if let known = resolved[key] { return known }
                let image = embed.attachmentName.flatMap { pathsByName[$0.lowercased()] }.flatMap { Vault.attachmentPath(for: embed, in: $0) }
                resolved[key] = image
                return image
            })
        }
        var live: [String: [Item]] = [:], logged: [String: [Item]] = [:], trashedBy: [String: [TrashedItem]] = [:]
        for item in index.items.values {
            for image in images(embedded: item.embeds) {
                if item.isLogged { logged[image, default: []].append(item) } else { live[image, default: []].append(item) }
            }
        }
        for entry in trashed {
            for image in images(embedded: entry.item.embeds) { trashedBy[image, default: []].append(entry) }
        }
        return attachments.map { attachment in
            AttachmentUse(attachment: attachment,
                          live: (live[attachment.path] ?? []).sorted(by: VaultIndex.byTitle),
                          logged: (logged[attachment.path] ?? []).sorted(by: VaultIndex.byTitle),
                          trashed: (trashedBy[attachment.path] ?? []).sorted { VaultIndex.byTitle($0.item, $1.item) })
        }
    }
}

/// The attachments list: images no live file embeds, then those that one does, each in Finder order by filename.
public struct AttachmentGroups: Sendable {
    /// Clean-up candidates ("Not in open files").
    public var candidates: [AttachmentUse]
    /// Images a live file embeds ("In open files").
    public var inUse: [AttachmentUse]
    /// Markdown files iCloud Drive hasn't downloaded yet, including those in `.trash/`. Images they embed show as
    /// not embedded until they arrive.
    public var pendingFiles: [String]

    public init(_ uses: [AttachmentUse], pendingFiles: [String] = []) {
        self.pendingFiles = pendingFiles
        let sorted = uses.sorted { Attachment.byName($0.attachment, $1.attachment) }
        candidates = sorted.filter { !$0.isInUse }
        inUse = sorted.filter(\.isInUse)
    }

    public var candidatesSize: Int64 { Attachment.totalSize(of: candidates.map(\.attachment)) }
    public var inUseSize: Int64 { Attachment.totalSize(of: inUse.map(\.attachment)) }
    public var totalSize: Int64 { candidatesSize + inUseSize }
}

extension Vault {
    /// The images directly in `Ta Da/attachments/`, in no set order, including iCloud Drive placeholders under their
    /// real names. A placeholder's size is read from its property list. Walks the whole folder; call it off the main
    /// actor.
    public func taDaAttachments() -> [Attachment] {
        taDaAttachments(imagePaths: attachmentPaths())
    }

    /// `taDaAttachments()` with each path spelled as in `imagePaths` (from `attachmentPaths()`), which is the folder's
    /// spelling on disk.
    func taDaAttachments(imagePaths: [String]) -> [Attachment] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .addedToDirectoryDateKey, .creationDateKey, .contentModificationDateKey]
        let folder = url(for: Self.attachmentFolder)
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        let spelled = Dictionary(imagePaths.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var found: [String: Attachment] = [:]
        for url in urls {
            let name = url.lastPathComponent
            let placeholder = Self.placeholderOriginal(name)
            let original = placeholder ?? name
            guard placeholder != nil || !name.hasPrefix("."), Self.isImage(original),
                  let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let size = placeholder == nil ? values.fileSize.map(Int64.init) : Self.placeholderSize(at: url)
            let path = Self.attachmentFolder + "/" + original
            let attachment = Attachment(path: spelled[path.lowercased()] ?? path, size: size,
                                        added: values.addedToDirectoryDate ?? values.creationDate ?? values.contentModificationDate,
                                        isDownloaded: placeholder == nil)
            if found[attachment.path]?.isDownloaded != true { found[attachment.path] = attachment }
        }
        return Array(found.values)
    }

    /// The size an iCloud Drive placeholder records (`NSURLFileSizeKey`); nil when it doesn't.
    static func placeholderSize(at url: URL) -> Int64? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let size = plist["NSURLFileSizeKey"] as? NSNumber else { return nil }
        return size.int64Value
    }

    /// Markdown files iCloud Drive hasn't downloaded yet, by the path they'll have, in the folder and `.trash/`.
    func pendingMarkdownPaths() -> [String] {
        guard let files = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsPackageDescendants]
        ) else { return [] }
        let rootComponents = root.pathComponents.count
        var paths: [String] = []
        for case let url as URL in files where url.lastPathComponent.hasPrefix(".") {
            let components = url.standardizedFileURL.pathComponents.dropFirst(rootComponents)
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if components.joined(separator: "/") != Self.trashFolder { files.skipDescendants() }
                continue
            }
            guard let original = Self.placeholderOriginal(url.lastPathComponent), original.lowercased().hasSuffix(".md") else { continue }
            paths.append((components.dropLast() + [original]).joined(separator: "/"))
        }
        return paths.sorted()
    }

    /// `taDaAttachments()` with how each is used, as `AttachmentGroups` lists them. Walks the whole folder.
    @concurrent public func attachmentGroups(index: VaultIndex, trashed: [TrashedItem]) async -> AttachmentGroups {
        await attachmentGroups(index: index, trashed: trashed, imagePaths: attachmentPaths())
    }

    /// `attachmentGroups(index:trashed:)` with `imagePaths` already read by `attachmentPaths()`, which saves one walk.
    @concurrent public func attachmentGroups(index: VaultIndex, trashed: [TrashedItem], imagePaths: [String]) async -> AttachmentGroups {
        let uses = AttachmentUse.uses(of: taDaAttachments(imagePaths: imagePaths), index: index, trashed: trashed, imagePaths: imagePaths)
        return AttachmentGroups(uses, pendingFiles: pendingMarkdownPaths())
    }
}
