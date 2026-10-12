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
        let taken = model.quickEntryTakenNames()
        for (draft, expected) in cases {
            #expect(AppModel.quickEntryPath(for: draft, taken: taken) == expected)
        }
        for (draft, expected) in cases.prefix(1) + cases.dropFirst(2) {
            #expect(await model.create(draft) == expected)
        }
    }

    @Test func thePickersEditTheDraftAndWriteNothing() async throws {
        let model = await folder.model()
        let before = try FileManager.default.contentsOfDirectory(atPath: folder.url.appending(path: "tasks").path)
        let path = AppModel.quickEntryDraftPath
        let project = try #require(model.index["projects/Ta Da MVP.md"]), area = try #require(model.index["areas/Personal.md"])

        await model.setStatus(.done, in: path)
        await model.setParent(project, of: [path])
        await model.setDate(.due, to: LocalDate("2026-10-14"), of: [path])
        await model.setDate(.deadline, to: LocalDate("2026-10-20"), of: [path])
        await model.addTag(Tag("venues")!, to: path)
        await model.addTag(Tag("Venues")!, to: path)
        await model.addTag(Tag("people/bea")!, to: path)
        await model.removeTag(Tag("VENUES")!, from: path)
        var expected = QuickEntryDraft()
        expected.status = .done
        expected.parent = .project("Ta Da MVP")
        expected.dueDate = LocalDate("2026-10-14")
        expected.deadline = LocalDate("2026-10-20")
        expected.tags = [Tag("people/bea")!]
        #expect(model.quickEntryDraft == expected)
        #expect(model.item(at: path)?.properties.project?.title == "Ta Da MVP")
        #expect(model.item(at: path)?.tags.map(\.tag.name) == ["people/bea"])

        await model.setParent(area, of: [path])
        #expect(model.quickEntryDraft.parent == .area("Personal"))
        model.quickEntryDraft = model.quickEntryDraft.changingKind(to: .project)
        await model.setParent(project, of: [path])
        #expect(model.quickEntryDraft.parent == .area("Personal"), "a project goes only under an area")
        await model.setParent(nil, of: [path])
        #expect(model.quickEntryDraft.parent == nil)

        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.appending(path: "tasks").path) == before)
        #expect(model.index[path] == nil)
    }

    @Test func theDraftsTagMenuListsAdded() {
        var item = QuickEntryDraft()
        item.tags = [Tag("venues")!]
        let draft = Item(parsing: item.text(today: LocalDate("2026-10-12")!), path: AppModel.quickEntryDraftPath)!
        let menu = TagChoice.menu(item: draft, tree: [], query: "", ownLabel: "Added")
        #expect(menu.sections.map(\.label) == ["Added"])
        #expect(TagChoice.menu(item: draft, tree: [], query: "garden", ownLabel: "Added").sections.first?.items.first?.title == "Create #garden")
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

@MainActor @Suite(.keyWindow)
struct QuickEntryPanelTests {
    /// Waits up to 3 s for `condition`.
    private func within(_ condition: () -> Bool) async -> Bool {
        let end = ContinuousClock.now + .seconds(3)
        while !condition() {
            guard ContinuousClock.now < end else { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    @Test func opensAFloatingPanelOnEverySpaceAndCreatesFromIt() async throws {
        let folder = try TestFolder(["projects/Ta Da MVP.md": "---\ntype: project\nstatus: Doing\n---\n"])
        let model = await folder.model()
        let quickEntry = QuickEntryPanel(model: model)
        quickEntry.open()
        let panel = try #require(quickEntry.panel)
        #expect(panel.level == .floating && panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces) && panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.frame.width == 560)

        quickEntry.toggle()
        #expect(!quickEntry.isOpen && !panel.isVisible)

        quickEntry.open()
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                   windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}",
                                                   charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        try await Task.sleep(for: .milliseconds(400))
        #expect(panel.performKeyEquivalent(with: escape))
        #expect(!quickEntry.isOpen)

        quickEntry.open()
        func press(_ key: String, _ flags: NSEvent.ModifierFlags, code: UInt16) throws -> Bool {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                                      windowNumber: panel.windowNumber, context: nil, characters: key,
                                                      charactersIgnoringModifiers: key, isARepeat: false, keyCode: code))
            return panel.performKeyEquivalent(with: event)
        }
        try await Task.sleep(for: .milliseconds(400))
        #expect(try press("s", .command, code: 1))
        #expect(await within { PropertyPicker.shared.isOpen(AppModel.quickEntryDraftPath, "dueDate") })
        PropertyPicker.shared.close()
        try await Task.sleep(for: .milliseconds(200))
        #expect(try press("m", [.command, .shift], code: 46))
        #expect(await within { PropertyPicker.shared.isOpen(AppModel.quickEntryDraftPath, "project") })
        #expect(quickEntry.isOpen)
        quickEntry.close()
        #expect(PropertyPicker.shared.isOpen(AppModel.quickEntryDraftPath, "project") == false)

        quickEntry.open()
        var draft = QuickEntryDraft()
        draft.title = "Book venue"
        draft.parent = .project("Ta Da MVP")
        quickEntry.create(draft, opening: false)
        #expect(!quickEntry.isOpen)
        #expect(await within { model.index["tasks/Book venue.md"] != nil })
        #expect(try folder.read("tasks/Book venue.md") == draft.text(today: model.today))
    }
}
