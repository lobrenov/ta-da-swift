// Rows in the iPhone's lists: a task with its checkbox and chips, a project with its ring, an area with its cube, a note
// with its page, an area's and a project's heading in Today, and the menu a press and hold opens on any of them.
#if os(iOS)
import SwiftUI
import TaDaCore

/// What a task row shows under its title.
enum PhoneRowMeta {
    /// Subtasks, repeat and dates, as the Mac's rows show them.
    case chips(TaskRow.Dates)
    /// An Upcoming entry: its kind, where the task lives, and its other date.
    case agenda(AgendaEntry, place: String, also: String?, dated: Bool)
    /// A search match: where the task lives and when it's due; the title and summary highlight the words.
    case search(words: [String], place: String)
}

struct PhoneTaskRow: View {
    let model: AppModel
    let item: Item
    var meta = PhoneRowMeta.chips(.labelled)
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    init(model: AppModel, item: Item, meta: PhoneRowMeta = .chips(.labelled)) {
        self.model = model
        self.item = item
        self.meta = meta
    }

    init(model: AppModel, item: Item, search: (words: [String], place: String)) {
        self.init(model: model, item: item, meta: .search(words: search.words, place: search.place))
    }

    var body: some View {
        let isPicked = nav.picked.contains(item.path)
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                StatusCheckbox(status: item.properties.status, title: item.title, size: 22) { toggle() }
                    .contentShape(.rect.inset(by: -10))
                    .padding(.top, 1)
                Button { open() } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            title
                            metaLine
                                .scaledFont(size: 13)
                                .foregroundStyle(theme.color(\.muted))
                                .lineLimit(1)
                            if case let .search(words, _) = meta, let summary = item.summary,
                               words.contains(where: { summary.localizedStandardContains($0) }) {
                                Text(summary.highlighting(words, fill: theme.color(\.due).opacity(theme.isDark ? 0.3 : 0.25)))
                                    .scaledFont(size: 15)
                                    .foregroundStyle(theme.color(\.fg))
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if nav.isPicking {
                            Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                                .scaledFont(size: 22)
                                .foregroundStyle(isPicked ? theme.color(\.accent) : theme.color(\.border))
                                // No height of its own, so the row keeps its height while picking.
                                .frame(height: 0)
                                .transition(.opacity.animation(PhoneNavigation.pickFade))
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isPicked ? .isSelected : [])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            PhoneRowSeparator()
        }
        .background {
            // An opaque base under the highlight, so the swipe's pill stays hidden behind the row.
            ZStack {
                theme.color(\.bg)
                theme.color(\.accent).opacity(isPicked ? (theme.isDark ? 0.16 : 0.1) : 0)
                    .animation(PhoneNavigation.pickFade, value: isPicked)
            }
        }
        .swipeToPick(item.path)
        .contextMenu { PhoneFileMenu(model: model, item: item) }
    }

    private var title: some View {
        let done = item.properties.status.isClosed
        let text: AttributedString = if case let .search(words, _) = meta {
            item.title.highlighting(words, fill: theme.color(\.due).opacity(theme.isDark ? 0.3 : 0.25))
        } else {
            AttributedString(item.title)
        }
        return Text(text)
            .scaledFont(size: 17)
            .strikethrough(done)
            .foregroundStyle(theme.color(done ? \.muted : \.fg))
            .lineLimit(2)
    }

    @ViewBuilder private var metaLine: some View {
        switch meta {
        case let .chips(dates):
            let chips = chips(dates: dates)
            if !chips.isEmpty {
                HStack(spacing: 12) {
                    ForEach(chips.indices, id: \.self) { chips[$0] }
                }
            }
        case let .agenda(entry, place, also, dated):
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    KindIcon(kind: entry.kind)
                    Text(entry.kind.label + (dated ? " \(entry.date.relativeLabel(today: model.today))" : ""))
                }
                Text(place)
                if let also { Text(also) }
            }
        case let .search(_, place):
            Text(place)
        }
    }

    private func chips(dates: TaskRow.Dates) -> [AnyView] {
        let p = item.properties
        let today = model.today
        var chips: [AnyView] = []
        let subtasks = item.subtasks
        if subtasks.total > 0 {
            chips.append(AnyView(Chip(systemImage: "checklist", text: "\(subtasks.done)/\(subtasks.total)",
                                      spoken: "\(subtasks.done) of \(subtasks.total) subtasks done")))
        }
        if let rule = p.repeatRule {
            chips.append(AnyView(Chip(systemImage: "repeat", text: rule, spoken: "Repeats \(rule)")))
        }
        if !p.status.isClosed {
            if let due = p.dueDate, dates != .overdueDueAndDeadline || due < today {
                chips.append(AnyView(DateChip(kind: .due, date: due, today: today, labelled: dates != .iconsOnly)))
            }
            if let deadline = p.deadline {
                chips.append(AnyView(DateChip(kind: .deadline, date: deadline, today: today, labelled: dates != .iconsOnly)))
            }
        }
        if !item.tags.isEmpty { chips.append(AnyView(TagCountChip(tags: item.tags))) }
        return chips
    }

    private func open() {
        if nav.isPicking {
            nav.togglePicked(item.path)
        } else {
            nav.push(.file(item.path))
        }
    }

    private func toggle() {
        let wasDone = item.properties.status.isClosed
        nav.play(wasDone ? .pick : .complete)
        Task { await model.toggleCompletion(item) }
    }
}

