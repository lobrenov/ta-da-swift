// A file's properties under its title, as the canvas's Properties page draws them: status, the parent (a task's
// project or area, a project's area), due date and deadline as chips that open pickers, with a dashed chip for a
// missing one; the Tags row; then the type, a task's area through its project, and the days the file was created and
// completed in a quiet line. An area has the quiet line, then the Tags row. Repeat isn't shown.
import SwiftUI
import TaDaCore
#if os(macOS)
import AppKit

struct PropertyChips: View {
    let model: AppModel
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch item.properties.kind {
            case .task, .project:
                PropertyChipRow(model: model, item: item)
                TagChipRow(model: model, item: item)
                QuietLine(model: model, item: item)
            case .note:
                TagChipRow(model: model, item: item)
                QuietLine(model: model, item: item)
            case .area:
                QuietLine(model: model, item: item)
                TagChipRow(model: model, item: item)
            }
        }
    }
}

/// The chips alone, wrapping, with `trailing` after the last one: the project browser's header adds the subtasks.
struct PropertyChipRow<Trailing: View>: View {
    let model: AppModel
    let item: Item
    @ViewBuilder var trailing: Trailing

    var body: some View {
        WrappingHStack(spacing: 6) {
            StatusPropertyChip(model: model, item: item)
            switch item.properties.kind {
            case .task: ParentPropertyChip(model: model, task: item)
            case .project: AreaPropertyChip(model: model, project: item)
            case .area, .note: EmptyView()
            }
            DatePropertyChip(kind: .due, model: model, item: item)
            DatePropertyChip(kind: .deadline, model: model, item: item)
            trailing
        }
        .font(.system(size: 12.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Properties")
        .onChange(of: item.path) { PropertyPicker.shared.close() }
        .onDisappear { PropertyPicker.shared.close(path: item.path) }
    }
}

extension PropertyChipRow where Trailing == EmptyView {
    init(model: AppModel, item: Item) {
        self.init(model: model, item: item) { EmptyView() }
    }
}

/// The status's dot and name, and a chevron.
private struct StatusPropertyChip: View {
    let model: AppModel
    let item: Item
    @State private var anchor = ScreenAnchor()
    @Environment(\.theme) private var theme

    var body: some View {
        let status = item.properties.status
        let isOpen = PropertyPicker.shared.isOpen(item.path, "status")
        Button { PropertyPicker.shared.pickStatus(of: item, model: model, anchor: anchor) } label: {
            HStack(spacing: 7) {
                Circle().fill(theme.statusColor(status)).frame(width: 7, height: 7)
                Text(status.rawValue)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.color(isOpen ? \.fg : \.muted))
            }
        }
        .buttonStyle(PropertyChipStyle(isOpen: isOpen, leading: 11, trailing: 9))
        .background(ScreenAnchorReader(anchor: anchor))
        .accessibilityLabel("Status")
        .accessibilityValue(status.rawValue)
        .accessibilityActions {
            ForEach(StatusChoice.order.filter { $0 != status }, id: \.self) { option in
                Button(option.rawValue) { Task { await model.setStatus(option, in: item.path) } }
            }
        }
    }
}

/// A task's project with its ring, or its area with its cube, in `link`; struck through in `muted` when no file has
/// that title. Clicking or ⇧⌘M opens the move menu; ⌘-click opens the project or area.
private struct ParentPropertyChip: View {
    let model: AppModel
    let task: Item
    @State private var anchor = ScreenAnchor()
    @Environment(\.theme) private var theme

