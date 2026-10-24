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
    return LoadedVault(name: name, files: files, index: VaultIndex(files.compactMap(\.item)))
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
            return [
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
        },
    ] as [String: Any], to: "queries.json")
}
