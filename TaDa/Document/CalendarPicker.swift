// The calendar under a dueDate or deadline chip: its month in a popup panel, with
// Today, Tomorrow, Next week and Clear. A date typed in its field ("fri", "3d", "25/12") moves a cursor to it,
// and ↵ sets it.
import SwiftUI
import TaDaCore
#if os(macOS)
import AppKit

/// Shows the calendar under a chip and passes on the date picked in it.
final class CalendarPicker {
    private let model: CalendarPickerModel
    private let panel: PopupPanel<CalendarPickerView>
    private var anchor = CGRect.zero
    private var gap: CGFloat = 6
    private weak var parent: NSWindow?

    /// What a click elsewhere, a scroll or esc does.
    var onDismiss: (() -> Void)? {
        get { panel.onDismiss }
        set { panel.onDismiss = newValue }
    }

    init() {
        let model = CalendarPickerModel()
        self.model = model
        panel = PopupPanel(becomesKey: true) { CalendarPickerView(model: model) }
        panel.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        panel.onEscape = { [weak self] in
            guard let self, !model.phrase.isEmpty else { return false }
            model.phrase = ""
            announceToVoiceOver(model.kind.name)
            return true
        }
        model.onMonthChange = { [weak self] in self?.layout() }
    }

    /// Shows `kind`'s calendar under `anchor` (screen coordinates) on the month of `selected`, or of today, with
    /// the cursor on that day and `other` (the file's other date) as a dot. `set` gets the date picked, or nil
    /// from Clear.
    func show(_ kind: AgendaEntry.Kind, selected: LocalDate?, other: LocalDate?, today: LocalDate, theme: Theme,
              below anchor: CGRect, gap: CGFloat = 6, in parent: NSWindow, set: @escaping (LocalDate?) -> Void) {
        self.anchor = anchor
        self.gap = gap
        self.parent = parent
        model.kind = kind
        model.selected = selected
        model.other = other
        model.today = today
        model.order = .system
        model.firstWeekday = Calendar.current.firstWeekday
        model.phrase = ""
        model.cursor = selected ?? today
        model.theme = theme
        model.set = set
        model.revision += 1
        layout()
        announceToVoiceOver("\(kind.name), \(model.cursor.formatted(.weekdayDayMonthYear))")
    }

    func hide() { panel.hide() }

    private func layout() {
        guard let parent else { return }
        panel.show(size: CGSize(width: CalendarMetrics.width, height: CalendarMetrics.height(weeks: MonthGrid(model.cursor).weeks)),
                   below: anchor, inset: 0, gap: gap, in: parent)
    }

    /// Takes ↵; other keys go to the field.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.isDisjoint(with: [.command, .control]),
              event.specialKey == .carriageReturn || event.specialKey == .enter else { return false }
        model.set(model.cursor)
        return true
    }
}

#endif

/// The calendar's state: which date it sets, the date it has, and the cursor a typed date moves.
@Observable
final class CalendarPickerModel {
    var kind = AgendaEntry.Kind.due
    var selected: LocalDate?
    /// The file's other date, shown as a dot.
    var other: LocalDate?
    var today = LocalDate(Date())
    /// The day ↵ sets. The calendar shows its month.
    var cursor = LocalDate(Date())
    var theme = Theme.all[0]
    /// Which a typed numeric date gives first.
    var order = DayOrder.dayMonth
    /// The locale's first weekday (1 = Sunday), for Next week.
    var firstWeekday = 2
    /// The date typed so far. Each change moves the cursor to the day it gives, if any; emptying it moves the
    /// cursor back to the date set, or today.
    var phrase = "" {
        didSet {
            guard phrase != oldValue else { return }
            match = phrase.isEmpty ? nil : DatePhrase.parse(phrase, today: today, order: order, firstWeekday: firstWeekday)
            if let match {
                moveCursor(to: match)
            } else if phrase.isEmpty {
                moveCursor(to: selected ?? today)
            }
        }
    }
    /// Bumped each time the calendar shows, which gives its field the keyboard.
    var revision = 0
    /// The day ↵ sets while a date is typed: the one it gives, or where the month buttons moved since. Nil when
    /// the typed date gives none.
    private(set) var match: LocalDate?
    @ObservationIgnored var set: (LocalDate?) -> Void = { _ in }
    /// Called when the cursor moves into another month, which can have another number of weeks.
    @ObservationIgnored var onMonthChange: () -> Void = {}

    var month: LocalDate { cursor.startOfMonth }

    /// Moves the cursor to the same day `months` away, or that month's last day when it's shorter.
    func move(months: Int) {
        moveCursor(to: cursor.adding(months: months) ?? cursor)
        if !phrase.isEmpty { match = cursor }
    }

    /// The day ↵ sets while a date is typed, or that the typed date gives none; nil while nothing is.
    var note: String? {
        guard !phrase.isEmpty else { return nil }
        return match?.formatted(.weekdayDayMonth) ?? "No match · \(cursor.formatted(.weekdayDayMonth))"
    }

    private func moveCursor(to day: LocalDate) {
        let before = month
        cursor = day
        if month != before { onMonthChange() }
    }
}

#if os(macOS)
/// The calendar's sizes, which give the panel its height.
private enum CalendarMetrics {
    static let width: CGFloat = 288
    static let padding: CGFloat = 6
    static let inset = EdgeInsets(top: 6, leading: 6, bottom: 4, trailing: 6)
    static let spacing: CGFloat = 10
    static let header: CGFloat = 18
    static let quickDay: CGFloat = 24
    static let monthRow: CGFloat = 22
    static let weekdays: CGFloat = 14
    static let week: CGFloat = 30
    static let weekSpacing: CGFloat = 2

