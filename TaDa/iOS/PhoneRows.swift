// Rows in the iPhone's lists: a task on one line with its checkbox, glyphs and date, a project with its ring, an area with
// its cube, a note with its page, an area's and a project's heading in Today, and the menu a press and hold opens on any
// of them.
#if os(iOS)
import SwiftUI
import TaDaCore

/// What a task row shows besides its title.
enum PhoneRowMeta {
    /// Glyphs, then where the task lives where the list's groups don't show its project or area, then one date.
    case row(TaskRow.Dates, place: String? = nil)
    /// An Agenda entry: where the task lives and the entry's date.
    case agenda(AgendaEntry, place: String)
    /// A search match: where the task lives under the title; the title and summary highlight the words.
    case search(words: [String], place: String)
}

struct PhoneTaskRow: View {
    let model: AppModel
    let item: Item
    var meta = PhoneRowMeta.row(.elsewhere)
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    init(model: AppModel, item: Item, meta: PhoneRowMeta = .row(.elsewhere)) {
        self.model = model
        self.item = item
        self.meta = meta
    }

    init(model: AppModel, item: Item, search: (words: [String], place: String)) {
        self.init(model: model, item: item, meta: .search(words: search.words, place: search.place))
    }

    var body: some View {
        let isPicked = nav.picked.contains(item.path)
        let isSearch = if case .search = meta { true } else { false }
        VStack(spacing: 0) {
            HStack(alignment: isSearch ? .top : .center, spacing: 12) {
                StatusCheckbox(status: item.properties.status, title: item.title, size: 22) { toggle() }
                    .contentShape(.rect.inset(by: -10))
                    .padding(.top, isSearch ? 1 : 0)
                Button { open() } label: {
                    HStack(spacing: 8) {
                        if case let .search(words, place) = meta {
                            searchBody(words: words, place: place)
                        } else {
                            oneLine
                        }
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
            .padding(.vertical, isSearch ? 10 : 0)
            .scaledMinHeight(isSearch ? 0 : 46)
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

    /// The title, glyphs, place and one date on a line; the place gives way before the title does.
    private var oneLine: some View {
        let done = item.properties.status.isClosed
        let (dates, place, entry): (TaskRow.Dates, String?, AgendaEntry?) = switch meta {
        case let .row(dates, place): (dates, place, nil)
        case let .agenda(entry, place): (.agenda, place, entry)
        case .search: (.elsewhere, nil, nil)
        }
        return HStack(spacing: 8) {
            Text(item.title)
                .scaledFont(size: 17)
                .strikethrough(done)
                .foregroundStyle(theme.color(done ? \.muted : \.fg))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            RowGlyphs(item: item, iconSize: 14)
            Spacer(minLength: 8)
            if let place {
                Text(place)
                    .scaledFont(size: 15)
                    .foregroundStyle(theme.color(\.muted))
                    .lineLimit(1)
                    .layoutPriority(-1)
                    .accessibilityLabel("In \(place)")
            }
            RowDate(item: item, today: model.today, inAgenda: dates == .agenda, entry: entry, textSize: 15, iconSize: 14)
        }
        .foregroundStyle(theme.color(\.muted))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func searchBody(words: [String], place: String) -> some View {
        let done = item.properties.status.isClosed
        let fill = theme.color(\.due).opacity(theme.isDark ? 0.3 : 0.25)
        return VStack(alignment: .leading, spacing: 3) {
            Text(item.title.highlighting(words, fill: fill))
                .scaledFont(size: 17)
                .strikethrough(done)
                .foregroundStyle(theme.color(done ? \.muted : \.fg))
                .lineLimit(2)
            Text(place)
                .scaledFont(size: 13)
                .foregroundStyle(theme.color(\.muted))
                .lineLimit(1)
            if let summary = item.summary, words.contains(where: { summary.localizedStandardContains($0) }) {
                Text(summary.highlighting(words, fill: fill))
                    .scaledFont(size: 15)
                    .foregroundStyle(theme.color(\.fg))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// A project in the Tasks tab or on an area's screen on one line: its ring, name, deadline and open-task count,
/// opening its tasks.
struct PhoneProjectRow: View {
    let model: AppModel
    let progress: ProjectProgress
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let project = progress.project
        let p = project.properties
        let open = model.index.tasks(in: project).count { !$0.properties.status.isClosed }
        VStack(spacing: 0) {
            Button { nav.push(.project(project.path)) } label: {
                HStack(spacing: 12) {
                    ProgressRing(progress)
                        .scaleEffect(22 / 14)
                        .foregroundStyle(theme.color(\.accent))
                        .frame(width: 24)
                    Text(project.title)
                        .scaledFont(size: 17, weight: .semibold)
                        .foregroundStyle(theme.color(p.status.isClosed ? \.muted : \.strong))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let deadline = p.deadline, !p.status.isClosed {
                        let overdue = deadline < model.today
                        HStack(spacing: 4) {
                            Image(systemName: AgendaEntry.Kind.deadline.systemImage)
                                .scaledFont(size: 14)
                                .foregroundStyle(theme.color(\.deadline))
                            Text(deadline.relativeLabel(today: model.today).capitalizedFirst)
                                .scaledFont(size: 15)
                                .foregroundStyle(theme.color(overdue ? \.deadline : \.muted))
                        }
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Deadline \(deadline.relativeLabel(today: model.today))\(overdue ? ", overdue" : "")")
                    }
                    if open > 0 {
                        Text("\(open)")
                            .scaledFont(size: 15)
                            .monospacedDigit()
                            .foregroundStyle(theme.color(\.muted))
                            .accessibilityLabel("^[\(open) open task](inflect: true)")
                    }
                }
                .padding(.horizontal, 16)
                .scaledMinHeight(46)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            PhoneRowSeparator(inset: 52)
        }
        .contextMenu { PhoneFileMenu(model: model, item: project) }
    }
}

/// An area in the Tasks tab on one line: its cube, name, and how many projects and open tasks are filed in it,
/// opening its screen.
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
                    Text(area.title)
                        .scaledFont(size: 17, weight: .semibold)
                        .foregroundStyle(theme.color(\.strong))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(projects == 1 ? "1 project" : "\(projects) projects") · \(tasks(open))")
                        .scaledFont(size: 15)
                        .foregroundStyle(theme.color(\.muted))
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                .padding(.horizontal, 16)
                .scaledMinHeight(46)
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

/// An area's heading inside a list: its cube and name over a rule. Its own tasks follow, then its projects' groups.
struct PhoneAreaHeader: View {
    let area: Item
    var isFirst = false
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                AreaIcon(size: 20)
                Text(area.title).scaledFont(size: 20, weight: .bold).foregroundStyle(theme.color(\.strong)).lineLimit(1)
            }
            Hairline()
        }
        .padding(.horizontal, 16)
        .padding(.top, isFirst ? 6 : 22)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A project's heading inside a list: its ring, name and area over a rule. Under its area's heading (`isUnderArea`)
/// it is smaller and has no rule.
struct PhoneProjectHeader: View {
    let model: AppModel
    let project: Item
    @Environment(\.theme) private var theme

    var body: some View {
        let progress = model.index.progress(of: project)
        let isUnderArea = model.index.area(of: project) != nil
        let area = project.properties.area?.title
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                ProgressRing(progress)
                    .foregroundStyle(theme.color(\.accent))
                    .scaleEffect(isUnderArea ? 1 : 20 / 14)
                    .frame(width: isUnderArea ? 14 : 20, height: isUnderArea ? 14 : 20)
                Text(project.title)
                    .scaledFont(size: isUnderArea ? 17 : 20, weight: isUnderArea ? .semibold : .bold)
                    .foregroundStyle(theme.color(\.strong))
                    .lineLimit(1)
                if let area, !isUnderArea {
                    Text(area).scaledFont(size: 15).foregroundStyle(theme.color(\.muted)).lineLimit(1)
                }
            }
            if !isUnderArea { Hairline() }
        }
        .padding(.horizontal, 16)
        .padding(.top, isUnderArea ? 14 : 22)
        .padding(.bottom, isUnderArea ? 4 : 0)
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
            ForEach(Status.choices(for: item.properties.kind), id: \.self) { Text($0.rawValue).tag($0) }
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
#endif
