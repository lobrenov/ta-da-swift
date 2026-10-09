// One task in a browser list: status checkbox, title and a line of chips.
import SwiftUI
import TaDaCore

struct TaskRow: View {
    /// Which date chips a list shows. Today only flags an overdue due date; it lists everything due by today.
    enum Dates {
        case overdueDueAndDeadline
        /// "Due" and "Deadline" words before each date.
        case labelled
        /// Icons only, as in a project's task list.
        case iconsOnly
    }

    let item: Item
    let selected: Bool
    let today: LocalDate
    var dates = Dates.labelled
    let onToggle: () -> Void
    let onSelect: () -> Void

    private var p: Properties { item.properties }
    private var isDone: Bool { p.status == .done }

    var body: some View {
        SelectableRow(item: item, selected: selected, onToggle: onToggle, onSelect: onSelect) { chips }
    }

    @ViewBuilder private var chips: some View {
        let subtasks = item.subtasks
        if subtasks.total > 0 {
            Chip(systemImage: "checklist", text: "\(subtasks.done)/\(subtasks.total)",
                 spoken: "\(subtasks.done) of \(subtasks.total) subtasks done")
        }
        if let rule = p.repeatRule {
            Chip(systemImage: "repeat", text: rule, spoken: "Repeats \(rule)")
        }
        if !isDone {
            if let due = p.dueDate, dates != .overdueDueAndDeadline || due < today {
                DateChip(kind: .due, date: due, today: today, labelled: dates != .iconsOnly)
            }
            if let deadline = p.deadline {
                DateChip(kind: .deadline, date: deadline, today: today, labelled: dates != .iconsOnly)
            }
        }
    }
}

/// A task's row in a browser list: its status checkbox, then a button holding its title over a line of `meta`, which
/// opens it. A selected row fills with `surface`.
struct SelectableRow<Meta: View>: View {
    let item: Item
    let selected: Bool
    let onToggle: () -> Void
    let onSelect: () -> Void
    @ViewBuilder var meta: Meta
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusCheckbox(status: item.properties.status, title: item.title, action: onToggle)
                .padding(.top, 2)
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 3) {
                    TaskTitle(item: item, selected: selected)
                    HStack(spacing: 12) { meta }
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.color(\.muted))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(selected ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 7))
    }
}

/// A task title: struck through and muted when done, strong when selected.
struct TaskTitle: View {
    let item: Item
    var selected = false
    var size: CGFloat = 13.5
    @Environment(\.theme) private var theme

    var body: some View {
        let done = item.properties.status == .done
        Text(item.title)
            .font(.system(size: size))
            .strikethrough(done)
            .foregroundStyle(theme.color(done ? \.muted : selected ? \.strong : \.fg))
            .lineLimit(2)
    }
}

/// The box left of a task: empty for Not Started, a square for Doing, a bar for Blocked, a tick for Done.
/// Clicking completes the task, or reopens a done one.
struct StatusCheckbox: View {
    let status: Status
    let title: String
    var size: CGFloat = 16
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let (marker, tint) = Self.box(for: status, theme: theme)
        Button(action: action) {
            InlineCheckboxView(marker: marker, tint: tint, background: theme.bg)
                .frame(width: size, height: size)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(status == .done ? "Mark not done: \(title)" : "Complete: \(title)")
        .help(status == .done ? "Mark not done" : "Complete")
    }

    /// The checkbox marker and tint that show a status.
    static func box(for status: Status, theme: Theme) -> (marker: Character, tint: PlatformColor) {
        let marker: Character = switch status {
        case .notStarted: " "
        case .doing: "/"
        case .blocked: "B"
        case .done: "x"
        }
        return (marker, theme.checkboxTint(marker))
    }
}

/// A coloured dot and the status name.
struct StatusLabel: View {
    let status: Status
    var dotSize: CGFloat = 6
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(theme.statusColor(status)).frame(width: dotSize, height: dotSize)
            Text(status.rawValue)
        }
    }
}

/// An icon and a short text. VoiceOver reads `spoken` (or the text) instead of the icon's name.
struct Chip: View {
    let systemImage: String
    var tint: KeyPath<Theme, PlatformColor>? = nil
    let text: String
    var spoken: String? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                #if os(iOS)
                .scaledFont(size: 10, weight: .semibold)
                #else
                .font(.system(size: 10, weight: .semibold))
                #endif
                .foregroundStyle(tint.map { theme.color($0) } ?? theme.color(\.muted))
            Text(text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken ?? text)
    }
}

/// A due date (calendar, due colour) or deadline (flag, deadline colour). Past dates turn the text red.
struct DateChip: View {
    let kind: AgendaEntry.Kind
    let date: LocalDate
    let today: LocalDate
    var labelled = true
    @Environment(\.theme) private var theme

    var body: some View {
        let day = date.relativeLabel(today: today)
        Chip(systemImage: kind.systemImage, tint: kind.tint,
             text: labelled ? "\(kind.label) \(day)" : day.capitalizedFirst)
            .foregroundStyle(date < today ? theme.color(\.deadline) : theme.color(\.muted))
            .accessibilityLabel("\(kind.label) \(day)\(date < today ? ", overdue" : "")")
    }
}

/// The calendar or flag for a date's kind.
struct KindIcon: View {
    let kind: AgendaEntry.Kind
    @Environment(\.theme) private var theme

    var body: some View {
        Image(systemName: kind.systemImage)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(theme.color(kind.tint))
            .accessibilityLabel(kind.label)
    }
}

extension AgendaEntry.Kind {
    var systemImage: String { self == .due ? "calendar" : "flag" }
    var tint: KeyPath<Theme, PlatformColor> { self == .due ? \.due : \.deadline }
    /// "Due" or "Deadline", before a day.
    var label: String { self == .due ? "Due" : "Deadline" }
    /// "Due date" or "Deadline", on a missing date's chip and atop its calendar.
    var name: String { self == .due ? "Due date" : "Deadline" }
    /// The frontmatter key: `dueDate` or `deadline`.
    var key: String { self == .due ? "dueDate" : "deadline" }
    var date: KeyPath<Properties, LocalDate?> { self == .due ? \.dueDate : \.deadline }
}

extension Theme {
    func statusColor(_ status: Status) -> Color {
        switch status {
        case .notStarted: color(\.muted)
        case .doing: color(\.doing)
        case .done: color(\.done)
        case .blocked: color(\.blocked)
        }
    }
}

extension LocalDate {
    /// "today", or "Tue 6 Oct" (with the year when it isn't this year's).
    func relativeLabel(today: LocalDate) -> String {
        if self == today { return "today" }
        return year == today.year ? formatted(.weekdayDayMonth) : formatted(.weekdayDayMonthYear)
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
