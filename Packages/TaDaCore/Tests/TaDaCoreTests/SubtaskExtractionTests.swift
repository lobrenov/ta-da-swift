import Foundation
import Testing
@testable import TaDaCore

/// The extract for the line holding `|`, and the text once its range is deleted.
private func extract(_ marked: String) -> (SubtaskExtraction.Extract, String)? {
    let location = (marked as NSString).range(of: "|").location
    let text = marked.replacingOccurrences(of: "|", with: "")
    guard let extract = SubtaskExtraction.extract(lineAt: location, in: text) else { return nil }
    return (extract, (text as NSString).replacingCharacters(in: extract.range, with: ""))
}

@Test func aSubtaskLineIsExtractedAndDeleted() throws {
    let (e, rest) = try #require(extract("Intro\n- [ ] Buy |milk \n- [x] Done\n"))
    #expect(e.title == "Buy milk")
    #expect(e.status == .notStarted)
    #expect(e.body == "")
    #expect(rest == "Intro\n- [x] Done\n")
}

@Test func theBoxGivesTheStatus() throws {
    #expect(try #require(extract("- [/] |A")).0.status == .doing)
    #expect(try #require(extract("- [x] |A")).0.status == .done)
    #expect(try #require(extract("- [X] |A")).0.status == .done)
    #expect(try #require(extract("- [-] |A")).0.status == .cancelled)
    #expect(try #require(extract("- [>] |A")).0.status == .notStarted)
}

@Test func notSubtasksAreNotExtracted() {
    #expect(extract("- [!] |Important") == nil)
    #expect(extract("- |Plain item") == nil)
    #expect(extract("|Plain line") == nil)
    #expect(extract("- [ ] |") == nil)
}

@Test func indentedLinesGoWithIt() throws {
    let text = "- [ ] |Parent\n    - [x] Child\n\n      Note\n- [ ] Sibling\n"
    let (e, rest) = try #require(extract(text))
    #expect(e.body == "- [x] Child\n\n  Note")
    #expect(rest == "- [ ] Sibling\n")
}

@Test func aNestedSubtaskStopsAtItsOutdent() throws {
    let (e, rest) = try #require(extract("- [ ] Parent\n\t- [ ] |Child\n\t\t- [ ] Grandchild\n\t- [ ] Next\n\nAfter"))
    #expect(e.title == "Child")
    #expect(e.body == "- [ ] Grandchild")
    #expect(rest == "- [ ] Parent\n\t- [ ] Next\n\nAfter")
}

@Test func theTaskTextHasTheParentStatusAndBody() throws {
    let today = LocalDate(year: 2026, month: 10, day: 25)!
    let (done, _) = try #require(extract("- [x] |Ship\n  - [ ] Tag it"))
    #expect(SubtaskExtraction.taskText(done, area: "Personal", today: today) == """
        ---
        type: task
        status: Done
        area: "[[Personal]]"
        createdDate: 2026-10-25
        completedDate: 2026-10-25
        ---
        - [ ] Tag it

        """)
    let (open, _) = try #require(extract("- [ ] |Plan"))
    #expect(SubtaskExtraction.taskText(open, project: "Ta Da", today: today)
        == NewFile.task(project: "Ta Da", today: today))
}

@Test func quotedAndFencedSubtasksAreNotExtracted() {
    #expect(extract("> [!todo]\n> - [ ] |A\n> \t- [ ] B") == nil)
    #expect(extract("```\n- [ ] |Example\n```") == nil)
    #expect(extract("~~~\n~~~\n- [ ] |After") != nil)
}

@Test func tabsIndentByFourColumns() throws {
    let (e, rest) = try #require(extract("    - [ ] |A\n\t\t- [ ] B\n\t- [ ] C\n"))
    #expect(e.body == "- [ ] B")
    #expect(rest == "\t- [ ] C\n")
}

@Test func extractAllTakesEverySubtaskAndLeavesTheRest() {
    let (text, extracts) = SubtaskExtraction.extractAll(from: "- [ ] A\n- [x] B\n  - [ ] B1\n> - [ ] Quoted\nText\n- [-] C")
    #expect(extracts.map(\.title) == ["A", "B", "C"])
    #expect(extracts[1].body == "- [ ] B1")
    #expect(text == "> - [ ] Quoted\nText\n")
}
