// A note's symbol: a page, in `muted`.
import SwiftUI

struct NoteIcon: View {
    /// 16 in a noteRow, 12 in a chip.
    var size: CGFloat = 16
    var tint: KeyPath<Theme, PlatformColor> = \.muted
    @Environment(\.theme) private var theme

    var body: some View {
        Image(systemName: "doc.text")
            .font(.system(size: size * 0.85, weight: .regular))
            .foregroundStyle(theme.color(tint))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
