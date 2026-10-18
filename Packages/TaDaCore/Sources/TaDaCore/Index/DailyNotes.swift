import Foundation

/// Where daily and week notes live and how they're named: `<dailyFolder>/YYYY-MM-DD.md` and
/// `<weekFolder>/GGGG-[W]WW.md`. The two folders can be the same.
public struct DailyNoteNames: Hashable, Sendable {
    public var dailyFolder: String
    public var weekFolder: String

    public init(dailyFolder: String = "Periodic Notes/Daily Notes", weekFolder: String = "Periodic Notes/Weekly Notes") {
        self.dailyFolder = dailyFolder
        self.weekFolder = weekFolder
    }

    public func path(for date: LocalDate) -> String { Self.path(in: dailyFolder, "\(date)") }

    public func path(for week: ISOWeek) -> String { Self.path(in: weekFolder, "\(week)") }

    /// The date a path names, or nil for any other path.
    public func date(atPath path: String) -> LocalDate? {
        Self.name(of: path, in: dailyFolder).flatMap { LocalDate($0) }
    }

    /// The week a path names, or nil for any other path.
    public func week(atPath path: String) -> ISOWeek? {
        guard let name = Self.name(of: path, in: weekFolder) else { return nil }
        guard name.utf8.count == 8, name.dropFirst(4).hasPrefix("-W"),
              let year = Self.digits(name.prefix(4)), let week = Self.digits(name.suffix(2)) else { return nil }
        return ISOWeek(year: year, week: week)
    }

    private static func digits(_ text: Substring) -> Int? {
        text.utf8.allSatisfy { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) } ? Int(text) : nil
    }

    private static func path(in folder: String, _ name: String) -> String {
        folder.isEmpty ? "\(name).md" : "\(folder)/\(name).md"
    }

    /// The filename without `.md` when the path is straight in `folder`, whose case is ignored.
    private static func name(of path: String, in folder: String) -> String? {
        let prefix = folder.isEmpty ? "" : folder + "/"
        guard path.hasSuffix(".md") else { return nil }
        var rest = Substring(path)
        if !prefix.isEmpty {
            guard let range = path.range(of: prefix, options: [.caseInsensitive, .anchored]) else { return nil }
            rest = path[range.upperBound...]
        }
        let name = rest.dropLast(3)
        return name.contains("/") ? nil : String(name)
    }
}

/// Daily and week notes are plain notes found by their name, in the folder in any case. A note renamed away from its
/// name isn't found.
extension VaultIndex {
    public func dailyNote(for date: LocalDate, names: DailyNoteNames = DailyNoteNames()) -> Item? {
        note(titled: "\(date)") { names.date(atPath: $0) == date }
    }

    public func weekNote(for week: ISOWeek, names: DailyNoteNames = DailyNoteNames()) -> Item? {
        note(titled: "\(week)") { names.week(atPath: $0) == week }
    }

    /// The unchecked boxes in a file: those with the Open state (`[ ]`, `[/]`, `[>]`, `[<]`).
    public func openCheckboxCount(_ item: Item) -> Int {
        item.checkboxes.count { $0.state == .open }
    }

    private func note(titled title: String, where matches: (String) -> Bool) -> Item? {
        items(titled: title).first { $0.properties.kind == .note && !$0.isLogged && matches($0.path) }
    }
}
