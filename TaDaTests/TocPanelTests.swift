import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct TocPanelTests {
    let folder: TestFolder

    init() throws {
        folder = try TestFolder([
            "areas/Home.md": "---\ntype: area\n---\n",
            "projects/Sell the Kombi.md": "---\ntype: project\n---\n## Plan\n",
            "tasks/Photograph the Kombi.md": """
            ---
            type: task
            project: "[[Sell the Kombi]]"
            area: "[[Home]]"
            ---
            # Title
            Intro with [[Swift conventions]].
            ## Scope
            ### Must ship
            ###### Deep
            ![[front.jpg]] then [[Home]], [[Crash reporting]], [[swift conventions]] and [[Photograph the Kombi]].
            """,
            "notes/Swift conventions.md": "Plain.\n",
            "notes/Roadmap.md": "See [[Photograph the Kombi]].\n",
            "notes/Only headings.md": "## One\n## Two\n",
            "notes/Empty.md": "Nothing here.\n",
            "notes/Lonely.md": "Alone.\n",
            "notes/Linker.md": "[[Empty]]\n",
        ])
    }

    private func content(_ path: String) async throws -> TocContent {
        let model = await folder.model()
        return TocContent(item: try #require(model.index[path]), index: model.index)
    }

    @Test func contentsListHeadingsFromH1WithTheirLines() async throws {
        let toc = try await content("tasks/Photograph the Kombi.md")
        #expect(toc.headings.map(\.text) == ["Title", "Scope", "Must ship", "Deep"])
        #expect(toc.headings.map(\.level) == [1, 2, 3, 6])
        #expect(toc.headings.map(\.line) == [0, 2, 3, 4])
        #expect(toc.headings.map(toc.depth(of:)) == [0, 1, 2, 5])
    }

    @Test func depthIsRelativeToTheShallowestLevelPresent() async throws {
        let only = try await content("notes/Only headings.md")
        #expect(only.headings.map(only.depth(of:)) == [0, 0])
        let project = try await content("projects/Sell the Kombi.md")
        #expect(project.headings.map(project.depth(of:)) == [0])
    }

    @Test func linksAreBodyLinksOnceInOrderWithUnresolvedOnesMarked() async throws {
        let toc = try await content("tasks/Photograph the Kombi.md")
        #expect(toc.links.map(\.title) == ["Swift conventions", "Home", "Crash reporting"])
        #expect(toc.links.map { $0.path == nil } == [false, false, true])
        #expect(toc.links.map(\.hint) == ["", "Area", ""])
    }

    @Test func frontmatterLinksEmbedsAndSelfLinksAreLeftOut() async throws {
        let task = try await content("tasks/Photograph the Kombi.md")
        #expect(!task.links.map(\.title).contains("Sell the Kombi"))
        #expect(!task.links.map(\.title).contains("front.jpg"))
        #expect(!task.links.map(\.title).contains("Photograph the Kombi"))
        let project = try await content("projects/Sell the Kombi.md")
        #expect(project.backlinks.isEmpty && project.links.isEmpty)
    }

    @Test func backlinksAreTheFilesLinkingHere() async throws {
        let note = try await content("notes/Swift conventions.md")
        #expect(note.backlinks.map(\.title) == ["Photograph the Kombi"])
        #expect(note.backlinks.first?.path == "tasks/Photograph the Kombi.md")
        let task = try await content("tasks/Photograph the Kombi.md")
        #expect(task.backlinks.map(\.title) == ["Roadmap"])
    }

    @Test func anEmptySectionIsLeftOut() async throws {
        let toc = try await content("notes/Only headings.md")
        #expect(toc.headings.count == 2 && toc.links.isEmpty && toc.backlinks.isEmpty)
        #expect(toc.hasRail && !toc.hasLinks)
        let linkOnly = try await content("notes/Linker.md")
        #expect(linkOnly.headings.isEmpty && linkOnly.links.count == 1)
        #expect(linkOnly.hasRail && linkOnly.hasLinks)
    }

    @Test func aFileWithNothingToShowHasNoRail() async throws {
        let lonely = try await content("notes/Lonely.md")
        #expect(lonely.headings.isEmpty && lonely.links.isEmpty && lonely.backlinks.isEmpty)
        #expect(!lonely.hasRail)
        let backlinksOnly = try await content("notes/Empty.md")
        #expect(backlinksOnly.hasRail && backlinksOnly.hasLinks)
    }

    @Test func theCurrentHeadingIsTheLastAtOrAboveTheLastVisibleLine() async throws {
        let toc = try await content("tasks/Photograph the Kombi.md")
        #expect(toc.currentHeading(lastVisibleLine: 0) == 0)
        #expect(toc.currentHeading(lastVisibleLine: 1) == 0)
        #expect(toc.currentHeading(lastVisibleLine: 2) == 1)
        #expect(toc.currentHeading(lastVisibleLine: 3) == 2)
        #expect(toc.currentHeading(lastVisibleLine: 40) == 3)
    }

    #if os(macOS)
    @Test func aBodyChangeFromOutsideTheEditorIsNotTyping() async throws {
        let model = await folder.model(selecting: "notes/Empty.md")
        let state = TocState()
        let document = try #require(model.document)
        document.body = "Changed elsewhere.\n"
        #expect(!state.typing)
    }
    #endif
}
