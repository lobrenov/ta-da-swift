import Foundation
import Testing
import TaDaCore
@testable import TaDa

@MainActor
struct AreaModelTests {
    let folder: TestFolder

    init() throws {
        folder = try TestFolder([
            "areas/Home.md": "---\ntype: area\n---\n",
            "projects/Garden.md": "---\ntype: project\nstatus: Doing\narea: \"[[Home]]\"\n---\n",
            "projects/Side.md": "---\ntype: project\nstatus: Doing\n---\n",
            "tasks/Weed.md": "---\ntype: task\nstatus: Doing\nproject: \"[[Garden]]\"\n---\n",
            "tasks/Rent.md": "---\ntype: task\nstatus: Doing\narea: \"[[Home]]\"\ndueDate: 2026-10-03\n---\n",
            "tasks/Loose.md": "---\ntype: task\nstatus: Not Started\n---\n",
        ])
    }

    @Test func listsSplitLooseProjectsFromAreas() async {
        let model = await folder.model()
        #expect(model.looseProjects.map(\.project.title) == ["Side"])
        #expect(model.areas.map { "\($0.area.title): \($0.projects.map(\.project.title))" } == ["Home: [\"Garden\"]"])
        #expect(model.looseTasks.map(\.title) == ["Loose"])
    }

    @Test func settingAParentWritesOneKey() async throws {
        let model = await folder.model()
        let home = try #require(model.index["areas/Home.md"])
        let side = try #require(model.index["projects/Side.md"])
        await model.setParent(home, of: ["tasks/Weed.md", "tasks/Loose.md", "projects/Side.md"])
        #expect(try folder.read("tasks/Weed.md") == "---\ntype: task\nstatus: Doing\nproject:\narea: \"[[Home]]\"\n---\n")
        #expect(try folder.read("tasks/Loose.md") == "---\ntype: task\nstatus: Not Started\narea: \"[[Home]]\"\n---\n")
        #expect(try folder.read("projects/Side.md") == "---\ntype: project\nstatus: Doing\narea: \"[[Home]]\"\n---\n")
        #expect(model.looseTasks.isEmpty && model.looseProjects.isEmpty)

        await model.setParent(side, of: ["tasks/Rent.md", "projects/Garden.md"])
        #expect(try folder.read("tasks/Rent.md") == "---\ntype: task\nstatus: Doing\narea:\ndueDate: 2026-10-03\nproject: \"[[Side]]\"\n---\n")
        #expect(model.index["projects/Garden.md"]?.properties.area?.title == "Home", "a project doesn't go under a project")

        await model.setParent(nil, of: ["projects/Side.md"])
        #expect(model.looseProjects.map(\.project.title) == ["Side"])
    }

    @Test func newFilesOnAnAreaPageGoInIt() async throws {
        let model = await folder.model()
        model.show(.area("areas/Home.md"))
        await model.newTask()
        let task = try #require(model.selection)
        #expect(model.domain == .area("areas/Home.md"))
        #expect(model.index[task]?.properties.area?.title == "Home")
        await model.newProject()
        let project = try #require(model.selection)
        #expect(model.domain == .project(project))
        #expect(model.index.area(of: try #require(model.index[project]))?.title == "Home")
    }

    @Test func newAreaOpensItsPage() async throws {
        let model = await folder.model()
        await model.newArea()
        #expect(model.domain == .area("areas/Untitled.md") && model.titleFocus == "areas/Untitled.md")
        #expect(try folder.read("areas/Untitled.md") == NewFile.area(today: model.today))
    }

    @Test func creatingANamedAreaResolvesFilesThatNameIt() async throws {
        try folder.write("---\ntype: task\nstatus: Doing\narea: Work\n---\n", "tasks/Timesheet.md")
        let model = await folder.model()
        #expect(model.looseTasks.map(\.title).contains("Timesheet"))
        await model.newArea(named: "Work")
        #expect(!model.looseTasks.map(\.title).contains("Timesheet"))
        #expect(model.areas.map(\.area.title) == ["Home", "Work"])
    }

    @Test func renamingAnAreaRelinksAndFollowsIt() async throws {
        let model = await folder.model()
        model.show(.area("areas/Home.md"))
        await model.rename("areas/Home.md", to: "House")
        #expect(model.domain == .area("areas/House.md"))
        #expect(try folder.read("projects/Garden.md").contains("area: \"[[House]]\""))
        #expect(try folder.read("tasks/Rent.md").contains("area: \"[[House]]\""))
        #expect(model.areas.first?.projects.map(\.project.title) == ["Garden"])
    }

    @Test func deletingAnAreaAsksFirstThenTakesEverything() async throws {
        let model = await folder.model()
        model.show(.area("areas/Home.md"))
        await model.moveToTrash(["areas/Home.md"])
        #expect(model.trashConfirmation?.count == 4)
        #expect(model.index["areas/Home.md"] != nil)
        let text = TrashConfirmationText(model: model)
        #expect(text.title == "Delete “Home”?")
        #expect(text.message.hasPrefix("Home, its 1 project and their 1 task, and its 1 own task move to the Trash."))

        // The alert clears the request as it closes, before its button's task runs.
        let request = try #require(model.trashConfirmation)
        model.trashConfirmation = nil
        await model.confirmTrash(request)
        #expect(model.trashConfirmation == nil && model.domain == .today)
        #expect(model.index.items.keys.sorted() == ["projects/Side.md", "tasks/Loose.md"])
        #expect(model.trash.count == 4)

        model.show(.trash)
        await model.restore([".trash/Weed.md"])
        #expect(model.index.items.keys.sorted() == ["areas/Home.md", "projects/Garden.md", "projects/Side.md", "tasks/Loose.md", "tasks/Weed.md"])
        #expect(model.trashNote == "3 items restored to areas/, projects/, and tasks/")
    }
}
