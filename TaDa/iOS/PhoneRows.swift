// Rows in the iPhone's lists: a task with its checkbox and chips, a project with its ring, a project's heading in
// Today and Loose, and the menu a press and hold opens on any of them.
#if os(iOS)
import SwiftUI
import TaDaCore

/// What a task row shows under its title.
enum PhoneRowMeta {
    /// Subtasks, repeat, dates and contexts, as the Mac's rows show them.
    case chips(TaskRow.Dates, contexts: Bool)
    /// An Upcoming entry: its kind, where the task lives, and its other date.
    case agenda(AgendaEntry, place: String, also: String?, dated: Bool)
    /// A search match: where the task lives and when it's due; the title and summary highlight the words.
    case search(words: [String], place: String)
}

struct PhoneTaskRow: View {
    let model: AppModel
    let item: Item
    var meta = PhoneRowMeta.chips(.labelled, contexts: true)
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    init(model: AppModel, item: Item, meta: PhoneRowMeta = .chips(.labelled, contexts: true)) {
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
        .background(isPicked ? theme.color(\.accent).opacity(theme.isDark ? 0.16 : 0.1) : theme.color(\.bg))
        .swipeToPick(item.path)
        .contextMenu { PhoneFileMenu(model: model, item: item) }
    }

    private var title: some View {
        let done = item.properties.status == .done
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
        case let .chips(dates, contexts):
            let chips = chips(dates: dates, contexts: contexts)
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

    private func chips(dates: TaskRow.Dates, contexts: Bool) -> [AnyView] {
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
        if p.status != .done {
            if let due = p.dueDate, dates != .overdueDueAndDeadline || due < today {
                chips.append(AnyView(DateChip(kind: .due, date: due, today: today, labelled: dates != .iconsOnly)))
            }
            if let deadline = p.deadline {
                chips.append(AnyView(DateChip(kind: .deadline, date: deadline, today: today, labelled: dates != .iconsOnly)))
            }
        }
        if contexts, !p.contexts.isEmpty {
            chips.append(AnyView(Text(p.contexts.joined(separator: " "))))
        }
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
        let wasDone = item.properties.status == .done
        nav.play(wasDone ? .pick : .complete)
        Task { await model.toggleCompletion(item) }
    }
}

/// A project in the Projects tab: its ring, title and progress, opening its tasks.
struct PhoneProjectRow: View {
    let model: AppModel
    let progress: ProjectProgress
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
                            .foregroundStyle(theme.color(project.properties.status == .done ? \.muted : \.fg))
                            .lineLimit(2)
                        Text(summary(project))
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
        .contextMenu { PhoneFileMenu(model: model, item: project) }
    }

    private func summary(_ project: Item) -> String {
        var parts = [project.properties.status.rawValue, "\(progress.done) of \(progress.total) done"]
        if let deadline = project.properties.deadline {
            parts.append("Deadline \(deadline.relativeLabel(today: model.today))")
        }
        return parts.joined(separator: " · ")
    }
}

/// A project's heading inside Today or Loose: its ring and title.
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

/// The menu a press and hold opens on a row: complete, today or tomorrow up top; then status, dates, project,
/// share, select (only in the list on screen) and trash.
struct PhoneFileMenu: View {
    let model: AppModel
    let item: Item
    /// False for a row that isn't in the list on screen, which has no picking to join.
    var canSelect = true
    @Environment(PhoneNavigation.self) private var nav

    var body: some View {
        let path = item.path
        let isDone = item.properties.status == .done
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
        if item.properties.kind == .task {
            Button("Move to Project…", systemImage: "folder") { nav.sheet = .project(paths: [path]) }
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
            nav.play(.trash)
            Task { await model.moveToTrash([path]) }
        }
    }
}

extension Status {
    /// The order status menus list them in.
    static let menuOrder: [Status] = [.notStarted, .doing, .blocked, .done]
}
#endif
