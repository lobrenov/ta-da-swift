import Markdown
import Testing
import Yams

// Pins down the two library behaviours the plan relies on, so a version bump that breaks them fails loudly.

@Test func swiftMarkdownExposesTaskListCheckboxes() {
    let document = Document(parsing: "- [x] done\n- [ ] open\n")
    let items = document.children
        .compactMap { $0 as? UnorderedList }
        .flatMap { Array($0.listItems) }
    #expect(items.map(\.checkbox) == [.checked, .unchecked])
}

@Test func yamsNodeTreeKeepsDatesAsRawStrings() throws {
    let node = try Yams.compose(yaml: "dueDate: 2026-10-02\ndone: yes\n")
    #expect(node?["dueDate"]?.scalar?.string == "2026-10-02")
    #expect(node?["done"]?.scalar?.string == "yes")
}
