import Foundation
import MarkdownEngine
import TaDaCore
import Testing
@testable import TaDa

/// The live editor draws a link as resolved when its title, read as the core reads it, names a file.
struct LiveEditorTests {
    @Test func linksResolveByTheirTitleAsTheCoreReadsIt() {
        let resolver = TitleResolver(titles: ["ta da mvp"])
        for target in ["Ta Da MVP", "ta da mvp", "Ta Da MVP.md", "projects/Ta Da MVP.md", "Ta Da MVP#Goals", " Ta Da MVP "] {
            #expect(resolver.resolve(displayName: target, range: NSRange()) != nil, "\(target)")
        }
        for target in ["Ta Da", "#Goals", "Ta Da MVP.txt"] {
            #expect(resolver.resolve(displayName: target, range: NSRange()) == nil, "\(target)")
        }
    }
}

/// A link to a task draws that task's status box.
struct LinkMarkerTests {
    private func index() -> VaultIndex {
        func item(_ path: String, _ kind: Item.Kind, _ status: Status = .notStarted) -> Item {
            let type = kind == .note ? "" : "type: \(kind.rawValue)\n"
            return Item(parsing: "---\n\(type)status: \(status.rawValue)\n---\n", path: path)!
        }
        return VaultIndex([
            item("Ta Da/tasks/A.md", .task, .doing), item("Ta Da/tasks/B.md", .task, .ongoing),
            item("Ta Da/tasks/C.md", .task, .blocked), item("Ta Da/tasks/D.md", .task, .done),
            item("Ta Da/tasks/E.md", .task, .cancelled), item("Ta Da/tasks/F.md", .task),
            item("Ta Da/projects/P.md", .project), item("Ta Da/areas/Z.md", .area), item("Notes/N.md", .note),
            item("Ta Da/logbook/L.md", .task, .done),
        ])
    }

    private func marker(_ target: String, in index: VaultIndex) -> Character? {
        TitleResolver(titles: index.titles, statuses: index.taskStatuses)
            .resolve(displayName: target, range: NSRange())?.marker
    }

    @Test func taskLinksCarryTheirStatusMarker() {
        let index = index()
        let expected: [(String, Character)] = [("A", "/"), ("b", ">"), ("C", "B"), ("D", "x"), ("E", "-"), ("F", " "), ("L", "x")]
        for (target, marker) in expected { #expect(self.marker(target, in: index) == marker, "\(target)") }
    }

    @Test func aliasedPathQualifiedLinksCarryTheMarker() {
        #expect(marker("tasks/A#Goals|alias", in: index()) == "/")
    }

    @Test func otherLinksCarryNoMarker() {
        let index = index()
        for target in ["P", "Z", "N"] { #expect(marker(target, in: index) == nil, "\(target)") }
        #expect(TitleResolver(titles: index.titles).resolve(displayName: "P", range: NSRange()) != nil)
    }

    @Test func fingerprintChangesWithStatus() {
        var index = index()
        let before = TitleResolver(titles: index.titles, statuses: index.taskStatuses).fingerprint()
        var task = index["Ta Da/tasks/A.md"]!
        task.properties.status = .done
        index.update(task)
        let after = TitleResolver(titles: index.titles, statuses: index.taskStatuses).fingerprint()
        #expect(before != after)
    }
}
