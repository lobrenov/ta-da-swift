// Today and Loose tasks: a header with context filters, loose tasks first, then one group per project.
#if os(macOS)
import SwiftUI
import TaDaCore

struct TaskListView: View {
    enum Kind { case today, loose }

    let model: AppModel
    let kind: Kind
    /// nil shows every context.
    @State private var context: String?

    var body: some View {
        let all = kind == .today ? model.todayTasks : model.looseTasks
        let contexts = Set(all.flatMap(\.properties.contexts)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let shown = all.filter { task in context.map { task.properties.contexts.contains($0) } ?? true }
        let groups = model.index.grouped(shown)

        BrowserColumn(model: model, paths: groups.flatMap(\.tasks).map(\.path), spacing: 22, empty: shown.isEmpty ? empty : nil) {
            header(contexts: contexts)
        } content: {
            list(groups)
        }
        .onChange(of: contexts) { if let context, !contexts.contains(context) { self.context = nil } }
    }

    private func header(contexts: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            switch kind {
            case .today:
                DomainHeader(.today) {
                    Text(model.today.formatted(.weekdayDayMonth)).font(.system(size: 13))
                }
            case .loose:
                DomainHeader(.loose)
            }
            if !contexts.isEmpty {
                ContextFilter(contexts: contexts, selection: $context)
            }
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
