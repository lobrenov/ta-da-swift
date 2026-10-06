// Upcoming: the seven days from tomorrow (empty days included), then later entries by month.
// An open task gets one entry on its due date and another on its deadline.
import SwiftUI
import TaDaCore

struct AgendaView: View {
    enum Style {
        /// Beside the month calendar: one line per entry, seven days only (the calendar lists the rest).
        case wide
        /// Beside a document: two lines per entry, with later entries by month.
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
        let later = Dictionary(grouping: entries.filter { $0.date > lastDay }) { $0.date.startOfMonth }
        // A task can have two entries (due and deadline); the arrow keys stop at its first.
        let listed = style == .wide ? entries.filter { $0.date <= lastDay } : entries
        var seen = Set<String>()
        let paths = listed.map(\.item.path).filter { seen.insert($0).inserted }

        ScrollView {
            LazyVStack(alignment: .leading, spacing: style == .wide ? 10 : 6) {
                ForEach(1...Self.days, id: \.self) { offset in
                    let day = today.adding(days: offset)
                    let items = entries.filter { $0.date == day }
                    VStack(alignment: .leading, spacing: 0) {
                        DayHeader(number: "\(day.day)", label: offset == 1 ? "Tomorrow" : day.formatted(.weekday),
                                  empty: items.isEmpty, style: style)
                        ForEach(items) { row($0, dated: false) }
                    }
                }
                if style == .column {
                    ForEach(later.keys.sorted(), id: \.self) { month in
                        VStack(alignment: .leading, spacing: 0) {
                            DayHeader(number: nil, label: Self.laterTitle(month, today: today), empty: false, style: style)
                            ForEach(later[month]!) { row($0, dated: true) }
                        }
                    }
                }
            }
            .padding(.horizontal, style == .wide ? 0 : 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .arrowKeySelection(model, paths: paths, allowsMultipleSelection: true)
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
        let other = entry.kind == .due ? p.deadline.map { ("Deadline", $0) } : p.dueDate.map { ("Due", $0) }
        return other.map { "\($0.0) \($0.1.relativeLabel(today: model.today))" }
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

/// The calendar or flag for an entry's kind.
private struct KindIcon: View {
    let kind: AgendaEntry.Kind
    @Environment(\.theme) private var theme

    var body: some View {
        Image(systemName: kind.systemImage)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(theme.color(kind.tint))
            .accessibilityLabel(kind == .due ? "Due" : "Deadline")
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
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusCheckbox(status: entry.item.properties.status, title: entry.item.title, action: onToggle)
                .padding(.top, 2)
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 3) {
                    TaskTitle(item: entry.item, selected: selected)
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            KindIcon(kind: entry.kind)
                            Text((entry.kind == .due ? "Due" : "Deadline") + (dated ? " \(entry.date.relativeLabel(today: today))" : ""))
                        }
                        Text(place).lineLimit(1)
                        if let also { Pill(text: also) }
                        if let rule = entry.item.properties.repeatRule { Pill(text: "Repeats \(rule.lowercased())") }
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.color(\.muted))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(selected ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 7))
    }
}
