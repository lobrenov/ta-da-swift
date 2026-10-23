import Foundation
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct AttachmentsModelTests {
    let folder: TestFolder

    init() throws {
        folder = try TestFolder([
            "Ta Da/tasks/Photograph the Kombi.md": "---\ntype: task\nstatus: Doing\n---\n![[front.jpg]]\n",
            "Ta Da/attachments/front.jpg": "x",
            "Ta Da/attachments/old.png": "y",
            "Ta Da/attachments/older.png": "z",
        ])
    }

    @Test func theListGroupsImagesByUseAndTheSelectionFollowsClicks() async {
        let model = await folder.model()
        model.show(.attachments)
        #expect(model.attachmentGroups.candidates.map(\.attachment.name) == ["old.png", "older.png"])
        #expect(model.attachmentGroups.inUse.map(\.attachment.name) == ["front.jpg"])
        model.selectOnly("Ta Da/attachments/old.png")
        #expect(model.isSelected("Ta Da/attachments/old.png") && model.selection == nil)
        model.selectAllAttachments()
        #expect(model.attachmentSelection.count == 3 && model.picked.count == 3)
    }

    @Test func movingUnusedImagesGoesStraightToTrashAndNotesIt() async throws {
        let model = await folder.model()
        model.show(.attachments)
        model.attachmentSelection = ["Ta Da/attachments/old.png", "Ta Da/attachments/older.png"]
        await model.moveAttachmentsToTrash(model.attachmentSelection)
        #expect(model.imageDialog == nil)
        #expect(model.attachmentNote == "2 attachments moved to Trash.")
        #expect(model.attachmentGroups.candidates.isEmpty && model.attachmentSelection.isEmpty)
        #expect(model.trashedAttachments.count == 2)
    }

    @Test func movingAnImageAnOpenFileEmbedsAsksFirst() async {
        let model = await folder.model()
        model.show(.attachments)
        let both: Set = ["Ta Da/attachments/front.jpg", "Ta Da/attachments/old.png"]
        await model.moveAttachmentsToTrash(both)
        #expect(model.imageDialog == .deleteSeveral(both.sorted()))
        await model.moveAttachmentsToTrash(["Ta Da/attachments/front.jpg"])
        #expect(model.imageDialog == .delete("Ta Da/attachments/front.jpg"))
        #expect(model.attachmentGroups.inUse.count == 1, "nothing moved")
    }

    @Test func movingAnImageWhoseUseIsUnknownAsksFirst() async {
        let model = await folder.model()
        model.show(.attachments)
        await model.moveAttachmentsToTrash(["Ta Da/attachments/missing.png"])
        #expect(model.imageDialog == .delete("Ta Da/attachments/missing.png"))
    }

    @Test func renamingPublishesTheRename() async {
        let model = await folder.model()
        await model.renameAttachment("Ta Da/attachments/front.jpg", to: "Front")
        #expect(model.renamedAttachment == .init(from: "Ta Da/attachments/front.jpg", to: "Ta Da/attachments/Front.jpg"))
    }

    @Test func renamingAnImageKeepsItPicked() async {
        let model = await folder.model()
        model.show(.attachments)
        model.attachmentSelection = ["Ta Da/attachments/front.jpg"]
        await model.renameAttachment("Ta Da/attachments/front.jpg", to: "Front")
        #expect(model.attachmentSelection == ["Ta Da/attachments/Front.jpg"])
        #expect(model.attachmentGroups.inUse.map(\.attachment.name) == ["Front.jpg"])
    }
}
