// A task's, project's, area's or note's file: title, property chips (none for an area or note), tags and a quiet line, then the body in the
// live editor (or the whole file in Source), and for a project its linked tasks. The tab bar gives way to a toolbar of
// the file's actions.
#if os(iOS)
import SwiftUI
import UIKit
import TaDaCore

struct PhoneFileScreen: View {
    let model: AppModel
    let path: String
    /// The file this screen shows once it's read; it follows the file through renames.
    @State private var opened: OpenDocument?
    @State private var isSource = false
    @State private var isEditing = false
    @State private var isVisible = false
    @State private var search = ListSearch()
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    /// The screen shows and edits only the document the model has open.
    private var document: OpenDocument? { opened === model.document ? opened : nil }
    private var shownPath: String { opened?.path ?? path }

    var body: some View {
        Group {
            if let document {
                page(document)
            } else if let error = model.documentError, model.selection == path {
                ContentUnavailableView("Couldn’t open the file", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background { theme.color(\.bg).ignoresSafeArea() }
        .navigationBarTitleDisplayMode(.inline)
        .background { TabBarHiddenOnTop() }
        .toolbar {
            if search.isOpen {
                // Keeps the navigation bar, so the page stays below the search field in its row.
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
            } else {
                toolbar
            }
        }
        .navigationBarBackButtonHidden(search.isOpen)
        .onAppear {
            isVisible = true
            model.selection = shownPath
        }
        .onDisappear {
            isVisible = false
            isEditing = false
            // Popping the screen closes the file; a tab switch, or a screen pushed over it, leaves it open.
            let shown = shownPath
            Task {
                if !nav.stacks.values.contains(where: { $0.contains(.file(path)) }), model.selection == shown {
                    model.selection = nil
                }
            }
        }
        .onChange(of: model.document.map(ObjectIdentifier.init), initial: true) {
            if let open = model.document, open === opened || open.path == shownPath { opened = open }
        }
        .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidBeginEditingNotification)) { editingChanged($0, to: true) }
        .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidEndEditingNotification)) { editingChanged($0, to: false) }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { editingChanged($0, to: true) }
        .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidEndEditingNotification)) { editingChanged($0, to: false) }
    }

    /// Follows the focus of the title, body and source text views while the screen is showing; a text field in a
    /// sheet or alert over the screen, or on another screen, doesn't count.
    private func editingChanged(_ notification: Notification, to editing: Bool) {
        guard isVisible else { return }
        var responder = notification.object as? UIResponder
        while let current = responder {
            if let controller = current as? UIViewController, controller.presentingViewController != nil { return }
            responder = current.next
        }
        isEditing = editing
    }

    private func page(_ document: OpenDocument) -> some View {
        ScrollView {
            if search.isSearching {
                PhoneSearchResults(model: model, query: search.query)
            } else {
                fileContent(document)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .pullToSearch(search)
    }

    private func fileContent(_ document: OpenDocument) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            DocumentBanner(model: model, document: document)
                .padding(.horizontal, -16)
            TitleField(model: model, document: document, size: 28)
            if let item = document.item {
                if item.properties.kind != .area {
                    if item.properties.kind != .note { PhoneChips(model: model, item: model.index[item.path] ?? item) }
                    PhoneTagChips(model: model, item: model.index[item.path] ?? item)
                }
                QuietLine(model: model, item: item)
                if item.properties.kind == .area {
                    PhoneTagChips(model: model, item: model.index[item.path] ?? item)
                }
            }
            WarningList(warnings: document.item.map { model.index[$0.path].map(model.index.warnings(for:)) ?? $0.warnings } ?? [])
            Hairline()
            if isSource {
                TextEditor(text: Binding { document.text } set: { document.text = $0 })
                    .scaledFont(size: 15, design: .monospaced)
                    .foregroundStyle(theme.color(\.fg))
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .frame(minHeight: 320)
                    .padding(.horizontal, -5)
            } else {
                BodyEditor(model: model, document: document, open: { nav.push(.file($0)) },
                           openTag: { nav.push(.tag($0.path)) })
            }
            if let item = document.item, item.properties.kind == .project {
                PhoneLinkedTasks(model: model, project: model.index[item.path] ?? item)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        // While editing, room for the last line to scroll above the keyboard bar.
        .padding(.bottom, isEditing ? 100 : 40)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismissKeyboard() }
                    .buttonStyle(.glassProminent)
                    .tint(theme.color(\.accent))
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isSource.toggle() } label: {
                    Label(isSource ? "Live" : "Source", systemImage: isSource ? "doc.richtext" : "doc.plaintext")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu { moreMenu } label: { Label("More", systemImage: "ellipsis") }
            }
        }
        if let item = document?.item {
            ToolbarItemGroup(placement: .bottomBar) {
                if item.properties.kind == .task || item.properties.kind == .project {
                    let status = item.properties.status
                    let setStatus = { (status: Status) in
                        nav.play(.pick)
                        Task { await model.setStatus(status, in: item.path) }
                    }
                    // A tap completes or reopens; a press and hold opens the statuses, which VoiceOver lists as actions.
                    Menu {
                        Picker("Status", selection: Binding(get: { status }, set: setStatus)) {
                            ForEach(Status.choices(for: item.properties.kind), id: \.self) { option in
                                Label { Text(option.rawValue) } icon: { Image(uiImage: statusImage(option)) }
                                    .tag(option)
                            }
                        }
                    } label: {
                        Label { Text(status.isClosed ? "Reopen" : "Complete") } icon: { Image(uiImage: statusImage(status)) }
                    } primaryAction: {
                        nav.play(status.isClosed ? .pick : .complete)
                        Task { await model.toggleCompletion(model.index[item.path] ?? item) }
                    }
                    .accessibilityValue(status.rawValue)
                    .accessibilityActions {
                        ForEach(Status.choices(for: item.properties.kind).filter { $0 != status }, id: \.self) { option in
                            Button(option.rawValue) { setStatus(option) }
                        }
                    }
                    Button("Schedule", systemImage: "calendar") { nav.sheet = .date(.due, paths: [item.path]) }
                    Button("Set Deadline", systemImage: "flag") { nav.sheet = .date(.deadline, paths: [item.path]) }
                }
                if item.properties.kind == .task {
                    Button("Move", systemImage: "folder") { nav.sheet = .move(paths: [item.path]) }
                }
                if let url = model.vault?.url(for: item.path) {
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                }
                Button("Move to Trash", systemImage: "trash", role: .destructive) {
                    // An area, or a file that embeds images, asks first, and its screens go once it's deleted.
                    if !model.asksBeforeTrashing([item.path]) {
                        nav.play(.trash)
                        nav.pop()
                    }
                    Task { await model.moveToTrash([item.path]) }
                }
                .tint(theme.color(\.deadline))
            }
        }
    }

    @ViewBuilder private var moreMenu: some View {
        if let item = document?.item {
            if let parent = model.index.parent(of: item) {
                let isArea = parent.properties.kind == .area
                Button("Open \(parent.title)", systemImage: isArea ? "cube" : "chart.pie") {
                    nav.push(isArea ? .area(parent.path) : .project(parent.path))
                }
            }
            if item.properties.kind == .project {
                Button("Show Tasks", systemImage: "list.bullet") { nav.push(.project(item.path)) }
            }
            if item.properties.kind == .area {
                Button("Show Projects and Tasks", systemImage: "list.bullet") { nav.push(.area(item.path)) }
            }
            if let modified = document?.modified {
                Text("Modified \(modified.formatted(.relative(presentation: .named)))")
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// A status's checkbox as an image in its own colours, for the toolbar and its menu, which show only images.
    private func statusImage(_ status: Status) -> UIImage {
        let (marker, tint) = StatusCheckbox.box(for: status, theme: theme)
        let rect = CGRect(x: 0, y: 0, width: 22, height: 22)
        return UIGraphicsImageRenderer(bounds: rect).image { context in
            InlineCheckbox.draw(marker, in: rect, tint: tint, background: theme.bg, context: context.cgContext)
        }
        .withRenderingMode(.alwaysOriginal)
    }
}

/// Hides the tab bar while the screen is on top, through the tab bar controller as the navigation transition that
/// shows or covers the screen starts, so the bar animates with the push and the pop; a cancelled swipe back puts it back.
private struct TabBarHiddenOnTop: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            setTabBarHidden(true)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            setTabBarHidden(false)
        }

        private func setTabBarHidden(_ hidden: Bool) {
            guard let tabBarController else { return }
            guard let coordinator = transitionCoordinator else {
                tabBarController.setTabBarHidden(hidden, animated: false)
                return
            }
            tabBarController.setTabBarHidden(hidden, animated: true)
            coordinator.animate(alongsideTransition: nil) { context in
                if context.isCancelled { tabBarController.setTabBarHidden(!hidden, animated: true) }
            }
        }
    }
}

