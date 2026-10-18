// The Agenda's day: its heading, the daily note's row, the day's events then reminders, then its tasks as Today's list
// groups them, under Scheduled. A day's tasks keep Today's Group menu and tag filter; while tags are picked the
// events and reminders hide.
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
        let paths = grouping == .project ? groups.flatMap(\.tasks).map(\.path)
            : TaskSections.shown(sections, by: grouping, in: list.foldKey, model: model)

        BrowserColumn(model: model, paths: paths, spacing: 22) {
            AgendaStrip(model: model)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(day.formatted(.fullDate)).font(.system(size: 18, weight: .bold)).foregroundStyle(theme.color(\.strong))
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    if let relative = model.relativeDayName(day) { Text(relative).fontWeight(.semibold).foregroundStyle(theme.color(\.accent)) }
                }
                .padding(.horizontal, 10)
                AgendaNoteRow(model: model, period: .day(day))
                if !events.isEmpty || !reminders.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(events) { EventRow(event: $0, day: day, context: .today) }
                        ForEach(reminders) { ReminderRow(reminder: $0, context: .today, today: day == model.today ? model.today : nil) }
                    }
                    .padding(.top, 4)
                }
            }
            if !all.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(spacing: 7) {
                            HStack(spacing: 8) {
                                Image(systemName: "calendar").font(.system(size: 12)).foregroundStyle(theme.color(\.due))
                                    .accessibilityHidden(true)
                                Text("Scheduled").fontWeight(.semibold).foregroundStyle(theme.color(\.strong))
                                Spacer(minLength: 8)
                                GroupButton(model: model, list: list)
                            }
                            .padding(.horizontal, 10)
                            Hairline()
                        }
                        .accessibilityElement(children: .contain)
                        TagFilterRow(model: model, domain: .agenda, items: all, shown: (tasks.count, all.count))
                    }
                    VStack(alignment: .leading, spacing: 22) {
                        if tasks.isEmpty {
                            Text("Nothing here carries the picked tags.").foregroundStyle(theme.color(\.muted)).padding(.horizontal, 10)
                        } else if grouping == .project {
                            ProjectGroups(model: model, groups: groups, dates: .overdueDueAndDeadline)
                        } else {
                            TaskSections(model: model, sections: sections, grouping: grouping, foldKey: list.foldKey,
                                         dates: .overdueDueAndDeadline, place: { model.index.parent(of: $0)?.title })
                        }
                    }
                }
            } else if events.isEmpty && reminders.isEmpty {
                Text("Nothing scheduled").foregroundStyle(theme.color(\.muted)).padding(.horizontal, 10)
            }
        }
        .showsAgendaNote(model)
    }
}

/// A day's or week's note as one row: its name, file and first paragraph, and its checkboxes; or, with no note, the
/// row that starts it.
struct AgendaNoteRow: View {
    let model: AppModel
    let period: AppModel.AgendaSelection
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
