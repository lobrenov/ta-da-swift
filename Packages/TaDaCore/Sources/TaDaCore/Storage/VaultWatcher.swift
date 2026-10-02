import Foundation
#if os(macOS)
import CoreServices

/// Calls `onChange` on a background queue shortly after anything changes under a folder.
/// It doesn't say what changed: callers compare modification dates (`Vault.modificationDates()`).
public final class VaultWatcher: @unchecked Sendable {
    /// Holds the callback for the stream; the stream's `info` points at it, unretained.
    private final class Handler {
        let onChange: @Sendable () -> Void
        init(_ onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }
    }

    private let handler: Handler
    private let stream: FSEventStreamRef
    private let queue = DispatchQueue(label: "TaDa.VaultWatcher")

    /// Nil when FSEvents can't watch the folder; callers then rescan when the app becomes active.
    public init?(root: URL, latency: TimeInterval = 0.3, onChange: @escaping @Sendable () -> Void) {
        handler = Handler(onChange)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(handler).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<Handler>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [root.path(percentEncoded: false)] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)
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
#endif
