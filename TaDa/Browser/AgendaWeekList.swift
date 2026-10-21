// The Agenda's week: its heading, the week note's row, a row for each day that picks it, then the tasks due or at their
// deadline in the week.
#if os(macOS)
import SwiftUI
import TaDaCore

struct AgendaWeekList: View {
    let model: AppModel
    let week: ISOWeek
    @Environment(\.theme) private var theme

    var body: some View {
        let entries = model.agendaWeekEntries
        var seen = Set<String>()
        // A task can have two entries (due and deadline); the arrow keys stop at its first.
        let paths = entries.map(\.item.path).filter { seen.insert($0).inserted }

        BrowserColumn(model: model, paths: paths, spacing: 22) {
            AgendaStrip(model: model)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Week \(week.week)").font(.system(size: 18, weight: .bold)).foregroundStyle(theme.color(\.strong))
                        .accessibilityAddTraits(.isHeader)
                    Text("\(week.firstDay.formatted(.dayMonth)) – \(week.firstDay.adding(days: 6).formatted(.dayMonth))")
                        .foregroundStyle(theme.color(\.muted))
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: 0)
                    if week == model.today.isoWeek { Text("This week").fontWeight(.semibold).foregroundStyle(theme.color(\.accent)) }
                }
                .padding(.horizontal, 10)
                if model.weekNotes { AgendaNoteRow(model: model, period: .week(week)) }
                VStack(spacing: 0) {
                    ForEach(week.days, id: \.self) { dayRow($0, entries: entries) }
                }
                .padding(.top, 4)
            }
            if !entries.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    VStack(spacing: 7) {
                        Text("Due this week").fontWeight(.semibold).foregroundStyle(theme.color(\.strong))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .accessibilityAddTraits(.isHeader)
                        Hairline()
                    }
                    .padding(.bottom, 4)
                    ForEach(entries) { entry in
                        TaskRow(item: entry.item, selected: model.isSelected(entry.item.path), today: model.today, dates: .overdueDueAndDeadline,
                                place: model.index.parent(of: entry.item)?.title,
                                onToggle: { Task { await model.toggleCompletion(entry.item) } },
                                onSelect: { model.click(entry.item.path) })
                        .fileMenu(model, path: entry.item.path)
                        .taskDrag(model, path: entry.item.path)
                    }
                }
            }
        }
        .showsAgendaNote(model)
    }

    /// A day: its label, its note's first paragraph, what it holds, and its dots. Clicking picks the day.
    private func dayRow(_ day: LocalDate, entries: [AgendaEntry]) -> some View {
        let note = model.index.dailyNote(for: day, names: model.dailyNoteNames)
        let counts = model.agendaDaySummary(day, entries: entries)
        let isToday = day == model.today
        return Button { model.agendaSelection = .day(day) } label: {
            HStack(spacing: 10) {
                Text(day.formatted(.weekdayDay)).fontWeight(.semibold)
                    .foregroundStyle(theme.color(isToday ? \.accent : \.strong))
                    .frame(width: 52, alignment: .leading)
                Text(note == nil ? "No note" : note?.summary ?? "")
                    .font(.system(size: 13.5))
                    .foregroundStyle(theme.color(note == nil ? \.muted : \.fg))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(counts).font(.system(size: 11.5)).foregroundStyle(theme.color(\.muted)).lineLimit(1).fixedSize()
                AgendaDots(model: model, day: day, size: 5).frame(width: 22, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .overlay(alignment: .bottom) { Hairline() }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.fullDate) + (note == nil ? ", no note" : ", note") + (counts.isEmpty ? "" : ", " + counts)
                            + AgendaDots.spoken(model, day))
    }
}
#endif
