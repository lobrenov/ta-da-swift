import Testing
@testable import TaDaCore

@Test func splitterSeparatesFrontmatterFromBody() {
    let text = "---\ntype: task\nstatus: Doing\n---\nBody line\n"
    let split = FrontmatterSplitter.split(text)
    #expect(split.yaml == "type: task\nstatus: Doing\n")
    #expect(split.block == "---\ntype: task\nstatus: Doing\n---\n")
    #expect(split.body == "Body line\n")
    #expect(split.bodyFirstLineIndex == 4)
}

@Test(arguments: [
    "---\ntype: task\n---\nBody\n",
    "---\r\ntype: task\r\n---\r\n\r\nBody\r\n",
    "---  \ntype: task\n--- \t\nBody",
    "---\n---\n",
    "---\ntype: task\n---",
    "No frontmatter\n---\ntype: task\n---\n",
    "---\ntype: task\nnever closed\n",
    "",
    "--- \u{1F600}\n",
])
func splitterKeepsEveryByte(_ text: String) {
    let split = FrontmatterSplitter.split(text)
    #expect(split.block + split.body == text)
}

@Test func splitterHandlesCRLF() {
    let split = FrontmatterSplitter.split("---\r\ntype: task\r\n---\r\nBody\r\n")
    #expect(split.yaml == "type: task\r\n")
    #expect(split.body == "Body\r\n")
    #expect(split.bodyFirstLineIndex == 3)
}

@Test func splitterAllowsEmptyFrontmatterAndBody() {
    let empty = FrontmatterSplitter.split("---\n---\n")
    #expect(empty.yaml == "")
    #expect(empty.body == "")
    #expect(empty.bodyFirstLineIndex == 2)

    let noNewline = FrontmatterSplitter.split("---\ntype: task\n---")
    #expect(noNewline.yaml == "type: task\n")
    #expect(noNewline.body == "")
}

@Test func splitterNeedsFenceOnFirstLineAndAClosingFence() {
    for text in ["\n---\ntype: task\n---\n", "Title\n---\ntype: task\n---\n", "---\ntype: task\n", " ---\ntype: task\n---\n", "----\ntype: task\n----\n"] {
        let split = FrontmatterSplitter.split(text)
        #expect(split.yaml == nil, "\(text.debugDescription)")
        #expect(split.body == text)
        #expect(split.bodyFirstLineIndex == 0)
    }
}

@Test func splitterStopsAtFirstClosingFence() {
    let split = FrontmatterSplitter.split("---\ntype: task\n---\nBody\n\n---\n\nMore\n")
    #expect(split.yaml == "type: task\n")
    #expect(split.body == "Body\n\n---\n\nMore\n")
}
