import Testing
import Yams
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
    let text = FrontmatterEditor.set("repeat", to: .text(value), in: "---\ntype: task\nstatus: Doing\n---\n")
    let read = try #require(PropertyReader.read(FrontmatterSplitter.split(text).yaml!))
    #expect(read.properties.repeatRule == value)
    #expect(read.warnings.isEmpty)
}

@Test func listAndLinkValuesReadBackUnchanged() throws {
    var text = "---\ntype: task\nstatus: Doing\n---\n"
    text = FrontmatterEditor.set("contexts", to: .list(["@computer", "a \"q\"", "Café"]), in: text)
    text = FrontmatterEditor.set("project", to: .link(title: "Game Jam - Starfall"), in: text)
    let yaml = try #require(FrontmatterSplitter.split(text).yaml)
    #expect((try Yams.load(yaml: yaml) as? [String: Any])?["contexts"] as? [String] == ["@computer", "a \"q\"", "Café"])
    #expect(try #require(PropertyReader.read(yaml)).properties.project?.title == "Game Jam - Starfall")
}

// MARK: Tags

private func tag(_ name: String) -> TaDaCore.Tag { TaDaCore.Tag(name)! }

/// The file's tags after parsing, by name.
private func tagNames(_ text: String) throws -> [String] {
    try #require(Item(parsing: text, path: "t.md")).properties.tags.map(\.name)
}

@Test func addTagInsertsAMissingKeyAfterCreatedDate() throws {
    let text = "---\ntype: task\nstatus: Doing\ncreatedDate: 2026-10-01\ndueDate: 2026-10-02\n---\nBody #inline\n"
    let after = FrontmatterEditor.addTag(tag("errands"), in: text)
    #expect(after == "---\ntype: task\nstatus: Doing\ncreatedDate: 2026-10-01\ntags: [errands]\ndueDate: 2026-10-02\n---\nBody #inline\n")
    #expect(FrontmatterEditor.addTag(tag("quick win"), in: "---\r\ntype: area\r\n---\r\n") == "---\r\ntype: area\r\ntags: [quick win]\r\n---\r\n")
    #expect(FrontmatterEditor.addTag(tag("a"), in: "No frontmatter #a\n") == "No frontmatter #a\n")
}

@Test func addTagKeepsAFlowList() throws {
    let text = "---\ntype: task\nstatus: Doing\ntags: [Errands, \"#home/garden\"] # keep\n---\n"
    let after = FrontmatterEditor.addTag(tag("people/Max"), in: text)
    #expect(changedLines(text, after) == (["tags: [Errands, \"#home/garden\"] # keep"], ["tags: [Errands, \"#home/garden\", people/Max] # keep"]))
    #expect(FrontmatterEditor.addTag(tag("errands"), in: text) == text, "already there, ignoring case")
    #expect(FrontmatterEditor.addTag(tag("HOME/GARDEN"), in: text) == text)
    let multiLine = "---\ntype: task\ntags: [a,\n  b]\n---\n"
    #expect(FrontmatterEditor.addTag(tag("c"), in: multiLine) == "---\ntype: task\ntags: [a, b, c]\n---\n")
    #expect(try tagNames(FrontmatterEditor.addTag(tag("x, y"), in: text)) == ["Errands", "home/garden", "x, y"])
}

@Test func addTagKeepsABlockList() throws {
    let text = "---\ntype: task\ntags:\n  - errands\n  # a comment\n  - \"quick win\"\nstatus: Doing\n---\n"
    let after = FrontmatterEditor.addTag(tag("home/garden"), in: text)
    #expect(after == "---\ntype: task\ntags:\n  - errands\n  # a comment\n  - \"quick win\"\n  - home/garden\nstatus: Doing\n---\n")
    let unindented = "---\r\ntype: task\r\ntags:\r\n- errands\r\n---\r\n"
    #expect(FrontmatterEditor.addTag(tag("2026"), in: unindented) == "---\r\ntype: task\r\ntags:\r\n- errands\r\n- \"2026\"\r\n---\r\n")
    #expect(FrontmatterEditor.addTag(tag("Quick Win"), in: text) == text)
}

