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
