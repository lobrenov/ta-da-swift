import AppKit
import Foundation
import SwiftUI
import Testing
import TaDaCore
@testable import TaDa

/// Files changed, added or deleted by other apps while Ta Da is running.
@MainActor
struct OutsideChangesTests {
    let folder: TestFolder
    static let task = "---\ntype: task\nstatus: Doing\ndueDate: 2026-10-03\n---\nBody.\n"

    init() throws {
        folder = try TestFolder(["tasks/Task.md": Self.task, "tasks/Other.md": "---\ntype: task\nstatus: Not Started\n---\n"])
    }

    /// Moves a file through file coordination, as Finder does.
    @concurrent nonisolated private static func coordinatedMove(_ source: URL, to destination: URL) async throws {
        try CoordinatedFileIO.move(source, to: destination)
    }

    /// Reads a file through file coordination, as iCloud Drive does before an upload.
    @concurrent nonisolated private static func coordinatedRead(_ url: URL) async throws -> String {
        try CoordinatedFileIO.read(url)
    }

    @Test func refreshPicksUpEditsNewFilesAndDeletions() async throws {
        let model = await folder.model()
        try folder.write(Self.task.replacingOccurrences(of: "Doing", with: "Blocked"), "tasks/Task.md")
        try folder.write("---\ntype: project\nstatus: Doing\n---\n", "projects/New.md")
        try FileManager.default.removeItem(at: folder.url.appending(path: "tasks/Other.md"))
        await model.refresh()
        #expect(model.index["tasks/Task.md"]?.properties.status == .blocked)
        #expect(model.index["projects/New.md"] != nil)
        #expect(model.index["tasks/Other.md"] == nil)
    }

    @Test func aRefreshCalledAsAnotherEndsStillScans() async throws {
        let model = await folder.model()
        let first = Task { await model.refresh() }
        // Each pass ends by trimming the trash selection, after its last suspension, so this continues once
        // the first refresh's pass has ended but before its caller has resumed.
        await withCheckedContinuation { continuation in
            withObservationTracking { _ = model.trashSelection } onChange: { continuation.resume() }
        }
        try folder.write(Self.task.replacingOccurrences(of: "Doing", with: "Blocked"), "tasks/Task.md")
        await model.refresh()
        #expect(model.index["tasks/Task.md"]?.properties.status == .blocked)
        await first.value
    }

