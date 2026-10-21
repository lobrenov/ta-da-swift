// A project's tasks beside the document pane: the project's header with the Group button and the tag filter, then its
// tasks by Status, Date or Open, each group foldable.
#if os(macOS)
import SwiftUI
import TaDaCore

struct ProjectBrowserView: View {
    let model: AppModel
    let project: Item
    @Environment(\.theme) private var theme

    var body: some View {
        let all = model.index.tasks(in: project)
        let filter = model.tagFilter(on: domain)
        let tasks = filter.apply(all)
        let grouping = model.grouping(of: .project)
        let sections = ListSection.sections(tasks, by: grouping, today: model.today)

        BrowserColumn(model: model, paths: TaskSections.shown(sections, by: grouping, in: project.path, model: model),
                      spacing: 22) {
            header(model.index.progress(of: project), tasks: all, shown: tasks.count)
        } content: {
            TaskSections(model: model, sections: sections, grouping: grouping, foldKey: project.path, dates: .iconsOnly)
            if all.isEmpty {
                Text("No tasks")
                    .foregroundStyle(theme.color(\.muted))
                    .padding(.horizontal, 10)
            } else if tasks.isEmpty {
                Text("No task here carries the picked tags.")
                    .foregroundStyle(theme.color(\.muted))
                    .padding(.horizontal, 10)
            }
            NewLinkedTaskButton(model: model).padding(.leading, 6)
        }
    }

    private var domain: AppModel.Domain { .project(project.path) }

    private func header(_ progress: ProjectProgress, tasks: [Item], shown: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
                GroupButton(model: model, list: .project)
                OpenFileButton(label: "Open project file") { model.selection = project.path }
            }
            ProjectPropertyLine(model: model, project: project, progress: progress)
            TagChipRow(model: model, item: project)
            TagFilterRow(model: model, domain: domain, items: tasks, shown: (shown, tasks.count))
        }
    }
}
#endif