    var body: some View {
        let p = task.properties
        let parent = model.index.parent(of: task)
        let link = p.project ?? p.area
        let isArea = parent.map { $0.properties.kind == .area } ?? (p.project == nil && p.area != nil)
        Button {
            if let parent, NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                model.open(parent.path)
            } else {
                PropertyPicker.shared.pickProject(of: [task], model: model, anchor: anchor)
            }
        } label: {
            if let parent {
                HStack(spacing: isArea ? 6 : 7) {
                    if isArea {
                        AreaIcon(size: 13)
                    } else {
                        ProgressRing(fraction: model.index.progress(of: parent).fraction)
                            .foregroundStyle(theme.color(\.accent))
                    }
                    Text(parent.title)
                }
            } else if let link {
                HStack(spacing: 6) {
                    if isArea { AreaIcon(size: 13, tint: \.muted) }
                    Text(link.title).strikethrough()
                }
            } else {
                MissingKeyLabel(name: "Project")
            }
        }
        .buttonStyle(PropertyChipStyle(text: parent != nil ? \.link : \.muted, isMissing: link == nil,
                                       isOpen: PropertyPicker.shared.isOpen(task.path, "project")))
        .background(ScreenAnchorReader(anchor: anchor))
        .onChange(of: model.propertyMenuRequest) { _, request in
            guard let request, request.menu == .project, request.onChip, request.anchor == task.path else { return }
            model.propertyMenuRequest = nil
            PropertyPicker.shared.pickProject(of: [task], model: model, anchor: anchor)
        }
        .help(parent.map { "⌘-click to open \($0.title)" }
            ?? link.map { "No \(isArea ? "area" : "project") is called “\($0.title)”" } ?? "")
        .accessibilityLabel(isArea ? "Area" : "Project")
        .accessibilityValue(parent?.title ?? link.map { "\($0.title), not found" } ?? "None")
        .accessibilityActions {
            if let parent {
                Button("Open \(parent.title)") { model.open(parent.path) }
            }
            ForEach(model.projects.filter { $0.project.path != parent?.path }) { other in
                Button(other.project.title) { Task { await model.setParent(other.project, of: [task.path]) } }
            }
            ForEach(model.areas.filter { $0.area.path != parent?.path }) { other in
                Button(other.area.title) { Task { await model.setParent(other.area, of: [task.path]) } }
            }
            if link != nil {
                Button("Loose tasks") { Task { await model.setParent(nil, of: [task.path]) } }
            }
        }
    }
}

/// A project's area with its cube, in `link`, and a chevron; struck through in `muted` when no area has that title.
/// Clicking opens the area menu; ⌘-click opens the area.
private struct AreaPropertyChip: View {
    let model: AppModel
    let project: Item
    @State private var anchor = ScreenAnchor()
    @Environment(\.theme) private var theme

    var body: some View {
        let link = project.properties.area
        let area = model.index.area(of: project)
        let isOpen = PropertyPicker.shared.isOpen(project.path, "area")
        Button {
            if let area, NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                model.open(area.path)
            } else {
                PropertyPicker.shared.pickArea(of: [project], model: model, anchor: anchor)
            }
        } label: {
            if let link {
                HStack(spacing: 6) {
                    AreaIcon(size: 13, tint: area != nil ? \.doing : \.muted)
                    Text(link.title).strikethrough(area == nil)
                    if area != nil {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.color(isOpen ? \.fg : \.muted))
                    }
                }
            } else {
                MissingKeyLabel(name: "Area")
            }
        }
        .buttonStyle(PropertyChipStyle(text: area != nil ? \.link : \.muted, isMissing: link == nil, isOpen: isOpen,
                                       trailing: area != nil ? 9 : 11))
        .background(ScreenAnchorReader(anchor: anchor))
        .onChange(of: model.propertyMenuRequest) { _, request in
            guard let request, request.menu == .area, request.onChip, request.anchor == project.path else { return }
            model.propertyMenuRequest = nil
            PropertyPicker.shared.pickArea(of: [project], model: model, anchor: anchor)
        }
        .help(area.map { "⌘-click to open \($0.title)" } ?? link.map { "No area is called “\($0.title)”" } ?? "")
        .accessibilityLabel("Area")
        .accessibilityValue(area?.title ?? link.map { "\($0.title), not found" } ?? "None")
        .accessibilityActions {
            if let area {
                Button("Open \(area.title)") { model.open(area.path) }
            }
            ForEach(model.areas.filter { $0.area.path != area?.path }) { other in
                Button(other.area.title) { Task { await model.setParent(other.area, of: [project.path]) } }
            }
            if link != nil {
                Button("No area") { Task { await model.setParent(nil, of: [project.path]) } }
            }
        }
    }
}

