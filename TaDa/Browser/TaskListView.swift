// Today and Loose tasks: a header, tasks without a parent first, then loose projects' groups, then each area's own
// tasks under its heading followed by its projects' groups.
#if os(macOS)
import SwiftUI
import TaDaCore

struct TaskListView: View {
    enum Kind { case today, loose }

    let model: AppModel
    let kind: Kind

    var body: some View {
        let all = kind == .today ? model.todayTasks : model.looseTasks
        let groups = model.index.grouped(all)

        BrowserColumn(model: model, paths: groups.flatMap(\.tasks).map(\.path), spacing: 22, empty: all.isEmpty ? empty : nil) {
            header
        } content: {
            list(groups)
        }
    }

    @ViewBuilder private var header: some View {
        switch kind {
        case .today:
            DomainHeader(.today) {
                Text(model.today.formatted(.weekdayDayMonth)).font(.system(size: 13))
            }
        case .loose:
            DomainHeader(.loose)
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
                        TaskRow(item: task, selected: model.isSelected(task.path), today: model.today,
                                dates: kind == .today ? .overdueDueAndDeadline : .labelled,
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

    @ViewBuilder private func header(_ group: TaskGroup) -> some View {
        if let parent = group.parent {
            switch parent.properties.kind {
            case .area:
                AreaGroupHeader(area: parent)
            case .project where model.index.area(of: parent) != nil:
                ProjectSubheader(project: parent, fraction: model.index.progress(of: parent).fraction)
            case .project:
                ProjectGroupHeader(project: parent, fraction: model.index.progress(of: parent).fraction)
            case .task, .note:
                EmptyView()
            }
        }
    }
}
#endif
