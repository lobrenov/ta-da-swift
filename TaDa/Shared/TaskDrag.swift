// Dragging task files: task rows drag as their files, onto the sidebar's projects, areas, Loose tasks and Today or into
// other apps as a drag from Finder would, and the project menu or a calendar opens under a row for ⇧⌘M, ⌘S or ⌘D. A drag on a picked row
// takes every picked task. Other apps get copies: Finder never moves a file out of the folder.
#if os(macOS)
import SwiftUI
import TaDaCore

extension View {
    /// Makes a task's row draggable, and opens ⇧⌘M's project menu, or ⌘S's or ⌘D's calendar, under it when it's
    /// the first picked row.
    func taskDrag(_ model: AppModel, path: String) -> some View {
        modifier(TaskDragSource(model: model, path: path))
    }

    /// Holds the rows `.taskDrag` (or `.draggable(containerItemID:)`, as the sidebar's projects) makes draggable: drags
    /// the picked tasks when a picked row is dragged, else the dragged row's, as copies of their files.
    func taskDragContainer(_ model: AppModel) -> some View {
        dragContainer(for: TaskFile.self, itemID: \.path) { paths in
            paths.compactMap { path in model.vault.map { TaskFile(path: path, url: $0.url(for: path)) } }
        }
        .dragContainerSelection(model.moveTargets())
        .dragConfiguration(DragConfiguration(operationsWithinApp: .init(allowCopy: true),
                                             operationsOutsideApp: .init(allowCopy: true)))
        .dragPreviewsFormation(.stack)
    }

    /// Takes dropped task rows: a project or area files them under it, Loose tasks empties their parent and Today
    /// makes them due today. An area also takes dropped projects. Rings the row while a drag is over it.
    func taskDrop(_ model: AppModel, onto target: TaskDropTarget, cornerRadius: CGFloat = 7) -> some View {
        modifier(TaskDropZone(model: model, target: target, cornerRadius: cornerRadius))
    }
}

/// A dragged task: its file URL is what a drop receives.
struct TaskFile: Transferable {
    let path: String
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.url)
    }
}

enum TaskDropTarget {
    case project(Item)
    case area(Item)
    case loose
    case today
}

private struct TaskDragSource: ViewModifier {
    let model: AppModel
    let path: String
    @State private var anchor = ScreenAnchor()

    func body(content: Content) -> some View {
        content
            .background(ScreenAnchorReader(anchor: anchor))
            .draggable(containerItemID: path)
            .onChange(of: model.propertyMenuRequest) { _, request in
                guard let request, !request.onChip, request.anchor == path else { return }
                model.propertyMenuRequest = nil
                let items = request.paths.compactMap { model.index[$0] }
                switch request.menu {
                case .project: PropertyPicker.shared.pickProject(of: items, model: model, anchor: anchor, gap: 4)
                case .area: PropertyPicker.shared.pickArea(of: items, model: model, anchor: anchor, gap: 4)
                case .date(let kind): PropertyPicker.shared.pickDate(kind, of: items, model: model, anchor: anchor, gap: 4)
                }
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
            .dropDestination(for: URL.self) { urls, _ in
                let paths = urls.compactMap { model.vault?.path(of: $0) }
                let tasks = paths.filter { model.index[$0]?.properties.kind == .task }
                Task {
                    switch target {
                    case .project(let project): await model.setParent(project, of: tasks)
                    case .area(let area):
                        await model.setParent(area, of: paths.filter { [.task, .project].contains(model.index[$0]?.properties.kind) })
                    case .loose: await model.setParent(nil, of: tasks)
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
#endif
