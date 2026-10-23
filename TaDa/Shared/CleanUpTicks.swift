// What the Mac's Clean Up dialog and the iPhone's Clean Up sheet share: the candidates grouped by reason, which are
// ticked, and the words. While markdown files are still downloading from iCloud Drive, nothing starts ticked.
import Foundation
import TaDaCore

/// The rows ticked when Clean Up opened (all of them, or none while files are still downloading) and the changes since.
/// Images that become candidates afterwards start unticked.
struct CleanUpTicks {
    private var initial: Set<String>?
    private var changes: [String: Bool] = [:]

    /// Fixes the starting ticks from `groups`.
    mutating func start(_ groups: AttachmentGroups) {
        initial = groups.pendingFiles.isEmpty ? Set(groups.candidates.map(\.id)) : []
    }

    func isTicked(_ use: AttachmentUse) -> Bool { changes[use.id] ?? (initial?.contains(use.id) == true) }

    mutating func toggle(_ use: AttachmentUse) { changes[use.id] = !isTicked(use) }

    /// The candidates ticked.
    func ticked(in candidates: [AttachmentUse]) -> [AttachmentUse] { candidates.filter(isTicked) }
}

/// A group of candidates that share a reason, with its title and tint.
struct CleanUpSection {
    let title: String
    let tint: KeyPath<Theme, PlatformColor>
    let uses: [AttachmentUse]

    private static let reasons: [(reason: CleanUpReason, title: String, tint: KeyPath<Theme, PlatformColor>)] = [
        (.loggedOnly, "Only in logged files", \.done),
        (.trashedOnly, "Only in trashed files", \.muted),
        (.loggedAndTrashed, "Only in logged and trashed files", \.due),
        (.unused, "Not embedded anywhere", \.deadline),
    ]

    /// `candidates` by reason, in the order Clean Up lists them; a reason with none is left out.
    static func sections(of candidates: [AttachmentUse]) -> [CleanUpSection] {
        reasons.compactMap { entry in
            let uses = candidates.filter { $0.cleanUpReason == entry.reason }
            return uses.isEmpty ? nil : CleanUpSection(title: entry.title, tint: entry.tint, uses: uses)
        }
    }
}

/// The words Clean Up uses.
enum CleanUpText {
    /// "Move 3 unused attachments to Trash?"
    static func title(count: Int) -> String { "Move \(count == 1 ? "1 unused attachment" : "\(count) unused attachments") to Trash?" }

    static let explanation = "No open task, project, area or note embeds these. Logged and trashed files that do will show them as missing until they’re restored from Trash."

    /// The note about files still downloading, which leaves every image unticked.
    static func pending(count: Int) -> String {
        "\(count == 1 ? "1 file is" : "\(count) files are") still downloading from iCloud Drive. An image they embed may look unused, so nothing is ticked."
    }

    /// "2 of 4 attachments · 3.5 MB"
    static func summary(ticked: [AttachmentUse], of total: Int) -> String {
        "\(ticked.count) of \(total == 1 ? "1 attachment" : "\(total) attachments") · "
            + Attachment.sizeText(Attachment.totalSize(of: ticked.map(\.attachment)))
    }
}
