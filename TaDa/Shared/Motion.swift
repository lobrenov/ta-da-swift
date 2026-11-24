// Reduce Motion: what slides, springs and scales become when the system setting is on.
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum Motion {
    /// The system's Reduce Motion setting.
    static var isReduced: Bool {
        #if os(macOS)
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        #else
        UIAccessibility.isReduceMotionEnabled
        #endif
    }

    /// `animation`, or none with Reduce Motion on.
    static func animation(_ animation: Animation) -> Animation? {
        isReduced ? nil : animation
    }

    /// `transition`, or a short fade with Reduce Motion on.
    static func transition(_ transition: AnyTransition) -> AnyTransition {
        isReduced ? .opacity.animation(.easeOut(duration: 0.15)) : transition
    }
}

/// `withAnimation`, without the animation when Reduce Motion is on.
@discardableResult
func withMotion<Result>(_ animation: Animation = .default, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(Motion.animation(animation), body)
}

/// `withAnimation` with a completion, without the animation when Reduce Motion is on.
func withMotion<Result>(_ animation: Animation = .default, _ body: () throws -> Result,
                        completion: @escaping @MainActor @Sendable () -> Void) rethrows -> Result {
    try withAnimation(Motion.animation(animation), body, completion: completion)
}
