// The Agenda tab's pages: a day (its note, events and reminders, then its tasks and its repeating tasks' occurrences) or
// a week (its note, a row for each day, then the tasks due in it), and the cards and rows that open a day's or a week's note.
#if os(iOS)
import SwiftUI
import TaDaCore

/// One day's or one week's page, which scrolls on its own. Its tasks come from the model when it's the selected one.
struct PhoneAgendaPage: View {
    let model: AppModel
    let period: AppModel.AgendaSelection
    let isOnScreen: Bool
    let search: ListSearch

    var body: some View {
        switch period {
        case let .day(day): PhoneAgendaDay(model: model, day: day, isOnScreen: isOnScreen, search: search)
        case let .week(week): PhoneAgendaWeek(model: model, week: week, isOnScreen: isOnScreen, search: search)
        }
    }
}

/// What a page sets the list's picking to, while it's the one on screen.
private struct PickState: Equatable {
    var paths: [String]
    var isActive: Bool
}

private struct PhoneAgendaDay: View {
    let model: AppModel
    let day: LocalDate
    let isOnScreen: Bool
    let search: ListSearch
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let isSelected = model.agendaSelection == .day(day)
        let list = GroupedList.today
        let all = isSelected ? model.agendaTasks : model.index.agendaDay(day, today: model.today)
        let filter = model.tagFilter(on: .agenda)
        let tasks = filter.apply(all)
        let grouping = model.grouping(of: list)
        let groups = grouping == .project ? model.index.grouped(tasks) : []
        let sections = grouping == .project ? [] : ListSection.sections(tasks, by: grouping, today: model.today)
        let events = filter.isActive ? [] : model.events(on: day), reminders = filter.isActive ? [] : model.reminders(on: day)
        let occurrences = (isSelected ? model.agendaOccurrences : model.index.occurrences(from: day, through: day, today: model.today))
            .filter { filter.matches($0.item) }
        let note = model.note(for: .day(day))
        let pickable = grouping == .project ? groups.flatMap(\.tasks).map(\.path)
            : sections.filter { !model.isFolded($0, by: grouping, in: list.foldKey) }.flatMap(\.tasks).map(\.path)
        let context: IntegrationRowContext = day == model.today ? .today : .upcoming

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(day.formatted(.fullDate)).scaledFont(size: 22, weight: .bold).foregroundStyle(theme.color(\.strong))
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    if let relative = model.relativeDayName(day) {
                        Text(relative).scaledFont(size: 15, weight: .semibold).foregroundStyle(theme.color(\.accent))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                AgendaNote(model: model, period: .day(day), note: note, isInline: day == model.today)
                if !events.isEmpty || !reminders.isEmpty {
                    Color.clear.frame(height: 6)
                    ForEach(events) { EventRow(event: $0, day: day, context: context) }
                    ForEach(reminders) { ReminderRow(reminder: $0, context: context, today: day == model.today ? model.today : nil) }
                }
                if !all.isEmpty {
                    HStack {
                        Text("Scheduled").scaledFont(size: 15, weight: .semibold).foregroundStyle(theme.color(\.strong))
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        PhoneGroupMenu(model: model, list: list)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    PhoneTagFilterBar(model: model, domain: .agenda, items: all, shown: tasks.count)
                    if tasks.isEmpty {
                        ContentUnavailableView("No matches", systemImage: "line.3.horizontal.decrease",
                                               description: Text("No task here carries the picked tags.")).padding(.top, 40)
                    } else if grouping == .project {
                        ForEach(groups) { group in
                            if let parent = group.parent {
                                if parent.properties.kind == .area {
                                    PhoneAreaHeader(area: parent)
                                } else {
                                    PhoneProjectHeader(model: model, project: parent)
                                }
                            }
                            ForEach(group.tasks) { PhoneTaskRow(model: model, item: $0, meta: .row(.agenda)) }
                        }
                    } else {
                        PhoneTaskSections(model: model, sections: sections, grouping: grouping, foldKey: list.foldKey,
                                          dates: .agenda, place: { model.index.parent(of: $0)?.title })
                    }
                } else if note == nil, events.isEmpty, reminders.isEmpty, occurrences.isEmpty {
                    Text("Nothing scheduled").scaledFont(size: 15).foregroundStyle(theme.color(\.muted))
                        .frame(maxWidth: .infinity).padding(.top, 24)
                }
                if !occurrences.isEmpty { AgendaRepeats(model: model, occurrences: occurrences) }
                PickingBarClearance()
            }
        }
        .scrollBounceBehavior(.always, axes: .vertical)
        .pullToSearch(search, hostsSearch: false)
        .onChange(of: PickState(paths: pickable, isActive: isSelected && isOnScreen), initial: true) { _, state in
            if state.isActive { nav.setPickable(state.paths) }
        }
    }
}

