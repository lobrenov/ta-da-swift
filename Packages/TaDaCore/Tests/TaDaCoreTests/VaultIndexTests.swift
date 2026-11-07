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

@Test func indexCountsEmbedsAndKeepsThemOutOfBacklinks() {
    let photo = makeItem("tasks/Photograph the Kombi.md", "type: task\nstatus: Doing", body: "![[odometer.png]] ![[Member]]")
    let history = makeItem("tasks/Kombi service history.md", "type: task\nstatus: Doing",
                           body: "![[attachments/Odometer.png]]\n\n![[odometer.png|200]] ![[front.jpg]]")
    var index = VaultIndex([member, photo, history])
    #expect(index.embedders(of: "ODOMETER.png").map { "\($0.item.title) \($0.count)" } == ["Kombi service history 2", "Photograph the Kombi 1"])
    #expect(index.embedders(of: "front.jpg").map(\.item.title) == ["Kombi service history"])
    #expect(index.backlinks(to: member).isEmpty, "an embed isn't a link")
    index.update(makeItem(history.path, "type: task\nstatus: Doing"))
    #expect(index.embedders(of: "odometer.png").map(\.item.title) == ["Photograph the Kombi"] && index.embedders(of: "front.jpg").isEmpty)
    index.remove(photo.path)
    #expect(index.embedders(of: "odometer.png").isEmpty)
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

@Test func patchingKeepsLookupsInStepWithTheItems() {
    let earlier = makeItem("archive/Ta Da MVP.md", "type: project\nstatus: Done")
    let nowhere = makeItem("projects/Nowhere.md", "type: project\nstatus: Doing")
    var index = VaultIndex([member, missing])
    expectInStep(index)
    index.update(project)
    expectInStep(index)
    #expect(index.tasks(in: project).map(\.title) == ["Member"] && index.backlinks(to: project).map(\.title) == ["Member"])
    index.update(earlier)
    expectInStep(index)
    #expect(index.tasks(in: earlier).map(\.title) == ["Member"] && index.tasks(in: project).isEmpty, "the first path takes over")
    index.update(makeItem(member.path, "type: task\nstatus: Doing\nproject: \"[[Nowhere]]\""))
    index.update(nowhere)
    expectInStep(index)
    #expect(index.tasks(in: nowhere).map(\.title) == ["Member", "Missing"] && index.backlinks(to: project).isEmpty)
    index.update(makeItem(nowhere.path, "type: task\nstatus: Doing"))
    expectInStep(index)
    #expect(index.tasks(in: nowhere).isEmpty && index.project(of: missing) == nil, "a project turned into a task")
    index.remove(earlier.path)
    index.remove(member.path)
    expectInStep(index)
    #expect(index.titles == ["ta da mvp", "missing", "nowhere"])
    for path in Array(index.items.keys) { index.remove(path) }
    #expect(index.titles.isEmpty)
}

/// Checks the lookups against answers worked out from every item, as a full rebuild would.
private func expectInStep(_ index: VaultIndex, sourceLocation: SourceLocation = #_sourceLocation) {
    let all = Array(index.items.values)
    #expect(index.titles == Set(all.map { $0.title.lowercased() }), sourceLocation: sourceLocation)
    for item in all {
        let title = item.title.lowercased()
        #expect(index.items(titled: title).map(\.path) == all.filter { $0.title.lowercased() == title }.map(\.path).sorted(),
                sourceLocation: sourceLocation)
        #expect(index.tasks(in: item) == index.tasks.filter { index.project(of: $0)?.path == item.path }.sorted(by: VaultIndex.byTitle),
                sourceLocation: sourceLocation)
        #expect(index.backlinks(to: item) == all.filter { $0.path != item.path && $0.links.contains { $0.title.lowercased() == title } }
                    .sorted(by: VaultIndex.byTitle), sourceLocation: sourceLocation)
    }
}

