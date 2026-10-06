// Upcoming: the seven days from tomorrow (empty days included), then later entries by month.
// An open task gets one entry on its due date and another on its deadline.
import SwiftUI
import TaDaCore

struct AgendaView: View {
    enum Style {
        /// Beside the month calendar: one line per entry, seven days only (the calendar lists the rest).
        case wide
        /// A browser column beside a document: two lines per entry, with later entries by month.
        case column
    }

    let model: AppModel
    let style: Style
    @Environment(\.theme) private var theme

    static let days = 7

    var body: some View {
        let today = model.today
        let entries = model.upcoming
        let lastDay = today.adding(days: Self.days)
        // A task can have two entries (due and deadline); the arrow keys stop at its first.
        let listed = style == .wide ? entries.filter { $0.date <= lastDay } : entries
        var seen = Set<String>()
        let paths = listed.map(\.item.path).filter { seen.insert($0).inserted }

        switch style {
        case .wide:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) { week(entries, today: today) }
                    .padding(.top, 4)
                    .padding(.bottom, 24)
            }
            .arrowKeySelection(model, paths: paths, allowsMultipleSelection: true)
        case .column:
            BrowserColumn(model: model, paths: paths, spacing: 6) {
                DomainHeader(.upcoming) {
                    Button("Month view") {
                        model.selection = nil
                        model.clearMultiSelection()
                    }
                    .buttonStyle(.plain)
                }
            } content: {
                week(entries, today: today)
                let later = Dictionary(grouping: entries.filter { $0.date > lastDay }) { $0.date.startOfMonth }
                ForEach(later.keys.sorted(), id: \.self) { month in
                    VStack(alignment: .leading, spacing: 0) {
                        DayHeader(number: nil, label: Self.laterTitle(month, today: today), empty: false, style: style)
                        ForEach(later[month]!) { row($0, dated: true) }
                    }
                }
            }
        }
    }

    /// The seven days from tomorrow, each under its header.
    private func week(_ entries: [AgendaEntry], today: LocalDate) -> some View {
        ForEach(1...Self.days, id: \.self) { offset in
            let day = today.adding(days: offset)
            let items = entries.filter { $0.date == day }
            VStack(alignment: .leading, spacing: 0) {
                DayHeader(number: "\(day.day)", label: offset == 1 ? "Tomorrow" : day.formatted(.weekday),
                          empty: items.isEmpty, style: style)
                ForEach(items) { row($0, dated: false) }
            }
        }
    }

    @ViewBuilder private func row(_ entry: AgendaEntry, dated: Bool) -> some View {
        let toggle: () -> Void = { Task { await model.toggleCompletion(entry.item) } }
        let select: () -> Void = { model.click(entry.item.path) }
        Group {
            switch style {
            case .wide:
                WideAgendaRow(entry: entry, place: place(of: entry.item), also: also(entry), onToggle: toggle, onSelect: select)
            case .column:
                ColumnAgendaRow(entry: entry, place: place(of: entry.item), also: also(entry), dated: dated,
                                today: model.today, selected: model.isSelected(entry.item.path),
                                onToggle: toggle, onSelect: select)
            }
        }
        .fileMenu(model, path: entry.item.path)
    }

    private func place(of task: Item) -> String {
        model.index.project(of: task)?.title ?? "Loose task"
    }

    /// The task's other date, so a deadline entry still says when it's due and vice versa.
    private func also(_ entry: AgendaEntry) -> String? {
        let p = entry.item.properties
        let (kind, date): (AgendaEntry.Kind, LocalDate?) = entry.kind == .due ? (.deadline, p.deadline) : (.due, p.dueDate)
        return date.map { "\(kind.label) \($0.relativeLabel(today: model.today))" }
    }

    /// "Later in October" for the rest of this month, then "November", or "January 2027" in another year.
    static func laterTitle(_ month: LocalDate, today: LocalDate) -> String {
        if month == today.startOfMonth { return "Later in \(month.formatted(.month))" }
        return month.year == today.year ? month.formatted(.month) : month.formatted(.monthYear)
    }
}

private struct DayHeader: View {
    /// The day of the month; nil for a month heading.
    let number: String?
    let label: String
    let empty: Bool
    let style: AgendaView.Style
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let number {
                    Text(number)
                        .font(.system(size: style == .wide ? 22 : 19, weight: .bold))
                        .foregroundStyle(theme.color(empty ? \.muted : \.strong))
                        .frame(width: style == .wide ? 34 : 26, alignment: .leading)
                }
                Text(label)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.color(empty ? \.muted : number == nil ? \.strong : \.fg))
            }
            .padding(.horizontal, style == .wide ? 0 : 10)
            .padding(.top, 6)
            .padding(.bottom, style == .wide ? 6 : 4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A rounded outline around a short note, e.g. "Deadline Fri 16 Oct".
private struct Pill: View {
    let text: String
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(theme.color(\.muted))
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(theme.color(\.border)))
    }
}

private struct WideAgendaRow: View {
    let entry: AgendaEntry
    let place: String
    let also: String?
    let onToggle: () -> Void
    let onSelect: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            StatusCheckbox(status: entry.item.properties.status, title: entry.item.title, size: 15, action: onToggle)
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    KindIcon(kind: entry.kind)
                    TaskTitle(item: entry.item).lineLimit(1)
                    Text(place).font(.system(size: 11.5)).foregroundStyle(theme.color(\.muted)).lineLimit(1).layoutPriority(-1)
                    if let also { Pill(text: also) }
                    if let rule = entry.item.properties.repeatRule { Pill(text: "Repeats \(rule.lowercased())") }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 30)
        .padding(.leading, 44)
    }
}

private struct ColumnAgendaRow: View {
    let entry: AgendaEntry
    let place: String
    let also: String?
    /// Later entries show their date beside the kind.
    let dated: Bool
    let today: LocalDate
    let selected: Bool
    let onToggle: () -> Void
    let onSelect: () -> Void

    var body: some View {
        SelectableRow(item: entry.item, selected: selected, onToggle: onToggle, onSelect: onSelect) {
            HStack(spacing: 4) {
                KindIcon(kind: entry.kind)
                Text(entry.kind.label + (dated ? " \(entry.date.relativeLabel(today: today))" : ""))
            }
            Text(place)
            if let also { Pill(text: also) }
            if let rule = entry.item.properties.repeatRule { Pill(text: "Repeats \(rule.lowercased())") }
        }
    }
}
