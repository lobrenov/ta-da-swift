// The lists the tabs open on: Loose (grouped by area and project), Tasks (the Loose row, then the projects with the
// areas), a project's tasks, and an area's projects and tasks.
#if os(iOS)
import SwiftUI
import TaDaCore

struct PhoneTaskListScreen: View {
    let model: AppModel
    @State private var isFiltering = false
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

        PhoneList(model: model, title: "Loose tasks", subtitle: tasks(open), pickable: pickable, add: newTask) {
            PhoneGroupFilterItems(model: model, group: .loose, domain: .loose, items: all, isFiltering: $isFiltering)
        } content: {
            PhoneTagFilterBar(model: model, domain: .loose, items: all, shown: shownTasks.count)
            if all.isEmpty {
                ContentUnavailableView("No loose tasks", systemImage: "tray")
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
                            PhoneProjectHeader(model: model, project: parent)
                        }
                    }
                    ForEach(group.tasks) { task in
                        PhoneTaskRow(model: model, item: task)
                    }
                }
            } else {
                PhoneTaskSections(model: model, sections: sections, grouping: grouping, foldKey: GroupedList.loose.foldKey, dates: .elsewhere)
            }
        }
        .sheet(isPresented: $isFiltering) { PhoneTagFilterSheet(model: model, domain: .loose, items: all) }
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
                        Text("Loose tasks")
                            .scaledFont(size: 17, weight: .semibold)
                            .foregroundStyle(theme.color(\.strong))
                        Spacer(minLength: 8)
                        if open > 0 {
                            Text("\(open)").scaledFont(size: 15).foregroundStyle(theme.color(\.muted))
                        }
                        Image(systemName: "chevron.right")
                            .scaledFont(size: 14, weight: .semibold)
                            .foregroundStyle(theme.color(\.muted))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
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
            ForEach(entry.projects) { PhoneProjectRow(model: model, progress: $0) }
        }
        if !completed.isEmpty {
            PhoneFoldHeader(model: model, title: "Completed", count: completed.count, group: "Completed", in: "Projects",
                            quiet: true)
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
    /// A closed group (Completed, Done, Cancelled): a smaller muted name.
    let quiet: Bool
    @Environment(\.theme) private var theme

    init(model: AppModel, title: String, count: Int, group: String, in list: String, isFolded: Bool? = nil, quiet: Bool = false) {
        self.model = model
        self.title = title
        self.count = count
        self.group = group
        self.list = list
        folded = isFolded
        self.quiet = quiet
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
                    if quiet {
                        Text(title).scaledFont(size: 15, weight: .semibold).foregroundStyle(theme.color(\.muted))
                        Spacer()
                        Text("\(count)").scaledFont(size: 15).foregroundStyle(theme.color(\.muted))
                    } else {
                        Text(title).scaledFont(size: 20, weight: .bold).foregroundStyle(theme.color(\.strong))
                        Text("\(count)").scaledFont(size: 15).foregroundStyle(theme.color(\.muted))
                        Spacer()
                    }
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
    @State private var isFiltering = false
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

            PhoneList(model: model, title: project.title,
                      fileButton: ("Project File", { nav.push(.file(path)) }),
                      pickable: shown.map(\.path), add: { await newTask(in: project) }) {
                PhoneGroupFilterItems(model: model, group: .project, domain: .project(path), items: all, isFiltering: $isFiltering)
                Divider()
                Button("Open Project File", systemImage: "doc") { nav.push(.file(path)) }
                Button("Move to Trash", systemImage: "trash", role: .destructive) {
                    if !model.asksBeforeTrashing([path]) {
                        nav.play(.trash)
                        nav.pop()
                    }
                    Task { await model.moveToTrash([path]) }
                }
            } content: {
                PhoneProjectLine(model: model, project: project, progress: progress)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                PhoneTagFilterBar(model: model, domain: .project(path), items: all, shown: tasks.count)
                PhoneTaskSections(model: model, sections: sections, grouping: grouping, foldKey: path, dates: .elsewhere)
                if all.isEmpty {
                    Text("No tasks")
                        .foregroundStyle(theme.color(\.muted))
                        .padding(16)
                } else if tasks.isEmpty {
                    Text("No task here carries the picked tags.")
                        .foregroundStyle(theme.color(\.muted))
                        .padding(16)
                }
            }
            .sheet(isPresented: $isFiltering) { PhoneTagFilterSheet(model: model, domain: .project(path), items: all) }
        } else {
            ContentUnavailableView("Project not found", systemImage: "questionmark.folder",
                                   description: Text("This project’s file is no longer in the folder."))
        }
    }

    private func newTask(in project: Item) async {
        if let path = await model.newLinkedTask(in: project) { nav.push(.file(path)) }
    }
}

