// What Settings ▸ Daily notes offers on both platforms: a typed folder tidied, the vault's folders, and the notes a template can be.
import Foundation
import TaDaCore

extension AppModel {
    /// A typed folder without surrounding whitespace or slashes; empty is the vault's top level.
    nonisolated static func cleanedFolder(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The paths of the vault's note folders, nested ones included.
    var noteFolderPaths: [String] {
        func paths(_ nodes: [FolderNode]) -> [String] { nodes.flatMap { [$0.path] + paths($0.children) } }
        return paths(folderTree)
    }

    /// The notes a template can be, by path, less the daily and week notes themselves.
    var templateChoices: [Item] {
        let names = dailyNoteNames
        return index.notes
            .filter { names.date(atPath: $0.path) == nil && names.week(atPath: $0.path) == nil }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// A daily note's file name for today, e.g. `2026-10-02.md`.
    var dailyNoteExample: String { "\(today).md" }

    /// A week note's file name for today's week, e.g. `2026-W40.md`.
    var weekNoteExample: String { "\(today.isoWeek).md" }
}
