// The slash, checkbox, file and property menus: a themed list in a borderless panel above a window.
// `PopupPanel` places the panel, closes it on a click elsewhere, a scroll or esc and passes it keys; the date
// picker's calendar uses it too. `PopupMenu` moves the highlight and picks, and its view draws the list around
// each menu's own rows, in the full or compact style of the design system's Menu component.
/// What a popup menu needs from each of its items.
protocol PopupMenuItem {
    /// The row's VoiceOver label, and what typing a menu's letters matches.
    var title: String { get }
    /// Read after the title, such as "Current".
    var accessibilityValue: String { get }
    /// Highlighted with a `deadline` tint instead of `surface`.
    var isDestructive: Bool { get }
    /// Drawn dimmed and skipped by the highlight, type-select, hover and click.
    var isEnabled: Bool { get }
    /// The rows of a submenu that opens beside this one's row, which then shows a ▸. Submenu rows' own submenus
    /// are ignored.
    var submenu: [PopupMenuSection<Self>] { get }
}

extension PopupMenuItem {
    var accessibilityValue: String { "" }
    var isDestructive: Bool { false }
    var isEnabled: Bool { true }
    var submenu: [PopupMenuSection<Self>] { [] }
}

/// Some of a menu's items: under an uppercase label, or after a divider when they have none and aren't first.
struct PopupMenuSection<Item> {
    var label: String? = nil
    var items: [Item]
}

#if os(macOS)
import SwiftUI
import AppKit

/// The Menu component's two densities.
struct PopupMenuStyle {
    var width: CGFloat
    var padding: CGFloat
    var rowHeight: CGFloat
    var rowPadding: CGFloat
    var rowRadius: CGFloat
    var fontSize: CGFloat
    /// What the footer's ↵ hint says; no footer when nil.
    var confirmLabel: String?
    /// The list scrolls beyond this height.
    var maxListHeight: CGFloat
    /// The highlight stays when the pointer leaves its row.
    var keepsHighlight: Bool

    /// The slash, checkbox and property menus.
    static func full(confirm: String, maxListHeight: CGFloat) -> Self {
        Self(width: 288, padding: 6, rowHeight: 34, rowPadding: 10, rowRadius: 7, fontSize: 13.5,
             confirmLabel: confirm, maxListHeight: maxListHeight, keepsHighlight: true)
    }

    /// The file menu.
    static let compact = Self(width: 196, padding: 4, rowHeight: 26, rowPadding: 8, rowRadius: 6, fontSize: 13,
                              confirmLabel: nil, maxListHeight: .infinity, keepsHighlight: false)

    static let labelHeight: CGFloat = 25
    static let dividerHeight: CGFloat = 7
    static let footerHeight: CGFloat = 34
    static let emptyHeight: CGFloat = 40
    /// The search field and its 2pt margin.
    static let searchHeight: CGFloat = 34
}

/// A borderless panel above a window, under an anchor. A click elsewhere or a scroll dismisses it, and so does
/// esc while it takes keys.
final class PopupPanel<Content: View> {
    private let content: () -> Content
    private let becomesKey: Bool
    private var panel: NSPanel?
    private var eventMonitor: Any?
    /// Takes the keys typed while the panel is open, returning whether it used each one. Nil leaves keys to
    /// the window.
    var onKey: ((NSEvent) -> Bool)?
    /// Takes esc first, returning whether it used it; esc dismisses otherwise.
    var onEscape: (() -> Bool)?
    /// What dismissing does; hides the panel unless set.
    var onDismiss: (() -> Void)?
    /// Called whenever the panel hides.
    var onHide: (() -> Void)?
    /// A window whose clicks and scrolls don't dismiss this panel, such as its submenu.
    var companion: (() -> NSWindow?)?

    /// With `becomesKey` the panel has the keyboard while it's open, for a text field in it.
    init(becomesKey: Bool = false, content: @escaping () -> Content) {
        self.becomesKey = becomesKey
        self.content = content
    }

    var isOpen: Bool { panel?.isVisible == true }
    var window: NSWindow? { panel }
    var frame: CGRect? { isOpen ? panel?.frame : nil }

