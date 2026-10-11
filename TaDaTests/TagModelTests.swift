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
}