/// The type, the status, a task's area through its project, the day the file was created, its progress and the files
/// that link here (a menu of them), under the chips.
private struct QuietLine: View {
    let model: AppModel
    let item: Item
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let p = item.properties
        var parts = [p.kind.rawValue]
        if p.kind == .task || p.kind == .project { parts.append(p.status.rawValue) }
        if p.kind == .task, p.project != nil, let area = model.index.area(of: item) {
            parts.append("in \(area.title)")
        }
        if let created = p.createdDate {
            parts.append("created \(created.date().formatted(.dateTime.day().month(.abbreviated).year()))")
        }
        if let completed = p.completedDate {
            parts.append("done \(completed.date().formatted(.dateTime.day().month(.abbreviated).year()))")
        }
        if p.kind == .project {
            let progress = model.index.progress(of: model.index[item.path] ?? item)
            if !progress.isOngoing { parts.append("\(progress.done) of \(progress.total) tasks done") }
        } else if p.kind == .area {
            let projects = model.index.projects(in: item).count
            parts.append("\(projects == 1 ? "1 project" : "\(projects) projects") · \(tasks(model.index.tasks(in: item).count))")
        } else if item.subtasks.total > 0 {
            parts.append("\(item.subtasks.done)/\(item.subtasks.total)")
        }
        let backlinks = model.index.backlinks(to: item)
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(parts.joined(separator: " · "))
            if !backlinks.isEmpty {
                Menu {
                    ForEach(backlinks) { link in
                        Button(link.title) { nav.push(.file(link.path)) }
                    }
                } label: {
                    Text(" · \(backlinks.count == 1 ? "1 backlink" : "\(backlinks.count) backlinks")")
                }
            }
        }
        .scaledFont(size: 13)
        .foregroundStyle(theme.color(\.muted))
    }
}

