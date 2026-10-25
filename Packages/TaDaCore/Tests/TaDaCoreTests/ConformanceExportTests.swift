import Foundation
import Testing
@testable import TaDaCore

/// Writes `Fixtures/Conformance/read.json` and `queries.json` for the TypeScript port to check against. The files are
/// rewritten on every run, so `git diff` shows any change in behaviour.
private let today = LocalDate("2026-10-02")!
private let conformanceFolder = URL(filePath: #filePath).deletingLastPathComponent()
    .appending(path: "Fixtures/Conformance").standardized

private struct LoadedVault {
    let name: String
    /// Every `.md` file under the vault, by path, and its parsed item.
    let files: [(path: String, item: Item?)]
    let folder: URL
    let index: VaultIndex
}

private func loadVault(_ name: String, at folder: URL) throws -> LoadedVault {
    let base = folder.path + "/"
    let urls = (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.allObjects ?? [])
        .compactMap { $0 as? URL }.filter { $0.pathExtension.lowercased() == "md" }
    let files = try urls.map { url in
        let path = String(url.path.dropFirst(base.count))
        return (path: path, item: Item(parsing: try String(contentsOf: url, encoding: .utf8), path: path))
    }.sorted { $0.path < $1.path }
    let indexed = Set(Vault(root: folder).markdownPaths())
    return LoadedVault(name: name, files: files, folder: folder, index: VaultIndex(files.filter { indexed.contains($0.path) }.compactMap(\.item)))
}

private func vaults() throws -> [LoadedVault] {
    [try loadVault("DesignVault", at: sampleVault),
     try loadVault("HomeVault", at: conformanceFolder.appending(path: "HomeVault"))]
}

private func write(_ object: Any, to name: String) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try (data + Data("\n".utf8)).write(to: conformanceFolder.appending(path: name))
}

private func orNull(_ value: Any?) -> Any { value ?? NSNull() }

private func json(_ link: WikiLink) -> [String: Any] {
    ["target": link.target, "heading": orNull(link.heading), "alias": orNull(link.alias)]
}

private func json(_ box: Checkbox) -> [String: Any] {
    ["marker": String(box.marker), "lineIndex": box.lineIndex, "column": box.column, "state": "\(box.state)"]
}

private func json(_ warning: Warning) -> [String: Any] {
    switch warning {
    case let .invalidYAML(problem, line): ["case": "invalidYAML", "problem": problem, "line": orNull(line)]
    case .missingStatus: ["case": "missingStatus"]
    case let .unknownStatus(value): ["case": "unknownStatus", "value": value]
    case let .invalidDate(key, value): ["case": "invalidDate", "key": key, "value": value]
    case let .invalidProject(value): ["case": "invalidProject", "value": value]
    case let .unexpectedValue(key): ["case": "unexpectedValue", "key": key]
    case let .unresolvedProject(value): ["case": "unresolvedProject", "value": value]
    case let .unresolvedArea(value): ["case": "unresolvedArea", "value": value]
    case let .areaIgnored(value): ["case": "areaIgnored", "value": value]
    }
}

private func json(_ item: Item) -> [String: Any] {
    let p = item.properties
    return [
        "path": item.path, "title": item.title, "kind": p.kind.rawValue, "status": p.status.rawValue,
        "area": orNull(p.area.map(json)), "project": orNull(p.project.map(json)),
        "createdDate": orNull(p.createdDate?.description), "completedDate": orNull(p.completedDate?.description),
        "dueDate": orNull(p.dueDate?.description), "deadline": orNull(p.deadline?.description),
        "repeat": orNull(p.repeatRule), "tags": p.tags.map(\.name),
        "summary": orNull(item.summary), "hasNote": item.hasNote,
        "subtasks": ["done": item.subtasks.done, "total": item.subtasks.total],
        "checkboxes": item.checkboxes.map(json), "links": item.links.map(json), "embeds": item.embeds.map(json),
        "tagUses": item.tags.map { ["tag": $0.tag.name, "inFrontmatter": $0.inFrontmatter, "inBody": $0.inBody] },
        "warnings": item.warnings.map(json), "isLogged": item.isLogged, "isNotePath": Item.isNotePath(item.path),
    ]
}