/// A project in the Projects tab or on an area's screen: its ring, title and progress, opening its tasks. Under an
/// area in the Projects tab (`isCompact`) it shows its open tasks' count instead; on an area's screen (`showsDates`)
/// its subtasks, due date and deadline follow its progress, as a task row shows them.
struct PhoneProjectRow: View {
    let model: AppModel
    let progress: ProjectProgress
    var isCompact = false
    var showsDates = false
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let project = progress.project
        VStack(spacing: 0) {
            Button { nav.push(.project(project.path)) } label: {
                HStack(spacing: 12) {
                    ProgressRing(fraction: progress.fraction)
                        .scaleEffect(22 / 14)
                        .foregroundStyle(theme.color(\.accent))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.title)
                            .scaledFont(size: 17)
                            .foregroundStyle(theme.color(project.properties.status.isClosed ? \.muted : \.fg))
                            .lineLimit(2)
                        if !isCompact {
                            meta(project)
                                .scaledFont(size: 13)
                                .foregroundStyle(theme.color(\.muted))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    if isCompact, progress.open > 0 {
                        Text("\(progress.open)").scaledFont(size: 15).foregroundStyle(theme.color(\.muted))
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
            PhoneRowSeparator(inset: 52)
        }
        .contextMenu { PhoneFileMenu(model: model, item: project) }
    }

    @ViewBuilder private func meta(_ project: Item) -> some View {
        let p = project.properties
        let summary = "\(p.status.rawValue) · \(progress.done) of \(progress.total) done"
        if showsDates {
            let subtasks = project.subtasks
            HStack(spacing: 12) {
                Text(summary)
                if subtasks.total > 0 {
                    Chip(systemImage: "checklist", text: "\(subtasks.done)/\(subtasks.total)",
                         spoken: "\(subtasks.done) of \(subtasks.total) subtasks done")
                }
                if !p.status.isClosed {
                    if let due = p.dueDate { DateChip(kind: .due, date: due, today: model.today, labelled: false) }
                    if let deadline = p.deadline { DateChip(kind: .deadline, date: deadline, today: model.today, labelled: false) }
                }
            }
        } else {
            Text(summary + (p.deadline.map { " · Deadline \($0.relativeLabel(today: model.today))" } ?? ""))
        }
    }
}

/// An area in the Projects tab: its cube, title, and how many projects and tasks are filed in it, opening its screen.
struct PhoneAreaRow: View {
    let model: AppModel
    let area: Item
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let projects = model.index.projects(in: area).count
        let open = model.index.tasks(in: area).count { !$0.properties.status.isClosed }
        VStack(spacing: 0) {
            Button { nav.push(.area(area.path)) } label: {
                HStack(spacing: 12) {
                    AreaIcon(size: 24).frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(area.title)
                            .scaledFont(size: 17, weight: .semibold)
                            .foregroundStyle(theme.color(\.strong))
                            .lineLimit(2)
                        Text("\(projects == 1 ? "1 project" : "\(projects) projects") · \(tasks(open))")
                            .scaledFont(size: 13)
                            .foregroundStyle(theme.color(\.muted))
                            .lineLimit(1)
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
        .contextMenu { PhoneFileMenu(model: model, item: area) }
    }
}

/// A note in a tag's screen or search: its page, title, and subtasks and folder, opening its file.
struct PhoneNoteRow: View {
    let model: AppModel
    let note: Item
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let folder = Vault.folder(of: note.path)
        let subtasks = note.subtasks
        let meta = (subtasks.total > 0 ? ["\(subtasks.done)/\(subtasks.total)"] : []) + [folder.isEmpty ? "Loose" : folder]
        VStack(spacing: 0) {
            Button { nav.push(.file(note.path)) } label: {
                HStack(spacing: 12) {
                    NoteIcon(size: 22).frame(width: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(note.title)
                            .scaledFont(size: 17)
                            .foregroundStyle(theme.color(\.fg))
                            .lineLimit(2)
                        Text(meta.joined(separator: " · "))
                            .scaledFont(size: 13)
                            .foregroundStyle(theme.color(\.muted))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            PhoneRowSeparator(inset: 52)
        }
    }
}

/// An area's heading inside Today: its cube and title over a rule. Its own tasks follow, then its projects' groups.
struct PhoneAreaHeader: View {
    let area: Item
    var isFirst = false
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                AreaIcon(size: 16)
                Text(area.title).scaledFont(size: 15, weight: .semibold).foregroundStyle(theme.color(\.strong)).lineLimit(1)
            }
            Hairline()
        }
        .padding(.horizontal, 16)
        .padding(.top, isFirst ? 6 : 22)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A project's heading inside Today: its ring and title.
struct PhoneProjectHeader: View {
    let project: Item
    let fraction: Double
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            ProgressRing(fraction: fraction).foregroundStyle(theme.color(\.accent))
            Text(project.title).scaledFont(size: 15, weight: .semibold).foregroundStyle(theme.color(\.strong)).lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The menu a press and hold opens on a row: complete, today or tomorrow up top; then status, dates, move (to an
/// area for a project), share, select (only in the list on screen) and trash. On an area: its file, share and trash.
struct PhoneFileMenu: View {
    let model: AppModel
    let item: Item
    /// False for a row that isn't in the list on screen, which has no picking to join.
    var canSelect = true
    @Environment(PhoneNavigation.self) private var nav

    var body: some View {
        if item.properties.kind == .area {
            areaItems
        } else {
            fileItems
        }
    }

    @ViewBuilder private var areaItems: some View {
        Button("Area File", systemImage: "doc.text") { nav.push(.file(item.path)) }
        if let url = model.vault?.url(for: item.path) {
            ShareLink(item: url) { Label("Share…", systemImage: "square.and.arrow.up") }
        }
        Divider()
        Button("Move to Trash", systemImage: "trash", role: .destructive) {
            Task { await model.moveToTrash([item.path]) }
        }
    }

    @ViewBuilder private var fileItems: some View {
        let path = item.path
        let isDone = item.properties.status.isClosed
        ControlGroup {
            Button {
                nav.play(isDone ? .pick : .complete)
                Task { await model.toggleCompletion(item) }
            } label: {
                Label(isDone ? "Reopen" : "Complete", systemImage: isDone ? "arrow.uturn.backward.circle" : "checkmark.circle")
            }
            Button {
                nav.play(.pick)
                Task { await model.setDate(.due, to: model.today, of: [path]) }
            } label: {
                Label("Today", systemImage: "star")
            }
            Button {
                nav.play(.pick)
                Task { await model.setDate(.due, to: model.today.adding(days: 1), of: [path]) }
            } label: {
                Label("Tomorrow", systemImage: "sun.max")
            }
        }
        Picker(selection: Binding { item.properties.status } set: { status in
            nav.play(.pick)
            Task { await model.setStatus(status, in: path) }
        }) {
            ForEach(Status.menuOrder, id: \.self) { Text($0.rawValue).tag($0) }
        } label: {
            Label("Status", systemImage: "circle.dashed")
        }
        .pickerStyle(.menu)
        Button("Schedule…", systemImage: "calendar") { nav.sheet = .date(.due, paths: [path]) }
        Button("Set Deadline…", systemImage: "flag") { nav.sheet = .date(.deadline, paths: [path]) }
        Button("Move…", systemImage: "folder") {
            nav.sheet = item.properties.kind == .task ? .move(paths: [path]) : .area(paths: [path])
        }
        Divider()
        if let url = model.vault?.url(for: path) {
            ShareLink(item: url) { Label("Share…", systemImage: "square.and.arrow.up") }
        }
        if canSelect, nav.pickable.contains(path) {
            Button("Select", systemImage: "checkmark.circle") { nav.startPicking(path) }
        }
        Divider()
        Button("Move to Trash", systemImage: "trash", role: .destructive) {
            if !model.asksBeforeTrashing([path]) { nav.play(.trash) }
            Task { await model.moveToTrash([path]) }
        }
    }
}

extension Status {
    /// The order status menus list them in.
    static let menuOrder: [Status] = [.notStarted, .doing, .blocked, .done, .cancelled]
}
#endif
