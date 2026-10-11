import AppKit
import Testing
@testable import TaDa

@MainActor
struct SidebarSwipeTests {
    /// Tracks each event in turn, returning what each one said.
    private func track(_ events: [(NSEvent.Phase, CGFloat, CGFloat)]) -> [SidebarSwipe.Direction?] {
        var swipe = SidebarSwipe()
        return events.map { swipe.track($0.0, dx: $0.1, dy: $0.2) }
    }

    @Test func aSidewaysSwipeCountsOnce() {
        #expect(track([(.began, 10, 1), (.changed, 20, 2), (.changed, 15, 1), (.changed, 30, 0), (.ended, 0, 0)])
                == [nil, nil, .right, nil, nil])
        #expect(track([(.began, -20, 0), (.changed, -25, 3)]) == [nil, .left])
    }

    @Test func mostlyVerticalSwipesDontCount() {
        #expect(track([(.began, 20, 30), (.changed, 30, 40), (.began, -20, 30), (.changed, -30, -60)]) == [nil, nil, nil, nil])
    }

    @Test func momentumAfterTheFingersLiftDoesntCount() {
        #expect(track([(.began, 10, 0), (.ended, 0, 0), ([], 60, 0)]) == [nil, nil, nil])
    }

    @Test func eachGestureCountsAgain() {
        #expect(track([(.began, 50, 0), (.began, -50, 0)]) == [.right, .left])
    }
}
