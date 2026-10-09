// Today and Loose tasks: a header, loose tasks first, then one group per project.
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
        ForEach(groups) { group in
            VStack(alignment: .leading, spacing: 1) {
                if let project = group.project {
                    ProjectGroupHeader(project: project, fraction: model.index.progress(of: project).fraction)
                }
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
#endif
