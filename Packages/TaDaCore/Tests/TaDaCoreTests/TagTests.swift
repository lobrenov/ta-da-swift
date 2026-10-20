import Testing
@testable import TaDaCore

@Test func tagMatchesIgnoringCaseAndKeepsItsSpelling() throws {
    let tag = try #require(Tag("Errands"))
    #expect(tag.name == "Errands" && tag.path == "errands")
    #expect(Tag("#errands")?.path == tag.path)
}

@Test func tagDropsHashAndEmptySegments() {
    #expect(Tag("home/")?.name == "home")
    #expect(Tag("#home//garden/")?.name == "home/garden")
    #expect(Tag(" quick win ")?.name == "quick win")
    #expect(Tag("") == nil && Tag("#") == nil && Tag("/") == nil && Tag("  ") == nil)
}

@Test func tagNestsBySlash() throws {
    let tag = try #require(Tag("People/Max/Work"))
    #expect(tag.segments == ["People", "Max", "Work"] && tag.leaf == "Work")
    #expect(tag.parent?.name == "People/Max" && tag.parent?.parent?.name == "People")
    #expect(tag.parent?.parent?.parent == nil)
    let people = try #require(Tag("people"))
    #expect(people.isAncestor(of: tag) && tag.parent!.isAncestor(of: tag))
    #expect(!tag.isAncestor(of: tag) && !tag.isAncestor(of: people))
    #expect(!people.isAncestor(of: Tag("peoplex/a")!))
}

/// The canvas's TagModel edge cases for inline tags: what's written, and the tags read.
@Test(arguments: [
    ("#home/garden, #fish", ["home/garden", "fish"]),
    ("#errands.", ["errands"]),
    ("#quick win", ["quick"]),
    ("#Errands", ["Errands"]),
    ("#home/", ["home"]),
    ("# Heading", []),
    ("#2026", []),
    ("#2026/", []),
    ("`#errands`", []),
    ("example.com/#top", []),
    ("[[Sell the Kombi#Plan]]", []),
])
func inlineTagEdgeCases(_ written: String, _ tags: [String]) {
    #expect(BodyScanner.scan(written).tags.map(\.name) == tags)
}

@Test func aTagNeedsACharacterThatIsNeitherADigitNorASlash() {
    #expect(BodyScanner.scan("#2026/10 #2026/q4\n").tags.map(\.name) == ["2026/q4"])
}
