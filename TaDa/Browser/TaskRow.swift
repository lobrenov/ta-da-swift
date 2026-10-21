// One task in a browser list: status checkbox, title, quiet glyphs and one date on a single line.
import SwiftUI
import TaDaCore

struct TaskRow: View {
    /// Which date a list shows. The Agenda only flags an overdue due date and reads a deadline as days left; every
    /// other list shows the date itself.
    enum Dates {
        case agenda
        case elsewhere
    }

    let item: Item
    let selected: Bool
    let today: LocalDate
    var dates = Dates.elsewhere
    /// The task's project or area, before the date, where the list's groups don't show it.
    var place: String? = nil
    let onToggle: () -> Void
    let onSelect: () -> Void

    var body: some View {
        SelectableRow(item: item, selected: selected, onToggle: onToggle, onSelect: onSelect) {
            RowGlyphs(item: item)
            Spacer(minLength: 8)
            if let place {
                Text(place)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .layoutPriority(-1)
                    .accessibilityLabel("In \(place)")
            }
            RowDate(item: item, today: today, inAgenda: dates == .agenda)
        }
    }
}

/// A task row's quiet glyphs, icon only: a note, subtasks, a repeat rule and tags. Each says its detail on hover and
/// to VoiceOver.
struct RowGlyphs: View {
    let item: Item
    var iconSize: CGFloat = 11.5
    @Environment(\.theme) private var theme

    var body: some View {
        let subtasks = item.subtasks
        HStack(spacing: 6) {
            if let summary = item.summary, !summary.isEmpty {
                glyph("doc.text", "Has a note")
            }
            if subtasks.total > 0 {
                glyph("checklist", "\(subtasks.done) of \(subtasks.total) subtasks done")
            }
            if let rule = item.properties.repeatRule {
                glyph("repeat", "Repeats \(rule)")
            }
            if !item.tags.isEmpty {
                glyph("tag", item.tags.count == 1 ? "1 tag" : "\(item.tags.count) tags", tint: \.accent,
                      help: item.tags.map { "#\($0.tag.name)  \($0.inFrontmatter ? "tags:" : "in text")" }.joined(separator: "\n"))
            }
        }
        .fixedSize()
    }

    private func glyph(_ systemImage: String, _ spoken: String, tint: KeyPath<Theme, PlatformColor> = \.muted,
                       help: String? = nil) -> some View {
        Image(systemName: systemImage)
            .rowFont(iconSize)
            .foregroundStyle(theme.color(tint))
            .help(help ?? spoken)
            .accessibilityLabel(spoken)
    }
}

/// A task row's one date, right-aligned: the deadline when set, else the due date, with its kind's icon. Closed tasks
/// show none. In the Agenda a deadline reads "today", "N days left" or "N days late" and a due date shows only when
/// overdue.
struct RowDate: View {
    let item: Item
    let today: LocalDate
    var inAgenda = false
    /// An Agenda entry to show instead: its kind's date, even when the task is closed.
    var entry: AgendaEntry? = nil
    var textSize: CGFloat = 12
    var iconSize: CGFloat = 12
    @Environment(\.theme) private var theme

    var body: some View {
        if let (kind, date) = shown {
            let overdue = date < today
            let text = inAgenda && kind == .deadline ? date.deadlineLabel(today: today) : date.relativeLabel(today: today).capitalizedFirst
            HStack(spacing: 4) {
                Image(systemName: kind.systemImage)
                    .rowFont(iconSize)
                    .foregroundStyle(theme.color(kind.tint))
                Text(text)
                    .rowFont(textSize)
                    .foregroundStyle(theme.color(overdue ? \.deadline : \.muted))
            }
            .lineLimit(1)
            .fixedSize()
            .help("\(kind.label) \(date.relativeLabel(today: today))")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(kind.label) \(date.relativeLabel(today: today))\(overdue ? ", overdue" : "")")
        }
    }

    private var shown: (kind: AgendaEntry.Kind, date: LocalDate)? {
        if let entry { return (entry.kind, entry.date) }
        let p = item.properties
        if p.status.isClosed { return nil }
        if let deadline = p.deadline { return (.deadline, deadline) }
        if let due = p.dueDate, !inAgenda || due < today { return (.due, due) }
        return nil
    }
}

