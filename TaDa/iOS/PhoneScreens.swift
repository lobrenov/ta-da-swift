// The lists the tabs open on: Today and Loose (grouped by project, with context filters), Upcoming (a week strip
// over the days ahead), Projects, and a project's tasks.
#if os(iOS)
import SwiftUI
import TaDaCore

struct PhoneTaskListScreen: View {
    enum Kind { case today, loose }

    let model: AppModel
    let kind: Kind
    /// nil shows every context.
    @State private var context: String?
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let all = kind == .today ? model.todayTasks : model.looseTasks
        let contexts = Set(all.flatMap(\.properties.contexts)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let shown = all.filter { task in context.map { task.properties.contexts.contains($0) } ?? true }
        let groups = model.index.grouped(shown)
        let open = all.count { $0.properties.status != .done }

        PhoneList(model: model, title: kind == .today ? "Today" : "Loose tasks",
                  subtitle: kind == .today
                      ? "\(model.today.date().formatted(.dateTime.weekday(.wide).day().month(.wide))) · \(tasks(open))"
                      : "No project · \(tasks(open))",
                  pickable: groups.flatMap(\.tasks).map(\.path), add: newTask) {
            EmptyView()
        } content: {
            if !contexts.isEmpty {
                PhoneContextPills(contexts: contexts, selection: $context)
            }
            if shown.isEmpty {
                empty.padding(.top, 60)
            }
            ForEach(groups) { group in
                if let project = group.project {
                    PhoneProjectHeader(project: project, fraction: model.index.progress(of: project).fraction)
                }
                ForEach(group.tasks) { task in
                    PhoneTaskRow(model: model, item: task,
                                 meta: .chips(kind == .today ? .overdueDueAndDeadline : .labelled, contexts: true))
                }
            }
        }
        .onChange(of: contexts) { if let context, !contexts.contains(context) { self.context = nil } }
    }

    private var empty: some View {
        switch kind {
        case .today:
            ContentUnavailableView("Nothing due today", systemImage: "star",
                                   description: Text("Tasks due or at their deadline today, or overdue, show here."))
        case .loose:
            ContentUnavailableView("No loose tasks", systemImage: "tray",
                                   description: Text("Open tasks that don’t belong to a project show here."))
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
                            meta: .agenda(entry, place: model.index.project(of: entry.item)?.title ?? "Loose task",
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
        let open = model.index.tasks.filter { $0.properties.status != .done }
        HStack(spacing: 0) {
            ForEach(0..<PhoneUpcomingScreen.days, id: \.self) { offset in
                let day = model.today.adding(days: offset)
                let due = open.contains { $0.properties.dueDate == day }
                let deadline = open.contains { $0.properties.deadline == day }
                Button { show(offset) } label: {
                    VStack(spacing: 3) {
                        Text(day.date().formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.color(\.muted))
                        Text("\(day.day)")
                            .font(.system(size: 20, weight: offset == 0 ? .bold : .regular))
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
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(theme.color(empty ? \.muted : \.strong))
                }
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
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
        let active = model.projects
        let completed = model.index.projects.filter { $0.properties.status == .done }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .map { model.index.progress(of: $0) }

        PhoneList(model: model, title: "Projects", subtitle: "\(active.count) open · \(completed.count) completed",
                  add: newProject) {
            EmptyView()
        } content: {
            if active.isEmpty, completed.isEmpty {
                ContentUnavailableView("No projects yet", systemImage: "chart.pie",
                                       description: Text("Files with `type: project` show here.")).padding(.top, 60)
            }
            ForEach(active) { PhoneProjectRow(model: model, progress: $0) }
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
}

/// A group's name and count with a chevron; tapping folds or opens it. Folds are remembered per list.
struct PhoneFoldHeader: View {
    let model: AppModel
    let title: String
    let count: Int
    let group: String
    let list: String
    @Environment(\.theme) private var theme

    init(model: AppModel, title: String, count: Int, group: String, in list: String) {
        self.model = model
        self.title = title
        self.count = count
        self.group = group
        self.list = list
    }

    var body: some View {
        let isFolded = model.isFolded(group, in: list)
        Button { withAnimation(.snappy) { model.toggleFolded(group, in: list) } } label: {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .rotationEffect(.degrees(isFolded ? 0 : 90))
                        .foregroundStyle(theme.color(\.muted))
                    Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.color(\.strong))
                    Spacer()
                    Text("\(count)").font(.system(size: 15)).foregroundStyle(theme.color(\.muted))
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
            let open = tasks.filter { $0.properties.status != .done }
            let done = tasks.filter { $0.properties.status == .done }
            let shown = (model.isFolded("Open", in: path) ? [] : open) + (model.isFolded("Completed", in: path) ? [] : done)
            let progress = model.index.progress(of: project)
            let subtasks = project.subtasks

            PhoneList(model: model, title: project.title,
                      pickable: shown.map(\.path), add: { await newTask(in: project) }) {
                Button("Open Project File", systemImage: "doc") { nav.push(.file(path)) }
                Button("Move to Trash", systemImage: "trash", role: .destructive) {
                    nav.play(.trash)
                    nav.pop()
                    Task { await model.moveToTrash([path]) }
                }
            } content: {
                VStack(alignment: .leading, spacing: 12) {
                    PhoneChips(model: model, item: project)
                    Text(((subtasks.total > 0 ? ["Subtasks \(subtasks.done)/\(subtasks.total)"] : [])
                          + ["\(progress.done) of \(progress.total) tasks done"]).joined(separator: " · "))
                        .font(.system(size: 13))
                        .foregroundStyle(theme.color(\.muted))
                    Button { nav.push(.file(path)) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text").foregroundStyle(theme.color(\.muted))
                            Text("Project file").foregroundStyle(theme.color(\.fg))
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.color(\.muted))
                        }
                        .font(.system(size: 17))
                        .padding(.horizontal, 16)
                        .frame(height: 48)
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
                ForEach(tasks) { PhoneTaskRow(model: model, item: $0, meta: .chips(.iconsOnly, contexts: true)) }
            }
        }
    }

    private func newTask(in project: Item) async {
        if let path = await model.newLinkedTask(in: project) { nav.push(.file(path)) }
    }
}
#endif
