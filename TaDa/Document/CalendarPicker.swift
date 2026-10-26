// The calendar under a dueDate or deadline chip: its month in a popup panel, with
// Today, Tomorrow, Next week and Clear. A date typed in its field ("fri", "3d", "25/12") moves a cursor to it,
// and ↵ sets it. A task's due date menu also takes a repeat rule ("every mon") and has a Repeat section under the
// month, whose Ends row swaps the menu to the date the repeat ends.
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
            guard let self else { return false }
            if !model.phrase.isEmpty {
                model.phrase = ""
            } else if model.isEnds {
                model.hideEnds()
            } else {
                return false
            }
            announceToVoiceOver(model.isEnds ? "Repeat ends" : model.kind.name)
            return true
        }
        model.onMonthChange = { [weak self] in self?.layout() }
    }

    /// Shows `kind`'s calendar under `anchor` (screen coordinates) on the month of `selected`, or of today, with
    /// the cursor on that day and `other` (the file's other date) as a dot. `set` gets the date picked, or nil
    /// from Clear.
    /// `repeating` gives a task's menu its Repeat section.
    func show(_ kind: AgendaEntry.Kind, selected: LocalDate?, other: LocalDate?, today: LocalDate, theme: Theme,
              repeating: CalendarPickerModel.Repeating? = nil, below anchor: CGRect, gap: CGFloat = 6, in parent: NSWindow,
              set: @escaping (LocalDate?) -> Void) {
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
        model.configure(repeating)
        model.set = set
        model.revision += 1
        layout()
        announceToVoiceOver("\(kind.name), \(model.cursor.formatted(.weekdayDayMonthYear))")
    }

    func hide() { panel.hide() }

    private func layout() {
        guard let parent else { return }
        panel.show(size: CGSize(width: CalendarMetrics.width,
                                height: CalendarMetrics.height(weeks: MonthGrid(model.cursor).weeks, section: CalendarMetrics.section(model))),
                   below: anchor, inset: 0, gap: gap, in: parent)
    }

    /// Takes ↵; other keys go to the field.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.isDisjoint(with: [.command, .control]),
              event.specialKey == .carriageReturn || event.specialKey == .enter else { return false }
        model.confirm()
        return true
    }
}

#endif

