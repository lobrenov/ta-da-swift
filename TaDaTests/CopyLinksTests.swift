#if os(macOS)
import Testing
@testable import TaDa

@MainActor
struct CopyLinksTests {
    private let list = ["Ta Da/tasks/One.md", "Ta Da/tasks/Two.md", "Notes/Three.md"]

    @Test func oneFileCopiesItsLink() {
        #expect(ListKeyView.linkText(picked: ["Ta Da/tasks/Two.md"], inOrder: list) == "[[Two]]")
    }

    @Test func severalFilesCopyOnePerLineInListOrder() {
        let text = ListKeyView.linkText(picked: ["Notes/Three.md", "Ta Da/tasks/One.md"], inOrder: list)
        #expect(text == "[[One]]\n[[Three]]")
    }

    @Test func aNoteCopiesItsLink() {
        #expect(ListKeyView.linkText(picked: ["Notes/Three.md"], inOrder: list) == "[[Three]]")
    }

    @Test func nothingPickedCopiesNothing() {
        #expect(ListKeyView.linkText(picked: [], inOrder: list).isEmpty)
    }
}
#endif