private struct PhoneAgendaWeek: View {
    let model: AppModel
    let week: ISOWeek
    let isOnScreen: Bool
    let search: ListSearch
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let isSelected = model.agendaSelection == .week(week)
        let entries = isSelected ? model.agendaWeekEntries : model.index.agendaWeek(week)
        let occurrences = isSelected ? model.agendaOccurrences
            : model.index.occurrences(from: week.firstDay, through: week.firstDay.adding(days: 6), today: model.today)
        var seen = Set<String>()
        // A task can have two entries (due and deadline); picking lists it once.
        let paths = entries.map(\.item.path).filter { seen.insert($0).inserted }

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Week \(week.week)").scaledFont(size: 22, weight: .bold).foregroundStyle(theme.color(\.strong))
                        .accessibilityAddTraits(.isHeader)
                    Text("\(week.firstDay.formatted(.dayMonth)) – \(week.firstDay.adding(days: 6).formatted(.dayMonth))")
                        .scaledFont(size: 15).foregroundStyle(theme.color(\.muted)).lineLimit(1)
                    Spacer(minLength: 0)
                    if week == model.today.isoWeek {
                        Text("This week").scaledFont(size: 15, weight: .semibold).foregroundStyle(theme.color(\.accent))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                if model.weekNotes {
                    AgendaNote(model: model, period: .week(week), note: model.note(for: .week(week)), isInline: true)
                }
                Color.clear.frame(height: 10)
                ForEach(week.days, id: \.self) { dayRow($0, entries: entries, occurrences: occurrences) }
                if !entries.isEmpty {
                    VStack(spacing: 7) {
                        Text("Due this week").scaledFont(size: 15, weight: .semibold).foregroundStyle(theme.color(\.strong))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.isHeader)
                        Hairline()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    ForEach(entries) { entry in
                        PhoneTaskRow(model: model, item: entry.item,
                                     meta: .agenda(entry, place: model.index.parent(of: entry.item)?.title ?? "Loose task"))
                    }
                }
                PickingBarClearance()
            }
        }
        .scrollBounceBehavior(.always, axes: .vertical)
        .pullToSearch(search, hostsSearch: false)
        .onChange(of: PickState(paths: paths, isActive: isSelected && isOnScreen), initial: true) { _, state in
            if state.isActive { nav.setPickable(state.paths) }
        }
    }

    /// A day: its label, its note's first paragraph with its dots, and what it holds. A tap picks the day.
    private func dayRow(_ day: LocalDate, entries: [AgendaEntry], occurrences: [Occurrence]) -> some View {
        let note = model.index.dailyNote(for: day, names: model.dailyNoteNames)
        let counts = model.agendaDaySummary(day, entries: entries, occurrences: occurrences)
        let firstRepeat = model.firstRepeat(on: day, entries: entries, occurrences: occurrences)
        let marks = model.index.dayMarks(from: day, through: day, today: model.today, names: model.dailyNoteNames)[day]
        return Button { withAnimation { model.agendaSelection = .day(day) } } label: {
            HStack(spacing: 12) {
                Text(day.formatted(.weekdayDay))
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(theme.color(day == model.today ? \.accent : \.strong))
                    .frame(width: 56, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        AgendaDots(model: model, day: day, size: 6, marks: marks)
                        if let firstRepeat {
                            Image(systemName: "repeat").scaledFont(size: 14).foregroundStyle(theme.color(\.muted)).accessibilityHidden(true)
                            Text(firstRepeat.title).scaledFont(size: 16).foregroundStyle(theme.color(\.muted)).lineLimit(1)
                        } else {
                            Text(note == nil ? "No note" : note?.summary ?? "")
                                .scaledFont(size: 16)
                                .foregroundStyle(theme.color(note == nil ? \.muted : \.fg))
                                .lineLimit(1)
                        }
                    }
                    if !counts.isEmpty {
                        Text(counts).scaledFont(size: 13).foregroundStyle(theme.color(\.muted)).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .scaledMinHeight(52)
                .padding(.trailing, 16)
                .overlay(alignment: .bottom) { Hairline() }
            }
            .padding(.leading, 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.fullDate) + (note == nil ? ", no note" : ", note") + (counts.isEmpty ? "" : ", " + counts)
                            + AgendaDots.spoken(model, day, marks: marks))
    }
}