private extension View {
    /// The system font at `size` points, scaling with Dynamic Type on the iPhone.
    func rowFont(_ size: CGFloat) -> some View {
        #if os(iOS)
        scaledFont(size: size)
        #else
        font(.system(size: size))
        #endif
    }
}

/// The tag glyph in `accent` and how many tags the file carries, last on a row's meta line. Hovering lists them and
/// where each is written. Nothing when the file has none.
struct TagCountChip: View {
    let tags: [Item.TagUse]

    var body: some View {
        if !tags.isEmpty {
            Chip(systemImage: "tag", tint: \.accent, text: "\(tags.count)", spoken: tags.count == 1 ? "1 tag" : "\(tags.count) tags")
                .help(tags.map { "#\($0.tag.name)  \($0.inFrontmatter ? "tags:" : "in text")" }.joined(separator: "\n"))
        }
    }
}

/// A task's row in a browser list, 32pt high: its status checkbox, then a button holding its title and `trailing`
/// (glyphs and dates), which opens it. A selected row fills with `surface`.
struct SelectableRow<Trailing: View>: View {
    let item: Item
    let selected: Bool
    let onToggle: () -> Void
    let onSelect: () -> Void
    @ViewBuilder var trailing: Trailing
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            StatusCheckbox(status: item.properties.status, title: item.title, action: onToggle)
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    TaskTitle(item: item, selected: selected, lines: 1)
                        .layoutPriority(1)
                        .help(item.title)
                    trailing
                        .foregroundStyle(theme.color(\.muted))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(selected ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 7))
    }
}

/// A task title: struck through and muted when done or cancelled, strong when selected.
struct TaskTitle: View {
    let item: Item
    var selected = false
    var size: CGFloat = 13.5
    var lines = 2
    @Environment(\.theme) private var theme

    var body: some View {
        let done = item.properties.status.isClosed
        Text(item.title)
            .font(.system(size: size))
            .strikethrough(done)
            .foregroundStyle(theme.color(done ? \.muted : selected ? \.strong : \.fg))
            .lineLimit(lines)
            .truncationMode(.tail)
    }
}

/// The box left of a task: empty for Not Started, a square for Doing, a bar for Blocked, a tick for Done, a slash for
/// Cancelled. Clicking completes the task, or reopens a done or cancelled one.
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
        .accessibilityLabel("\(Self.action(for: status)): \(title)")
        .help(Self.action(for: status))
    }

    /// What a click does: "Mark not done", "Reopen" or "Complete".
    static func action(for status: Status) -> String {
        switch status {
        case .done: "Mark not done"
        case .cancelled: "Reopen"
        default: "Complete"
        }
    }

    /// The checkbox marker and tint that show a status. Ongoing is Forwarded's `[>]` in its dot's `doing`.
    static func box(for status: Status, theme: Theme) -> (marker: Character, tint: PlatformColor) {
        let marker: Character = switch status {
        case .notStarted: " "
        case .doing: "/"
        case .ongoing: ">"
        case .blocked: "B"
        case .done: "x"
        case .cancelled: "-"
        }
        return (marker, status == .ongoing ? theme.doing : theme.checkboxTint(marker))
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

extension ListSection {
    /// A Completed, Done or Cancelled group.
    var isClosed: Bool {
        switch kind {
        case .completed: true
        case .status(let status): status.isClosed
        case .date, .open: false
        }
    }
}

extension Theme {
    func statusColor(_ status: Status) -> Color {
        switch status {
        case .notStarted: color(\.muted)
        case .doing, .ongoing: color(\.doing)
        case .done: color(\.done)
        case .blocked: color(\.blocked)
        case .cancelled: color(\.muted)
        }
    }
}

extension LocalDate {
    /// "today", or "Tue 6 Oct" (with the year when it isn't this year's).
    func relativeLabel(today: LocalDate) -> String {
        if self == today { return "today" }
        return year == today.year ? formatted(.weekdayDayMonth) : formatted(.weekdayDayMonthYear)
    }

    /// A deadline's distance: "Today", "3 days left" or "1 day late".
    func deadlineLabel(today: LocalDate) -> String {
        let days = today.days(to: self)
        if days == 0 { return "Today" }
        let n = abs(days)
        return "\(n) day\(n == 1 ? "" : "s") \(days > 0 ? "left" : "late")"
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
