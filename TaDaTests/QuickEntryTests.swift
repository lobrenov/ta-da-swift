import AppKit
import Foundation
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct QuickEntryTests {
    let folder: TestFolder

    init() throws {
        folder = try TestFolder([
            "projects/Ta Da MVP.md": "---\ntype: project\nstatus: Doing\n---\n",
            "areas/Personal.md": "---\ntype: area\n---\n",
            "tasks/Call Bea.md": "---\ntype: task\nstatus: Not Started\n---\n",
            "tasks/Notes.md": "Not a Ta Da file\n",
            ".logbook/2026-09/Shipped.md": "---\ntype: project\nstatus: Done\ncompletedDate: 2026-09-30\n---\n",
        ])
    }

    private func draft(_ kind: Item.Kind, _ title: String) -> QuickEntryDraft {
        var draft = QuickEntryDraft().changingKind(to: kind)
        draft.title = title
        return draft
    }

    @Test func createsEachKindWithEveryField() async throws {
        let model = await folder.model()
        var task = draft(.task, "Book venue")
        task.parent = .project("Ta Da MVP")
        task.status = .doing
        task.dueDate = LocalDate("2026-10-14")
        task.deadline = LocalDate("2026-10-20")
        task.tags = [Tag("gamejams/venues")!]
        var project = draft(.project, "Garden")
        project.parent = .area("Personal")
        project.tags = [Tag("home/garden")!]
        var area = draft(.area, "Wellbeing")
        area.tags = [Tag("wellbeing")!]

        for draft in [task, project, area] {
            let path = try #require(await model.create(draft))
            #expect(path == "\(draft.folder)/\(draft.title).md")
            #expect(try folder.read(path) == draft.text(today: model.today))
            #expect(model.index[path]?.properties.tags == draft.tags)
        }
        #expect(model.index["tasks/Book venue.md"]?.properties.project?.title == "Ta Da MVP")
        #expect(model.projects.first { $0.project.title == "Ta Da MVP" }?.total == 1)
    }

    @Test func aTakenNameIsNumberedAsThePathSays() async throws {
        let model = await folder.model()
        let cases = [(draft(.task, "Call Bea"), "tasks/Call Bea 2.md"),
                     (draft(.task, "call bea"), "tasks/call bea 2.md"),
                     (draft(.project, "Ta Da MVP"), "projects/Ta Da MVP 2.md"),
                     (draft(.project, "Shipped"), "projects/Shipped 2.md"),
                     (draft(.area, "Personal"), "areas/Personal 2.md"),
                     (draft(.task, "Notes"), "tasks/Notes 2.md"),
                     (draft(.task, "New: plan"), "tasks/New - plan.md")]
        for (draft, expected) in cases {
            #expect(model.quickEntryPath(for: draft) == expected)
        }
        for (draft, expected) in cases.prefix(1) + cases.dropFirst(2) {
            #expect(await model.create(draft) == expected)
        }
    }

    @Test func theHotkeyDefaultsToControlSpaceAndSurvivesARelaunch() {
        let first = AppModel(defaults: folder.defaults)
        #expect(first.quickEntryHotkey == .quickEntryDefault && first.quickEntryHotkey?.displayString == "⌃Space")

        let chord = Hotkey(keyCode: 40, modifiers: Hotkey.option | Hotkey.command | Hotkey.shift, key: "K")
        first.quickEntryHotkey = chord
        #expect(AppModel(defaults: folder.defaults).quickEntryHotkey == chord)
        #expect(chord.displayString == "⌥⇧⌘K" && chord.spokenString == "Option Shift Command K")
        #expect(Hotkey(chord.dictionary) == chord)
        #expect(Hotkey(["keyCode": 49]) == nil && Hotkey(["keyCode": "x", "modifiers": 4096, "key": "Space"]) == nil)

        first.quickEntryHotkey = nil
        #expect(AppModel(defaults: folder.defaults).quickEntryHotkey == nil)
    }

    @Test func aKeyPressRecordsAChordWithControlOptionOrCommand() throws {
        func press(_ keyCode: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags) throws -> Hotkey? {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                                      windowNumber: 0, context: nil, characters: characters,
                                                      charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
            return Hotkey(event)
        }
        #expect(try press(49, " ", .control) == .quickEntryDefault)
        #expect(try press(40, "k", [.option, .shift, .command])?.displayString == "⌥⇧⌘K")
        #expect(try press(122, "\u{F704}", .command)?.displayString == "⌘F1")
        #expect(try press(40, "K", .shift) == nil)
        #expect(try press(40, "k", []) == nil)
    }
}