    /// Shows the panel at `size` right of `row` (screen coordinates), `inset` points above its top, or left of it
    /// at the screen's edge.
    func show(size: CGSize, beside row: CGRect, inset: CGFloat, in parent: NSWindow) {
        let panel = panel ?? makePanel()
        var origin = CGPoint(x: row.maxX - 2, y: row.maxY + inset - size.height)
        if let visible = parent.screen?.visibleFrame {
            if origin.x + size.width > visible.maxX - 4 { origin.x = row.minX + 2 - size.width }
            origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - size.height - 4)
        }
        place(panel, at: CGRect(origin: origin, size: size), in: parent)
    }

    /// Shows the panel at `size` below `anchor` (screen coordinates), `inset` points left of it and `gap` below,
    /// or above it when there's no room below. Moves and resizes it when it's already open.
    func show(size: CGSize, below anchor: CGRect, inset: CGFloat, gap: CGFloat, in parent: NSWindow) {
        let panel = panel ?? makePanel()
        var origin = CGPoint(x: anchor.minX - inset, y: anchor.minY - gap - size.height)
        if let visible = parent.screen?.visibleFrame {
            if origin.y < visible.minY { origin.y = anchor.maxY + gap }
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
        }
        place(panel, at: CGRect(origin: origin, size: size), in: parent)
    }

    private func place(_ panel: NSPanel, at frame: CGRect, in parent: NSWindow) {
        panel.setFrame(frame, display: true)
        if panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            parent.addChildWindow(panel, ordered: .above)
            panel.appearanceSource = parent
        }
        panel.orderFront(nil)
        if becomesKey { panel.makeKey() }
        panel.invalidateShadow()
        installEventMonitor()
    }

    /// Hides the panel, and gives the keyboard back to its window when it had it, so a click that dismissed it
    /// reaches the window. The event monitor goes even when the panel is already hidden, as `hidesOnDeactivate` does.
    func hide() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        defer { onHide?() }
        guard let panel, panel.isVisible else { return }
        let parent = panel.parent
        let wasKey = panel.isKeyWindow
        parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        if wasKey { parent?.makeKey() }
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: true)
        panel.becomesKey = becomesKey
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.contentView = FirstMouseHostingView(rootView: content())
        self.panel = panel
        return panel
    }

    private func installEventMonitor() {
        guard eventMonitor == nil else { return }
        var mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        if onKey != nil { mask.insert(.keyDown) }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.charactersIgnoringModifiers == String(KeyEquivalent.escape.character) {
                    if onEscape?() != true { dismiss() }
                    return nil
                }
                return onKey?(event) == true ? nil : event
            }
            // A two-finger click on a trackpad also sends scroll events that don't move.
            let isStillScroll = event.type == .scrollWheel && event.scrollingDeltaX == 0 && event.scrollingDeltaY == 0
            if event.window !== panel, event.window !== companion?(), !isStillScroll { dismiss() }
            return event
        }
    }

    private func dismiss() {
        if let onDismiss { onDismiss() } else { hide() }
    }
}

/// Shows a menu in a `PopupPanel`, moves its highlight and picks from it. With `takesKeys` the menu takes every
/// key while it's open: ↑↓ move, ↵ picks and esc dismisses; letters highlight the item whose title they start, or
/// go to the search field when the menu has one. Without it, the caller passes keys to `move(by:)` and
/// `pickHighlighted()`.
final class PopupMenu<Item: PopupMenuItem, Row: View> {
    private let model: PopupMenuModel<Item>
    private let panel: PopupPanel<PopupMenuView<Item, Row>>
    private let submenuModel: PopupMenuModel<Item>
    private let submenuPanel: PopupPanel<PopupMenuView<Item, Row>>
    private weak var parentWindow: NSWindow?
    private var typed = ""
    private var typedAt: TimeInterval = 0

    /// What dismissing does; hides the menu unless set.
    var onDismiss: (() -> Void)? {
        get { panel.onDismiss }
        set { panel.onDismiss = newValue }
    }

