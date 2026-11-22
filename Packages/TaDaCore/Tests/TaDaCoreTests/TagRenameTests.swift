import Foundation
import Testing
@testable import TaDaCore

private func tag(_ name: String) -> TaDaCore.Tag { Tag(name)! }
private func front(_ tags: String) -> String { "---\ntype: task\nstatus: Doing\n\(tags)\ncreatedDate: 2026-09-01\n---\nbody #home\n" }

private func rename(_ from: String, _ to: String, _ text: String) -> String? { FrontmatterEditor.renameTag(tag(from), to: tag(to), in: text) }
private func delete(_ name: String, _ text: String) -> String? { FrontmatterEditor.deleteTag(tag(name), in: text) }

@Test func renamingKeepsTheListsStyle() {
    #expect(rename("a", "x", front("tags: [a, \"b c\"]")) == front("tags: [x, \"b c\"]"))
    #expect(rename("a", "x", front("tags:\n  - a\n  - \"b c\"")) == front("tags:\n  - x\n  - \"b c\""))
    #expect(rename("a", "x y", front("tags:\n  - a")) == front("tags:\n  - x y"))
    #expect(rename("a", "x", front("tags: a, b")) == front("tags: [x, b]"))
    #expect(rename("a", "x", front("tags: [a] # keep")) == front("tags: [x] # keep"))
}

@Test func renamingNeverTouchesTheBody() {
    let after = rename("home", "house", front("tags: [home]"))
    #expect(after == front("tags: [house]"))
    #expect(after?.hasSuffix("body #home\n") == true)
}

@Test func aRenameThatMatchesNothingReturnsTheTextUnchanged() {
    let text = front("tags: [a, b]")
    #expect(rename("missing", "x", text) == text)
    #expect(rename("a", "a", text) == text)
    #expect(rename("a", "x", "no frontmatter") == "no frontmatter")
    #expect(delete("missing", text) == text)
}

@Test func renamingToAnExistingTagMerges() {
    #expect(rename("a", "b", front("tags: [a, B, c]")) == front("tags: [B, c]"))
    #expect(rename("a", "b", front("tags:\n  - a\n  - b\n  - c")) == front("tags:\n  - b\n  - c"))
    #expect(rename("a", "b", front("tags: [b, a]")) == front("tags: [b]"))
    #expect(rename("a", "b", front("tags: a, b")) == front("tags: [b]"))
}

@Test func aCaseOnlyRenameRewritesEverySpelling() {
    #expect(rename("work", "Work", front("tags: [work, WORK/x]")) == front("tags: [Work]").replacingOccurrences(of: "[Work]", with: "[Work, Work/x]"))
    #expect(rename("work", "Work", front("tags: [Work]")) == front("tags: [Work]"))
}

@Test func renamingMovesChildrenAndKeepsTheirRest() {
    #expect(rename("home/garden", "house/garden", front("tags: [home/garden, home/garden/Beds, home]"))
            == front("tags: [house/garden, house/garden/Beds, home]"))
    #expect(rename("home", "house", front("tags: [Home/Garden/Beds, homework]")) == front("tags: [house/Garden/Beds, homework]"))
    #expect(rename("home", "a/b", front("tags: [home/x]")) == front("tags: [a/b/x]"))
}

@Test func renamingQuotesLikeAddTag() {
    #expect(rename("a", "x, y", front("tags: [a]")) == front("tags: [\"x, y\"]"))
    #expect(rename("a", "yes", front("tags:\n  - a")) == front("tags:\n  - \"yes\""))
}

@Test func deletingRemovesTheTagAndItsChildren() {
    #expect(delete("home", front("tags: [home, Home/garden, homework, b]")) == front("tags: [homework, b]"))
    #expect(delete("home", front("tags:\n  - home\n  - b\n  - home/x")) == front("tags:\n  - b"))
    #expect(delete("home", front("tags: [home, home/x]")) == front("tags:"))
    #expect(delete("home", front("tags:\n  - home/x")) == front("tags:"))
    #expect(delete("a", front("tags: a, b")) == front("tags: [b]"))
}

@Test func unsplicableValuesReportTheTagOnlyWhenTheyCarryIt() {
    let block = front("tags: |\n  a, b")
    let commented = front("tags: [a, # c\n  b]")
    let multiline = front("tags: a,\n  b")
    for text in [block, commented, multiline] {
        #expect(rename("a", "x", text) == nil)
        #expect(delete("a", text) == nil)
        #expect(rename("missing", "x", text) == text)
        #expect(delete("missing", text) == text)
    }
}

