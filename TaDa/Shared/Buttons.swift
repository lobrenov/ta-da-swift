// The design system's Button component: text buttons (`td-btn` and its kinds) and the segmented control (`td-seg`),
// as the canvas draws them.
import SwiftUI

/// A text button. `outlined` has a 1pt `border` and a 12pt `fg` label; `outlinedStrong` a 12.5pt semibold `strong`
/// one, beside a primary button; `primary` an `accent` fill and `danger` a `deadline` fill, with bold `bg` labels.
/// Disabled labels are `muted` and a disabled filled button is `surface`, all at half opacity as plain buttons are.
struct ActionButtonStyle: ButtonStyle {
    enum Kind { case outlined, outlinedStrong, primary, danger }

    var kind = Kind.outlined
    /// 30pt, or 28 in panels and confirmations and 32 in the sidebar.
    var height: CGFloat = 30
    /// Behind an outlined button's label, as on a panel.
    var fill: KeyPath<Theme, NSColor>? = nil
    /// Stretches the button across its container instead of padding the label.
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        ActionButtonBody(label: configuration.label, style: self)
    }
}

private struct ActionButtonBody<Label: View>: View {
    let label: Label
    let style: ActionButtonStyle
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let (size, weight, padding, text): (CGFloat, Font.Weight, CGFloat, KeyPath<Theme, NSColor>) = switch style.kind {
        case .outlined: (12, .regular, 12, \.fg)
        case .outlinedStrong: (12.5, .semibold, 14, \.strong)
        case .primary: (12.5, .bold, 16, \.bg)
        case .danger: (12, .bold, 12, \.bg)
        }
        let isOutlined = style.kind == .outlined || style.kind == .outlinedStrong
        label
            .font(.system(size: size, weight: weight))
            .foregroundStyle(theme.color(isEnabled ? text : \.muted))
            .padding(.horizontal, style.fullWidth ? 0 : padding)
            .frame(maxWidth: style.fullWidth ? .infinity : nil)
            .frame(height: style.height)
            .background(fill(isOutlined: isOutlined), in: .rect(cornerRadius: 7))
            .overlay {
                if isOutlined { RoundedRectangle(cornerRadius: 7).strokeBorder(theme.color(\.border)) }
            }
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(.rect)
    }

    private func fill(isOutlined: Bool) -> Color {
        if isOutlined { return style.fill.map { theme.color($0) } ?? .clear }
        return theme.color(!isEnabled ? \.surface : style.kind == .primary ? \.accent : \.deadline)
    }
}

/// Options side by side on a `surface` track; the selected one sits on `bg` in semibold `strong`.
struct SegmentedControl<Value: Hashable>: View {
    /// What VoiceOver calls the control.
    let label: String
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    /// A fixed segment height; nil pads each segment 3pt above and below.
    var height: CGFloat? = nil
    var unselectedWeight = Font.Weight.regular
    /// Added to each segment's help, as "Live (⌘E)".
    var shortcut: String? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                segment(options[i].value, options[i].title)
            }
        }
        .padding(2)
        .background(theme.color(\.surface), in: .rect(cornerRadius: 7))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func segment(_ value: Value, _ title: String) -> some View {
        let selected = value == selection
        return Button { selection = value } label: {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : unselectedWeight))
                .foregroundStyle(theme.color(selected ? \.strong : \.fg))
                .padding(.horizontal, 12)
                .padding(.vertical, height == nil ? 3 : 0)
                .frame(height: height)
                .background(selected ? theme.color(\.bg) : .clear, in: .rect(cornerRadius: 5))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(shortcut.map { "\(title) (\($0))" } ?? "")
    }
}
