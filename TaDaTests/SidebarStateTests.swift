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
        #expect(state.swiped(.right, overSidebar: false) { false } == nil)
        #expect(!state.floats)
        #expect(state.swiped(.left, overSidebar: false) { false } == nil)
        #expect(state.swiped(.left, overSidebar: true) { false } == .detailOnly)
        slide(&state, to: .detailOnly)
        #expect(state.swiped(.right, overSidebar: false) { true } == nil)
        #expect(!state.floats)
        _ = state.swiped(.right, overSidebar: false) { false }
        #expect(state.floats)
        _ = state.swiped(.left, overSidebar: false) { false }
        #expect(!state.floats)
    }
}