    /// The search field's placeholder. The field shows while there's one, and has the keyboard.
    var searchPrompt: String? {
        get { model.searchPrompt }
        set { model.searchPrompt = newValue }
    }

    /// What's typed in the search field.
    var query: String {
        get { model.query }
        set { model.query = newValue }
    }

    /// Called as the search field's text is typed.
    var onSearch: (String) -> Void {
        get { model.onSearch }
        set { model.onSearch = newValue }
    }

    /// The footer's key hints, in place of ↑↓ Navigate, ↵ and the style's confirm label, and esc Close.
    var footerHints: [(key: String, label: String)]? {
        get { model.footerHints }
        set { model.footerHints = newValue }
    }

    /// What ⇧↵ does in a menu that takes keys; ⇧↵ picks the highlighted item unless set.
    var onShiftReturn: (() -> Void)?

    /// `row` draws an item's row content, given whether it's highlighted. A menu with a `searchPrompt` has a
    /// search field above its list.
    init(style: PopupMenuStyle, takesKeys: Bool, emptyText: String? = nil, searchPrompt: String? = nil,
         row: @escaping (_ item: Item, _ isHighlighted: Bool, _ theme: Theme) -> Row) {
        let model = PopupMenuModel<Item>(style: style, emptyText: emptyText)
        model.searchPrompt = searchPrompt
        self.model = model
        panel = PopupPanel(becomesKey: searchPrompt != nil) { PopupMenuView(model: model, row: row) }
        let submenuModel = PopupMenuModel<Item>(style: .compact, emptyText: nil)
        self.submenuModel = submenuModel
        submenuPanel = PopupPanel { PopupMenuView(model: submenuModel, row: row) }
        if takesKeys { panel.onKey = { [weak self] event in self?.handleKey(event) ?? false } }
        panel.onEscape = { [weak self] in self?.closeSubmenu() ?? false }
        panel.onHide = { [weak self] in self?.closeSubmenu() }
        panel.companion = { [weak self] in self?.submenuPanel.window }
        submenuPanel.companion = { [weak self] in self?.panel.window }
        model.onHover = { [weak self] index in self?.hover(index) }
        submenuModel.pick = { [weak self] item in self?.pickFromSubmenu(item) }
    }

    var isOpen: Bool { panel.isOpen }
    /// Whether a submenu is open beside a row.
    var isSubmenuOpen: Bool { submenuPanel.isOpen }
    /// The highlighted submenu row, as an index into its items; nil when none is.
    var submenuHighlight: Int? { submenuModel.highlight }
    /// The highlighted item, as an index into all the items; nil when none is.
    var highlight: Int? { model.highlight }

    /// Shows `sections` below `anchor` (screen coordinates), `inset` points left of it and `gap` below, or above
    /// it when there's no room below. Refreshes the menu when it's already open.
    /// `header` is drawn above the list, `height` tall, with a divider under it.
    func show(_ sections: [PopupMenuSection<Item>], highlight: Int?, theme: Theme, below anchor: CGRect,
              inset: CGFloat, gap: CGFloat, in parent: NSWindow, header: (height: CGFloat, view: AnyView)? = nil,
              pick: @escaping (Item) -> Void) {
        closeSubmenu()
        let opening = !panel.isOpen
        model.header = header
        model.sections = sections.filter { !$0.items.isEmpty }
        model.highlight = highlight
        model.theme = theme
        model.pick = pick
        parentWindow = parent
        model.revision += 1
        panel.show(size: model.size, below: anchor, inset: inset, gap: gap, in: parent)
        if opening { announceHighlight() }
    }

    func hide() { panel.hide() }

    /// Moves the highlight `offset` items, wrapping round, in the open submenu or else the menu. With none
    /// highlighted, down starts at the first item and up at the last.
    func move(by offset: Int) {
        let target = isSubmenuOpen ? submenuModel : model
        let items = target.items
        let count = items.count
        guard count > 0 else { return }
        var index = target.highlight.map { ($0 + offset % count + count) % count } ?? (offset > 0 ? 0 : count - 1)
        var tries = 0
        while !items[index].isEnabled, tries < count {
            index = (index + (offset > 0 ? 1 : count - 1)) % count
            tries += 1
        }
        guard items[index].isEnabled else { return }
        target.highlight = index
        announceHighlight()
    }

