// The menus of a subtask's `>` date and `@` parent. The editor engine tracks the query and routes the keys; LiveEditor shows
// the choices in a compact popup menu under the `>` or `@` on the Mac and in a list above the keyboard bar on iPhone. A
// click on a drawn pill or chip opens the same choices on the Mac (the calendar for a date), and a popover on iPhone.
import SwiftUI
import TaDaCore

/// A date row: its name, and on the quick rows the day it sets.
struct DateChoiceRow: View {
    let choice: DateChoice
    let isHighlighted: Bool
    let theme: Theme

    var body: some View {
        HStack(spacing: 8) {
            Text(choice.title)
                .foregroundStyle(theme.color(isHighlighted || choice.kind == .typed ? \.strong : \.fg))
                .fontWeight(choice.kind == .typed ? .semibold : .regular)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let detail = choice.detail {
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.color(\.muted))
                    .lineLimit(1)
            }
        }
    }
}

/// A parent row: an area's cube or a project's ring and its title, a project's open tasks, or New project.
struct ParentChoiceRow: View {
    let choice: ParentChoice
    let isHighlighted: Bool
    let theme: Theme

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 16)
            Text(choice.kind == .new ? "New project “\(choice.title)”" : choice.title)
                .fontWeight(choice.kind == .area ? .semibold : .regular)
                .foregroundStyle(theme.color(isHighlighted || choice.kind == .area ? \.strong : \.fg))
                .lineLimit(1)
            Spacer(minLength: 8)
            if case .project(_, _, let open) = choice.kind {
                Text("\(open)")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(theme.color(\.muted))
                    .frame(minWidth: 14, alignment: .trailing)
            }
        }
        .environment(\.theme, theme)
    }

    @ViewBuilder private var icon: some View {
        switch choice.kind {
        case .project(let fraction, let ongoing, _):
            ProgressRing(fraction: fraction, ongoing: ongoing).foregroundStyle(theme.color(\.accent))
        case .area:
            AreaIcon()
        case .new:
            Image(systemName: "plus").font(.system(size: 12)).foregroundStyle(theme.color(\.muted))
        case .remove:
            Image(systemName: "xmark").font(.system(size: 12)).foregroundStyle(theme.color(\.muted))
        }
    }
}

#if os(macOS)
import AppKit

extension DateChoice: PopupMenuItem {}
extension ParentChoice: PopupMenuItem {}

enum ChoiceMenuKey { case up, down, confirm }

/// Shows, moves through and picks from a compact choice menu: the `>` and `@` queries (the editor keeps the keys) and the
/// menu a click on a chip opens (the menu takes them). Owned by LiveEditor.
final class ChoiceMenuController<Choice: PopupMenuItem & Equatable, Row: View> {
    private var shown: [Choice]?
    private let menu: PopupMenu<Choice, Row>

    init(takesKeys: Bool, emptyText: String? = nil, row: @escaping (Choice, Bool, Theme) -> Row) {
        var style = PopupMenuStyle.compact
        style.width = 250
        style.maxListHeight = 216
        style.keepsHighlight = true
        menu = PopupMenu(style: style, takesKeys: takesKeys, emptyText: emptyText, row: row)
    }

    var isOpen: Bool { menu.isOpen }

    /// Shows the menu under `anchor` (screen coordinates), or refreshes it, highlighting `highlight` unless the choices are
    /// those it already shows.
    func show(_ choices: [Choice], highlight: Int? = 0, anchor: CGRect, theme: Theme, pick: @escaping (Choice) -> Void,
              dismiss: @escaping () -> Void) {
        guard anchor != .zero, let parent = NSApp.keyWindow else { return }
        let highlight = shown == choices ? menu.highlight : highlight
        shown = choices
        // A click elsewhere or a scroll ends the query; the typed text stays.
        menu.onDismiss = dismiss
        menu.show([PopupMenuSection(items: choices)], highlight: choices.isEmpty ? nil : highlight, theme: theme,
                  below: anchor, inset: 8, gap: 6, in: parent, pick: pick)
    }

    func hide() {
        menu.hide()
        shown = nil
    }

    /// Returns `true` when the menu used the key.
    func handle(_ key: ChoiceMenuKey) -> Bool {
        guard menu.isOpen else { return false }
        switch key {
        case .up: menu.move(by: -1)
        case .down: menu.move(by: 1)
        case .confirm: return menu.pickHighlighted()
        }
        return true
    }
}

