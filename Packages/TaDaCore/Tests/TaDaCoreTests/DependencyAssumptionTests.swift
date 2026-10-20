import Testing
import Yams

// Pins down the library behaviour the plan relies on, so a version bump that breaks it fails loudly.

@Test func yamsNodeTreeKeepsDatesAsRawStrings() throws {
    let node = try Yams.compose(yaml: "dueDate: 2026-10-02\ndone: yes\n")
    #expect(node?["dueDate"]?.scalar?.string == "2026-10-02")
    #expect(node?["done"]?.scalar?.string == "yes")
}
