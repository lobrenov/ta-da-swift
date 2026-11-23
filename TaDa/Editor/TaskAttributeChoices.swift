// The choices behind a subtask's `>` date and `@` parent: the typed query's rows for the Mac's popup menus and the
// iPhone's lists above the keyboard bar, and the text a pick writes. LiveEditor shows them.
import Foundation
import TaDaCore

/// A row of the `>` date menu.
struct DateChoice: Equatable, Identifiable {
    enum Kind: Equatable {
        /// The day the typed phrase gives.
        case typed
        case today, tomorrow, nextWeek
        /// Opens the calendar.
        case pick
    }

    let kind: Kind
    /// Nil for Pick a date….
    let date: LocalDate?

    var id: Kind { kind }

    var title: String {
        switch kind {
        case .typed: date?.formatted(.wideWeekdayDayMonth) ?? ""
        case .today: "Today"
        case .tomorrow: "Tomorrow"
        case .nextWeek: "Next week"
        case .pick: "Pick a date…"
        }
    }

    /// The day the row sets, on the right of the quick rows.
    var detail: String? { kind == .typed ? nil : date?.formatted(.weekdayDayMonth) }

    /// The attribute a pick writes: `>2026-10-02`.
    var token: String? { date.map { ">\($0)" } }

    /// The token and a space, which a pick in the typed query writes.
    var markdown: String? { token.map { $0 + " " } }

    /// The typed phrase's day first (highlighted), then Today, Tomorrow and Next week that it doesn't repeat, then
    /// Pick a date… when `includesPick`.
    static func choices(query: String, today: LocalDate, firstWeekday: Int, order: DayOrder, includesPick: Bool) -> [DateChoice] {
        let typed = DatePhrase.parse(query, today: today, order: order, firstWeekday: firstWeekday)
        var rows = typed.map { [DateChoice(kind: .typed, date: $0)] } ?? []
        for (kind, date) in [(Kind.today, today), (.tomorrow, today.adding(days: 1)), (.nextWeek, today.nextWeek(firstWeekday: firstWeekday))]
        where date != typed {
            rows.append(DateChoice(kind: kind, date: date))
        }
        if includesPick { rows.append(DateChoice(kind: .pick, date: nil)) }
        return rows
    }
}

extension DateChoice {
    /// The row ↵ picks: the typed phrase's day; none when the text gives no day, so ↵ is a newline.
    static func highlight(in choices: [DateChoice]) -> Int? { choices.first?.kind == .typed ? 0 : nil }
}

/// A row of the `@` parent menu: an area, a project, or New project for the typed name.
struct ParentChoice: Equatable, Identifiable {
    enum Kind: Equatable {
        case area
        case project(fraction: Double, ongoing: Bool, open: Int)
        case new
        /// Takes the parent off a line (in the menu a click opens).
        case remove
    }

    let title: String
    let kind: Kind

    var id: String {
        switch kind {
        case .area: "area:\(title)"
        case .project: "project:\(title)"
        case .new: "new:\(title)"
        case .remove: "remove"
        }
    }

    static let remove = ParentChoice(title: "Remove parent", kind: .remove)

    /// The attribute a pick writes: `@[[Title]]`.
    var token: String { "@[[\(title)]]" }

    /// The token and a space, which a pick in the typed query writes.
    var markdown: String { token + " " }

    /// The areas and active projects whose titles contain `query`: the projects without an area, then each area followed by
    /// its projects, as the move menu lists them; no Loose tasks. With a name typed, New project “name” ends the list.
    static func choices(index: VaultIndex, query: String) -> [ParentChoice] {
        let name = query.trimmingCharacters(in: .whitespaces)
        func matches(_ title: String) -> Bool { name.isEmpty || title.localizedStandardContains(name) }
        func project(_ progress: ProjectProgress) -> ParentChoice? {
            matches(progress.project.title)
                ? ParentChoice(title: progress.project.title,
                               kind: .project(fraction: progress.fraction, ongoing: progress.isOngoing, open: progress.open)) : nil
        }
        var rows = index.looseProjects().compactMap(project)
        for entry in index.areaProjects() {
            if matches(entry.area.title) { rows.append(ParentChoice(title: entry.area.title, kind: .area)) }
            rows += entry.projects.compactMap(project)
        }
        if !name.isEmpty { rows.append(ParentChoice(title: name, kind: .new)) }
        return rows
    }
}

enum TaskAttributeText {
    /// The range to delete to remove an attribute: its `source` at `range` in `text`, with the space core's line writers take
    /// with it (the one before it, else the one after it when it starts the text after the box). Nil when the text there isn't
    /// `source` on a subtask line.
    static func removalRange(of source: String, isDue: Bool, at range: NSRange, in text: String) -> NSRange? {
        let text = text as NSString
        guard NSMaxRange(range) <= text.length, text.substring(with: range) == source else { return nil }
        var start = 0, end = 0, contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: range)
        let old = text.substring(with: NSRange(location: start, length: contentsEnd - start))
        guard let new = isDue ? SubtaskLine.settingDue(nil, inLine: old) : SubtaskLine.settingParent(nil, inLine: old) else { return nil }
        let (before, after) = (old as NSString, new as NSString)
        var prefix = 0
        while prefix < after.length, before.character(at: prefix) == after.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < after.length - prefix, before.character(at: before.length - 1 - suffix) == after.character(at: after.length - 1 - suffix) { suffix += 1 }
        let removed = NSRange(location: start + prefix, length: before.length - prefix - suffix)
        guard removed.length > 0, after.length == before.length - removed.length else { return nil }
        return removed
    }
}

extension ParentChoice {
    /// The row ↵ picks: the first; none when the only row is New project, which needs a click or an arrow first.
    static func highlight(in choices: [ParentChoice]) -> Int? {
        choices.contains { $0.kind != .new } ? 0 : nil
    }
}
