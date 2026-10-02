// A month grid with dots for open tasks' due dates and deadlines, and the month's entries after the agenda's seven days.
import SwiftUI
import TaDaCore

struct MonthCalendarView: View {
    let model: AppModel
    /// The first day of the month shown; nil shows this month.
    @State private var shownMonth: LocalDate?
    @Environment(\.theme) private var theme

    var body: some View {
        let today = model.today
        let month = shownMonth ?? today.startOfMonth
        let open = model.index.tasks.filter { $0.properties.status != .done }
        let due = Set(open.compactMap(\.properties.dueDate))
        let deadlines = Set(open.compactMap(\.properties.deadline))
        let lastAgendaDay = today.adding(days: AgendaView.days)
        let later = model.index.upcoming(after: lastAgendaDay).filter { $0.date.startOfMonth == month }

        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(month.formatted(.monthYear))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(theme.color(\.strong))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    monthButton("chevron.left", "Previous month") { shownMonth = month.addingMonths(-1) }
                    monthButton("chevron.right", "Next month") { shownMonth = month.addingMonths(1) }
                }
                grid(month: month, today: today, due: due, deadlines: deadlines)
            }
            .padding(16)
            .background(theme.color(\.side), in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color(\.border)))

            VStack(alignment: .leading, spacing: 4) {
                Text("Later in \(month.formatted(.month))")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.color(\.strong))
                    .padding(.bottom, 6)
                    .accessibilityAddTraits(.isHeader)
                if later.isEmpty {
                    Text("Nothing after \(lastAgendaDay.formatted(.weekdayDayMonth)).")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.color(\.muted))
                }
                ForEach(later) { entry in
                    Button { model.selection = entry.item.path } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.date.formatted(.weekdayDayMonth))
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(theme.color(\.muted))
                            HStack(spacing: 8) {
                                Image(systemName: entry.kind.systemImage)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(theme.color(entry.kind.tint))
                                    .accessibilityLabel(entry.kind == .due ? "Due" : "Deadline")
                                Text(entry.item.title).lineLimit(1).foregroundStyle(theme.color(\.fg))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .overlay(alignment: .top) { Hairline() }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 300)
        .onChange(of: today) { shownMonth = nil }
    }

    private func monthButton(_ systemImage: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.color(\.muted))
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func grid(month: LocalDate, today: LocalDate, due: Set<LocalDate>, deadlines: Set<LocalDate>) -> some View {
        let calendar = Calendar.current
        // Weekday symbols start on Sunday; rotate them to the locale's first weekday.
        let first = calendar.firstWeekday - 1
        let symbols = Array(calendar.veryShortStandaloneWeekdaySymbols[first...] + calendar.veryShortStandaloneWeekdaySymbols[..<first])
        let leading = (month.weekday - calendar.firstWeekday + 7) % 7
        let daysInMonth = month.days(to: month.addingMonths(1))
        let cells: [LocalDate?] = Array(repeating: nil, count: leading) + (0..<daysInMonth).map { month.adding(days: $0) }
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 0), count: 7)

        return VStack(spacing: 4) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(symbols.indices, id: \.self) { i in
                    Text(symbols[i]).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(theme.color(\.muted))
                }
            }
            .accessibilityHidden(true)
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(cells.indices, id: \.self) { i in
                    if let day = cells[i] {
                        DayCell(day: day, today: today, hasDue: due.contains(day), hasDeadline: deadlines.contains(day))
                    } else {
                        Color.clear.frame(height: 34)
                    }
                }
            }
        }
    }
}

private struct DayCell: View {
    let day: LocalDate
    let today: LocalDate
    let hasDue: Bool
    let hasDeadline: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        let isToday = day == today
        VStack(spacing: 2) {
            Text("\(day.day)")
                .font(.system(size: 11.5, weight: isToday ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(theme.color(isToday ? \.strong : day < today ? \.muted : \.fg))
                .frame(width: 22, height: 18)
                .background(isToday ? theme.color(\.surface) : .clear, in: .capsule)
            HStack(spacing: 2) {
                if hasDue { Circle().fill(theme.color(\.due)).frame(width: 4, height: 4) }
                if hasDeadline { RoundedRectangle(cornerRadius: 1).fill(theme.color(\.deadline)).frame(width: 4, height: 4) }
            }
            .frame(height: 4)
        }
        .padding(.top, 4)
        .frame(height: 34, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [day.formatted(.weekdayDayMonth)]
        if day == today { parts.append("today") }
        if hasDue { parts.append("tasks due") }
        if hasDeadline { parts.append("deadlines") }
        return parts.joined(separator: ", ")
    }
}
