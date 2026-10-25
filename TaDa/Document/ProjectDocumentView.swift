// A project's own page: title, properties, the description in the live editor, and the tasks that link to it.
#if os(macOS)
import SwiftUI
import TaDaCore

struct ProjectDocumentView: View {
    let model: AppModel
    let document: OpenDocument
    let project: Item
    /// A new linked task's row, scrolled into view once it's laid out.
    @State private var revealed: String?

    var body: some View {
        let tasks = model.index.tasks(in: project)
        ScrollViewReader { proxy in
            GeometryReader { viewport in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        TitleField(model: model, document: document, size: 28)
                        PropertyChips(model: model, item: project)
                        WarningList(warnings: model.index.warnings(for: project))
                        Hairline()
                        BodyEditor(model: model, document: document)
                        LinkedTasksTable(model: model, project: project, tasks: tasks) { revealed = $0 }
                            .padding(.top, 6)
                        Spacer(minLength: 0)
                        DocumentFooter(document: document)
                    }
                    .padding(.horizontal, 56)
                    .padding(.top, 30)
                    .padding(.bottom, 40)
                    .frame(minHeight: viewport.size.height, alignment: .top)
                }
            }
            .task(id: revealed) {
                guard let revealed else { return }
                withAnimation { proxy.scrollTo(revealed, anchor: .center) }
            }
        }
    }
}

/// Every task whose `project` links here: open ones first, by status, then done ones, each status by date. Clicking a row opens the task;
/// its status and dates open their menus, and its title renames it in place. New linked task adds a row here.
private struct LinkedTasksTable: View {
    let model: AppModel
    let project: Item
    let tasks: [Item]
    /// Shows a new task's row.
    let reveal: (String) -> Void
    @Environment(\.theme) private var theme

    private static let order: [Status] = [.doing, .ongoing, .blocked, .notStarted, .done, .cancelled]

    var body: some View {
        let sorted = tasks.enumerated().sorted { a, b in
            let (ra, rb) = (Self.order.firstIndex(of: a.element.properties.status)!, Self.order.firstIndex(of: b.element.properties.status)!)
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "link").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.color(\.link))
                    .accessibilityHidden(true)
                Text("Tasks").font(.system(size: 14, weight: .bold)).foregroundStyle(theme.color(\.strong))
                    .accessibilityAddTraits(.isHeader)
                Text("type: task · project: [[\(project.title)]]")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.color(\.muted))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button {
                    Task { if let path = await model.newLinkedTask(in: project) { reveal(path) } }
                } label: {
                    Label("New linked task", systemImage: "plus")
                }
                .buttonStyle(ActionButtonStyle(height: 28, fill: \.bg))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(theme.color(\.side))
            Hairline()
            columns(Text("status"), Text("title"), Text("dueDate"), Text("deadline"))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(theme.color(\.muted))
            .frame(height: 30)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ForEach(sorted) { task in
                Hairline()
                LinkedTaskRow(model: model, task: task)
                    .id(task.path)
                    .fileMenu(model, path: task.path, cornerRadius: 0)
                    .taskDrag(model, path: task.path)
            }
            if tasks.isEmpty {
                Hairline()
                Text("No tasks link here yet.")
                    .foregroundStyle(theme.color(\.muted))
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
        }
        .clipShape(.rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color(\.border)))
    }
}

/// One linked task. Clicking the row opens the task; the status and date cells open their menus under themselves,
/// and the title renames the task in place.
private struct LinkedTaskRow: View {
    let model: AppModel
    let task: Item
    @State private var hovering = false
    @Environment(\.theme) private var theme

    var body: some View {
        let p = task.properties
        let done = p.status.isClosed
        let subtasks = task.subtasks
        let due = p.dueDate?.relativeLabel(today: model.today)
        let deadline = p.deadline?.relativeLabel(today: model.today)
        let picker = PropertyPicker.shared
        columns(
            PickerCell(isOpen: picker.isOpen(task.path, "status")) {
                picker.pickStatus(of: task, model: model, anchor: $0)
            } label: {
                StatusLabel(status: p.status, dotSize: 7)
            }
            .accessibilityLabel("status")
            .accessibilityValue(p.status.rawValue),
            HStack(spacing: 10) {
                InlineTitleField(model: model, path: task.path, height: 26, font: .system(size: 13)) {
                    TaskTitle(item: task, size: 13)
                }
                .accessibilityIdentifier("linked-task-title")
                .accessibilityLabel("title")
                .accessibilityValue(task.title)
                if subtasks.total > 0 {
                    Chip(systemImage: "checklist", text: "\(subtasks.done)/\(subtasks.total)",
                         spoken: "\(subtasks.done) of \(subtasks.total) subtasks done")
                        .font(.system(size: 11.5))
                }
            },
            PickerCell(isOpen: picker.isOpen(task.path, AgendaEntry.Kind.due.key)) {
                picker.pickDate(.due, of: [task], model: model, anchor: $0)
            } label: {
                Text(due?.capitalizedFirst ?? "—")
                    .foregroundStyle(theme.color(p.dueDate != nil && !done ? \.fg : \.muted))
            }
            .accessibilityLabel("dueDate")
            .accessibilityValue(due ?? "none"),
            PickerCell(isOpen: picker.isOpen(task.path, AgendaEntry.Kind.deadline.key)) {
                picker.pickDate(.deadline, of: [task], model: model, anchor: $0)
            } label: {
                HStack(spacing: 5) {
                    if p.deadline != nil { KindIcon(kind: .deadline) }
                    Text(deadline?.capitalizedFirst ?? "—")
                        .foregroundStyle(theme.color(p.deadline != nil ? \.fg : \.muted))
                }
            }
            .accessibilityLabel("deadline")
            .accessibilityValue(deadline ?? "none")
        )
        .font(.system(size: 12))
        .frame(height: 36)
        .background(hovering ? theme.color(\.code) : .clear)
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture { model.selection = task.path }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(task.title)
        .accessibilityAction(named: "Open task") { model.selection = task.path }
    }
}

/// A cell that opens a menu under itself, `surface` under the pointer and while its menu is open.
private struct PickerCell<Label: View>: View {
    let isOpen: Bool
    let action: (ScreenAnchor) -> Void
    @ViewBuilder var label: Label
    @State private var anchor = ScreenAnchor()
    @State private var hovering = false
    @Environment(\.theme) private var theme

    var body: some View {
        Button { action(anchor) } label: {
            label
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(hovering || isOpen ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 7))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(ScreenAnchorReader(anchor: anchor))
        .onHover { hovering = $0 }
        .padding(.leading, -8)
    }
}

/// The table's four columns: status, title, dueDate and deadline. Only the title stretches.
private func columns(_ status: some View, _ title: some View, _ due: some View, _ deadline: some View) -> some View {
    HStack(spacing: 12) {
        status.frame(width: 128, alignment: .leading)
        title.frame(maxWidth: .infinity, alignment: .leading)
        due.frame(width: 104, alignment: .leading)
        deadline.frame(width: 140, alignment: .leading)
    }
    .lineLimit(1)
    .padding(.horizontal, 16)
}

/// Creates a task filed under the current project or area and opens it with its title ready to type.
struct NewLinkedTaskButton: View {
    let model: AppModel
    var title = "New linked task"
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: create) {
            Label(title, systemImage: "plus")
                .font(.system(size: 12))
                .foregroundStyle(theme.color(\.muted))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func create() {
        Task { await model.newTask() }
    }
}
#endif
