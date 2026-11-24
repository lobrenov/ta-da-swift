import Foundation
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct PlaceTests {
    let folder: TestFolder

    init() throws {
        folder = try TestFolder([
            "Ta Da/projects/P.md": "---\ntype: project\nstatus: Doing\n---\n",
            "Ta Da/tasks/One.md": "---\ntype: task\nstatus: Doing\nproject: \"[[P]]\"\n---\n",
        ])
    }

    @Test func aFolderOpensOnTheDomainAndFileItWasLeftOn() async throws {
        let first = await folder.model()
        first.domain = .project("Ta Da/projects/P.md")
        first.selection = "Ta Da/tasks/One.md"
        let second = await folder.model()
        #expect(second.domain == .project("Ta Da/projects/P.md"))
        #expect(second.selection == "Ta Da/tasks/One.md")
    }

    @Test func aPlaceThatsGoneOpensOnTheAgenda() async throws {
        let first = await folder.model()
        first.domain = .project("Ta Da/projects/P.md")
        first.selection = "Ta Da/tasks/One.md"
        try FileManager.default.removeItem(at: folder.url.appending(path: "Ta Da/projects/P.md"))
        try FileManager.default.removeItem(at: folder.url.appending(path: "Ta Da/tasks/One.md"))
        let second = await folder.model()
        #expect(second.domain == .agenda)
        #expect(second.selection == nil)
    }
}
