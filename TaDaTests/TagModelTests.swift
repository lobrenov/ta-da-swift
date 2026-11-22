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

    @Test func theVisibleTagsStartFoldedAndTheCountHasParents() async throws {
        let model = await folder.model()
        #expect(model.visibleTags.map(\.node.tag.name) == ["errands", "Home"] && model.tagCount == 3)
        model.toggleTagFolded("home")
        #expect(model.visibleTags.map { "\($0.node.tag.name) \($0.depth)" } == ["errands 0", "Home 0", "home/garden 1"])
        #expect(model.tagCount == 3)
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
        #expect(model.sidebarMode == .projects && model.isTagFolded("home"))
        model.sidebarMode = .tags
        model.toggleTagFolded("home")
        model.toggleTagFolded("people")
        model.toggleTagFolded("people")
        let relaunched = AppModel(defaults: folder.defaults)
        #expect(relaunched.sidebarMode == .tags && !relaunched.isTagFolded("home") && relaunched.isTagFolded("people"))
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
        model.show(.agenda)
        #expect(model.sidebarMode == .tags, "Agenda and the rows above the switch leave it alone")
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

    @Test func anIPhoneTagPageStaysCurrentWhileItShows() async throws {
        let model = await folder.model(selecting: "tasks/Weed.md")
        model.showPhoneTagPage("errands")
        #expect(model.phoneTagPages["errands"]?.groups.flatMap(\.tasks).map(\.path) == ["tasks/Weed.md"])
        #expect(model.taggedCount == 2 && model.untaggedCount == 1)

        let document = try #require(model.document)
        document.text = document.text.replacing("#errands", with: "#errands done")
        #expect(model.phoneTagPages["errands"]?.groups.first?.tasks.first?.summary?.contains("done") == true)
        document.text = document.text.replacing("#errands", with: "")
        #expect(model.phoneTagPages["errands"]?.groups.isEmpty == true)
        model.hidePhoneTagPage("errands")
        #expect(model.phoneTagPages.isEmpty)
    }

    @Test func suggestionsLeaveOutTheTagBeingTyped() async throws {
        let model = await folder.model(selecting: "tasks/Weed.md")
        let document = try #require(model.document)
        document.text += "#homw"
        let source = LinkMenuSource(index: model.index, openPath: "tasks/Weed.md")
        #expect(source.tagSuggestions("hom").map(\.tag.path) == ["home", "home/garden"])
        #expect(LinkMenuSource(index: model.index).tagSuggestions("hom").map(\.tag.path).contains("homw"))
    }

    // MARK: Renaming and deleting a tag

    @Test func renamingATagWritesThroughAndStateFollows() async throws {
        let model = await folder.model()
        model.toggleTagFolded("home")
        model.toggleFilterTag("home/garden", on: .agenda)
        model.toggleFolded("Notes", in: "tag:home")
        model.toggleFolded("Notes", in: "tag:errands")
        model.show(.tag("home/garden"))
        model.showPhoneTagPage("home")

        await model.renameTag(try #require(model.tag(at: "home")), to: try #require(Tag("House")))
        #expect(try folder.read("tasks/Weed.md") == "---\ntype: task\nstatus: Doing\ncreatedDate: 2026-10-01\ntags: [House/garden]\n---\nPull them. #errands\n")
        #expect(try folder.read("areas/Home.md") == "---\ntype: area\ntags: [House]\n---\n")
        #expect(tree(model) == ["errands 1", "House 2", "House/garden 1"])
        #expect(model.expandedTags == ["house"] && !model.isTagFolded("house"))
        #expect(model.tagFilter(on: .agenda).picked == ["house/garden"])
        #expect(model.isFolded("Notes", in: "tag:house") && model.isFolded("Notes", in: "tag:errands") && model.foldedGroups["tag:home"] == nil)
        #expect(model.domain == .tag("house/garden") && model.shownTag?.name == "House/garden")
        #expect(model.tagPage?.groups.flatMap(\.tasks).map(\.path) == ["tasks/Weed.md"])
        #expect(model.phoneTagPages.keys.compactMap { $0 } == ["house"] && model.phoneTagPages["house"]?.groups.isEmpty == false)
        #expect(model.errorMessage == nil)
    }

    @Test func renamingToTheSamePathChangesCase() async throws {
        let model = await folder.model()
        await model.renameTag(try #require(model.tag(at: "errands")), to: try #require(Tag("Errands")))
        #expect(try folder.read("tasks/Weed.md").hasSuffix("Pull them. #Errands\n"))
        #expect(model.tag(at: "errands")?.name == "Errands")
    }

    @Test func renamingIntoAnExistingTagMerges() async throws {
        let model = await folder.model()
        model.askRenameTag(try #require(model.tag(at: "errands")), to: "home")
        #expect(model.tagRenameConfirmation?.merges == true && model.tagRenameConfirmation?.count == 1)
        await model.renameTag(try #require(model.tag(at: "errands")), to: try #require(Tag("home")))
        #expect(tree(model) == ["Home 2", "home/garden 1"])
    }

    @Test func renameAsksOnlyForAValidChangedName() async throws {
        let model = await folder.model()
        let home = try #require(model.tag(at: "home"))
        model.askRenameTag(home, to: "Home")
        model.askRenameTag(home, to: "has space #")
        model.askRenameTag(home, to: "")
        model.askRenameTag(home, to: "home/garden")
        model.askRenameTag(home, to: "Home/Pond")
        #expect(model.tagRenameConfirmation == nil)
        #expect(AppModel.renameTarget(of: home, to: "HOME")?.name == "HOME" && AppModel.renameTarget(of: home, to: "homely")?.name == "homely")
        model.askRenameTag(home, to: "house")
        #expect(model.tagRenameConfirmation?.new?.name == "house" && model.tagRenameConfirmation?.merges == false)
        #expect(model.tagRenameConfirmation?.count == 2)
        model.askDeleteTag(home)
        #expect(model.tagDeleteConfirmation?.count == 2)
    }

    @Test func deletingATagWritesThroughAndStateIsDropped() async throws {
        let model = await folder.model()
        model.toggleTagFolded("home")
        model.toggleFilterTag("home/garden", on: .agenda)
        model.toggleFilterTag("errands", on: .agenda)
        model.toggleFolded("Notes", in: "tag:home")
        model.show(.tag("home"))
        model.showPhoneTagPage("home")
        model.showPhoneTagPage("errands")

        await model.deleteTag(try #require(model.tag(at: "home")))
        #expect(try folder.read("tasks/Weed.md") == "---\ntype: task\nstatus: Doing\ncreatedDate: 2026-10-01\ntags:\n---\nPull them. #errands\n")
        #expect(tree(model) == ["errands 1"])
        #expect(model.expandedTags.isEmpty)
        #expect(model.tagFilter(on: .agenda).picked == ["errands"])
        #expect(model.foldedGroups["tag:home"] == nil)
        #expect(model.domain == .tag(nil) && model.shownTag == nil)
        #expect(model.phoneTagPages.keys.compactMap { $0 } == ["errands"])
    }

    @Test func aTagThatCantBeEditedReportsOnlyACount() async throws {
        try folder.write("---\ntype: task\nstatus: Doing\ntags: [work, # c\n  b]\n---\n", "tasks/Stuck.md")
        let model = await folder.model()
        await model.renameTag(try #require(model.tag(at: "work")), to: try #require(Tag("job")))
        #expect(model.errorMessage == "1 file still has “work”. Ta Da can’t edit its tags property.")
        #expect(AppModel.tagFailureMessage(count: 2, tag: try #require(Tag("work"))) == "2 files still have “work”. Ta Da can’t edit their tags property.")
        #expect(AppModel.renameTagMessage(count: 1) == "Changes 1 file, including child tags. This can’t be undone.")
        #expect(AppModel.deleteTagMessage(count: 3) == "Removes it and its child tags from 3 files. This can’t be undone.")
    }

    @Test func stateStaysWhileAFileStillCarriesTheTag() async throws {
        try folder.write("---\ntype: task\nstatus: Doing\ntags: [work, # c\n  b]\n---\n", "tasks/Stuck.md")
        let model = await folder.model()
        model.toggleFilterTag("work", on: .agenda)
        model.show(.tag("work"))
        let work = try #require(model.tag(at: "work"))
        #expect(await model.renameTag(work, to: try #require(Tag("job"))) == false)
        #expect(model.tagFilter(on: .agenda).picked == ["work"] && model.domain == .tag("work"))
        #expect(await model.deleteTag(work) == false)
        #expect(model.tagFilter(on: .agenda).picked == ["work"] && model.domain == .tag("work"))
        #expect(await model.renameTag(try #require(model.tag(at: "errands")), to: try #require(Tag("Errands"))))
    }
}
