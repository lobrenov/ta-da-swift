// The lists the tabs open on: Loose (grouped by area and project), Tasks (the Loose row, then the projects with the
// areas), a project's tasks, and an area's projects and tasks.
#if os(iOS)
import SwiftUI
import TaDaCore

struct PhoneTaskListScreen: View {
    let model: AppModel
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let all = model.looseTasks
        let filter = model.tagFilter(on: .loose)
        let shownTasks = filter.apply(all)
        let grouping = model.grouping(of: .loose)
        let groups = grouping == .project ? model.index.grouped(shownTasks) : []
        let sections = grouping == .project ? [] : ListSection.sections(shownTasks, by: grouping, today: model.today)
        let open = all.count { !$0.properties.status.isClosed }
        let pickable = grouping == .project ? groups.flatMap(\.tasks).map(\.path)
            : sections.filter { !model.isFolded($0, by: grouping, in: GroupedList.loose.foldKey) }.flatMap(\.tasks).map(\.path)
        let dates = TaskRow.Dates.labelled

        PhoneList(model: model, title: "Loose tasks", subtitle: "No project or area · \(tasks(open))",
                  titleAccessory: AnyView(PhoneGroupMenu(model: model, list: .loose)),
                  pickable: pickable, add: newTask) {
            EmptyView()
        } content: {
            PhoneTagFilterBar(model: model, domain: .loose, items: all, shown: shownTasks.count)
            if all.isEmpty {
                ContentUnavailableView("No loose tasks", systemImage: "tray",
                                       description: Text("Open tasks that don’t belong to a project or an area show here."))
                    .padding(.top, 60)
            } else if shownTasks.isEmpty, filter.isActive {
                ContentUnavailableView("No matches", systemImage: "line.3.horizontal.decrease",
                                       description: Text("No task here carries the picked tags.")).padding(.top, 40)
            }
            if grouping == .project {
                ForEach(groups) { group in
                    if let parent = group.parent {
                        if parent.properties.kind == .area {
                            PhoneAreaHeader(area: parent, isFirst: group.id == groups.first?.id)
                        } else {
                            PhoneProjectHeader(project: parent, progress: model.index.progress(of: parent))
                        }
                    }
                    ForEach(group.tasks) { task in
                        PhoneTaskRow(model: model, item: task, meta: .chips(dates))
                    }
                }
            } else {
                PhoneTaskSections(model: model, sections: sections, grouping: grouping, foldKey: GroupedList.loose.foldKey, dates: dates)
            }
        }
    }

    /// A new loose task opens with its title ready to type.
    private func newTask() async {
        model.domain = .loose
        await model.newTask()
        if let path = model.selection { nav.push(.file(path)) }
    }
}

/// The Tasks tab: a Loose tasks row, then the loose projects and the areas with their projects.
struct PhoneTasksScreen: View {
    let model: AppModel
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let open = model.looseTasks.count { !$0.properties.status.isClosed }
        PhoneList(model: model, title: "Tasks",
                  subtitle: "\(tasks(open)) loose · \(model.projects.count == 1 ? "1 project" : "\(model.projects.count) projects") · \(model.areas.count == 1 ? "1 area" : "\(model.areas.count) areas")",
                  add: newTask) {
            Button("New Project", systemImage: "chart.pie") { Task { await newProject() } }
            Button("New Area", systemImage: "cube") { Task { await newArea() } }
        } content: {
            VStack(spacing: 0) {
                Button { nav.push(.loose) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "tray")
                            .scaledFont(size: 22)
                            .foregroundStyle(theme.color(\.accent))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Loose tasks")
                                .scaledFont(size: 17, weight: .semibold)
                                .foregroundStyle(theme.color(\.strong))
                            Text("\(tasks(open)) with no project or area")
                                .scaledFont(size: 13)
                                .foregroundStyle(theme.color(\.muted))
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .scaledFont(size: 14, weight: .semibold)
                            .foregroundStyle(theme.color(\.muted))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                PhoneRowSeparator(inset: 52)
            }
            PhoneProjectRows(model: model)
        }
    }

    /// A new loose task opens with its title ready to type.
    private func newTask() async {
        model.domain = .loose
        await model.newTask()
        if let path = model.selection { nav.push(.file(path)) }
    }

    private func newProject() async {
        await model.newProject()
        if let path = model.selection { nav.push(.file(path)) }
    }

    private func newArea() async {
        await model.newArea()
        if let path = model.selection { nav.push(.file(path)) }
    }
}

func tasks(_ count: Int) -> String {
    count == 1 ? "1 task" : "\(count) tasks"
}

