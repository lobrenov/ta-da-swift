// Applies the model's theme to a window: the `\.theme` environment value and the matching system
// appearance for the window, following the Mac's appearance as it changes.
import AppKit
import Combine
import SwiftUI

extension View {
    func themed(by model: AppModel) -> some View {
        modifier(Themed(model: model))
    }
}

private struct Themed: ViewModifier {
    let model: AppModel

    func body(content: Content) -> some View {
        content
            .environment(\.theme, model.theme)
            // Light schemes use the light system appearance so pickers, context menus and scroll bars match.
            .preferredColorScheme(model.theme.isDark ? .dark : .light)
            .onReceive(NSApp.publisher(for: \.effectiveAppearance)) { _ in
                model.systemIsDark = Appearance.systemIsDark
            }
    }
}
