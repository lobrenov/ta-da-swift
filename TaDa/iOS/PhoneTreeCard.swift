// What the Notes and Tags tabs draw their trees with: a rounded card of rows with folds, indents, icons and counts.
#if os(iOS)
import SwiftUI

/// A group's small muted label above its card.
struct PhoneCardLabel: View {
    let title: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(title)
            .scaledFont(size: 13)
            .foregroundStyle(theme.color(\.muted))
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 7)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Rows on a rounded `side` card with a hairline border.
struct PhoneCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) { content }
            .background(theme.color(\.side))
            .clipShape(.rect(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(theme.color(\.border)) }
            .padding(.horizontal, 16)
    }
}

/// A row of a card: its icon, name and count, opening `route`. With a `depth` it sits in a tree, indented 28pt per
/// level, with a fold chevron before it when it has children.
struct PhoneTreeRow: View {
    let symbol: String
    var tint: KeyPath<Theme, PlatformColor> = \.link
    let name: String
    /// What VoiceOver reads for the row.
    let spoken: String
    let route: PhoneRoute
    let count: Int
    var depth: Int? = nil
    var hasChildren = false
    var isFolded = false
    let isLast: Bool
    var toggleFold: () -> Void = {}
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            if depth != nil {
                Button { withAnimation(.snappy, toggleFold) } label: {
                    Image(systemName: "chevron.right")
                        .scaledFont(size: 13, weight: .bold)
                        .rotationEffect(.degrees(isFolded ? 0 : 90))
                        .foregroundStyle(theme.color(\.accent))
                        .opacity(hasChildren ? 1 : 0)
                        .frame(width: 30)
                        .frame(maxHeight: .infinity)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(!hasChildren)
                .accessibilityHidden(!hasChildren)
                .accessibilityLabel(isFolded ? "Expand \(name)" : "Collapse \(name)")
            }
            Button { nav.push(route) } label: {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .scaledFont(size: 18)
                        .foregroundStyle(theme.color(tint))
                        .frame(width: 24)
                    HStack(spacing: 8) {
                        Text(name)
                            .scaledFont(size: 17)
                            .foregroundStyle(theme.color(\.fg))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(count)").scaledFont(size: 17).foregroundStyle(theme.color(\.muted))
                        Image(systemName: "chevron.right")
                            .scaledFont(size: 13, weight: .semibold)
                            .foregroundStyle(theme.color(\.muted))
                    }
                    .padding(.vertical, 11)
                    .padding(.trailing, 14)
                    .scaledMinHeight(44)
                    .overlay(alignment: .bottom) { if !isLast { Hairline() } }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(spoken)
        }
        .padding(.leading, depth.map { 8 + CGFloat($0) * 28 } ?? 16)
    }
}
#endif
