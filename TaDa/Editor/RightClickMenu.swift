// The Live editor's right-click menu: sections of items in a compact popup menu under what was clicked, which the
// engine rings until the menu closes. The table's row and column grips use it; later uses add items, not menus.
#if os(macOS)
import SwiftUI
import AppKit
import TaDaCore

/// One row of a right-click menu.
struct RightClickMenuEntry: PopupMenuItem {
    let title: String
    var systemImage: String? = nil
    /// A key hint on the right.
    var shortcut: String? = nil
    /// Drawn with a tick: the current choice.
    var isChecked = false
    var isDestructive = false
    let action: () -> Void

    var accessibilityValue: String { isChecked ? "Current" : "" }
}

/// Shows, moves through and picks from a right-click menu. Owned by LiveEditor.
final class RightClickMenuController {
    private let menu = PopupMenu(style: .compact, takesKeys: true, row: RightClickMenuRow.init)

    /// Opens the menu under `anchor` (screen coordinates), with a divider between `sections`. `close` runs however
    /// the menu closes.
    func show(_ sections: [[RightClickMenuEntry]], anchor: CGRect, theme: Theme, close: @escaping () -> Void) {
        guard anchor != .zero, let parent = NSApp.keyWindow else { return close() }
        menu.onDismiss = { [weak self] in
            self?.hide()
            close()
        }
        menu.show(sections.map { PopupMenuSection(items: $0) }, highlight: nil, theme: theme, below: anchor,
                  inset: 0, gap: 4, in: parent) { [weak self] item in
            self?.hide()
            close()
            item.action()
        }
    }

    func hide() { menu.hide() }
}

private struct RightClickMenuRow: View {
    let item: RightClickMenuEntry
    let isHighlighted: Bool
    let theme: Theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.systemImage ?? "circle")
                .font(.system(size: 12))
                .frame(width: 14)
                .opacity(item.systemImage == nil ? 0 : 1)
                .foregroundStyle(theme.color(item.isDestructive ? \.deadline : isHighlighted ? \.accent : \.muted))
            Text(item.title)
                .foregroundStyle(theme.color(item.isDestructive ? \.deadline : isHighlighted ? \.strong : \.fg))
                .lineLimit(1)
            Spacer(minLength: 8)
            if item.isChecked {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.color(\.accent))
            }
            if let shortcut = item.shortcut {
                Text(shortcut)
                    .font(.system(size: 11.5))
                    .tracking(0.5)
                    .foregroundStyle(theme.color(\.muted))
            }
        }
    }
}
#endif