@Test func loggedFilesResolveAsLinksButStayOutOfTheLists() {
    let index = VaultIndex([
        makeItem("projects/Kombi.md", "type: project\nstatus: Doing"),
        makeItem("Ta Da/logbook/2026-09/Kombi.md", "type: project\nstatus: Done\ncompletedDate: 2026-09-30"),
        makeItem("Ta Da/logbook/2026-09/Sold.md", "type: project\nstatus: Done\ncompletedDate: 2026-09-30"),
        makeItem("tasks/Open.md", "type: task\nstatus: Doing\nproject: \"[[Kombi]]\""),
        makeItem("tasks/Closed.md", "type: task\nstatus: Done\nproject: \"[[Kombi]]\""),
        makeItem("Ta Da/logbook/2026-09/Photos.md", "type: task\nstatus: Done\ncompletedDate: 2026-09-30\nproject: \"[[Kombi]]\""),
        makeItem("Ta Da/logbook/2026-09/Listing.md", "type: task\nstatus: Done\ncompletedDate: 2026-09-30\nproject: \"[[Sold]]\""),
    ])
    #expect(index["Ta Da/logbook/2026-09/Photos.md"]?.isLogged == true)
    #expect(index.items(titled: "Kombi").map(\.path) == ["projects/Kombi.md", "Ta Da/logbook/2026-09/Kombi.md"], "the file that isn't logged resolves first")
    #expect(index.projects.map(\.title) == ["Kombi"])
    #expect(Set(index.logged.map(\.title)) == ["Kombi", "Sold", "Photos", "Listing"])
    let kombi = index["projects/Kombi.md"]!, sold = index["Ta Da/logbook/2026-09/Sold.md"]!
    #expect(index.tasks(in: kombi).map(\.title) == ["Closed", "Open"])
    #expect(index.tasks(in: kombi, includingLogged: true).map(\.title) == ["Closed", "Open", "Photos"])
    #expect(index.openTasks(in: kombi).map(\.title) == ["Open"])
    #expect(index.tasks(in: sold, includingLogged: true).map(\.title) == ["Listing"], "a logged project has its logged tasks")
    #expect(index.parent(of: index["Ta Da/logbook/2026-09/Listing.md"]!)?.path == sold.path)
    #expect((index.progress(of: kombi).done, index.progress(of: kombi).total) == (2, 3), "progress counts logged tasks")
    #expect(index.search("photos").isEmpty && index.search("open").map(\.title) == ["Open"])
}

@Test func indexPatchesTagsPerItem() {
    let a = makeItem("tasks/A.md", "type: task\nstatus: Doing\ntags: [Errands]", body: "#home/garden")
    let b = makeItem("tasks/B.md", "type: task\nstatus: Doing", body: "#errands")
    var index = VaultIndex([a, b])
    #expect(index.carriedTags.map(\.name).sorted() == ["Errands", "home/garden"])
    #expect(index.paths(carrying: "errands") == [a.path, b.path])
    #expect(index.paths(carrying: "home").isEmpty, "a parent isn't carried by its children's files")

    index.update(makeItem("tasks/A.md", "type: task\nstatus: Doing"))
    #expect(index.paths(carrying: "errands") == [b.path] && index.paths(carrying: "home/garden").isEmpty)
    #expect(index.carriedTags.map(\.name) == ["errands"], "spelled by the remaining carrier")

    index.update(a)
    #expect(index.carriedTags.map(\.name).sorted() == ["Errands", "home/garden"], "the first path's spelling wins")
    index.remove(b.path)
    index.remove(a.path)
    #expect(index.carriedTags.isEmpty)
}

@Test func patchedTagSpellingsMatchARebuild() {
    let files = [
        makeItem("tasks/A.md", "type: task\nstatus: Doing\ntags: [Home]"),
        makeItem("tasks/B.md", "type: task\nstatus: Doing\ntags: [home]"),
        makeItem("tasks/C.md", "type: task\nstatus: Doing", body: "#HOME"),
    ]
    var index = VaultIndex(files.reversed())
    #expect(index.carriedTags.map(\.name) == ["Home"])
    let edits = [makeItem("tasks/A.md", "type: task\nstatus: Doing"), makeItem("tasks/B.md", "type: task\nstatus: Doing\ntags: [hOme]")]
    for edit in edits { index.update(edit) }
    #expect(index.carriedTags.map(\.name) == VaultIndex([edits[0], edits[1], files[2]]).carriedTags.map(\.name))
    #expect(index.carriedTags.map(\.name) == ["hOme"])
}

@Test func indexCountsLoggedFilesInTags() {
    let logged = makeItem("Ta Da/logbook/tasks/Old.md", "type: task\nstatus: Done\ntags: [old]")
    var index = VaultIndex([logged])
    #expect(index.paths(carrying: "old") == [logged.path])
    index.update(makeItem("tasks/Old.md", "type: task\nstatus: Done\ntags: [old]"))
    #expect(index.paths(carrying: "old") == [logged.path, "tasks/Old.md"])
    index.remove(logged.path)
    #expect(index.paths(carrying: "old") == ["tasks/Old.md"])
}