    /// Picks the highlighted item of the open submenu, or of the menu, where a row with a submenu opens its
    /// submenu instead; false when there's none.
    @discardableResult
    func pickHighlighted() -> Bool {
        if isSubmenuOpen {
            guard let highlight = submenuModel.highlight, submenuModel.items.indices.contains(highlight),
                  submenuModel.items[highlight].isEnabled else { return false }
            pickFromSubmenu(submenuModel.items[highlight])
            return true
        }
        guard let highlight = model.highlight, model.items.indices.contains(highlight),
              model.items[highlight].isEnabled else { return false }
        if model.items[highlight].submenu.isEmpty {
            model.pick(model.items[highlight])
        } else {
            openSubmenu(at: highlight, highlightFirst: true)
        }
        return true
    }

    /// Opens the highlighted row's submenu with its first row highlighted; false when the row has none.
    @discardableResult
    func openSubmenu() -> Bool {
        guard !isSubmenuOpen, let highlight = model.highlight, model.items.indices.contains(highlight),
              !model.items[highlight].submenu.isEmpty else { return false }
        openSubmenu(at: highlight, highlightFirst: true)
        return true
    }

    /// Closes the open submenu; false when none was open.
    @discardableResult
    func closeSubmenu() -> Bool {
        let wasOpen = isSubmenuOpen
        model.openIndex = nil
        submenuModel.highlight = nil
        submenuPanel.hide()
        return wasOpen
    }

    /// The screen frames of the menu and its open submenu.
    var rootFrame: CGRect? { panel.frame }
    var submenuFrame: CGRect? { submenuPanel.frame }

    /// What the pointer entering row `index` does: opens its submenu, or closes the open one.
    func hover(_ index: Int) {
        if model.items.indices.contains(index), !model.items[index].submenu.isEmpty {
            guard model.openIndex != index else { return }
            openSubmenu(at: index, highlightFirst: false)
        } else {
            closeSubmenu()
        }
    }

    private func openSubmenu(at index: Int, highlightFirst: Bool) {
        guard let parent = parentWindow, let rootFrame = panel.frame else { return }
        model.highlight = index
        model.openIndex = index
        submenuModel.sections = model.items[index].submenu
        submenuModel.highlight = highlightFirst ? submenuModel.items.firstIndex { $0.isEnabled } : nil
        submenuModel.theme = model.theme
        submenuModel.revision += 1
        let top = rootFrame.maxY - model.rowTop(of: index)
        let row = CGRect(x: rootFrame.minX, y: top - model.style.rowHeight, width: rootFrame.width,
                         height: model.style.rowHeight)
        submenuPanel.show(size: submenuModel.size, beside: row, inset: submenuModel.style.padding, in: parent)
        if highlightFirst { announceHighlight() }
    }

    private func pickFromSubmenu(_ item: Item) {
        model.pick(item)
        hide()
    }

    func handleKey(_ event: NSEvent) -> Bool {
        switch event.specialKey {
        case .downArrow: move(by: 1)
        case .upArrow: move(by: -1)
        case .rightArrow:
            if !isSubmenuOpen, !openSubmenu(), model.searchPrompt != nil { return false }
        case .leftArrow:
            if !closeSubmenu(), model.searchPrompt != nil { return false }
        case .carriageReturn, .enter:
            if event.modifierFlags.contains(.shift), let onShiftReturn { onShiftReturn() } else { pickHighlighted() }
        default:
            guard model.searchPrompt == nil else { return false }
            if !isSubmenuOpen { typeSelect(event) }
        }
        return true
    }

    /// Highlights the item whose title starts with the letters typed in the last second, as menus do.
    private func typeSelect(_ event: NSEvent) {
        guard event.specialKey == nil, event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
              let characters = event.characters, !characters.isEmpty else { return }
        typed = event.timestamp - typedAt < 1 ? typed + characters : characters
        typedAt = event.timestamp
        guard let match = TypeSelect.match(typed, in: model.items.map { $0.isEnabled ? $0.title : "" }, from: model.highlight) else { return }
        model.highlight = match
        announceHighlight()
    }

