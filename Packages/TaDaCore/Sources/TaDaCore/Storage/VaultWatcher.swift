import Foundation
#if os(macOS)
import CoreServices

/// Calls `onChange` on a background queue shortly after anything changes under a folder, with the files and folders
/// that changed, or nil when FSEvents can't say (events were dropped, or the folder itself moved). Callers compare
/// modification dates (`Vault.modificationDates()`) to find what changed in the files.
public final class VaultWatcher: @unchecked Sendable {
    /// Holds the callback for the stream; the stream's `info` points at it, unretained.
    private final class Handler {
        let onChange: @Sendable (Set<URL>?) -> Void
        init(_ onChange: @escaping @Sendable (Set<URL>?) -> Void) { self.onChange = onChange }
    }

    private let handler: Handler
    private let stream: FSEventStreamRef
    private let queue = DispatchQueue(label: "TaDa.VaultWatcher")

    /// Nil when FSEvents can't watch the folder; callers then rescan when the app becomes active.
    public init?(root: URL, latency: TimeInterval = 0.3, onChange: @escaping @Sendable (Set<URL>?) -> Void) {
        handler = Handler(onChange)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(handler).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let rescan = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagRootChanged)
            let list = Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            let whole = (0..<count).contains { flags[$0] & rescan != 0 } || list.count != count
            Unmanaged<Handler>.fromOpaque(info).takeUnretainedValue().onChange(whole ? nil : Set(list.map { URL(filePath: $0) }))
        }
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [root.path(percentEncoded: false)] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot
                | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            return nil
        }
    }

    deinit {
        // Stop, then drain the queue, so no callback runs after `handler` is released.
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        queue.sync {}
    }
}
#else

/// Calls `onChange` on a background queue when file coordination reports a change under a folder: another app's
/// coordinated write, or iCloud Drive adding, changing or moving a file. It passes the files that changed, or nil
/// for a change to the folder itself; callers compare modification dates (`Vault.modificationDates()`). Changes made
/// without coordination are found when the app becomes active. `latency` is unused: coordination reports each change
/// as it happens.
public final class VaultWatcher: NSObject, NSFilePresenter, Sendable {
    public let presentedItemURL: URL?
    public let presentedItemOperationQueue: OperationQueue
    private let onChange: @Sendable (Set<URL>?) -> Void

    public init?(root: URL, latency: TimeInterval = 0.3, onChange: @escaping @Sendable (Set<URL>?) -> Void) {
        presentedItemURL = root
        presentedItemOperationQueue = OperationQueue()
        presentedItemOperationQueue.maxConcurrentOperationCount = 1
        self.onChange = onChange
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    deinit {
        NSFileCoordinator.removeFilePresenter(self)
    }

    public func presentedItemDidChange() { onChange(nil) }
    public func presentedSubitemDidAppear(at url: URL) { onChange([url]) }
    public func presentedSubitemDidChange(at url: URL) { onChange([url]) }
    public func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { onChange([oldURL, newURL]) }
}
#endif
