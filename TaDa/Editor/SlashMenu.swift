// The slash menu: a themed list of markdown formats in a borderless panel under the `/`.
// The editor engine tracks the `/query` and routes the keys; LiveEditor bridges the two.
import SwiftUI
import AppKit
import TaDaCore

/// Shows, moves through and picks from the slash menu. Owned by LiveEditor.
final class SlashMenuController {
    enum Key { case up, down, confirm }

    private let model = SlashMenuModel()
    private var panel: NSPanel?
    private var eventMonitor: Any?
    private var onDismiss: () -> Void = {}

    /// Shows the menu under `anchor` (the `/`, in screen coordinates), or refreshes it.
    func show(query: String, atLineStart: Bool, anchor: CGRect, theme: Theme,
              pick: @escaping (SlashCommand) -> Void, dismiss: @escaping () -> Void) {
        guard anchor != .zero, let parent = NSApp.keyWindow else { return }
        let commands = SlashCommand.matching(query, atLineStart: atLineStart)
        if commands != model.commands || query != model.query { model.selection = 0 }
        model.commands = commands
        model.query = query
        model.theme = theme
        model.pick = pick
        onDismiss = dismiss

        let panel = panel ?? makePanel()
        let size = model.size
        var origin = CGPoint(x: anchor.minX - 8, y: anchor.minY - 6 - size.height)
        if let visible = parent.screen?.visibleFrame {
            if origin.y < visible.minY { origin.y = anchor.maxY + 6 }
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
        }
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        if panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            parent.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
        panel.invalidateShadow()
        installEventMonitor()
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    /// Returns `true` when the menu used the key. ↵ with no matches falls through to the editor.
    func handle(_ key: Key) -> Bool {
        guard panel?.isVisible == true else { return false }
        let count = model.commands.count
        switch key {
        case .up, .down:
            guard count > 0 else { return true }
            model.selection = (model.selection + (key == .down ? 1 : count - 1)) % count
            return true
        case .confirm:
            guard model.commands.indices.contains(model.selection) else { return false }
            model.pick(model.commands[model.selection])
            return true
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.contentView = FirstMouseHostingView(rootView: SlashMenuView(model: model))
        self.panel = panel
        return panel
    }

    /// A click elsewhere or a scroll closes the menu; the editor's `/` text stays.
    private func installEventMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
            // A two-finger click on a trackpad also sends scroll events that don't move.
            let isStillScroll = event.type == .scrollWheel && event.scrollingDeltaX == 0 && event.scrollingDeltaY == 0
            if let self, event.window !== self.panel, !isStillScroll { self.onDismiss() }
            return event
        }
    }
}

@Observable
private final class SlashMenuModel {
    var commands: [SlashCommand] = []
    var query = ""
    var selection = 0
    var theme = Theme.all[0]
    @ObservationIgnored var pick: (SlashCommand) -> Void = { _ in }

    static let width: CGFloat = 288
    static let rowHeight: CGFloat = 34
    static let headerHeight: CGFloat = 25
    static let maxListHeight: CGFloat = 284

    /// Grouped under headers while nothing is typed; ranked flat once it is.
    var sections: [(group: SlashCommand.Group?, commands: [SlashCommand])] {
        guard query.isEmpty else { return [(nil, commands)] }
        return SlashCommand.Group.allCases.compactMap { group in
            let members = commands.filter { $0.group == group }
            return members.isEmpty ? nil : (group, members)
        }
    }

    var listHeight: CGFloat {
        guard !commands.isEmpty else { return 40 }
        let headers = sections.filter { $0.group != nil }.count
        let content = CGFloat(commands.count) * (Self.rowHeight + 1) + CGFloat(headers) * Self.headerHeight
        return min(content, Self.maxListHeight)
    }

    /// The list, a 6pt pad all round, and the 34pt footer.
    var size: CGSize { CGSize(width: Self.width, height: listHeight + 12 + 34) }
}

private struct SlashMenuView: View {
    let model: SlashMenuModel

