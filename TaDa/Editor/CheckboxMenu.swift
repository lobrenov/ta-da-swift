// The checkbox menu: checkbox markers in a popup menu under a right-clicked box, with Extract to Task for a subtask.
// The editor engine reports the right-click; LiveEditor bridges the two.
#if os(macOS)
import SwiftUI
import AppKit
import TaDaCore

/// Shows, moves through and picks from the checkbox menu. Owned by LiveEditor.
final class CheckboxMenuController {
    private let menu = PopupMenu(style: .full(confirm: "Set", maxListHeight: 400), takesKeys: true,
                                 row: CheckboxMenuRow.init)

    /// Shows the menu under `anchor` (the box, in screen coordinates) with `current` highlighted. With `extract`, Extract
    /// to Task follows the subtask markers.
    func show(current: Character, anchor: CGRect, items: [(marker: Character, title: String)],
              theme: Theme, pick: @escaping (Character) -> Void, extract: (() -> Void)? = nil) {
        guard anchor != .zero, let parent = NSApp.keyWindow else { return }
        let all = items.map {
            CheckboxMenuItem(marker: $0.marker, title: $0.title, tint: theme.checkboxTint($0.marker), isCurrent: $0.marker == current)
        }
        var sections = [PopupMenuSection(label: "Subtasks", items: all.filter { !$0.isIcon }),
                        PopupMenuSection(label: "Icons", items: all.filter(\.isIcon))]
        if extract != nil {
            sections.insert(PopupMenuSection(items: [CheckboxMenuItem(marker: nil, title: "Extract to Task", tint: .clear, isCurrent: false)]),
                            at: 1)
        }
        let highlight = sections.flatMap(\.items).firstIndex(where: \.isCurrent) ?? 0
        // The rows' boxes line up under the clicked box.
        menu.show(sections, highlight: highlight, theme: theme, below: anchor, inset: 16, gap: 4, in: parent) { [weak self] item in
            self?.hide()
            if let marker = item.marker { pick(marker) } else { extract?() }
        }
    }

    func hide() { menu.hide() }
}

private struct CheckboxMenuItem: PopupMenuItem {
    /// Nil for Extract to Task.
    let marker: Character?
    let title: String
    let tint: NSColor
    let isCurrent: Bool

    /// Reference-set markers that aren't subtasks.
    var isIcon: Bool { marker.map { Checkbox.State(marker: $0) == .icon } ?? false }
    var accessibilityValue: String { isCurrent ? "Current" : "" }
}

private struct CheckboxMenuRow: View {
    let item: CheckboxMenuItem
    let isHighlighted: Bool
    let theme: Theme

    var body: some View {
        HStack(spacing: 10) {
            if let marker = item.marker {
                InlineCheckboxView(marker: marker, tint: item.tint, background: theme.bg)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.color(isHighlighted ? \.accent : \.muted))
                    .frame(width: 16, height: 16)
            }
            Text(item.title)
                .foregroundStyle(theme.color(isHighlighted ? \.strong : \.fg))
                .lineLimit(1)
            Spacer(minLength: 8)
            if item.isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.color(\.accent))
            }
            if let marker = item.marker {
                Text(verbatim: "[\(marker)]")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.color(\.muted))
            }
        }
    }
}
#endif