// MARK: Projects

struct PhoneProjectRows: View {
    let model: AppModel

    var body: some View {
        let completed = model.index.projects.filter { $0.properties.status.isClosed }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .map { model.index.progress(of: $0) }

        ForEach(model.looseProjects) { PhoneProjectRow(model: model, progress: $0) }
        ForEach(model.areas) { entry in
            PhoneAreaRow(model: model, area: entry.area)
                .padding(.top, 14)
            ForEach(entry.projects) { PhoneProjectRow(model: model, progress: $0, isCompact: true) }
        }
        if !completed.isEmpty {
            PhoneFoldHeader(model: model, title: "Completed", count: completed.count, group: "Completed", in: "Projects")
            if !model.isFolded("Completed", in: "Projects") {
                ForEach(completed) { PhoneProjectRow(model: model, progress: $0) }
            }
        }
    }
}

/// A group's name and count with a chevron; tapping folds or opens it. Folds are remembered per list.
struct PhoneFoldHeader: View {
    let model: AppModel
    let title: String
    let count: Int
    let group: String
    let list: String
    /// Whether it's folded, for a group whose stored fold means something else, as an area's Completed does.
    let folded: Bool?
    @Environment(\.theme) private var theme

    init(model: AppModel, title: String, count: Int, group: String, in list: String, isFolded: Bool? = nil) {
        self.model = model
        self.title = title
        self.count = count
        self.group = group
        self.list = list
        folded = isFolded
    }