/// A file's properties as chips: a task's project or area (the move sheet), a project's area (the area sheet), due date
/// and deadline open their sheets; the status is the toolbar's checkbox. A missing one is a dashed chip that adds it; a
/// project or area no file has is struck through.
struct PhoneChips: View {
    let model: AppModel
    let item: Item
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let p = item.properties
        WrappingHStack(spacing: 8) {
            if p.kind == .task || p.kind == .project {
                let parent = model.index.parent(of: item)
                let link = p.kind == .task ? p.project ?? p.area : p.area
                let isArea = parent.map { $0.properties.kind == .area } ?? (p.kind == .project || p.project == nil && p.area != nil)
                Button { nav.sheet = p.kind == .task ? .move(paths: [item.path]) : .area(paths: [item.path]) } label: {
                    if let parent {
                        chip(missing: false, text: \.link) {
                            if isArea {
                                AreaIcon(size: 15)
                            } else {
                                ProgressRing(model.index.progress(of: parent)).foregroundStyle(theme.color(\.accent))
                            }
                            Text(parent.title).lineLimit(1)
                        }
                    } else if let link {
                        chip(missing: false, text: \.muted) {
                            if isArea { AreaIcon(size: 15, tint: \.muted) }
                            Text(link.title).strikethrough()
                        }
                    } else {
                        missing(p.kind == .task ? "Project" : "Area")
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isArea ? "Area" : "Project")
                .accessibilityValue(parent?.title ?? link.map { "\($0.title), not found" } ?? "None")
            }
            dateChip(.due, p.dueDate)
            dateChip(.deadline, p.deadline)
        }
        .scaledFont(size: 15)
    }

