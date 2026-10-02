// The frontmatter as key/value rows. Status and the two planning dates are editable; other keys are read-only.
import SwiftUI
import TaDaCore

struct PropertyTable: View {
    static let taskKeys = ["type", "status", "area", "contexts", "project", "createdDate", "completedDate", "dueDate", "deadline", "repeat"]

    let model: AppModel
    let item: Item
    let keys: [String]
    var keyWidth: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(keys, id: \.self) { key in
                HStack(spacing: 12) {
                    Text(key)
                        .font(.system(size: 11.5, design: .monospaced))
                        .frame(width: keyWidth, alignment: .leading)
                        .modifier(Muted())
                    value(for: key)
                        .font(.system(size: 12.5))
                    Spacer(minLength: 0)
                }
                .frame(height: 28)
                .accessibilityElement(children: .contain)
            }
        }
    }

    @ViewBuilder private func value(for key: String) -> some View {
        let p = item.properties
        switch key {
        case "type": PlainValue(text: p.kind.rawValue)
        case "status": StatusMenu(status: p.status) { status in Task { await model.setStatus(status, in: item.path) } }
        case "area": PlainValue(text: p.area)
        case "contexts": PlainValue(text: p.contexts.isEmpty ? nil : p.contexts.joined(separator: ", "))
        case "project": ProjectLink(model: model, task: item)
        case "createdDate": PlainValue(text: p.createdDate?.description)
        case "completedDate": PlainValue(text: p.completedDate?.description)
        case "dueDate": DateValue(model: model, path: item.path, key: key, date: p.dueDate)
        case "deadline": DateValue(model: model, path: item.path, key: key, date: p.deadline)
        case "repeat": PlainValue(text: p.repeatRule)
        default: EmptyView()
        }
    }
}

private struct Muted: ViewModifier {
    @Environment(\.theme) private var theme
    func body(content: Content) -> some View { content.foregroundStyle(theme.color(\.muted)) }
}

/// A read-only value, or a muted dash when it's missing.
private struct PlainValue: View {
    let text: String?
    @Environment(\.theme) private var theme

    var body: some View {
        Text(text ?? "—")
            .foregroundStyle(theme.color(text == nil ? \.muted : \.fg))
            .lineLimit(1)
            .textSelection(.enabled)
    }
}

/// A plain button that shows a rounded surface on hover, so editable values look clickable.
struct PropertyButtonStyle: ButtonStyle {
    @State private var hovering = false
    @Environment(\.theme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(hovering || configuration.isPressed ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 5))
            .padding(.horizontal, -6)
            .contentShape(.rect)
            .onHover { hovering = $0 }
    }
}

/// The status with its dot; clicking lists the four statuses.
struct StatusMenu: View {
    let status: Status
    let onPick: (Status) -> Void
    @State private var isPicking = false
    @Environment(\.theme) private var theme

    var body: some View {
        Button { isPicking = true } label: {
            HStack(spacing: 7) {
                Circle().fill(theme.statusColor(status)).frame(width: 7, height: 7)
                Text(status.rawValue).foregroundStyle(theme.color(\.fg))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(theme.color(\.muted))
            }
        }
        .buttonStyle(PropertyButtonStyle())
        .accessibilityLabel("Status: \(status.rawValue)")
        .popover(isPresented: $isPicking, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Status.allCases, id: \.self) { option in
                    Button {
                        isPicking = false
                        if option != status { onPick(option) }
                    } label: {
                        HStack(spacing: 8) {
                            Circle().fill(theme.statusColor(option)).frame(width: 7, height: 7)
                            Text(option.rawValue)
                            Spacer(minLength: 16)
                            if option == status { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                        }
                        .frame(width: 150, alignment: .leading)
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(PropertyButtonStyle())
                    .accessibilityAddTraits(option == status ? .isSelected : [])
                }
            }
            .font(.system(size: 12.5))
            .foregroundStyle(theme.color(\.fg))
            .padding(10)
            .background(theme.color(\.bg))
        }
    }
}

/// A date shown as written; clicking opens a calendar with Today and Clear.
private struct DateValue: View {
    let model: AppModel
    let path: String
    let key: String
    let date: LocalDate?
    @State private var isPicking = false
    @Environment(\.theme) private var theme

    var body: some View {
        Button { isPicking = true } label: {
            Text(date?.description ?? "—").foregroundStyle(theme.color(date == nil ? \.muted : \.fg))
        }
        .buttonStyle(PropertyButtonStyle())
        .accessibilityLabel("\(key): \(date?.formatted(.weekdayDayMonthYear) ?? "none")")
        .popover(isPresented: $isPicking, arrowEdge: .bottom) {
            VStack(spacing: 8) {
                DatePicker(key, selection: selection, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                HStack {
                    Button("Clear") {
                        isPicking = false
                        set(nil)
                    }
                    .disabled(date == nil)
                    Spacer()
                    Button("Today") { set(model.today) }
                }
                .controlSize(.small)
            }
            .padding(12)
        }
    }

    private var selection: Binding<Date> {
        Binding { (date ?? model.today).date() } set: { set(LocalDate($0)) }
    }

    private func set(_ new: LocalDate?) {
        guard new != date else { return }
        Task { await model.setProperty(key, to: new.map { .date($0) }, in: path) }
    }
}

/// A task's `project` link: opens the project, or shows the unresolved title muted.
private struct ProjectLink: View {
    let model: AppModel
    let task: Item
    @Environment(\.theme) private var theme

    var body: some View {
        if let link = task.properties.project {
            if let project = model.index.project(of: task) {
                Button("[[\(link.title)]]") { model.open(project.path) }
                    .buttonStyle(PropertyButtonStyle())
                    .foregroundStyle(theme.color(\.link))
                    .help("Open \(project.title)")
            } else {
                Text("[[\(link.title)]]").foregroundStyle(theme.color(\.muted)).strikethrough()
                    .help("No project is called “\(link.title)”")
            }
        } else {
            PlainValue(text: nil)
        }
    }
}
