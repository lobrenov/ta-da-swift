import SwiftUI
import Testing
@testable import TaDa

@MainActor
struct SidebarStateTests {
    /// Applies the columns `SidebarState` gives, as the view does once it has slid.
    private func slide(_ state: inout SidebarState, to columns: NavigationSplitViewVisibility?) {
        guard let columns else { return }
        state.columns = columns
        state.slid()
    }

    @Test func aNarrowWindowHidesTheSidebarAndAWideOneBringsItBack() {
        var state = SidebarState()
        #expect(state.fit(narrow: true) == .detailOnly)
        slide(&state, to: .detailOnly)
        #expect(state.usesOwnToggle)
        #expect(state.fit(narrow: false) == .all)
        #expect(!state.usesOwnToggle)
    }

    @Test func aSidebarHiddenByHandStaysHiddenWhenTheWindowWidens() {
        var state = SidebarState()
        slide(&state, to: state.toggle())
        #expect(state.columns == .detailOnly)
        #expect(state.fit(narrow: true) == nil)
        #expect(state.usesOwnToggle)
        #expect(state.fit(narrow: false) == nil)
        #expect(state.columns == .detailOnly)
    }

    @Test func inANarrowWindowTheButtonFloatsTheSidebar() {
        var state = SidebarState()
        slide(&state, to: state.fit(narrow: true))
        #expect(state.toggle() == nil)
        #expect(state.floats)
        #expect(state.toggle() == nil)
        #expect(!state.floats)
    }

    @Test func wideningTheWindowHidesTheFloatingSidebar() {
        var state = SidebarState()
        slide(&state, to: state.fit(narrow: true))
        _ = state.toggle()
        #expect(state.fit(narrow: false) == .all)
        #expect(!state.floats)
    }

    @Test func theSidebarCantDockInANarrowWindow() {
        var state = SidebarState()
        slide(&state, to: state.fit(narrow: true))
        _ = state.toggle()
        state.columns = .all
        #expect(state.columnsChanged() == .detailOnly)
        #expect(!state.floats)
        #expect(state.fit(narrow: false) == .all)
    }

    @Test func searchFloatsTheHiddenSidebarWithItsFieldFocused() {
        var state = SidebarState()
        state.searchRequested()
        #expect(!state.floats)
        slide(&state, to: state.fit(narrow: true))
        state.searchRequested()
        #expect(state.floats && state.floatsForSearch)
        state.floats = false
        #expect(!state.floatsForSearch)
    }

    @Test func swipes() {
        var state = SidebarState()
        #expect(state.switchesViews(overSidebar: true, swiping: true), "over the docked sidebar a swipe switches its view")
        #expect(!state.switchesViews(overSidebar: false, swiping: true))
        state.swiped(.right) { false }
        #expect(!state.floats)
        state.swiped(.left) { false }
        #expect(state.columns != .detailOnly, "a swipe no longer hides the docked sidebar")
        slide(&state, to: .detailOnly)
        #expect(!state.switchesViews(overSidebar: true, swiping: true) && !state.switchesViews(overSidebar: true, swiping: false))
        state.swiped(.right) { true }
        #expect(!state.floats)
        state.swiped(.right) { false }
        #expect(state.floats)
        #expect(!state.switchesViews(overSidebar: true, swiping: true), "a swipe over the floating sidebar hides it")
        #expect(state.switchesViews(overSidebar: true, swiping: false), "the mouse's buttons switch the floating sidebar's view")
        state.swiped(.left) { false }
        #expect(!state.floats)
    }
}
