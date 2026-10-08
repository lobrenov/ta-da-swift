// A file's properties under its title, as the canvas's Properties page draws them: status, project (on a task),
// due date and deadline as chips that open pickers, with a dashed chip for a missing one; then the type and the
// days the file was created and completed in a quiet line. Area, contexts and repeat aren't shown.
import SwiftUI
import AppKit
import TaDaCore

struct PropertyChips: View {
    let model: AppModel
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PropertyChipRow(model: model, item: item)
            QuietLine(model: model, item: item)
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
            if item.properties.kind == .task {
                ProjectPropertyChip(model: model, task: item)
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

/// A task's project with its ring, in `link`; struck through in `muted` when no project has that title.
/// Clicking or ⇧⌘M picks another; ⌘-click opens the project.
private struct ProjectPropertyChip: View {
    let model: AppModel
    let task: Item
    @State private var anchor = ScreenAnchor()
    @Environment(\.theme) private var theme

    var body: some View {
        let link = task.properties.project
        let project = model.index.project(of: task)
        Button {
            if let project, NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                model.open(project.path)
            } else {
                PropertyPicker.shared.pickProject(of: [task], model: model, anchor: anchor)
            }
        } label: {
            if let project {
                HStack(spacing: 7) {
                    ProgressRing(fraction: model.index.progress(of: project).fraction)
                        .foregroundStyle(theme.color(\.accent))
                    Text(project.title)
                }
            } else if let link {
                Text(link.title).strikethrough()
            } else {
                MissingKeyLabel(name: "Project")
            }
        }
        .buttonStyle(PropertyChipStyle(text: project != nil ? \.link : \.muted, isMissing: link == nil,
                                       isOpen: PropertyPicker.shared.isOpen(task.path, "project")))
        .background(ScreenAnchorReader(anchor: anchor))
        .onChange(of: model.propertyMenuRequest) { _, request in
            guard let request, request.menu == .project, request.onChip, request.anchor == task.path else { return }
            model.propertyMenuRequest = nil
            PropertyPicker.shared.pickProject(of: [task], model: model, anchor: anchor)
        }
        .help(project.map { "⌘-click to open \($0.title)" } ?? link.map { "No project is called “\($0.title)”" } ?? "")
        .accessibilityLabel("Project")
        .accessibilityValue(project?.title ?? link.map { "\($0.title), not found" } ?? "None")
        .accessibilityActions {
            if let project {
                Button("Open \(project.title)") { model.open(project.path) }
            }
            ForEach(model.projects.filter { $0.project.path != project?.path }) { other in
                Button(other.project.title) {
                    Task { await model.setProperty("project", to: .link(title: other.project.title), in: task.path) }
                }
            }
            if link != nil {
                Button("No project") { Task { await model.setProperty("project", to: nil, in: task.path) } }
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
        let isDone = p.status == .done
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
        Task { await model.setProperty(kind.key, to: date.map { .date($0) }, in: item.path) }
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

/// The file's type (a project's with its progress) and the days it was created and completed, in `muted`.
private struct QuietLine: View {
    let model: AppModel
    let item: Item
    @Environment(\.theme) private var theme

    var body: some View {
        let p = item.properties
        WrappingHStack(spacing: 14) {
            HStack(spacing: 6) {
                if p.kind == .project {
                    let progress = model.index.progress(of: item)
                    ProgressRing(fraction: progress.fraction)
                        .foregroundStyle(theme.color(\.accent))
                        .scaleEffect(12 / 14)
                        .frame(width: 12, height: 12)
                    Text("Project · \(progress.done) of \(progress.total) tasks done")
                } else {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(theme.color(\.muted), lineWidth: 1.3)
                        .frame(width: 11, height: 11)
                    Text("Task")
                }
            }
            if let created = p.createdDate {
                Text("Created \(created.relativeLabel(today: model.today))")
            }
            if let completed = p.completedDate {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                    Text("Completed \(completed.relativeLabel(today: model.today))")
                }
                .foregroundStyle(theme.color(\.done))
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(theme.color(\.muted))
        .accessibilityElement(children: .combine)
    }
}

/// Lays its views out left to right, `spacing` apart, and starts a new row `spacing` below when one is full.
private struct WrappingHStack: Layout {
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