    @Test func theWatcherUpdatesTheIndexWithoutARefreshCall() async throws {
        let model = await folder.model()
        #expect(model.isWatching)
        try await Task.sleep(for: .milliseconds(300))
        try folder.write(Self.task.replacingOccurrences(of: "Doing", with: "Done"), "tasks/Task.md")
        for _ in 0..<40 where model.index["tasks/Task.md"]?.properties.status != .done {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(model.index["tasks/Task.md"]?.properties.status == .done, "within 2 s")
    }

    @Test func aCleanOpenFileReloads() async throws {
        let model = await folder.model(selecting: "tasks/Task.md")
        try folder.write(Self.task + "From Obsidian.\n", "tasks/Task.md")
        await model.refresh()
        #expect(model.document?.text == Self.task + "From Obsidian.\n")
        #expect(model.document?.isDirty == false)
    }

    @Test func ourOwnSavesDontCountAsOutsideChanges() async throws {
        let model = await folder.model(selecting: "tasks/Task.md")
        let document = try #require(model.document)
        document.body += "Mine.\n"
        await model.save(document)
        await model.refresh()
        #expect(document.diskText == nil)
        #expect(document.text == Self.task + "Mine.\n")
    }

    @Test func unsavedEditsAreKeptAndNeverOverwriteAnOutsideChange() async throws {
        let model = await folder.model(selecting: "tasks/Task.md")
        let document = try #require(model.document)
        document.body += "Mine.\n"
        try folder.write(Self.task + "Theirs.\n", "tasks/Task.md")

        // A save before the watcher noticed must not overwrite theirs.
        await model.save(document)
        #expect(try folder.read("tasks/Task.md") == Self.task + "Theirs.\n")
        #expect(document.diskText == Self.task + "Theirs.\n")
        #expect(document.text == Self.task + "Mine.\n")

        await model.refresh()
        #expect(document.text == Self.task + "Mine.\n", "a refresh keeps the edits too")

        await model.keepMine(document)
        #expect(try folder.read("tasks/Task.md") == Self.task + "Mine.\n")
        #expect(document.diskText == nil && !document.isDirty)
    }

    @Test func usingTheirsDropsTheEdits() async throws {
        let model = await folder.model(selecting: "tasks/Task.md")
        let document = try #require(model.document)
        document.body += "Mine.\n"
        try folder.write(Self.task + "Theirs.\n", "tasks/Task.md")
        await model.refresh()
        #expect(document.diskText != nil)
        model.useTheirs(document)
        #expect(document.text == Self.task + "Theirs.\n" && !document.isDirty)
        #expect(try folder.read("tasks/Task.md") == Self.task + "Theirs.\n")
    }

    @Test func leavingAConflictedFileKeepsTheEditsInACopy() async throws {
        let model = await folder.model(selecting: "tasks/Task.md")
        let document = try #require(model.document)
        document.body += "Mine.\n"
        try folder.write(Self.task + "Theirs.\n", "tasks/Task.md")
        await model.refresh()

        model.selection = "tasks/Other.md"
        await model.loading?.value
        #expect(try folder.read("tasks/Task.md") == Self.task + "Theirs.\n")
        #expect(try folder.read("tasks/Task (unsaved edits).md") == Self.task + "Mine.\n")
        #expect(model.index["tasks/Task (unsaved edits).md"] != nil)
        #expect(model.errorMessage?.contains("Task (unsaved edits)") == true)
    }

    @Test func leavingAConflictedFileTwiceQuicklyKeepsOneCopy() async throws {
        try folder.write("---\ntype: task\nstatus: Not Started\n---\n", "tasks/Third.md")
        let model = await folder.model(selecting: "tasks/Task.md")
        let document = try #require(model.document)
        document.body += "Mine.\n"
        try folder.write(Self.task + "Theirs.\n", "tasks/Task.md")
        await model.refresh()

        model.selection = "tasks/Other.md"
        model.selection = "tasks/Third.md"
        await model.loading?.value
        let copies = try FileManager.default.contentsOfDirectory(atPath: folder.url.appending(path: "tasks").path)
            .filter { $0.hasPrefix("Task (unsaved edits)") }
        #expect(copies == ["Task (unsaved edits).md"])
        #expect(model.errorMessage == "“Task” changed outside Ta Da while you were editing it, so your edits were saved as “Task (unsaved edits)”.")
        #expect(model.document?.path == "tasks/Third.md")
    }

    @Test func aDeletedCleanFileCloses() async throws {
        let model = await folder.model(selecting: "tasks/Task.md")
        try FileManager.default.removeItem(at: folder.url.appending(path: "tasks/Task.md"))
        await model.refresh()
        #expect(model.selection == nil)
        #expect(model.index["tasks/Task.md"] == nil)
    }

    @Test func aDeletedFileWithEditsCanBeSavedAgain() async throws {
        let model = await folder.model(selecting: "tasks/Task.md")
        let document = try #require(model.document)
        document.body += "Mine.\n"
        try FileManager.default.removeItem(at: folder.url.appending(path: "tasks/Task.md"))
        await model.refresh()
        #expect(document.isRemovedOnDisk)
        #expect(model.selection == "tasks/Task.md")

        await model.saveAgain(document)
        #expect(try folder.read("tasks/Task.md") == Self.task + "Mine.\n")
        #expect(!document.isRemovedOnDisk)
    }

    @Test func aRenameOutsideTaDaIsFollowed() async throws {
        let model = await folder.model(selecting: "tasks/Task.md")
        let document = try #require(model.document)
        document.body += "Mine.\n"
        try await Self.coordinatedMove(folder.url.appending(path: "tasks/Task.md"), to: folder.url.appending(path: "tasks/Renamed.md"))
        for _ in 0..<40 where document.path != "tasks/Renamed.md" { try await Task.sleep(for: .milliseconds(50)) }
        await model.refresh()
        #expect(document.path == "tasks/Renamed.md" && model.selection == "tasks/Renamed.md")
        #expect(!document.isRemovedOnDisk)
        #expect(model.index["tasks/Task.md"] == nil && model.index["tasks/Renamed.md"] != nil)
        await model.save(document)
        #expect(try folder.read("tasks/Renamed.md") == Self.task + "Mine.\n")
    }

    @Test func anotherAppsCoordinatedReadGetsTheUnsavedEdits() async throws {
        let model = await folder.model(selecting: "tasks/Task.md")
        model.saveDelay = .seconds(60)
        let document = try #require(model.document)
        document.body += "Mine.\n"
        #expect(try await Self.coordinatedRead(folder.url.appending(path: "tasks/Task.md")) == Self.task + "Mine.\n")
        #expect(!document.isDirty)
    }

    @Test func quittingWithAConflictWritesACopy() async throws {
        let model = await folder.model(selecting: "tasks/Task.md")
        model.document?.body += "Mine.\n"
        try folder.write(Self.task + "Theirs.\n", "tasks/Task.md")
        await model.saveBeforeQuitting()
        #expect(try folder.read("tasks/Task.md") == Self.task + "Theirs.\n")
        #expect(try folder.read("tasks/Task (unsaved edits).md") == Self.task + "Mine.\n")
    }

    @Test func quittingSavesEditsNotYetSaved() async throws {
        let model = await folder.model(selecting: "tasks/Task.md")
        model.document?.body += "Mine.\n"
        await model.saveBeforeQuitting()
        #expect(try folder.read("tasks/Task.md") == Self.task + "Mine.\n")
        #expect(model.document?.isDirty == false)
    }

    @Test func quittingDuringASaveWaitsForIt() async throws {
        let model = await folder.model(selecting: "tasks/Task.md")
        let document = try #require(model.document)
        document.body += "Mine.\n"
        let saving = Task { await model.save(document) }
        await Task.yield()
        await model.saveBeforeQuitting()
        await saving.value
        #expect(try folder.read("tasks/Task.md") == Self.task + "Mine.\n")
        #expect(document.diskText == nil && !document.isDirty)
        #expect(!FileManager.default.fileExists(atPath: folder.url.appending(path: "tasks/Task (unsaved edits).md").path))
    }

    @Test func searchShowsMatchesUntilADomainIsPicked() async throws {
        let model = await folder.model()
        model.searchText = "  "
        #expect(!model.isSearching)
        model.searchText = "oth"
        #expect(model.isSearching)
        #expect(model.index.search(model.searchText).map(\.title) == ["Other"])
        model.show(.loose)
        #expect(model.searchText.isEmpty && model.domain == .loose)
    }

    @Test func anOutsideEditReachesTheLiveEditor() async throws {
        let model = await folder.model()
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 1280, height: 800),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.orderFrontRegardless()
        model.selection = "tasks/Task.md"
        func textView(in view: NSView) -> NSTextView? {
            if let textView = view as? NSTextView, textView.isEditable { return textView }
            return view.subviews.lazy.compactMap(textView(in:)).first
        }
        for _ in 0..<50 where textView(in: window.contentView!) == nil { try await Task.sleep(for: .milliseconds(100)) }
        try #require(textView(in: window.contentView!) != nil, "the editor shows the file first, within 5 s")

        try folder.write(Self.task + "From TextEdit.\n", "tasks/Task.md")
        await model.refresh()
        for _ in 0..<50 where textView(in: window.contentView!)?.string.contains("From TextEdit.") != true {
            try await Task.sleep(for: .milliseconds(100))
        }
        let editor = try #require(textView(in: window.contentView!))
        #expect(editor.string.contains("From TextEdit."))
        #expect(model.document?.isDirty == false)
    }
}