    var body: some View {
        let isFolded = folded ?? model.isFolded(group, in: list)
        Button { withAnimation(.snappy) { model.toggleFolded(group, in: list) } } label: {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .scaledFont(size: 12, weight: .bold)
                        .rotationEffect(.degrees(isFolded ? 0 : 90))
                        .foregroundStyle(theme.color(\.muted))
                    Text(title).scaledFont(size: 17, weight: .semibold).foregroundStyle(theme.color(\.strong))
                    Spacer()
                    Text("\(count)").scaledFont(size: 15).foregroundStyle(theme.color(\.muted))
                }
                Hairline()
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isFolded ? "Collapsed" : "Expanded")
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: A project's tasks

struct PhoneProjectScreen: View {
    let model: AppModel
    let path: String
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        if let project = model.index[path] {
            let all = model.index.tasks(in: project)
            let filter = model.tagFilter(on: .project(path))
            let tasks = filter.apply(all)
            let grouping = model.grouping(of: .project)
            let sections = ListSection.sections(tasks, by: grouping, today: model.today)
            let shown = sections.filter { !model.isFolded($0, by: grouping, in: path) }.flatMap(\.tasks)
            let progress = model.index.progress(of: project)
            let subtasks = project.subtasks

            PhoneList(model: model, title: project.title,
                      titleAccessory: AnyView(PhoneGroupMenu(model: model, list: .project)),
                      fileButton: ("Project File", { nav.push(.file(path)) }),
                      pickable: shown.map(\.path), add: { await newTask(in: project) }) {
                Button("Open Project File", systemImage: "doc") { nav.push(.file(path)) }
                Button("Move to Trash", systemImage: "trash", role: .destructive) {
                    if !model.asksBeforeTrashing([path]) {
                        nav.play(.trash)
                        nav.pop()
                    }
                    Task { await model.moveToTrash([path]) }
                }
            } content: {
                VStack(alignment: .leading, spacing: 12) {
                    PhoneChips(model: model, item: project)
                    let line = (subtasks.total > 0 ? ["Subtasks \(subtasks.done)/\(subtasks.total)"] : [])
                        + (progress.isOngoing ? [] : ["\(progress.done) of \(progress.total) tasks done"])
                    if !line.isEmpty {
                        Text(line.joined(separator: " · "))
                            .scaledFont(size: 13)
                            .foregroundStyle(theme.color(\.muted))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                PhoneTagFilterBar(model: model, domain: .project(path), items: all, shown: tasks.count)
                PhoneTaskSections(model: model, sections: sections, grouping: grouping, foldKey: path, dates: .iconsOnly)
                if all.isEmpty {
                    Text("No tasks link to this project yet.")
                        .foregroundStyle(theme.color(\.muted))
                        .padding(16)
                } else if tasks.isEmpty {
                    Text("No task here carries the picked tags.")
                        .foregroundStyle(theme.color(\.muted))
                        .padding(16)
                }
            }
        } else {
            ContentUnavailableView("Project not found", systemImage: "questionmark.folder",
                                   description: Text("This project’s file is no longer in the folder."))
        }
    }

    private func newTask(in project: Item) async {
        if let path = await model.newLinkedTask(in: project) { nav.push(.file(path)) }
    }
}

// MARK: An area's projects and tasks

struct PhoneAreaScreen: View {
    let model: AppModel
    let path: String
    @State private var isRenaming = false
    @State private var newTitle = ""
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        if let area = model.index[path] {
            let allProjects = model.index.projects(in: area), allFiled = model.index.tasks(in: area)
            let filter = model.tagFilter(on: .area(path))
            let projects = filter.apply(allProjects).map { model.index.progress(of: $0) }
            let filed = filter.apply(allFiled)
            let open = filed.filter { !$0.properties.status.isClosed }
            let done = filed.filter { $0.properties.status.isClosed }
            let shown = (isFolded("Tasks") ? [] : open) + (isFolded("Completed") ? [] : done)

            PhoneList(model: model, title: area.title,
                      subtitle: "\(projects.count == 1 ? "1 project" : "\(projects.count) projects") · \(tasks(open.count))",
                      icon: AnyView(AreaIcon(size: 30)),
                      pickable: shown.map(\.path), add: { await newTask(in: area) }) {
                Button("New Task", systemImage: "plus") { Task { await newTask(in: area) } }
                Button("New Project", systemImage: "chart.pie") { Task { await newProject() } }
                Divider()
                Button("Area File", systemImage: "doc.text") { nav.push(.file(path)) }
                Button("Rename", systemImage: "pencil") {
                    newTitle = area.title
                    isRenaming = true
                }
                if let url = model.vault?.url(for: path) {
                    ShareLink(item: url) { Label("Share…", systemImage: "square.and.arrow.up") }
                }
                Divider()
                Button("Move to Trash", systemImage: "trash", role: .destructive) {
                    Task { await model.moveToTrash([path]) }
                }
            } content: {
                PhoneTagFilterBar(model: model, domain: .area(path), items: allProjects + allFiled,
                                  shown: projects.count + filed.count)
                if filter.isActive, projects.isEmpty, filed.isEmpty {
                    ContentUnavailableView("No matches", systemImage: "line.3.horizontal.decrease",
                                           description: Text("Nothing here carries the picked tags.")).padding(.top, 40)
                } else {
                    if !projects.isEmpty {
                        fold("Projects", count: projects.count)
                        if !isFolded("Projects") {
                            ForEach(projects) { PhoneProjectRow(model: model, progress: $0, showsDates: true) }
                        }
                    }
                    fold("Tasks", count: open.count)
                    if !isFolded("Tasks") {
                        if open.isEmpty, !filter.isActive {
                            Text("No tasks filed straight to \(area.title). Tasks in its projects stay on their project.")
                                .scaledFont(size: 15)
                                .foregroundStyle(theme.color(\.muted))
                                .padding(16)
                        }
                        ForEach(open) { PhoneTaskRow(model: model, item: $0, meta: .chips(.iconsOnly)) }
                    }
                    fold("Completed", count: done.count)
                    if !isFolded("Completed") {
                        ForEach(done) { PhoneTaskRow(model: model, item: $0, meta: .chips(.iconsOnly)) }
                    }
                }
            }
            .alert("Rename Area", isPresented: $isRenaming) {
                TextField("Name", text: $newTitle)
                Button("Cancel", role: .cancel) {}
                Button("Rename") { Task { await rename() } }
            }
        } else {
            ContentUnavailableView("Area not found", systemImage: "questionmark.folder",
                                   description: Text("This area’s file is no longer in the folder."))
        }
    }

    /// Completed starts folded: a stored entry for it means it was opened.
    private func isFolded(_ group: String) -> Bool {
        model.isFolded(group, in: path) != (group == "Completed")
    }

    private func fold(_ title: String, count: Int) -> some View {
        PhoneFoldHeader(model: model, title: title, count: count, group: title, in: path, isFolded: isFolded(title))
    }

    private func newTask(in area: Item) async {
        if let path = await model.newLinkedTask(in: area) { nav.push(.file(path)) }
    }

    private func newProject() async {
        model.domain = .area(path)
        await model.newProject()
        if let path = model.selection { nav.push(.file(path)) }
    }

    /// Renames the area's file, and this screen follows it to its new path.
    private func rename() async {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        model.domain = .area(path)
        await model.rename(path, to: title)
        if case let .area(renamed) = model.domain, renamed != path {
            nav.replace(.area(path), with: .area(renamed))
        }
    }
}
#endif
