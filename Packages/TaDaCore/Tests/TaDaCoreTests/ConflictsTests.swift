import Foundation
import Synchronization
import Testing
@testable import TaDaCore

/// Presents a file and records, as each coordinated writer takes it, how many other versions it has.
private final class WriteWatcher: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    private let counts = Mutex<[Int]>([])

    init(_ url: URL) {
        presentedItemURL = url
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    /// The file's other versions at the start of each coordinated write, in order.
    var versionsAtEachWrite: [Int] { counts.withLock { $0 } }

    func relinquishPresentedItem(toWriter writer: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
        let count = presentedItemURL.flatMap { NSFileVersion.otherVersionsOfItem(at: $0) }?.count ?? 0
        counts.withLock { $0.append(count) }
        writer(nil)
    }
}

/// A file with one other version in the version store, standing in for an iCloud conflict.
private func fileWithAnotherVersion(in folder: URL) throws -> (url: URL, version: NSFileVersion) {
    try writeFile("current\n", "Task.md", in: folder)
    try writeFile("other\n", "Other.md", in: folder)
    let url = folder.appending(path: "Task.md")
    let version = try NSFileVersion.addOfItem(at: url, withContentsOf: folder.appending(path: "Other.md"), options: [])
    return (url, version)
}

@Test func keepingTheCurrentVersionRemovesTheOthersInACoordinatedWrite() async throws {
    try await withTemporaryFolder { folder in
        let (url, _) = try fileWithAnotherVersion(in: folder)
        let watcher = WriteWatcher(url)
        defer { NSFileCoordinator.removeFilePresenter(watcher) }

        try Conflicts.keepCurrent(url)
        #expect(watcher.versionsAtEachWrite == [1], "one coordinated write, taken while the version was still there")
        #expect(NSFileVersion.otherVersionsOfItem(at: url)?.isEmpty == true)
        #expect(try CoordinatedFileIO.read(url) == "current\n")
    }
}

@Test func adoptingAVersionWritesItAndRemovesTheOthersInOneCoordinatedWrite() async throws {
    try await withTemporaryFolder { folder in
        let (url, version) = try fileWithAnotherVersion(in: folder)
        let watcher = WriteWatcher(url)
        defer { NSFileCoordinator.removeFilePresenter(watcher) }

        let text = try Conflicts.adopt(ConflictVersion(device: nil, modified: nil, url: version.url), at: url)
        #expect(text == "other\n")
        #expect(try CoordinatedFileIO.read(url) == "other\n")
        #expect(watcher.versionsAtEachWrite == [1], "one coordinated write, taken while the version was still there")
        #expect(NSFileVersion.otherVersionsOfItem(at: url)?.isEmpty == true)
    }
}
