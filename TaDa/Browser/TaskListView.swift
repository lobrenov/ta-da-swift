// Loose tasks: a header with the Group button and the tag filter, then the tasks by the list's grouping.
// Project grouping puts tasks without a parent first, then loose projects' groups, then each area's own tasks under
// its heading followed by its projects' groups; a heading opens its page. Status, Date and Open give foldable groups.
#if os(macOS)
import SwiftUI
import TaDaCore

struct TaskListView: View {
    let model: AppModel

    private let list = GroupedList.loose

    var body: some View {
        let all = model.looseTasks
        let filter = model.tagFilter(on: .loose)
        let tasks = filter.apply(all)
        let grouping = model.grouping(of: list)
        let groups = grouping == .project ? model.index.grouped(tasks) : []
        let sections = grouping == .project ? [] : ListSection.sections(tasks, by: grouping, today: model.today)
        let paths = grouping == .project ? groups.flatMap(\.tasks).map(\.path)
            : TaskSections.shown(sections, by: grouping, in: list.foldKey, model: model)

        BrowserColumn(model: model, paths: paths, spacing: 22,
                      empty: all.isEmpty && !filter.isActive ? empty : tasks.isEmpty && filter.isActive ? .noTagMatch : nil) {
            VStack(alignment: .leading, spacing: 10) {
                DomainHeader(.loose) { GroupFilterButton(model: model, list: list, domain: .loose, items: all) }
                TagFilterRow(model: model, domain: .loose, items: all, shown: (tasks.count, all.count))
            }
        } content: {
            if grouping == .project {
                ProjectGroups(model: model, groups: groups, dates: .elsewhere)
            } else {
                TaskSections(model: model, sections: sections, grouping: grouping, foldKey: list.foldKey, dates: .elsewhere)
            }
        }
    }

    private var empty: EmptyState {
        EmptyState(systemImage: AppModel.Domain.loose.systemImage, title: "No loose tasks")
    }
}

/// Task groups under their project's or area's heading, which opens its page.
struct ProjectGroups: View {
    let model: AppModel
    let groups: [TaskGroup]
    let dates: TaskRow.Dates

    var body: some View {
        ForEach(sections(groups), id: \.first?.id) { section in
            VStack(alignment: .leading, spacing: 1) {
                ForEach(section) { group in
                    header(group)
                    ForEach(group.tasks) { task in
                        TaskRow(item: task, selected: model.isSelected(task.path), today: model.today, dates: dates,
                                move: model.index.repeatMove(of: task, today: model.today),
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
                ProjectGroupHeader(project: parent, progress: model.index.progress(of: parent), area: parent.properties.area?.title)
                    .opensPage(of: parent, model)
            case .task, .note:
                EmptyView()
            }
        }
    }
}
#endif