private func paths(_ items: [Item], sorted: Bool = true) -> [String] {
    let paths = items.map(\.path)
    return sorted ? paths.sorted() : paths
}

private func entries(_ entries: [AgendaEntry]) -> [[String: Any]] {
    entries.map { ["path": $0.item.path, "date": $0.date.description, "kind": "\($0.kind)"] }
}

private func progress(_ list: [ProjectProgress]) -> [[String: Any]] {
    list.map { ["path": $0.project.path, "done": $0.done, "total": $0.total] }
}

@Test func writeConformanceFiles() throws {
    let loaded = try vaults()
    try write([
        "today": today.description,
        "vaults": loaded.map { vault in
            ["name": vault.name,
             "files": vault.files.map { ["path": $0.path, "item": orNull($0.item.map(json))] as [String: Any] }]
        },
    ] as [String: Any], to: "read.json")

    try write([
        "today": today.description,
        "vaults": loaded.map { vault -> [String: Any] in
            let index = vault.index
            let all = Array(index.items.values).sorted { $0.path < $1.path }
            let marks = index.dayMarks(from: LocalDate("2026-10-01")!, through: LocalDate("2026-10-31")!)
            var queries: [String: Any] = [
                "name": vault.name,
                "liveTasks": paths(index.tasks), "projects": paths(index.projects), "areas": paths(index.areas),
                "notes": paths(index.notes), "logged": paths(index.logged),
                "today": paths(index.today(today), sorted: false),
                "overdue": paths(all.filter { index.isOverdue($0, today: today) }),
                "upcoming": entries(index.upcoming(after: today)),
                "agendaWeek": entries(index.agendaWeek(today.isoWeek)),
                "dayMarks": marks.keys.sorted().map {
                    ["date": $0.description, "hasOpenTasks": marks[$0]!.hasOpenTasks, "hasOpenBoxes": marks[$0]!.hasOpenBoxes]
                },
                "loose": paths(index.loose(), sorted: false),
                "activeProjects": progress(index.activeProjects()),
                "looseProjects": progress(index.looseProjects()),
                "areaProjects": index.areaProjects().map { ["area": $0.area.path, "projects": progress($0.projects)] },
                "parents": Dictionary(uniqueKeysWithValues: all.map { ($0.path, orNull(index.parent(of: $0)?.path)) }),
                "warnings": Dictionary(uniqueKeysWithValues: all.compactMap { item -> (String, [[String: Any]])? in
                    let warnings = index.warnings(for: item)
                    return warnings.isEmpty ? nil : (item.path, warnings.map(json))
                }),
            ]
            queries.merge(b1Queries(vault)) { _, new in new }
            return queries
        },
    ] as [String: Any], to: "queries.json")
}

// MARK: B1 queries

private func json(_ node: TagNode) -> [String: Any] {
    ["tag": node.tag.name, "path": node.tag.path, "count": node.count, "children": node.children.map(json)]
}

private func allNodes(_ nodes: [TagNode]) -> [TagNode] { nodes.flatMap { [$0] + allNodes($0.children) } }

private func json(_ node: FolderNode) -> [String: Any] {
    ["path": node.path, "name": node.name, "count": node.count, "children": node.children.map(json)]
}

private func allFolders(_ nodes: [FolderNode]) -> [String] { nodes.flatMap { [$0.path] + allFolders($0.children) } }

private func json(_ section: ListSection) -> [String: Any] {
    let kind: [String: Any]
    switch section.kind {
    case let .status(status): kind = ["case": "status", "value": status.rawValue]
    case let .date(group): kind = ["case": "date", "value": group.rawValue]
    case .open: kind = ["case": "open", "value": NSNull()]
    case .completed: kind = ["case": "completed", "value": NSNull()]
    }
    return ["title": section.title, "kind": kind, "tasks": section.tasks.map(\.path)]
}

