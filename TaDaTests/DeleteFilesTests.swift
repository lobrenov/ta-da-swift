import Foundation
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct DeleteFilesTests {
    let folder: TestFolder

    init() throws {
        folder = try TestFolder([
            "Ta Da/projects/Sell the Kombi.md": "---\ntype: project\n---\n![[kombi-rego.jpg]]\n",
            "Ta Da/tasks/Photograph the Kombi.md": "---\ntype: task\nproject: \"[[Sell the Kombi]]\"\n---\n![[front.jpg]] ![[interior.jpg]]\n![[odometer.png]] ![[front.jpg]]\n",
            "Ta Da/tasks/List the Kombi.md": "---\ntype: task\nproject: \"[[Sell the Kombi]]\"\n---\n![[front.jpg]] ![[carsales-ad.png]]\n",
            "Ta Da/tasks/Kombi service history.md": "---\ntype: task\n---\n![[odometer.png]]\n",
            "Ta Da/tasks/Plain.md": "---\ntype: task\n---\nNo images.\n",
            "Ta Da/attachments/kombi-rego.jpg": "a", "Ta Da/attachments/front.jpg": "b", "Ta Da/attachments/interior.jpg": "c",
            "Ta Da/attachments/odometer.png": "d", "Ta Da/attachments/carsales-ad.png": "e",
        ])
    }

    private typealias Image = AppModel.TrashImage

    @Test func deletingATaskThatEmbedsImagesListsThemFirst() async throws {
        let model = await folder.model()
        #expect(model.asksBeforeTrashing(["Ta Da/tasks/Photograph the Kombi.md"]))
        await model.moveToTrash(["Ta Da/tasks/Photograph the Kombi.md"])
        let request = try #require(model.trashConfirmation)
        #expect(model.index["Ta Da/tasks/Photograph the Kombi.md"] != nil)
        #expect(request.images.map(\.item.title) == ["Photograph the Kombi"])
        #expect(request.images.first?.images == [
            Image(path: "Ta Da/attachments/front.jpg", keptIn: ["List the Kombi"], goingIn: []),
            Image(path: "Ta Da/attachments/interior.jpg", keptIn: [], goingIn: []),
            Image(path: "Ta Da/attachments/odometer.png", keptIn: ["Kombi service history"], goingIn: []),
        ])
        let text = TrashConfirmationText(model: model)
        #expect(text.subject == "“Photograph the Kombi”")
        #expect(text.imagesSummary(ticked: 1, phone: false) == "1 file and 1 of 3 attachments go to Trash. Restore brings them back together.")
        #expect(TrashConfirmationText.note(for: request.images[0].images[0], ticked: true, phone: false)
                == ("Also in ", "List the Kombi", ", which will show it as broken"))
    }

    @Test func confirmingTrashesTheTickedImagesWithTheFileAndRestoresThemTogether() async throws {
        let model = await folder.model()
        await model.moveToTrash(["Ta Da/tasks/Photograph the Kombi.md"])
        let request = try #require(model.trashConfirmation)
        model.trashConfirmation = nil
        await model.confirmTrash(request, images: ["Ta Da/attachments/interior.jpg"])
        #expect(model.index["Ta Da/tasks/Photograph the Kombi.md"] == nil)
        #expect(!model.attachments.contains("Ta Da/attachments/interior.jpg") && model.attachments.contains("Ta Da/attachments/front.jpg"))
        #expect(model.trashedAttachmentsByFile[".trash/Photograph the Kombi.md"]?.map(\.path) == [".trash/attachments/interior.jpg"])
        #expect(model.looseTrashedAttachments.isEmpty && model.trashCount == 2)

        await model.restore([".trash/Photograph the Kombi.md"])
        #expect(model.index["Ta Da/tasks/Photograph the Kombi.md"] != nil && model.attachments.contains("Ta Da/attachments/interior.jpg"))
        #expect(model.trashCount == 0)
    }

    @Test func anImageThatWontMoveDoesntUndoTheFilesThatDid() async throws {
        let model = await folder.model()
        await model.moveToTrash(["Ta Da/tasks/Photograph the Kombi.md"], confirmed: true, images: ["Ta Da/attachments/gone.jpg"])
        #expect(model.index["Ta Da/tasks/Photograph the Kombi.md"] == nil && model.trash.map(\.id) == [".trash/Photograph the Kombi.md"])
        #expect(model.errorMessage?.contains("move the images to the trash") == true)
    }

    @Test func aProjectListsEachImageUnderTheFirstFileThatEmbedsIt() async throws {
        let model = await folder.model()
        await model.moveToTrash(["Ta Da/projects/Sell the Kombi.md"])
        let request = try #require(model.trashConfirmation)
        #expect(request.count == 3)
        #expect(request.images.map(\.item.title) == ["Sell the Kombi", "List the Kombi", "Photograph the Kombi"])
        #expect(request.images[1].images == [
            Image(path: "Ta Da/attachments/front.jpg", keptIn: [], goingIn: ["Photograph the Kombi"]),
            Image(path: "Ta Da/attachments/carsales-ad.png", keptIn: [], goingIn: []),
        ])
        #expect(request.images[2].images.map(\.path) == ["Ta Da/attachments/interior.jpg", "Ta Da/attachments/odometer.png"])
        #expect(TrashConfirmationText(model: model).subject == "“Sell the Kombi” and its 2 tasks")
        #expect(TrashConfirmationText.note(for: request.images[1].images[0], ticked: true, phone: true)
                == ("Also in ", "Photograph the Kombi", ", moving too"))
    }

    @Test func aFileWithoutImagesGoesStraightAway() async {
        let model = await folder.model()
        #expect(!model.asksBeforeTrashing(["Ta Da/tasks/Plain.md"]))
        await model.moveToTrash(["Ta Da/tasks/Plain.md"])
        #expect(model.trashConfirmation == nil && model.index["Ta Da/tasks/Plain.md"] == nil)
    }
}
