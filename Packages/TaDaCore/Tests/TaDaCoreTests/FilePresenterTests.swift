import Foundation
import Synchronization
import Testing
@testable import TaDaCore

@Test func otherReadersWaitForTheSaveAndTheFilesOwnAccessesDont() async throws {
    try await withTemporaryFolder { folder in
        let url = folder.appending(path: "a.md")
        try CoordinatedFileIO.write("text", to: url)
        let saves = Count()
        let presenter = FilePresenter(url: url, save: { saves.add() }, moved: {})
        NSFileCoordinator.addFilePresenter(presenter)
        defer { NSFileCoordinator.removeFilePresenter(presenter) }

        _ = try CoordinatedFileIO.read(url, presenter: presenter)
        try CoordinatedFileIO.update(url, presenter: presenter) { $0 + " mine" }
        #expect(saves.value == 0)
        #expect(try CoordinatedFileIO.read(url) == "text mine")
        #expect(saves.value == 1)
        try CoordinatedFileIO.update(url) { $0 }
        #expect(saves.value == 2, "a merging write asks too")
    }
}

@Test func aMoveUpdatesThePresentedURL() async throws {
    try await withTemporaryFolder { folder in
        let a = folder.appending(path: "a.md"), b = folder.appending(path: "b.md")
        try CoordinatedFileIO.write("text", to: a)
        let moves = Count()
        let presenter = FilePresenter(url: a, save: {}, moved: { moves.add() })
        NSFileCoordinator.addFilePresenter(presenter)
        defer { NSFileCoordinator.removeFilePresenter(presenter) }

        try CoordinatedFileIO.move(a, to: b)
        for _ in 0..<40 where moves.value == 0 { try await Task.sleep(for: .milliseconds(50)) }
        #expect(moves.value == 1)
        #expect(presenter.presentedItemURL?.lastPathComponent == "b.md")
    }
}

private final class Count: Sendable {
    private let count = Mutex(0)
    var value: Int { count.withLock { $0 } }
    func add() { count.withLock { $0 += 1 } }
}
