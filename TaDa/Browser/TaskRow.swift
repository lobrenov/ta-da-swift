// One task in a browser list: status checkbox, one date, title and quiet glyphs on a single line.
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
    /// An Agenda week entry whose date the row shows.
    var entry: AgendaEntry? = nil
    /// Where a done or skipped repeating task moves.
    var move: RepeatMove? = nil
    let onToggle: () -> Void
    let onSelect: () -> Void

    var body: some View {
        SelectableRow(item: item, selected: selected, onToggle: onToggle, onSelect: onSelect) {
            RowDate(item: item, today: today, inAgenda: dates == .agenda, entry: entry)
        } trailing: {
            RowGlyphs(item: item, today: today, move: move)
            Spacer(minLength: 8)
            if let place {
                Text(place)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .layoutPriority(-1)
                    .accessibilityLabel("In \(place)")
            }
        }
    }
}

/// A task row's quiet glyphs, icon only: a note, subtasks, a repeat rule and tags. Each says its detail on hover and
/// to VoiceOver. A done or skipped repeating task's glyph is followed by where it moves ("Tomorrow") or "Ended".
struct RowGlyphs: View {
    let item: Item
    let today: LocalDate
    var move: RepeatMove? = nil
    var iconSize: CGFloat = 11.5
    @Environment(\.theme) private var theme

    var body: some View {
        let glyphs = glyphs
        // The glyphs drop, keeping their spoken labels, when the row's title would otherwise truncate.
        ViewThatFits(in: .horizontal) {
            glyphRow(glyphs)
            // A repeat glyph keeps its text; the other glyphs drop.
            if let repeating = glyphs.first(where: { $0.systemImage == "repeat" && $0.text != nil }) {
                glyphRow([repeating])
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(glyphs.map(\.spoken).joined(separator: ", "))
            }
            Color.clear.frame(width: 0)
                .accessibilityElement()
                .accessibilityLabel(glyphs.map(\.spoken).joined(separator: ", "))
        }
    }

    private func glyphRow(_ glyphs: [(systemImage: String, spoken: String, tint: KeyPath<Theme, PlatformColor>, help: String?, text: String?)]) -> some View {
        HStack(spacing: 6) {
            ForEach(glyphs, id: \.systemImage) { glyph in
                HStack(spacing: 4) {
                    Image(systemName: glyph.systemImage)
                    if let text = glyph.text { Text(text) }
                }
                .rowFont(iconSize)
                .foregroundStyle(theme.color(glyph.tint))
                .help(glyph.help ?? glyph.spoken)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(glyph.spoken)
            }
        }
        .fixedSize()
    }

    private var glyphs: [(systemImage: String, spoken: String, tint: KeyPath<Theme, PlatformColor>, help: String?, text: String?)] {
        let subtasks = item.subtasks
        var glyphs: [(systemImage: String, spoken: String, tint: KeyPath<Theme, PlatformColor>, help: String?, text: String?)] = []
        if item.hasNote {
            glyphs.append(("doc.text", "Has a note", \.muted, nil, nil))
        }
        if subtasks.total > 0 {
            glyphs.append(("checklist", "\(subtasks.done) of \(subtasks.total) subtasks done", \.muted, nil, nil))
        }
        if let rule = item.properties.repeatRule {
            glyphs.append(("repeat", RepeatWording.rowHelp(rule, move: move, today: today), \.muted, nil,
                           move.map { RepeatWording.rowNext($0, today: today) }))
        }
        if !item.tags.isEmpty {
            glyphs.append(("tag", item.tags.count == 1 ? "1 tag" : "\(item.tags.count) tags", \.accent,
                           item.tags.map { "#\($0.tag.name)  \($0.inFrontmatter ? "tags:" : "in text")" }.joined(separator: "\n"), nil))
        }
        return glyphs
    }
}

/// A task row's one date as a pill before the title: the deadline when set, else the due date. It is tinted `accent`, or
/// `deadline` when overdue (a deadline today included). Closed tasks show none. In the Agenda a deadline reads "Today",
/// "N days left" or "N days late" and a due date shows only when overdue.
struct RowDate: View {
    let item: Item
    let today: LocalDate
    var inAgenda = false
    /// An Agenda entry to show instead: its kind's date.
    var entry: AgendaEntry? = nil
    var textSize: CGFloat = 12
    @Environment(\.theme) private var theme

    var body: some View {
        if let (kind, date) = shown {
            let overdue = date < today || (kind == .deadline && date == today)
            let text = inAgenda && kind == .deadline ? date.deadlineLabel(today: today) : date.rowLabel(today: today)
            let tint = theme.color(overdue ? \.deadline : \.accent)
            Text(text)
                .rowFont(textSize)
                .foregroundStyle(overdue ? tint : theme.color(\.fg))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(tint.opacity(theme.isDark ? 0.22 : 0.14), in: .capsule)
                .fixedSize()
                .help("\(kind.label) \(date.relativeLabel(today: today))")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(kind.label) \(date.relativeLabel(today: today))\(date < today ? ", overdue" : "")")
        }
    }

    private var shown: (kind: AgendaEntry.Kind, date: LocalDate)? {
        let p = item.properties
        if p.status.isClosed { return nil }
        if let entry { return (entry.kind, entry.date) }
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

/// A task's row in a browser list, 32pt high: its status checkbox, then a button holding `leading` (the date), its title
/// and `trailing` (glyphs and place), which opens it. A selected row fills with `surface`.
struct SelectableRow<Leading: View, Trailing: View>: View {
    let item: Item
    let selected: Bool
    let onToggle: () -> Void
    let onSelect: () -> Void
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            StatusCheckbox(status: item.properties.status, title: item.title, action: onToggle)
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    leading
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
    /// A task row's date, short: "Today", the weekday for the next six days ("Thu"), else "29 Oct" (with the year when
    /// it isn't this year's).
    func rowLabel(today: LocalDate) -> String {
        let days = today.days(to: self)
        if days == 0 { return "Today" }
        if (1...6).contains(days) { return formatted(.shortWeekday) }
        return year == today.year ? formatted(.dayMonth) : formatted(.dayMonthYear)
    }

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
