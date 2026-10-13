import Foundation

/// An incomplete reminder, read from the device's Reminders lists. Ta Da never writes it.
public struct ExternalReminder: Hashable, Sendable, Identifiable {
    public var identifier: String
    public var title: String
    /// The day it's due; reminders without one never show.
    public var due: LocalDate?
    /// The list's colour as `#RRGGBB`.
    public var color: String

    public init(identifier: String, title: String, due: LocalDate?, color: String) {
        self.identifier = identifier
        self.title = title
        self.due = due
        self.color = color
    }

    public var id: String { identifier }

    /// Due today or earlier.
    public func isInToday(today: LocalDate) -> Bool {
        due.map { $0 <= today } ?? false
    }

    /// Due before today.
    public func isOverdue(today: LocalDate) -> Bool {
        due.map { $0 < today } ?? false
    }

    /// The day it shows in Upcoming: its due date, when that's after `today`.
    public func upcomingDate(after today: LocalDate) -> LocalDate? {
        due.flatMap { $0 > today ? $0 : nil }
    }

    /// Today's reminders: due today or earlier, by due date, then title.
    public static func today(_ reminders: [ExternalReminder], today: LocalDate) -> [ExternalReminder] {
        reminders.filter { $0.isInToday(today: today) }.sorted(by: byDueOrder)
    }

    /// Upcoming's reminders on their due dates after `today`, keyed by day, each day by title.
    public static func upcoming(_ reminders: [ExternalReminder], after today: LocalDate) -> [LocalDate: [ExternalReminder]] {
        Dictionary(grouping: reminders.filter { $0.upcomingDate(after: today) != nil }) { $0.due! }
            .mapValues { $0.sorted(by: byDueOrder) }
    }

    private static func byDueOrder(_ a: ExternalReminder, _ b: ExternalReminder) -> Bool {
        if let x = a.due, let y = b.due, x != y { return x < y }
        let order = a.title.localizedStandardCompare(b.title)
        return order == .orderedSame ? a.id < b.id : order == .orderedAscending
    }
}
