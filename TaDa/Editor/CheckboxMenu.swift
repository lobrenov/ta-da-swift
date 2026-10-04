// The checkbox menu: a themed list of checkbox markers in a borderless panel under a right-clicked box.
// The editor engine reports the right-click; LiveEditor bridges the two.
import SwiftUI
import AppKit
import TaDaCore

/// Shows, moves through and picks from the checkbox menu. Owned by LiveEditor.
final class CheckboxMenuController {
    private let model = CheckboxMenuModel()
    private var panel: NSPanel?
    private var eventMonitor: Any?

    /// Shows the menu under `anchor` (the box, in screen coordinates) with `current` selected.
    func show(current: Character, anchor: CGRect, items: [(marker: Character, title: String)],
              tints: [Character: NSColor], theme: Theme, pick: @escaping (Character) -> Void) {
        guard anchor != .zero, let parent = NSApp.keyWindow else { return }
        let all = items.map { CheckboxMenuItem(marker: $0.marker, title: $0.title) }
        model.items = all.filter { !$0.isIcon } + all.filter(\.isIcon)
        model.current = current
        model.selection = model.items.firstIndex { $0.marker == current } ?? 0
        model.tints = tints
        model.theme = theme
        model.pick = { [weak self] marker in
            self?.hide()
            pick(marker)
        }
        model.revision += 1

        let panel = panel ?? makePanel()
        let size = model.size
        // The rows' boxes line up under the clicked box.
        var origin = CGPoint(x: anchor.minX - 16, y: anchor.minY - 4 - size.height)
        if let visible = parent.screen?.visibleFrame {
            if origin.y < visible.minY { origin.y = anchor.maxY + 4 }
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
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        guard let panel, panel.isVisible else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.contentView = FirstMouseHostingView(rootView: CheckboxMenuView(model: model))
        self.panel = panel
        return panel
    }

    /// While open, the menu takes every key: ↑↓ move, ↵ picks, esc closes. A click elsewhere or a scroll closes it.
    private func installEventMonitor() {
        guard eventMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                handle(event)
                return nil
            }
            if event.window !== panel { hide() }
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        let count = model.items.count
        switch event.keyCode {
        case 125 where count > 0: model.selection = (model.selection + 1) % count
        case 126 where count > 0: model.selection = (model.selection + count - 1) % count
        case 36, 76 where model.items.indices.contains(model.selection): model.pick(model.items[model.selection].marker)
        case 53: hide()
        default: break
        }
    }
}

private struct CheckboxMenuItem: Hashable {
    let marker: Character
    let title: String

    /// Reference-set markers that aren't subtasks.
    var isIcon: Bool { Checkbox.State(marker: marker) == .icon }
}

@Observable
private final class CheckboxMenuModel {
    var items: [CheckboxMenuItem] = []
    var current: Character = " "
    var selection = 0
    /// Bumped on each show, to scroll the current marker into view.
    var revision = 0
    var tints: [Character: NSColor] = [:]
    var theme = Theme.all[0]
    @ObservationIgnored var pick: (Character) -> Void = { _ in }

    static let width: CGFloat = 288
    static let rowHeight: CGFloat = 34
    static let headerHeight: CGFloat = 25
    static let maxListHeight: CGFloat = 400

    var sections: [(title: String, items: [CheckboxMenuItem])] {
        [("Subtasks", items.filter { !$0.isIcon }), ("Icons", items.filter(\.isIcon))].filter { !$0.items.isEmpty }
    }

    var listHeight: CGFloat {
        let content = CGFloat(items.count) * (Self.rowHeight + 1) + CGFloat(sections.count) * Self.headerHeight
        return min(content, Self.maxListHeight)
    }

    /// The list, a 6pt pad all round, and the 34pt footer.
    var size: CGSize { CGSize(width: Self.width, height: listHeight + 12 + 34) }
}

private struct CheckboxMenuView: View {
    let model: CheckboxMenuModel

    private var theme: Theme { model.theme }
    private var menuBackground: Color { theme.color(theme.isDark ? \.side : \.bg) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(model.sections, id: \.title) { section in
                            Text(section.title.uppercased())
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.6)
                                .foregroundStyle(theme.color(\.muted))
                                .padding(.horizontal, 10)
                                .frame(height: CheckboxMenuModel.headerHeight - 1, alignment: .bottom)
                                .padding(.bottom, 1)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(section.items, id: \.self) { item in
                                row(item)
                            }
                        }
                    }
                }
                .scrollIndicators(.automatic)
                .frame(height: model.listHeight)
                .onAppear { scroller.scrollTo(model.current, anchor: .center) }
                .onChange(of: model.revision) { scroller.scrollTo(model.current, anchor: .center) }
                .onChange(of: model.selection) {
                    guard model.items.indices.contains(model.selection) else { return }
                    scroller.scrollTo(model.items[model.selection].marker)
                }
            }
            footer
        }
        .padding(6)
        .frame(width: CheckboxMenuModel.width)
        .background(menuBackground, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color(\.surface)))
        .font(.system(size: 13.5))
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
    }

    private func row(_ item: CheckboxMenuItem) -> some View {
        let isSelected = model.items.firstIndex(of: item) == model.selection
        let isCurrent = item.marker == model.current
        return HStack(spacing: 10) {
            InlineCheckboxView(marker: item.marker, tint: model.tints[item.marker] ?? theme.fg, background: theme.bg)
                .frame(width: 16, height: 16)
            Text(item.title)
                .foregroundStyle(theme.color(isSelected ? \.strong : \.fg))
                .lineLimit(1)
            Spacer(minLength: 8)
            if isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.color(\.accent))
            }
            Text("[\(item.marker)]")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.color(\.muted))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .frame(height: CheckboxMenuModel.rowHeight)
        .background(isSelected ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 7))
        .contentShape(.rect)
        .onHover { inside in
            if inside, let index = model.items.firstIndex(of: item) { model.selection = index }
        }
        .onTapGesture { model.pick(item.marker) }
        .id(item.marker)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.title)
        .accessibilityValue(isCurrent ? "Current" : "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.pick(item.marker) }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            MenuKeyHint(key: "↑↓", label: "Navigate", theme: theme)
            MenuKeyHint(key: "↵", label: "Set", theme: theme)
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