/// The Repeats group: a muted row for each occurrence on the day, with a box that can't be ticked. A tap opens the task.
private struct AgendaRepeats: View {
    let model: AppModel
    let occurrences: [Occurrence]
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "repeat").scaledFont(size: 14).accessibilityHidden(true)
                Text("Repeats").scaledFont(size: 15, weight: .semibold)
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.color(\.muted))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Hairline()
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        ForEach(occurrences, id: \.self) { row($0) }
    }

    private func row(_ occurrence: Occurrence) -> some View {
        let item = occurrence.item
        let place = model.occurrencePlace(occurrence) ?? "Loose task"
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(theme.color(\.muted).opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                Button { if !nav.isPicking { nav.push(.file(item.path)) } } label: {
                    HStack(spacing: 8) {
                        OccurrencePills(occurrence: occurrence)
                        Text(item.title).scaledFont(size: 17).lineLimit(1).layoutPriority(1)
                        Image(systemName: "repeat").scaledFont(size: 14).accessibilityHidden(true)
                        Spacer(minLength: 8)
                        Text(place).scaledFont(size: 15).lineLimit(1).layoutPriority(-1)
                    }
                    .foregroundStyle(theme.color(\.muted))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.occurrenceLabel(occurrence, place: place))
                .accessibilityHint("Opens the task")
            }
            .padding(.horizontal, 16)
            .scaledMinHeight(46)
            PhoneRowSeparator()
        }
    }
}

/// A day's or a week's note: as a card with its checkbox lines and first paragraph when `isInline`, else as a row with
/// its first paragraph; or, with no note, the row that starts it. Each opens the file.
private struct AgendaNote: View {
    let model: AppModel
    let period: AppModel.AgendaSelection
    let note: Item?
    let isInline: Bool
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    private var isDay: Bool { if case .day = period { true } else { false } }
    private var name: String { isDay ? "Daily note" : "Week note" }
    private var file: String { String(model.notePath(for: period).split(separator: "/").last ?? "") }