    private func announceHighlight() {
        let target = isSubmenuOpen ? submenuModel : model
        guard let highlight = target.highlight, target.items.indices.contains(highlight) else { return }
        let item = target.items[highlight]
        announceToVoiceOver([item.title, item.accessibilityValue].filter { !$0.isEmpty }.joined(separator: ", "))
    }
}

/// Reads `text` to VoiceOver, which stays on the window under a popup while it moves through the popup's items.
func announceToVoiceOver(_ text: String) {
    guard NSWorkspace.shared.isVoiceOverEnabled else { return }
    NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                         userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
}

/// Which item typing picks in a menu.
enum TypeSelect {
    /// The first of `titles` from `start` on, wrapping round, that starts with `typed`, ignoring case. The same
    /// letter typed again steps on to the next title that starts with it.
    static func match(_ typed: String, in titles: [String], from start: Int?) -> Int? {
        guard let letter = typed.first, !titles.isEmpty else { return nil }
        let repeats = typed.allSatisfy { $0 == letter }
        let prefix = repeats ? String(letter) : typed
        let first = start.map { repeats ? $0 + 1 : $0 } ?? 0
        return (0..<titles.count).lazy.map { (first + $0) % titles.count }.first {
            titles[$0].range(of: prefix, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

@Observable
private final class PopupMenuModel<Item: PopupMenuItem> {
    let style: PopupMenuStyle
    let emptyText: String?
    var sections: [PopupMenuSection<Item>] = []
    var highlight: Int?
    var theme = Theme.all[0]
    var searchPrompt: String?
    var header: (height: CGFloat, view: AnyView)?
    var query = ""
    var footerHints: [(key: String, label: String)]?
    /// Bumped on each show, to scroll the highlight into view.
    var revision = 0
    @ObservationIgnored var pick: (Item) -> Void = { _ in }
    /// Called with the index of a row the pointer enters or taps.
    @ObservationIgnored var onHover: (Int) -> Void = { _ in }
    /// The row whose submenu is open.
    @ObservationIgnored var openIndex: Int?
    @ObservationIgnored var onSearch: (String) -> Void = { _ in }

    init(style: PopupMenuStyle, emptyText: String?) {
        self.style = style
        self.emptyText = emptyText
    }

    var items: [Item] { sections.flatMap(\.items) }

    /// The labels, dividers and rows, 1pt apart, up to the style's limit.
    var listHeight: CGFloat {
        guard !items.isEmpty else { return emptyText == nil ? 0 : PopupMenuStyle.emptyHeight }
        var heights: [CGFloat] = []
        for (index, section) in sections.enumerated() {
            if section.label != nil {
                heights.append(PopupMenuStyle.labelHeight)
            } else if index > 0 {
                heights.append(PopupMenuStyle.dividerHeight)
            }
            heights += Array(repeating: style.rowHeight, count: section.items.count)
        }
        return min(heights.reduce(0, +) + CGFloat(heights.count - 1), style.maxListHeight)
    }

    /// A row's distance from the panel's top, under the padding, search field, header and the rows and labels
    /// before it, 1pt apart, at most the list's visible height. Submenus assume an unscrolled list.
    func rowTop(of index: Int) -> CGFloat {
        var y = style.padding + (searchPrompt == nil ? 0 : PopupMenuStyle.searchHeight)
            + (header.map { $0.height + PopupMenuStyle.dividerHeight } ?? 0)
        let limit = y + max(listHeight - style.rowHeight, 0)
        var seen = 0
        for (sectionIndex, section) in sections.enumerated() {
            if section.label != nil {
                y += PopupMenuStyle.labelHeight + 1
            } else if sectionIndex > 0 {
                y += PopupMenuStyle.dividerHeight + 1
            }
            if index < seen + section.items.count { return min(y + CGFloat(index - seen) * (style.rowHeight + 1), limit) }
            y += CGFloat(section.items.count) * (style.rowHeight + 1)
            seen += section.items.count
        }
        return min(y, limit)
    }

    /// The search field, the header and its divider, the list, the padding all round and the footer.
    var size: CGSize {
        let search = searchPrompt == nil ? 0 : PopupMenuStyle.searchHeight
        let header = header.map { $0.height + PopupMenuStyle.dividerHeight } ?? 0
        let footer = style.confirmLabel == nil ? 0 : PopupMenuStyle.footerHeight
        return CGSize(width: style.width, height: search + header + listHeight + style.padding * 2 + footer)
    }
}

private struct PopupMenuView<Item: PopupMenuItem, Row: View>: View {
    let model: PopupMenuModel<Item>
    let row: (Item, Bool, Theme) -> Row

    private var style: PopupMenuStyle { model.style }
    private var theme: Theme { model.theme }

    var body: some View {
        VStack(spacing: 0) {
            if let prompt = model.searchPrompt {
                PopupField(prompt: prompt, systemImage: "magnifyingglass", text: Binding { model.query } set: { query in
                    guard query != model.query else { return }
                    model.query = query
                    model.onSearch(query)
                }, theme: theme, revision: model.revision)
            }
            if let header = model.header {
                header.view
                    .frame(height: header.height)
                Hairline()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .accessibilityHidden(true)
            }
            ScrollViewReader { scroller in
                ScrollView { list }
                    .scrollIndicators(.automatic)
                    .frame(height: model.listHeight)
                    .onChange(of: model.revision, initial: true) { reveal(in: scroller, anchor: .center) }
                    .onChange(of: model.highlight) { reveal(in: scroller, anchor: nil) }
            }
            if let confirm = style.confirmLabel {
                PopupFooter(hints: model.footerHints ?? [("↑↓", "Navigate"), ("↵", confirm), ("esc", "Close")], theme: theme)
            }
        }
        .popupChrome(theme: theme, width: style.width, padding: style.padding)
        .font(.system(size: style.fontSize))
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(model.sections.enumerated()), id: \.offset) { index, section in
                if let label = section.label {
                    Text(label.uppercased())
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(theme.color(\.muted))
                        .padding(.horizontal, 10)
                        .frame(height: PopupMenuStyle.labelHeight - 1, alignment: .bottom)
                        .padding(.bottom, 1)
                        .accessibilityAddTraits(.isHeader)
                        .id(LabelID(section: index))
                } else if index > 0 {
                    Hairline()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .accessibilityHidden(true)
                }
                let start = model.sections[..<index].reduce(0) { $0 + $1.items.count }
                ForEach(Array(section.items.enumerated()), id: \.offset) { offset, item in
                    rowView(item, index: start + offset)
                }
            }
            if model.items.isEmpty, let emptyText = model.emptyText {
                Text(emptyText)
                    .foregroundStyle(theme.color(\.muted))
                    .padding(.horizontal, 10)
                    .frame(height: PopupMenuStyle.emptyHeight, alignment: .leading)
            }
        }
    }

    private func rowView(_ item: Item, index: Int) -> some View {
        let isHighlighted = model.highlight == index
        let fill: Color = !isHighlighted ? .clear
            : item.isDestructive ? theme.color(\.deadline).opacity(theme.isDark ? 0.22 : 0.14)
            : theme.color(\.surface)
        return HStack(spacing: 8) {
            row(item, isHighlighted, theme)
            if !item.submenu.isEmpty {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.color(\.muted))
                    .accessibilityHidden(true)
            }
        }
            .padding(.horizontal, style.rowPadding)
            .frame(height: style.rowHeight)
            .background(fill, in: .rect(cornerRadius: style.rowRadius))
            .opacity(item.isEnabled ? 1 : 0.45)
            .contentShape(.rect)
            .onHover { inside in
                if inside {
                    if item.isEnabled { model.highlight = index }
                    model.onHover(index)
                } else if !style.keepsHighlight, model.highlight == index, model.openIndex != index {
                    model.highlight = nil
                }
            }
            .onTapGesture { activate(item, index: index) }
            .id(RowID(index: index))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.title)
            .accessibilityValue(item.accessibilityValue)
            .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { activate(item, index: index) }
    }

