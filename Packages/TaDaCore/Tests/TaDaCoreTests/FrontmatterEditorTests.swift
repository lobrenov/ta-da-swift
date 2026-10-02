import Testing
@testable import TaDaCore

private let file = """
---
type: task
# a comment
status: Not Started
statusNote: keep me
contexts:
  - "@computer"
  - "@home"
dueDate:   2026-10-02   
nested:
  status: untouched
custom: [1, 2]
---
Body with status: Done
"""

@Test func setReplacesOnlyTheKeysLine() {
    let after = FrontmatterEditor.set("status", to: .text("Done"), in: file)
    #expect(changedLines(file, after) == (["status: Not Started"], ["status: Done"]))
}

@Test func setReplacesAMultiLineValue() {
    let after = FrontmatterEditor.set("contexts", to: .list(["@phone"]), in: file)
    #expect(changedLines(file, after) == (["  - \"@computer\"", "  - \"@home\""], ["  - \"@phone\""]))
    let empty = FrontmatterEditor.set("contexts", to: .list([]), in: file)
    #expect(changedLines(file, empty) == (["contexts:", "  - \"@computer\"", "  - \"@home\""], ["contexts: []"]))
}

@Test func setReplacesFlowAndUnindentedLists() {
    let flow = "---\ncontexts: [\"@a\"]\ntype: task\n---\n"
    #expect(FrontmatterEditor.set("contexts", to: .list(["@b", "@c"]), in: flow) == "---\ncontexts:\n  - \"@b\"\n  - \"@c\"\ntype: task\n---\n")
    let unindented = "---\ncontexts:\n- \"@a\"\n-\ntype: task\n---\n"
    #expect(FrontmatterEditor.set("contexts", to: .list(["@b"]), in: unindented) == "---\ncontexts:\n  - \"@b\"\ntype: task\n---\n")
}

@Test func setMatchesWholeUnindentedKeysOnly() {
    let after = FrontmatterEditor.set("due", to: .date(LocalDate("2026-11-01")!), in: file)
    #expect(changedLines(file, after) == ([], ["due: 2026-11-01"]))
    #expect(after.contains("dueDate:   2026-10-02   \n"))
    #expect(after.contains("  status: untouched\n"))
    #expect(after.contains("Body with status: Done"))
}

@Test func setAppendsAMissingKeyBeforeTheClosingFence() {
    let after = FrontmatterEditor.set("deadline", to: .date(LocalDate("2026-10-06")!), in: file)
    #expect(changedLines(file, after) == ([], ["deadline: 2026-10-06"]))
    #expect(after.contains("custom: [1, 2]\ndeadline: 2026-10-06\n---\n"))
}

@Test func setHandlesEmptyFrontmatterAndAFenceAtEndOfFile() {
    #expect(FrontmatterEditor.set("type", to: .text("task"), in: "---\n---\nBody") == "---\ntype: task\n---\nBody")
    #expect(FrontmatterEditor.set("status", to: .text("Done"), in: "---\ntype: task\n---") == "---\ntype: task\nstatus: Done\n---")
}

@Test func setCreatesFrontmatterWhenThereIsNone() {
    #expect(FrontmatterEditor.set("type", to: .text("task"), in: "Just a body\n") == "---\ntype: task\n---\nJust a body\n")
    #expect(FrontmatterEditor.set("type", to: .text("task"), in: "") == "---\ntype: task\n---\n")
    #expect(FrontmatterEditor.set("type", to: .text("task"), in: "Body\r\nMore\r\n") == "---\r\ntype: task\r\n---\r\nBody\r\nMore\r\n")
    // An unclosed fence isn't frontmatter, so a new block goes above it.
    #expect(FrontmatterEditor.set("type", to: .text("task"), in: "---\nnot closed\n") == "---\ntype: task\n---\n---\nnot closed\n")
}

@Test func setKeepsCRLF() {
    let crlf = "---\r\ntype: task\r\nstatus: Doing\r\ncontexts:\r\n  - \"@a\"\r\n---\r\nBody\r\n"
    #expect(FrontmatterEditor.set("status", to: .text("Done"), in: crlf) == "---\r\ntype: task\r\nstatus: Done\r\ncontexts:\r\n  - \"@a\"\r\n---\r\nBody\r\n")
    #expect(FrontmatterEditor.set("contexts", to: .list(["@b", "@c"]), in: crlf) == "---\r\ntype: task\r\nstatus: Doing\r\ncontexts:\r\n  - \"@b\"\r\n  - \"@c\"\r\n---\r\nBody\r\n")
    #expect(FrontmatterEditor.set("area", to: .text("Work"), in: crlf) == "---\r\ntype: task\r\nstatus: Doing\r\ncontexts:\r\n  - \"@a\"\r\narea: Work\r\n---\r\nBody\r\n")
}

@Test func clearEmptiesAnExistingKeyOnly() {
    let after = FrontmatterEditor.clear("contexts", in: file)
    #expect(changedLines(file, after) == (["  - \"@computer\"", "  - \"@home\""], []))
    #expect(FrontmatterEditor.clear("deadline", in: file) == file)
    #expect(FrontmatterEditor.clear("type", in: "No frontmatter") == "No frontmatter")
    #expect(FrontmatterEditor.clear("dueDate", in: "---\r\ndueDate: 2026-10-02\r\n---\r\n") == "---\r\ndueDate:\r\n---\r\n")
}

@Test func writtenValuesUseTheWritingRules() {
    let base = "---\ntype: task\n---\n"
    #expect(FrontmatterEditor.set("project", to: .link(title: "Ta Da MVP"), in: base).contains("project: \"[[Ta Da MVP]]\"\n"))
    #expect(FrontmatterEditor.set("dueDate", to: .date(LocalDate("2026-01-05")!), in: base).contains("dueDate: 2026-01-05\n"))
    #expect(FrontmatterEditor.set("status", to: .text("Not Started"), in: base).contains("status: Not Started\n"))
    #expect(FrontmatterEditor.set("area", to: .text("yes"), in: base).contains("area: \"yes\"\n"))
}

@Test(arguments: [
    "Personal", "Weekly · Fri", "Dan’s", "yes", "No", "null", "~", "2026", "2026-10-02", "@home", "#tag", "-dash",
    "a: b", "a #b", "ends:", " padded ", "quote\"d", "it's", "back\\slash", "tab\there", "line\nbreak", "[x]", "{y}", "*star", "!bang", "Café ☕️",
])
func textValuesReadBackUnchanged(_ value: String) throws {
    let text = FrontmatterEditor.set("area", to: .text(value), in: "---\ntype: task\nstatus: Doing\n---\n")
    let read = try #require(PropertyReader.read(FrontmatterSplitter.split(text).yaml!))
    #expect(read.properties.area == value)
    #expect(read.warnings.isEmpty)
}

@Test func listAndLinkValuesReadBackUnchanged() throws {
    var text = "---\ntype: task\nstatus: Doing\n---\n"
    text = FrontmatterEditor.set("contexts", to: .list(["@computer", "a \"q\"", "Café"]), in: text)
    text = FrontmatterEditor.set("project", to: .link(title: "Game Jam - Starfall"), in: text)
    let read = try #require(PropertyReader.read(FrontmatterSplitter.split(text).yaml!))
    #expect(read.properties.contexts == ["@computer", "a \"q\"", "Café"])
    #expect(read.properties.project?.title == "Game Jam - Starfall")
}
