import AppKit
import Foundation
import SwiftUI
import Testing
import TaDaCore
@testable import TaDa

/// Files changed, added or deleted by other apps while Ta Da is running.
@MainActor
struct OutsideChangesTests {
    let defaults: UserDefaults
    let suite = "TaDaTests-\(UUID().uuidString)"
    let folder = FileManager.default.temporaryDirectory.appending(path: "TaDaVault-\(UUID().uuidString)", directoryHint: .isDirectory)
    static let task = "---\ntype: task\nstatus: Doing\ndueDate: 2026-10-03\n---\nBody.\n"

    init() throws {
        defaults = UserDefaults(suiteName: suite)!
        try write(Self.task, "tasks/Task.md")
        try write("---\ntype: task\nstatus: Not Started\n---\n", "tasks/Other.md")
    }

    private func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }

    /// Writes as another app would, making sure the modification date moves on.
    private func write(_ text: String, _ path: String) throws {
        let url = folder.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(Double.random(in: 1...1000))],
                                              ofItemAtPath: url.path)
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: folder.appending(path: path), encoding: .utf8)
    }

    /// Moves a file through file coordination, as Finder does.
    @concurrent nonisolated private static func coordinatedMove(_ source: URL, to destination: URL) async throws {
        try CoordinatedFileIO.move(source, to: destination)
    }

    /// Reads a file through file coordination, as iCloud Drive does before an upload.
    @concurrent nonisolated private static func coordinatedRead(_ url: URL) async throws -> String {
        try CoordinatedFileIO.read(url)
    }

    private func model(selecting path: String? = nil) async -> AppModel {
        let model = AppModel(defaults: defaults)
        model.today = LocalDate("2026-10-03")!
        await model.choose(folder)
        if let path {
            model.selection = path
            await model.loadSelection()
        }
        return model
    }

    @Test func refreshPicksUpEditsNewFilesAndDeletions() async throws {
        defer { cleanUp() }
        let model = await model()
        try write(Self.task.replacingOccurrences(of: "Doing", with: "Blocked"), "tasks/Task.md")
        try write("---\ntype: project\nstatus: Doing\n---\n", "projects/New.md")
        try FileManager.default.removeItem(at: folder.appending(path: "tasks/Other.md"))
        await model.refresh()
        #expect(model.index["tasks/Task.md"]?.properties.status == .blocked)
        #expect(model.index["projects/New.md"] != nil)
        #expect(model.index["tasks/Other.md"] == nil)
    }

    @Test func theWatcherUpdatesTheIndexWithoutARefreshCall() async throws {
        defer { cleanUp() }
        let model = await model()
        #expect(model.isWatching)
        try await Task.sleep(for: .milliseconds(300))
        try write(Self.task.replacingOccurrences(of: "Doing", with: "Done"), "tasks/Task.md")
        for _ in 0..<40 where model.index["tasks/Task.md"]?.properties.status != .done {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(model.index["tasks/Task.md"]?.properties.status == .done, "within 2 s")
    }

    @Test func aCleanOpenFileReloads() async throws {
        defer { cleanUp() }
        let model = await model(selecting: "tasks/Task.md")
        try write(Self.task + "From Obsidian.\n", "tasks/Task.md")
        await model.refresh()
        #expect(model.document?.text == Self.task + "From Obsidian.\n")
        #expect(model.document?.isDirty == false)
    }

    @Test func ourOwnSavesDontCountAsOutsideChanges() async throws {
        defer { cleanUp() }
        let model = await model(selecting: "tasks/Task.md")
        let document = try #require(model.document)
        document.body += "Mine.\n"
        await model.save(document)
        await model.refresh()
        #expect(document.diskText == nil)
        #expect(document.text == Self.task + "Mine.\n")
    }

    @Test func unsavedEditsAreKeptAndNeverOverwriteAnOutsideChange() async throws {
        defer { cleanUp() }
        let model = await model(selecting: "tasks/Task.md")
        let document = try #require(model.document)
        document.body += "Mine.\n"
        try write(Self.task + "Theirs.\n", "tasks/Task.md")

        // A save before the watcher noticed must not overwrite theirs.
        await model.save(document)
        #expect(try read("tasks/Task.md") == Self.task + "Theirs.\n")
        #expect(document.diskText == Self.task + "Theirs.\n")
        #expect(document.text == Self.task + "Mine.\n")

        await model.refresh()
        #expect(document.text == Self.task + "Mine.\n", "a refresh keeps the edits too")

        await model.keepMine(document)
        #expect(try read("tasks/Task.md") == Self.task + "Mine.\n")
        #expect(document.diskText == nil && !document.isDirty)
    }

    @Test func usingTheirsDropsTheEdits() async throws {
        defer { cleanUp() }
        let model = await model(selecting: "tasks/Task.md")
        let document = try #require(model.document)
        document.body += "Mine.\n"
        try write(Self.task + "Theirs.\n", "tasks/Task.md")
        await model.refresh()
        #expect(document.diskText != nil)
        model.useTheirs(document)
        #expect(document.text == Self.task + "Theirs.\n" && !document.isDirty)
        #expect(try read("tasks/Task.md") == Self.task + "Theirs.\n")
    }

    @Test func leavingAConflictedFileKeepsTheEditsInACopy() async throws {
        defer { cleanUp() }
        let model = await model(selecting: "tasks/Task.md")
        let document = try #require(model.document)
        document.body += "Mine.\n"
        try write(Self.task + "Theirs.\n", "tasks/Task.md")
        await model.refresh()

        model.selection = "tasks/Other.md"
        await model.loadSelection()
        #expect(try read("tasks/Task.md") == Self.task + "Theirs.\n")
        #expect(try read("tasks/Task (unsaved edits).md") == Self.task + "Mine.\n")
        #expect(model.index["tasks/Task (unsaved edits).md"] != nil)
        #expect(model.errorMessage?.contains("Task (unsaved edits)") == true)
    }

    @Test func aDeletedCleanFileCloses() async throws {
        defer { cleanUp() }
        let model = await model(selecting: "tasks/Task.md")
        try FileManager.default.removeItem(at: folder.appending(path: "tasks/Task.md"))
        await model.refresh()
        #expect(model.selection == nil)
        #expect(model.index["tasks/Task.md"] == nil)
    }

    @Test func aDeletedFileWithEditsCanBeSavedAgain() async throws {
        defer { cleanUp() }
        let model = await model(selecting: "tasks/Task.md")
        let document = try #require(model.document)
        document.body += "Mine.\n"
        try FileManager.default.removeItem(at: folder.appending(path: "tasks/Task.md"))
        await model.refresh()
        #expect(document.isRemovedOnDisk)
        #expect(model.selection == "tasks/Task.md")

        await model.saveAgain(document)
        #expect(try read("tasks/Task.md") == Self.task + "Mine.\n")
        #expect(!document.isRemovedOnDisk)
    }

    @Test func aRenameOutsideTaDaIsFollowed() async throws {
        defer { cleanUp() }
        let model = await model(selecting: "tasks/Task.md")
        let document = try #require(model.document)
        document.body += "Mine.\n"
        try await Self.coordinatedMove(folder.appending(path: "tasks/Task.md"), to: folder.appending(path: "tasks/Renamed.md"))
        for _ in 0..<40 where document.path != "tasks/Renamed.md" { try await Task.sleep(for: .milliseconds(50)) }
        await model.refresh()
        #expect(document.path == "tasks/Renamed.md" && model.selection == "tasks/Renamed.md")
        #expect(!document.isRemovedOnDisk)
        #expect(model.index["tasks/Task.md"] == nil && model.index["tasks/Renamed.md"] != nil)
        await model.save(document)
        #expect(try read("tasks/Renamed.md") == Self.task + "Mine.\n")
    }

    @Test func anotherAppsCoordinatedReadGetsTheUnsavedEdits() async throws {
        defer { cleanUp() }
        let model = await model(selecting: "tasks/Task.md")
        model.saveDelay = .seconds(60)
        let document = try #require(model.document)
        document.body += "Mine.\n"
        #expect(try await Self.coordinatedRead(folder.appending(path: "tasks/Task.md")) == Self.task + "Mine.\n")
        #expect(!document.isDirty)
    }

    @Test func quittingWithAConflictWritesACopy() async throws {
        defer { cleanUp() }
        let model = await model(selecting: "tasks/Task.md")
        model.document?.body += "Mine.\n"
        try write(Self.task + "Theirs.\n", "tasks/Task.md")
        await model.saveBeforeQuitting()
        #expect(try read("tasks/Task.md") == Self.task + "Theirs.\n")
        #expect(try read("tasks/Task (unsaved edits).md") == Self.task + "Mine.\n")
    }

    @Test func quittingSavesEditsNotYetSaved() async throws {
        defer { cleanUp() }
        let model = await model(selecting: "tasks/Task.md")
        model.document?.body += "Mine.\n"
        await model.saveBeforeQuitting()
        #expect(try read("tasks/Task.md") == Self.task + "Mine.\n")
        #expect(model.document?.isDirty == false)
    }

    @Test func quittingDuringASaveWaitsForIt() async throws {
        defer { cleanUp() }
        let model = await model(selecting: "tasks/Task.md")
        let document = try #require(model.document)
        document.body += "Mine.\n"
        let saving = Task { await model.save(document) }
        await Task.yield()
        await model.saveBeforeQuitting()
        await saving.value
        #expect(try read("tasks/Task.md") == Self.task + "Mine.\n")
        #expect(document.diskText == nil && !document.isDirty)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "tasks/Task (unsaved edits).md").path))
    }

    @Test func searchShowsMatchesUntilADomainIsPicked() async throws {
        defer { cleanUp() }
        let model = await model()
        model.searchText = "  "
        #expect(!model.isSearching)
        model.searchText = "oth"
        #expect(model.isSearching)
        #expect(model.index.search(model.searchText).map(\.title) == ["Other"])
        model.show(.upcoming)
        #expect(model.searchText.isEmpty && model.domain == .upcoming)
    }

    @Test func anOutsideEditReachesTheLiveEditor() async throws {
        defer { cleanUp() }
        let model = await model()
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 1280, height: 800),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.orderFrontRegardless()
        model.selection = "tasks/Task.md"
        try await Task.sleep(for: .milliseconds(600))

        try write(Self.task + "From TextEdit.\n", "tasks/Task.md")
        await model.refresh()
        try await Task.sleep(for: .milliseconds(400))
        func textView(in view: NSView) -> NSTextView? {
            if let textView = view as? NSTextView, textView.isEditable { return textView }
            return view.subviews.lazy.compactMap(textView(in:)).first
        }
        let editor = try #require(textView(in: window.contentView!))
        #expect(editor.string.contains("From TextEdit."))
        #expect(model.document?.isDirty == false)
    }
}
