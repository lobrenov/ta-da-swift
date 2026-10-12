// The lists the tabs open on: Today and Loose (grouped by area and project), Upcoming (a week strip over the days
// ahead), Projects (with the areas), a project's tasks, and an area's projects and tasks.
#if os(iOS)
import SwiftUI
import TaDaCore

struct PhoneTaskListScreen: View {
    enum Kind { case today, loose }

    let model: AppModel
    let kind: Kind
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let all = kind == .today ? model.todayTasks : model.looseTasks
        let groups = model.index.grouped(all)
        let open = all.count { !$0.properties.status.isClosed }

        PhoneList(model: model, title: kind == .today ? "Today" : "Loose tasks",
                  subtitle: kind == .today
                      ? "\(model.today.date().formatted(.dateTime.weekday(.wide).day().month(.wide))) · \(tasks(open))"
                      : "No project or area · \(tasks(open))",
                  pickable: groups.flatMap(\.tasks).map(\.path), add: newTask) {
            EmptyView()
        } content: {
            if all.isEmpty {
                empty.padding(.top, 60)
            }
            ForEach(groups) { group in
                if let parent = group.parent {
                    if parent.properties.kind == .area {
                        PhoneAreaHeader(area: parent, isFirst: group.id == groups.first?.id)
                    } else {
                        PhoneProjectHeader(project: parent, progress: model.index.progress(of: parent))
                    }
                }
                ForEach(group.tasks) { task in
                    PhoneTaskRow(model: model, item: task,
                                 meta: .chips(kind == .today ? .overdueDueAndDeadline : .labelled))
                }
            }
        }
    }

    private var empty: some View {
        switch kind {
        case .today:
            ContentUnavailableView("Nothing due today", systemImage: "star",
                                   description: Text("Tasks due or at their deadline today, or overdue, show here."))
        case .loose:
            ContentUnavailableView("No loose tasks", systemImage: "tray",
                                   description: Text("Open tasks that don’t belong to a project or an area show here."))
        }
    }

    /// A new task opens with its title ready to type: due today in Today, a loose task in Loose.
    private func newTask() async {
        model.domain = kind == .today ? .today : .loose
        await model.newTask()
        if let path = model.selection { nav.push(.file(path)) }
    }
}

func tasks(_ count: Int) -> String {
    count == 1 ? "1 task" : "\(count) tasks"
}

// MARK: Upcoming

struct PhoneUpcomingScreen: View {
    let model: AppModel
    @State private var target: ScrollRequest?
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    static let days = 7

    var body: some View {
        let today = model.today
        let entries = model.upcoming
        let lastDay = today.adding(days: Self.days)
        let later = Dictionary(grouping: entries.filter { $0.date > lastDay }) { $0.date.startOfMonth }
        var seen = Set<String>()
        let paths = entries.map(\.item.path).filter { seen.insert($0).inserted }

        PhoneList(model: model, title: "Upcoming", pickable: paths,
                  add: newTask, scrollTarget: target) {
            EmptyView()
        } content: {
            WeekStrip(model: model) { offset in
                target = ScrollRequest(offset == 0 ? "top" : "day-\(offset)")
            }
            .id("top")
            ForEach(1...Self.days, id: \.self) { offset in
                let day = today.adding(days: offset)
                let items = entries.filter { $0.date == day }
                DayHeader(number: "\(day.day)", label: offset == 1 ? "Tomorrow" : day.formatted(.weekday), empty: items.isEmpty)
                    .id("day-\(offset)")
                ForEach(items) { row($0, dated: false) }
            }
            ForEach(later.keys.sorted(), id: \.self) { month in
                DayHeader(number: nil, label: month.agendaMonthTitle(today: today), empty: false)
                ForEach(later[month]!) { row($0, dated: true) }
            }
        }
    }

    private func row(_ entry: AgendaEntry, dated: Bool) -> some View {
        let p = entry.item.properties
        let (kind, date): (AgendaEntry.Kind, LocalDate?) = entry.kind == .due ? (.deadline, p.deadline) : (.due, p.dueDate)
        let also = date.map { "\(kind.label) \($0.relativeLabel(today: model.today))" }
        return PhoneTaskRow(model: model, item: entry.item,
                            meta: .agenda(entry, place: model.index.parent(of: entry.item)?.title ?? "Loose task",
                                          also: also, dated: dated))
    }

    private func newTask() async {
        model.domain = .upcoming
        await model.newTask()
        if let path = model.selection { nav.push(.file(path)) }
    }
}

