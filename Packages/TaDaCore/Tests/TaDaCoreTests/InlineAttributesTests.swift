import Foundation
import Testing
@testable import TaDaCore

private func parse(_ text: String) -> (due: String?, parent: String?) {
    let found = InlineAttributes.parse(text)
    return (found.due?.date.description, found.parent?.title)
}

@Test func aDateAndAParentAreRead() {
    let found = InlineAttributes.parse("Call Sam >2026-10-09 @[[Ta Da MVP]]")
    #expect(found.due?.date == LocalDate("2026-10-09") && found.due?.range == NSRange(location: 9, length: 11))
    #expect(found.parent?.title == "Ta Da MVP" && found.parent?.range == NSRange(location: 21, length: 14))
}

@Test func attributesAtTheStartOfTheTextCount() {
    #expect(parse(">2026-10-09 call") == ("2026-10-09", nil))
    #expect(parse("@[[Home]] call") == (nil, "Home"))
}

@Test func anAttributeNeedsWhitespaceBeforeIt() {
    #expect(parse("a>2026-10-09") == (nil, nil))
    #expect(parse("mail@[[Home]]") == (nil, nil))
    #expect(parse("a\t>2026-10-09") == ("2026-10-09", nil))
}

@Test func theFirstOfEachCounts() {
    #expect(parse("a >2026-10-09 >2026-11-01 @[[A]] @[[B]]") == ("2026-10-09", "A"))
    #expect(parse("a >2026-02-30 >2026-11-01") == ("2026-11-01", nil))
}

@Test func theDateMustBeValidAndEndTheWord() {
    #expect(parse("a >2026-13-01") == (nil, nil))
    #expect(parse("a >2026-10-9") == (nil, nil))
    #expect(parse("a >soon") == (nil, nil))
    #expect(parse("a >2026-10-091") == (nil, nil))
    #expect(parse("a >2026-10-09, b") == ("2026-10-09", nil))
}

@Test func theAtMustBeRightBeforeTheLink() {
    #expect(parse("a @ [[Home]]") == (nil, nil))
    #expect(parse("a @Home") == (nil, nil))
    #expect(parse("a @[[Home") == (nil, nil))
    #expect(parse("a @[[]]") == (nil, nil))
    #expect(parse("a @[[#heading]]") == (nil, nil))
}

@Test func aParentTakesTheLinkTarget() {
    #expect(parse("a @[[Ta Da MVP|the MVP]]").parent == "Ta Da MVP")
    #expect(parse("a @[[Ta Da MVP#Goals]]").parent == "Ta Da MVP")
    #expect(parse("a @[[Projects/Ta Da MVP.md]]").parent == "Ta Da MVP")
}

@Test func codeSpansAndLinksHoldNoAttributes() {
    #expect(parse("a `>2026-10-09 @[[A]]` b") == (nil, nil))
    #expect(parse("a ``x ` >2026-10-09`` b") == (nil, nil))
    #expect(parse("a `unclosed >2026-10-09") == ("2026-10-09", nil))
    #expect(parse("a `x` >2026-10-09") == ("2026-10-09", nil))
    #expect(parse("see [[Note >2026-10-09]] b") == (nil, nil))
    #expect(parse("see [[Note >2026-10-09]] >2026-10-10") == ("2026-10-10", nil))
    #expect(parse("see ![[pic >2026-10-09.png]]") == (nil, nil))
    #expect(parse("see [the >2026-10-09 doc](https://x.y/ >2026-10-08) b") == (nil, nil))
    #expect(parse("[ ] >2026-10-09") == ("2026-10-09", nil))
}

@Test func strippingRemovesTheCountedTokensAndOneSpace() {
    func stripped(_ text: String) -> String { InlineAttributes.parse(text).stripped(from: text) }
    #expect(stripped("Call Sam >2026-10-09 @[[Ta Da MVP]]") == "Call Sam")
    #expect(stripped(">2026-10-09 Call Sam") == "Call Sam")
    #expect(stripped("Call >2026-10-09 Sam") == "Call Sam")
    #expect(stripped("@[[A]] >2026-10-09 Call Sam") == "Call Sam")
    #expect(stripped("a >2026-10-09 b >2026-11-01") == "a b >2026-11-01")
    #expect(stripped("plain") == "plain")
    #expect(stripped(">2026-10-09") == "")
}

@Test func nonASCIITextKeepsUTF16Ranges() {
    let found = InlineAttributes.parse("Café ☕️ >2026-10-09")
    #expect(found.due?.range == NSRange(location: 8, length: 11))
}

@Test func removingTakesOneSpaceBeforeElseAfter() {
    func stripped(_ text: String) -> String { InlineAttributes.parse(text).stripped(from: text) }
    func removed(_ text: String) -> String {
        InlineAttributes.removing(InlineAttributes.parse(text).due!.range, from: text as NSString)
    }
    #expect(removed("a  >2026-10-09  b") == "a   b")
    #expect(removed("a\t >2026-10-09") == "a\t")
    #expect(removed(">2026-10-09  b") == " b")
    #expect(removed("a >2026-10-09 b") == "a b")
    #expect(stripped("a  >2026-10-09  b") == "a   b")
}

@Test func linkTextHoldsNoAttributesWhateverItsBrackets() {
    #expect(parse("[a [b] >2026-10-09 c](https://x.y) d") == (nil, nil))
    #expect(parse("[a [b] >2026-10-09 c][ref] d") == (nil, nil))
    #expect(parse("[text >2026-10-09][ref] >2026-10-10") == ("2026-10-10", nil))
    #expect(parse("[a [b](u) @[[A]] c](https://x.y) @[[B]]") == (nil, "B"))
    #expect(parse("[a \\] >2026-10-09 b](https://x.y)") == (nil, nil))
    #expect(parse("[a `]` >2026-10-09](https://x.y)") == (nil, nil))
    #expect(parse("[url](https://x.y/(a) >2026-10-09) z") == (nil, nil))
}

@Test func bracketsThatAreNoLinkLeaveAttributesAlone() {
    #expect(parse("[a [b] >2026-10-09 c] d") == ("2026-10-09", nil))
    #expect(parse("[x] >2026-10-09") == ("2026-10-09", nil))
    #expect(parse("[unclosed >2026-10-09") == ("2026-10-09", nil))
}