private func b1Queries(_ vault: LoadedVault) -> [String: Any] {
    let index = vault.index
    let tree = index.tagTree()
    let nodes = allNodes(tree)
    func browser(_ tag: TaDaCore.Tag?) -> [String: Any] {
        let b = index.tagBrowser(tag)
        return ["areasAndProjects": b.areasAndProjects.map(\.path),
                "groups": b.groups.map { ["parent": orNull($0.parent?.path), "tasks": $0.tasks.map(\.path)] as [String: Any] },
                "completed": b.completed.map(\.path), "notes": b.notes.map(\.path), "children": b.children.map(json)]
    }
    var browsers: [String: Any] = ["": browser(nil)]
    for node in nodes { browsers[node.tag.path] = browser(node.tag) }
    let folders = index.folderTree()
    var notesIn: [String: Any] = ["": index.notes(in: "").map(\.path)]
    for folder in allFolders(folders) { notesIn[folder] = index.notes(in: folder).map(\.path) }
    func sections(_ tasks: [Item]) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: Grouping.allCases.map {
            ($0.rawValue, ListSection.sections(tasks, by: $0, today: today).map(json) as Any)
        })
    }
    let tasksByPath = index.tasks.sorted { $0.path < $1.path }

    let trashed = Vault(root: vault.folder).trashedItems().sorted { $0.item.path < $1.item.path }
    let live: (Item) -> Bool = { !$0.path.hasPrefix(".trash/") }
    func ids(_ items: [TrashedItem]) -> [String] { items.map(\.item.path) }
    var tasksOf: [String: Any] = [:], contentsOf: [String: Any] = [:]
    var tasksOfTrashed: [String: Any] = [:], contentsOfTrashed: [String: Any] = [:]
    for project in (index.projects + trashed.map(\.item).filter { $0.properties.kind == .project }).sorted(by: { $0.path < $1.path }) {
        let found = ids(TrashedItem.tasks(of: project, in: trashed))
        if !found.isEmpty { if live(project) { tasksOf[project.path] = found } else { tasksOfTrashed[project.path] = found } }
    }
    for area in (index.areas + trashed.map(\.item).filter { $0.properties.kind == .area }).sorted(by: { $0.path < $1.path }) {
        let found = TrashedItem.contents(of: area, in: trashed)
        guard !found.projects.isEmpty || !found.tasks.isEmpty else { continue }
        let value: [String: Any] = ["projects": ids(found.projects), "tasks": ids(found.tasks)]
        if live(area) { contentsOf[area.path] = value } else { contentsOfTrashed[area.path] = value }
    }
    return [
        "tagTree": tree.map(json),
        "tagged": Dictionary(uniqueKeysWithValues: nodes.map { ($0.tag.path, index.items(tagged: $0.tag).map(\.path)) }),
        "untagged": index.untagged().map(\.path),
        "tagBrowsers": browsers,
        "tagSuggestions": Dictionary(uniqueKeysWithValues: ["", "c", "ca", "work/"].map {
            ($0, index.tagSuggestions($0).map(json))
        }),
        "folderTree": folders.map(json),
        "notesIn": notesIn,
        "sections": ["today": sections(index.today(today)), "loose": sections(index.loose())],
        "tagFilterTags": TagFilter.tags(of: tasksByPath).map { ["tag": $0.tag.name, "count": $0.count] as [String: Any] },
        "trash": trashed.map { ["path": $0.item.path, "item": json($0.item)] as [String: Any] },
        "trashTasksOf": tasksOf, "trashContentsOf": contentsOf,
        "trashTasksOfTrashed": tasksOfTrashed, "trashContentsOfTrashed": contentsOfTrashed,
    ]
}

// MARK: O2 writes

private func fixtureText(_ vault: String, _ path: String) -> String {
    let folder = vault == "DesignVault" ? sampleVault : conformanceFolder.appending(path: "HomeVault")
    return try! String(contentsOf: folder.appending(path: path), encoding: .utf8)
}

