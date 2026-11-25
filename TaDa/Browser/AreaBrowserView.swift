// An area beside the document pane: its header with the Group button and the tag filter, its projects one line each, then
// the tasks filed straight to it by the project grouping, each group foldable.
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
        let grouping = model.grouping(of: .project)
        let sections = ListSection.sections(tasks, by: grouping, today: model.today)

        BrowserColumn(model: model, paths: ListSection.shownPaths(sections, by: grouping, in: area.path, model: model), spacing: 22,
                      empty: filter.isActive && projects.isEmpty && tasks.isEmpty ? .noTagMatch : nil) {
            header(projects: allProjects.count, tasks: allTasks.count { !$0.properties.status.isClosed },
                   files: allProjects + allTasks, shown: projects.count + tasks.count)
        } content: {
            if !projects.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(projects) { projectRow($0) }
                }
            }
            TaskSections(model: model, sections: sections, grouping: grouping, foldKey: area.path, dates: .elsewhere)
            if projects.isEmpty, tasks.isEmpty, !filter.isActive {
                Text("No tasks")
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.color(\.muted))
                    .padding(.horizontal, 10)
            }
            SubtaskCards(model: model, cards: filter.isActive ? [] : model.subtaskCards(of: area), parent: area)
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
                GroupFilterButton(model: model, list: .project, domain: .area(area.path), items: files)
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

    /// A project on one line: ring, name, deadline and open-task count; clicking opens its page.
    private func projectRow(_ progress: ProjectProgress) -> some View {
        let project = progress.project
        let p = project.properties
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
                Text(progress.open > 0 ? "\(progress.open)" : "")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(theme.color(\.muted))
                    .frame(minWidth: 18, alignment: .trailing)
                    .accessibilityLabel("^[\(progress.open) open task](inflect: true)")
                    .accessibilityHidden(progress.open == 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(progress.isOngoing ? "Ongoing" : "\(progress.done) of \(progress.total) tasks done")
        .fileMenu(model, path: project.path)
    }
}
#endif
