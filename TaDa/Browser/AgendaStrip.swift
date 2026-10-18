// The Agenda's header: its title with Week | Month and ‹ Today ›, then the days of the selected week, or every week of
// the month when it's open, each row led by its ISO week number. A day shows its dots: a ring when its daily note has
// unchecked boxes, `due` when an open task is due or at its deadline, `muted` for an event or reminder.
#if os(macOS)
import SwiftUI
import TaDaCore

struct AgendaStrip: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    private static let weekColumn: CGFloat = 40

    /// The day the strip's month is the month of.
    private var anchor: LocalDate {
        switch model.agendaSelection {
        case let .day(day): day
        case let .week(week): week.firstDay.adding(days: 3)
        }
    }

    private var weeks: [ISOWeek] {
        let range = model.agendaRange
        return (0..<(range.lowerBound.days(to: range.upperBound) + 1) / 7).map { range.lowerBound.adding(days: $0 * 7).isoWeek }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Too narrow for the title and both controls, the title gives way and the icon stays.
            ViewThatFits(in: .horizontal) {
                DomainHeader(.agenda) { controls }
                HStack {
                    Image(systemName: AppModel.Domain.agenda.systemImage).font(.system(size: 20))
                        .foregroundStyle(theme.color(AppModel.Domain.agenda.tint)).accessibilityLabel("Agenda")
                    Spacer(minLength: 8)
                    controls
                }
            }
            if model.agendaMonthOpen {
                Text(anchor.formatted(.monthYear)).font(.system(size: 13, weight: .bold)).foregroundStyle(theme.color(\.strong))
            }
            VStack(spacing: 2) {
                initials
                ForEach(weeks, id: \.self) { week in
                    HStack(spacing: 0) {
                        weekCell(week).frame(width: Self.weekColumn)
                        ForEach(week.days, id: \.self) { dayCell($0, in: week).frame(maxWidth: .infinity) }
                    }
                }
            }
        }
    }

    private var initials: some View {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        return HStack(spacing: 0) {
            Text("W").frame(width: Self.weekColumn)
            ForEach(1...7, id: \.self) { Text(symbols[$0 % 7]).frame(maxWidth: .infinity) }
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(theme.color(\.muted))
        .padding(.bottom, 2)
        .accessibilityHidden(true)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            SegmentedControl(label: "Calendar size", options: [(false, "Week"), (true, "Month")],
                             selection: Binding { model.agendaMonthOpen } set: { model.agendaMonthOpen = $0 },
                             height: 22, unselectedWeight: .semibold)
            stepper
        }
    }

    /// ‹ Today ›, which step a day, or a week when a week is picked.
    private var stepper: some View {
        let unit: String = if case .week = model.agendaSelection { "week" } else { "day" }
        return HStack(spacing: 0) {
            stepButton("chevron.left", label: "Previous \(unit)") { model.stepAgenda(by: -1) }
            Rectangle().fill(theme.color(\.border)).frame(width: 1)
            Button { model.showAgendaToday() } label: {
                Text("Today").font(.system(size: 12)).foregroundStyle(theme.color(\.fg)).padding(.horizontal, 8)
                    .frame(maxHeight: .infinity).contentShape(.rect)
            }
            .buttonStyle(.plain)
            Rectangle().fill(theme.color(\.border)).frame(width: 1)
            stepButton("chevron.right", label: "Next \(unit)") { model.stepAgenda(by: 1) }
        }
        .frame(height: 26)
        .background(theme.color(\.code), in: .rect(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.color(\.border)))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Move through days")
    }

    private func stepButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 10, weight: .bold)).foregroundStyle(theme.color(\.fg))
                .frame(width: 26).frame(maxHeight: .infinity).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func weekCell(_ week: ISOWeek) -> some View {
        let selected = model.agendaSelection == .week(week)
        let hasNote = model.index.weekNote(for: week, names: model.dailyNoteNames) != nil
        return Button { model.agendaSelection = .week(week) } label: {
            Text("\(week.week)")
                .font(.system(size: 11, weight: selected ? .bold : .semibold, design: .monospaced))
                .foregroundStyle(theme.color(selected ? \.bg : hasNote ? \.link : \.muted))
                .frame(width: 28, height: 22)
                .background(selected ? theme.color(\.strong) : .clear, in: .rect(cornerRadius: 6))
                .padding(.top, 4)
                .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38, alignment: .top)
                .background(selected ? theme.color(\.side) : .clear, in: .rect(cornerRadius: 7))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Week \(week.week)\(hasNote ? ", note" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func dayCell(_ day: LocalDate, in week: ISOWeek) -> some View {
        let selected = model.agendaSelection == .day(day)
        let isToday = day == model.today
        let faded = day.month != anchor.month || day < model.today
        return Button { model.agendaSelection = .day(day) } label: {
            VStack(spacing: 3) {
                Text("\(day.day)")
                    .font(.system(size: 13, weight: selected || isToday ? .bold : .medium))
                    .foregroundStyle(theme.color(selected ? \.bg : isToday ? \.accent : faded ? \.muted : \.fg))
                    .frame(width: 24, height: 22)
                    .background(selected ? theme.color(isToday ? \.accent : \.strong) : .clear, in: .rect(cornerRadius: 11))
                AgendaDots(model: model, day: day, size: 4)
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38, alignment: .top)
            .background(model.agendaSelection == .week(week) ? theme.color(\.side) : .clear, in: .rect(cornerRadius: 7))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel((isToday ? "Today, " : "") + day.formatted(.weekdayDayMonth) + AgendaDots.spoken(model, day))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A day's dots, in order: the ring, then `due`, then `muted`.
struct AgendaDots: View {
    let model: AppModel
    let day: LocalDate
    let size: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        let marks = model.agendaMarks[day]
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
    static func spoken(_ model: AppModel, _ day: LocalDate) -> String {
        let marks = model.agendaMarks[day]
        return (marks?.hasOpenBoxes == true ? ", open items in the note" : "") + (marks?.hasOpenTasks == true ? ", tasks due" : "")
            + (hasEvents(model, day) ? ", events" : "")
    }
}
#endif
