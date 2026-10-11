// A two-finger trackpad swipe to the left or right, followed scroll event by scroll event.
#if os(macOS)
import AppKit

struct SidebarSwipe {
    enum Direction { case left, right }

    /// How far the fingers go sideways, in points, before it's a swipe.
    static let distance: CGFloat = 40

    private var travel = CGSize.zero
    private var isDone = false

    /// Takes one scroll event's phase and the fingers' movement in it (`dx` positive to the right). Gives the direction
    /// once per gesture: when the fingers have gone `distance` sideways, at least twice as far as up or down.
    mutating func track(_ phase: NSEvent.Phase, dx: CGFloat, dy: CGFloat) -> Direction? {
        if phase.contains(.began) {
            travel = .zero
            isDone = false
        }
        guard phase.contains(.began) || phase.contains(.changed), !isDone else { return nil }
        travel.width += dx
        travel.height += dy
        guard abs(travel.width) >= Self.distance, abs(travel.width) >= abs(travel.height) * 2 else { return nil }
        isDone = true
        return travel.width > 0 ? .right : .left
    }

    /// The fingers' movement to the right in a scroll event: its delta, which natural scrolling reverses.
    static func fingersDX(_ event: NSEvent) -> CGFloat {
        event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
    }

    /// Whether a scroll view under the pointer can scroll left, so the swipe scrolls it instead.
    static func scrollsLeft(_ event: NSEvent) -> Bool {
        guard let content = event.window?.contentView else { return false }
        var view = content.hitTest(content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow)
        while let current = view {
            if let scroll = current as? NSScrollView, scroll.contentView.bounds.minX > 0 { return true }
            view = current.superview
        }
        return false
    }
}
#endif