    static func height(weeks: Int) -> CGFloat {
        let grid = CGFloat(weeks) * week + CGFloat(weeks - 1) * weekSpacing
        return padding * 2 + PopupMenuStyle.searchHeight + inset.top + inset.bottom + header + quickDay + monthRow + weekdays
            + spacing * 4 + grid
    }
}

private struct CalendarPickerView: View {
    let model: CalendarPickerModel

    var body: some View {
        let theme = model.theme
        let grid = MonthGrid(model.month)
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 0), count: 7)
        VStack(spacing: 0) {
            PopupField(prompt: "Type a date: fri, 3d, 25/12", systemImage: "calendar", text: Binding { model.phrase } set: { phrase in
                guard phrase != model.phrase else { return }
                model.phrase = phrase
                announceToVoiceOver(model.note ?? model.kind.name)
            }, note: model.note, theme: theme, revision: model.revision)
            VStack(alignment: .leading, spacing: CalendarMetrics.spacing) {
                header
                HStack(spacing: 6) {
                    QuickDayButton(title: "Today", day: model.today, model: model)
                    QuickDayButton(title: "Tomorrow", day: model.today.adding(days: 1), model: model)
                    QuickDayButton(title: "Next week", day: model.today.nextWeek(firstWeekday: model.firstWeekday), model: model)
                }
                HStack(spacing: 2) {
                    Text(model.month.formatted(.monthYear))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.color(\.strong))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    MonthStepButton(forward: false) { model.move(months: -1) }
                    MonthStepButton(forward: true) { model.move(months: 1) }
                }
                .padding(.horizontal, 2)
                .frame(height: CalendarMetrics.monthRow)
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(grid.weekdaySymbols.indices, id: \.self) { i in
                        Text(grid.weekdaySymbols[i]).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(theme.color(\.muted))
                    }
                }
                .frame(height: CalendarMetrics.weekdays)
                .accessibilityHidden(true)
                LazyVGrid(columns: columns, spacing: CalendarMetrics.weekSpacing) {
                    ForEach(grid.days.indices, id: \.self) { i in
                        if let day = grid.days[i] {
                            PickerDayCell(day: day, model: model)
                        } else {
                            Color.clear.frame(height: CalendarMetrics.week)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(model.month.formatted(.monthYear))
            }
            .padding(CalendarMetrics.inset)
        }
        .popupChrome(theme: theme, width: CalendarMetrics.width, padding: CalendarMetrics.padding)
    }

    private var header: some View {
        HStack {
            Text(model.kind.name.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(model.theme.color(\.muted))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if model.selected != nil {
                Button("Clear") { model.set(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(model.theme.color(\.muted))
            }
        }
        .padding(.horizontal, 4)
        .frame(height: CalendarMetrics.header)
    }
}

/// A pill that sets a day near today; its tooltip says which.
private struct QuickDayButton: View {
    let title: String
    let day: LocalDate
    let model: CalendarPickerModel
    @Environment(\.theme) private var theme

    var body: some View {
        Button { model.set(day) } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.color(\.fg))
                .padding(.horizontal, 10)
                .frame(height: CalendarMetrics.quickDay)
                .background(theme.color(\.code), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(day.formatted(.weekdayDayMonth))
        .accessibilityValue(day.formatted(.weekdayDayMonth))
    }
}

/// A day: today on `surface`, the date set filled in its key's colour, the cursor ringed in `accent`, and the
/// file's other date as a dot below.
private struct PickerDayCell: View {
    let day: LocalDate
    let model: CalendarPickerModel
    @Environment(\.theme) private var theme

    var body: some View {
        let isToday = day == model.today
        let isSet = day == model.selected
        Button { model.set(day) } label: {
            VStack(spacing: 2) {
                Text("\(day.day)")
                    .font(.system(size: 12, weight: isSet || isToday ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(theme.color(isSet ? \.bg : isToday ? \.strong : day < model.today ? \.muted : \.fg))
                    .frame(width: 24, height: 20)
                    .background(isSet ? theme.color(model.kind.tint) : isToday ? theme.color(\.surface) : .clear, in: .capsule)
                    .overlay {
                        if day == model.cursor, !isSet {
                            Capsule().strokeBorder(theme.color(\.accent), lineWidth: 1.5).padding(-1.5)
                        }
                    }
                HStack(spacing: 2) {
                    if day == model.other {
                        if model.kind == .due {
                            RoundedRectangle(cornerRadius: 1).fill(theme.color(\.deadline)).frame(width: 4, height: 4)
                        } else {
                            Circle().fill(theme.color(\.due)).frame(width: 4, height: 4)
                        }
                    }
                }
                .frame(height: 4)
            }
            .padding(.top, 3)
            .frame(maxWidth: .infinity)
            .frame(height: CalendarMetrics.week, alignment: .top)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSet ? .isSelected : [])
    }

    private var accessibilityText: String {
        var parts = [day.formatted(.weekdayDayMonth)]
        if day == model.today { parts.append("today") }
        if day == model.other { parts.append(model.kind == .due ? "deadline" : "due date") }
        return parts.joined(separator: ", ")
    }
}

/// The chevron that shows the previous or next month.
struct MonthStepButton: View {
    let forward: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: forward ? "chevron.right" : "chevron.left")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.color(\.muted))
                .frame(width: 22, height: 22)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(forward ? "Next month" : "Previous month")
    }
}
#endif
