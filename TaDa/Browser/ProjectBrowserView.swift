// A project's tasks beside the document pane: the project's header, then Open and Completed groups, each foldable.
#if os(macOS)
import SwiftUI
import TaDaCore

struct ProjectBrowserView: View {
    let model: AppModel
    let project: Item
    @Environment(\.theme) private var theme

    var body: some View {
        let tasks = model.index.tasks(in: project)
        let open = tasks.filter { !$0.properties.status.isClosed }
        let done = tasks.filter { $0.properties.status.isClosed }
        let shown = (isFolded("Open") ? [] : open) + (isFolded("Completed") ? [] : done)

        BrowserColumn(model: model, paths: shown.map(\.path), spacing: 18) {
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
        let subtasks = project.subtasks
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressRing(progress).scaleEffect(24 / 16).frame(width: 21, height: 21)
                    .foregroundStyle(theme.color(\.accent))
                InlineTitleField(model: model, path: project.path, height: 34, font: .system(size: 24, weight: .bold)) {
                    Text(project.title)
                        .tracking(-0.24)
                        .foregroundStyle(theme.color(\.strong))
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 12)
                Button { model.selection = project.path } label: {
                    Label("Open project file", systemImage: "doc")
                }
                .buttonStyle(ActionButtonStyle(height: 28))
                .fixedSize()
            }
            PropertyChipRow(model: model, item: project) {
                if subtasks.total > 0 {
                    Chip(systemImage: "checklist", text: "\(subtasks.done)/\(subtasks.total)",
                         spoken: "\(subtasks.done) of \(subtasks.total) subtasks done")
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.color(\.muted))
                        .padding(.leading, 6)
                }
            }
            TagChipRow(model: model, item: project)
            if !progress.isOngoing {
                Text("\(progress.done) of \(progress.total) tasks done")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.color(\.muted))
            }
        }
    }

    private func isFolded(_ group: String) -> Bool { model.isFolded(group, in: project.path) }

    @ViewBuilder private func group(_ title: String, _ tasks: [Item]) -> some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                CountGroupHeader(title: title, count: tasks.count, isExpanded: Binding(
                    get: { !isFolded(title) },
                    set: { _ in model.toggleFolded(title, in: project.path) }))
                ForEach(isFolded(title) ? [] : tasks) { task in
                    TaskRow(item: task, selected: model.isSelected(task.path), today: model.today,
                            dates: .iconsOnly,
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
