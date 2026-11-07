// Add Link: textMenu's row that links the selected text. It opens the link menu's files under the selection with a
// search field holding the text; a pick writes `[[Title|selection]]` and the last row writes `[[text]]`.
#if os(macOS)
import SwiftUI
import AppKit
import TaDaCore

/// A row of the Add Link menu: a file to link to, or a link to a file that doesn't exist yet.
enum AddLinkChoice: Hashable, PopupMenuItem {
    case file(LinkChoice)
    case new(String)

    var title: String {
        switch self {
        case .file(let choice): choice.title
        case .new(let text): "Link “\(text)”"
        }
    }

    var accessibilityValue: String {
        switch self {
        case .file(let choice): choice.hint
        case .new: "New"
        }
    }
}

enum AddLink {
    /// The selection cut back to its first and last non-blank characters, when it can be linked: one line that overlaps
    /// no link and holds neither `]]` nor `|`.
    static func range(_ selection: NSRange, in text: NSString) -> NSRange? {
        guard NSMaxRange(selection) <= text.length,
              let range = ExtractTask.extractableRange(selection, selectedText: text.substring(with: selection)) else { return nil }
        let linked = text.substring(with: range)
        guard !linked.contains("]]"), !linked.contains("|") else { return nil }
        let line = text.lineRange(for: range)
        for link in Self.links {
            for match in link.matches(in: text as String, range: line) where NSIntersectionRange(match.range, range).length > 0 {
                return nil
            }
        }
        return range
    }

    /// Wiki links, markdown links and images, and autolinks, as the editor shows them.
    private static let links = [#"\[\[[^\]]*\]\]"#, #"!?\[[^\]]*\]\([^)]*\)"#, #"<[^>\s]+>"#].map {
        // The patterns are constants.
        try! NSRegularExpression(pattern: $0)
    }

    /// The menu's sections for the field's `query`: the files that match, then a link to `query` as it is. Recent files
    /// while the field is empty.
    static func sections(_ query: String, search: LinkMenuSearch) -> [PopupMenuSection<AddLinkChoice>] {
        let files = search.choices(.link, query: query).choices.map(AddLinkChoice.file)
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var sections = [PopupMenuSection(label: "Add Link", items: files)]
        if !text.isEmpty, !text.contains("]]"), !text.contains("|"), text.rangeOfCharacter(from: .newlines) == nil {
            sections.append(PopupMenuSection(items: [.new(text)]))
        }
        return sections.filter { !$0.items.isEmpty }
    }

    /// What replaces the selection `text`: `[[Title|text]]`, or `[[Title]]` when they match but for case.
    static func markdown(_ choice: AddLinkChoice, selection text: String) -> String {
        switch choice {
        case .file(let file):
            file.title.compare(text, options: .caseInsensitive) == .orderedSame ? "[[\(file.title)]]" : "[[\(file.title)|\(text)]]"
        case .new(let name):
            "[[\(name)]]"
        }
    }
}

/// Shows, moves through and picks from the Add Link menu. Owned by LiveEditor.
final class AddLinkMenuController {
    private let search = LinkMenuSearch()
    private lazy var menu = makeMenu()
    private var anchor = CGRect.zero
    private var theme = Theme.all[0]
    private weak var window: NSWindow?
    private var pick: (AddLinkChoice) -> Void = { _ in }

    /// Opens the menu under `anchor` (screen coordinates) with `text`, the selection, in the field. `pick` runs the chosen row
    /// after the menu has closed; `close` runs however it closes.
    func show(text: String, source: LinkMenuSource, anchor: CGRect, theme: Theme, pick: @escaping (AddLinkChoice) -> Void,
              close: @escaping () -> Void) {
        guard anchor != .zero, let window = NSApp.keyWindow else { return close() }
        search.source = source
        self.anchor = anchor
        self.theme = theme
        self.window = window
        self.pick = { [weak self] choice in
            self?.hide()
            close()
            pick(choice)
        }
        menu.onDismiss = { [weak self] in
            self?.hide()
            close()
        }
        menu.query = text
        refresh()
    }

    func hide() { menu.hide() }

    private func refresh() {
        guard let window else { return }
        let sections = AddLink.sections(menu.query, search: search)
        menu.show(sections, highlight: sections.isEmpty ? nil : 0, theme: theme, below: anchor, inset: 0, gap: 4, in: window) { [weak self] in
            self?.pick($0)
        }
    }

    private func makeMenu() -> PopupMenu<AddLinkChoice, AddLinkRow> {
        let menu = PopupMenu(style: .full(confirm: "Link", maxListHeight: 284), takesKeys: true, emptyText: "No matching files",
                             searchPrompt: "Link to a file") { [search] choice, isHighlighted, theme in
            AddLinkRow(choice: choice, isHighlighted: isHighlighted, theme: theme, search: search)
        }
        menu.onSearch = { [weak self] _ in self?.refresh() }
        return menu
    }
}

private struct AddLinkRow: View {
    let choice: AddLinkChoice
    let isHighlighted: Bool
    let theme: Theme
    let search: LinkMenuSearch

    var body: some View {
        switch choice {
        case .file(let file):
            LinkMenuRow(choice: file, isHighlighted: isHighlighted, theme: theme, search: search)
        case .new:
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.color(isHighlighted ? \.accent : \.muted))
                    .frame(width: 20)
                Text(choice.title)
                    .foregroundStyle(theme.color(isHighlighted ? \.strong : \.fg))
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                Text("New")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.color(\.muted))
            }
        }
    }
}
#endif
