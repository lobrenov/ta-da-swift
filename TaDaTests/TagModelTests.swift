import Foundation
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct TagModelTests {
    let folder: TestFolder

    init() throws {
        folder = try TestFolder([
            "areas/Home.md": "---\ntype: area\ntags: [Home]\n---\n",
            "tasks/Weed.md": "---\ntype: task\nstatus: Doing\ncreatedDate: 2026-10-01\ntags: [home/garden]\n---\nPull them. #errands\n",
            "tasks/Loose.md": "---\ntype: task\nstatus: Not Started\n---\n",
        ])
    }

    private func tree(_ model: AppModel) -> [String] {
        func describe(_ nodes: [TagNode]) -> [String] { nodes.flatMap { ["\($0.tag.name) \($0.count)"] + describe($0.children) } }
        return describe(model.tagTree)
    }

    @Test func theTagTreeAndUntaggedFollowTyping() async throws {
        let model = await folder.model(selecting: "tasks/Loose.md")
        #expect(tree(model) == ["errands 1", "Home 2", "home/garden 1"] && model.untaggedCount == 1)
        #expect(model.tag(at: "home/garden")?.name == "home/garden" && model.tag(at: "home")?.name == "Home")
        #expect(model.tag(at: "nothing") == nil && model.tag(at: "home/nothing") == nil)

        let document = try #require(model.document)
        document.text += "Ask #People/Max\n"
        #expect(tree(model) == ["errands 1", "Home 2", "home/garden 1", "People 1", "People/Max 1"] && model.untaggedCount == 0)
    }

    @Test func theVisibleTagsLeaveOutFoldedChildrenAndTheCountHasParents() async throws {
        let model = await folder.model()
        #expect(model.visibleTags.map { "\($0.node.tag.name) \($0.depth)" } == ["errands 0", "Home 0", "home/garden 1"])
        #expect(model.tagCount == 3)
        model.toggleTagFolded("home")
        #expect(model.visibleTags.map(\.node.tag.name) == ["errands", "Home"] && model.tagCount == 3)
    }

    @Test func tagsAreAddedAndRemovedInTagsOnly() async throws {
        let model = await folder.model()
        let quick = try #require(Tag("quick win"))
        await model.addTag(quick, to: "tasks/Weed.md")
        #expect(try folder.read("tasks/Weed.md") == "---\ntype: task\nstatus: Doing\ncreatedDate: 2026-10-01\ntags: [home/garden, quick win]\n---\nPull them. #errands\n")
        await model.removeTag(try #require(Tag("Home/Garden")), from: "tasks/Weed.md")
        await model.removeTag(try #require(Tag("errands")), from: "tasks/Weed.md")
        #expect(try folder.read("tasks/Weed.md") == "---\ntype: task\nstatus: Doing\ncreatedDate: 2026-10-01\ntags: [quick win]\n---\nPull them. #errands\n")
        await model.addTag(quick, to: "tasks/Loose.md")
        #expect(try folder.read("tasks/Loose.md") == "---\ntype: task\nstatus: Not Started\ntags: [quick win]\n---\n")
        #expect(tree(model) == ["errands 1", "Home 1", "quick win 2"] && model.untaggedCount == 0)
    }

    @Test func aNewTaskOnATagsPageCarriesTheTag() async throws {
        let model = await folder.model()
        model.show(.tag("home/garden"))
        await model.newTask()
        let path = try #require(model.selection)
        #expect(model.domain == .tag("home/garden") && model.titleFocus == path)
        #expect(try folder.read(path) == "---\ntype: task\nstatus: Not Started\ncreatedDate: 2026-10-03\ntags: [home/garden]\n---\n")

        model.show(.tag(nil))
        await model.newTask()
        let untagged = try #require(model.selection)
        #expect(model.domain == .tag(nil) && model.index[untagged]?.tags.isEmpty == true)
    }

    @Test func theSidebarModeAndTagFoldsSurviveARelaunch() async {
        let model = await folder.model()
        #expect(model.sidebarMode == .projects && !model.isTagFolded("home"))
        model.sidebarMode = .tags
        model.toggleTagFolded("home")
        model.toggleTagFolded("people")
        model.toggleTagFolded("people")
        let relaunched = AppModel(defaults: folder.defaults)
        #expect(relaunched.sidebarMode == .tags && relaunched.isTagFolded("home") && !relaunched.isTagFolded("people"))
    }

    @Test func pickingATagClearsTheSelection() async {
        let model = await folder.model(selecting: "tasks/Weed.md")
        model.show(.tag("errands"))
        #expect(model.selection == nil && model.domain.title == "errands")
        #expect(AppModel.Domain.tag(nil).title == "Untagged")
    }

    @Test func theSidebarFollowsTheDomain() async {
        let model = await folder.model()
        model.show(.tag("errands"))
        #expect(model.sidebarMode == .tags)
        model.show(.area("areas/Home.md"))
        #expect(model.sidebarMode == .projects)
        model.sidebarMode = .tags
        model.show(.today)
        #expect(model.sidebarMode == .tags, "Today and the rows above the switch leave it alone")
        model.show(.loose)
        #expect(model.sidebarMode == .projects)
    }

    @Test func aTagPageKeepsItsSpellingOnceNoFileCarriesIt() async throws {
        let model = await folder.model()
        model.show(.tag("home"))
        #expect(model.shownTag?.name == "Home" && model.tagPage?.areasAndProjects.map(\.title) == ["Home"])
        await model.removeTag(try #require(Tag("home/garden")), from: "tasks/Weed.md")
        await model.removeTag(try #require(Tag("home")), from: "areas/Home.md")
        #expect(model.tag(at: "home") == nil, "\(model.tagTree.map(\.tag.name))")
        #expect(model.shownTag?.name == "Home", "\(String(describing: model.shownTag))")
        #expect(model.tagPage?.areasAndProjects.isEmpty == true && model.tagPage?.groups.isEmpty == true)
        await model.newTask()
        #expect(try folder.read(try #require(model.selection)).contains("tags: [Home]\n"))
    }

    @Test func typingKeepsTheTagPageCurrent() async throws {
        let model = await folder.model()
        model.show(.tag("errands"))
        model.selection = "tasks/Weed.md"
        await model.loading?.value
        let document = try #require(model.document)
        document.text += "More.\n"
        #expect(model.tagPage?.groups.flatMap(\.tasks).first?.summary == "Pull them. #errands More.")
        document.text = document.text.replacingOccurrences(of: "#errands", with: "#errand")
        #expect(model.tagPage?.groups.isEmpty == true && model.tagTree.map(\.tag.name) == ["errand", "Home"])
    }
}