@Test func crlfIsKept() {
    let crlf = front("tags: [a, b]").replacingOccurrences(of: "\n", with: "\r\n")
    #expect(rename("a", "x", crlf) == front("tags: [x, b]").replacingOccurrences(of: "\n", with: "\r\n"))
    let block = front("tags:\n  - a\n  - b").replacingOccurrences(of: "\n", with: "\r\n")
    #expect(rename("a", "x", block) == front("tags:\n  - x\n  - b").replacingOccurrences(of: "\n", with: "\r\n"))
    #expect(delete("a", block) == front("tags:\n  - b").replacingOccurrences(of: "\n", with: "\r\n"))
}

// MARK: Whole file

private let both = "---\ntype: task\ntags: [home, home/garden, work]\n---\nSee #home and #Home/Garden/Beds, #homework, `#home`, [#home](x).\n"

@Test func aFileEditChangesTagsAndBody() {
    let renamed = TagEditor.rename(tag("home"), to: tag("house"), in: both)
    #expect(renamed.text == "---\ntype: task\ntags: [house, house/garden, work]\n---\nSee #house and #house/Garden/Beds, #homework, `#home`, [#home](x).\n")
    #expect(!renamed.unspliceable)
    let deleted = TagEditor.delete(tag("home"), in: both)
    #expect(deleted.text == "---\ntype: task\ntags: [work]\n---\nSee and, #homework, `#home`, [#home](x).\n")
}

@Test func aFileEditLeavesTheFrontmatterBytesAloneWhenOnlyTheBodyChanges() {
    let text = "---\ntype: note\n# #home in a comment\ntitle: \"#home\"\n---\n#home\n"
    #expect(TagEditor.rename(tag("home"), to: tag("house"), in: text).text == "---\ntype: note\n# #home in a comment\ntitle: \"#home\"\n---\n#house\n")
    #expect(TagEditor.delete(tag("home"), in: text).text == "---\ntype: note\n# #home in a comment\ntitle: \"#home\"\n---\n\n")
}

@Test func aFileEditWithAnUnsplicableValueStillEditsTheBody() {
    let text = "---\ntype: task\ntags: [home, # c\n  b]\n---\n#home\n"
    let renamed = TagEditor.rename(tag("home"), to: tag("house"), in: text)
    #expect(renamed.unspliceable)
    #expect(renamed.text == "---\ntype: task\ntags: [home, # c\n  b]\n---\n#house\n")
    #expect(!TagEditor.rename(tag("missing"), to: tag("x"), in: text).unspliceable)
}

@Test func aFileEditKeepsCRLFAndReadsFilesWithoutFrontmatter() {
    let crlf = both.replacingOccurrences(of: "\n", with: "\r\n")
    #expect(TagEditor.delete(tag("home"), in: crlf).text == "---\r\ntype: task\r\ntags: [work]\r\n---\r\nSee and, #homework, `#home`, [#home](x).\r\n")
    #expect(TagEditor.rename(tag("a"), to: tag("b"), in: "x #a\n").text == "x #b\n")
}

