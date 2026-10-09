// A task's or project's file: title, property chips and a quiet line, then the body in the live editor (or the whole
// file in Source), and for a project its linked tasks. The tab bar gives way to a toolbar of the file's actions.
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
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    /// The screen shows and edits only the document the model has open.
    private var document: OpenDocument? { opened === model.document ? opened : nil }
    private var shownPath: String { document?.path ?? path }

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
        .background(theme.color(\.bg))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar { toolbar }
        .onAppear { model.selection = shownPath }
        .onDisappear {
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

    /// Follows the focus of the title, body and source text views; a text field in a sheet or alert over the screen
    /// doesn't count.
    private func editingChanged(_ notification: Notification, to editing: Bool) {
        var responder = notification.object as? UIResponder
        while let current = responder {
            if let controller = current as? UIViewController, controller.presentingViewController != nil { return }
            responder = current.next
        }
        isEditing = editing
    }

    private func page(_ document: OpenDocument) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DocumentBanner(model: model, document: document)
                    .padding(.horizontal, -16)
                TitleField(model: model, document: document, size: 28)
                if let item = document.item {
                    PhoneChips(model: model, item: model.index[item.path] ?? item)
                    QuietLine(model: model, item: item)
                }
                WarningList(warnings: document.item.map { model.index[$0.path].map(model.index.warnings(for:)) ?? $0.warnings } ?? [])
                Hairline()
                if isSource {
                    TextEditor(text: Binding { document.text } set: { document.text = $0 })
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(theme.color(\.fg))
                        .scrollContentBackground(.hidden)
                        .scrollDisabled(true)
                        .frame(minHeight: 320)
                        .padding(.horizontal, -5)
                } else {
                    BodyEditor(model: model, document: document) { nav.push(.file($0)) }
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
        .scrollDismissesKeyboard(.interactively)
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
                let isDone = item.properties.status == .done
                Button {
                    nav.play(isDone ? .pick : .complete)
                    Task { await model.toggleCompletion(model.index[item.path] ?? item) }
                } label: {
                    Label(isDone ? "Reopen" : "Complete", systemImage: isDone ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .tint(theme.color(\.done))
                Button("Schedule", systemImage: "calendar") { nav.sheet = .date(.due, paths: [item.path]) }
                Button("Set Deadline", systemImage: "flag") { nav.sheet = .date(.deadline, paths: [item.path]) }
                if item.properties.kind == .task {
                        Button("Move to Project", systemImage: "folder") { nav.sheet = .project(paths: [item.path]) }
                }
                if let url = model.vault?.url(for: item.path) {
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                }
                Button("Move to Trash", systemImage: "trash", role: .destructive) {
                    nav.play(.trash)
                    nav.pop()
                    Task { await model.moveToTrash([item.path]) }
                }
                .tint(theme.color(\.deadline))
            }
        }
    }

    @ViewBuilder private var moreMenu: some View {
        if let item = document?.item {
            if let project = model.index.project(of: item) {
                Button("Open \(project.title)", systemImage: "chart.pie") { nav.push(.project(project.path)) }
            }
            if item.properties.kind == .project {
                Button("Show Tasks", systemImage: "list.bullet") { nav.push(.project(item.path)) }
            }
            let backlinks = model.index.backlinks(to: item)
            if !backlinks.isEmpty {
                Menu("\(backlinks.count) Backlink\(backlinks.count == 1 ? "" : "s")", systemImage: "link") {
                    ForEach(backlinks) { link in
                        Button(link.title) { nav.push(.file(link.path)) }
                    }
                }
            }
            if let modified = document?.modified {
                Text("Modified \(modified.formatted(.relative(presentation: .named)))")
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// The type, the day the file was created and its progress, under the chips.
private struct QuietLine: View {
    let model: AppModel
    let item: Item
    @Environment(\.theme) private var theme

    var body: some View {
        let p = item.properties
        var parts = [p.kind.rawValue]
        if let created = p.createdDate {
            parts.append("created \(created.date().formatted(.dateTime.day().month(.abbreviated).year()))")
        }
        if let completed = p.completedDate {
            parts.append("done \(completed.date().formatted(.dateTime.day().month(.abbreviated).year()))")
        }
        if p.kind == .project {
            let progress = model.index.progress(of: model.index[item.path] ?? item)
            parts.append("\(progress.done) of \(progress.total) tasks done")
        } else if item.subtasks.total > 0 {
            parts.append("\(item.subtasks.done)/\(item.subtasks.total)")
        }
        return Text(parts.joined(separator: " · "))
            .font(.system(size: 13))
            .foregroundStyle(theme.color(\.muted))
    }
}

/// A file's properties as chips: status opens a menu; project, due date and deadline open their sheets. A missing one
/// is a dashed chip that adds it.
struct PhoneChips: View {
    let model: AppModel
    let item: Item
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let p = item.properties
        WrappingHStack(spacing: 8) {
            Menu {
                Picker("Status", selection: Binding { p.status } set: { status in
                    nav.play(.pick)
                    Task { await model.setStatus(status, in: item.path) }
                }) {
                    ForEach(Status.menuOrder, id: \.self) { Text($0.rawValue).tag($0) }
                }
            } label: {
                let (marker, tint) = StatusCheckbox.box(for: p.status, theme: theme)
                chip(missing: false) {
                    InlineCheckboxView(marker: marker, tint: tint, background: theme.bg).frame(width: 16, height: 16)
                    Text(p.status.rawValue)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.color(\.muted))
                }
            }
            .accessibilityLabel("Status")
            .accessibilityValue(p.status.rawValue)
            if p.kind == .task {
                let project = model.index.project(of: item)
                Button { nav.sheet = .project(paths: [item.path]) } label: {
                    if let project {
                        chip(missing: false, text: \.link) {
                            ProgressRing(fraction: model.index.progress(of: project).fraction).foregroundStyle(theme.color(\.accent))
                            Text(project.title).lineLimit(1)
                        }
                    } else if let link = p.project {
                        chip(missing: false, text: \.muted) { Text(link.title).strikethrough() }
                    } else {
                        missing("Project")
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Project")
                .accessibilityValue(project?.title ?? "None")
            }
            dateChip(.due, p.dueDate)
            dateChip(.deadline, p.deadline)
        }
        .font(.system(size: 15))
    }

    private func dateChip(_ kind: AgendaEntry.Kind, _ date: LocalDate?) -> some View {
        let isDone = item.properties.status == .done
        let isOverdue = !isDone && date.map { $0 < model.today } == true
        return Button { nav.sheet = .date(kind, paths: [item.path]) } label: {
            if let date {
                chip(missing: false, text: isDone ? \.muted : isOverdue ? \.deadline : \.fg) {
                    Image(systemName: kind.systemImage).font(.system(size: 13, weight: .semibold))
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
            Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
            Text(name)
        }
    }

    private func chip(missing: Bool, text: KeyPath<Theme, PlatformColor> = \.fg, @ViewBuilder _ label: () -> some View) -> some View {
        HStack(spacing: 6) { label() }
            .foregroundStyle(theme.color(text))
            .padding(.horizontal, 10)
            .frame(height: 34)
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
    @Environment(PhoneNavigation.self) private var nav
    @Environment(\.theme) private var theme

    var body: some View {
        let tasks = model.index.tasks(in: project)
        let sorted = tasks.filter { $0.properties.status != .done } + tasks.filter { $0.properties.status == .done }
        VStack(alignment: .leading, spacing: 0) {
            Text("Tasks")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(theme.color(\.strong))
                .padding(.top, 12)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            ForEach(sorted) { task in
                HStack(spacing: 12) {
                    StatusCheckbox(status: task.properties.status, title: task.title, size: 20) {
                        nav.play(task.properties.status == .done ? .pick : .complete)
                        Task { await model.toggleCompletion(task) }
                    }
                    Button { nav.push(.file(task.path)) } label: {
                        HStack(spacing: 8) {
                            TaskTitle(item: task, size: 16).lineLimit(1)
                            Spacer(minLength: 8)
                            if let (kind, date) = date(of: task) {
                                Image(systemName: kind.systemImage).font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(theme.color(kind.tint))
                                Text(date.relativeLabel(today: model.today).capitalizedFirst)
                                    .font(.system(size: 13))
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
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 14)
                    .frame(height: 38)
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
