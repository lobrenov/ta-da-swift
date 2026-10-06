import Foundation
import Testing
@testable import TaDaCore

struct SourceHighlighterTests {
    private func roles(_ text: String) -> [(String, SourceHighlighter.Role)] {
        let ns = text as NSString
        return SourceHighlighter.runs(in: text).map { (ns.substring(with: $0.range), $0.role) }
    }

    @Test func frontmatterKeysValuesStringsAndDates() {
        let text = "---\ntype: task\ncontexts: [\"@computer\", \"@phone\"]\nproject: \"[[Ta Da MVP]]\" # link\ndueDate: 2026-10-02\ndeadline: 2026-02-30\ntags:\n  - \"a\"\ncompletedDate:\n---\n"
        let found = roles(text)
        #expect(found.contains { $0 == ("---", .punct) })
        #expect(found.contains { $0 == ("type", .key) } && found.contains { $0 == ("task", .value) })
        #expect(found.contains { $0 == ("\"@computer\"", .string) } && found.contains { $0 == ("\"@phone\"", .string) })
        #expect(found.contains { $0 == ("[", .punct) } && found.contains { $0 == (",", .punct) } && found.contains { $0 == ("]", .punct) })
        #expect(found.contains { $0 == ("\"[[Ta Da MVP]]\"", .string) } && found.contains { $0 == (" # link", .punct) })
        #expect(found.contains { $0 == ("2026-10-02", .date) } && found.contains { $0 == ("2026-02-30", .value) }, "a date LocalDate reads")
        #expect(found.contains { $0 == ("  -", .punct) } && found.contains { $0 == ("\"a\"", .string) })
        #expect(found.contains { $0 == ("completedDate", .key) })
        #expect(!found.contains { $0.0.contains("[[") && $0.1 == .link }, "links in frontmatter stay strings")
    }

    @Test func bodyHeadingsCheckboxesAndLinks() {
        let text = "---\ntype: task\n---\n## Subtasks\n- [x] Done thing\n  - [ ] Open [[Ta Da MVP|the MVP]]\n```\n- [ ] in code\n```\nSee [[Note]], not [[#Goals]].\n"
        let found = roles(text)
        #expect(found.contains { $0 == ("## ", .punct) } && found.contains { $0 == ("Subtasks", .heading) })
        #expect(found.contains { $0 == ("- [x] ", .checkDone) } && found.contains { $0 == ("Done thing", .doneText) })
        #expect(found.contains { $0 == ("- [ ] ", .check) })
        #expect(found.contains { $0 == ("Ta Da MVP|the MVP", .link) } && found.contains { $0 == ("[[", .punct) })
        #expect(!found.contains { $0.0.contains("in code") })
        #expect(found.contains { $0 == ("Note", .link) })
        #expect(!found.contains { $0 == ("#Goals", .link) }, "a link WikiLink reads")
    }

    @Test func checkboxesAreColouredExactlyWhenTheyCount() {
        for line in ["- [ ] Open", "  * [x] Done", "1) [?] Icon", "> - [-] Quoted", "-  [ ] Two spaces", "-\t[/] Tab",
                     "- [x]\tTab after", "- [y] Unknown", "- [ ]", "- [x]NoSpace", "-[ ] No space before",
                     "[ ] Not a list", "-     [ ] Indented code"] {
            let coloured = SourceHighlighter.runs(in: line + "\n").contains { $0.role == .check || $0.role == .checkDone }
            #expect(coloured == !BodyScanner.scan(line + "\n").checkboxes.isEmpty, "\(line)")
        }
    }

    @Test func withoutFrontmatterEverythingIsBody() {
        // No opening fence, no closing fence, or an indented one: FrontmatterSplitter finds no frontmatter.
        for text in ["type: task\n---\n# Title\n", "---\ntype: task\n# Title\n", " ---\ntype: task\n---\n# Title\n"] {
            let found = roles(text)
            #expect(!found.contains { $0.1 == .key } && found.contains { $0 == ("Title", .heading) }, "\(text)")
        }
    }

    @Test func fencesMayEndInSpacesAndCRLF() {
        let found = roles("---\r\ntype: task\r\n---  \r\n# Title\r\n")
        #expect(found.contains { $0 == ("type", .key) } && found.contains { $0 == ("---  ", .punct) })
        #expect(found.contains { $0 == ("Title", .heading) })
    }

    @Test func rangesAreUTF16() {
        let text = "---\narea: Café 🙂\ndueDate: 2026-10-02\n---\n"
        #expect(roles(text).contains { $0 == ("2026-10-02", .date) })
        #expect(roles(text).contains { $0 == ("Café 🙂", .value) })
    }
}