/// Frontmatter inputs: inline cases for each shape the editors handle, then real files.
private let frontmatterInputs: [(label: String, text: String)] = [
    ("task", "---\ntype: task\nstatus: Not Started\n---\n"),
    ("task with body", "---\ntype: task\nstatus: Doing\ndueDate: 2026-10-05\nproject: \"[[Garden]]\"\n---\nBody text.\n\n- [ ] one\n"),
    ("comments", "---\n# a comment\ntype: task # trailing\nstatus: Doing   # c\ndueDate: 2026-10-05 # d\n# end\n---\nBody\n"),
    ("no trailing newline", "---\ntype: task\nstatus: Doing\n---\nBody"),
    ("no newline after fence", "---\ntype: task\nstatus: Doing\n---"),
    ("no frontmatter", "Just text\n- [ ] box\n"),
    ("empty file", ""),
    ("empty frontmatter", "---\n---\n"),
    ("empty keys", "---\ntype: task\nstatus:\nproject:\ncompletedDate:\ntags:\n---\n"),
    ("flow tags", "---\ntype: task\nstatus: Doing\ncreatedDate: 2026-09-01\ntags: [a, \"b c\", d]\n---\n"),
    ("block tags", "---\ntype: task\ntags:\n  - a\n  - \"b c\"\ncreatedDate: 2026-09-01\n---\n"),
    ("string tags", "---\ntype: task\ntags: a, b\n---\n"),
    ("empty flow tags", "---\ntype: note\ncreatedDate: 2026-09-01\ntags: []\n---\nnote\n"),
    ("tags with comment", "---\ntype: task\ntags: [a, # c\n  b]\n---\n"),
    ("tags block scalar", "---\ntype: task\ntags: |\n  a\n---\n"),
    ("both parents", "---\ntype: task\nstatus: Doing\nproject: \"[[Garden]]\"\narea: \"[[Home]]\"\n---\n"),
    ("area only", "---\ntype: task\nstatus: Doing\narea: Home\n---\n"),
    ("quoted values", "---\ntype: task\nstatus: \"Doing\"\nrepeat: 'Weekly · Fri'\ntitle: a: b\n---\n"),
    ("done task", "---\ntype: task\nstatus: Done\ncompletedDate: 2026-10-01\nproject: \"[[Garden]]\"\n---\n"),
    ("unknown keys", "---\ntype: project\nstatus: Doing\ncontexts: [x]\nfoo:\n  - 1\n  - 2\nbar: baz\n---\nBody\n"),
    ("tag-like first line", "#hash\n---\ntype: task\n---\n"),
    ("home buy seed", fixtureText("HomeVault", "Ta Da/tasks/Buy seed.md")),
    ("home fix tap", fixtureText("HomeVault", "Ta Da/tasks/Fix tap.md")),
    ("home call plumber", fixtureText("HomeVault", "Ta Da/tasks/Call plumber.md")),
    ("home odd status", fixtureText("HomeVault", "Ta Da/tasks/Odd status.md")),
    ("home garden", fixtureText("HomeVault", "Ta Da/projects/Garden.md")),
    ("home area", fixtureText("HomeVault", "Ta Da/areas/Home.md")),
    ("home inbox", fixtureText("HomeVault", "Inbox.md")),
    ("home stray", fixtureText("HomeVault", "Ta Da/tasks/Stray.md")),
    ("home broken yaml", fixtureText("HomeVault", "Ta Da/tasks/Broken yaml.md")),
    ("design pick a test framework", fixtureText("DesignVault", "Ta Da/tasks/Pick a test framework.md")),
    ("design resolve cabin", fixtureText("DesignVault", "Ta Da/tasks/Resolve the cabin payback.md")),
    ("design ta da mvp", fixtureText("DesignVault", "Ta Da/projects/Ta Da MVP.md")),
    ("design not a task", fixtureText("DesignVault", "notes/Not a task.md")),
]