/// A project's properties as one quiet line: its status, deadline and due date that are set, each a button opening its
/// menu or sheet, then the subtasks and, unless the project is Ongoing, "n of m done".
private struct PhoneProjectLine: View {
    let model: AppModel
    let project: Item
    let progress: ProjectProgress
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let p = project.properties
        let subtasks = project.subtasks
        WrappingHStack(spacing: 14) {
            Menu {
                Picker("Status", selection: Binding(get: { p.status }, set: { status in
                    nav.play(.pick)
                    Task { await model.setStatus(status, in: project.path) }
                })) {
                    ForEach(Status.choices(for: p.kind), id: \.self) { Text($0.rawValue).tag($0) }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(theme.statusColor(p.status)).frame(width: 8, height: 8)
                    Text(p.status.rawValue)
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .accessibilityLabel("Status")
            .accessibilityValue(p.status.rawValue)
            dateButton(.deadline, p.deadline)
            dateButton(.due, p.dueDate)
            if subtasks.total > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "checklist").scaledFont(size: 13)
                    Text("\(subtasks.done)/\(subtasks.total)")
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(subtasks.done) of \(subtasks.total) subtasks done")
            }
            if !progress.isOngoing {
                Text("\(progress.done) of \(progress.total) done")
            }
        }
        .scaledFont(size: 15)
        .foregroundStyle(theme.color(\.muted))
    }

    @ViewBuilder private func dateButton(_ kind: AgendaEntry.Kind, _ date: LocalDate?) -> some View {
        if let date {
            let isDone = project.properties.status.isClosed
            let isOverdue = !isDone && date < model.today
            Button { nav.sheet = .date(kind, paths: [project.path]) } label: {
                HStack(spacing: 5) {
                    Image(systemName: kind.systemImage)
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(theme.color(isDone ? \.muted : kind.tint))
                    Text(date.relativeLabel(today: model.today).capitalizedFirst)
                        .foregroundStyle(theme.color(isOverdue ? \.deadline : \.muted))
                }
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(kind.name)
            .accessibilityValue(date.formatted(.weekdayDayMonthYear) + (isOverdue ? ", overdue" : ""))
        }
    }
}

// MARK: An area's projects and tasks

struct PhoneAreaScreen: View {
    let model: AppModel
    let path: String
    @State private var isRenaming = false
    @State private var newTitle = ""
    @State private var isFiltering = false
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
            let shown = open + (isFolded ? [] : done)

            PhoneList(model: model, title: area.title,
                      subtitle: "\(projects.count == 1 ? "1 project" : "\(projects.count) projects") · \(tasks(open.count))",
                      icon: AnyView(AreaIcon(size: 30)),
                      pickable: shown.map(\.path), add: { await newTask(in: area) }) {
                PhoneGroupFilterItems(model: model, domain: .area(path), items: allProjects + allFiled, isFiltering: $isFiltering)
                Divider()
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
                    ForEach(projects) { PhoneProjectRow(model: model, progress: $0) }
                    if !open.isEmpty {
                        Color.clear.frame(height: projects.isEmpty ? 0 : 22)
                        ForEach(open) { PhoneTaskRow(model: model, item: $0) }
                    }
                    if projects.isEmpty, filed.isEmpty, !filter.isActive {
                        Text("No tasks")
                            .scaledFont(size: 15)
                            .foregroundStyle(theme.color(\.muted))
                            .padding(16)
                    }
                    if !done.isEmpty {
                        PhoneFoldHeader(model: model, title: "Completed", count: done.count, group: "Completed", in: path,
                                        isFolded: isFolded, quiet: true)
                        if !isFolded {
                            ForEach(done) { PhoneTaskRow(model: model, item: $0) }
                        }
                    }
                }
            }
            .alert("Rename Area", isPresented: $isRenaming) {
                TextField("Name", text: $newTitle)
                Button("Cancel", role: .cancel) {}
                Button("Rename") { Task { await rename() } }
            }
            .sheet(isPresented: $isFiltering) {
                PhoneTagFilterSheet(model: model, domain: .area(path), items: allProjects + allFiled)
            }
        } else {
            ContentUnavailableView("Area not found", systemImage: "questionmark.folder",
                                   description: Text("This area’s file is no longer in the folder."))
        }
    }

    /// Completed starts folded: a stored entry for it means it was opened.
    private var isFolded: Bool { !model.isFolded("Completed", in: path) }

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
