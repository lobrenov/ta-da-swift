import Foundation
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct LinkFollowTests {
    let folder: TestFolder

    init() throws {
        folder = try TestFolder([
            "areas/Home.md": "---\ntype: area\n---\n",
            "projects/Sell the Kombi.md": "---\ntype: project\n---\nSee [[Photograph the Kombi]].\n",
            "tasks/Photograph the Kombi.md": "---\ntype: task\nproject: \"[[Sell the Kombi]]\"\n---\nFor [[Sell the Kombi#Plan|the sale]].\n",
            "tasks/Fix the gate.md": "---\ntype: task\narea: \"[[Home]]\"\n---\n",
            "tasks/Loose.md": "---\ntype: task\n---\n[[Sell the Kombi]], [[Fix the gate]] and `[[Sell the Kombi]]`\n",
        ])
    }

    @Test func aLinkToATaskOpensItInItsProjectAreaOrLooseTasks() async {
        let model = await folder.model()
        model.openLink(to: "tasks/Photograph the Kombi.md")
        #expect(model.domain == .project("projects/Sell the Kombi.md") && model.selection == "tasks/Photograph the Kombi.md")
        model.openLink(to: "tasks/Fix the gate.md")
        #expect(model.domain == .area("areas/Home.md") && model.selection == "tasks/Fix the gate.md")
        model.openLink(to: "tasks/Loose.md")
        #expect(model.domain == .loose && model.selection == "tasks/Loose.md")
        model.openLink(to: "projects/Sell the Kombi.md")
        #expect(model.domain == .project("projects/Sell the Kombi.md") && model.selection == "projects/Sell the Kombi.md")
    }

    @Test func renamingAFileRewritesTheLinksToItTheOpenFileInPlace() async throws {
        let model = await folder.model(selecting: "tasks/Photograph the Kombi.md")
        await model.rename("projects/Sell the Kombi.md", to: "Sell the car")
        #expect(model.errorMessage == nil)
        #expect(model.document?.text == "---\ntype: task\nproject: \"[[Sell the car]]\"\n---\nFor [[Sell the car#Plan|the sale]].\n")
        #expect(try folder.read("tasks/Loose.md") == "---\ntype: task\n---\n[[Sell the car]], [[Fix the gate]] and `[[Sell the Kombi]]`\n")
        let project = try #require(model.index["projects/Sell the car.md"])
        #expect(model.index.backlinks(to: project).map(\.title) == ["Loose", "Photograph the Kombi"])
    }

    @Test func linksStayWhenAnotherFileKeepsTheOldTitle() async throws {
        try "---\ntype: task\n---\n".write(to: folder.url.appending(path: "tasks/Sell the Kombi.md"), atomically: true, encoding: .utf8)
        let model = await folder.model()
        await model.rename("projects/Sell the Kombi.md", to: "Sell the car")
        #expect(try folder.read("tasks/Loose.md").hasPrefix("---\ntype: task\n---\n[[Sell the Kombi]]"))
    }

    @Test func linksStayWhenAPlainNoteKeepsTheOldTitle() async throws {
        try folder.write("Just a note.\n", "notes/Sell the Kombi.md")
        let model = await folder.model()
        await model.rename("projects/Sell the Kombi.md", to: "Sell the car")
        #expect(try folder.read("tasks/Loose.md").hasPrefix("---\ntype: task\n---\n[[Sell the Kombi]]"))
    }

    @Test func aFilesLinksToItselfFollowItsRename() async throws {
        try folder.write("---\ntype: task\n---\nSee [[Loose]] and [[Fix the gate]].\n", "tasks/Loose.md")
        let model = await folder.model()
        await model.rename("tasks/Loose.md", to: "Spare")
        #expect(try folder.read("tasks/Spare.md") == "---\ntype: task\n---\nSee [[Spare]] and [[Fix the gate]].\n")
    }
}
