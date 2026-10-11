import AppKit
import Testing
@testable import TaDa

@MainActor
struct SidebarSwipeTests {
    /// Tracks each event in turn, returning what each one said.
    private func track(_ events: [(NSEvent.Phase, CGFloat, CGFloat)]) -> [Bool] {
        var swipe = SidebarSwipe()
        return events.map { swipe.track($0.0, dx: $0.1, dy: $0.2) }
    }

    @Test func aSidewaysSwipeToTheRightCountsOnce() {
        #expect(track([(.began, 10, 1), (.changed, 20, 2), (.changed, 15, 1), (.changed, 30, 0), (.ended, 0, 0)])
                == [false, false, true, false, false])
    }

    @Test func leftwardsOrMostlyVerticalSwipesDontCount() {
        #expect(track([(.began, -20, 0), (.changed, -40, 0), (.began, 20, 30), (.changed, 30, 40)]) == [false, false, false, false])
    }

    @Test func momentumAfterTheFingersLiftDoesntCount() {
        #expect(track([(.began, 10, 0), (.ended, 0, 0), ([], 60, 0)]) == [false, false, false])
    }

    @Test func eachGestureCountsAgain() {
        #expect(track([(.began, 50, 0), (.began, 50, 0)]) == [true, true])
    }
}
