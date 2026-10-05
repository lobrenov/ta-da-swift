import Testing
@testable import TaDaCore

@Test func checkboxStatesFollowTheReferenceSet() {
    for marker in [" ", "/", ">", "<"] as [Character] { #expect(Checkbox.State(marker: marker) == .open) }
    for marker in ["x", "X"] as [Character] { #expect(Checkbox.State(marker: marker) == .done) }
    #expect(Checkbox.State(marker: "-") == .cancelled)
    for marker in Array("?!*\"lbiSIpcfkwud") { #expect(Checkbox.State(marker: marker) == .icon) }
    for marker in ["y", "✓", "0"] as [Character] { #expect(Checkbox.State(marker: marker) == nil) }
}

/// Lines around the edges of the checkbox syntax, and whether each has a box.
private let checkboxSyntaxCases: [(line: String, isBox: Bool)] = [
    ("- [ ] Open", true), ("  * [x] Done", true), ("1) [?] Icon", true), ("> - [-] Quoted", true),
    ("-  [ ] Two spaces", true), ("-\t[/] Tab", true), ("- [x]\tTab after", true),
    ("- [y] Unknown", false), ("- [ ]", false), ("- [x]NoSpace", false), ("-[ ] No space before", false),
    ("[ ] Not a list", false), ("-     [ ] Indented code", false),
]

@Test func theScannerAndAddSubtaskAgreeOnWhatIsABox() {
    for (line, isBox) in checkboxSyntaxCases {
        #expect(!BodyScanner.scan(line + "\n").checkboxes.isEmpty == isBox, "scanner: \(line)")
        let toggles = switch SubtaskLine.edit(for: line[...]) {
        case .convert: false
        case .setMarker, .none: true
        }
        #expect(toggles == isBox, "Add Subtask: \(line)")
    }
}
