import Testing
@testable import TaDaCore

@Test func wikiLinkParsesTargetHeadingAndAlias() throws {
    let plain = try #require(WikiLink("[[Ta Da MVP]]"))
    #expect(plain.target == "Ta Da MVP" && plain.heading == nil && plain.alias == nil)

    let aliased = try #require(WikiLink("[[Ta Da MVP|the app]]"))
    #expect(aliased.target == "Ta Da MVP" && aliased.alias == "the app")

    let heading = try #require(WikiLink("[[Ta Da MVP#Goals]]"))
    #expect(heading.target == "Ta Da MVP" && heading.heading == "Goals")

    let both = try #require(WikiLink("[[projects/Ta Da MVP#Goals|goals]]"))
    #expect(both.target == "projects/Ta Da MVP" && both.heading == "Goals" && both.alias == "goals")
    #expect(both.title == "Ta Da MVP")
}

@Test func wikiLinkTitleDropsFolderAndExtension() throws {
    #expect(try #require(WikiLink("[[a/b/Café.md]]")).title == "Café")
    #expect(try #require(WikiLink("[[ Spaced ]]")).title == "Spaced")
}

@Test func wikiLinkRejectsNonLinks() {
    #expect(WikiLink("Ta Da MVP") == nil)
    #expect(WikiLink("[[Ta Da MVP]] and more") == nil)
    #expect(WikiLink("[Ta Da MVP]") == nil)
    #expect(WikiLink("[[]]") == nil)
    #expect(WikiLink("[[#Heading only]]") == nil)
}

@Test func wikiLinkScanFindsEveryLink() {
    let links = WikiLink.scan("See [[A]], [[B|bee]] and [[C#h]]; not [single] or [[broken\nlink]] 🙂 [[Dan’s]]")
    #expect(links.map(\.target) == ["A", "B", "C", "Dan’s"])
}
