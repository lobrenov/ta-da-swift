import Testing
@testable import TaDaCore

/// Applies an insertion the way the editor does, to check the resulting line.
private func apply(_ line: String) -> String {
    switch SubtaskLine.insertion(for: line[...]) {
    case let .convert(offset, text):
        let utf16 = Array(line.utf16)
        return String(decoding: utf16[..<offset] + Array(text.utf16) + utf16[offset...], as: UTF16.self)
    case let .newSubtask(text):
        return line + text
    }
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
    #expect(SubtaskLine.insertion(for: "  - Item") == .convert(offset: 4, text: "[ ] "))
}

@Test func notQuiteListItemsArePlainLines() {
    #expect(apply("-dash") == "- [ ] -dash")
    #expect(apply("1234567890. long") == "- [ ] 1234567890. long")
}

@Test func subtasksStartANewOneBelow() {
    #expect(apply("- [ ] One") == "- [ ] One\n- [ ] ")
    #expect(apply("  - [x] Done") == "  - [x] Done\n  - [ ] ")
    #expect(apply("> * [/] Doing") == "> * [/] Doing\n> * [ ] ")
    #expect(apply("3. [ ] Third") == "3. [ ] Third\n4. [ ] ")
    #expect(apply("- [ ]") == "- [ ]\n- [ ] ")
    #expect(SubtaskLine.insertion(for: "- [ ] A", ending: "\r\n") == .newSubtask(text: "\r\n- [ ] "))
}

@Test func bracketsThatArentBoxesAreListText() {
    #expect(apply("- [link](x)") == "- [ ] [link](x)")
    #expect(apply("- [[Wiki]]") == "- [ ] [[Wiki]]")
}
