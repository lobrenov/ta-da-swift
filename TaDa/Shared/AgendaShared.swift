// What the Mac's and the iPhone's Agenda share: a day's dots, the labels of its rows, and the month's anchor day.
import SwiftUI
import TaDaCore

/// A day's dots, in order: the ring, then `due`, then `muted`. `marks` stands in for the model's when the day is
/// outside the range it keeps marks for.
struct AgendaDots: View {
    let model: AppModel
    let day: LocalDate
    let size: CGFloat
    var marks: DayMarks?
    @Environment(\.theme) private var theme

    var body: some View {
        let marks = marks ?? model.agendaMarks[day]
        HStack(spacing: 2) {
            if marks?.hasOpenBoxes == true { Circle().strokeBorder(theme.color(\.due)).frame(width: size, height: size) }
            if marks?.hasOpenTasks == true { Circle().fill(theme.color(\.due)).frame(width: size, height: size) }
            if Self.hasEvents(model, day) { Circle().fill(theme.color(\.muted)).frame(width: size, height: size) }
        }
        .frame(height: size)
        .accessibilityHidden(true)
    }

    private static func hasEvents(_ model: AppModel, _ day: LocalDate) -> Bool {
        model.hasEvents(on: day) || !model.reminders(on: day).isEmpty
    }

    /// What the dots mean, for VoiceOver: ", open items in the note, tasks due, events".
    static func spoken(_ model: AppModel, _ day: LocalDate, marks: DayMarks? = nil) -> String {
        let marks = marks ?? model.agendaMarks[day]
        return (marks?.hasOpenBoxes == true ? ", open items in the note" : "") + (marks?.hasOpenTasks == true ? ", tasks due" : "")
            + (hasEvents(model, day) ? ", events" : "")
    }
}

/// The one spring of the Agenda's slides and its week-to-month opening.
enum AgendaMotion {
    static let spring = Animation.smooth(duration: 0.3)
}

extension Theme {
    /// A badge's fill for `due`: 18% in dark schemes and 16% in light ones.
    var dueFill: Color { color(\.due).opacity(isDark ? 0.18 : 0.16) }
}

extension AppModel.AgendaSelection {
    /// The day the Agenda's month is the month of: the day, or the middle of the week.
    var anchor: LocalDate {
        switch self {
        case let .day(day): day
        case let .week(week): week.firstDay.adding(days: 3)
        }
    }
}

extension AppModel {
    /// The day the Agenda's month is the month of: the selected day, or the middle of the selected week.
    var agendaAnchor: LocalDate { agendaSelection.anchor }

    /// "Today", "Tomorrow" or "Yesterday" for the days around today.
    func relativeDayName(_ day: LocalDate) -> String? {
        switch today.days(to: day) {
        case 0: "Today"
        case 1: "Tomorrow"
        case -1: "Yesterday"
        default: nil
        }
    }

    /// A week's day row: "2 events · 1 due", counting the open tasks `entries` have on `day`, as its dots do.
    func agendaDaySummary(_ day: LocalDate, entries: [AgendaEntry]) -> String {
        let external = events(on: day).count + reminders(on: day).count
        let due = Set(entries.filter { $0.date == day && !$0.item.properties.status.isClosed }.map(\.item.path)).count
        return [external > 0 ? "\(external) \(external == 1 ? "event" : "events")" : nil, due > 0 ? "\(due) due" : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
