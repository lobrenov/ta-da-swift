// The callout menu: callout types and fold signs in a popup menu under a right-clicked callout's icon.
// The editor engine reports the right-click; LiveEditor bridges the two.
import SwiftUI
import AppKit
import TaDaCore

/// Shows, moves through and picks from the callout menu. Owned by LiveEditor.
final class CalloutMenuController {
    private let menu = PopupMenu(style: .full(confirm: "Set", maxListHeight: 400), takesKeys: true,
                                 row: CalloutMenuRow.init)

    /// Shows the menu under `anchor` (the icon, in screen coordinates), opened on the current type: `type` and
    /// `fold` as the title line has them. `close` runs however the menu closes.
    func show(type: String, fold: Character?, anchor: CGRect, theme: Theme,
              setType: @escaping (CalloutType) -> Void, setFold: @escaping (Character?) -> Void,
              close: @escaping () -> Void) {
        guard anchor != .zero, let parent = NSApp.keyWindow else { return }
        let current = CalloutType(named: type)
        let types = CalloutType.allCases.map { CalloutMenuItem.type($0, tint: theme.calloutTint($0), isCurrent: $0 == current) }
        let folds = ([nil, "+", "-"] as [Character?]).map { CalloutMenuItem.fold($0, type: type, isCurrent: $0 == fold) }
        // An unknown type opens on Note.
        let highlight = CalloutType.allCases.firstIndex(of: current ?? .note)
        menu.onDismiss = { [weak self] in
            self?.hide()
            close()
        }
        // The rows' icons line up under the callout's.
        menu.show([PopupMenuSection(label: "Type", items: types), PopupMenuSection(label: "Fold", items: folds)],
                  highlight: highlight, theme: theme, below: anchor, inset: 16, gap: 4, in: parent) { [weak self] item in
            self?.hide()
            close()
            switch item {
            case .type(let type, _, _): setType(type)
            case .fold(let sign, _, _): setFold(sign)
            }
        }
    }

    func hide() { menu.hide() }
}

private enum CalloutMenuItem: PopupMenuItem {
    case type(CalloutType, tint: NSColor, isCurrent: Bool)
    /// The sign after `]`, and the type as written, for the syntax hint.
    case fold(Character?, type: String, isCurrent: Bool)

    var title: String {
        switch self {
        case .type(let type, _, _): type.title
        case .fold(nil, _, _): "Always open"
        case .fold("+", _, _): "Foldable, open"
        case .fold: "Foldable, folded"
        }
    }

    var isCurrent: Bool {
        switch self {
        case .type(_, _, let isCurrent), .fold(_, _, let isCurrent): isCurrent
        }
    }

    var syntax: String {
        switch self {
        case .type(let type, _, _): "[!\(type.rawValue)]"
        case .fold(let sign, let type, _): "[!\(type)]" + (sign.map { String($0) } ?? "")
        }
    }

    var accessibilityValue: String { isCurrent ? "Current" : "" }
}

private struct CalloutMenuRow: View {
    let item: CalloutMenuItem
    let isHighlighted: Bool
    let theme: Theme

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 16, height: 16)
            Text(item.title)
                .foregroundStyle(theme.color(isHighlighted ? \.strong : \.fg))
                .lineLimit(1)
            Spacer(minLength: 8)
            if item.isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.color(\.accent))
            }
            Text(verbatim: item.syntax)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.color(\.muted))
        }
    }

    @ViewBuilder private var icon: some View {
        switch item {
        case .type(let type, let tint, _):
            CalloutIconView(type: type, tint: tint)
        case .fold(let sign, _, _):
            // The artboard's dash and chevrons, in `muted` (`accent` when highlighted).
            Canvas { context, size in
                let points: [CGPoint] = switch sign {
                case nil: [CGPoint(x: 4.5, y: 8), CGPoint(x: 11.5, y: 8)]
                case "+": [CGPoint(x: 3.5, y: 6), CGPoint(x: 8, y: 10.5), CGPoint(x: 12.5, y: 6)]
                default: [CGPoint(x: 6, y: 3.5), CGPoint(x: 10.5, y: 8), CGPoint(x: 6, y: 12.5)]
                }
                var path = Path()
                path.addLines(points.map { CGPoint(x: $0.x * size.width / 16, y: $0.y * size.height / 16) })
                context.stroke(path, with: .color(theme.color(isHighlighted ? \.accent : \.muted)),
                               style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
