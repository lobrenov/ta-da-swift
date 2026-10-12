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
        #expect(task.lines.map { ($0.added ? "+ " : "  ") + $0.text } == [
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
        #expect(area.lines.filter(\.added).map(\.text) == ["type: area"])
        #expect(area.subtasks == "An area counts no subtasks; its checkboxes stay as written.")
    }
}