/// The calendar's state: which date it sets, the date it has, and the cursor a typed date moves. In a task's due date
/// menu it also holds the Repeat section: the rule the files share, the rule being typed and the Ends view.
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

    /// What the Repeat section works on: the files, the index their occurrences come from, the rule they all share (nil
    /// when they have none or differ) and what writes a rule, or empties it when nil. `closing` is whether the menu
    /// closes after the write.
    struct Repeating {
        let items: [Item]
        let index: VaultIndex
        let rule: RepeatRule?
        let set: (_ rule: RepeatRule?, _ closing: Bool) -> Void

        init(items: [Item], index: VaultIndex, set: @escaping (_ rule: RepeatRule?, _ closing: Bool) -> Void) {
            let rules = Set(items.map { $0.properties.repeatRule?.rule })
            self.items = items
            self.index = index
            rule = rules.count == 1 ? rules.first ?? nil : nil
            self.set = set
        }
    }

    /// Whether the menu has a Repeat section.
    private(set) var showsRepeat = false
    /// The rule every file has.
    private(set) var current: RepeatRule?
    /// Whether the Ends view shows in place of the date menu.
    private(set) var isEnds = false
    /// The rule typed in the field, when it reads as one that can start.
    private(set) var typedRule: RepeatRule?
    @ObservationIgnored private var items: [Item] = []
    @ObservationIgnored private var index = VaultIndex()
    @ObservationIgnored private var setRepeat: (RepeatRule?, Bool) -> Void = { _, _ in }
    @ObservationIgnored private var laidOut = [false, false, false, false]

    /// Starts the menu with `repeating`'s section, or none, and the date view.
    func configure(_ repeating: Repeating?) {
        showsRepeat = repeating != nil
        isEnds = false
        typedRule = nil
        current = repeating?.rule
        items = repeating?.items ?? []
        index = repeating?.index ?? VaultIndex()
        setRepeat = repeating?.set ?? { _, _ in }
        laidOut = shape
    }

    /// The date typed so far. Each change moves the cursor to the day it gives, if any; emptying it moves the
    /// cursor back to the date shown as set, or today. A phrase starting with "every" in a task's due date menu is read
    /// as a rule instead, leaving the cursor on the date set.
    var phrase = "" {
        didSet {
            guard phrase != oldValue else { return }
            if isRule {
                match = nil
                typedRule = RepeatRule.parse(phrase).flatMap { start(of: $0) == nil ? nil : $0 }
                moveCursor(to: shownDate ?? today)
            } else {
                typedRule = nil
                match = phrase.isEmpty ? nil : DatePhrase.parse(phrase, today: today, order: order, firstWeekday: firstWeekday)
                if let match {
                    moveCursor(to: match)
                } else if phrase.isEmpty {
                    moveCursor(to: shownDate ?? today)
                }
            }
            relayout()
        }
    }
    /// Bumped each time the calendar shows, which gives its field the keyboard.
    var revision = 0
    /// The day ↵ sets while a date is typed: the one it gives, or where the month buttons moved since. Nil when
    /// the typed date gives none.
    private(set) var match: LocalDate?
    @ObservationIgnored var set: (LocalDate?) -> Void = { _ in }
    /// Called when the calendar's height may have changed: the cursor moving into another month, which can have
    /// another number of weeks, or the Repeat section changing.
    @ObservationIgnored var onMonthChange: () -> Void = {}

    var month: LocalDate { cursor.startOfMonth }

    /// Moves the cursor to the same day `months` away, or that month's last day when it's shorter.
    func move(months: Int) {
        moveCursor(to: cursor.adding(months: months) ?? cursor)
        if !phrase.isEmpty { match = cursor }
    }

    /// The day ↵ sets while a date is typed, or that the typed date gives none; nil while nothing is. For a rule, where it
    /// starts, or that the phrase isn't one.
    var note: String? {
        guard !phrase.isEmpty else { return nil }
        if isRule {
            return typedRule.flatMap { start(of: $0) }.map { "From \($0.formatted(.weekdayDayMonth))" } ?? "No match"
        }
        return match?.formatted(.weekdayDayMonth) ?? "No match · \(cursor.formatted(.weekdayDayMonth))"
    }

    /// ↵: sets the typed rule, the end date or the cursor's day.
    func confirm() {
        if isEnds {
            setEnd(cursor)
        } else if isRule {
            if let typedRule { setRepeat(typedRule, true) }
        } else {
            set(cursor)
        }
    }

    /// Sets the day clicked: the end date in the Ends view, else the date.
    func pick(_ day: LocalDate?) {
        if isEnds { setEnd(day) } else { set(day) }
    }

    /// Ends the repeat on `day`, or never when it's nil.
    func setEnd(_ day: LocalDate?) {
        guard let current else { return }
        setRepeat(current.ending(on: day), true)
    }

    /// Stops the repeat.
    func stopRepeating() { setRepeat(nil, true) }

    /// Switches the rule to count from completion, or back to its schedule. The menu stays open.
    func setWhenDone(_ whenDone: Bool) {
        guard let rule = current, rule.whenDone != whenDone else { return }
        current = rule.whenDone(whenDone)
        setRepeat(current, false)
    }

    /// Swaps the menu to the end date, on the date the repeat ends.
    func showEnds() {
        guard current != nil else { return }
        isEnds = true
        phrase = ""
        moveCursor(to: shownDate ?? today)
        relayout()
    }

    /// Swaps the menu back to the due date.
    func hideEnds() {
        isEnds = false
        phrase = ""
        moveCursor(to: selected ?? today)
        relayout()
    }

    /// The date the month fills as set: the repeat's end in the Ends view, else the date.
    var shownDate: LocalDate? { isEnds ? current?.until : selected }

    /// The rule the Repeat section spells out: the one typed, else the one set.
    var displayedRule: RepeatRule? { typedRule ?? current }

    /// The rule the month previews: the typed one, else the set one, with the end being typed in the Ends view.
    private var previewRule: RepeatRule? {
        if isEnds {
            guard let current else { return nil }
            return match.map { current.ending(on: $0) } ?? current
        }
        return displayedRule
    }

    /// `rule` spelled out for the section: "Every week on Monday until Sun 20 Dec".
    func spelled(_ rule: RepeatRule) -> String {
        rule.description { $0.formatted(.weekdayDayMonth) }
    }

    /// The Ends view's line: the rule with the end being picked.
    var endsSummary: String { previewRule.map(spelled) ?? "" }

    /// The days of `month` a coming occurrence of the rule falls on, as ↵ would set it.
    func occurrenceDays(in month: LocalDate) -> Set<LocalDate> {
        guard showsRepeat, let rule = previewRule else { return [] }
        let first = month.startOfMonth, last = month.addingMonths(1).adding(days: -1)
        var days = Set<LocalDate>()
        for item in items {
            var task = item
            var starts: LocalDate?
            if task.properties.dueDate == nil, typedRule != nil, let date = rule.firstDate(from: today) {
                task.properties.dueDate = date
                starts = date
            }
            task.properties.repeatRule = Repeat(text: rule.phrase, rule: rule)
            let dates = index.occurrences(of: task, from: first, through: last, today: today).filter { $0.kind == .due }.map(\.date)
            days.formUnion(dates)
            if let starts, (first...last).contains(starts) { days.insert(starts) }
        }
        return days
    }

    /// Whether the field's phrase is a rule.
    private var isRule: Bool {
        showsRepeat && !isEnds && phrase.drop(while: \.isWhitespace).lowercased().hasPrefix("every")
    }

    /// Where a rule starts: the date set, else its first date; nil when its end has passed.
    private func start(of rule: RepeatRule) -> LocalDate? { selected ?? rule.firstDate(from: today) }

    /// What decides the height of the Repeat section.
    private var shape: [Bool] { [showsRepeat, isEnds, displayedRule != nil, current != nil] }

    private func relayout() {
        guard shape != laidOut else { return }
        laidOut = shape
        onMonthChange()
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

    /// The Repeat section's hairline and the gap under it.
    static let sectionTop: CGFloat = 11
    static let sectionSpacing: CGFloat = 8
    static let ruleLine: CGFloat = 18
    static let helper: CGFloat = 32
    static let setRows: CGFloat = 56
    static let endsSummary: CGFloat = 16

    /// The height of what's under the month: the Repeat section, or the Ends view's line; 0 for neither.
    static func section(_ model: CalendarPickerModel) -> CGFloat {
        guard model.showsRepeat else { return 0 }
        if model.isEnds { return sectionTop + endsSummary }
        var rows = [header, helper]
        if model.displayedRule != nil { rows.append(ruleLine) }
        if model.current != nil { rows.append(setRows) }
        return sectionTop + rows.reduce(0, +) + sectionSpacing * CGFloat(rows.count - 1)
    }

    static func height(weeks: Int, section: CGFloat) -> CGFloat {
        let grid = CGFloat(weeks) * week + CGFloat(weeks - 1) * weekSpacing
        return padding * 2 + PopupMenuStyle.searchHeight + inset.top + inset.bottom + header + quickDay + monthRow + weekdays
            + spacing * 4 + grid + (section > 0 ? spacing + section : 0)
    }
}

