import Testing
@testable import TaDaCore

private let project = makeItem("projects/Ta Da MVP.md", "type: project\nstatus: Doing")
private let member = makeItem("tasks/Member.md", "type: task\nstatus: Doing\nproject: \"[[ta da mvp]]\"", body: "See [[Ta Da MVP#Goals|goals]].")
private let folderLink = makeItem("tasks/Folder link.md", "type: task\nstatus: Done\nproject: \"[[projects/Ta Da MVP.md]]\"")
private let toTask = makeItem("tasks/To a task.md", "type: task\nstatus: Doing\nproject: \"[[Member]]\"")
private let missing = makeItem("tasks/Missing.md", "type: task\nstatus: Doing\nproject: \"[[Nowhere]]\"", body: "[[Member]]")

@Test func indexResolvesProjectsByTitleIgnoringCaseAndFolders() {
    let index = VaultIndex([project, member, folderLink, toTask, missing])
    #expect(index.project(of: member)?.path == project.path)
    #expect(index.project(of: folderLink)?.path == project.path)
    #expect(index.project(of: toTask) == nil, "a link to a task isn't a project")
    #expect(index.project(of: missing) == nil)
    #expect(index.tasks(in: project).map(\.title) == ["Folder link", "Member"])
}

@Test func indexWarnsOnUnresolvedProjects() {
    let index = VaultIndex([project, member, toTask, missing])
    #expect(index.warnings(for: member).isEmpty)
    #expect(index.warnings(for: missing) == [.unresolvedProject("Nowhere")])
    #expect(index.warnings(for: toTask) == [.unresolvedProject("Member")])
}

@Test func indexFindsBacklinks() {
    let index = VaultIndex([project, member, missing])
    #expect(index.backlinks(to: project).map(\.title) == ["Member"])
    #expect(index.backlinks(to: member).map(\.title) == ["Missing"])
}

@Test func indexPrefersTheFirstPathWhenTitlesRepeat() {
    let duplicate = makeItem("archive/Ta Da MVP.md", "type: project\nstatus: Done")
    let index = VaultIndex([project, duplicate, member])
    #expect(index.items(titled: "TA DA MVP").map(\.path) == ["archive/Ta Da MVP.md", "projects/Ta Da MVP.md"])
    #expect(index.project(of: member)?.path == "archive/Ta Da MVP.md")
}

@Test func indexPatchesItems() {
    var index = VaultIndex([member])
    #expect(index.project(of: member) == nil)
    index.update(project)
    #expect(index.tasks(in: project).map(\.title) == ["Member"])
    index.update(makeItem(member.path, "type: task\nstatus: Doing"))
    #expect(index.tasks(in: project).isEmpty)
    index.remove(project.path)
    #expect(index[project.path] == nil && index.items.count == 1)
}
