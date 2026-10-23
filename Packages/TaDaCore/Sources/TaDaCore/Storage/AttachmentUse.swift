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
        var trashedByImage: [String: [TrashedItem]] = [:]
        for entry in trashed.sorted(by: { VaultIndex.byTitle($0.item, $1.item) }) {
            let images = Set(entry.item.embeds.compactMap { Vault.attachmentPath(for: $0, in: imagePaths) })
            for image in images { trashedByImage[image, default: []].append(entry) }
        }
        return attachments.map { attachment in
            let embedders = index.embedders(ofAttachment: attachment.path, among: imagePaths).map(\.item)
            return AttachmentUse(attachment: attachment, live: embedders.filter { !$0.isLogged },
                                 logged: embedders.filter(\.isLogged), trashed: trashedByImage[attachment.path] ?? [])
        }
    }
}

/// The attachments list: images no live file embeds, then those that one does, each in Finder order by filename.
public struct AttachmentGroups: Sendable {
    /// Clean-up candidates ("Not in open files").
    public var candidates: [AttachmentUse]
    /// Images a live file embeds ("In open files").
    public var inUse: [AttachmentUse]

    public init(_ uses: [AttachmentUse]) {
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
    /// real names. A placeholder's size is read from its property list.
    public func taDaAttachments() -> [Attachment] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .addedToDirectoryDateKey, .creationDateKey, .contentModificationDateKey]
        let folder = url(for: Self.attachmentFolder)
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return urls.compactMap { url in
            let name = url.lastPathComponent
            let placeholder = Self.placeholderOriginal(name)
            let original = placeholder ?? name
            guard placeholder != nil || !name.hasPrefix("."), Self.isImage(original),
                  let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return nil }
            let size = placeholder == nil ? values.fileSize.map(Int64.init) : Self.placeholderSize(at: url)
            return Attachment(path: Self.attachmentFolder + "/" + original, size: size,
                              added: values.addedToDirectoryDate ?? values.creationDate ?? values.contentModificationDate,
                              isDownloaded: placeholder == nil)
        }
    }

    /// The size an iCloud Drive placeholder records (`NSURLFileSizeKey`); nil when it doesn't.
    static func placeholderSize(at url: URL) -> Int64? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let size = plist["NSURLFileSizeKey"] as? NSNumber else { return nil }
        return size.int64Value
    }

    /// `taDaAttachments()` with how each is used, as `AttachmentGroups` lists them.
    public func attachmentGroups(index: VaultIndex, trashed: [TrashedItem]) -> AttachmentGroups {
        AttachmentGroups(AttachmentUse.uses(of: taDaAttachments(), index: index, trashed: trashed, imagePaths: attachmentPaths()))
    }
}