@Test func validNamesAreThoseTheParserReadsAsOneWholeTag() {
    for name in ["home", "home/garden", "a_b-c", "2026/x", "x1", "Café"] { #expect(Tag.isValidName(name), "\(name)") }
    for name in ["", "2026", "2026/10", "/", "a b", "a,b", "a.b", "home/ ", "#home", "a\nb", "[x]"] { #expect(!Tag.isValidName(name), "\(name)") }
}

// MARK: Index and vault

private func tagged(_ tags: String, _ body: String) -> String { "---\ntype: task\nstatus: Doing\ntags: \(tags)\n---\n\(body)" }

@Test func theIndexListsEveryCarrierOfATagOrAChildLoggedIncluded() {
    let items = [
        Item(parsing: tagged("[home]", ""), path: "Ta Da/tasks/A.md")!,
        Item(parsing: tagged("[]", "#Home/garden"), path: "Ta Da/tasks/B.md")!,
        Item(parsing: tagged("[homework]", ""), path: "Ta Da/tasks/C.md")!,
        Item(parsing: "---\ntype: task\nstatus: Done\ncompletedDate: 2020-01-01\ntags: [home]\n---\n", path: "Ta Da/logbook/D.md")!,
    ]
    let index = VaultIndex(items)
    #expect(index.paths(carryingOrUnder: tag("HOME")) == ["Ta Da/logbook/D.md", "Ta Da/tasks/A.md", "Ta Da/tasks/B.md"])
    #expect(index.paths(carryingOrUnder: tag("missing")).isEmpty)
}

@Test func renamingATagWritesEachCarrierOnceAndReportsWhatItCouldntSplice() async throws {
    try await withTemporaryFolder { folder in
        let flow = tagged("[home, work]", "#home\n")
        let block = "---\ntype: task\nstatus: Doing\ntags:\n  - Home/x\n---\n"
        let stuck = tagged("[home, # c\n  b]", "#home\n")
        let untouched = tagged("[work]", "#homework\n")
        let logged = "---\ntype: task\nstatus: Done\ncompletedDate: 2020-01-01\ntags: [home]\n---\n"
        for (text, path) in [(flow, "Ta Da/tasks/Flow.md"), (block, "Ta Da/tasks/Block.md"), (stuck, "Ta Da/tasks/Stuck.md"),
                             (untouched, "Ta Da/tasks/Untouched.md"), (logged, "Ta Da/logbook/Logged.md"), (flow, ".trash/Gone.md")] {
            try writeFile(text, path, in: folder)
        }
        let vault = Vault(root: folder)
        let index = await vault.loadIndex()
        let before = vault.modificationDate(of: "Ta Da/tasks/Untouched.md")

        let result = vault.renameTag(tag("home"), to: tag("house"), index: index)
        #expect(result.items.map(\.path) == ["Ta Da/logbook/Logged.md", "Ta Da/tasks/Block.md", "Ta Da/tasks/Flow.md", "Ta Da/tasks/Stuck.md"])
        #expect(result.failed == ["Ta Da/tasks/Stuck.md"])
        #expect(try vault.read("Ta Da/tasks/Flow.md") == tagged("[house, work]", "#house\n"))
        #expect(try vault.read("Ta Da/tasks/Block.md") == block.replacingOccurrences(of: "Home/x", with: "house/x"))
        #expect(try vault.read("Ta Da/tasks/Stuck.md") == tagged("[home, # c\n  b]", "#house\n"))
        #expect(try vault.read("Ta Da/logbook/Logged.md") == logged.replacingOccurrences(of: "[home]", with: "[house]"))
        #expect(try vault.read("Ta Da/tasks/Untouched.md") == untouched)
        #expect(vault.modificationDate(of: "Ta Da/tasks/Untouched.md") == before)
        #expect(try vault.read(".trash/Gone.md") == flow)
        #expect(result.items.first { $0.path == "Ta Da/tasks/Flow.md" }?.tags.map(\.tag.name) == ["house", "work"])
    }
}

@Test func aFileThatWouldntChangeIsntWritten() async throws {
    try await withTemporaryFolder { folder in
        let text = tagged("[house]", "#house\n")
        try writeFile(text, "Ta Da/tasks/A.md", in: folder)
        let vault = Vault(root: folder)
        let index = await vault.loadIndex()
        let before = vault.modificationDate(of: "Ta Da/tasks/A.md")
        try await Task.sleep(for: .milliseconds(20))
        let result = vault.renameTag(tag("house"), to: tag("house"), index: index)
        #expect(result.failed.isEmpty)
        #expect(vault.modificationDate(of: "Ta Da/tasks/A.md") == before)
    }
}

@Test func deletingATagRemovesItAndItsChildrenFromEveryCarrier() async throws {
    try await withTemporaryFolder { folder in
        try writeFile(tagged("[home, home/garden, work]", "See #home/garden and #work.\n"), "Ta Da/tasks/A.md", in: folder)
        try writeFile("a note #Home\n", "Notes/N.md", in: folder)
        let vault = Vault(root: folder)
        let index = await vault.loadIndex()
        let result = vault.deleteTag(tag("home"), index: index)
        #expect(result.failed.isEmpty)
        #expect(try vault.read("Ta Da/tasks/A.md") == tagged("[work]", "See and #work.\n"))
        #expect(try vault.read("Notes/N.md") == "a note\n")
        #expect(result.items.allSatisfy { $0.tags.map(\.tag.path).filter { $0.hasPrefix("home") }.isEmpty })
    }
}

@Test func anUnreadableCarrierIsReportedAndTheRestAreWritten() async throws {
    try await withTemporaryFolder { folder in
        try writeFile(tagged("[a]", ""), "Ta Da/tasks/A.md", in: folder)
        try writeFile(tagged("[a]", ""), "Ta Da/tasks/B.md", in: folder)
        let vault = Vault(root: folder)
        let index = await vault.loadIndex()
        try Data([0xff, 0xfe]).write(to: folder.appending(path: "Ta Da/tasks/A.md"))
        let result = vault.renameTag(tag("a"), to: tag("b"), index: index)
        #expect(result.failed == ["Ta Da/tasks/A.md"])
        #expect(result.items.map(\.path) == ["Ta Da/tasks/B.md"])
    }
}
