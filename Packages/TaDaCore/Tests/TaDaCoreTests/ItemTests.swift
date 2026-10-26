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

@Test(arguments: [
    ("Some text.\n", true),
    ("- One\n- Two\n", true),
    ("## Heading\n", true),
    ("- [ ] A\n- [x] B\n", false),
    ("\n\n", false),
    ("", false),
])
func itemHasNoteWhenTheBodyHasMoreThanCheckboxes(body: String, hasNote: Bool) throws {
    let item = try #require(Item(parsing: "---\r\ntype: task\r\n---\r\n" + body, path: "T.md"))
    #expect(item.hasNote == hasNote)
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
func untypedFilesAreNotesOnlyAtNotePaths(_ text: String) {
    #expect(Item(parsing: text, path: "x.md")?.properties.kind == .note)
    #expect(Item(parsing: text, path: "Meetings/x.md")?.properties.kind == .note)
    #expect(Item(parsing: text, path: "Ta Da/tasks/x.md") == nil)
}

@Test func notePaths() {
    for path in ["Note.md", "A/B/Note.MD", "Meetings/tasks/Note.md", "tasks/Note.md", "attachments/Note.md", ".trash/Note.md", ".trash/Meetings/Note.md"] {
        #expect(Item.isNotePath(path), "\(path)")
    }
    for path in ["Ta Da/Note.md", "ta da/tasks/Note.md", "Ta Da/logbook/2026-10/Note.md",
                 ".obsidian/Note.md", "A/.hidden/Note.md", ".Note.md", "Note.txt", ".trash/Ta Da/Note.md"] {
        #expect(!Item.isNotePath(path), "\(path)")
    }
}

@Test func typedFilesAreNeverNotes() throws {
    let item = try #require(Item(parsing: "---\ntype: Task\nstatus: Doing\n---\n", path: "Meetings/x.md"))
    #expect(item.properties.kind == .task)
}

@Test func noteReadsCreatedDateAndTagsOnly() throws {
    let text = "---\ncreatedDate: 2026-10-04\ntags: [work, ark]\nstatus: Done\ndueDate: 2026-10-05\narea: \"[[Work]]\"\n---\n- [x] A\n- [ ] B\n- [-] C\n#plan\n"
    let item = try #require(Item(parsing: text, path: "Meetings/Ark.md"))
    #expect(item.properties.kind == .note)
    #expect(item.properties.createdDate == LocalDate("2026-10-04"))
    #expect(item.tags.map(\.tag.path) == ["work", "ark", "plan"])
    #expect(item.properties.status == .notStarted && item.properties.dueDate == nil && item.properties.area == nil)
    #expect(item.subtasks == (done: 1, total: 2))
    #expect(item.warnings.isEmpty)
}

@Test func noteWithBrokenYAMLLoadsWithAWarning() throws {
    let item = try #require(Item(parsing: "---\ntags: [a\n---\nBody\n", path: "Broken.md"))
    #expect(item.properties.kind == .note)
    #expect(item.warnings.count == 1)
}

@Test func itemWithBrokenYAMLStillLoads() throws {
    let item = try #require(Item(parsing: "---\ntype: task\ncontexts:\n  - @computer\n---\n- [ ] Still counted\n", path: "Broken.md"))
    #expect(item.subtasks == (done: 0, total: 1))
    #expect(item.warnings.count == 1)
}

/// Every SampleVault file parses cleanly; the note without frontmatter and the daily and week notes are notes.
@Test func sampleVaultParses() throws {
    let files = try sampleFiles()
    #expect(files.count > 20)

    var items: [String: Item] = [:]
    for file in files {
        let title = file.deletingPathExtension().lastPathComponent
        let item = try #require(Item(parsing: try String(contentsOf: file, encoding: .utf8), path: file.lastPathComponent), "\(title) didn't parse")
        guard item.properties.kind != .note else {
            #expect(file.path.contains("/notes/") || file.path.contains("/Periodic Notes/"), "\(title) is a note")
            continue
        }
        // The design's tasks name an area beside their project, which ignores it, and its `Weekly · Fri` isn't a rule.
        let warnings = item.warnings.filter { if case .invalidRepeat("Weekly · Fri") = $0 { false } else { true } }
        let ignored = warnings.filter { if case .areaIgnored = $0 { true } else { false } }
        #expect(warnings == ignored && ignored.count == (item.properties.project != nil ? 1 : 0), "\(title): \(item.warnings)")
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
    #expect(timesheet.properties.repeatRule?.text == "Weekly · Fri")

    let website = try #require(items["Update Dan’s website for Starfall"])
    #expect(website.properties.project?.title == "Game Jam - Starfall")
    #expect(website.properties.deadline == LocalDate("2026-10-08"))
}

@Test func itemMergesFrontmatterAndBodyTags() throws {
    // The canvas's TagModel file.
    let text = """
    ---
    type: task
    status: Not Started
    area: "[[Personal]]"
    tags: [errands, quick win]
    createdDate: 2026-10-01
    ---
    # Message Max about a coat and a jacket

    Ask #people/max about a coat and a jacket
    in the same fabric as my pants. #Errands, #fabric

    - [ ] Find the receipt `#not-a-tag`
    """
    let item = try #require(Item(parsing: text, path: "tasks/Message Max.md"))
    #expect(item.properties.tags.map(\.name) == ["errands", "quick win"])
    #expect(item.tags.map { "\($0.tag.name) \($0.inFrontmatter) \($0.inBody)" } == [
        "errands true true",
        "quick win true false",
        "people/max false true",
        "fabric false true",
    ])
}
