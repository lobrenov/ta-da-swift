import Foundation
#if os(iOS)
import UIKit
#endif
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

/// An embed of an existing file that isn't an image draws a file block.
struct FileBlockTests {
    @Test func onlyAnExistingNonImageEmbedIsAFile() {
        let images = AttachmentImages(root: nil, paths: ["Ta Da/attachments/menu.pdf", "Ta Da/attachments/front.jpg"])
        #expect(images.isFile(for: EmbeddedImageRequest(name: "menu.pdf")))
        #expect(images.isFile(for: EmbeddedImageRequest(name: "Ta Da/attachments/menu.pdf")))
        #expect(!images.isFile(for: EmbeddedImageRequest(name: "front.jpg")))
        #expect(!images.isFile(for: EmbeddedImageRequest(name: "gone.pdf")))
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

/// The editor's chips for a subtask's `>date` and `@[[parent]]`.
struct TaskAttributeChipTests {
    let today = LocalDate("2026-10-02")!

    private func index() -> VaultIndex {
        let files = [
            ("Ta Da/projects/Ta Da MVP.md", "---\ntype: project\nstatus: Doing\n---\n"),
            ("Ta Da/areas/Home.md", "---\ntype: area\n---\n"),
            ("Ta Da/tasks/Plan.md", "---\ntype: task\nstatus: Doing\n---\n"),
        ]
        return VaultIndex(files.compactMap { Item(parsing: $0.1, path: $0.0) })
    }

    @Test @MainActor func datesAreLabelledAsTaskRowsAreAndOverdueOnesTintedDeadline() {
        let theme = Theme.all[0]
        let style = LiveEditor.taskAttributeStyle(theme: theme, index: index(), today: today)
        let due = style.due("2026-10-02")
        #expect(due.label == "Today" && due.tint == theme.accent)
        #expect(style.due("2026-10-04").label == LocalDate("2026-10-04")!.rowLabel(today: today))
        let overdue = style.due("2026-10-01")
        #expect(overdue.label == LocalDate("2026-10-01")!.rowLabel(today: today) && overdue.tint == theme.deadline)
        #expect(style.due("2026-10-09").tint == theme.accent)
    }

    @Test @MainActor func parentsDrawTheirIconInLinkAndUnresolvedOnesStruckAndMuted() {
        let theme = Theme.all[0]
        let style = LiveEditor.taskAttributeStyle(theme: theme, index: index(), today: today)
        for title in ["Ta Da MVP", "Home", "Ta Da MVP#Notes", "Projects/Ta Da MVP"] {
            let chip = style.parent(title, nil)
            #expect(chip.label == (title.hasPrefix("Home") ? "Home" : "Ta Da MVP") && chip.tint == theme.link && !chip.strikethrough
                    && chip.drawIcon != nil, "\(title)")
        }
        for title in ["Nowhere", "Plan"] {
            let chip = style.parent(title, nil)
            #expect(chip.label == title && chip.tint == theme.muted && chip.strikethrough && chip.drawIcon == nil, "\(title): not a project or area")
        }
    }

    @Test @MainActor func theStyleRestylesWhenTheIndexOrTheDayChanges() {
        let theme = Theme.all[0]
        let a = LiveEditor.taskAttributeStyle(theme: theme, index: index(), today: today, generation: 1).fingerprint()
        #expect(a == LiveEditor.taskAttributeStyle(theme: theme, index: index(), today: today, generation: 1).fingerprint())
        #expect(a != LiveEditor.taskAttributeStyle(theme: theme, index: index(), today: today, generation: 2).fingerprint())
        #expect(a != LiveEditor.taskAttributeStyle(theme: theme, index: index(), today: today.adding(days: 1), generation: 1).fingerprint())
    }
}

#if os(iOS)
/// The iPhone editor's body text scales with the text size, and headings, derived from it, keep their ratio.
struct EditorDynamicTypeTests {
    private func size(_ category: UIContentSizeCategory) -> CGFloat {
        LiveEditor.scaledBodySize(in: UITraitCollection(preferredContentSizeCategory: category))
    }

    @Test func bodyIs17AtTheDefaultSizeAndGrowsWithoutACap() {
        #expect(size(.large) == 17)
        #expect(size(.accessibilityExtraExtraExtraLarge) > size(.extraExtraExtraLarge))
        #expect(size(.accessibilityExtraExtraExtraLarge) > 17)
        #expect(size(.extraSmall) < 17)
    }

    @Test func headingsKeepTheirRatioToTheBody() {
        let headings = MarkdownEditorConfiguration.default.headings
        for level in 1...6 {
            let ratio = headings.fontMultiplier(for: level)
            #expect(abs(size(.large) * ratio / size(.large) - ratio) < 0.001)
            #expect(abs(size(.accessibilityExtraExtraExtraLarge) * ratio / size(.accessibilityExtraExtraExtraLarge) - ratio) < 0.001)
        }
        #expect(size(.accessibilityExtraExtraExtraLarge) * headings.fontMultiplier(for: 1) > size(.large) * headings.fontMultiplier(for: 1))
    }
}
#endif