/// Checkbox inputs: lists, nesting, quotes, callouts, code and icon markers.
private let checkboxInputs: [(label: String, text: String)] = [
    ("flat list", "---\ntype: task\n---\n- [ ] a\n- [x] b\n- [-] c\n- [/] d\n- [>] e\n- [<] f\n- [X] g\n- [?] h\n"),
    ("nested", "- [ ] a\n  - [x] b\n    - [ ] c\n1. [ ] numbered\n* [x] star\n+ [ ] plus\n"),
    ("quote and callout", "> [!note] Title\n> - [ ] in callout\n> - [x] done in callout\n\n> quote\n> - [ ] in quote\n"),
    ("code and text", "```\n- [ ] in code\n```\n- [y] not a box\n- [ ]no space\n- [ ] real\n"),
    ("no trailing newline", "- [ ] last"),
    ("home buy seed", fixtureText("HomeVault", "Ta Da/tasks/Buy seed.md")),
    ("home daily note", fixtureText("HomeVault", "Periodic Notes/Daily Notes/2026-10-03.md")),
    ("design daily note", fixtureText("DesignVault", "Periodic Notes/Daily Notes/2026-10-01.md")),
    ("design create a system testing plan", fixtureText("DesignVault", "Ta Da/tasks/Create a system testing plan.md")),
    ("design weekly note", fixtureText("DesignVault", "Periodic Notes/Weekly Notes/2026-W40.md")),
]

private func propertyValue(_ kind: String, _ value: Any) -> (PropertyValue, [String: Any]) {
    let arg: [String: Any] = ["kind": kind, "value": value]
    switch kind {
    case "text": return (.text(value as! String), arg)
    case "date": return (.date(LocalDate(value as! String)!), arg)
    case "link": return (.link(title: value as! String), arg)
    default: return (.list(value as! [String]), arg)
    }
}

