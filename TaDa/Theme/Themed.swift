// Applies the model's theme to a window: the `\.theme` environment value and the matching system
// appearance for the window, following the system appearance as it changes.
import Combine
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension View {
    func themed(by model: AppModel) -> some View {
        modifier(Themed(model: model))
    }
}

private struct Themed: ViewModifier {
    let model: AppModel
    #if os(iOS)
    @State private var registration: (any UITraitChangeRegistration)?
    #endif

    func body(content: Content) -> some View {
        content
            .environment(\.theme, model.theme)
            // Light schemes use the light system appearance so pickers, context menus and scroll bars match.
            #if os(macOS)
            .preferredColorScheme(model.theme.isDark ? .dark : .light)
            .onReceive(NSApp.publisher(for: \.effectiveAppearance)) { _ in
                model.systemIsDark = Appearance.systemIsDark
            }
            #else
            // Overrides the windows, not the scene, so the scene keeps the device's appearance.
            .onChange(of: model.theme.isDark, initial: true) { _, isDark in
                for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                    for window in scene.windows { window.overrideUserInterfaceStyle = isDark ? .dark : .light }
                }
            }
            .onAppear {
                guard registration == nil,
                      let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
                model.systemIsDark = Appearance.systemIsDark
                registration = scene.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (_: UIWindowScene, _) in
                    model.systemIsDark = Appearance.systemIsDark
                }
            }
            #endif
    }
}
