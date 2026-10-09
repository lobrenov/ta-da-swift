import Foundation
import Testing
@testable import TaDaCore

@Test func itemParsesAWholeFile() throws {
    let text = """
    ---
    type: task
    status: Doing
    contexts: ["@computer"]
    project: "[[Ta Da MVP]]"
    dueDate: 2026-10-02
    ---

    Bring the files in line.

    - [x] One
    - [ ] Two
      - [-] Cancelled
      - [/] Started
    - [!] Icon only

    Related: [[Ta Da MVP]]
    """
    let item = try #require(Item(parsing: text, path: "Update files.md"))
    #expect(item.title == "Update files")
    #expect(item.properties.kind == .task && item.properties.status == .doing)
    #expect(item.summary == "Bring the files in line.")
    #expect(item.checkboxes.map(\.lineIndex) == [10, 11, 12, 13, 14])
    #expect(item.subtasks == (done: 1, total: 3))
    #expect(item.links.map(\.title) == ["Ta Da MVP"])
    #expect(item.warnings.isEmpty)
}

@Test func itemCheckboxLinesAreFileLinesWithCRLF() throws {
    let text = "---\r\ntype: task\r\nstatus: Done\r\n---\r\n- [x] A\r\n- [ ] B\r\n"
    let item = try #require(Item(parsing: text, path: "T.md"))
    let lines = text.components(separatedBy: "\r\n")
    for box in item.checkboxes {
        #expect(Array(lines[box.lineIndex].utf8)[box.column] == box.marker.asciiValue)
    }
    #expect(item.subtasks == (done: 1, total: 2))
}

@Test(arguments: [
    "No frontmatter\n\n- [ ] not a subtask\n",
    "---\nstatus: Doing\n---\nBody\n",
    "---\ntype: note\n---\n",
    "---\ntype: task\nnever closed\n",
    "",
])
func itemIgnoresNonTaDaFiles(_ text: String) {
    #expect(Item(parsing: text, path: "x.md") == nil)
}

@Test func itemWithBrokenYAMLStillLoads() throws {
    let item = try #require(Item(parsing: "---\ntype: task\ncontexts:\n  - @computer\n---\n- [ ] Still counted\n", path: "Broken.md"))
    #expect(item.subtasks == (done: 0, total: 1))
    #expect(item.warnings.count == 1)
}

/// Every SampleVault file parses cleanly; the note without frontmatter is ignored.
@Test func sampleVaultParses() throws {
    let files = try sampleFiles()
    #expect(files.count > 20)

    var items: [String: Item] = [:]
    for file in files {
        let title = file.deletingPathExtension().lastPathComponent
        guard let item = Item(parsing: try String(contentsOf: file, encoding: .utf8), path: file.lastPathComponent) else {
            #expect(file.path.contains("/notes/"), "\(title) didn't parse")
            continue
        }
        // The design's tasks name an area beside their project, which ignores it.
        let ignored = item.warnings.filter { if case .areaIgnored = $0 { true } else { false } }
        #expect(item.warnings == ignored && ignored.count == (item.properties.project != nil ? 1 : 0), "\(title): \(item.warnings)")
        #expect(item.properties.kind == (file.path.contains("/projects/") ? .project : .task), "\(title)")
        items[title] = item
    }
    #expect(items["Not a task"] == nil)

    let claude = try #require(items["Update my claude.md files"])
    #expect(claude.properties.area?.title == "Personal")
    #expect(claude.properties.project == nil && claude.properties.repeatRule == nil)
    #expect(claude.subtasks == (done: 2, total: 5))
    #expect(claude.links.map(\.title) == ["Ta Da MVP"])

    let timesheet = try #require(items["Submit timesheet"])
    #expect(timesheet.properties.repeatRule == "Weekly · Fri")

    let website = try #require(items["Update Dan’s website for Starfall"])
    #expect(website.properties.project?.title == "Game Jam - Starfall")
    #expect(website.properties.deadline == LocalDate("2026-10-08"))
}