private struct CalendarPickerView: View {
    let model: CalendarPickerModel

    var body: some View {
        let theme = model.theme
        let grid = MonthGrid(model.month)
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 0), count: 7)
        let occurrences = model.occurrenceDays(in: model.month)
        VStack(spacing: 0) {
            PopupField(prompt: prompt, systemImage: model.isEnds ? "repeat" : "calendar", text: Binding { model.phrase } set: { phrase in
                guard phrase != model.phrase else { return }
                model.phrase = phrase
                announceToVoiceOver(model.note ?? model.kind.name)
            }, note: model.note, theme: theme, revision: model.revision)
            VStack(alignment: .leading, spacing: CalendarMetrics.spacing) {
                header
                HStack(spacing: 6) {
                    if model.isEnds {
                        QuickDayButton(title: "Never", day: nil, model: model)
                        QuickDayButton(title: "In 4 weeks", day: model.today.adding(days: 28), model: model)
                        QuickDayButton(title: "End of year", day: LocalDate(year: model.today.year, month: 12, day: 31), model: model)
                    } else {
                        QuickDayButton(title: "Today", day: model.today, model: model)
                        QuickDayButton(title: "Tomorrow", day: model.today.adding(days: 1), model: model)
                        QuickDayButton(title: "Next week", day: model.today.nextWeek(firstWeekday: model.firstWeekday), model: model)
                    }
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
                            PickerDayCell(day: day, model: model, isOccurrence: occurrences.contains(day))
                        } else {
                            Color.clear.frame(height: CalendarMetrics.week)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(model.month.formatted(.monthYear))
                if model.showsRepeat {
                    if model.isEnds { EndsSummary(model: model) } else { RepeatSection(model: model) }
                }
            }
            .padding(CalendarMetrics.inset)
        }
        .popupChrome(theme: theme, width: CalendarMetrics.width, padding: CalendarMetrics.padding)
    }

    private var prompt: String {
        if model.isEnds { return "Type an end date: 20 dec, 8w" }
        return model.showsRepeat ? "Type a date or rule: fri, every mon" : "Type a date: fri, 3d, 25/12"
    }

    private var header: some View {
        HStack {
            if model.isEnds {
                Button { model.hideEnds() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
                        Text("REPEAT ENDS")
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(model.theme.color(\.muted))
                .accessibilityLabel("Repeat ends")
                .accessibilityHint("Back to the due date")
            } else {
                Text(model.kind.name.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(model.theme.color(\.muted))
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            if model.shownDate != nil {
                Button("Clear") { model.pick(nil) }
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
    /// Nil for Never, in the Ends view.
    let day: LocalDate?
    let model: CalendarPickerModel
    @Environment(\.theme) private var theme

    var body: some View {
        Button { model.pick(day) } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.color(\.fg))
                .padding(.horizontal, 10)
                .frame(height: CalendarMetrics.quickDay)
                .background(theme.color(\.code), in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(day?.formatted(.weekdayDayMonth) ?? "No end date")
        .accessibilityValue(day?.formatted(.weekdayDayMonth) ?? "No end date")
    }
}

/// A day: today on `surface`, the date set filled in its key's colour (`muted` for the repeat's end), a coming
/// occurrence on a faint `due` fill, the cursor ringed in `accent`, and the file's other date as a dot below.
private struct PickerDayCell: View {
    let day: LocalDate
    let model: CalendarPickerModel
    let isOccurrence: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        let isToday = day == model.today
        let isSet = day == model.shownDate
        let other = model.isEnds ? nil : model.other
        Button { model.pick(day) } label: {
            VStack(spacing: 2) {
                Text("\(day.day)")
                    .font(.system(size: 12, weight: isSet || isToday ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(theme.color(isSet ? \.bg : isToday || isOccurrence ? \.strong : day < model.today ? \.muted : \.fg))
                    .frame(width: 24, height: 20)
                    .background(fill(isSet: isSet, isToday: isToday), in: .capsule)
                    .overlay {
                        if day == model.cursor, !isSet {
                            Capsule().strokeBorder(theme.color(\.accent), lineWidth: 1.5).padding(-1.5)
                        }
                    }
                HStack(spacing: 2) {
                    if day == other {
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

    private func fill(isSet: Bool, isToday: Bool) -> Color {
        if isSet { return theme.color(model.isEnds ? \.muted : model.kind.tint) }
        if isOccurrence { return theme.color(\.due).opacity(theme.isDark ? 0.26 : 0.3) }
        return isToday ? theme.color(\.surface) : .clear
    }

    private var accessibilityText: String {
        var parts = [day.formatted(.weekdayDayMonth)]
        if day == model.today { parts.append("today") }
        if !model.isEnds, day == model.other { parts.append(model.kind == .due ? "deadline" : "due date") }
        if isOccurrence { parts.append("repeats") }
        return parts.joined(separator: ", ")
    }
}

/// The Repeat section under a task's month: its rule spelled out (`muted` while it's only typed), the helper text,
/// and once a rule is set, When done and Ends.
private struct RepeatSection: View {
    let model: CalendarPickerModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: CalendarMetrics.sectionSpacing) {
            HStack {
                Label("REPEAT", systemImage: "repeat")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(theme.color(\.muted))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if model.current != nil {
                    Button("Stop") { model.stopRepeating() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.color(\.muted))
                }
            }
            .padding(.horizontal, 4)
            .frame(height: CalendarMetrics.header)
            if let rule = model.displayedRule {
                let text = model.spelled(rule)
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.color(model.typedRule == nil ? \.strong : \.muted))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .frame(height: CalendarMetrics.ruleLine, alignment: .leading)
                    .help(text)
            }
            Text("Type repetition rules naturally. They're recognised as you type.")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.color(\.muted))
                .padding(.horizontal, 4)
                .frame(height: CalendarMetrics.helper, alignment: .topLeading)
            if let rule = model.current {
                VStack(spacing: 0) {
                    HStack {
                        Text("When done").foregroundStyle(theme.color(\.fg))
                        Spacer()
                        Toggle("When done", isOn: Binding { rule.whenDone } set: { model.setWhenDone($0) })
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .tint(theme.color(\.accent))
                    }
                    .padding(.horizontal, 4)
                    .frame(height: 28)
                    .accessibilityElement(children: .combine)
                    Button { model.showEnds() } label: {
                        HStack(spacing: 6) {
                            Text("Ends").foregroundStyle(theme.color(\.fg))
                            Spacer()
                            Text(rule.until?.formatted(.weekdayDayMonth) ?? "Never")
                                .foregroundStyle(theme.color(rule.until == nil ? \.muted : \.fg))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.color(\.muted))
                        }
                        .padding(.horizontal, 4)
                        .frame(height: 28)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ends")
                    .accessibilityValue(rule.until?.formatted(.weekdayDayMonthYear) ?? "Never")
                }
                .font(.system(size: 13))
            }
        }
        .padding(.top, CalendarMetrics.sectionTop)
        .overlay(alignment: .top) { Rectangle().fill(theme.color(\.border)).frame(height: 1) }
    }
}

/// The Ends view's line under the month: the rule with the end being picked.
private struct EndsSummary: View {
    let model: CalendarPickerModel
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "repeat").font(.system(size: 11, weight: .semibold))
            Text(model.endsSummary).lineLimit(1)
        }
        .font(.system(size: 12))
        .foregroundStyle(theme.color(\.muted))
        .padding(.horizontal, 4)
        .padding(.top, CalendarMetrics.sectionTop - 1)
        .frame(height: CalendarMetrics.sectionTop + CalendarMetrics.endsSummary, alignment: .topLeading)
        .overlay(alignment: .top) { Rectangle().fill(theme.color(\.border)).frame(height: 1) }
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