typealias DateMenuController = ChoiceMenuController<DateChoice, DateChoiceRow>
typealias ParentMenuController = ChoiceMenuController<ParentChoice, ParentChoiceRow>

extension ChoiceMenuController where Choice == DateChoice, Row == DateChoiceRow {
    convenience init() {
        self.init(takesKeys: false) { DateChoiceRow(choice: $0, isHighlighted: $1, theme: $2) }
    }
}

extension ChoiceMenuController where Choice == ParentChoice, Row == ParentChoiceRow {
    convenience init(takesKeys: Bool) {
        self.init(takesKeys: takesKeys, emptyText: "No project or area") { ParentChoiceRow(choice: $0, isHighlighted: $1, theme: $2) }
    }
}
#else

/// The `>` query's choices, above the keyboard bar: a tap picks one.
struct PhoneDateList: View {
    let choices: [DateChoice]
    let highlight: Int
    let theme: Theme
    let pick: (DateChoice) -> Void

    var body: some View {
        PhoneChoiceList(choices: choices, highlight: highlight, theme: theme, pick: pick) { choice, isHighlighted in
            DateChoiceRow(choice: choice, isHighlighted: isHighlighted, theme: theme)
        }
    }
}

/// The `@` query's choices, above the keyboard bar: a tap picks one.
struct PhoneParentList: View {
    let choices: [ParentChoice]
    let highlight: Int
    let theme: Theme
    let pick: (ParentChoice) -> Void

    var body: some View {
        PhoneChoiceList(choices: choices, highlight: highlight, theme: theme, pick: pick) { choice, isHighlighted in
            ParentChoiceRow(choice: choice, isHighlighted: isHighlighted, theme: theme)
        }
    }
}

private struct PhoneChoiceList<Choice: Identifiable, Row: View>: View {
    let choices: [Choice]
    let highlight: Int
    let theme: Theme
    let pick: (Choice) -> Void
    @ViewBuilder let row: (Choice, Bool) -> Row

    private static var rowHeight: CGFloat { 44 }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(choices.enumerated()), id: \.element.id) { offset, choice in
                    Button { pick(choice) } label: {
                        row(choice, offset == highlight)
                            .padding(.horizontal, 12)
                            .frame(height: Self.rowHeight)
                            .background(offset == highlight ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 16))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
        .scrollIndicators(.never)
        .frame(height: min(CGFloat(choices.count) * Self.rowHeight + 8, 162))
        .font(.system(size: 17))
        .glassEffect(in: .rect(cornerRadius: 20))
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }
}

/// The popover a tap on a drawn date pill opens: the quick days, a calendar and Remove. A pick writes the date.
struct PhoneDatePopover: View {
    let current: LocalDate?
    let today: LocalDate
    let theme: Theme
    let pick: (LocalDate) -> Void
    let remove: () -> Void
    @State private var day: Date

    init(current: LocalDate?, today: LocalDate, theme: Theme, pick: @escaping (LocalDate) -> Void, remove: @escaping () -> Void) {
        self.current = current
        self.today = today
        self.theme = theme
        self.pick = pick
        self.remove = remove
        _day = State(initialValue: (current ?? today).date())
    }

    var body: some View {
        let choices = DateChoice.choices(query: "", today: today, firstWeekday: Calendar.current.firstWeekday, order: .system,
                                         includesPick: false)
        VStack(spacing: 0) {
            ForEach(choices) { choice in
                Button { choice.date.map(pick) } label: {
                    DateChoiceRow(choice: choice, isHighlighted: false, theme: theme)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            DatePicker("Due date", selection: $day, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(theme.color(\.accent))
                .padding(.horizontal, 8)
                .onChange(of: day) { pick(LocalDate(day)) }
            Button(role: .destructive, action: remove) {
                Text("Remove date")
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.color(\.deadline))
        }
        .font(.system(size: 17))
        .frame(width: 320)
    }
}

/// The popover a tap on a drawn parent chip opens: the areas and projects, and Remove. A pick writes the link.
struct PhoneParentPopover: View {
    let choices: [ParentChoice]
    let theme: Theme
    let pick: (ParentChoice) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(choices) { choice in
                    Button { pick(choice) } label: {
                        ParentChoiceRow(choice: choice, isHighlighted: false, theme: theme)
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .font(.system(size: 17))
        .frame(width: 300, height: min(CGFloat(choices.count) * 44, 360))
    }
}
#endif
