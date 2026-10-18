// The Agenda tab: the title with the month button, the week strip (or the month when it's open), and the day or week
// below it as a row of pages. Swiping the pages moves a day, or a week when a week is picked; swiping the strip moves
// a week; both follow `AppModel.agendaSelection`.
#if os(iOS)
import SwiftUI
import TaDaCore

struct PhoneAgendaScreen: View {
    let model: AppModel
    @State private var search = ListSearch()
    /// On screen: not in another tab, nor under a pushed screen. Only the page on screen sets what can be picked.
    @State private var isOnScreen = false
    @Environment(PhoneNavigation.self) private var nav
    @Environment(SearchHost.self) private var searchHost
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            if search.isSearching {
                ScrollView { PhoneSearchResults(model: model, query: search.query) }
            } else {
                if !search.isOpen { header }
                PhoneAgendaStrip(model: model)
                pages
            }
        }
        .background { theme.color(\.bg).ignoresSafeArea() }
        .navigationTitle("Agenda")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottomTrailing) {
            if !nav.isPicking, !search.isSearching {
                FloatingAddButton { Task { await newTask() } }
            }
        }
        .toolbar {
            if !nav.isPicking, !search.isOpen {
                // The large title is in the page; the bar stays bare.
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
                if model.agendaSelection != .day(model.today) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Today") {
                            nav.play(.pick)
                            withAnimation { model.showAgendaToday() }
                        }
                        .fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Search", systemImage: "magnifyingglass") { search.open() }
                        if !nav.pickable.isEmpty {
                            Button("Select", systemImage: "checkmark.circle") { nav.startPicking() }
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                }
            }
        }
        .pickingBars(model: model)
        .onAppear {
            isOnScreen = true
            searchHost.search = search
        }
        .onDisappear {
            isOnScreen = false
            search.isFocused = false
            if searchHost.search === search { searchHost.search = nil }
        }
        .onChange(of: nav.tab) { search.reset() }
    }

    /// The large title and the month button, which opens and closes the month. The title also steps the Agenda, for
    /// VoiceOver.
    private var header: some View {
        let isWeek = if case .week = model.agendaSelection { true } else { false }
        let unit = isWeek ? "week" : "day"
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Agenda")
                .scaledFont(size: 34, weight: .bold)
                .foregroundStyle(theme.color(\.strong))
                .accessibilityAddTraits(.isHeader)
                .accessibilityAction(named: "Previous \(unit)") { model.stepAgenda(by: -1) }
                .accessibilityAction(named: "Next \(unit)") { model.stepAgenda(by: 1) }
            Spacer(minLength: 0)
            Button { withAnimation { model.agendaMonthOpen.toggle() } } label: {
                HStack(spacing: 4) {
                    Text(model.agendaAnchor.formatted(.monthYear)).lineLimit(1)
                    Image(systemName: model.agendaMonthOpen ? "chevron.up" : "chevron.down")
                        .scaledFont(size: 14, weight: .semibold)
                }
                .scaledFont(size: 16, weight: .semibold)
                .foregroundStyle(theme.color(\.accent))
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(model.agendaMonthOpen ? "Shows one week" : "Shows the month")
        }
        .padding(.horizontal, 16)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// One page for each day, or each week when a week is picked, of which only those near the selection are drawn.
    private var pages: some View {
        let selection = model.agendaSelection
        let isWeek = if case .week = selection { true } else { false }
        return ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(AgendaPaging.keys(like: selection, today: model.today), id: \.self) { key in
                    PhoneAgendaPage(model: model, period: AgendaPaging.selection(forKey: key, like: selection), isOnScreen: isOnScreen)
                        .containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: Binding<Int?> {
            AgendaPaging.key(of: model.agendaSelection)
        } set: { key in
            guard let key, key != AgendaPaging.key(of: model.agendaSelection) else { return }
            model.agendaSelection = AgendaPaging.selection(forKey: key, like: model.agendaSelection)
        })
        // A day's pages and a week's are different rows.
        .id(isWeek)
    }

    /// A new task opens with its title ready to type, due on the selected day.
    private func newTask() async {
        model.domain = .agenda
        await model.newTask()
        if let path = model.selection { nav.push(.file(path)) }
    }
}

