// Today and Loose tasks: a header with the Group button and the tag filter, then the tasks by the list's grouping.
// Project grouping puts tasks without a parent first, then loose projects' groups, then each area's own tasks under
// its heading followed by its projects' groups; a heading opens its page. Status, Date and Open give foldable groups.
// Today starts with the day's events, then its reminders, unless tags are picked.
#if os(macOS)
import SwiftUI
import TaDaCore

struct TaskListView: View {
    enum Kind { case today, loose }

    let model: AppModel
    let kind: Kind

    private var list: GroupedList { kind == .today ? .today : .loose }
    private var domain: AppModel.Domain { kind == .today ? .agenda : .loose }

    var body: some View {
        let all = kind == .today ? model.agendaTasks : model.looseTasks
        let filter = model.tagFilter(on: domain)
        let tasks = filter.apply(all)
        let grouping = model.grouping(of: list)
        let groups = grouping == .project ? model.index.grouped(tasks) : []
        let sections = grouping == .project ? [] : ListSection.sections(tasks, by: grouping, today: model.today)
        let showsCalendar = kind == .today && !filter.isActive
        let events = showsCalendar ? model.todayEvents : [], reminders = showsCalendar ? model.todayReminders : []
        let paths = grouping == .project ? groups.flatMap(\.tasks).map(\.path)
            : TaskSections.shown(sections, by: grouping, in: list.foldKey, model: model)

        BrowserColumn(model: model, paths: paths, spacing: 22,
                      empty: all.isEmpty && events.isEmpty && reminders.isEmpty && !filter.isActive ? empty
                          : tasks.isEmpty && filter.isActive ? .noTagMatch : nil) {
            VStack(alignment: .leading, spacing: 10) {
                header
                TagFilterRow(model: model, domain: domain, items: all, shown: (tasks.count, all.count))
            }
        } content: {
            if !events.isEmpty || !reminders.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if !events.isEmpty {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(events) { EventRow(event: $0, day: model.today, context: .today) }
                        }
                    }
                    if !reminders.isEmpty {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(reminders) { ReminderRow(reminder: $0, context: .today, today: model.today) }
                        }
                    }
                }
            }
            if grouping == .project {
                list(groups)
            } else {
                TaskSections(model: model, sections: sections, grouping: grouping, foldKey: list.foldKey, dates: dates,
                             place: kind == .today ? { model.index.parent(of: $0)?.title } : nil)
            }
        }
    }

    private var dates: TaskRow.Dates { kind == .today ? .overdueDueAndDeadline : .labelled }

    @ViewBuilder private var header: some View {
        switch kind {
        case .today:
            DomainHeader(.agenda) {
                HStack(spacing: 10) {
                    Text(model.today.formatted(.weekdayDayMonth)).font(.system(size: 13)).fixedSize()
                    GroupButton(model: model, list: list)
                }
            }
        case .loose:
            DomainHeader(.loose) { GroupButton(model: model, list: list) }
        }
    }

    private var empty: EmptyState {
        switch kind {
        case .today:
            EmptyState(systemImage: "star", title: "Nothing due today",
                       message: "Tasks due or at their deadline today, or overdue, show here.")
        case .loose:
            EmptyState(systemImage: AppModel.Domain.loose.systemImage, title: "No loose tasks",
                       message: "Open tasks that don’t belong to a project show here.")
        }
    }

    private func list(_ groups: [TaskGroup]) -> some View {
        ForEach(sections(groups), id: \.first?.id) { section in
            VStack(alignment: .leading, spacing: 1) {
                ForEach(section) { group in
                    header(group)
                    ForEach(group.tasks) { task in
                        TaskRow(item: task, selected: model.isSelected(task.path), today: model.today, dates: dates,
                                onToggle: { Task { await model.toggleCompletion(task) } },
                                onSelect: { model.click(task.path) })
                        .fileMenu(model, path: task.path)
                        .taskDrag(model, path: task.path)
                    }
                }
            }
        }
    }

    /// The groups split where the list leaves space: an area's projects stay in its section.
    private func sections(_ groups: [TaskGroup]) -> [[TaskGroup]] {
        var sections: [[TaskGroup]] = []
        for group in groups {
            if let parent = group.parent, parent.properties.kind == .project, model.index.area(of: parent) != nil, !sections.isEmpty {
                sections[sections.count - 1].append(group)
            } else {
                sections.append([group])
            }
        }
        return sections
    }

    /// A project's or area's heading, which opens its page.
    @ViewBuilder private func header(_ group: TaskGroup) -> some View {
        if let parent = group.parent {
            switch parent.properties.kind {
            case .area:
                AreaGroupHeader(area: parent).opensPage(of: parent, model)
            case .project where model.index.area(of: parent) != nil:
                ProjectSubheader(project: parent, progress: model.index.progress(of: parent)).opensPage(of: parent, model)
            case .project:
                ProjectGroupHeader(project: parent, progress: model.index.progress(of: parent)).opensPage(of: parent, model)
            case .task, .note:
                EmptyView()
            }
        }
    }
}
#endif