/// A due date or deadline: its icon in the key's colour and the day, red once it has passed and all `muted`
/// once the file is done. Clicking, or ⌘S (due date) or ⌘D (deadline), opens its calendar.
private struct DatePropertyChip: View {
    let kind: AgendaEntry.Kind
    let model: AppModel
    let item: Item
    @State private var anchor = ScreenAnchor()
    @Environment(\.theme) private var theme

    var body: some View {
        let p = item.properties
        let date = kind == .due ? p.dueDate : p.deadline
        let isDone = p.status.isClosed
        let isOverdue = !isDone && date.map { $0 < model.today } == true
        Button { PropertyPicker.shared.pickDate(kind, of: [item], model: model, anchor: anchor) } label: {
            if let date {
                HStack(spacing: 6) {
                    Image(systemName: kind.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.color(isDone ? \.muted : kind.tint))
                    Text("\(kind.label) \(date.relativeLabel(today: model.today))")
                }
            } else {
                MissingKeyLabel(name: kind.name)
            }
        }
        .buttonStyle(PropertyChipStyle(text: isDone ? \.muted : isOverdue ? \.deadline : \.fg, isMissing: date == nil,
                                       isOpen: PropertyPicker.shared.isOpen(item.path, kind.key)))
        .background(ScreenAnchorReader(anchor: anchor))
        .onChange(of: model.propertyMenuRequest) { _, request in
            guard let request, request.menu == .date(kind), request.onChip, request.anchor == item.path else { return }
            model.propertyMenuRequest = nil
            PropertyPicker.shared.pickDate(kind, of: [item], model: model, anchor: anchor)
        }
        .accessibilityLabel(kind.name)
        .accessibilityValue(date.map { $0.formatted(.weekdayDayMonthYear) + (isOverdue ? ", overdue" : "") } ?? "None")
        .accessibilityActions {
            Button("Today") { set(model.today) }
            Button("Tomorrow") { set(model.today.adding(days: 1)) }
            Button("Next week") { set(CalendarPickerModel.nextWeek(after: model.today)) }
            if date != nil {
                Button("Clear") { set(nil) }
            }
        }
    }

    private func set(_ date: LocalDate?) {
        Task { await model.setDate(kind, to: date, of: [item.path]) }
    }
}

/// A missing key's chip: a plus and the key's name.
private struct MissingKeyLabel: View {
    let name: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "plus").font(.system(size: 9, weight: .bold))
            Text(name)
        }
    }
}

/// A chip's capsule: `code` inside a `border` outline, or a dashed outline for a missing key, and `surface` under
/// the pointer. While its picker is open it's `surface` with an `accent` ring, and its text `strong`.
private struct PropertyChipStyle: ButtonStyle {
    var text: KeyPath<Theme, NSColor> = \.fg
    var isMissing = false
    let isOpen: Bool
    var leading: CGFloat = 9
    var trailing: CGFloat = 11

    func makeBody(configuration: Configuration) -> some View {
        PropertyChipBody(label: configuration.label, isPressed: configuration.isPressed, style: self)
    }
}

private struct PropertyChipBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let style: PropertyChipStyle
    @State private var hovering = false
    @Environment(\.theme) private var theme

    var body: some View {
        let lit = hovering || isPressed || style.isOpen
        label
            .foregroundStyle(theme.color(style.isOpen ? \.strong : style.isMissing ? (lit ? \.fg : \.muted) : style.text))
            .lineLimit(1)
            .padding(.leading, style.leading)
            .padding(.trailing, style.trailing)
            .frame(height: 26)
            .background(lit ? theme.color(\.surface) : style.isMissing ? .clear : theme.color(\.code), in: .capsule)
            .overlay {
                if style.isMissing, !style.isOpen {
                    Capsule().strokeBorder(theme.color(lit ? \.muted : \.surface), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                } else {
                    Capsule().strokeBorder(theme.color(lit ? \.surface : \.border))
                }
            }
            .overlay {
                if style.isOpen {
                    Capsule().strokeBorder(theme.color(\.accent), lineWidth: 2).padding(-2)
                }
            }
            .contentShape(.capsule)
            .onHover { hovering = $0 }
    }
}

