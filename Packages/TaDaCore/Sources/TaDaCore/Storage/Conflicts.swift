import Foundation

/// A version of a file that iCloud kept because two devices changed it at the same time.
public struct ConflictVersion: Hashable, Sendable {
    /// The device that saved it, when iCloud knows.
    public var device: String?
    public var modified: Date?
    /// Where the version's contents can be read.
    public var url: URL
}

/// Unresolved iCloud conflicts for one file, through `NSFileVersion`.
public enum Conflicts {
    /// Conflicting versions of the file, newest first. Empty outside iCloud Drive.
    public static func versions(of url: URL) -> [ConflictVersion] {
        (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [])
            .map { ConflictVersion(device: $0.localizedNameOfSavingComputer, modified: $0.modificationDate, url: $0.url) }
            .sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
    }

    /// Keeps the file as it is and discards the conflicting versions.
    public static func keepCurrent(_ url: URL) throws {
        for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [] {
            version.isResolved = true
        }
        try NSFileVersion.removeOtherVersionsOfItem(at: url)
    }

    /// Replaces the file with a conflicting version's text, then discards the conflicts. Returns the text.
    public static func adopt(_ version: ConflictVersion, at url: URL) throws -> String {
        let text = try CoordinatedFileIO.read(version.url)
        try CoordinatedFileIO.write(text, to: url)
        try keepCurrent(url)
        return text
    }
}
