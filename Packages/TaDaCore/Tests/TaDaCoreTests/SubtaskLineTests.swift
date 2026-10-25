import Foundation
import Testing
@testable import TaDaCore

/// Applies an edit the way the editor does, to check the resulting line.
private func apply(_ line: String) -> String {
    var utf16 = Array(line.utf16)
    switch SubtaskLine.edit(for: line[...]) {
    case let .convert(offset, text):
        utf16.insert(contentsOf: text.utf16, at: offset)
    case let .setMarker(offset, marker):
        utf16.replaceSubrange(offset...offset, with: String(marker).utf16)
    case .none:
        break
    }
    return String(decoding: utf16, as: UTF16.self)
}

@Test func plainLinesBecomeSubtasks() {
    #expect(apply("Buy milk") == "- [ ] Buy milk")
    #expect(apply("  Indented") == "  - [ ] Indented")
    #expect(apply("> Quoted") == "> - [ ] Quoted")
    #expect(apply("") == "- [ ] ")
    #expect(apply("\t") == "\t- [ ] ")
    #expect(apply("Über 🙂") == "- [ ] Über 🙂")
}

@Test func listItemsGetABox() {
    #expect(apply("- Buy milk") == "- [ ] Buy milk")
    #expect(apply("    * Nested") == "    * [ ] Nested")
    #expect(apply("+ Plus") == "+ [ ] Plus")
    #expect(apply("12. Ordered") == "12. [ ] Ordered")
    #expect(apply("1) Paren") == "1) [ ] Paren")
    #expect(apply("- ") == "- [ ] ")
    #expect(SubtaskLine.edit(for: "  - Item") == .convert(offset: 4, text: "[ ] "))
}

@Test func notQuiteListItemsArePlainLines() {
    #expect(apply("-dash") == "- [ ] -dash")
    #expect(apply("1234567890. long") == "- [ ] 1234567890. long")
}

@Test func subtasksCompleteAndReopenLikeAClick() {
    #expect(apply("- [ ] One") == "- [x] One")
    #expect(apply("  - [/] Doing") == "  - [x] Doing")
    #expect(apply("> 3. [>] Forwarded") == "> 3. [x] Forwarded")
    #expect(apply("-  [ ] Two spaces") == "-  [x] Two spaces")
    #expect(apply("- [x] Done 🙂") == "- [ ] Done 🙂")
    #expect(apply("* [X] Done") == "* [ ] Done")
    #expect(apply("- [-] Cancelled") == "- [ ] Cancelled")
    #expect(SubtaskLine.edit(for: "  - [ ] A") == .setMarker(offset: 5, marker: "x"))
}

@Test func iconBoxesAreLeftAlone() {
    #expect(SubtaskLine.edit(for: "- [?] Question") == .none)
    #expect(SubtaskLine.edit(for: "- [!] Important") == .none)
}

@Test func bracketsThatArentBoxesAreListText() {
    #expect(apply("- [link](x)") == "- [ ] [link](x)")
    #expect(apply("- [[Wiki]]") == "- [ ] [[Wiki]]")
    #expect(apply("- [a] Not a marker") == "- [ ] [a] Not a marker")
    #expect(apply("- [ ]") == "- [ ] [ ]", "a box needs a space after it")
    #expect(apply("- [x]NoSpace") == "- [ ] [x]NoSpace")
}

/// Applies `SubtaskLine.plan` to `text` with `selection` (the whole text if nil), returning the result and the plan.
private func plan(_ text: String, selection: NSRange? = nil) -> (result: String, plan: SubtaskLine.Plan)? {
    let range = selection ?? NSRange(location: 0, length: (text as NSString).length)
    guard let plan = SubtaskLine.plan(in: text, selection: range) else { return nil }
    return ((text as NSString).replacingCharacters(in: plan.range, with: plan.text), plan)
}

@Test func selectionConvertsPlainLinesAndLeavesSubtasks() throws {
    let out = try #require(plan("Buy milk\n- [x] Done\n- Eggs\n> Quote"))
    #expect(out.result == "- [ ] Buy milk\n- [x] Done\n- [ ] Eggs\n> - [ ] Quote")
    #expect(out.plan.actionName == "Add Subtask")
    #expect((out.result as NSString).substring(with: out.plan.selection) == out.result)
}

@Test func selectionSkipsBlankLines() throws {
    let out = try #require(plan("One\n\n  \nTwo\n"))
    #expect(out.result == "- [ ] One\n\n  \n- [ ] Two\n")
    #expect((out.result as NSString).substring(with: out.plan.selection) == "- [ ] One\n\n  \n- [ ] Two")
    #expect(plan("\n  \n\n") == nil)
}

@Test func selectionCompletesOpenSubtasks() throws {
    let out = try #require(plan("- [ ] A\n- [/] B\n- [ ] C"))
    #expect(out.result == "- [x] A\n- [x] B\n- [x] C")
    #expect(out.plan.actionName == "Complete Subtask")
}

@Test func selectionLeavesDoneSubtasksWhenCompleting() throws {
    #expect(plan("- [x] A\n- [-] B\n- [ ] C")?.result == "- [x] A\n- [-] B\n- [x] C")
}

@Test func selectionCompletesWhenMixedOpenAndComplete() throws {
    let out = try #require(plan("- [x] A\n- [ ] B\n\n  - [ ] C"))
    #expect(out.result == "- [x] A\n- [x] B\n\n  - [x] C")
    #expect(out.plan.actionName == "Complete Subtask")
}

@Test func selectionReopensWhenAllComplete() throws {
    let out = try #require(plan("- [x] A\n- [X] B\n- [-] C"))
    #expect(out.result == "- [ ] A\n- [ ] B\n- [ ] C")
    #expect(out.plan.actionName == "Reopen Subtask")
}

@Test func selectionOfOnlyIconBoxesDoesNothing() {
    #expect(plan("- [?] A\n- [!] B") == nil)
}

@Test func selectionEndingAtALineStartExcludesThatLine() throws {
    let out = try #require(plan("A\nB\nC", selection: NSRange(location: 0, length: 4)))
    #expect(out.result == "- [ ] A\n- [ ] B\nC")
}

@Test func singleLineActsOnTheCaretLine() throws {
    let caret = try #require(plan("A\nBuy\nC", selection: NSRange(location: 4, length: 0)))
    #expect(caret.result == "A\n- [ ] Buy\nC")
    #expect(caret.plan.selection == NSRange(location: 10, length: 0))
    #expect(caret.plan.actionName == "Add Subtask")
    let blank = try #require(plan("\n", selection: NSRange(location: 0, length: 0)))
    #expect(blank.result == "- [ ] \n")
    let done = try #require(plan("- [ ] A", selection: NSRange(location: 3, length: 0)))
    #expect(done.result == "- [x] A")
    #expect(done.plan.selection == NSRange(location: 3, length: 0))
    #expect(done.plan.actionName == "Complete Subtask")
    #expect(plan("- [x] A", selection: NSRange(location: 0, length: 0))?.plan.actionName == "Reopen Subtask")
    #expect(plan("- [?] A", selection: NSRange(location: 0, length: 0)) == nil)
    #expect(plan("- [ ] A", selection: NSRange(location: 2, length: 3))?.result == "- [x] A", "within one line")
}