    var body: some View {
        Group {
            if let note, isInline {
                AgendaNoteCard(model: model, note: note, name: name, systemImage: isDay ? "doc.text" : "calendar")
            } else if let note {
                row(note)
            } else {
                startRow
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private func row(_ note: Item) -> some View {
        let open = model.index.openCheckboxCount(note)
        let isPast = if case let .day(day) = period { day < model.today } else { false }
        return Button { nav.push(.file(note.path)) } label: {
            HStack(spacing: 10) {
                Image(systemName: isDay ? "doc.text" : "calendar").scaledFont(size: 17).foregroundStyle(theme.color(\.muted))
                    .accessibilityHidden(true)
                Text(name).scaledFont(size: 15, weight: .semibold).foregroundStyle(theme.color(\.strong))
                Text(note.summary ?? "").scaledFont(size: 14).foregroundStyle(theme.color(\.muted)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isPast, open > 0 {
                    HStack(spacing: 4) {
                        Circle().fill(theme.color(\.due)).frame(width: 6, height: 6)
                        Text("\(open) open")
                    }
                    .scaledFont(size: 12)
                    .foregroundStyle(theme.color(\.strong))
                    .padding(.horizontal, 8)
                    .scaledMinHeight(22)
                    .background(theme.dueFill, in: .capsule)
                }
            }
            .padding(.horizontal, 14)
            .scaledMinHeight(48)
            .background(theme.color(\.side), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.color(\.border)))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open the \(name.lowercased()) \(file)" + (isPast && open > 0 ? ", \(open) open" : ""))
    }

    private var startRow: some View {
        let title = isDay ? "Start this day’s note" : "Start the week note"
        return Button {
            Task {
                await model.openOrCreateNote(for: period)
                if let path = model.selection { nav.push(.file(path)) }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus").scaledFont(size: 17, weight: .semibold).accessibilityHidden(true)
                Text(title).scaledFont(size: 15, weight: .semibold).foregroundStyle(theme.color(\.fg))
                Spacer(minLength: 8)
                Text(file).scaledFont(size: 13).lineLimit(1)
            }
            .foregroundStyle(theme.color(\.muted))
            .padding(.horizontal, 14)
            .scaledMinHeight(48)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.color(\.surface), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start the \(name.lowercased()) \(file)")
    }
}

/// A note drawn in the page: its name and checkbox count, its checkbox lines, then its first paragraph.
private struct AgendaNoteCard: View {
    let model: AppModel
    let note: Item
    let name: String
    let systemImage: String
    @State private var loaded: [NoteBoxLine]?
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let boxes = note.subtasks
        Button { nav.push(.file(note.path)) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: systemImage).scaledFont(size: 17).foregroundStyle(theme.color(\.muted)).accessibilityHidden(true)
                    Text(name).scaledFont(size: 15, weight: .semibold).foregroundStyle(theme.color(\.strong))
                    Spacer(minLength: 8)
                    if boxes.total > 0 {
                        Text("\(boxes.done)/\(boxes.total)").scaledFont(size: 13).foregroundStyle(theme.color(\.muted))
                    }
                    Image(systemName: "chevron.right").scaledFont(size: 13, weight: .semibold).foregroundStyle(theme.color(\.muted))
                        .accessibilityHidden(true)
                }
                .padding(.top, 10)
                .padding(.bottom, 6)
                VStack(alignment: .leading, spacing: 0) {
                    if let lines = model.cachedBoxLines(of: note) ?? loaded {
                        ForEach(lines.indices, id: \.self) { line(lines[$0]) }
                    } else {
                        // Room for the lines until they're read, so nothing below moves.
                        ForEach(0..<NoteBoxLine.count(of: note.checkboxes), id: \.self) { _ in Color.clear.scaledMinHeight(26) }
                    }
                    if let summary = note.summary {
                        Text(summary).scaledFont(size: 15).foregroundStyle(theme.color(\.muted)).lineLimit(1).padding(.top, 4)
                    }
                }
                .padding(.leading, 29)
                .padding(.bottom, 12)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.color(\.side), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.color(\.border)))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open the \(name.lowercased()), \(boxes.done) of \(boxes.total) done")
        .task(id: note) { loaded = await model.boxLines(of: note) }
    }

    private func line(_ line: NoteBoxLine) -> some View {
        let tint: KeyPath<Theme, PlatformColor> = switch line.state {
        case .done: \.done
        case .doing: \.doing
        case .open: \.muted
        }
        return HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(theme.color(tint), lineWidth: 1.5)
                .background(line.state == .done ? theme.color(tint) : .clear, in: .rect(cornerRadius: 4))
                .frame(width: 16, height: 16)
                .overlay {
                    switch line.state {
                    case .done: Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(theme.color(\.bg))
                    case .doing: RoundedRectangle(cornerRadius: 1.5).fill(theme.color(tint)).frame(width: 6, height: 6)
                    case .open: EmptyView()
                    }
                }
                .accessibilityHidden(true)
            Text(line.text)
                .scaledFont(size: 15)
                .strikethrough(line.state == .done)
                .foregroundStyle(theme.color(line.state == .done ? \.muted : \.fg))
                .lineLimit(1)
        }
        .scaledMinHeight(26)
    }
}
#endif