    private func activate(_ item: Item, index: Int) {
        guard item.isEnabled else { return }
        if item.submenu.isEmpty { model.pick(item) } else { model.onHover(index) }
    }

    /// Scrolls the highlighted row into view; the first row brings its section's label too.
    private func reveal(in scroller: ScrollViewProxy, anchor: UnitPoint?) {
        guard let highlight = model.highlight, model.items.indices.contains(highlight) else { return }
        if highlight == 0, model.sections.first?.label != nil {
            scroller.scrollTo(LabelID(section: 0), anchor: .top)
        } else {
            scroller.scrollTo(RowID(index: highlight), anchor: anchor)
        }
    }
}

/// The text field at the top of a popup (a menu's search, the calendar's typed date), in `surface`, with a
/// muted `note` on its right. It takes the keyboard each time `revision` changes.
struct PopupField: View {
    let prompt: String
    let systemImage: String
    @Binding var text: String
    var note: String?
    let theme: Theme
    let revision: Int
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.color(\.muted))
                .accessibilityHidden(true)
            TextField(prompt, text: $text, prompt: Text(prompt).foregroundStyle(theme.color(\.muted)))
                .textFieldStyle(.plain)
                .foregroundStyle(theme.color(\.strong))
                .focused($focused)
            if let note {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.color(\.muted))
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityHidden(true)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .frame(height: PopupMenuStyle.searchHeight - 4)
        .background(theme.color(\.surface), in: .rect(cornerRadius: 7))
        .padding(2)
        .onChange(of: revision, initial: true) { focused = true }
    }
}