/// Today and the six days after it: the weekday, the date, and dots for due dates and deadlines. Tapping a day
/// scrolls to it.
private struct WeekStrip: View {
    let model: AppModel
    let show: (Int) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        let open = model.index.tasks.filter { !$0.properties.status.isClosed }
        HStack(spacing: 0) {
            ForEach(0..<PhoneUpcomingScreen.days, id: \.self) { offset in
                let day = model.today.adding(days: offset)
                let due = open.contains { $0.properties.dueDate == day }
                let deadline = open.contains { $0.properties.deadline == day }
                Button { show(offset) } label: {
                    VStack(spacing: 3) {
                        Text(day.date().formatted(.dateTime.weekday(.narrow)))
                            .scaledFont(size: 12, weight: .semibold)
                            .foregroundStyle(theme.color(\.muted))
                        Text("\(day.day)")
                            .scaledFont(size: 20, weight: offset == 0 ? .bold : .regular)
                            .foregroundStyle(theme.color(\.strong))
                        HStack(spacing: 3) {
                            if due { Circle().fill(theme.color(\.due)).frame(width: 5, height: 5) }
                            if deadline { Circle().fill(theme.color(\.deadline)).frame(width: 5, height: 5) }
                        }
                        .frame(height: 5)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(offset == 0 ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 12))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.formatted(.weekdayDayMonth) + (due ? ", due dates" : "") + (deadline ? ", deadlines" : ""))
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        // Seven columns: past this, the numbers wouldn't fit.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// A day's number and name over a rule, muted when nothing is on it; or a later month's name.
private struct DayHeader: View {
    let number: String?
    let label: String
    let empty: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let number {
                    Text(number)
                        .scaledFont(size: 22, weight: .bold)
                        .foregroundStyle(theme.color(empty ? \.muted : \.strong))
                }
                Text(label)
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(theme.color(empty ? \.muted : number == nil ? \.strong : \.fg))
            }
            .padding(.top, 12)
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: Projects

struct PhoneProjectsScreen: View {
    let model: AppModel
    @Environment(PhoneNavigation.self) private var nav

    var body: some View {
        let completed = model.index.projects.filter { $0.properties.status.isClosed }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .map { model.index.progress(of: $0) }

        PhoneList(model: model, title: "Projects",
                  subtitle: "\(model.projects.count) open · \(model.areas.count == 1 ? "1 area" : "\(model.areas.count) areas")",
                  add: newProject) {
            Button("New Area", systemImage: "cube") { Task { await newArea() } }
        } content: {
            if model.projects.isEmpty, completed.isEmpty, model.areas.isEmpty {
                ContentUnavailableView("No projects yet", systemImage: "chart.pie",
                                       description: Text("Files with `type: project` or `type: area` show here.")).padding(.top, 60)
            }
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

    private func newProject() async {
        await model.newProject()
        if let path = model.selection { nav.push(.file(path)) }
    }

    private func newArea() async {
        await model.newArea()
        if let path = model.selection { nav.push(.file(path)) }
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
            let tasks = model.index.tasks(in: project)
            let open = tasks.filter { !$0.properties.status.isClosed }
            let done = tasks.filter { $0.properties.status.isClosed }
            let shown = (model.isFolded("Open", in: path) ? [] : open) + (model.isFolded("Completed", in: path) ? [] : done)
            let progress = model.index.progress(of: project)
            let subtasks = project.subtasks

            PhoneList(model: model, title: project.title,
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
                    Button { nav.push(.file(path)) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text").foregroundStyle(theme.color(\.muted))
                            Text("Project file").foregroundStyle(theme.color(\.fg))
                            Spacer()
                            Image(systemName: "chevron.right").scaledFont(size: 14, weight: .semibold)
                                .foregroundStyle(theme.color(\.muted))
                        }
                        .scaledFont(size: 17)
                        .padding(.horizontal, 16)
                        .scaledMinHeight(48)
                        .background(theme.color(\.code), in: .rect(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.color(\.border)))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                group("Open", open)
                group("Completed", done)
                if tasks.isEmpty {
                    Text("No tasks link to this project yet.")
                        .foregroundStyle(theme.color(\.muted))
                        .padding(16)
                }
            }
        } else {
            ContentUnavailableView("Project not found", systemImage: "questionmark.folder",
                                   description: Text("This project’s file is no longer in the folder."))
        }
    }

    @ViewBuilder private func group(_ title: String, _ tasks: [Item]) -> some View {
        if !tasks.isEmpty {
            PhoneFoldHeader(model: model, title: title, count: tasks.count, group: title, in: path)
            if !model.isFolded(title, in: path) {
                ForEach(tasks) { PhoneTaskRow(model: model, item: $0, meta: .chips(.iconsOnly)) }
            }
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
            let projects = model.index.projects(in: area).map { model.index.progress(of: $0) }
            let filed = model.index.tasks(in: area)
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
                if !projects.isEmpty {
                    fold("Projects", count: projects.count)
                    if !isFolded("Projects") {
                        ForEach(projects) { PhoneProjectRow(model: model, progress: $0, showsDates: true) }
                    }
                }
                fold("Tasks", count: open.count)
                if !isFolded("Tasks") {
                    if open.isEmpty {
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
