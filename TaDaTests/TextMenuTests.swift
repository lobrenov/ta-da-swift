#if os(macOS)
import Foundation
import SwiftUI
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct TextMenuTests {
    private func target(selection: Bool = false, link: Bool = false, addLink: Bool = true, extract: Bool = true, formats: Set<SlashCommand> = [],
                        block: SlashCommand? = nil, isBody: Bool = true) -> TextMenuTarget {
        TextMenuTarget(hasSelection: selection, onLink: link, canAddLink: addLink, canExtract: extract, formats: formats, block: block, isBody: isBody)
    }

    private func titles(_ sections: [[TextMenuRow]]) -> [[String]] { sections.map { $0.map(\.title) } }

    private func row(_ title: String, in sections: [[TextMenuRow]]) -> TextMenuRow? {
        sections.flatMap { $0 }.first { $0.title == title }
    }

    private func submenu(_ title: String, in sections: [[TextMenuRow]]) throws -> [[TextMenuRow]] {
        try #require(row(title, in: sections)).submenu.map(\.items)
    }

    @Test func aCaretTurnsCutAndCopyOff() {
        let sections = TextMenu.sections(for: target())
        #expect(titles(sections) == [["Cut", "Copy", "Paste", "Paste as Plain Text", "Select All"], ["Format", "Paragraph", "Insert"]])
        #expect(sections[0].map(\.isEnabled) == [false, false, true, true, true])
        #expect(sections[0].map(\.key) == ["⌘X", "⌘C", "⌘V", "⌥⇧⌘V", "⌘A"])
    }

    @Test func aSelectionTurnsThemOnAndAddsExtractToTask() {
        let sections = TextMenu.sections(for: target(selection: true))
        #expect(titles(sections) == [["Cut", "Copy", "Paste", "Paste as Plain Text", "Select All"], ["Add Link", "Extract to Task"],
                                     ["Format", "Paragraph", "Insert"]])
        #expect(sections[0].allSatisfy { $0.isEnabled })
        #expect(sections[1].map(\.key) == [nil, "⌥⌘E"])
    }

    @Test func extractToTaskIsLeftOutWithoutAModelToRunIt() {
        #expect(row("Extract to Task", in: TextMenu.sections(for: target(selection: true, extract: false))) == nil)
    }

    @Test func addLinkIsLeftOutOfACaretAndOfSelectionsThatCantBeLinked() {
        #expect(row("Add Link", in: TextMenu.sections(for: target())) == nil)
        #expect(row("Add Link", in: TextMenu.sections(for: target(selection: true, addLink: false))) == nil)
        #expect(titles(TextMenu.sections(for: target(selection: true, addLink: false, extract: false))).count == 2)
    }

    @Test func addLinkNeedsOneLineWithoutAPipeOrClosingBrackets() {
        func range(_ selected: String, at location: Int = 10) -> NSRange? {
            AddLink.range(NSRange(location: location, length: (selected as NSString).length), selectedText: selected)
        }
        #expect(range("crash reporting") == NSRange(location: 10, length: 15))
        #expect(range("  crash reporting \n") == NSRange(location: 12, length: 15), "trimmed")
        #expect(range("   ") == nil, "blank")
        #expect(range("crash\nreporting") == nil, "two lines")
        #expect(range("a | b") == nil, "a pipe")
        #expect(range("a ]] b") == nil, "a closing bracket pair")
        #expect(range("a ] b") != nil)
    }

    @Test func aLinkAddsOpenLinkAndCopyLinkFirst() {
        let sections = TextMenu.sections(for: target(link: true))
        #expect(titles(sections).prefix(2) == [["Open Link", "Copy Link"], ["Cut", "Copy", "Paste", "Paste as Plain Text", "Select All"]])
        #expect(sections.count == 3)
    }

    @Test func theSubmenusListTheSlashMenusCommandsWithTheFormatMenusKeys() throws {
        let sections = TextMenu.sections(for: target())
        let format = try submenu("Format", in: sections).flatMap { $0 }
        #expect(format.map(\.title) == ["Bold", "Italic", "Strikethrough", "Highlight", "Inline code"])
        #expect(format.map(\.key) == ["⌘B", "⌘I", "⇧⌘S", "⇧⌘H", nil])
        let paragraph = try submenu("Paragraph", in: sections).flatMap { $0 }
        #expect(paragraph.map(\.title) == ["Heading 1", "Heading 2", "Heading 3", "Body", "Bulleted list", "Numbered list", "Task", "Quote"])
        let insert = try submenu("Insert", in: sections).flatMap { $0 }
        #expect(insert.map(\.title) == ["Wikilink", "Link", "Image", "Table", "Callout", "Code block", "Divider"])
        #expect(format.allSatisfy { !$0.isChecked })
    }

    @Test func paragraphAndInsertSubmenusAreDividedIntoGroups() throws {
        let sections = TextMenu.sections(for: target())
        #expect(try submenu("Paragraph", in: sections).map { $0.map(\.title) }
                == [["Heading 1", "Heading 2", "Heading 3", "Body"], ["Bulleted list", "Numbered list", "Task", "Quote"]])
        #expect(try submenu("Insert", in: sections).map { $0.map(\.title) }
                == [["Wikilink", "Link", "Image"], ["Table", "Callout", "Code block", "Divider"]])
        #expect(try submenu("Format", in: sections).count == 1)
    }

    @Test func formatAndParagraphTickWhatTheTextAlreadyIs() throws {
        let sections = TextMenu.sections(for: target(formats: [.bold, .highlight], block: .heading2, isBody: false))
        let format = try submenu("Format", in: sections).flatMap { $0 }
        #expect(format.filter(\.isChecked).map(\.title) == ["Bold", "Highlight"])
        let paragraph = try submenu("Paragraph", in: sections).flatMap { $0 }
        #expect(paragraph.filter(\.isChecked).map(\.title) == ["Heading 2"])
        let insert = try submenu("Insert", in: sections).flatMap { $0 }
        #expect(insert.allSatisfy { !$0.isChecked })
    }

    @Test func bodyIsTickedOnABodyLine() throws {
        let paragraph = try submenu("Paragraph", in: TextMenu.sections(for: target())).flatMap { $0 }
        #expect(paragraph.filter(\.isChecked).map(\.title) == ["Body"])
        let deep = try submenu("Paragraph", in: TextMenu.sections(for: target(isBody: false))).flatMap { $0 }
        #expect(deep.allSatisfy { !$0.isChecked })
    }

    @Test func extractTrimsTheSelectionToItsFirstAndLastNonBlankCharacters() {
        // A triple-click selects the line and its ending.
        #expect(ExtractTask.extractableRange(NSRange(location: 10, length: 12), selectedText: "  Buy milk \n") == NSRange(location: 12, length: 8))
        #expect(ExtractTask.extractableRange(NSRange(location: 0, length: 4), selectedText: "Milk") == NSRange(location: 0, length: 4))
    }

    @Test func theBlanksAroundATrimmedSelectionStay() {
        #expect(ExtractTask.replacingTrimmed(in: "  Buy milk \n") { "[[\($0)]]" } == "  [[Buy milk]] \n")
        #expect(ExtractTask.replacingTrimmed(in: " \n ") { $0 } == nil)
    }

    @Test func extractNeedsOneLineOfText() {
        #expect(ExtractTask.extractableRange(NSRange(location: 0, length: 7), selectedText: " \n  \n ") == nil)
        #expect(ExtractTask.extractableRange(NSRange(location: 0, length: 9), selectedText: "Buy\nmilk\n") == nil)
    }

    @Test func linkOnASelectionLabelsTheTrimmedTextAndPutsTheCaretInTheParentheses() throws {
        let link = try #require(TextMenu.linkInsertion(selection: NSRange(location: 4, length: 11), selectedText: " the kombi "))
        #expect(link.text == " [the kombi]() ")
        #expect(link.selection == NSRange(location: 13, length: 0))
        #expect((link.text as NSString).substring(to: link.selection.location) == " [the kombi](")
    }

    @Test func linkCountsTheCaretInUTF16() throws {
        let link = try #require(TextMenu.linkInsertion(selection: NSRange(location: 0, length: 6), selectedText: "🚐 van"))
        #expect(link.text == "[🚐 van]()")
        #expect(link.selection == NSRange(location: 9, length: 0))
    }

    @Test func linkWithoutTextFallsBackToTheTemplate() {
        #expect(TextMenu.linkInsertion(selection: NSRange(location: 3, length: 0), selectedText: "") == nil)
        #expect(TextMenu.linkInsertion(selection: NSRange(location: 3, length: 2), selectedText: " \n") == nil)
    }

    /// With `TADA_RENDER_DIR` set, draws every row of the root menu and the three submenus to PNGs.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TADA_RENDER_DIR"] != nil))
    func renderRows() async throws {
        let output = URL(filePath: try #require(ProcessInfo.processInfo.environment["TADA_RENDER_DIR"]), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let sections = TextMenu.sections(for: target(selection: true, link: true, formats: [.bold], block: .heading2, isBody: false))
        let root = sections.flatMap { $0 }
        let menus = [("root", root)] + root.filter { !$0.submenu.isEmpty }.map { ($0.title, $0.submenu.flatMap(\.items)) }
        for theme in [ThemeSet.standard.light, ThemeSet.standard.dark] {
            for (name, rows) in menus {
                let view = VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { offset, row in
                        HStack(spacing: 8) {
                            TextMenuRowView(item: row, isHighlighted: offset == 1, theme: theme)
                            if !row.submenu.isEmpty { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)) }
                        }
                        .padding(.horizontal, 8).frame(height: 26)
                    }
                }
                .frame(width: 196).padding(4).background(Color(theme.bg)).foregroundStyle(Color(theme.fg))
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try #require(renderer.nsImage)
                let tiff = try #require(image.tiffRepresentation)
                let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
                try png.write(to: output.appending(path: "textmenu-\(name)-\(theme.name).png"))
            }
        }
    }
}
#endif
