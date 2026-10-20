import MarkdownEngineSyntax
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

@Test func checkboxMarkersAreTheSyntaxTargetsMarkers() {
    #expect(TaskMarker.all.allSatisfy { Checkbox.State(marker: $0) != nil })
    #expect(Checkbox.State(marker: "y") == nil && Checkbox.State(marker: "%") == nil)
}

@Test func aClickSetsTheSyntaxTargetsToggle() {
    for marker in TaskMarker.all { #expect(Checkbox.State(marker: marker)?.markerAfterClick == TaskMarker.toggled(marker)) }
}

@Test func boxOffsetsCountTheSameInEveryReader() throws {
    // The marker's UTF-8 offset in the line, which is also its UTF-16 one: only ASCII comes before it.
    let cases: [(line: String, column: Int)] = [("- [ ] é", 3), ("- [x] \r", 3), (">\t1) [?] 日本", 6), ("-    [ ] a", 6)]
    for (line, column) in cases {
        let bytes = Array(line.utf8)
        let markerEnd = try #require(CheckboxSyntax.markerEnd(in: bytes, at: CheckboxSyntax.markerStart(in: bytes)))
        #expect(CheckboxSyntax.box(in: bytes, after: markerEnd)?.offset == column, "\(line.debugDescription)")
        #expect(BodyScanner.scan(line + "\n").checkboxes.first?.column == column, "\(line.debugDescription)")
        guard case .setMarker(let offset, _)? = Optional(SubtaskLine.edit(for: Substring(line.trimmingCharacters(in: .newlines)))),
              Checkbox.State(marker: Array(line)[column]) != .icon else { continue }
        #expect(offset == column, "\(line.debugDescription)")
    }
    #expect(CheckboxSyntax.box(in: Array("- ".utf8), after: 9) == nil)
}
