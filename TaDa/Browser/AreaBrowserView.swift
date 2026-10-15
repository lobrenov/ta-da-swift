// An area beside the document pane: its header with the tag filter, its projects, the tasks filed straight to it and their completed
// group, each foldable. Completed starts folded.
#if os(macOS)
import SwiftUI
import TaDaCore

struct AreaBrowserView: View {
    let model: AppModel
    let area: Item
    @Environment(\.theme) private var theme

    var body: some View {
        let allProjects = model.index.projects(in: area), allTasks = model.index.tasks(in: area)
        let filter = model.tagFilter(on: .area(area.path))
        let projects = filter.apply(allProjects).map { model.index.progress(of: $0) }
        let tasks = filter.apply(allTasks)
        let open = tasks.filter { !$0.properties.status.isClosed }
        let done = tasks.filter { $0.properties.status.isClosed }
        let shown = (isFolded("Tasks") ? [] : open) + (isFolded("Completed") ? [] : done)

        BrowserColumn(model: model, paths: shown.map(\.path), spacing: 18,
                      empty: filter.isActive && projects.isEmpty && tasks.isEmpty ? .noTagMatch : nil) {
            header(projects: allProjects.count, tasks: allTasks.count { !$0.properties.status.isClosed },
                   files: allProjects + allTasks, shown: projects.count + tasks.count)
        } content: {
            if !projects.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    foldHeader("Projects", count: projects.count)
                    ForEach(isFolded("Projects") ? [] : projects) { projectRow($0) }
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                foldHeader("Tasks", count: open.count)
                if !isFolded("Tasks") {
                    if open.isEmpty, !filter.isActive {
                        Text("No tasks filed straight to \(area.title). Tasks in its projects stay on their project.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.color(\.muted))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                    }
                    ForEach(open) { taskRow($0) }
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                foldHeader("Completed", count: done.count)
                ForEach(isFolded("Completed") ? [] : done) { taskRow($0) }
            }
            NewLinkedTaskButton(model: model, title: "New task in \(area.title)").padding(.leading, 6)
        }
    }

    private func header(projects: Int, tasks: Int, files: [Item], shown: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AreaIcon(size: 24)
                InlineTitleField(model: model, path: area.path, height: 34, font: .system(size: 24, weight: .bold)) {
                    Text(area.title)
                        .tracking(-0.24)
                        .foregroundStyle(theme.color(\.strong))
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 12)
                Button { model.selection = area.path } label: {
                    Label("Open area file", systemImage: "doc")
                }
                .buttonStyle(ActionButtonStyle(height: 28))
                .fixedSize()
            }
            Text("^[\(projects) project](inflect: true) · ^[\(tasks) task](inflect: true)")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.color(\.muted))
            TagChipRow(model: model, item: area)
            TagFilterRow(model: model, domain: .area(area.path), items: files, shown: (shown, files.count))
        }
    }

    /// Completed starts folded: a stored entry for it means it was opened.
    private func isFolded(_ group: String) -> Bool {
        model.isFolded(group, in: area.path) != (group == "Completed")
    }

    private func foldHeader(_ title: String, count: Int) -> some View {
        CountGroupHeader(title: title, count: count, isExpanded: Binding(
            get: { !isFolded(title) },
            set: { _ in model.toggleFolded(title, in: area.path) }))
    }

    /// A project's ring, title and a line of its status and progress, then its subtasks, due date and deadline as a
    /// task row shows them; clicking opens its page.
    private func projectRow(_ progress: ProjectProgress) -> some View {
        let project = progress.project
        let p = project.properties
        let subtasks = project.subtasks
        return Button { model.show(.project(project.path)) } label: {
            HStack(spacing: 10) {
                ProgressRing(progress)
                    .foregroundStyle(theme.color(\.accent))
                    .scaleEffect(16 / 14)
                    .frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.title).font(.system(size: 13.5)).foregroundStyle(theme.color(\.fg))
                    HStack(spacing: 12) {
                        Text(progress.isOngoing ? p.status.rawValue : "\(p.status.rawValue) · \(progress.done) of \(progress.total) done")
                        if subtasks.total > 0 {
                            Chip(systemImage: "checklist", text: "\(subtasks.done)/\(subtasks.total)",
                                 spoken: "\(subtasks.done) of \(subtasks.total) subtasks done")
                        }
                        if !p.status.isClosed {
                            if let due = p.dueDate {
                                DateChip(kind: .due, date: due, today: model.today, labelled: false)
                            }
                            if let deadline = p.deadline {
                                DateChip(kind: .deadline, date: deadline, today: model.today, labelled: false)
                            }
                        }
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.color(\.muted))
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.color(\.muted))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(progress.isOngoing ? "Ongoing" : "\(progress.done) of \(progress.total) tasks done")
        .fileMenu(model, path: project.path)
    }

    private func taskRow(_ task: Item) -> some View {
        TaskRow(item: task, selected: model.isSelected(task.path), today: model.today, dates: .iconsOnly,
                onToggle: { Task { await model.toggleCompletion(task) } },
                onSelect: { model.click(task.path) })
        .fileMenu(model, path: task.path)
        .taskDrag(model, path: task.path)
    }
}
#endif
