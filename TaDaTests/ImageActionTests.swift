import Foundation
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct ImageActionTests {
    let folder: TestFolder

    init() throws {
        folder = try TestFolder([
            "Ta Da/tasks/Photograph the Kombi.md": "---\ntype: task\nstatus: Doing\n---\nShots:\n\n![[front.jpg]]\n",
            "Ta Da/tasks/Kombi service history.md": "---\ntype: task\nstatus: Done\n---\n![[front.jpg|320]] and ![[Ta Da/attachments/front.jpg]]\n",
            "Ta Da/tasks/Other.md": "---\ntype: task\n---\n![[notes/front.jpg]]\n",
            "Ta Da/attachments/front.jpg": "x",
            "notes/front.jpg": "y",
        ])
    }

    @Test func anImagesEmbeddersListTheOpenFileFirst() async {
        let model = await folder.model(selecting: "Ta Da/tasks/Photograph the Kombi.md")
        let path = try? #require(model.attachmentPath(forEmbed: "front.jpg"))
        #expect(path == "Ta Da/attachments/front.jpg")
        #expect(model.embedders(ofAttachment: "Ta Da/attachments/front.jpg").map { "\($0.item.title) \($0.count)" }
                == ["Photograph the Kombi 1", "Kombi service history 2"])
    }

    @Test func renamingAnImageRetargetsItsEmbedsTheOpenFileInPlace() async throws {
        let model = await folder.model(selecting: "Ta Da/tasks/Photograph the Kombi.md")
        await model.renameAttachment("Ta Da/attachments/front.jpg", to: "Front side")
        #expect(model.errorMessage == nil)
        #expect(model.attachments.contains("Ta Da/attachments/Front side.jpg") && !model.attachments.contains("Ta Da/attachments/front.jpg"))
        #expect(model.document?.text == "---\ntype: task\nstatus: Doing\n---\nShots:\n\n![[Front side.jpg]]\n")
        #expect(try folder.read("Ta Da/tasks/Kombi service history.md")
                == "---\ntype: task\nstatus: Done\n---\n![[Front side.jpg|320]] and ![[Ta Da/attachments/Front side.jpg]]\n")
        #expect(try folder.read("Ta Da/tasks/Other.md") == "---\ntype: task\n---\n![[notes/front.jpg]]\n")
        #expect(model.index["Ta Da/tasks/Kombi service history.md"]?.embeds.first?.target == "Front side.jpg")
    }

    @Test func renamingToAnotherImagesNameIsRefused() async throws {
        let model = await folder.model(selecting: "Ta Da/tasks/Photograph the Kombi.md")
        await model.renameAttachment("notes/front.jpg", to: "Front")
        #expect(model.errorMessage != nil)
        #expect(try folder.read("Ta Da/tasks/Other.md") == "---\ntype: task\n---\n![[notes/front.jpg]]\n")
    }

    @Test func deletingAnImageTrashesItAloneAndListsIt() async throws {
        try FileManager.default.removeItem(at: folder.url.appending(path: "notes/front.jpg"))
        let model = await folder.model(selecting: "Ta Da/tasks/Photograph the Kombi.md")
        await model.trashAttachment("Ta Da/attachments/front.jpg")
        #expect(!model.attachments.contains("Ta Da/attachments/front.jpg"))
        #expect(model.looseTrashedAttachments.map(\.path) == [".trash/attachments/front.jpg"])
        #expect(model.document?.text.contains("![[front.jpg]]") == true, "its embeds stay")
        let trashed = try #require(model.trashedAttachments.first)
        #expect(model.embeddersSummary(of: trashed) == "In Kombi service history, Other, Photograph the Kombi")
        await model.restore([trashed.path])
        #expect(model.attachments.contains("Ta Da/attachments/front.jpg") && model.trashedAttachments.isEmpty)
    }
}