private struct LabelID: Hashable {
    let section: Int
}

/// A row's place in all the items, apart from the `ForEach` offsets in each section.
private struct RowID: Hashable {
    let index: Int
}

extension View {
    /// A popup's panel as the Menu component draws it: `side` in dark schemes and `bg` in light ones, inside a
    /// `surface` border. Its content gets `theme` as the `\.theme` environment value.
    func popupChrome(theme: Theme, width: CGFloat, padding: CGFloat) -> some View {
        self.padding(padding)
            .frame(width: width)
            .background(theme.color(theme.isDark ? \.side : \.bg), in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color(\.surface)))
            .environment(\.colorScheme, theme.isDark ? .dark : .light)
            .environment(\.theme, theme)
    }
}

/// Key caps and what they do, under a hairline at the foot of a popup.
struct PopupFooter: View {
    let hints: [(key: String, label: String)]
    let theme: Theme

    var body: some View {
        HStack(spacing: 14) {
            ForEach(hints.indices, id: \.self) { i in
                MenuKeyHint(key: hints[i].key, label: hints[i].label, theme: theme)
            }
            Spacer()
        }
        .font(.system(size: 11))
        .foregroundStyle(theme.color(\.muted))
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .frame(height: PopupMenuStyle.footerHeight, alignment: .top)
        .overlay(alignment: .top) { Hairline() }
        .accessibilityHidden(true)
    }
}

/// A key cap and what it does, for a popup's footer.
struct MenuKeyHint: View {
    let key: String
    let label: String
    let theme: Theme

    var body: some View {
        HStack(spacing: 5) {
            KeyCap(key: key, theme: theme)
            Text(label)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// A key or chord (esc, ⌘P, ⇧⌘S) on a cap, in the system font, whose ⌘ ⇧ ⌥ ⌃ ⌫ ↵ ⇥ match its letters.
struct KeyCap: View {
    let key: String
    var size: CGFloat = 10.5
    let theme: Theme

    var body: some View {
        Text(key)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(theme.color(\.fg))
            .padding(.horizontal, size * 0.5)
            .frame(minWidth: size * 1.9, minHeight: size * 1.6)
            .background(theme.color(\.surface), in: .rect(cornerRadius: 4))
            .lineLimit(1)
            .fixedSize()
    }
}

/// A borderless panel becomes key only when it says it can.
private final class KeyablePanel: NSPanel {
    var becomesKey = false
    override var canBecomeKey: Bool { becomesKey }
}

/// A panel that isn't key passes its first click straight to its content.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
#endif
