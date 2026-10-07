// A project's tasks beside the document pane: the project's header, then Open and Completed groups.
import SwiftUI
import TaDaCore

struct ProjectBrowserView: View {
    let model: AppModel
    let project: Item
    @Environment(\.theme) private var theme

    var body: some View {
        let tasks = model.index.tasks(in: project)
        let open = tasks.filter { $0.properties.status != .done }
        let done = tasks.filter { $0.properties.status == .done }

        BrowserColumn(model: model, paths: (open + done).map(\.path), spacing: 18) {
            header(model.index.progress(of: project))
        } content: {
            group("Open", open)
            if !done.isEmpty { group("Completed", done) }
            if tasks.isEmpty {
                Text("No tasks link to this project yet.")
                    .foregroundStyle(theme.color(\.muted))
                    .padding(.horizontal, 10)
            }
            NewLinkedTaskButton(model: model).padding(.leading, 6)
        }
    }

    private func header(_ progress: ProjectProgress) -> some View {
        let p = project.properties
        return VStack(alignment: .leading, spacing: 12) {
            DomainHeader(title: project.title, ring: progress.fraction, size: 24) {
                Button("Open project file") { model.selection = project.path }
                    .buttonStyle(.plain)
            }
            HStack(spacing: 14) {
                StatusLabel(status: p.status, dotSize: 7)
                if let due = p.dueDate { DateChip(kind: .due, date: due, today: model.today) }
                if let deadline = p.deadline { DateChip(kind: .deadline, date: deadline, today: model.today) }
                Text("\(progress.done) of \(progress.total) done")
            }
            .font(.system(size: 12))
            .foregroundStyle(theme.color(\.muted))
            if let summary = project.summary {
                Text(summary).font(.system(size: 13)).foregroundStyle(theme.color(\.fg)).lineLimit(4)
            }
        }
    }

    @ViewBuilder private func group(_ title: String, _ tasks: [Item]) -> some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                CountGroupHeader(title: title, count: tasks.count)
                ForEach(tasks) { task in
                    TaskRow(item: task, selected: model.isSelected(task.path), today: model.today,
                            dates: .iconsOnly, showsContexts: false,
                            onToggle: { Task { await model.toggleCompletion(task) } },
                            onSelect: { model.click(task.path) })
                    .fileMenu(model, path: task.path)
                    .taskDrag(model, path: task.path)
                }
            }
        }
    }
}
