import Foundation

public enum FileIOError: Error, Equatable {
    case notUTF8(String)
}

/// File reads and writes through `NSFileCoordinator`, so iCloud Drive and other apps see consistent files.
/// Synchronous: call it off the main actor.
public enum CoordinatedFileIO {
    /// Reads UTF-8 text. A coordinated read downloads an evicted iCloud file first.
    /// `presenter` is the file's own `FilePresenter`, if it's open.
    public static func read(_ url: URL, presenter: FilePresenter? = nil) throws -> String {
        try coordinate(presenter: presenter) { coordinator, error, body in
            coordinator.coordinate(readingItemAt: url, options: [], error: error) { url in body { try decode(url) } }
        }
    }

    /// Replaces the file atomically, creating it if needed.
    public static func write(_ text: String, to url: URL) throws {
        try coordinate { coordinator, error, body in
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: error) { url in
                body { try Data(text.utf8).write(to: url, options: .atomic) }
            }
        }
    }

    /// Reads, transforms and writes back in one coordinated access, so no other coordinated writer
    /// can change the file in between. Writes only when the text changes. Returns the resulting text.
    /// `presenter` is the file's own `FilePresenter`, if it's open.
    @discardableResult
    public static func update(_ url: URL, presenter: FilePresenter? = nil, _ transform: (String) throws -> String) throws -> String {
        try withoutActuallyEscaping(transform) { transform in
            try coordinate(presenter: presenter) { coordinator, error, body in
                coordinator.coordinate(writingItemAt: url, options: .forMerging, error: error) { url in
                    body {
                        let old = try decode(url)
                        let new = try transform(old)
                        if new != old { try Data(new.utf8).write(to: url, options: .atomic) }
                        return new
                    }
                }
            }
        }
    }

    /// Writes a new file, creating its folder; fails if the file already exists.
    public static func create(_ text: String, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try coordinate { coordinator, error, body in
            coordinator.coordinate(writingItemAt: url, options: [], error: error) { url in
                body { try Data(text.utf8).write(to: url, options: .withoutOverwriting) }
            }
        }
    }

    /// Moves a file, telling other coordinated clients (e.g. iCloud Drive) about the move.
    public static func move(_ source: URL, to destination: URL) throws {
        try coordinate { coordinator, error, body in
            coordinator.coordinate(writingItemAt: source, options: .forMoving,
                                   writingItemAt: destination, options: .forReplacing, error: error) { from, to in
                body {
                    coordinator.item(at: from, willMoveTo: to)
                    try FileManager.default.moveItem(at: from, to: to)
                    coordinator.item(at: from, didMoveTo: to)
                }
            }
        }
    }

    /// Moves a file to the system Trash, or deletes it where trashing isn't supported (on iOS, outside iCloud Drive),
    /// telling other coordinated clients it's going.
    public static func moveToSystemTrash(_ url: URL) throws {
        try coordinate { coordinator, error, body in
            coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: error) { url in
                body { try trashOrDelete(url) }
            }
        }
    }

    /// Trashes the file with `trash`; if that's unsupported for it, deletes it.
    static func trashOrDelete(_ url: URL, trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws {
        do {
            try trash(url)
        } catch let error as CocoaError where error.code == .featureUnsupported {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func decode(_ url: URL) throws -> String {
        guard let text = String(data: try Data(contentsOf: url), encoding: .utf8) else {
            throw FileIOError.notUTF8(url.lastPathComponent)
        }
        return text
    }

    /// Runs one coordination, surfacing both the coordinator's error and the accessor's.
    static func coordinate<T>(
        presenter: FilePresenter? = nil,
        _ run: (NSFileCoordinator, NSErrorPointer, (() throws -> T) -> Void) -> Void
    ) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, any Error>?
        run(NSFileCoordinator(filePresenter: presenter), &coordinationError) { work in result = Result(catching: work) }
        if let coordinationError { throw coordinationError }
        guard let result else { throw CocoaError(.fileReadUnknown) }
        return try result.get()
    }
}
