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
    let found = WikiLink.scan("See [[A]], [[B|bee]] and [[C#h]]; not [single] or [[broken\nlink]] 🙂 [[Dan’s]]")
    #expect(found.links.map(\.target) == ["A", "B", "C", "Dan’s"] && found.embeds.isEmpty)
}

@Test func wikiLinkScanSeparatesEmbeds() {
    let found = WikiLink.scan("![[front.jpg]] beside [[Kombi]], then![[img/odometer.PNG|300]] and ![[Note]]")
    #expect(found.links.map(\.target) == ["Kombi"])
    #expect(found.embeds.map(\.target) == ["front.jpg", "img/odometer.PNG", "Note"])
    #expect(found.embeds.map(\.attachmentName) == ["front.jpg", "odometer.PNG", nil])
}

@Test func attachmentNameNeedsAnImageExtension() throws {
    #expect(try #require(WikiLink("[[Pasted image 20260930101522.png]]")).attachmentName == "Pasted image 20260930101522.png")
    #expect(try #require(WikiLink("[[report.pdf]]")).attachmentName == nil)
    #expect(try #require(WikiLink("[[Version 1.2]]")).attachmentName == nil)
    #expect(try #require(WikiLink("[[.png]]")).attachmentName == ".png")
}

@Test func retargetingLinksKeepsTheirFolderHeadingAndAliasAndSkipsEmbedsAndCode() {
    let text = """
    ---
    project: "[[Sell the Kombi]]"
    ---
    See [[sell the kombi]], [[projects/Sell the Kombi.md#Plan|the plan]] and [[Sell the Kombi list]].
    ![[Sell the Kombi.png]] `[[Sell the Kombi]]`

    ```
    [[Sell the Kombi]]
    ```

    """
    let expected = """
    ---
    project: "[[Sell the Kombi]]"
    ---
    See [[Sell the car]], [[projects/Sell the car.md#Plan|the plan]] and [[Sell the Kombi list]].
    ![[Sell the Kombi.png]] `[[Sell the Kombi]]`

    ```
    [[Sell the Kombi]]
    ```

    """
    #expect(Vault.retargetLinks(in: text, from: "Sell the Kombi", to: "Sell the car") == expected)
    #expect(BodyScanner.linkTargets(in: "[[A]] ![[b.png]] [[ C |c]]").map(\.link.target) == ["A", "C"])
}
