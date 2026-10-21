// An area beside the document pane: its header with the tag filter, its projects one line each, the tasks filed straight
// to it, then their Completed group, which starts folded.
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
        let shown = open + (isFolded ? [] : done)

        BrowserColumn(model: model, paths: shown.map(\.path), spacing: 22,
                      empty: filter.isActive && projects.isEmpty && tasks.isEmpty ? .noTagMatch : nil) {
            header(projects: allProjects.count, tasks: allTasks.count { !$0.properties.status.isClosed },
                   files: allProjects + allTasks, shown: projects.count + tasks.count)
        } content: {
            if !projects.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(projects) { projectRow($0) }
                }
            }
            if !open.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(open) { taskRow($0) }
                }
            }
            if !done.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    CountGroupHeader(title: "Completed", count: done.count, isExpanded: Binding(
                        get: { !isFolded },
                        set: { _ in model.toggleFolded("Completed", in: area.path) }), quiet: true)
                    ForEach(isFolded ? [] : done) { taskRow($0) }
                }
            }
            if projects.isEmpty, tasks.isEmpty, !filter.isActive {
                Text("No tasks")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.color(\.muted))
                    .padding(.horizontal, 10)
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
    private var isFolded: Bool { !model.isFolded("Completed", in: area.path) }

    /// A project on one line: ring, name, deadline and open-task count; clicking opens its page.
    private func projectRow(_ progress: ProjectProgress) -> some View {
        let project = progress.project
        let p = project.properties
        let open = model.index.tasks(in: project).count { !$0.properties.status.isClosed }
        return Button { model.show(.project(project.path)) } label: {
            HStack(spacing: 10) {
                ProgressRing(progress)
                    .foregroundStyle(theme.color(\.accent))
                    .scaleEffect(16 / 14)
                    .frame(width: 16, height: 16)
                Text(project.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.color(\.strong))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let deadline = p.deadline, !p.status.isClosed {
                    let overdue = deadline < model.today
                    HStack(spacing: 4) {
                        Image(systemName: AgendaEntry.Kind.deadline.systemImage)
                            .foregroundStyle(theme.color(\.deadline))
                        Text(deadline.relativeLabel(today: model.today).capitalizedFirst)
                            .foregroundStyle(theme.color(overdue ? \.deadline : \.muted))
                    }
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Deadline \(deadline.relativeLabel(today: model.today))\(overdue ? ", overdue" : "")")
                }
                Text("\(open)")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(theme.color(\.muted))
                    .frame(minWidth: 18, alignment: .trailing)
                    .accessibilityLabel("^[\(open) open task](inflect: true)")
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
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