    private func dateChip(_ kind: AgendaEntry.Kind, _ date: LocalDate?) -> some View {
        let isDone = item.properties.status.isClosed
        let isOverdue = !isDone && date.map { $0 < model.today } == true
        return Button { nav.sheet = .date(kind, paths: [item.path]) } label: {
            if let date {
                chip(missing: false, text: isDone ? \.muted : isOverdue ? \.deadline : \.fg) {
                    Image(systemName: kind.systemImage).scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(theme.color(isDone ? \.muted : kind.tint))
                    Text(date.relativeLabel(today: model.today).capitalizedFirst)
                }
            } else {
                missing(kind.name)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.name)
        .accessibilityValue(date.map { $0.formatted(.weekdayDayMonthYear) + (isOverdue ? ", overdue" : "") } ?? "None")
    }

    private func missing(_ name: String) -> some View {
        chip(missing: true, text: \.muted) {
            Image(systemName: "plus").scaledFont(size: 12, weight: .semibold)
            Text(name)
        }
    }

    private func chip(missing: Bool, text: KeyPath<Theme, PlatformColor> = \.fg, @ViewBuilder _ label: () -> some View) -> some View {
        HStack(spacing: 6) { label() }
            .foregroundStyle(theme.color(text))
            .padding(.horizontal, 10)
            .scaledMinHeight(34)
            .background(missing ? .clear : theme.color(\.code), in: .rect(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(theme.color(\.border), style: StrokeStyle(lineWidth: 1, dash: missing ? [4, 3] : []))
            }
            .contentShape(.rect)
    }
}

/// A project's tasks on its file: open ones first, then done ones, each with its date; and New Linked Task.
private struct PhoneLinkedTasks: View {
    let model: AppModel
    let project: Item
    @ScaledMetric(relativeTo: .body) private var titleSize: CGFloat = 16
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let tasks = model.index.tasks(in: project)
        let sorted = tasks.filter { !$0.properties.status.isClosed } + tasks.filter { $0.properties.status.isClosed }
        VStack(alignment: .leading, spacing: 0) {
            Text("Tasks")
                .scaledFont(size: 22, weight: .bold)
                .foregroundStyle(theme.color(\.strong))
                .padding(.top, 12)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            ForEach(sorted) { task in
                HStack(spacing: 12) {
                    StatusCheckbox(status: task.properties.status, title: task.title, size: 20) {
                        nav.play(task.properties.status.isClosed ? .pick : .complete)
                        Task { await model.toggleCompletion(task) }
                    }
                    Button { nav.push(.file(task.path)) } label: {
                        HStack(spacing: 8) {
                            TaskTitle(item: task, size: titleSize).lineLimit(1)
                            Spacer(minLength: 8)
                            if let (kind, date) = date(of: task) {
                                Image(systemName: kind.systemImage).scaledFont(size: 11, weight: .semibold)
                                    .foregroundStyle(theme.color(kind.tint))
                                Text(date.relativeLabel(today: model.today).capitalizedFirst)
                                    .scaledFont(size: 13)
                                    .foregroundStyle(theme.color(\.muted))
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                .frame(minHeight: 44)
                .contextMenu { PhoneFileMenu(model: model, item: task, canSelect: false) }
            }
            Button {
                Task { if let path = await model.newLinkedTask(in: project) { nav.push(.file(path)) } }
            } label: {
                Label("New Linked Task", systemImage: "plus")
                    .scaledFont(size: 15, weight: .medium)
                    .padding(.horizontal, 14)
                    .scaledMinHeight(38)
                    .overlay(Capsule().strokeBorder(theme.color(\.border)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.color(\.fg))
            .padding(.top, 12)
        }
    }

    /// The due date, or the deadline when there's no due date.
    private func date(of task: Item) -> (AgendaEntry.Kind, LocalDate)? {
        let p = task.properties
        if let due = p.dueDate { return (.due, due) }
        return p.deadline.map { (.deadline, $0) }
    }
}
#endif