@Test func liveFilesSpellATagBeforeLoggedOnes() {
    let logged = makeItem("Ta Da/logbook/tasks/Old.md", "type: task\nstatus: Done\ntags: [Home]")
    let live = makeItem("tasks/New.md", "type: task\nstatus: Doing\ntags: [home]")
    var index = VaultIndex([logged, live])
    #expect(index.carriedTags.map(\.name) == ["home"])
    index.remove(live.path)
    #expect(index.carriedTags.map(\.name) == ["Home"])
    index.update(live)
    #expect(index.carriedTags.map(\.name) == ["home"])
    index.remove(live.path)
    index.update(makeItem("tasks/Newer.md", "type: task\nstatus: Doing\ntags: [HOME]"))
    index.remove("tasks/Newer.md")
    #expect(index.carriedTags.map(\.name) == ["Home"])
}

@Test func movingATaggedFileIntoTheLogbookAndBackKeepsTheTagCounts() {
    let live = makeItem("tasks/Old.md", "type: task\nstatus: Done\ntags: [Home]")
    let logged = makeItem("Ta Da/logbook/tasks/Old.md", "type: task\nstatus: Done\ntags: [Home]")
    var index = VaultIndex([live, makeItem("tasks/Other.md", "type: task\nstatus: Doing\ntags: [home]")])
    index.remove(live.path)
    index.update(logged)
    #expect(index.tagTree().map { [$0.tag.name, String($0.count)] } == [["home", "2"]])
    index.remove(logged.path)
    index.update(live)
    #expect(index.tagTree().map { [$0.tag.name, String($0.count)] } == [["Home", "2"]])
    #expect(index.paths(carrying: "home") == [live.path, "tasks/Other.md"])
}

@Test func titlesResolveToTaDaFilesBeforeNotes() {
    var index = VaultIndex([
        makeItem("Ark.md", "tags: []"),
        makeItem("Meetings/Ark.md", "tags: []"),
        makeItem("projects/Ark.md", "type: project\nstatus: Doing"),
        makeItem("Ta Da/logbook/2026-09/Ark.md", "type: task\nstatus: Done"),
    ])
    #expect(index.items(titled: "ark").map(\.path) == ["projects/Ark.md", "Ark.md", "Meetings/Ark.md", "Ta Da/logbook/2026-09/Ark.md"])
    index.update(makeItem("Ark.md", "type: area"))
    #expect(index.items(titled: "Ark").map(\.path) == ["Ark.md", "projects/Ark.md", "Meetings/Ark.md", "Ta Da/logbook/2026-09/Ark.md"])
}

@Test func taskStatusesFollowTheItemALinkOpens() {
    var index = VaultIndex([
        makeItem("tasks/Live.md", "type: task\nstatus: Doing"),
        makeItem("Ta Da/logbook/2026-09/Live.md", "type: task\nstatus: Done"),
        makeItem("Ta Da/logbook/2026-09/Old.md", "type: task\nstatus: Cancelled"),
        makeItem("Ark.md", "tags: []"),
        makeItem("Ta Da/logbook/2026-09/Ark.md", "type: task\nstatus: Done"),
        makeItem("projects/P.md", "type: project\nstatus: Doing"),
    ])
    #expect(index.taskStatuses == ["live": .doing, "old": .cancelled])
    index.update(makeItem("tasks/Live.md", "type: task\nstatus: Blocked"))
    #expect(index.taskStatuses["live"] == .blocked)
}

@Test func notesAreNeverFiledOrParents() {
    let note = makeItem("Ark.md", "project: \"[[Ta Da MVP]]\"\narea: \"[[Work]]\"")
    let area = makeItem("areas/Work.md", "type: area")
    let index = VaultIndex([project, area, note])
    #expect(note.properties.kind == .note && note.properties.project == nil && note.properties.area == nil)
    #expect(index.parent(of: note) == nil && index.area(of: note) == nil)
    #expect(index.tasks(in: project).isEmpty && index.tasks(in: area).isEmpty && index.projects(in: area).isEmpty)
    #expect(index.notes.map(\.path) == ["Ark.md"])
}

@Test func linksFromAnItemAreEachBodyLinkOnceInOrderResolvedOrNot() {
    let source = makeItem("tasks/Source.md", "type: task\nstatus: Doing\nproject: \"[[Ta Da MVP]]\"",
                          body: "[[Nowhere]] then [[member|m]], [[Ta Da MVP#Goals]], [[NOWHERE]], [[Member]] and ![[Photo.png]]")
    let index = VaultIndex([project, member, source])
    let links = index.links(from: source)
    #expect(links.map { $0.item?.path } == [nil, member.path, project.path])
    #expect(links.map(\.title) == ["Nowhere", "member", "Ta Da MVP"])
    #expect(index.links(from: project).isEmpty)
}
