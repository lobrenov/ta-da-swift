// The words Attachments uses for an image, on the Mac and iPhone: its size, where it's embedded and why it can be cleaned up.
import Foundation
import TaDaCore

extension Attachment {
    /// "2.1 MB", as Finder shows it; empty when the size isn't known.
    var sizeText: String { size.map(Attachment.sizeText) ?? "" }

    static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// "JPEG", "PNG": the file type in capitals.
    var typeText: String {
        let ext = FileNaming.split(name).ext.uppercased()
        return ext == "JPG" ? "JPEG" : ext
    }

    /// "Fri 2 Oct"; nil when no date is recorded.
    var addedText: String? { added.map { LocalDate($0).formatted(.weekdayDayMonth) } }

    /// "1 image", "3 images".
    static func countText(_ n: Int) -> String { n == 1 ? "1 image" : "\(n) images" }

    /// "PNG · 2.1 MB · 1920 × 1440 · Added Mon 28 Sep", with "Not downloaded" while iCloud Drive hasn't sent it.
    func metaText(dimensions: String?) -> String {
        [typeText, sizeText, dimensions, addedText.map { "Added \($0)" }, isDownloaded ? nil : "Not downloaded"]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// A where-line: plain text, the titles of the files (shown as links) and plain text after them.
struct AttachmentWhere {
    var prefix: String
    var titles = ""
    var suffix = ""
}

extension AttachmentUse {
    /// The titles of the logged then trashed files that embed it.
    var closedTitles: String { (logged.map(\.title) + trashed.map(\.item.title)).joined(separator: ", ") }

    /// "In A, B and 1 logged file"; "In the Logbook: …"; "In Trash: …"; "In the Logbook and Trash: …"; "Not embedded
    /// anywhere · added Fri 2 Oct".
    var whereLine: AttachmentWhere {
        switch cleanUpReason {
        case nil:
            let others = [logged.count > 0 ? Self.count(logged.count, "logged file") : nil,
                          trashed.count > 0 ? Self.count(trashed.count, "trashed file") : nil].compactMap { $0 }
            return AttachmentWhere(prefix: "In ", titles: live.map(\.title).joined(separator: ", "),
                                   suffix: others.isEmpty ? "" : " and " + others.joined(separator: " and "))
        case .unused:
            return AttachmentWhere(prefix: "Not embedded anywhere" + (attachment.addedText.map { " · added \($0)" } ?? ""))
        case .loggedOnly: return AttachmentWhere(prefix: "In the Logbook: ", titles: closedTitles)
        case .trashedOnly: return AttachmentWhere(prefix: "In Trash: ", titles: closedTitles)
        case .loggedAndTrashed: return AttachmentWhere(prefix: "In the Logbook and Trash: ", titles: closedTitles)
        }
    }

    /// Where a live file that embeds it sits: a task's project or area, or Loose task; a project's area; a note's folder.
    static func livePlace(_ item: Item) -> String {
        let p = item.properties
        return switch p.kind {
        case .task: p.project?.title ?? p.area?.title ?? "Loose task"
        case .project: p.area?.title ?? "Project"
        case .area: "Area"
        case .note: Vault.folder(of: item.path).split(separator: "/").last.map(String.init) ?? "Notes"
        }
    }

    /// "Logbook · Oct 2026", for a logged file that embeds it.
    static func loggedPlace(_ item: Item) -> String {
        "Logbook" + (item.properties.completedDate.map { " · " + $0.date().formatted(.dateTime.month(.abbreviated).year()) } ?? "")
    }

    private static func count(_ n: Int, _ noun: String) -> String { n == 1 ? "1 \(noun)" : "\(n) \(noun)s" }
}
