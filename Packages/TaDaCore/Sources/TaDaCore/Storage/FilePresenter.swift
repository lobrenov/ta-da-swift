import Foundation
import Synchronization

/// Presents an open file to file coordination. Another app's coordinated read or merging write (iCloud
/// Drive's uploads among them) waits for `save`, and a coordinated move or rename updates `presentedItemURL`
/// and calls `moved`. Both run on the main actor, without waiting for a thread in the cooperative pool.
/// Register it with `NSFileCoordinator.addFilePresenter(_:)`, and pass it to the app's own coordinated reads
/// and writes of the file: they then don't message it, and a save made for a waiting reader goes first.
public final class FilePresenter: NSObject, NSFilePresenter, Sendable {
    public let presentedItemOperationQueue: OperationQueue
    private let url: Mutex<URL?>
    private let save: @MainActor @Sendable () async -> Void
    private let moved: @MainActor @Sendable () -> Void

    public init(url: URL, save: @escaping @MainActor @Sendable () async -> Void,
                moved: @escaping @MainActor @Sendable () -> Void) {
        presentedItemOperationQueue = OperationQueue()
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        self.url = Mutex(url)
        self.save = save
        self.moved = moved
    }

    public var presentedItemURL: URL? { url.withLock { $0 } }

    /// The reader then gets the file as `save` left it; `save` reports its own errors.
    public func savePresentedItemChanges(completionHandler: @escaping @Sendable ((any Error)?) -> Void) {
        Task { @MainActor in
            await save()
            completionHandler(nil)
        }
    }

    public func presentedItemDidMove(to newURL: URL) {
        url.withLock { $0 = newURL }
        Task { @MainActor in moved() }
    }
}
