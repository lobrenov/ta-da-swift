// A project's own page: title, two columns of properties, the description in the live editor,
// and the tasks that link to it.
import SwiftUI
import TaDaCore

struct ProjectDocumentView: View {
    let model: AppModel
    let document: OpenDocument
    let project: Item
    @Environment(\.theme) private var theme

    var body: some View {
        let tasks = model.index.tasks(in: project)
        GeometryReader { viewport in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        ProgressRing(fraction: model.index.progress(of: project))
                            .scaleEffect(1.7).frame(width: 24, height: 24)
                            .foregroundStyle(theme.color(\.accent))
                        TitleField(model: model, document: document, size: 28)
                        Text("\(tasks.count { $0.properties.status == .done }) of \(tasks.count) tasks done")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.color(\.muted))
                            .fixedSize()
                    }
                    HStack(alignment: .top, spacing: 40) {
                        PropertyTable(model: model, item: project, keys: ["type", "status", "area"], keyWidth: 116)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        PropertyTable(model: model, item: project, keys: ["createdDate", "dueDate", "deadline"], keyWidth: 116)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    WarningList(warnings: model.index.warnings(for: project))
                    Hairline()
                    BodyEditor(model: model, document: document)
                        .frame(maxWidth: 736, alignment: .leading)
                    LinkedTasksTable(model: model, project: project, tasks: tasks)
                        .padding(.top, 6)
                    Spacer(minLength: 0)
                    DocumentFooter(model: model, document: document)
                }
                .padding(.horizontal, 56)
                .padding(.top, 30)
                .padding(.bottom, 40)
                .frame(minHeight: viewport.size.height, alignment: .top)
            }
        }
    }
}

/// Every task whose `project` links here: open ones first, by status, then done ones.
private struct LinkedTasksTable: View {
    let model: AppModel
    let project: Item
    let tasks: [Item]
    @Environment(\.theme) private var theme

    private static let order: [Status] = [.doing, .blocked, .notStarted, .done]

    var body: some View {
        let sorted = tasks.enumerated().sorted { a, b in
            let (ra, rb) = (Self.order.firstIndex(of: a.element.properties.status)!, Self.order.firstIndex(of: b.element.properties.status)!)
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "link").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.color(\.link))
                Text("Tasks").font(.system(size: 14, weight: .bold)).foregroundStyle(theme.color(\.strong))
                    .accessibilityAddTraits(.isHeader)
                Text("type: task · project: [[\(project.title)]]")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.color(\.muted))
                    .lineLimit(1)
                Spacer(minLength: 8)
                NewLinkedTaskButton(model: model, bordered: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(theme.color(\.side))
            Hairline()
            columns(Text("status"), Text("title"), Text("dueDate"), Text("deadline"), Text("contexts"))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(theme.color(\.muted))
            .frame(height: 30)
            .accessibilityHidden(true)
            ForEach(sorted) { task in
                Hairline()
                Button { model.selection = task.path } label: { taskRow(task).contentShape(.rect) }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Opens the task")
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

    private func taskRow(_ task: Item) -> some View {
        let p = task.properties
        let done = p.status == .done
        let subtasks = task.subtasks
        return columns(
            StatusLabel(status: p.status, dotSize: 7),
            HStack(spacing: 10) {
                TaskTitle(item: task, size: 13).lineLimit(1)
                if subtasks.total > 0 { Chip(systemImage: "checklist", text: "\(subtasks.done)/\(subtasks.total)").font(.system(size: 11.5)) }
            },
            Text(p.dueDate?.relativeLabel(today: model.today).capitalizedFirst ?? "—")
                .foregroundStyle(theme.color(p.dueDate != nil && !done ? \.fg : \.muted)),
            HStack(spacing: 5) {
                if p.deadline != nil {
                    Image(systemName: "flag").font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.color(\.deadline))
                }
                Text(p.deadline?.relativeLabel(today: model.today).capitalizedFirst ?? "—")
                    .foregroundStyle(theme.color(p.deadline != nil ? \.fg : \.muted))
            },
            Text(p.contexts.joined(separator: " ")).foregroundStyle(theme.color(\.muted))
        )
        .font(.system(size: 12))
        .frame(height: 36)
    }

    /// The table's five columns: status, title, dueDate, deadline and contexts. Only the title stretches.
    private func columns(_ status: some View, _ title: some View, _ due: some View, _ deadline: some View,
                         _ contexts: some View) -> some View {
        HStack(spacing: 12) {
            status.frame(width: 128, alignment: .leading)
            title.frame(maxWidth: .infinity, alignment: .leading)
            due.frame(width: 104, alignment: .leading)
            deadline.frame(width: 140, alignment: .leading)
            contexts.frame(width: 96, alignment: .leading)
        }
        .lineLimit(1)
        .padding(.horizontal, 16)
    }
}

/// Creates a task linked to the current project and opens it with its title ready to type.
struct NewLinkedTaskButton: View {
    let model: AppModel
    var bordered = false
    @Environment(\.theme) private var theme

    var body: some View {
        Button { Task { await model.newTask() } } label: {
            Label("New linked task", systemImage: "plus")
                .font(.system(size: 12))
                .foregroundStyle(theme.color(bordered ? \.fg : \.muted))
                .padding(.horizontal, bordered ? 12 : 10)
                .frame(height: bordered ? 28 : 30)
                .background(bordered ? theme.color(\.bg) : .clear, in: .rect(cornerRadius: 7))
                .overlay {
                    if bordered { RoundedRectangle(cornerRadius: 7).strokeBorder(theme.color(\.border)) }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
