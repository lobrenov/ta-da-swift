import Testing
@testable import TaDaCore

@Test func checkboxStatesFollowTheReferenceSet() {
    for marker in [" ", "/", ">", "<"] as [Character] { #expect(Checkbox.State(marker: marker) == .open) }
    for marker in ["x", "X"] as [Character] { #expect(Checkbox.State(marker: marker) == .done) }
    #expect(Checkbox.State(marker: "-") == .cancelled)
    for marker in Array("?!*\"lbiSIpcfkwud") { #expect(Checkbox.State(marker: marker) == .icon) }
    for marker in ["y", "✓", "0"] as [Character] { #expect(Checkbox.State(marker: marker) == nil) }
}
