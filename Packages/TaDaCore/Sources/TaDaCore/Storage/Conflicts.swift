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

    /// Keeps the file as it is and discards the conflicting versions, in one coordinated write.
    public static func keepCurrent(_ url: URL) throws {
        try CoordinatedFileIO.coordinate { coordinator, error, body in
            coordinator.coordinate(writingItemAt: url, options: [], error: error) { url in
                body { try resolve(url) }
            }
        }
    }

    /// Replaces the file with a conflicting version's text and discards the conflicts, in one coordinated
    /// write. Returns the text.
    public static func adopt(_ version: ConflictVersion, at url: URL) throws -> String {
        try CoordinatedFileIO.coordinate { coordinator, error, body in
            coordinator.coordinate(readingItemAt: version.url, options: [],
                                   writingItemAt: url, options: .forReplacing, error: error) { versionURL, url in
                body {
                    let text = try CoordinatedFileIO.decode(versionURL)
                    try Data(text.utf8).write(to: url, options: .atomic)
                    try resolve(url)
                    return text
                }
            }
        }
    }

    /// Marks the conflicts resolved and removes the other versions. Runs inside a coordinated write to the file.
    private static func resolve(_ url: URL) throws {
        for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [] {
            version.isResolved = true
        }
        try NSFileVersion.removeOtherVersionsOfItem(at: url)
    }
}
