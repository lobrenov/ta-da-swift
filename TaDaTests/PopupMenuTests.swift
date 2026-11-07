#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import TaDa

@MainActor
struct PopupMenuTests {
    private struct Entry: PopupMenuItem {
        var title: String
        var children: [Entry] = []
        var isTicked = false
    }

    private let entries = [
        Entry(title: "Copy"),
        Entry(title: "Format", children: [Entry(title: "Bold", isTicked: true), Entry(title: "Italic")]),
        Entry(title: "Paste"),
    ]

    private func open(picks: @escaping (String) -> Void = { _ in }) -> (PopupMenu<Entry, Text>, NSWindow) {
        let window = NSWindow(contentRect: CGRect(x: 200, y: 400, width: 600, height: 400), styleMask: [.titled],
                              backing: .buffered, defer: false)
        let menu = PopupMenu<Entry, Text>(style: .compact, takesKeys: true) { item, _, _ in Text(item.title) }
        menu.show([PopupMenuSection(items: entries)], highlight: 1, theme: Theme.all[0],
                  below: CGRect(x: 300, y: 600, width: 1, height: 1), inset: 0, gap: 0, in: window) { picks($0.title) }
        return (menu, window)
    }

    private func key(_ special: Int) -> NSEvent {
        let character = String(UnicodeScalar(special)!)
        return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                context: nil, characters: character, charactersIgnoringModifiers: character,
                                isARepeat: false, keyCode: 0)!
    }

    private var right: NSEvent { key(NSRightArrowFunctionKey) }
    private var left: NSEvent { key(NSLeftArrowFunctionKey) }
    private var down: NSEvent { key(NSDownArrowFunctionKey) }
    private var up: NSEvent { key(NSUpArrowFunctionKey) }
    private var enter: NSEvent { key(0x0D) }

    @Test func rightArrowOpensTheHighlightedRowsSubmenu() {
        let (menu, _) = open()
        defer { menu.hide() }
        #expect(!menu.isSubmenuOpen)
        #expect(menu.handleKey(right))
        #expect(menu.isSubmenuOpen)
        #expect(menu.submenuHighlight == 0)
    }

    @Test func rightArrowOnARowWithoutChildrenOpensNothing() {
        let (menu, _) = open()
        defer { menu.hide() }
        menu.move(by: 1)
        #expect(menu.highlight == 2)
        _ = menu.handleKey(right)
        #expect(!menu.isSubmenuOpen)
    }

    @Test func leftArrowClosesTheSubmenuAndKeepsTheMenu() {
        let (menu, _) = open()
        defer { menu.hide() }
        _ = menu.handleKey(right)
        _ = menu.handleKey(left)
        #expect(!menu.isSubmenuOpen)
        #expect(menu.isOpen)
        #expect(menu.highlight == 1)
    }

    @Test func arrowsMoveInTheOpenSubmenuNotTheMenu() {
        let (menu, _) = open()
        defer { menu.hide() }
        _ = menu.handleKey(right)
        _ = menu.handleKey(down)
        #expect(menu.submenuHighlight == 1)
        _ = menu.handleKey(down)
        #expect(menu.submenuHighlight == 0, "wraps round")
        _ = menu.handleKey(up)
        #expect(menu.submenuHighlight == 1)
        #expect(menu.highlight == 1)
    }

    @Test func returnPicksTheSubmenuRowAndClosesTheWholeMenu() {
        var picked: [String] = []
        let (menu, _) = open { picked.append($0) }
        _ = menu.handleKey(right)
        _ = menu.handleKey(down)
        _ = menu.handleKey(enter)
        #expect(picked == ["Italic"])
        #expect(!menu.isSubmenuOpen)
        #expect(!menu.isOpen)
    }

    @Test func returnOnARowWithChildrenOpensItsSubmenuInsteadOfPicking() {
        var picked: [String] = []
        let (menu, _) = open { picked.append($0) }
        defer { menu.hide() }
        _ = menu.handleKey(enter)
        #expect(menu.isSubmenuOpen)
        #expect(picked.isEmpty)
    }

    @Test func returnOnARowWithoutChildrenPicksIt() {
        var picked: [String] = []
        let (menu, _) = open { picked.append($0) }
        defer { menu.hide() }
        menu.move(by: -1)
        _ = menu.handleKey(enter)
        #expect(picked == ["Copy"])
    }

    @Test func hoveringAnotherRootRowClosesTheSubmenu() {
        let (menu, _) = open()
        defer { menu.hide() }
        _ = menu.handleKey(right)
        menu.hoverRow(2)
        #expect(!menu.isSubmenuOpen)
        menu.hoverRow(1)
        #expect(menu.isSubmenuOpen)
        #expect(menu.submenuHighlight == nil)
    }

    @Test func hidingTheMenuClosesTheSubmenu() {
        let (menu, _) = open()
        _ = menu.handleKey(right)
        menu.hide()
        #expect(!menu.isSubmenuOpen)
        #expect(!menu.isOpen)
    }

    @Test func submenuOpensBesideItsRowAlignedToIt() throws {
        let (menu, _) = open()
        defer { menu.hide() }
        _ = menu.handleKey(right)
        let root = try #require(menu.rootFrame)
        let sub = try #require(menu.submenuFrame)
        #expect(sub.minX >= root.maxX - 4 || sub.maxX <= root.minX + 4)
        let style = PopupMenuStyle.compact
        let rowTop = root.maxY - (style.padding + style.rowHeight + 1)
        #expect(abs(sub.maxY - style.padding - rowTop) < 1)
    }

    @Test func tickAndChildrenDefaultOff() {
        struct Plain: PopupMenuItem { var title = "x" }
        #expect(Plain().children.isEmpty)
        #expect(!Plain().isTicked)
    }
}
#endif
