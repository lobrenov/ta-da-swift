// The tab bar hidden while a pushed screen is on top, animated with the push and the pop.
#if os(iOS)
import SwiftUI
import UIKit

/// Hides the tab bar while the screen is on top, through the tab bar controller as the navigation transition that
/// shows or covers the screen starts, so the bar animates with the push and the pop. A cancelled swipe back calls viewWillAppear again, which hides it again.
struct TabBarHiddenOnTop: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            setTabBarHidden(true)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            setTabBarHidden(false)
        }

        private func setTabBarHidden(_ hidden: Bool) {
            tabBarController?.setTabBarHidden(hidden, animated: transitionCoordinator != nil)
        }
    }
}
#endif
