// The Logbook beside the document pane: Log Now, the completed files not logged yet (logging tonight, or waiting for
// their project's open tasks), then the logged ones by day and month. A row's box reopens a task, which goes back to
// `tasks/`.
#if os(macOS)
import SwiftUI
import TaDaCore

struct LogbookView: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let groups = LogbookGroup.groups(model.logbook, index: model.index, today: model.today)
        BrowserColumn(model: model, paths: groups.flatMap(\.items).map(\.path), spacing: 20,
                      empty: groups.isEmpty ? empty : nil) {
            header(waiting: groups.filter(\.isWaiting).map(\.items.count).reduce(0, +))
        } content: {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 1) {
                    GroupTitle(title: group.title, note: note(group.kind))
                    ForEach(group.items) { item in
                        LogbookRow(model: model, item: item)
                            .fileMenu(model, path: item.path)
                    }
                }
            }
        }
    }

    private func note(_ kind: LogbookGroup.Kind) -> String? {
        switch kind {
        case .logsTonight: "Still in place · logs tonight"
        case .waitsForOpenTasks: "Still in place · logs once its project's tasks are completed"
        case .logged: nil
        }
    }

    private func header(waiting: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            DomainHeader(.logbook) {
                Button("Log Now") { Task { await model.logNow() } }
                    .buttonStyle(ActionButtonStyle(kind: .primary, height: 28))
                    .disabled(!model.hasFilesToLog)
                    .help("Moves the completed files to \(Vault.logbookFolder)/")
            }
            Text(waiting == 0 ? "Up to date · logs every night at midnight"
                 : "\(waiting) completed, still in place · logs every night at midnight")
                .font(.system(size: 11.5))
                .foregroundStyle(theme.color(\.muted))
        }
    }

    private var empty: EmptyState {
        EmptyState(systemImage: AppModel.Domain.logbook.systemImage, title: "Nothing logged yet",
                   message: "Completed tasks and projects move here every night, into `\(Vault.logbookFolder)/`.")
    }
}

/// A group's name over a rule, with a muted note on the right.
private struct GroupTitle: View {
    let title: String
    let note: String?
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).fontWeight(.semibold).foregroundStyle(theme.color(\.strong))
                Spacer()
                if let note { Text(note).font(.system(size: 11.5)).foregroundStyle(theme.color(\.muted)) }
            }
            .padding(.horizontal, 10)
            Hairline()
        }
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A logged or completed file: a task's box (which reopens it) or a project's full ring, its struck title over its parent,
/// and the day it was completed.
private struct LogbookRow: View {
    let model: AppModel
    let item: Item
    @Environment(\.theme) private var theme

    var body: some View {
        let selected = model.isSelected(item.path)
        HStack(alignment: .top, spacing: 10) {
            if item.properties.kind == .project {
                ProgressRing(fraction: 1)
                    .foregroundStyle(theme.color(item.properties.status == .cancelled ? \.muted : \.done))
                    .padding(.top, 2)
            } else {
                StatusCheckbox(status: item.properties.status, title: item.title) {
                    Task { await model.toggleCompletion(item) }
                }
                .padding(.top, 2)
            }
            Button { model.click(item.path) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    TaskTitle(item: item, selected: selected)
                        .fontWeight(item.properties.kind == .project ? .semibold : .regular)
                    HStack(spacing: 12) {
                        Text(LogbookGroup.meta(item, index: model.index))
                        let subtasks = item.subtasks
                        if subtasks.total > 0 {
                            Chip(systemImage: "checklist", text: "\(subtasks.done)/\(subtasks.total)",
                                 spoken: "\(subtasks.done) of \(subtasks.total) subtasks done")
                        }
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.color(\.muted))
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            Text(LogbookGroup.shortDate(item, today: model.today))
                .font(.system(size: 11.5))
                .foregroundStyle(theme.color(\.muted))
                .padding(.top, 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(selected ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 7))
    }
}
#endif
