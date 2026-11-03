// The Agenda's day: the daily note's row, the day's events then reminders, then the picked tags' chips and the Group and
// Filter capsule over its tasks as Today's list groups them, then the coming occurrences of repeating tasks in a
// Repeats group. While tags are picked the events and reminders hide.
#if os(macOS)
import SwiftUI
import TaDaCore

struct AgendaDayList: View {
    let model: AppModel
    let day: LocalDate
    @Environment(\.theme) private var theme

    var body: some View {
        let list = GroupedList.today
        let all = model.agendaTasks
        let filter = model.tagFilter(on: .agenda)
        let tasks = filter.apply(all)
        let grouping = model.grouping(of: list)
        let groups = grouping == .project ? model.index.grouped(tasks) : []
        let sections = grouping == .project ? [] : ListSection.sections(tasks, by: grouping, today: model.today)
        let events = filter.isActive ? [] : model.events(on: day), reminders = filter.isActive ? [] : model.reminders(on: day)
        let occurrences = model.agendaOccurrences.filter { filter.matches($0.item) }
        let shownPaths = grouping == .project ? groups.flatMap(\.tasks).map(\.path)
            : TaskSections.shown(sections, by: grouping, in: list.foldKey, model: model)

        BrowserColumn(model: model, paths: shownPaths, spacing: 22) {
            AgendaStrip(model: model)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                AgendaNoteRow(model: model, period: .day(day))
                if !events.isEmpty || !reminders.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(events) { EventRow(event: $0, day: day, context: .today) }
                        ForEach(reminders) { ReminderRow(reminder: $0, context: .today, today: day == model.today ? model.today : nil) }
                    }
                    .padding(.top, 4)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                if !all.isEmpty || filter.isActive {
                    HStack(alignment: .top, spacing: 8) {
                        TagFilterRow(model: model, domain: .agenda, items: all, shown: (tasks.count, all.count))
                        Spacer(minLength: 8)
                        GroupFilterButton(model: model, list: all.isEmpty ? nil : list, domain: .agenda, items: all)
                    }
                }
                if !all.isEmpty {
                    VStack(alignment: .leading, spacing: 22) {
                        if tasks.isEmpty {
                            Text("Nothing here carries the picked tags.").foregroundStyle(theme.color(\.muted)).padding(.horizontal, 10)
                        } else if grouping == .project {
                            ProjectGroups(model: model, groups: groups, dates: .agenda)
                        } else {
                            TaskSections(model: model, sections: sections, grouping: grouping, foldKey: list.foldKey,
                                         dates: .agenda, place: { model.index.parent(of: $0)?.title })
                        }
                    }
                }
            }
            if all.isEmpty, events.isEmpty, reminders.isEmpty, occurrences.isEmpty {
                Text("Nothing scheduled").foregroundStyle(theme.color(\.muted)).padding(.horizontal, 10)
            }
            if !occurrences.isEmpty { AgendaRepeats(model: model, occurrences: occurrences) }
        }
        .showsAgendaNote(model)
    }
}

