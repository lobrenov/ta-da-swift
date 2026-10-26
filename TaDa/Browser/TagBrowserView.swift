// A tag's page beside the document pane, or Untagged's: its header with a count line and child tags, then its tagged
// areas and projects, its open tasks in Today's groups (a project's or area's heading opens its page) with Loose
// last, their Completed group, then its notes, each foldable.
// Completed starts folded. A tag includes its children's files.
#if os(macOS)
import SwiftUI
import TaDaCore

struct TagBrowserView: View {
    let model: AppModel
    /// The tag's path; nil for Untagged.
    let path: String?
    @Environment(\.theme) private var theme

    var body: some View {
        // Set while a tag page shows, which is when the workspace shows this view.
        if let page = model.tagPage { column(page) }
    }

    private func column(_ page: TagBrowser) -> some View {
        let tag = model.shownTag
        let open = page.groups.flatMap(\.tasks)
        let rows = rows(page, open: open, untagged: tag == nil)

        return BrowserColumn(model: model, paths: rows.compactMap(\.filePath), spacing: 1) {
            header(tag, page: page, open: open.count)
        } content: {
            ForEach(rows) { row in
                switch row {
                case let .fold(title, count, first): foldHeader(title, count: count).padding(.top, first ? 0 : 17)
                case let .parent(item): parentRow(item)
                case let .group(group): groupHeader(group)
                case let .task(task): taskRow(task)
                case let .noteFile(note):
                    NoteRow(item: note, selected: model.isSelected(note.path), showsFolder: true) { model.click(note.path) }
                    .fileMenu(model, path: note.path)
                case let .note(text):
                    Text(text)
                        .font(.system(size: 12.5))
                        .foregroundStyle(theme.color(\.muted))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                }
            }
        }
    }

    /// One row of the page, straight in the column's lazy stack.
    private enum Row: Identifiable {
        case fold(String, count: Int, first: Bool)
        case parent(Item)
        case group(TaskGroup)
        case task(Item)
        case noteFile(Item)
        case note(String)

        var id: String {
            switch self {
            case .fold(let title, _, _): "fold:" + title
            case .parent(let item): "parent:" + item.path
            case .group(let group): "group:" + group.id
            case .task(let task): task.path
            case .noteFile(let note): note.path
            case .note: "note"
            }
        }

        /// The task's or note's path, for the arrow keys.
        var filePath: String? {
            switch self {
            case .task(let item), .noteFile(let item): item.path
            default: nil
            }
        }
    }

    /// Tagged areas and projects, Tasks in Today's groups (Loose last), Completed and Notes, each under its fold header.
    private func rows(_ page: TagBrowser, open: [Item], untagged: Bool) -> [Row] {
        let parentsTitle = untagged ? "Areas and projects" : "Tagged areas and projects"
        var rows: [Row] = []
        if !page.areasAndProjects.isEmpty {
            rows.append(.fold(parentsTitle, count: page.areasAndProjects.count, first: true))
            if !isFolded(parentsTitle) { rows += page.areasAndProjects.map(Row.parent) }
        }
        rows.append(.fold("Tasks", count: open.count, first: rows.isEmpty))
        if !isFolded("Tasks") {
            if open.isEmpty { rows.append(.note(untagged ? "Every open task has a tag." : "No open tasks carry this tag.")) }
            for group in page.groups { rows += [.group(group)] + group.tasks.map(Row.task) }
        }
        if !page.completed.isEmpty {
            rows.append(.fold("Completed", count: page.completed.count, first: false))
            if !isFolded("Completed") { rows += page.completed.map(Row.task) }
        }
        if !page.notes.isEmpty {
            rows.append(.fold("Notes", count: page.notes.count, first: false))
            if !isFolded("Notes") { rows += page.notes.map(Row.noteFile) }
        }
        return rows
    }

