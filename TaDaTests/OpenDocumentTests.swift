import AppKit
import Foundation
import SwiftUI
import Testing
import TaDaCore
@testable import TaDa

/// The open document: reading, editing, saving, renaming and creating files through AppModel.
@MainActor
struct OpenDocumentTests {
    let defaults: UserDefaults
    let suite = "TaDaTests-\(UUID().uuidString)"
    let folder = FileManager.default.temporaryDirectory.appending(path: "TaDaVault-\(UUID().uuidString)", directoryHint: .isDirectory)

    static let task = "---\ntype: task\nstatus: Doing # keep\nproject: \"[[Ta Da MVP]]\"\ndueDate: 2026-10-02\n---\nBody line.\n\n- [ ] One\n- [x] Two\n"

    init() throws {
        defaults = UserDefaults(suiteName: suite)!
        for (path, text) in [
            ("projects/Ta Da MVP.md", "---\ntype: project\nstatus: Doing\n---\nThe project.\n"),
            ("tasks/Task.md", Self.task),
            ("tasks/Other.md", "---\ntype: task\nstatus: Not Started\nproject: \"[[ta da mvp]]\"\n---\nSee [[Task]].\n"),
        ] {
            let url = folder.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
    }

    private func cleanUp() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }

    private func read(_ path: String) throws -> String {
        try String(contentsOf: folder.appending(path: path), encoding: .utf8)
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

    @Test func selectingAFileOpensItsTextWithoutChangingIt() async throws {
        defer { cleanUp() }
        let model = await model(selecting: "tasks/Task.md")
        let document = try #require(model.document)
        #expect(document.text == Self.task)
        #expect(document.body == "Body line.\n\n- [ ] One\n- [x] Two\n")
        #expect(!document.isDirty)
        #expect(document.modified != nil)
    }

    @Test func bodyEditsUpdateTheIndexAndSaveOnlyTheBody() async throws {
        defer { cleanUp() }
        let model = await model(selecting: "tasks/Task.md")
        let document = try #require(model.document)
        document.body = document.body.replacingOccurrences(of: "- [ ] One", with: "- [x] One")
        #expect(document.isDirty)
        #expect(model.index["tasks/Task.md"].map { $0.subtasks.done == 2 && $0.subtasks.total == 2 } == true)

        await model.save(document)
        #expect(!document.isDirty)
        #expect(try read("tasks/Task.md") == Self.task.replacingOccurrences(of: "- [ ] One", with: "- [x] One"))
    }

    @Test func editsSaveAfterAPause() async throws {
        defer { cleanUp() }
        let model = await model(selecting: "tasks/Task.md")
        let document = try #require(model.document)
        document.body += "More.\n"
        #expect(try read("tasks/Task.md") == Self.task, "not yet")
        try await Task.sleep(for: .milliseconds(1200))
        #expect(try read("tasks/Task.md") == Self.task + "More.\n")
    }

    @Test func propertyEditsOnTheOpenFileGoThroughItsText() async throws {
        defer { cleanUp() }
        let model = await model(selecting: "tasks/Task.md")
        let document = try #require(model.document)
        await model.setStatus(.done, in: "tasks/Task.md")
        await model.setProperty("deadline", to: .date(LocalDate("2026-10-09")!), in: "tasks/Task.md")
        await model.setProperty("dueDate", to: nil, in: "tasks/Task.md")
        let expected = "---\ntype: task\nstatus: Done\nproject: \"[[Ta Da MVP]]\"\ndueDate:\ncompletedDate: 2026-10-03\ndeadline: 2026-10-09\n---\nBody line.\n\n- [ ] One\n- [x] Two\n"
        #expect(document.text == expected)
        #expect(model.index["tasks/Task.md"]?.properties.deadline == LocalDate("2026-10-09"))
        #expect(try read("tasks/Task.md") == Self.task, "saved later")

        // Switching files saves the previous one first.
        model.selection = "tasks/Other.md"
        await model.loadSelection()
        #expect(try read("tasks/Task.md") == expected)
        #expect(model.document?.path == "tasks/Other.md")
    }

    @Test func rowCompletionOfTheOpenFileEditsTheBuffer() async throws {
        defer { cleanUp() }
        let model = await model(selecting: "tasks/Task.md")
        await model.toggleCompletion(try #require(model.index["tasks/Task.md"]))
        #expect(model.document?.item?.properties.status == .done)
        #expect(model.document?.isDirty == true)
    }

    @Test func renamingATaskMovesItsFileAndKeepsItOpen() async throws {
        defer { cleanUp() }
        let model = await model(selecting: "tasks/Task.md")
        model.document?.body += "Unsaved.\n"
        await model.rename("tasks/Task.md", to: "Renamed: task")
        #expect(model.selection == "tasks/Renamed - task.md")
        #expect(model.document?.path == "tasks/Renamed - task.md")
        #expect(model.index["tasks/Task.md"] == nil)
        #expect(model.index["tasks/Renamed - task.md"] != nil)
        #expect(try read("tasks/Renamed - task.md") == Self.task + "Unsaved.\n", "saved before the move")
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "tasks/Task.md").path))
        #expect(try read("tasks/Other.md").contains("See [[Task]]."), "body links aren't rewritten")
    }

    @Test func renamingAProjectRelinksItsTasks() async throws {
        defer { cleanUp() }
        let model = await model()
        model.open("projects/Ta Da MVP.md")
        await model.loadSelection()
        await model.rename("projects/Ta Da MVP.md", to: "Ta Da 1.0")
        #expect(model.domain == .project("projects/Ta Da 1.0.md"))
        #expect(model.selection == "projects/Ta Da 1.0.md")
        #expect(try read("tasks/Task.md") == Self.task.replacingOccurrences(of: "[[Ta Da MVP]]", with: "[[Ta Da 1.0]]"))
        #expect(try read("tasks/Other.md").contains("project: \"[[Ta Da 1.0]]\"\n"))
        let project = try #require(model.index["projects/Ta Da 1.0.md"])
        #expect(model.index.tasks(in: project).map(\.title) == ["Other", "Task"])
    }

    @Test func aTaskThatCantBeRelinkedDoesntUndoTheRename() async throws {
        defer { cleanUp() }
        let model = await model()
        model.open("projects/Ta Da MVP.md")
        await model.loadSelection()
        try Data([0xff, 0xfe]).write(to: folder.appending(path: "tasks/Other.md"))
        await model.rename("projects/Ta Da MVP.md", to: "Ta Da 1.0")
        #expect(model.selection == "projects/Ta Da 1.0.md")
        #expect(model.document?.path == "projects/Ta Da 1.0.md")
        #expect(try read("tasks/Task.md").contains("project: \"[[Ta Da 1.0]]\"\n"))
        #expect(model.errorMessage?.contains("“Other”") == true)
    }

    @Test func newLinkedTaskIsCreatedSelectedAndReadyToName() async throws {
        defer { cleanUp() }
        let model = await model()
        model.domain = .project("projects/Ta Da MVP.md")
        await model.newTask()
        #expect(model.selection == "tasks/Untitled.md")
        #expect(model.titleFocus == "tasks/Untitled.md")
        #expect(try read("tasks/Untitled.md") == "---\ntype: task\nstatus: Not Started\nproject: \"[[Ta Da MVP]]\"\ncreatedDate: 2026-10-03\n---\n")
        let project = try #require(model.index["projects/Ta Da MVP.md"])
        #expect(model.index.tasks(in: project).map(\.title).contains("Untitled"))
    }

    @Test func newTasksLandWhereTheyShow() async throws {
        defer { cleanUp() }
        let model = await model()
        await model.newTask()
        #expect(model.domain == .today)
        #expect(model.index.today(model.today).map(\.path).contains("tasks/Untitled.md"), "due today")

        model.domain = .upcoming
        await model.newTask()
        #expect(model.domain == .loose)
        #expect(model.selection == "tasks/Untitled 2.md")

        await model.newProject()
        #expect(model.domain == .project("projects/Untitled.md"))
        #expect(model.selection == "projects/Untitled.md")
    }

    @Test func aDeletedSelectionShowsAnError() async throws {
        defer { cleanUp() }
        let model = await model()
        try FileManager.default.removeItem(at: folder.appending(path: "tasks/Other.md"))
        model.selection = "tasks/Other.md"
        await model.loadSelection()
        #expect(model.document == nil)
        #expect(model.documentError?.contains("Other") == true)
    }

    @Test func theLiveEditorEditsOnlyTheBody() async throws {
        defer { cleanUp() }
        let model = await model()
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 1280, height: 800),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.orderFrontRegardless()
        model.selection = "tasks/Task.md"
        try await Task.sleep(for: .milliseconds(800))

        func textView(in view: NSView) -> NSTextView? {
            if let textView = view as? NSTextView, textView.isEditable { return textView }
            return view.subviews.lazy.compactMap(textView(in:)).first
        }
        let editor = try #require(textView(in: window.contentView!))
        let document = try #require(model.document)
        #expect(!document.isDirty, "opening doesn't rewrite the file")

        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        editor.insertText("Z", replacementRange: NSRange(location: NSNotFound, length: 0))
        try await Task.sleep(for: .milliseconds(300))
        #expect(document.text == Self.task + "Z")
    }
}
