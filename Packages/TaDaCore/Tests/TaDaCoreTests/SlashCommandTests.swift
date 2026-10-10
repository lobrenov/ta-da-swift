import Foundation
import Testing
@testable import TaDaCore

@Test func emptyQueryListsEveryCommandInMenuOrder() {
    #expect(SlashCommand.matching("", atLineStart: true) == SlashCommand.allCases)
}

@Test func midLineOffersOnlyInlineAndLinks() {
    let commands = SlashCommand.matching("", atLineStart: false)
    #expect(commands.first == .wikiLink)
    #expect(!commands.contains { $0.group == .blocks })
    #expect(SlashCommand.matching("h", atLineStart: false) == [.highlight, .link])
}

@Test func titlePrefixRanksAboveWordsAliasesAndSubstrings() {
    #expect(SlashCommand.matching("ta", atLineStart: true) == [.task, .table])
    #expect(SlashCommand.matching("li", atLineStart: true) == [.link, .bulletedList, .numberedList, .divider])
    #expect(SlashCommand.matching("link", atLineStart: true) == [.link, .wikiLink])
    #expect(SlashCommand.matching("todo", atLineStart: true) == [.task])
    #expect(SlashCommand.matching("CODE", atLineStart: true) == [.codeBlock, .inlineCode])
    #expect(SlashCommand.matching("xyz", atLineStart: true).isEmpty)
}

@Test func insertionPlacesTheCaretOrSelection() {
    let bold = SlashCommand.bold.insertion()
    #expect(bold.text == "****" && bold.selection == NSRange(location: 2, length: 0))

    let table = SlashCommand.table.insertion()
    #expect(table.text == "| Column | Column |\n| --- | --- |\n|  |  |")
    #expect((table.text as NSString).substring(with: table.selection) == "Column")
    #expect(table.selection.location == 2)

    let code = SlashCommand.codeBlock.insertion()
    #expect(code.text == "```\n\n```" && code.selection.location == 4)

    let link = SlashCommand.wikiLink.insertion(), image = SlashCommand.image.insertion()
    #expect(link.text == "[[]]" && link.selection == NSRange(location: 2, length: 0))
    #expect(image.text == "![[]]" && image.selection == NSRange(location: 3, length: 0))
}

@Test func dividerAfterAParagraphGetsABlankLine() {
    #expect(SlashCommand.divider.insertion(followsBlankLine: true).text == "---\n")
    let afterText = SlashCommand.divider.insertion(followsBlankLine: false)
    #expect(afterText.text == "\n---\n" && afterText.selection.location == 5)
}

@Test func calloutOpensANoteWithTheCaretAtItsTitle() {
    #expect(SlashCommand.matching("call", atLineStart: true) == [.callout])
    #expect(SlashCommand.matching("warn", atLineStart: true) == [.callout])
    #expect(!SlashCommand.matching("", atLineStart: false).contains(.callout))
    let callout = SlashCommand.callout.insertion()
    #expect(callout.text == "> [!note] " && callout.selection == NSRange(location: 10, length: 0))
}