    private func header(_ tag: Tag?, page: TagBrowser, open: Int) -> some View {
        let areas = page.areasAndProjects.count { $0.properties.kind == .area }
        let projects = page.areasAndProjects.count - areas
        var counts: [String] = []
        if areas > 0 { counts.append(areas == 1 ? "1 area" : "\(areas) areas") }
        if projects > 0 { counts.append(projects == 1 ? "1 project" : "\(projects) projects") }
        counts.append(open == 1 ? "1 open task" : "\(open) open tasks")
        if !page.notes.isEmpty { counts.append(page.notes.count == 1 ? "1 note" : "\(page.notes.count) notes") }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: tag == nil ? "tag.slash" : "tag")
                    .font(.system(size: 20))
                    .foregroundStyle(theme.color(tag == nil ? \.muted : \.accent))
                    .accessibilityHidden(true)
                Group {
                    if let tag {
                        TagName(tag: tag)
                    } else {
                        Text("Untagged")
                    }
                }
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.24)
                .foregroundStyle(theme.color(\.strong))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(tag.map { "Tag \($0.name)" } ?? "Untagged")
            }
            .frame(height: 34)
            Text(counts.joined(separator: " · "))
                .font(.system(size: 11.5))
                .foregroundStyle(theme.color(\.muted))
            if !page.children.isEmpty {
                WrappingHStack(spacing: 6) {
                    ForEach(page.children) { child in
                        Button { model.show(.tag(child.tag.path)) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "tag")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(theme.color(\.accent))
                                Text(child.tag.leaf).foregroundStyle(theme.color(\.strong))
                                Text("\(child.count)").monospacedDigit().foregroundStyle(theme.color(\.muted))
                            }
                            .font(.system(size: 12.5))
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(theme.tagFill(), in: .capsule)
                            .overlay(Capsule().strokeBorder(theme.tagRing))
                            .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Tag \(child.tag.name), \(child.count) files")
                    }
                }
            }
        }
    }

    /// The fold state's key: the page's own, beside the projects' and areas' paths.
    private var foldKey: String { "tag:" + (path ?? "") }

    /// Completed starts folded: a stored entry for it means it was opened.
    private func isFolded(_ group: String) -> Bool {
        model.isFolded(group, in: foldKey) != (group == "Completed")
    }

    private func foldHeader(_ title: String, count: Int) -> some View {
        CountGroupHeader(title: title, count: count, isExpanded: Binding(
            get: { !isFolded(title) },
            set: { _ in model.toggleFolded(title, in: foldKey) }), quiet: title == "Completed")
    }

    @ViewBuilder private func groupHeader(_ group: TaskGroup) -> some View {
        switch group.parent {
        case let parent? where parent.properties.kind == .area:
            AreaGroupHeader(area: parent).opensPage(of: parent, model).padding(.top, 8)
        case let parent? where model.index.area(of: parent) != nil:
            ProjectSubheader(project: parent, progress: model.index.progress(of: parent)).opensPage(of: parent, model)
        case let parent?:
            ProjectGroupHeader(project: parent, progress: model.index.progress(of: parent), area: parent.properties.area?.title)
                .opensPage(of: parent, model)
                .padding(.top, 8)
        case nil:
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Image(systemName: AppModel.Domain.loose.systemImage)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.color(\.accent))
                    Text("Loose").fontWeight(.semibold).foregroundStyle(theme.color(\.strong))
                }
                .padding(.horizontal, 10)
                Hairline()
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }

    /// An area's cube, title and project count, or a project's ring, title, progress and area; clicking opens its page.
    private func parentRow(_ item: Item) -> some View {
        let isArea = item.properties.kind == .area
        let progress = isArea ? nil : model.index.progress(of: item)
        let meta = if let progress {
            "\(progress.isOngoing ? "Ongoing" : "\(progress.done) of \(progress.total) done") · \(model.index.area(of: item)?.title ?? "No area")"
        } else {
            model.index.projects(in: item).count == 1 ? "1 project" : "\(model.index.projects(in: item).count) projects"
        }
        return Button { model.show(isArea ? .area(item.path) : .project(item.path)) } label: {
            HStack(spacing: 10) {
                Group {
                    if let progress {
                        ProgressRing(progress).foregroundStyle(theme.color(\.accent))
                    } else {
                        AreaIcon()
                    }
                }
                .frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 13.5, weight: isArea ? .semibold : .regular))
                        .foregroundStyle(theme.color(isArea ? \.strong : \.fg))
                    HStack(spacing: 12) {
                        Text(meta)
                        TagCountChip(tags: item.tags)
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
        .fileMenu(model, path: item.path)
    }

    private func taskRow(_ task: Item) -> some View {
        TaskRow(item: task, selected: model.isSelected(task.path), today: model.today,
                move: model.index.repeatMove(of: task, today: model.today),
                onToggle: { Task { await model.toggleCompletion(task) } },
                onSelect: { model.click(task.path) })
        .fileMenu(model, path: task.path)
        .taskDrag(model, path: task.path)
    }
}
#endif