@Test func addTagTurnsAnEmptyKeyOrAStringIntoAFlowList() throws {
    for empty in ["tags:", "tags: []", "tags: ~", "tags: # none yet"] {
        #expect(FrontmatterEditor.addTag(tag("a"), in: "---\ntype: task\n\(empty)\n---\n") == "---\ntype: task\ntags: [a]\n---\n", "\(empty)")
    }
    #expect(FrontmatterEditor.addTag(tag("c"), in: "---\ntype: task\ntags: a, b\n---\n") == "---\ntype: task\ntags: [a, b, c]\n---\n")
    #expect(FrontmatterEditor.addTag(tag("c"), in: "---\ntype: task\ntags: \"a, #b\"\n---\n") == "---\ntype: task\ntags: [a, \"#b\", c]\n---\n")
    #expect(FrontmatterEditor.addTag(tag("B"), in: "---\ntype: task\ntags: \"a, #b\"\n---\n") == "---\ntype: task\ntags: \"a, #b\"\n---\n")
}

@Test func removeTagKeepsTheListsStyle() throws {
    let flow = "---\ntype: task\ntags: [Errands, \"#home/garden\", 'quick win']\n---\nBody #errands\n"
    #expect(FrontmatterEditor.removeTag(tag("home/garden"), in: flow) == "---\ntype: task\ntags: [Errands, 'quick win']\n---\nBody #errands\n")
    let block = "---\ntype: task\ntags:\n  - errands\n  - \"#Home/Garden\"\n  - quick win\nstatus: Doing\n---\n"
    #expect(FrontmatterEditor.removeTag(tag("home/garden"), in: block) == "---\ntype: task\ntags:\n  - errands\n  - quick win\nstatus: Doing\n---\n")
    #expect(FrontmatterEditor.removeTag(tag("b"), in: "---\ntype: task\ntags: a, b\n---\n") == "---\ntype: task\ntags: [a]\n---\n")
}

@Test func removingTheLastTagLeavesAnEmptyKey() throws {
    #expect(FrontmatterEditor.removeTag(tag("a"), in: "---\ntype: task\ntags: [a]\n---\n") == "---\ntype: task\ntags:\n---\n")
    #expect(FrontmatterEditor.removeTag(tag("a"), in: "---\r\ntype: task\r\ntags:\r\n  - A\r\nstatus: Doing\r\n---\r\n") == "---\r\ntype: task\r\ntags:\r\nstatus: Doing\r\n---\r\n")
    #expect(FrontmatterEditor.removeTag(tag("a"), in: "---\ntype: task\ntags: a\n---\n") == "---\ntype: task\ntags:\n---\n")
    #expect(try tagNames("---\ntype: task\nstatus: Doing\ntags:\n---\n").isEmpty)
}

@Test func removeTagLeavesOtherTextAlone() {
    let text = "---\ntype: task\ntags: [a]\n---\n#b in the body\n"
    #expect(FrontmatterEditor.removeTag(tag("b"), in: text) == text, "body tags are never rewritten")
    #expect(FrontmatterEditor.removeTag(tag("a"), in: "---\ntype: task\n---\n") == "---\ntype: task\n---\n")
    #expect(FrontmatterEditor.removeTag(tag("a"), in: "#a only") == "#a only")
}

@Test(arguments: ["errands", "quick win", "home/garden", "2026", "-dash", "yes", "a: b", "x, y", "[x]", "Café ☕️", "#hash"])
func addedAndRemovedTagsReadBack(_ name: String) throws {
    let new = tag(name)
    for list in ["tags: [first]", "tags:\n  - first", "tags: first", ""] {
        let text = "---\ntype: task\nstatus: Doing\ncreatedDate: 2026-10-01\n\(list)\n---\n"
        let added = FrontmatterEditor.addTag(new, in: text)
        let expected = list.isEmpty ? [new.name] : ["first", new.name]
        #expect(try tagNames(added) == expected, "\(list)")
        #expect(try tagNames(FrontmatterEditor.removeTag(new, in: added)) == expected.dropLast(), "\(list)")
    }
}
