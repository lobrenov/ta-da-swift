import Foundation
import Testing
@testable import TaDaCore

/// Applies `format` at `caret` the way the editor does; the result marks the new caret with `|`.
private func apply(_ format: LineFormat, _ marked: String) -> String {
    let caret = (marked as NSString).range(of: "|").location
    let string = (marked as NSString).replacingCharacters(in: NSRange(location: caret, length: 1), with: "")
    let plan = LineFormat.plan(format, in: string, caret: caret)
    let result = (string as NSString).replacingCharacters(in: plan.range, with: plan.text) as NSString
    return result.replacingCharacters(in: plan.selection, with: "|")
}

private func insert(_ command: SlashCommand, callout: CalloutType = .note, _ marked: String) -> String {
    let caret = (marked as NSString).range(of: "|").location
    let string = (marked as NSString).replacingCharacters(in: NSRange(location: caret, length: 1), with: "")
    let (text, selection) = LineFormat.blockInsertion(command, callout: callout, in: string, caret: caret)
    let marked = (text as NSString).replacingCharacters(in: NSRange(location: selection.location, length: 0), with: "|")
    return (string as NSString).replacingCharacters(in: NSRange(location: caret, length: 0), with: marked)
}

@Test func headingsToggleAndReplace() {
    #expect(apply(.heading(1), "Ti|tle") == "# Ti|tle")
    #expect(apply(.heading(1), "# Ti|tle") == "Ti|tle")
    #expect(apply(.heading(3), "# Ti|tle") == "### Ti|tle")
    #expect(apply(.heading(2), "> Quo|ted") == "> ## Quo|ted")
    #expect(apply(.heading(1), "|") == "# |")
    #expect(apply(.heading(1), "#| ") == "|")
    #expect(apply(.heading(1), "#hashtag|") == "# #hashtag|")
    #expect(apply(.heading(1), "One\nTw|o\nThree") == "One\n# Tw|o\nThree")
    #expect(apply(.heading(1), "- Ite|m") == "- # Ite|m")
    #expect(apply(.heading(2), "- [ ] Ta|sk") == "- [ ] ## Ta|sk")
    #expect(apply(.heading(2), "- [ ] ## Ta|sk") == "- [ ] Ta|sk")
    #expect(apply(.heading(1), "> 1. [/] Ta|sk") == "> 1. [/] # Ta|sk")
}

@Test func listsToggleAndSwap() {
    #expect(apply(.bulletedList, "Ite|m") == "- Ite|m")
    #expect(apply(.bulletedList, "  - Ite|m") == "  Ite|m")
    #expect(apply(.numberedList, "  - Ite|m") == "  1. Ite|m")
    #expect(apply(.bulletedList, "3. Ite|m") == "- Ite|m")
    #expect(apply(.numberedList, "3. Ite|m") == "Ite|m")
    #expect(apply(.bulletedList, "- [x] Do|ne") == "Do|ne")
    #expect(apply(.numberedList, "- [ ] Ta|sk") == "1. [ ] Ta|sk")
    #expect(apply(.bulletedList, "-| [ ] Task") == "|Task")
}

@Test func quotesToggle() {
    #expect(apply(.quote, "Li|ne") == "> Li|ne")
    #expect(apply(.quote, "  Li|ne") == "  > Li|ne")
    #expect(apply(.quote, "> Li|ne") == "Li|ne")
    #expect(apply(.quote, ">Li|ne") == "Li|ne")
    #expect(apply(.quote, "> - [ ] Ta|sk") == "- [ ] Ta|sk")
}

@Test func boxesTakeTheMarker() {
    #expect(apply(.box("/"), "- [ ] Ta|sk") == "- [/] Ta|sk")
    #expect(apply(.box("x"), "  * [?] Ta|sk") == "  * [x] Ta|sk")
    #expect(apply(.box("-"), "- Ite|m") == "- [-] Ite|m")
    #expect(apply(.box(">"), "Li|ne") == "- [>] Li|ne")
    #expect(apply(.box(" "), "> Quo|ted") == "> - [ ] Quo|ted")
    #expect(apply(.box("<"), "Über 🙂|") == "- [<] Über 🙂|")
}

@Test func lineStateReadsThePrefix() {
    #expect(LineFormat.state(of: "## Heading") == LineFormat.State(heading: 2))
    #expect(LineFormat.state(of: "> 1. [/] Task") == LineFormat.State(list: .numberedList, quote: true, box: "/"))
    #expect(LineFormat.state(of: "- Item") == LineFormat.State(list: .bulletedList))
    #expect(LineFormat.state(of: "####### Seven") == LineFormat.State())
    #expect(LineFormat.state(of: "#tag") == LineFormat.State())
    #expect(LineFormat.state(of: "- [ ] ## Task") == LineFormat.State(heading: 2, list: .bulletedList, box: " "))
}

@Test func blocksGoOnALineOfTheirOwn() {
    #expect(insert(.callout, "|") == "> [!note] |")
    #expect(insert(.callout, callout: .warning, "|") == "> [!warning] |")
    #expect(insert(.callout, callout: .tip, "Text|") == "Text\n> [!tip] |")
    #expect(insert(.codeBlock, "Te|xt") == "Te\n```\n|\n```\nxt")
    #expect(insert(.divider, "|") == "---\n|")
    #expect(insert(.divider, "Para\n|") == "Para\n\n---\n|")
    #expect(insert(.divider, "Para|") == "Para\n\n---\n|")
    #expect(insert(.divider, "Para\n\n|") == "Para\n\n---\n|")
    #expect(insert(.table, "|") == "| |Column | Column |\n| --- | --- |\n|  |  |")
}

@Test func inlineFormatsAroundTheCaret() {
    #expect(LineFormat.inlineFormats(in: "a **bo|ld** b".replacingOccurrences(of: "|", with: ""), at: 6) == [.bold])
    #expect(LineFormat.inlineFormats(in: "a *it* b", at: 4) == [.italic])
    #expect(LineFormat.inlineFormats(in: "***both***", at: 5) == [.bold, .italic])
    #expect(LineFormat.inlineFormats(in: "~~x~~ ==y==", at: 3) == [.strikethrough])
    #expect(LineFormat.inlineFormats(in: "~~x~~ ==y==", at: 9) == [.highlight])
    #expect(LineFormat.inlineFormats(in: "`**c**`", at: 4) == [.code])
    #expect(LineFormat.inlineFormats(in: "**open", at: 4) == [])
    #expect(LineFormat.inlineFormats(in: "a **b** c", at: 8) == [])
    #expect(LineFormat.inlineFormats(in: "* item and *x*", at: 4) == [])
    #expect(LineFormat.inlineFormats(in: "* item and *x*", at: 12) == [.italic])
    #expect(LineFormat.inlineFormats(in: "  * [ ] a *b*", at: 11) == [.italic])
}
