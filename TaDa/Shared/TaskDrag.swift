// Moving tasks between projects from the lists: task rows drag onto the sidebar's projects, Loose tasks and Today,
// and the project menu opens under a row for ⇧⌘M. A drag or drop on a picked row acts on every picked task.
import SwiftUI
import TaDaCore

extension View {
    /// Makes a task's row draggable, and opens ⇧⌘M's project menu under it when it's the first picked row.
    func taskDrag(_ model: AppModel, path: String) -> some View {
        modifier(TaskDragSource(model: model, path: path))
    }

    /// Takes dropped task rows: a project links them to it, Loose tasks empties their project and Today makes
    /// them due today. Rings the row while a drag is over it.
    func taskDrop(_ model: AppModel, onto target: TaskDropTarget, cornerRadius: CGFloat = 7) -> some View {
        modifier(TaskDropZone(model: model, target: target, cornerRadius: cornerRadius))
    }
}

enum TaskDropTarget {
    case project(Item)
    case loose
    case today
}

private struct TaskDragSource: ViewModifier {
    let model: AppModel
    let path: String
    @State private var anchor = ScreenAnchor()
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .background(ScreenAnchorReader(anchor: anchor))
            .draggable(path) {
                let count = model.multiSelection.contains(path) ? model.moveTargets(for: path).count : 1
                Text(count == 1 ? Item.title(ofPath: path) : "\(count) tasks")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.color(\.strong))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(theme.color(\.surface), in: .rect(cornerRadius: 7))
            }
            .onChange(of: model.moveMenuRequest) { _, request in
                guard let request, !request.onChip, request.anchor == path else { return }
                model.moveMenuRequest = nil
                PropertyPicker.shared.pickProject(of: request.paths.compactMap { model.index[$0] }, model: model,
                                                  anchor: anchor, gap: 4)
            }
    }
}

private struct TaskDropZone: ViewModifier {
    let model: AppModel
    let target: TaskDropTarget
    let cornerRadius: CGFloat
    @State private var isTargeted = false
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .dropDestination(for: String.self) { paths, _ in
                let tasks = paths.first.map { model.moveTargets(for: $0) } ?? []
                guard !tasks.isEmpty else { return }
                Task {
                    switch target {
                    case .project(let project): await model.setProject(project, of: tasks)
                    case .loose: await model.setProject(nil, of: tasks)
                    case .today: await model.makeDueToday(tasks)
                    }
                }
            }
            .onDropSessionUpdated { session in
                switch session.phase {
                case .entering, .active: isTargeted = true
                default: isTargeted = false
                }
            }
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(theme.color(\.accent), lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
    }
}
