// Applies the model's theme to a window: the `\.theme` environment value and the matching system
// appearance, following the Mac's appearance as it changes.
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
            .onChange(of: model.theme.isDark, initial: true) {
                // Light schemes use the light system appearance so menus, pickers and scroll bars match.
                NSApp.appearance = NSAppearance(named: model.theme.isDark ? .darkAqua : .aqua)
            }
            .onReceive(DistributedNotificationCenter.default().publisher(for: .init("AppleInterfaceThemeChangedNotification"))
                .receive(on: RunLoop.main)) { _ in
                model.systemIsDark = Appearance.systemIsDark
            }
    }
}
