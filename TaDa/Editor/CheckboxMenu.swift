// The checkbox menu: checkbox markers in a popup menu under a right-clicked box.
// The editor engine reports the right-click; LiveEditor bridges the two.
import SwiftUI
import AppKit
import TaDaCore

/// Shows, moves through and picks from the checkbox menu. Owned by LiveEditor.
final class CheckboxMenuController {
    private let menu = PopupMenu(style: .full(confirm: "Set", maxListHeight: 400), takesKeys: true,
                                 row: CheckboxMenuRow.init)

    /// Shows the menu under `anchor` (the box, in screen coordinates) with `current` highlighted.
    func show(current: Character, anchor: CGRect, items: [(marker: Character, title: String)],
              tints: [Character: NSColor], theme: Theme, pick: @escaping (Character) -> Void) {
        guard anchor != .zero, let parent = NSApp.keyWindow else { return }
        let all = items.map {
            CheckboxMenuItem(marker: $0.marker, title: $0.title, tint: tints[$0.marker] ?? theme.fg, isCurrent: $0.marker == current)
        }
        let sections = [PopupMenuSection(label: "Subtasks", items: all.filter { !$0.isIcon }),
                        PopupMenuSection(label: "Icons", items: all.filter(\.isIcon))]
        let highlight = sections.flatMap(\.items).firstIndex(where: \.isCurrent) ?? 0
        // The rows' boxes line up under the clicked box.
        menu.show(sections, highlight: highlight, theme: theme, below: anchor, inset: 16, gap: 4, in: parent) { [weak self] item in
            self?.hide()
            pick(item.marker)
        }
    }

    func hide() { menu.hide() }
}

private struct CheckboxMenuItem: PopupMenuItem {
    let marker: Character
    let title: String
    let tint: NSColor
    let isCurrent: Bool

    /// Reference-set markers that aren't subtasks.
    var isIcon: Bool { Checkbox.State(marker: marker) == .icon }
    var accessibilityValue: String { isCurrent ? "Current" : "" }
}

private struct CheckboxMenuRow: View {
    let item: CheckboxMenuItem
    let isHighlighted: Bool
    let theme: Theme

    var body: some View {
        HStack(spacing: 10) {
            InlineCheckboxView(marker: item.marker, tint: item.tint, background: theme.bg)
                .frame(width: 16, height: 16)
            Text(item.title)
                .foregroundStyle(theme.color(isHighlighted ? \.strong : \.fg))
                .lineLimit(1)
            Spacer(minLength: 8)
            if item.isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.color(\.accent))
            }
            Text(verbatim: "[\(item.marker)]")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.color(\.muted))
        }
    }
}