@Test func writeConformanceWrites() throws {
    var cases: [[String: Any]] = []
    func add(_ op: String, _ label: String, _ args: [String: Any], input: String?, _ run: (String) -> Any?) {
        guard let input else {
            cases.append(["name": "\(op) \(label)", "op": op, "args": args, "input": NSNull(), "expected": orNull(run(""))])
            return
        }
        for (suffix, text) in [(" (LF)", input), (" (CRLF)", input.replacingOccurrences(of: "\n", with: "\r\n"))] {
            cases.append(["name": "\(op) \(label)\(suffix)", "op": op, "args": args, "input": text, "expected": orNull(run(text))])
        }
    }
    func tag(_ name: String) -> TaDaCore.Tag { TaDaCore.Tag(name)! }
    let coreLabels: Set<String> = ["task", "task with body", "comments", "no trailing newline", "no frontmatter", "empty file",
                                   "empty keys", "flow tags", "block tags", "string tags", "tags with comment", "both parents",
                                   "home buy seed", "home odd status", "home inbox", "design resolve cabin"]
    let core = frontmatterInputs.filter { coreLabels.contains($0.label) }

    // Completion
    for (label, text) in core {
        for status in [Status.done, .cancelled, .notStarted, .doing] {
            add("Completion.setStatus", "\(label) -> \(status.rawValue)", ["status": status.rawValue], input: text) {
                Completion.setStatus(status, in: $0, today: today)
            }
        }
    }
    for (label, text) in core.prefix(4) {
        for status in [Status.notStarted, .done, .cancelled] {
            add("Completion.toggle", "\(label) from \(status.rawValue)", ["current": status.rawValue], input: text) {
                Completion.toggle(status, in: $0, today: today)
            }
        }
    }

    // ChecklistEditor
    for (label, text) in checkboxInputs {
        let boxes = Item(parsing: text, path: "Inbox.md")?.checkboxes ?? []
        func box(_ line: Int, in text: String) -> Checkbox? {
            Item(parsing: text, path: "Inbox.md")?.checkboxes.first { $0.lineIndex == line }
        }
        for found in boxes {
            add("ChecklistEditor.click", "\(label) line \(found.lineIndex)", ["lineIndex": found.lineIndex], input: text) { text in
                box(found.lineIndex, in: text).flatMap { ChecklistEditor.click($0, in: text) }
            }
        }
        for found in boxes.prefix(1) {
            for marker in ["x", " ", "-", "y", "é"] {
                add("ChecklistEditor.setMarker", "\(label) line \(found.lineIndex) to \(marker)",
                    ["lineIndex": found.lineIndex, "marker": marker], input: text) { text in
                    box(found.lineIndex, in: text).flatMap { ChecklistEditor.setMarker(Character(marker), of: $0, in: text) }
                }
            }
        }
        add("ChecklistEditor.setMarker", "\(label) missing line", ["lineIndex": 999, "marker": "x"], input: text) { _ in nil as String? }
    }

    // TagEditor
    for (label, text) in core {
        for name in ["new", "Café", "A"] {
            add("TagEditor.addTag", "\(label) \(name)", ["tag": name], input: text) { FrontmatterEditor.addTag(tag(name), in: $0) }
        }
        for name in ["a", "B C", "missing"] {
            add("TagEditor.removeTag", "\(label) \(name)", ["tag": name], input: text) { FrontmatterEditor.removeTag(tag(name), in: $0) }
        }
    }

    // Parent
    for (label, text) in core {
        add("Parent.set", "\(label) project Garden", ["parent": ["kind": "project", "title": "Garden"]], input: text) {
            Parent.set(.project("Garden"), in: $0)
        }
        add("Parent.set", "\(label) area Home", ["parent": ["kind": "area", "title": "Home"]], input: text) {
            Parent.set(.area("Home"), in: $0)
        }
        add("Parent.set", "\(label) none", ["parent": NSNull()], input: text) { Parent.set(nil, in: $0) }
    }

    // FrontmatterEditor
    let sets: [(key: String, kind: String, value: Any)] = [
        ("status", "text", "Doing"), ("status", "text", "yes"), ("repeat", "text", "a: b # c"),
        ("dueDate", "date", "2026-10-09"), ("project", "link", "My Project"), ("tags", "list", ["a", "b c"]),
        ("tags", "list", [String]()), ("newKey", "text", "value"),
    ]
    for (label, text) in core {
        for set in sets {
            let (value, arg) = propertyValue(set.kind, set.value)
            add("FrontmatterEditor.set", "\(label) \(set.key)=\(set.value)", ["key": set.key, "value": arg], input: text) {
                FrontmatterEditor.set(set.key, to: value, in: $0)
            }
        }
        for key in ["status", "tags", "missing"] {
            add("FrontmatterEditor.clear", "\(label) \(key)", ["key": key], input: text) { FrontmatterEditor.clear(key, in: $0) }
        }
    }
    let tops: [[(key: String, kind: String, value: Any)]] = [
        [("type", "text", "task"), ("status", "text", "Not Started"), ("createdDate", "date", "2026-10-02")],
        [("project", "link", "Garden"), ("tags", "list", ["x"])],
    ]
    for (label, text) in core {
        for (n, keys) in tops.enumerated() {
            let converted = keys.map { (key: $0.key, value: propertyValue($0.kind, $0.value)) }
            add("FrontmatterEditor.insertAtTop", "\(label) set \(n + 1)",
                ["keys": converted.map { ["key": $0.key, "value": $0.value.1] as [String: Any] }], input: text) {
                FrontmatterEditor.insertAtTop(converted.map { (key: $0.key, value: $0.value.0) }, in: $0)
            }
        }
    }

    // NewFile
    func tags(_ names: [String]) -> [TaDaCore.Tag] { names.compactMap { TaDaCore.Tag($0) } }
    let tagSets: [[String]] = [[], ["work/admin"], ["Café", "two words", "#hash", "a", "A"], ["a, b", "yes", "-x"]]
    for names in tagSets {
        let label = "tags \(names)"
        add("NewFile.area", label, ["tags": names], input: nil) { _ in NewFile.area(tags: tags(names), today: today) }
        add("NewFile.note", label, ["tags": names], input: nil) { _ in NewFile.note(tags: tags(names), today: today) }
        for area in [nil, "Home", "Say \"hi\": now"] {
            add("NewFile.project", "area \(area ?? "nil") \(label)", ["area": orNull(area), "tags": names], input: nil) { _ in
                NewFile.project(area: area, tags: tags(names), today: today)
            }
        }
        for (project, area) in [(nil, nil), ("Garden", nil), (nil, "Home"), ("Garden", "Home"), ("Say \"hi\": now", nil)] as [(String?, String?)] {
            add("NewFile.task", "project \(project ?? "nil") area \(area ?? "nil") \(label)",
                ["project": orNull(project), "area": orNull(area), "tags": names], input: nil) { _ in
                NewFile.task(project: project, area: area, tags: tags(names), today: today)
            }
        }
    }

    // FileNaming
    let titles = ["Plain title", "Game Jam: Starfall", "a/b\\c|d", "Q? \"quoted\" <x> *y*", "[[Link]] #tag ^block", "  spaced   out  ", ".hidden",
                  "...", "", "   ", "Tab\tand\nnewline", "Café ☕️ 日本", String(repeating: "long ", count: 60), String(repeating: "é", count: 150), "Untitled"]
    for title in titles {
        add("FileNaming.sanitise", "\(title.prefix(30).debugDescription)", ["title": title], input: nil) { _ in FileNaming.sanitise(title) }
    }
    let existings: [[String]] = [[], ["Note.md"], ["note.md", "Note 2.md"], ["Note 2.md"], ["NOTE.MD", "note 2.md", "NOTE 3.md"]]
    for title in ["Note", "note", "Game Jam: Starfall", "", "Café"] {
        for existing in existings {
            add("FileNaming.filename", "\(title.debugDescription) existing \(existing)", ["title": title, "existing": existing], input: nil) { _ in
                FileNaming.filename(for: title, existing: Set(existing))
            }
        }
    }

    // DatePhrase
    let phrases = ["today", "tod", "t", "TODAY", "  today ", "tomorrow", "tmr", "fri", "friday", "f", "next fri", "this friday", "on fri",
                   "fri 3pm", "friday at 15:00", "fri 3 pm", "fri at 3", "tomorrow at 9", "fri 3", "tomorrow 15:", "tu", "th", "w", "s", "su",
                   "m", "weekend", "wknd", "next week", "n", "next", "next wk", "next month", "end of month", "eom", "e", "3d", "3 days",
                   "in 3 days", "+3", "2w", "in 2 weeks", "1m", "1y", "25", "25th", "the 25th", "2", "1st", "31", "25/12", "25.12", "25-12",
                   "dec 25", "25 dec", "december 25th", "25th of december", "Dec 25, 2026", "dec. 25", "25dec", "25/12/27", "25/12/2027",
                   "2027-12-25", "1/1", "13/10", "12/10", "29/2", "sept 3", "5/12", "12/25", "1/1/2020", "dec 3 pm", "",
                   "  ", "xyz", "31/2", "0", "32", "3pm", "ma", "25 ju", "this", "13/13", "2027-12", "1/1/123", "9999y", "2027-12-251", "25/12/2"]
    for phrase in phrases {
        add("DatePhrase.parse", "\(phrase.debugDescription) dayMonth Sunday", ["phrase": phrase, "order": "dayMonth", "firstWeekday": 1], input: nil) { _ in
            DatePhrase.parse(phrase, today: today, order: .dayMonth, firstWeekday: 1)?.description
        }
    }
    for phrase in phrases.prefix(16) {
        add("DatePhrase.parse", "\(phrase.debugDescription) monthDay Monday", ["phrase": phrase, "order": "monthDay", "firstWeekday": 2], input: nil) { _ in
            DatePhrase.parse(phrase, today: today, order: .monthDay, firstWeekday: 2)?.description
        }
    }

    let names = cases.map { $0["name"] as! String }
    #expect(Set(names).count == names.count, "duplicate case names")
    try write(["today": today.description, "cases": cases] as [String: Any], to: "writes.json")
}