    private var theme: Theme { model.theme }
    private var menuBackground: Color { theme.color(theme.isDark ? \.side : \.bg) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(model.sections, id: \.group) { section in
                            if let group = section.group {
                                Text(group.rawValue.uppercased())
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .tracking(0.6)
                                    .foregroundStyle(theme.color(\.muted))
                                    .padding(.horizontal, 10)
                                    .frame(height: SlashMenuModel.headerHeight - 1, alignment: .bottom)
                                    .padding(.bottom, 1)
                                    .accessibilityAddTraits(.isHeader)
                                    .id(group)
                            }
                            ForEach(section.commands, id: \.self) { command in
                                row(command)
                            }
                        }
                        if model.commands.isEmpty {
                            Text("No matching formats")
                                .foregroundStyle(theme.color(\.muted))
                                .padding(.horizontal, 10)
                                .frame(height: 40, alignment: .leading)
                        }
                    }
                }
                .scrollIndicators(.automatic)
                .frame(height: model.listHeight)
                .onChange(of: model.selection) {
                    guard model.commands.indices.contains(model.selection) else { return }
                    // The first row brings its group header back into view too.
                    if model.selection == 0, let group = model.sections.first?.group {
                        scroller.scrollTo(group, anchor: .top)
                    } else {
                        scroller.scrollTo(model.commands[model.selection])
                    }
                }
            }
            footer
        }
        .padding(6)
        .frame(width: SlashMenuModel.width)
        .background(menuBackground, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color(\.surface)))
        .font(.system(size: 13.5))
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
    }

    private func row(_ command: SlashCommand) -> some View {
        let isSelected = model.commands.firstIndex(of: command) == model.selection
        return HStack(spacing: 12) {
            SlashCommandIcon(command: command)
                .foregroundStyle(theme.color(isSelected ? \.accent : \.muted))
                .frame(width: 20, height: 20)
            Text(command.title)
                .foregroundStyle(theme.color(isSelected ? \.strong : \.fg))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(command.hint)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.color(\.muted))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .frame(height: SlashMenuModel.rowHeight)
        .background(isSelected ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 7))
        .contentShape(.rect)
        .onHover { inside in
            if inside, let index = model.commands.firstIndex(of: command) { model.selection = index }
        }
        .onTapGesture { model.pick(command) }
        .id(command)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.pick(command) }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            MenuKeyHint(key: "↑↓", label: "Navigate", theme: theme)
            MenuKeyHint(key: "↵", label: "Insert", theme: theme)
            MenuKeyHint(key: "esc", label: "Close", theme: theme)
            Spacer()
        }
        .font(.system(size: 11))
        .foregroundStyle(theme.color(\.muted))
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .frame(height: 34, alignment: .top)
        .overlay(alignment: .top) { Rectangle().fill(theme.color(\.border)).frame(height: 1) }
        .accessibilityHidden(true)
    }

}

/// A key cap and what it does, for a menu footer.
struct MenuKeyHint: View {
    let key: String
    let label: String
    let theme: Theme

    var body: some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(theme.color(\.fg))
                .padding(.horizontal, 5)
                .background(theme.color(\.surface), in: .rect(cornerRadius: 4))
            Text(label)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

private struct SlashCommandIcon: View {
    let command: SlashCommand

    var body: some View {
        switch command {
        case .heading1: glyph("H1")
        case .heading2: glyph("H2")
        case .heading3: glyph("H3")
        case .wikiLink: Text("[[ ]]").font(.system(size: 9.5, weight: .semibold, design: .monospaced))
        default: Image(systemName: symbol).font(.system(size: 13))
        }
    }

    private func glyph(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .bold))
    }

    private var symbol: String {
        switch command {
        case .bulletedList: "list.bullet"
        case .numberedList: "list.number"
        case .task: "checkmark.square"
        case .quote: "text.quote"
        case .divider: "minus"
        case .codeBlock: "terminal"
        case .table: "tablecells"
        case .link: "link"
        case .image: "photo"
        case .bold: "bold"
        case .italic: "italic"
        case .strikethrough: "strikethrough"
        case .highlight: "highlighter"
        case .inlineCode: "chevron.left.forwardslash.chevron.right"
        case .heading1, .heading2, .heading3, .wikiLink: ""
        }
    }
}

/// The panel never becomes key, so the first click must reach the menu.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
