import Foundation
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct ConvertPreviewTests {
    private let today = LocalDate("2026-10-12")!
    private let text = "---\ncreatedDate: 2026-10-04\ntags: [travel]\n---\n- [x] Passport\n- [ ] Charger\n- [-] Kettle\n"

    private func preview(_ kind: Item.Kind, parent: Parent? = nil, taken: Set<String> = [], folderLinks: Int = 0) throws -> ConvertPreview {
        let note = try #require(Item(parsing: text, path: "Packing list.md"))
        return ConvertPreview(note: note, text: text, kind: kind, status: .notStarted, parent: parent, today: today,
                              taken: taken, folderLinks: folderLinks)
    }

    @Test func aTaskShowsItsMoveAddedKeysAndSubtasks() throws {
        let task = try preview(.task, parent: .project("Trip"))
        #expect(task.from == "Packing list.md" && task.to == "tasks/Packing list.md")
        #expect(task.lines.map { ($0.change == .added ? "+ " : "  ") + $0.text } == [
            "  ---", "+ type: task", "+ status: Not Started", "+ project: \"[[Trip]]\"", "  createdDate: 2026-10-04",
            "  tags: [travel]", "  ---",
        ])
        #expect(task.subtasks == "3 checkboxes become its subtasks · 1/2")
        #expect(task.links == "Links to it by title keep working.")
    }

    @Test func aProjectNumbersATakenNameAndCountsFolderLinks() throws {
        let project = try preview(.project, taken: ["Packing list.md"], folderLinks: 2)
        #expect(project.to == "projects/Packing list 2.md")
        #expect(project.links == "2 links written with its folder are rewritten.")
    }

    @Test func anAreaHasNoStatusAndNoSubtasks() throws {
        let area = try preview(.area, parent: .area("Home"))
        #expect(area.lines.filter { $0.change == .added }.map(\.text) == ["type: area"])
        #expect(area.subtasks == "An area counts no subtasks; its checkboxes stay as written.")
    }

    private func lines(_ text: String, _ kind: Item.Kind = .task, parent: Parent? = nil) throws -> [String] {
        let note = try #require(Item(parsing: text, path: "Note.md"))
        return ConvertPreview(note: note, text: text, kind: kind, status: .notStarted, parent: parent, today: today, taken: [],
                              folderLinks: 0).lines.map { line in
            (line.change == .added ? "+ " : line.change == .removed ? "- " : "  ") + line.text
        }
    }

    @Test func aNoteWithoutFrontmatterGetsEveryLine() throws {
        #expect(try lines("Body\n") == ["+ ---", "+ type: task", "+ status: Not Started", "+ createdDate: 2026-10-12", "+ ---"])
    }

    @Test func crlfLinesAreKeptAndReplacedKeysShowAsRemoved() throws {
        #expect(try lines("---\r\nstatus: Doing\r\nproject: \"[[Old]]\"\r\ntags: []\r\n---\r\n") == [
            "  ---", "+ type: task", "+ createdDate: 2026-10-12", "+ status: Not Started", "+ project:", "  tags: []",
            "- status: Doing", "- project: \"[[Old]]\"", "  ---",
        ])
    }

    @Test func subtasksCountTheTextBeingConverted() throws {
        let note = try #require(Item(parsing: "- [ ] One\n", path: "Note.md"))
        let preview = ConvertPreview(note: note, text: "- [ ] One\n- [x] Two\n", kind: .task, status: .notStarted, parent: nil,
                                     today: today, taken: [], folderLinks: 0)
        #expect(preview.subtasks == "2 checkboxes become its subtasks · 1/2")
    }

    @Test func thePreviewsPathIsWhereConvertPutsTheFile() async throws {
        let folder = try TestFolder([
            "Meeting #3.md": "Body\n",
            "Packing list.md": "Body\n",
            "projects/Packing list.md": "---\ntype: project\nstatus: Doing\n---\n",
        ])
        let model = await folder.model()
        let vault = try #require(model.vault)
        for (path, kind) in [("Meeting #3.md", Item.Kind.task), ("Packing list.md", .project)] {
            let note = try #require(model.index[path])
            let taken = vault.filenames(in: kind == .task ? Vault.taskFolder : Vault.projectFolder).union(model.index.projectFilenames())
            let preview = ConvertPreview(note: note, text: try vault.read(path), kind: kind, status: .notStarted, parent: nil,
                                         today: today, taken: taken, folderLinks: 0)
            let result = try vault.convert(path, to: kind, index: model.index, today: today)
            #expect(preview.to == result.path)
        }
    }
}
