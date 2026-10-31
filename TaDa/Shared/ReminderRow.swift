// A reminder in the Agenda: a circle in its list's colour and its title; in Today an overdue one shows its due
// date in `deadline`, and in Upcoming's later months each shows its date. Reminders aren't links.
import SwiftUI
import TaDaCore

struct ReminderRow: View {
    let reminder: ExternalReminder
    let context: IntegrationRowContext
    /// Today's date, for the overdue date; nil in Upcoming.
    var today: LocalDate?
    /// Shows the due date, as Upcoming's later months do.
    var dated = false
    @Environment(\.theme) private var theme

    private var overdueDate: String? {
        guard let today, reminder.isOverdue(today: today), let due = reminder.due else { return nil }
        return due.formatted(.weekdayDayMonth)
    }

    private var laterDate: String? {
        dated ? reminder.due?.formatted(.weekdayDayMonth) : nil
    }

    var body: some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Reminder: \(reminder.title)" + ((overdueDate ?? laterDate).map { ", due \($0)" } ?? ""))
    }

    #if os(macOS)
    private var content: some View {
        HStack(spacing: 10) {
            Circle()
                .strokeBorder(Color(calendarHex: reminder.color), lineWidth: 1.5)
                .frame(width: context == .today ? 13 : 12, height: context == .today ? 13 : 12)
                .frame(width: context == .today ? 16 : 15)
            Text(reminder.title)
                .font(.system(size: context == .today ? 13.5 : 13))
                .foregroundStyle(theme.color(\.fg))
                .lineLimit(1)
            Spacer(minLength: 0)
            if let overdueDate {
                Text(overdueDate).font(.system(size: 11.5)).foregroundStyle(theme.color(\.deadline)).fixedSize()
            } else if let laterDate {
                Text(laterDate).font(.system(size: 11.5)).foregroundStyle(theme.color(\.muted)).fixedSize()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: context == .today ? 26 : 24)
    }
    #else
    private var content: some View {
        HStack(spacing: 12) {
            Circle()
                .strokeBorder(Color(calendarHex: reminder.color), lineWidth: 1.75)
                .frame(width: 17, height: 17)
                .frame(width: 22)
            HStack(spacing: 10) {
                Text(reminder.title)
                    .scaledFont(size: 16)
                    .foregroundStyle(theme.color(\.fg))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let overdueDate {
                    Text(overdueDate).scaledFont(size: 13).foregroundStyle(theme.color(\.deadline)).fixedSize()
                } else if let laterDate {
                    Text(laterDate).scaledFont(size: 13).foregroundStyle(theme.color(\.muted)).fixedSize()
                }
            }
            .padding(.trailing, 16)
            .scaledMinHeight(40)
        }
        .padding(.leading, 16)
    }
    #endif
}