/// The Repeats group: a muted row for each occurrence on the day, with a box that can't be ticked. A click opens the task
/// alone; the rows stay out of the list's keys and picks.
private struct AgendaRepeats: View {
    let model: AppModel
    let occurrences: [Occurrence]
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            VStack(spacing: 7) {
                HStack(spacing: 8) {
                    Image(systemName: "repeat").font(.system(size: 12)).accessibilityHidden(true)
                    Text("Repeats").fontWeight(.semibold)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(theme.color(\.muted))
                .padding(.horizontal, 10)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Hairline()
            }
            .padding(.bottom, 4)
            ForEach(occurrences, id: \.self) { row($0) }
        }
    }

    private func row(_ occurrence: Occurrence) -> some View {
        let item = occurrence.item
        let selected = model.isSelected(item.path)
        let help = RepeatWording.occurrenceHelp(occurrence, today: model.today)
        let place = model.occurrencePlace(occurrence)
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(theme.color(\.muted).opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Button { model.selectOnly(item.path) } label: {
                HStack(spacing: 8) {
                    OccurrencePills(occurrence: occurrence)
                    Text(item.title)
                        .font(.system(size: 13.5))
                        .foregroundStyle(theme.color(\.muted))
                        .lineLimit(1)
                        .layoutPriority(1)
                    Image(systemName: "repeat").font(.system(size: 11.5)).foregroundStyle(theme.color(\.muted)).accessibilityHidden(true)
                    Spacer(minLength: 8)
                    if let place {
                        Text(place).font(.system(size: 12)).foregroundStyle(theme.color(\.muted)).lineLimit(1).layoutPriority(-1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.occurrenceLabel(occurrence, place: place))
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(selected ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 7))
        .help(help)
    }
}

/// A day's or week's note as one row: its name, file and first paragraph, and its checkboxes; or, with no note, the
/// row that starts it.
struct AgendaNoteRow: View {
    let model: AppModel
    let period: AppModel.AgendaSelection
    @State private var loaded: [NoteBoxLine]?
    @Environment(\.theme) private var theme

    private var isDay: Bool { if case .day = period { true } else { false } }

    var body: some View {
        let file = String(model.notePath(for: period).split(separator: "/").last ?? "")
        if let note = model.note(for: period) {
            noteRow(note, file: file)
        } else {
            Button { Task { await model.openOrCreateNote(for: period) } } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).accessibilityHidden(true)
                    Text(isDay ? "Start this day’s note" : "Start the week note").foregroundStyle(theme.color(\.fg))
                    Spacer(minLength: 8)
                    Text(file).font(.system(size: 11.5, design: .monospaced))
                }
                .foregroundStyle(theme.color(\.muted))
                .padding(.horizontal, 10)
                .frame(height: 34)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.color(\.surface), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDay ? "Start this day’s note" : "Start the week note")
        }
    }

    private func noteRow(_ note: Item, file: String) -> some View {
        let selected = model.selection == note.path
        let boxes = note.subtasks
        let open = model.index.openCheckboxCount(note)
        let past = if case let .day(day) = period { day < model.today } else { false }
        return Button { model.selection = note.path } label: {
            HStack(alignment: .top, spacing: 10) {
                NoteIcon().padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(isDay ? "Daily note" : "Week note").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(theme.color(\.strong))
                    HStack(spacing: 8) {
                        Text(file).font(.system(size: 11.5, design: .monospaced)).layoutPriority(1)
                        if let summary = note.summary {
                            Text("·")
                            Text(summary)
                        }
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.color(\.muted))
                    .lineLimit(1)
                    if let lines = model.cachedBoxLines(of: note) ?? loaded {
                        ForEach(lines.indices, id: \.self) { boxLine(lines[$0]) }
                    } else {
                        // Room for the lines until they're read, so nothing below moves.
                        ForEach(0..<NoteBoxLine.count(of: note.checkboxes), id: \.self) { _ in Color.clear.frame(height: 20) }
                    }
                }
                Spacer(minLength: 8)
                if past, open > 0 {
                    HStack(spacing: 4) {
                        Circle().fill(theme.color(\.due)).frame(width: 5, height: 5)
                        Text("\(open) open")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(theme.color(\.strong))
                    .padding(.horizontal, 7)
                    .frame(height: 18)
                    .background(theme.dueFill, in: .capsule)
                } else if boxes.total > 0 {
                    Text("\(boxes.done)/\(boxes.total)").font(.system(size: 11.5)).foregroundStyle(theme.color(\.muted))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 7))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(isDay ? "Daily note" : "Week note"), \(file)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .task(id: note) { loaded = await model.boxLines(of: note) }
    }

    private func boxLine(_ line: NoteBoxLine) -> some View {
        let tint: KeyPath<Theme, PlatformColor> = switch line.state {
        case .done: \.done
        case .doing: \.doing
        case .open: \.muted
        }
        return HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3.5)
                .strokeBorder(theme.color(tint), lineWidth: 1.5)
                .background(line.state == .done ? theme.color(tint) : .clear, in: .rect(cornerRadius: 3.5))
                .frame(width: 13, height: 13)
                .overlay {
                    switch line.state {
                    case .done: Image(systemName: "checkmark").font(.system(size: 7.5, weight: .heavy)).foregroundStyle(theme.color(\.bg))
                    case .doing: RoundedRectangle(cornerRadius: 1.5).fill(theme.color(tint)).frame(width: 5, height: 5)
                    case .open: EmptyView()
                    }
                }
                .accessibilityHidden(true)
            Text(line.text)
                .font(.system(size: 13))
                .strikethrough(line.state == .done)
                .foregroundStyle(theme.color(line.state == .done ? \.muted : \.fg))
                .lineLimit(1)
        }
        .frame(minHeight: 20)
    }
}

extension View {
    /// Shows the period's note in the document pane while nothing else is picked, and drops a pick when the period changes.
    func showsAgendaNote(_ model: AppModel) -> some View {
        modifier(AgendaNoteShown(model: model))
    }
}

private struct AgendaNoteShown: ViewModifier {
    let model: AppModel

    private struct Shown: Equatable {
        var period: AppModel.AgendaSelection
        var note: String?
        var selection: String?
        var picked: Bool
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: model.agendaSelection) {
                model.selection = nil
                model.clearMultiSelection()
            }
            .onChange(of: Shown(period: model.agendaSelection, note: model.note(for: model.agendaSelection)?.path,
                                selection: model.selection, picked: !model.multiSelection.isEmpty), initial: true) {
                guard model.selection == nil, model.multiSelection.isEmpty, let note = model.note(for: model.agendaSelection) else { return }
                model.selection = note.path
            }
    }
}
#endif
