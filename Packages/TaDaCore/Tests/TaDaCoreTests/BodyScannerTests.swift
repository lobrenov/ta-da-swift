import Testing
@testable import TaDaCore

private func markers(_ scan: BodyScan) -> String { String(scan.checkboxes.map(\.marker)) }

@Test func scannerFindsCheckboxesWithLinesAndColumns() {
    let body = "Intro.\n\n- [x] Done\n- [ ] Open\n* [/] Star bullet\n+ [-] Plus bullet\n1. [>] Ordered\n2) [<] Paren\n"
    let scan = BodyScanner.scan(body, firstLineIndex: 10)
    #expect(markers(scan) == "x /-><")
    #expect(scan.checkboxes.map(\.lineIndex) == [12, 13, 14, 15, 16, 17])
    #expect(scan.checkboxes.map(\.column) == [3, 3, 3, 3, 4, 4])
}

@Test func scannerFindsNestedAndQuotedCheckboxes() {
    let body = "- [ ] Parent\n  - [x] Child\n    - [/] Grandchild\n\t- [-] Tab-indented\n- Plain parent\n  1. [ ] Ordered child\n> - [x] Quoted\n> > - [ ] Double quoted\n"
    let scan = BodyScanner.scan(body)
    #expect(markers(scan) == " x/- x ")
    let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
    for box in scan.checkboxes {
        let line = Array(lines[box.lineIndex].utf8)
        #expect(line[box.column] == box.marker.asciiValue, "line \(box.lineIndex)")
        #expect(line[box.column - 1] == UInt8(ascii: "[") && line[box.column + 1] == UInt8(ascii: "]"))
    }
}

@Test func scannerIgnoresChecklistsInCode() {
    let body = """
    ```
    - [ ] fenced
    ```

    ~~~markdown
    - [x] tilde fenced
    ~~~

        - [ ] indented code

    - [ ] Real
      ```
      - [ ] fenced inside an item
      ```
    -     [ ] item starting with indented code
    - `[ ]` inline code

    <div>
    - [ ] html block
    </div>

    """
    #expect(markers(BodyScanner.scan(body)) == " ")
}

@Test func scannerNeedsAKnownMarkerAndASpace() {
    let body = "- [y] Unknown marker\n- [x]NoSpace\n- [ ]\n- [xx] Two\n- [✓] Unicode\n- [x]\tTab after\n- text [ ] later\n-[ ] No space after bullet\n[ ] Not a list\n- [?] Icon\n"
    let scan = BodyScanner.scan(body)
    #expect(markers(scan) == "x?")
    #expect(scan.checkboxes.map(\.lineIndex) == [5, 9])
}

@Test func scannerHandlesCRLF() {
    let body = "Summary line\r\n\r\n- [x] One\r\n  - [ ] Two\r\n\r\nSee [[Link]]\r\n"
    let scan = BodyScanner.scan(body, firstLineIndex: 3)
    #expect(scan.summary == "Summary line")
    #expect(markers(scan) == "x ")
    #expect(scan.checkboxes.map(\.lineIndex) == [5, 6])
    #expect(scan.checkboxes.map(\.column) == [3, 5])
    #expect(scan.links.map(\.target) == ["Link"])
}

@Test func scannerColumnsAreUTF8Offsets() {
    let body = "Ünïcödé 🙂 intro\n\n> - [x] Café ☕️ [[Dan’s site|Dan]]\n"
    let scan = BodyScanner.scan(body)
    #expect(scan.checkboxes.map(\.column) == [5])
    #expect(scan.summary == "Ünïcödé 🙂 intro")
    #expect(scan.links.map(\.target) == ["Dan’s site"])
}

@Test func scannerFindsLinksOutsideCode() {
    let body = """
    # Heading [[In Heading]]

    Text [[A]], [[B|alias]], [[C#Section]], *[[Emphasised]]* and **bold [[Strong]]**.
    Inline `[[Not Code]]` and <span>[[In Span]]</span>?

    - [ ] Item [[In List]]

    | Col |
    | --- |
    | [[In Table]] |

    ```
    [[Not Fenced]]
    ```

    <div>
    [[Not HTML]]
    </div>

    """
    let scan = BodyScanner.scan(body)
    #expect(scan.links.map(\.target) == ["In Heading", "A", "B", "C", "Emphasised", "Strong", "In Span", "In List", "In Table"])
    #expect(scan.links[1].alias == nil && scan.links[2].alias == "alias" && scan.links[3].heading == "Section")
}

@Test func scannerFindsEmbedsApartFromLinks() {
    let body = """
    Before ![[front.jpg]] and [[Kombi]].

    - [ ] Photo ![[odometer.png]]

    `![[Not Code.png]]`

    """
    let scan = BodyScanner.scan(body)
    #expect(scan.links.map(\.target) == ["Kombi"])
    #expect(scan.embeds.map(\.target) == ["front.jpg", "odometer.png"])
}

@Test func targetsAreTheRangesOfEachLinksOrEmbedsTarget() {
    let body = "See [[ Kombi #Plan|the plan]] and ![[front.jpg]].\n\n`[[Code]]` [[Kombi]]\n"
    let links = BodyScanner.linkTargets(in: body)
    #expect(links.map { String(body[$0.range]) } == ["Kombi", "Kombi"])
    #expect(links.map(\.link.heading) == ["Plan", nil] && links[0].link.alias == "the plan")
    let embeds = BodyScanner.embedTargets(in: body)
    #expect(embeds.map { String(body[$0.range]) } == ["front.jpg"])
}

@Test func scannerSummaryIsFirstTopLevelParagraph() {
    #expect(BodyScanner.scan("# Title\n\n- list first\n\nFirst \"quoted\" para\nwraps here.\n\nSecond.\n").summary == "First \"quoted\" para wraps here.")
    #expect(BodyScanner.scan("- [ ] Only a list\n").summary == nil)
    #expect(BodyScanner.scan("").summary == nil)
}

@Test func targetsStayRightAfterABackslashHardBreak() {
    let body = "Note:\\\n`[[Old]]` is the syntax\nsee [[Old]] here\n\n- x\\\n  ![[a.png]] `![[a.png]]`\n  ![[a.png]]\n  [[Old]]\\\n  [[Old]]\n  [[Old]]"
    func edited(_ text: String) -> String {
        Vault.retargetLinks(in: Vault.retargetEmbeds(in: text, from: "attachments/a.png", to: "attachments/b.png", paths: ["attachments/a.png"]),
                            from: "Old", to: "New")
    }
    #expect(BodyScanner.linkTargets(in: body).count == 4)
    #expect(BodyScanner.embedTargets(in: body).count == 2)
    #expect(edited(body) == "Note:\\\n`[[Old]]` is the syntax\nsee [[New]] here\n\n- x\\\n  ![[b.png]] `![[a.png]]`\n  ![[b.png]]\n  [[New]]\\\n  [[New]]\n  [[New]]")
    #expect(edited("a\\\nb\\\n![[a.png]] `![[a.png]]`\n![[a.png]]") == "a\\\nb\\\n![[b.png]] `![[a.png]]`\n![[b.png]]")
}
