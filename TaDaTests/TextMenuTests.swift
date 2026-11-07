#if os(macOS)
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct TextMenuTests {
    private func target(selection: Bool = false, link: Bool = false, extract: Bool = true, formats: Set<SlashCommand> = [],
                        block: SlashCommand? = nil, isBody: Bool = true) -> TextMenuTarget {
        TextMenuTarget(hasSelection: selection, onLink: link, canExtract: extract, formats: formats, block: block, isBody: isBody)
    }

    private func titles(_ sections: [[TextMenuRow]]) -> [[String]] { sections.map { $0.map(\.title) } }

    private func row(_ title: String, in sections: [[TextMenuRow]]) -> TextMenuRow? {
        sections.flatMap { $0 }.first { $0.title == title }
    }

    @Test func aCaretTurnsCutAndCopyOff() {
        let sections = TextMenu.sections(for: target())
        #expect(titles(sections) == [["Cut", "Copy", "Paste", "Paste as Plain Text", "Select All"], ["Format", "Paragraph", "Insert"]])
        #expect(sections[0].map(\.isEnabled) == [false, false, true, true, true])
        #expect(sections[0].map(\.key) == ["⌘X", "⌘C", "⌘V", "⌥⇧⌘V", "⌘A"])
    }

    @Test func aSelectionTurnsThemOnAndAddsExtractToTask() {
        let sections = TextMenu.sections(for: target(selection: true))
        #expect(titles(sections) == [["Cut", "Copy", "Paste", "Paste as Plain Text", "Select All"], ["Extract to Task"],
                                     ["Format", "Paragraph", "Insert"]])
        #expect(sections[0].allSatisfy { $0.isEnabled })
        #expect(sections[1][0].key == "⌥⌘E")
    }

    @Test func extractToTaskIsLeftOutWithoutAModelToRunIt() {
        #expect(row("Extract to Task", in: TextMenu.sections(for: target(selection: true, extract: false))) == nil)
    }

    @Test func aLinkAddsOpenLinkAndCopyLinkFirst() {
        let sections = TextMenu.sections(for: target(link: true))
        #expect(titles(sections).prefix(2) == [["Open Link", "Copy Link"], ["Cut", "Copy", "Paste", "Paste as Plain Text", "Select All"]])
        #expect(sections.count == 3)
    }

    @Test func theSubmenusListTheSlashMenusCommandsWithTheFormatMenusKeys() throws {
        let sections = TextMenu.sections(for: target())
        let format = try #require(row("Format", in: sections)).submenu
        #expect(format.map(\.title) == ["Bold", "Italic", "Strikethrough", "Highlight", "Inline code"])
        #expect(format.map(\.key) == ["⌘B", "⌘I", "⇧⌘S", "⇧⌘H", nil])
        let paragraph = try #require(row("Paragraph", in: sections)).submenu
        #expect(paragraph.map(\.title) == ["Heading 1", "Heading 2", "Heading 3", "Body", "Bulleted list", "Numbered list", "Task", "Quote"])
        let insert = try #require(row("Insert", in: sections)).submenu
        #expect(insert.map(\.title) == ["Wikilink", "Link", "Image", "Table", "Callout", "Code block", "Divider"])
        #expect(format.allSatisfy { !$0.isChecked })
    }

    @Test func formatAndParagraphTickWhatTheTextAlreadyIs() throws {
        let sections = TextMenu.sections(for: target(formats: [.bold, .highlight], block: .heading2, isBody: false))
        let format = try #require(row("Format", in: sections)).submenu
        #expect(format.filter(\.isChecked).map(\.title) == ["Bold", "Highlight"])
        let paragraph = try #require(row("Paragraph", in: sections)).submenu
        #expect(paragraph.filter(\.isChecked).map(\.title) == ["Heading 2"])
        let insert = try #require(row("Insert", in: sections)).submenu
        #expect(insert.allSatisfy { !$0.isChecked })
    }

    @Test func bodyIsTickedOnABodyLine() throws {
        let paragraph = try #require(row("Paragraph", in: TextMenu.sections(for: target()))).submenu
        #expect(paragraph.filter(\.isChecked).map(\.title) == ["Body"])
        let deep = try #require(row("Paragraph", in: TextMenu.sections(for: target(isBody: false)))).submenu
        #expect(deep.allSatisfy { !$0.isChecked })
    }
}
#endif
