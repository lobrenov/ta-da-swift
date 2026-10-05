// Trash: the Ta Da files in `.trash/`. Clicking a row picks it; picked files are restored to `tasks/` and
// `projects/`, and Empty Trash moves everything to the Mac's Trash. A single pane, like the other archive views.
import SwiftUI
import TaDaCore

struct TrashView: View {
    let model: AppModel
    @State private var isConfirmingEmpty = false
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            pathBar
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 14) {
                        DomainHeader(title: "Trash", systemImage: "trash", tint: \.muted) { EmptyView() }
                        buttons
                        if isConfirmingEmpty, !model.trash.isEmpty { confirmation }
                        if let note = model.trashNote { toast(note) }
                    }
                    if model.trash.isEmpty {
                        EmptyState(systemImage: "trash", title: "Trash is empty", message: "Deleted tasks and projects wait here.")
                            .padding(.top, 40)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(model.trash) { row($0) }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Deleted files")
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 64)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: model.trash.isEmpty) { if model.trash.isEmpty { isConfirmingEmpty = false } }
    }

    /// "Ta Da / .trash", as the document pane shows a file's place.
    private var pathBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder").font(.system(size: 12))
            Text(model.vault?.root.lastPathComponent ?? "")
            Text("/")
            Text(Vault.trashFolder).foregroundStyle(theme.color(\.fg))
            Spacer(minLength: 12)
            Text("Files stay here until the trash is emptied").font(.system(size: 12))
        }
        .font(.system(size: 11.5, design: .monospaced))
        .foregroundStyle(theme.color(\.muted))
        .lineLimit(1)
        .padding(.horizontal, 20)
        .frame(height: 46)
    }

    private var buttons: some View {
        let picked = model.trashSelection.count
        let isEmpty = model.trash.isEmpty
        return HStack(spacing: 10) {
            Button {
                isConfirmingEmpty = true
                model.trashNote = nil
            } label: {
                Text("Empty Trash")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(theme.color(isEmpty ? \.muted : \.bg))
                    .padding(.horizontal, 16)
                    .frame(height: 30)
                    .background(theme.color(isEmpty ? \.surface : \.accent), in: .rect(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .disabled(isEmpty)
            Button {
                Task { await model.restore(model.trashSelection) }
            } label: {
                Label(picked == 0 ? "Restore Items" : picked == 1 ? "Restore 1 Item" : "Restore \(picked) Items",
                      systemImage: "arrow.counterclockwise")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.color(picked == 0 ? \.muted : \.strong))
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.color(\.border)))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(picked == 0)
            .help("Restore (⌘⌫)")
            if !isEmpty {
                Text(picked == 0 ? "Select files to restore them" : "Restored files return to tasks/ and projects/")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.color(\.muted))
            }
        }
    }

    private var confirmation: some View {
        let count = model.trash.count
        return HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(theme.color(\.deadline))
                .accessibilityHidden(true)
            Text("Move \(count) \(count == 1 ? "file" : "files") to the Mac’s Trash?")
                .foregroundStyle(theme.color(\.fg))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { isConfirmingEmpty = false } label: {
                Text("Cancel")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.color(\.fg))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.color(\.border)))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            Button {
                isConfirmingEmpty = false
                Task { await model.emptyTrash() }
            } label: {
                Text("Empty Trash")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.color(\.bg))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(theme.color(\.deadline), in: .rect(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(theme.color(\.code), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.color(\.deadline)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Empty Trash")
    }

    private func toast(_ note: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.color(\.done))
                .accessibilityHidden(true)
            Text(note).foregroundStyle(theme.color(\.fg))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.color(\.code), in: .rect(cornerRadius: 10))
    }

    private func row(_ entry: TrashedItem) -> some View {
        let item = entry.item
        let isProject = item.properties.kind == .project
        let isPicked = model.trashSelection.contains(entry.id)
        let tasks = isProject ? TrashedItem.tasks(of: item, in: model.trash) : []
        return Button {
            if isPicked { model.trashSelection.remove(entry.id) } else { model.trashSelection.insert(entry.id) }
            model.trashNote = nil
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if isProject {
                    let done = tasks.count { $0.item.properties.status == .done }
                    ProgressRing(fraction: tasks.isEmpty ? 0 : Double(done) / Double(tasks.count))
                        .foregroundStyle(theme.color(\.accent))
                        .padding(.top, 2)
                } else {
                    let box = StatusCheckbox.box(for: item.properties.status, theme: theme)
                    InlineCheckboxView(marker: box.marker, tint: box.tint, background: theme.bg)
                        .frame(width: 16, height: 16)
                        .padding(.top, 2)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(.system(size: 13.5, weight: isProject ? .semibold : .regular))
                            .foregroundStyle(theme.color(isPicked ? \.strong : \.fg))
                        if !tasks.isEmpty {
                            Text("\(tasks.count)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(theme.color(\.muted))
                                .padding(.horizontal, 5)
                                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(theme.color(\.border)))
                                .accessibilityLabel("\(tasks.count) tasks")
                        }
                    }
                    Text(isProject ? item.properties.area ?? "Project" : item.properties.project?.title ?? "Loose task")
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.color(\.muted))
                }
                .lineLimit(1)
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 1) {
                    if let deleted = entry.deleted {
                        Text("Deleted \(LocalDate(deleted).formatted(.weekdayDayMonth))")
                    }
                    Text("from \(isProject ? Vault.projectFolder : Vault.taskFolder)/")
                        .font(.system(size: 11, design: .monospaced))
                }
                .font(.system(size: 11.5))
                .foregroundStyle(theme.color(\.muted))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isPicked ? theme.color(\.surface) : .clear, in: .rect(cornerRadius: 7))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
        .fileMenu(model, path: entry.id)
    }
}