/// The file's type (a project's with its progress, an area's with its counts, a note's as the note menu, then its folder
/// and subtasks), a task's area through its project, the days it was created (a note without `createdDate`: last
/// edited) and completed, and the files that link here (a menu of them), in `muted`.
private struct QuietLine: View {
    let model: AppModel
    let item: Item
    @Environment(\.theme) private var theme

    var body: some View {
        let p = item.properties
        WrappingHStack(spacing: 14) {
            HStack(spacing: 6) {
                switch p.kind {
                case .project:
                    let progress = model.index.progress(of: item)
                    ProgressRing(fraction: progress.fraction)
                        .foregroundStyle(theme.color(\.accent))
                        .scaleEffect(12 / 14)
                        .frame(width: 12, height: 12)
                    Text("Project · \(progress.done) of \(progress.total) tasks done")
                case .area:
                    AreaIcon(size: 12)
                    Text("Area · ^[\(model.index.projects(in: item).count) project](inflect: true) · ^[\(model.index.tasks(in: item).count) task](inflect: true)")
                case .task:
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(theme.color(\.muted), lineWidth: 1.3)
                        .frame(width: 11, height: 11)
                    Text("Task")
                case .note:
                    NoteMenuButton(model: model, path: item.path)
                }
            }
            if p.kind == .note {
                let folder = Vault.folder(of: item.path)
                HStack(spacing: 4) {
                    Image(systemName: folder.isEmpty ? "tray" : "folder").font(.system(size: 10))
                    Text(folder.isEmpty ? "Loose" : folder)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("In \(folder.isEmpty ? "Loose" : folder)")
                let subtasks = item.subtasks
                if subtasks.total > 0 {
                    Chip(systemImage: "checklist", text: "\(subtasks.done)/\(subtasks.total)",
                         spoken: "\(subtasks.done) of \(subtasks.total) subtasks done")
                }
            }
            if let created = p.createdDate {
                Text("Created \(created.relativeLabel(today: model.today))")
            } else if p.kind == .note, let document = model.document, document.path == item.path, let modified = document.modified {
                Text("Edited \(LocalDate(modified).relativeLabel(today: model.today))")
            }
            if p.kind == .task, p.project != nil, let area = model.index.area(of: item) {
                HStack(spacing: 6) {
                    Text("in")
                    AreaIcon(size: 12)
                    Text(area.title)
                }
            }
            if let completed = p.completedDate {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                    Text("Completed \(completed.relativeLabel(today: model.today))")
                }
                .foregroundStyle(theme.color(\.done))
            }
            let backlinks = model.index.backlinks(to: item)
            if !backlinks.isEmpty {
                Menu(backlinks.count == 1 ? "1 backlink" : "\(backlinks.count) backlinks") {
                    ForEach(backlinks) { link in
                        Button(link.title) { model.openLink(to: link.path) }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(theme.color(\.muted))
        .accessibilityElement(children: .contain)
    }
}

/// Note ▾: the note's page icon and type, opening the note menu under it.
private struct NoteMenuButton: View {
    let model: AppModel
    let path: String
    @State private var anchor = ScreenAnchor()
    @State private var hovering = false
    @State private var isOpen = false
    /// When the menu last closed; a click that closed it doesn't open it again.
    @State private var closed = Date.distantPast
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 5) {
                NoteIcon(size: 12)
                Text("Note")
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background(hovering || isOpen ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 5))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -6)
        .background(ScreenAnchorReader(anchor: anchor))
        .onHover { hovering = $0 }
        .accessibilityLabel("Note menu")
        .help("Convert, reveal or delete this note")
    }

    private func toggle() {
        guard !isOpen, Date().timeIntervalSince(closed) > 0.3, let window = anchor.window else { return }
        let rect = anchor.rect
        let point = CGPoint(x: rect.minX, y: rect.minY - 2)
        let actions = FileMenuAction.noteActions(for: path, model: model, onRow: false, at: point, in: window)
        FileMenu.shared.show(actions, at: point, in: window, theme: model.theme) {
            isOpen = false
            closed = Date()
        }
        isOpen = true
    }
}

#endif

/// Lays its views out left to right, `spacing` apart, and starts a new row `spacing` below when one is full.
struct WrappingHStack: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(of: subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0,
                      height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(of: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(of subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !row.indices.isEmpty, row.width + spacing + size.width > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