/// The weekday initials, then the week or the month, then the handle that opens and closes the month.
struct PhoneAgendaStrip: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        // The weeks beside the selected one are drawn while a swipe settles, so they need their own marks.
        let selected = model.agendaSelection
        let first = AgendaPaging.week(forKey: AgendaPaging.weekKey(of: selected) - 1).firstDay
        let marks = model.agendaMarks.merging(model.index.dayMarks(from: first, through: first.adding(days: 20), names: model.dailyNoteNames)) { current, _ in current }
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("W").frame(width: AgendaWeekRow.weekColumn)
                ForEach(1...7, id: \.self) { Text(Calendar.current.veryShortStandaloneWeekdaySymbols[$0 % 7]).frame(maxWidth: .infinity) }
            }
            .scaledFont(size: 11, weight: .semibold)
            .foregroundStyle(theme.color(\.muted))
            .padding(.bottom, 2)
            .accessibilityHidden(true)
            if model.agendaMonthOpen {
                AgendaMonth(model: model, marks: marks)
            } else {
                AgendaWeekStrip(model: model, marks: marks)
            }
            Button { withAnimation { model.agendaMonthOpen.toggle() } } label: {
                Capsule().fill(theme.color(\.surface)).frame(width: 36, height: 5)
                    .frame(maxWidth: .infinity, minHeight: 18)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.agendaMonthOpen ? "Show one week" : "Show the month")
        }
        .padding(.top, 8)
        .padding(.horizontal, 12)
        .overlay(alignment: .bottom) { Hairline() }
        // Eight columns: past this, the numbers wouldn't fit.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// The selected week as a row of weeks that pages: swiping moves the selection by a week.
struct AgendaWeekStrip: View {
    let model: AppModel
    let marks: [LocalDate: DayMarks]
    @ScaledMetric(relativeTo: .body) private var height = 46

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(AgendaPaging.weeks(today: model.today), id: \.self) { key in
                    AgendaWeekRow(model: model, week: AgendaPaging.week(forKey: key), marks: marks)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .frame(height: height)
        .scrollPosition(id: Binding<Int?> {
            AgendaPaging.weekKey(of: model.agendaSelection)
        } set: { key in
            guard let key, key != AgendaPaging.weekKey(of: model.agendaSelection) else { return }
            model.agendaSelection = AgendaPaging.selection(movingToWeek: key, from: model.agendaSelection)
        })
    }
}

/// Every ISO week of the selection's month.
struct AgendaMonth: View {
    let model: AppModel
    let marks: [LocalDate: DayMarks]

    var body: some View {
        VStack(spacing: 2) {
            ForEach(model.agendaAnchor.isoWeeksOfMonth, id: \.self) { AgendaWeekRow(model: model, week: $0, marks: marks) }
        }
    }
}

/// A week: its number, which picks the week, then its days, which pick a day. Picking in the open month folds it back.
struct AgendaWeekRow: View {
    static let weekColumn: CGFloat = 38

    let model: AppModel
    let week: ISOWeek
    let marks: [LocalDate: DayMarks]
    @ScaledMetric(relativeTo: .body) private var height = 46
    @Environment(\.theme) private var theme

    var body: some View {
        let isSelected = model.agendaSelection == .week(week)
        HStack(spacing: 0) {
            weekCell(isSelected).frame(width: Self.weekColumn)
            ForEach(week.days, id: \.self) { dayCell($0, bandCell: isSelected).frame(maxWidth: .infinity) }
        }
        .frame(height: height)
    }

    private func pick(_ period: AppModel.AgendaSelection) {
        model.agendaSelection = period
        model.agendaMonthOpen = false
    }

    private func weekCell(_ isSelected: Bool) -> some View {
        let hasNote = model.weekNotes && model.index.weekNote(for: week, names: model.dailyNoteNames) != nil
        return Button { withAnimation { pick(.week(week)) } } label: {
            Text("\(week.week)")
                .scaledFont(size: 13, weight: isSelected ? .bold : .semibold)
                .monospacedDigit()
                .foregroundStyle(theme.color(isSelected ? \.bg : hasNote ? \.link : \.muted))
                .frame(width: 30, height: 26)
                .background(isSelected ? theme.color(\.strong) : .clear, in: .rect(cornerRadius: 8))
                .padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(isSelected ? theme.color(\.side) : .clear, in: .rect(cornerRadius: 10))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Week \(week.week)\(hasNote ? ", note" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func dayCell(_ day: LocalDate, bandCell: Bool) -> some View {
        let isSelected = model.agendaSelection == .day(day)
        let isToday = day == model.today
        let faded = day.month != model.agendaAnchor.month || day < model.today
        return Button { withAnimation { pick(.day(day)) } } label: {
            VStack(spacing: 3) {
                Text("\(day.day)")
                    .scaledFont(size: 18, weight: isSelected || isToday ? .bold : .medium)
                    .foregroundStyle(theme.color(isSelected ? \.bg : isToday ? \.accent : faded ? \.muted : \.fg))
                    .frame(width: 30, height: 30)
                    .background(isSelected ? theme.color(isToday ? \.accent : \.strong) : .clear, in: .circle)
                AgendaDots(model: model, day: day, size: 5, marks: marks[day])
            }
            .padding(.top, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(bandCell ? theme.color(\.side) : .clear, in: .rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel((isToday ? "Today, " : "") + day.formatted(.weekdayDayMonth) + AgendaDots.spoken(model, day, marks: marks[day]))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
